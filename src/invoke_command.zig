//! `mylang invoke`: call one ordinary export through the native runtime.
//!
//! The command reuses the native test runner's machinery rather than growing a
//! second one: the same checked schema, the same copied-value codec, the same
//! isolated bounded child, and the same QBE artifacts. What it adds is the part
//! a *caller* needs — a selector that names an export instead of a test, the
//! eligibility question a checked signature does not answer, and one
//! `native-invocation-v1` object that keeps a returned `Err` distinct from a
//! trap, a timeout and a bad request.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const snapshot = @import("native_test_snapshot.zig");
const sessions = @import("native_test_session.zig");
const execute = @import("native_test_execute.zig");
const wire = @import("native_test_wire.zig");
const budget = @import("memory_budget");

const Value = std.json.Value;
const stdout = std.Io.File.stdout();
const stderr = std.Io.File.stderr();

/// Command-line, request and eligibility failures an invoke run reports.
pub const Error = sessions.Error || error{ InvalidInvokeArguments, InvalidRequest };

/// Budget used when `--timeout-ms` is absent, matching one native test call.
const default_timeout_ms = 60000;
/// Largest response the guest may hand back, shared with the test runner.
const depth_limit = 64;
/// The response version every answer carries.
const version = "native-invocation-v1";
/// The verdict a caller reads when the target is not invocable.
const status_rejected = "rejected";
/// The verdict a caller reads when the request, not the target, was wrong.
const status_invalid_request = "invalid-request";
/// The schema key holding one declaration's name.
const name_key = "name";
/// `--input=FILE` and its space-separated spelling.
const input_prefix = "--input=";
/// The capability type the adapter injects rather than the caller granting.
const stream_cap = "stream_cap";

/// The entry, the export to call and how the caller asked for it.
const Target = struct {
    source: []const u8 = "",
    function: []const u8 = "",
    describe: bool = false,
    input: ?[]const u8 = null,
};

/// Native toolchain, build mode and cache selection.
const Tools = struct {
    cache: []const u8 = ".mylang-cache/invoke",
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
    mode: []const u8 = "Debug",
    no_cache: bool = false,
    gc_stress: bool = false,
};

/// How to run one `mylang invoke`.
pub const Invocation = struct {
    target: Target = .{},
    limits: execute.Limits = .{ .timeout_ms = default_timeout_ms },
    tools: Tools = .{},
};

/// Native invocation requires no Python interpreter.
pub const usage = "usage: mylang invoke <entry.my> --function 'module::name' (--describe | --input=FILE)\n" ++
    "  --describe  report the checked contract, wire support, effects, capabilities,\n" ++
    "              eligibility and limits without executing any guest code\n" ++
    "  --input=FILE  call the export once with a JSON object of named arguments\n" ++
    "  --format=json (the only format today)\n" ++
    "  --cache-dir DIR --no-cache --qbe PATH --zig PATH --mode Debug|ReleaseFast\n" ++
    "  --max-steps N --max-frames N --max-calls N --timeout-ms N\n" ++
    "  --max-memory BYTES  per-call byte ceiling (K/M/G suffixes; default 512M)\n" ++
    "  --gc-stress  run the call under the runtime's stress collector\n" ++
    "exit: 0 completed call (including a returned Result.Err) or a description,\n" ++
    "      1 the project did not check, or the call trapped or ran out of budget,\n" ++
    "      2 a usage, target, request or setup failure\n";

/// A flag whose value is the next argument, so both `--flag=value` and the
/// `--flag value` spelling the documented usage writes are accepted.
const Pending = enum { none, function, input, cache, qbe, zig, mode, steps, frames, calls, timeout, memory };

const Parsed = struct { options: Invocation, pending: Pending = .none };

/// Every value-taking flag, in one table, so the two accepted spellings cannot
/// drift apart: `--flag=value` and `--flag value` are both read here, and the
/// usage text that advertises the spaced form is therefore true.
const value_flags = [_]struct { name: []const u8, field: Pending }{
    .{ .name = "--function", .field = .function },
    .{ .name = "--input", .field = .input },
    .{ .name = "--cache-dir", .field = .cache },
    .{ .name = "--qbe", .field = .qbe },
    .{ .name = "--zig", .field = .zig },
    .{ .name = "--mode", .field = .mode },
    .{ .name = "--max-steps", .field = .steps },
    .{ .name = "--max-frames", .field = .frames },
    .{ .name = "--max-calls", .field = .calls },
    .{ .name = "--timeout-ms", .field = .timeout },
    .{ .name = "--max-memory", .field = .memory },
};

/// Parse one `mylang invoke` command line. A repeated flag, a value-less
/// `--flag=` or a missing selector is a usage error rather than a default.
pub fn parse(args: []const []const u8) error{InvalidInvokeArguments}!Invocation {
    var parsed: Parsed = .{ .options = .{} };
    for (args) |arg| {
        if (parsed.pending != .none) {
            try assign(&parsed.options, parsed.pending, arg);
            parsed.pending = .none;
            continue;
        }
        if (std.mem.eql(u8, arg, "--describe")) {
            if (parsed.options.target.describe) return error.InvalidInvokeArguments;
            parsed.options.target.describe = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-cache")) {
            if (parsed.options.tools.no_cache) return error.InvalidInvokeArguments;
            parsed.options.tools.no_cache = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gc-stress")) {
            if (parsed.options.tools.gc_stress) return error.InvalidInvokeArguments;
            parsed.options.tools.gc_stress = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--format=")) {
            if (!std.mem.eql(u8, arg["--format=".len..], "json")) return error.InvalidInvokeArguments;
            continue;
        }
        if (try valueFlag(arg, &parsed)) continue;
        if (std.mem.startsWith(u8, arg, "--") or parsed.options.target.source.len != 0) return error.InvalidInvokeArguments;
        parsed.options.target.source = arg;
    }
    if (parsed.pending != .none) return error.InvalidInvokeArguments;
    if (parsed.options.target.source.len == 0 or parsed.options.target.function.len == 0) return error.InvalidInvokeArguments;
    if (parsed.options.target.describe == (parsed.options.target.input != null)) return error.InvalidInvokeArguments;
    return parsed.options;
}

/// Read one value-taking flag in either spelling. An exact flag name arms the
/// next argument; a `--flag=value` form assigns immediately. Anything else is
/// left for the caller's remaining branches.
fn valueFlag(arg: []const u8, parsed: *Parsed) error{InvalidInvokeArguments}!bool {
    for (value_flags) |entry| {
        if (std.mem.eql(u8, arg, entry.name)) {
            parsed.pending = entry.field;
            return true;
        }
        if (std.mem.startsWith(u8, arg, entry.name) and arg.len > entry.name.len and arg[entry.name.len] == '=') {
            if (arg.len == entry.name.len + 1) return error.InvalidInvokeArguments;
            try assign(&parsed.options, entry.field, arg[entry.name.len + 1 ..]);
            return true;
        }
    }
    return false;
}

/// Apply one flag's value. Numbers are parsed here so a malformed bound is a
/// usage error before any project is read; zero is not a bound.
fn assign(target: *Invocation, field: Pending, text: []const u8) error{InvalidInvokeArguments}!void {
    if (text.len == 0) return error.InvalidInvokeArguments;
    if (field == .function) {
        if (target.target.function.len != 0) return error.InvalidInvokeArguments;
        target.target.function = text;
        return;
    }
    if (field == .input) {
        if (target.target.input != null) return error.InvalidInvokeArguments;
        target.target.input = text;
        return;
    }
    switch (field) {
        .none => return error.InvalidInvokeArguments,
        .function, .input => unreachable,
        .cache => target.tools.cache = text,
        .qbe => target.tools.qbe = text,
        .zig => target.tools.zig = text,
        .mode => target.tools.mode = text,
        .steps => target.limits.max_steps = try positive(text),
        .frames => target.limits.max_frames = try positive(text),
        .calls => target.limits.max_calls = try positive(text),
        .timeout => target.limits.timeout_ms = std.math.cast(u32, try positive(text)) orelse return error.InvalidInvokeArguments,
        .memory => target.limits.max_memory = try positive(text),
    }
}

fn positive(text: []const u8) error{InvalidInvokeArguments}!u64 {
    const parsed = std.fmt.parseInt(u64, text, 10) catch return error.InvalidInvokeArguments;
    if (parsed == 0) return error.InvalidInvokeArguments;
    return parsed;
}

/// Run one `mylang invoke`. A usage error prints the usage and exits 2; every
/// other path publishes exactly one object on stdout.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try stdout.writeStreamingAll(process.io, usage);
        return 0;
    }
    var opts = parse(args) catch {
        try stderr.writeStreamingAll(process.io, usage);
        return 2;
    };
    var context = try fs.Context.init(process.arena.allocator(), process.io, process.environ_map);
    defer context.deinit();
    opts.limits.max_memory = budget.resolve(opts.limits.max_memory, context.environ, budget.variable, budget.test_default) catch {
        try stderr.writeStreamingAll(process.io, usage);
        return 2;
    };
    // A request file that cannot be read is a request failure, so it is detected
    // before the project is checked: a caller who mistyped a path should not pay
    // for a build to learn it.
    if (opts.target.input) |path| {
        if (!context.exists(path)) return refuse(context, opts, Identities.unknown, status_invalid_request, "the request file cannot be read", 2);
    }
    var session = try sessions.Session.init(context, .{
        .source = opts.target.source,
        .cache = opts.tools.cache,
        .qbe = opts.tools.qbe,
        .zig = opts.tools.zig,
        .mode = opts.tools.mode,
        .limits = opts.limits,
        .flags = .{ .no_cache = opts.tools.no_cache, .gc_stress = opts.tools.gc_stress },
    });
    defer context.remove(session.temporary);
    // A library entry needs no dummy `main`: the snapshot supplies a synthetic
    // one, exactly as `mylang test` does.
    const prepared = try snapshot.withTestEntry(context, session.source);
    const captured = try snapshot.materialize(context, prepared, try context.temporary(session.temporary));
    var project = session.facts(captured.entry_path) catch |err| switch (err) {
        error.SourceRejected => return refuse(context, opts, Identities.unknown, "source-rejected", "the project did not check", 1),
        error.ProjectConfigurationFailed, error.ProjectPolicyRejected => return 2,
        else => return err,
    };
    const schema = project.schema;
    const identities = try identitySet(context, &session, captured, schema);
    const function = select(schema, opts.target.function) catch |err| switch (err) {
        error.UnknownFunction => return refuse(context, opts, identities, status_rejected, "no exported function of this project has that qualified name", 2),
        error.GenericTemplate => return refuse(context, opts, identities, status_rejected, "that name is a generic template with no checked instantiation; add a concrete wrapper and invoke that", 2),
    };
    const eligibility = try evaluate(context.allocator, schema, function);
    if (opts.target.describe) {
        const description = try describe(context.allocator, function, eligibility);
        try publish(context, DescribeResponse{
            .status = "ok",
            .function = v.text(v.get(function, name_key)),
            .identities = identities,
            .limits = limitSet(opts.limits),
            .describe = description,
        });
        return 0;
    }
    if (eligibility.unsupported) |stop| {
        return refuse(context, opts, identities, status_rejected, try std.fmt.allocPrint(context.allocator, "the type at {s} cannot cross the invocation boundary: {s}", .{ stop.path, stop.detail }), 2);
    }
    if (eligibility.capabilities.len != 0) {
        return refuse(context, opts, identities, status_rejected, try std.fmt.allocPrint(context.allocator, "that export needs external authority this version does not grant: {s}", .{eligibility.capabilities[0]}), 2);
    }
    var request = readRequest(context, opts) catch |err| switch (err) {
        error.InvalidRequest => return refuse(context, opts, identities, status_invalid_request, "the request file is not a JSON object of named arguments", 2),
        else => return err,
    };
    defer request.deinit();
    // Arguments are validated against the checked signature before any child is
    // started, so a malformed request never reaches guest code.
    var codec: wire.Codec = .{ .allocator = context.allocator, .types = v.array(v.get(schema, "types")) };
    defer codec.deinit();
    codec.arguments(function, request.value) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return refuse(context, opts, identities, status_invalid_request, argumentFailure(err), 2),
    };
    const executor = try session.executor(&project, "");
    const outcome = try executor.execute(function, request.value, opts.limits);
    const verdict = classify(outcome.status, outcome.diagnostics);
    try publish(context, OutcomeResponse{
        .status = verdict.status,
        .function = v.text(v.get(function, name_key)),
        .identities = identities,
        .limits = limitSet(opts.limits),
        .outcome = .{
            .status = callStatus(verdict.status),
            .value = outcome.actual,
            .diagnostics = outcome.diagnostics,
            .output = outcome.output,
            .steps = outcome.steps,
        },
        .reason = verdict.reason,
    });
    return verdict.exit_code;
}

/// The outcome's own word for a completed call. The top-level verdict says
/// `ok`; the outcome says what the call did, so a consumer that reads only the
/// outcome never has to interpret a success as a missing failure.
fn callStatus(verdict: []const u8) []const u8 {
    return if (std.mem.eql(u8, verdict, "ok")) "returned" else verdict;
}

/// How one child-call status maps onto the caller's verdict.
const Verdict = struct { status: []const u8, exit_code: u8, reason: ?[]const u8 = null };

/// A returned value is a completed call whatever it carries, so a language
/// `Result.Err` stays a typed result at exit 0. Everything else is a runtime
/// failure of a different kind, and the diagnostics name it. The executor
/// reports an expired deadline as a child failure, so the deadline is recovered
/// here from the error the child process raised rather than reported as a host
/// problem the caller could do nothing about.
fn classify(status: []const u8, diagnostics: []const u8) Verdict {
    if (std.mem.eql(u8, status, "value")) return .{ .status = "ok", .exit_code = 0 };
    if (std.mem.eql(u8, status, "trap")) return .{ .status = "trap", .exit_code = 1, .reason = "the call trapped" };
    if (std.mem.indexOf(u8, diagnostics, "Timeout") != null) {
        return .{ .status = "timeout", .exit_code = 1, .reason = "the call exceeded its wall-clock budget" };
    }
    return .{ .status = "infrastructure-failure", .exit_code = 2, .reason = "the isolated child failed to run the call" };
}

/// What a rejected run publishes: the selector, the reason, and no outcome. A
/// refusal that never reached the guest still names the limits it would have
/// used, so a caller can see the budget the request was judged against.
fn refuse(context: fs.Context, opts: Invocation, identities: Identities, status: []const u8, reason: []const u8, code: u8) !u8 {
    try publish(context, RefusedResponse{
        .status = status,
        .function = opts.target.function,
        .identities = identities,
        .limits = limitSet(opts.limits),
        .reason = reason,
    });
    return code;
}

fn publish(context: fs.Context, value: anytype) !void {
    const bytes = try std.json.Stringify.valueAlloc(context.allocator, value, .{});
    defer context.allocator.free(bytes);
    try stdout.writeStreamingAll(context.io, bytes);
    try stdout.writeStreamingAll(context.io, "\n");
}

fn readRequest(context: fs.Context, opts: Invocation) Error!std.json.Parsed(Value) {
    return parseRequest(context.allocator, try context.read(opts.target.input.?));
}

/// Parse one request document into the object of named arguments the codec
/// validates. A document that is not a JSON object is a request failure, so a
/// caller learns that before any project is read.
fn parseRequest(allocator: std.mem.Allocator, bytes: []const u8) (std.mem.Allocator.Error || error{InvalidRequest})!std.json.Parsed(Value) {
    const parsed = std.json.parseFromSlice(Value, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidRequest,
    };
    if (parsed.value != .object) {
        var owned = parsed;
        owned.deinit();
        return error.InvalidRequest;
    }
    return parsed;
}

/// The reason one argument set was refused, in the caller's vocabulary.
fn argumentFailure(err: wire.Error) []const u8 {
    return switch (err) {
        error.InvalidTestArguments => "the request does not name exactly the parameters the signature declares",
        error.TestValueLimit => "the request nests or repeats more values than one invocation accepts",
        else => "a request value does not match the declared type at that position",
    };
}

/// The export the caller named, or why the name does not select one.
fn select(schema: Value, name: []const u8) error{ UnknownFunction, GenericTemplate }!Value {
    for (v.array(v.get(schema, "functions"))) |function| {
        if (std.mem.eql(u8, v.text(v.get(function, name_key)), name)) return function;
    }
    for (v.array(v.get(schema, "generic_templates"))) |template| {
        if (std.mem.eql(u8, v.text(v.get(template, name_key)), name)) return error.GenericTemplate;
    }
    return error.UnknownFunction;
}

/// One position on the wire that cannot carry a copied value.
const Unsupported = struct { path: []const u8, detail: []const u8 };

/// Whether one export can be invoked, and the first thing that stops it.
const Eligibility = struct {
    unsupported: ?Unsupported = null,
    capabilities: []const []const u8 = &.{},
};

/// One parameter as `--describe` publishes it.
const Parameter = struct { name: []const u8, type: []const u8, mode: []const u8, wire: []const u8 };

/// The wire verdict for the whole call.
const WireOut = struct { supported: bool, unsupported_path: ?[]const u8, unsupported_detail: ?[]const u8 };

/// The eligibility half of a description, grouped to keep the record bounded.
const EligibilityOut = struct { eligible: bool, reason: ?[]const u8, wire: WireOut };

/// What `--describe` reports about one export.
const Describe = struct {
    signature: []const u8,
    parameters: []const Parameter,
    result: []const u8,
    effects: []const []const u8,
    required_capabilities: []const []const u8,
    invocation: EligibilityOut,
};

/// Identity of everything the answer was produced from.
const Identities = struct {
    compiler: []const u8,
    zig: []const u8,
    qbe: []const u8,
    source: []const u8,
    schema: []const u8,

    const unknown: Identities = .{ .compiler = "", .zig = "", .qbe = "", .source = "", .schema = "" };
};

/// The effective execution bounds, so a response is readable without the flags.
const Limits = struct { max_steps: u64, max_frames: u64, max_calls: u64, timeout_ms: u32, max_memory: u64 };

/// One call's typed outcome. `status` says what the call did — `returned` for a
/// completed call whatever it carries, then `trap`, `timeout` or
/// `infrastructure-failure` — so a consumer that reads only this never has to
/// interpret a success as a missing failure.
const Outcome = struct {
    status: []const u8,
    value: Value = .null,
    diagnostics: []const u8 = "",
    output: []const u8 = "",
    steps: u64 = 0,
};

/// A description answer: the contract and the eligibility verdict, no outcome.
const DescribeResponse = struct {
    version: []const u8 = version,
    status: []const u8,
    function: []const u8,
    identities: Identities,
    limits: Limits,
    describe: Describe,
};

/// A call answer: the typed outcome the one child produced.
const OutcomeResponse = struct {
    version: []const u8 = version,
    status: []const u8,
    function: []const u8,
    identities: Identities,
    limits: Limits,
    outcome: Outcome,
    reason: ?[]const u8 = null,
};

/// A refusal: the selector, the reason it was refused, and no outcome at all.
const RefusedResponse = struct {
    version: []const u8 = version,
    status: []const u8,
    function: []const u8,
    identities: Identities,
    limits: Limits,
    reason: []const u8,
};

fn limitSet(limits: execute.Limits) Limits {
    return .{
        .max_steps = limits.max_steps,
        .max_frames = limits.max_frames,
        .max_calls = limits.max_calls,
        .timeout_ms = limits.timeout_ms,
        .max_memory = limits.max_memory orelse 0,
    };
}

/// The compiler, tool, source and schema identities one response is pinned to,
/// so a caller can tell two answers apart without re-reading the project.
fn identitySet(context: fs.Context, session: *const sessions.Session, captured: snapshot.Snapshot, schema: Value) !Identities {
    const encoded = try std.json.Stringify.valueAlloc(context.allocator, schema, .{});
    defer context.allocator.free(encoded);
    return .{
        .compiler = session.hashes[0],
        .zig = try fs.digest(context.allocator, session.hashes[1]),
        .qbe = try fs.digest(context.allocator, session.hashes[2]),
        .source = captured.identity,
        .schema = try fs.digest(context.allocator, encoded),
    };
}

/// Record one required capability once. A capability parameter and the effect
/// it produces name the same authority, so listing both would overstate what
/// the caller has to grant.
fn addCapability(allocator: std.mem.Allocator, capabilities: *std.ArrayList([]const u8), capability: []const u8) Error!void {
    for (capabilities.items) |existing| {
        if (std.mem.eql(u8, existing, capability)) return;
    }
    try capabilities.append(allocator, capability);
}

/// Why a callable type is still not a call argument.
const abi_detail = "the native call ABI carries integers, booleans and an injected stream; that type is a copied value but not a call argument";

/// The capability a parameter type demands, or null when the adapter supplies
/// it. `stream_cap` is the runtime's own stream: printing needs no host grant.
fn capabilityOf(type_name: []const u8) ?[]const u8 {
    const table = [_]struct { type_name: []const u8, capability: []const u8 }{
        .{ .type_name = "filesystem_cap", .capability = "Filesystem" },
        .{ .type_name = "network_cap", .capability = "Network" },
        .{ .type_name = "clock_cap", .capability = "Clock" },
        .{ .type_name = "random_cap", .capability = "Entropy" },
        .{ .type_name = "environment_cap", .capability = "Environment" },
        .{ .type_name = "host_cap", .capability = "Host" },
    };
    for (table) |entry| if (std.mem.eql(u8, entry.type_name, type_name)) return entry.capability;
    return null;
}

/// The capability an effect demands, or null when the effect needs no authority
/// outside the process. Managed allocation, printing to an injected stream and
/// mutation of copied inputs are the runtime's own business.
fn authorityOf(name: []const u8) ?[]const u8 {
    const table = [_]struct { effect: []const u8, capability: []const u8 }{
        .{ .effect = "filesystem", .capability = "Filesystem" },
        .{ .effect = "network", .capability = "Network" },
        .{ .effect = "clock", .capability = "Clock" },
        .{ .effect = "random", .capability = "Entropy" },
        .{ .effect = "environment", .capability = "Environment" },
        .{ .effect = "host", .capability = "Host" },
    };
    for (table) |entry| if (std.mem.eql(u8, entry.effect, name)) return entry.capability;
    return null;
}

/// Walk one export's signature and its declared ceiling and report the first
/// thing that stops an invocation, so a checked signature is never advertised
/// as a callable one.
fn evaluate(allocator: std.mem.Allocator, schema: Value, function: Value) Error!Eligibility {
    const types = v.array(v.get(schema, "types"));
    var walk: Walker = .{ .allocator = allocator, .types = types };
    var capabilities: std.ArrayList([]const u8) = .empty;
    for (parametersOf(function)) |parameter| {
        const name = v.text(v.get(parameter, name_key));
        const type_name = v.text(v.get(parameter, "type"));
        const path = try std.fmt.allocPrint(allocator, "parameters.{s}", .{name});
        // An injected stream takes no JSON argument, so it is not encoded and
        // cannot be unsupported on the wire; every other capability is refused.
        if (std.mem.eql(u8, type_name, stream_cap)) continue;
        if (capabilityOf(type_name)) |capability| {
            try addCapability(allocator, &capabilities, capability);
            continue;
        }
        if (isListType(types, type_name)) return .{ .unsupported = unsupportedAt(path, list_argument_detail), .capabilities = capabilities.items };
        if (try walk.check(type_name, path, 0)) |stop| return .{ .unsupported = stop, .capabilities = capabilities.items };
        if (!abiCarries(types, type_name)) return .{ .unsupported = unsupportedAt(path, abi_detail), .capabilities = capabilities.items };
    }
    const result = v.text(v.get(function, "result"));
    if (try walk.check(result, "result", 0)) |stop| {
        return .{ .unsupported = stop, .capabilities = capabilities.items };
    }
    if (!abiCarriesResult(types, result)) return .{ .unsupported = unsupportedAt("result", abi_detail), .capabilities = capabilities.items };
    for (v.array(v.get(function, "effects"))) |effect| {
        const capability = authorityOf(v.text(effect)) orelse continue;
        try addCapability(allocator, &capabilities, capability);
    }
    return .{ .capabilities = capabilities.items };
}

/// The schema definition of one type name, or null when the checked schema has
/// none. Both the codec walk and the call-ABI rule read the same table.
fn definitionIn(types: []const Value, name: []const u8) ?Value {
    for (types) |item| {
        if (std.mem.eql(u8, v.text(v.get(item, name_key)), name)) return item;
    }
    return null;
}

/// Whether the native call ABI can carry one type. The ABI is narrower than the
/// codec: integers and booleans travel by value and the adapter injects a
/// stream, but a record is a perfectly good copied value that still cannot be a
/// call argument. That gap is exactly what `--describe` exists to report.
fn abiCarries(types: []const Value, type_name: []const u8) bool {
    if (std.mem.eql(u8, type_name, stream_cap)) return true;
    const item = definitionIn(types, type_name) orelse return false;
    const kind = v.text(v.get(item, "kind"));
    return std.mem.eql(u8, kind, "integer") or std.mem.eql(u8, kind, "boolean");
}

/// Whether the return direction of the call ABI can carry one type. It carries
/// everything an argument can, plus a copied managed text: the codec reads a
/// returned text out of the guest value after the call has finished and
/// allocates nothing while doing it, so the handle in the return slot never has
/// to survive a collection safepoint. The argument direction cannot say the
/// same — building a guest text while materialising arguments would need the
/// codec runtime to hold a root across the next argument's allocation, and it
/// has no root slots yet — so a text parameter stays refused.
fn abiCarriesResult(types: []const Value, type_name: []const u8) bool {
    return abiCarries(types, type_name) or isListType(types, type_name);
}

/// Whether the checked schema declares one type as a copied managed list: an
/// opaque list of one scalar. The wire table spells it `list`, and `str` is the
/// member of that family the parent reads as a string rather than an array.
fn isListType(types: []const Value, type_name: []const u8) bool {
    const item = definitionIn(types, type_name) orelse return false;
    if (!std.mem.eql(u8, v.text(v.get(item, "kind")), "list")) return false;
    if (!v.boolean(v.get(item, "opaque"))) return false;
    // `bytes` is an opaque scalar list too, and the plan stages its encoding
    // separately. Reporting it eligible here would advertise a callable the wire
    // table refuses, which is the failure this command exists to prevent.
    if (std.mem.eql(u8, type_name, "bytes")) return false;
    const element = definitionIn(types, v.text(v.get(item, "element"))) orelse return false;
    const kind = v.text(v.get(element, "kind"));
    return std.mem.eql(u8, kind, "integer") or std.mem.eql(u8, kind, "boolean");
}

/// Why a copied managed list is not a call argument yet, in the caller's words.
const list_argument_detail = "a copied managed list is carried in the return direction only in this version, because building a guest list while materialising arguments would need a root across the next argument's allocation";

/// The one position on the wire that stops an invocation, with its reason.
fn unsupportedAt(path: []const u8, detail: []const u8) ?Unsupported {
    return .{ .path = path, .detail = detail };
}

/// One export's declared parameter list. The schema spells it the same way for
/// every function, so one helper keeps the key literal in one place.
fn parametersOf(function: Value) []const Value {
    return v.array(v.get(function, "parameters"));
}

/// A type-driven walk over the checked schema, mirroring the codec's own rules
/// without a value to encode. It answers "could this type cross the boundary at
/// all", which is the question `--describe` has to answer before a caller
/// writes a request.
const Walker = struct {
    allocator: std.mem.Allocator,
    types: []const Value,
    /// Guard against a cyclic schema, matching the codec's own depth ceiling.
    visits: usize = 0,

    fn definition(self: *Walker, name: []const u8) ?Value {
        return definitionIn(self.types, name);
    }

    /// The first position under `name` that cannot carry a copied value.
    fn check(self: *Walker, name: []const u8, path: []const u8, depth: usize) Error!?Unsupported {
        self.visits += 1;
        if (depth > depth_limit or self.visits > 4096) return unsupportedAt(path, "the type nests deeper than one invocation accepts");
        const item = self.definition(name) orelse return unsupportedAt(path, "the checked schema has no definition for that type");
        const kind = v.text(v.get(item, "kind"));
        if (std.mem.eql(u8, kind, "integer") or std.mem.eql(u8, kind, "boolean")) return null;
        // A copied managed list is a value the codec carries, so the walk stops
        // here and leaves the direction question to the call-ABI rule.
        if (isListType(self.types, name)) return null;
        if (std.mem.eql(u8, kind, "domain")) {
            const wire_name = v.text(v.get(v.get(item, "codec"), "wire"));
            if (wire_name.len == 0) return unsupportedAt(path, "the domain declares no wire codec");
            return self.check(wire_name, path, depth + 1);
        }
        if (std.mem.eql(u8, kind, "array")) {
            return self.check(v.text(v.get(item, "element")), try std.fmt.allocPrint(self.allocator, "{s}[]", .{path}), depth + 1);
        }
        if (std.mem.eql(u8, kind, "record") or std.mem.eql(u8, kind, "table")) {
            for (v.array(v.get(item, if (std.mem.eql(u8, kind, "table")) "cases" else "fields"))) |field| {
                const child = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ path, v.text(v.get(field, name_key)) });
                const child_type = if (std.mem.eql(u8, kind, "table")) v.text(v.get(item, "element")) else v.text(v.get(field, "type"));
                if (try self.check(child_type, child, depth + 1)) |found| return found;
            }
            return null;
        }
        if (std.mem.eql(u8, kind, "enumeration") or std.mem.eql(u8, kind, "tagged_union") or std.mem.eql(u8, kind, "result")) {
            for (v.array(v.get(item, "cases"))) |case| {
                const payload = v.get(case, "payload");
                if (payload == .null) continue;
                const child = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ path, v.text(v.get(case, name_key)) });
                if (try self.check(v.text(payload), child, depth + 1)) |found| return found;
            }
            return null;
        }
        if (std.mem.eql(u8, kind, "capability")) return unsupportedAt(path, "a capability parameter is not a copied value");
        return unsupportedAt(path, "that type has no copied-value representation");
    }
};

/// How one parameter reaches the callee: the adapter injects a stream, a
/// capability is granted by the caller rather than encoded, and everything else
/// is a copied value.
fn wireLabel(type_name: []const u8) []const u8 {
    if (std.mem.eql(u8, type_name, stream_cap)) return "injected";
    return if (capabilityOf(type_name) != null) "authority" else "copied";
}

/// Render the checked contract into the description a caller reads.
fn describe(allocator: std.mem.Allocator, function: Value, eligibility: Eligibility) Error!Describe {
    var parameters: std.ArrayList(Parameter) = .empty;
    for (parametersOf(function)) |parameter| {
        const type_name = v.text(v.get(parameter, "type"));
        try parameters.append(allocator, .{
            .name = v.text(v.get(parameter, name_key)),
            .type = type_name,
            .mode = v.text(v.get(parameter, "mode")),
            .wire = wireLabel(type_name),
        });
    }
    var effects: std.ArrayList([]const u8) = .empty;
    for (v.array(v.get(function, "effects"))) |effect| try effects.append(allocator, v.text(effect));
    const stop = eligibility.unsupported;
    return .{
        .signature = try renderSignature(allocator, function),
        .parameters = parameters.items,
        .result = v.text(v.get(function, "result")),
        .effects = effects.items,
        .required_capabilities = eligibility.capabilities,
        .invocation = .{
            .eligible = stop == null and eligibility.capabilities.len == 0,
            .reason = if (stop) |value|
                try std.fmt.allocPrint(allocator, "the type at {s} cannot cross the invocation boundary: {s}", .{ value.path, value.detail })
            else if (eligibility.capabilities.len != 0)
                try std.fmt.allocPrint(allocator, "that export needs external authority this version does not grant: {s}", .{eligibility.capabilities[0]})
            else
                null,
            .wire = .{
                .supported = stop == null,
                .unsupported_path = if (stop) |value| value.path else null,
                .unsupported_detail = if (stop) |value| value.detail else null,
            },
        },
    };
}

/// Render the checked contract as `def name(a: T, ...) -> R effects(...)`. The
/// schema carries the parameter and result types, not the source text, so this
/// is a rendering of the checked contract rather than a copy of the source.
fn renderSignature(allocator: std.mem.Allocator, function: Value) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.print("def {s}(", .{v.text(v.get(function, name_key))});
    for (parametersOf(function), 0..) |parameter, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ v.text(v.get(parameter, name_key)), v.text(v.get(parameter, "type")) });
    }
    try writer.print(") -> {s} effects(", .{v.text(v.get(function, "result"))});
    for (v.array(v.get(function, "effects")), 0..) |effect, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(v.text(effect));
    }
    try writer.writeAll(")");
    return out.toOwnedSlice();
}

/// One checked schema exercising every eligibility branch: a scalar call, a
/// record call, a capability parameter, an injected stream, a managed value and
/// an uninstantiated generic template.
const test_schema =
    \\{"functions":[
    \\{"name":"lib::add","parameters":[{"name":"a","type":"i64","mode":"value"},{"name":"b","type":"i64","mode":"value"}],"result":"i64","effects":[]},
    \\{"name":"lib::shift","parameters":[{"name":"p","type":"lib::Point","mode":"value"}],"result":"lib::Point","effects":["managed_allocation"]},
    \\{"name":"lib::read_it","parameters":[{"name":"fs","type":"filesystem_cap","mode":"value"}],"result":"i64","effects":["filesystem"]},
    \\{"name":"lib::shout","parameters":[{"name":"out","type":"stream_cap","mode":"value"},{"name":"x","type":"i64","mode":"value"}],"result":"i64","effects":["output"]},
    \\{"name":"lib::text","parameters":[{"name":"s","type":"blob","mode":"value"}],"result":"i64","effects":[]},
    \\{"name":"lib::render","parameters":[{"name":"n","type":"i64","mode":"value"}],"result":"str","effects":["managed_allocation"]},
    \\{"name":"lib::measure","parameters":[{"name":"text","type":"str","mode":"value"}],"result":"i64","effects":[]},
    \\{"name":"lib::series","parameters":[{"name":"n","type":"i64","mode":"value"}],"result":"List<i64>","effects":["managed_allocation"]},
    \\{"name":"lib::tally","parameters":[{"name":"values","type":"List<i64>","mode":"value"}],"result":"i64","effects":[]}],
    \\"types":[{"name":"i64","kind":"integer"},{"name":"bool","kind":"boolean"},
    \\{"name":"lib::Point","kind":"record","fields":[{"name":"x","type":"i64"},{"name":"y","type":"i64"}]},
    \\{"name":"blob","kind":"managed"},{"name":"u32","kind":"integer","signed":false,"bits":32},
    \\{"name":"str","kind":"list","opaque":true,"element":"u32"},
    \\{"name":"List<i64>","kind":"list","opaque":true,"element":"i64"},
    \\{"name":"filesystem_cap","kind":"capability"},{"name":"stream_cap","kind":"capability"}],
    \\"generic_templates":[{"name":"lib::first","module":"lib","kind":"function","contract":{"callable":false,"requires_explicit_instantiation":true}}]}
;

fn testSchema(allocator: std.mem.Allocator) !std.json.Parsed(Value) {
    return std.json.parseFromSlice(Value, allocator, test_schema, .{ .allocate = .alloc_always });
}

test "invoke accepts both selector spellings and refuses an incomplete request" {
    const joined = try parse(&.{ "lib.my", "--function=lib::add", "--describe" });
    try std.testing.expectEqualStrings("lib.my", joined.target.source);
    try std.testing.expectEqualStrings("lib::add", joined.target.function);
    try std.testing.expect(joined.target.describe);
    const separated = try parse(&.{ "lib.my", "--function", "lib::add", "--input", "req.json" });
    try std.testing.expectEqualStrings("lib::add", separated.target.function);
    try std.testing.expectEqualStrings("req.json", separated.target.input.?);
    try std.testing.expectEqual(@as(u32, default_timeout_ms), separated.limits.timeout_ms);
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{"lib.my"}));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function=lib::add" }));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function=lib::add", "--describe", "--input=req.json" }));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function=lib::add", "--describe", "--format=xml" }));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function=lib::add", "--describe", "--max-steps=0" }));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function=lib::add", "--describe", "--max-steps=abc" }));
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{ "lib.my", "--function" }));
    // Every value-taking flag accepts both spellings, so the usage text that
    // advertises the spaced form cannot advertise a flag the parser rejects.
    const bounds = try parse(&.{ "lib.my", "--function", "lib::add", "--describe", "--max-steps", "500", "--timeout-ms", "30000" });
    try std.testing.expectEqual(@as(u64, 500), bounds.limits.max_steps);
    try std.testing.expectEqual(@as(u32, 30000), bounds.limits.timeout_ms);
    const tools = try parse(&.{ "lib.my", "--function", "lib::add", "--describe", "--cache-dir", "/tmp/c", "--mode", "ReleaseFast" });
    try std.testing.expectEqualStrings("/tmp/c", tools.tools.cache);
    try std.testing.expectEqualStrings("ReleaseFast", tools.tools.mode);
    try std.testing.expectError(error.InvalidInvokeArguments, parse(&.{"--describe"}));
}

// spec: INVOKE-SELECT-1
test "invoke selects one export and reports an unknown or generic name" {
    const parsed = try testSchema(std.testing.allocator);
    defer parsed.deinit();
    const selected = try select(parsed.value, "lib::add");
    try std.testing.expectEqualStrings("lib::add", v.text(v.get(selected, name_key)));
    try std.testing.expectError(error.UnknownFunction, select(parsed.value, "lib::hidden"));
    try std.testing.expectError(error.GenericTemplate, select(parsed.value, "lib::first"));
}

// spec: INVOKE-AUTHORITY-1
test "invoke admits only exports that need no external authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const scalar = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::add"));
    try std.testing.expect(scalar.unsupported == null);
    try std.testing.expectEqual(@as(usize, 0), scalar.capabilities.len);
    // Allocating a record is the runtime's own business, so a ceiling that
    // names only `managed_allocation` demands no capability from the caller.
    const allocated = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::shift"));
    try std.testing.expectEqual(@as(usize, 0), allocated.capabilities.len);
    // An injected stream is supplied by the adapter, so printing needs no grant.
    const streamed = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::shout"));
    try std.testing.expect(streamed.unsupported == null);
    try std.testing.expectEqual(@as(usize, 0), streamed.capabilities.len);
    const authority = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::read_it"));
    try std.testing.expectEqual(@as(usize, 1), authority.capabilities.len);
    try std.testing.expectEqualStrings("Filesystem", authority.capabilities[0]);
}

test "invoke names the first type position that cannot cross the boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const managed = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::text"));
    try std.testing.expectEqualStrings("parameters.s", managed.unsupported.?.path);
    try std.testing.expectEqualStrings("that type has no copied-value representation", managed.unsupported.?.detail);
}

test "invoke refuses a copied type the native call ABI cannot carry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    // `lib::shift` is a legitimate copied-value call and still not callable: a
    // record cannot be a call argument or a call result.
    const shift = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::shift"));
    try std.testing.expectEqualStrings("parameters.p", shift.unsupported.?.path);
    try std.testing.expectEqualStrings(abi_detail, shift.unsupported.?.detail);
    const described = try describe(arena.allocator(), try select(parsed.value, "lib::shift"), shift);
    try std.testing.expect(!described.invocation.eligible);
    try std.testing.expect(!described.invocation.wire.supported);
    try std.testing.expect(described.invocation.reason.?.len != 0);
}

// spec: INVOKE-DESCRIBE-1
// spec: INVOKE-TEXT-1
test "invoke carries a copied text in the return direction only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const rendered = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::render"));
    try std.testing.expect(rendered.unsupported == null);
    const description = try describe(arena.allocator(), try select(parsed.value, "lib::render"), rendered);
    try std.testing.expect(description.invocation.eligible);
    try std.testing.expectEqualStrings("str", description.result);
    // The same type in an argument position is refused, and the reason says why
    // rather than reporting the type as one the boundary cannot carry at all.
    const measured = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::measure"));
    try std.testing.expectEqualStrings("parameters.text", measured.unsupported.?.path);
    try std.testing.expectEqualStrings(list_argument_detail, measured.unsupported.?.detail);
    const refused = try describe(arena.allocator(), try select(parsed.value, "lib::measure"), measured);
    try std.testing.expect(!refused.invocation.eligible);
}

// spec: INVOKE-LIST-1
test "invoke carries a copied list result and refuses the same type as an argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const series = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::series"));
    try std.testing.expect(series.unsupported == null);
    const described = try describe(arena.allocator(), try select(parsed.value, "lib::series"), series);
    try std.testing.expect(described.invocation.eligible);
    try std.testing.expectEqualStrings("List<i64>", described.result);
    // A list of the same element type in an argument position is refused, so a
    // caller's array is never answered with something the boundary built wrongly.
    const tally = try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::tally"));
    try std.testing.expectEqualStrings("parameters.values", tally.unsupported.?.path);
    try std.testing.expectEqualStrings(list_argument_detail, tally.unsupported.?.detail);
}

test "invoke describes a callable contract and an ineligible one alike" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const add = try describe(arena.allocator(), try select(parsed.value, "lib::add"), try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::add")));
    try std.testing.expectEqualStrings("def lib::add(a: i64, b: i64) -> i64 effects()", add.signature);
    try std.testing.expectEqualStrings("i64", add.result);
    try std.testing.expectEqual(@as(usize, 2), add.parameters.len);
    try std.testing.expectEqualStrings("copied", add.parameters[0].wire);
    try std.testing.expect(add.invocation.eligible);
    try std.testing.expect(add.invocation.wire.supported);
    try std.testing.expect(add.invocation.reason == null);
    const reader = try describe(arena.allocator(), try select(parsed.value, "lib::read_it"), try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::read_it")));
    try std.testing.expect(!reader.invocation.eligible);
    try std.testing.expect(reader.invocation.reason.?.len != 0);
    try std.testing.expectEqualStrings("Filesystem", reader.required_capabilities[0]);
    const streamed = try describe(arena.allocator(), try select(parsed.value, "lib::shout"), try evaluate(arena.allocator(), parsed.value, try select(parsed.value, "lib::shout")));
    try std.testing.expect(streamed.invocation.eligible);
    try std.testing.expectEqualStrings("injected", streamed.parameters[0].wire);
}

// spec: INVOKE-RESULT-1
test "invoke publishes one native-invocation-v1 object with the documented fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try testSchema(arena.allocator());
    defer parsed.deinit();
    const function = try select(parsed.value, "lib::add");
    const eligibility = try evaluate(arena.allocator(), parsed.value, function);
    const response = DescribeResponse{
        .status = "ok",
        .function = "lib::add",
        .identities = .{ .compiler = "c", .zig = "z", .qbe = "q", .source = "s", .schema = "k" },
        .limits = limitSet(.{ .timeout_ms = default_timeout_ms }),
        .describe = try describe(arena.allocator(), function, eligibility),
    };
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), response, .{});
    const answer = try std.json.parseFromSlice(Value, arena.allocator(), bytes, .{ .allocate = .alloc_always });
    defer answer.deinit();
    try std.testing.expectEqualStrings(version, v.text(v.get(answer.value, "version")));
    try std.testing.expectEqualStrings("lib::add", v.text(v.get(answer.value, "function")));
    try std.testing.expectEqualStrings("c", v.text(v.get(v.get(answer.value, "identities"), "compiler")));
    try std.testing.expectEqual(@as(u64, default_timeout_ms), v.number(v.get(v.get(answer.value, "limits"), "timeout_ms")));
    try std.testing.expect(v.get(answer.value, "describe") != .null);
    try std.testing.expect(v.get(answer.value, "outcome") == .null);
    const refused = RefusedResponse{ .status = status_rejected, .function = "lib::add", .identities = Identities.unknown, .limits = limitSet(.{}), .reason = "no" };
    const refused_bytes = try std.json.Stringify.valueAlloc(arena.allocator(), refused, .{});
    const refusal = try std.json.parseFromSlice(Value, arena.allocator(), refused_bytes, .{ .allocate = .alloc_always });
    defer refusal.deinit();
    try std.testing.expectEqualStrings(status_rejected, v.text(v.get(refusal.value, "status")));
    try std.testing.expect(v.get(refusal.value, "describe") == .null);
    try std.testing.expect(v.get(refusal.value, "outcome") == .null);
}

test "invoke renders a signature from the checked contract" {
    const parsed = try testSchema(std.testing.allocator);
    defer parsed.deinit();
    const rendered = try renderSignature(std.testing.allocator, try select(parsed.value, "lib::shift"));
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("def lib::shift(p: lib::Point) -> lib::Point effects(managed_allocation)", rendered);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.WriteFailed, renderSignature(failing.allocator(), try select(parsed.value, "lib::shift")));
}

// spec: INVOKE-STATUS-1
test "invoke separates a completed call from a trap, a timeout and a host failure" {
    try std.testing.expectEqual(@as(u8, 0), classify("value", "").exit_code);
    try std.testing.expectEqualStrings("ok", classify("value", "").status);
    try std.testing.expectEqual(@as(u8, 1), classify("trap", "R_INDEX").exit_code);
    try std.testing.expectEqualStrings("trap", classify("trap", "R_INDEX").status);
    try std.testing.expectEqual(@as(u8, 1), classify("infrastructure-failure", "Timeout").exit_code);
    try std.testing.expectEqualStrings("timeout", classify("infrastructure-failure", "Timeout").status);
    try std.testing.expectEqual(@as(u8, 2), classify("infrastructure-failure", "FileNotFound").exit_code);
    try std.testing.expectEqualStrings("infrastructure-failure", classify("infrastructure-failure", "FileNotFound").status);
}

// spec: INVOKE-ARGS-1
test "invoke admits a request only when it is an object of named arguments" {
    const parsed = try parseRequest(std.testing.allocator, "{\"a\":\"2\",\"b\":\"3\"}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
    try std.testing.expectError(error.InvalidRequest, parseRequest(std.testing.allocator, "[1, 2]"));
    try std.testing.expectError(error.InvalidRequest, parseRequest(std.testing.allocator, "not json"));
}

test "invoke maps capability parameters and authority effects to one vocabulary" {
    try std.testing.expectEqualStrings("Filesystem", capabilityOf("filesystem_cap").?);
    try std.testing.expectEqualStrings("Entropy", capabilityOf("random_cap").?);
    try std.testing.expect(capabilityOf(stream_cap) == null);
    try std.testing.expect(capabilityOf("i64") == null);
    try std.testing.expectEqualStrings("Network", authorityOf("network").?);
    try std.testing.expect(authorityOf("managed_allocation") == null);
    try std.testing.expect(authorityOf("output") == null);
    try std.testing.expect(authorityOf("mutation") == null);
}

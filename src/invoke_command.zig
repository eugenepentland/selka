//! `mylang invoke`: call one exported function of a checked program through the
//! native runtime and report its result as `native-invocation-v1`.
//!
//! This file owns the command surface only: flag parsing, the diagnostic
//! channel split, and the exit status. The request/response contract lives in
//! `invoke.zig`, the generated wire schema in `invoke_wire_schema.zig` and the
//! child-process execution in `invoke_execute.zig`.
//!
//! Stdout carries exactly one JSON object and nothing else: the child protocol,
//! the compiler's diagnostics and the guest's own prints all travel elsewhere
//! or inside that object's fields.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const execute = @import("native_test_execute.zig");
const wire = @import("native_test_wire.zig");
const invalidation = @import("invalidation.zig");
const budget = @import("memory_budget");
const invoke = @import("invoke.zig");
const schema_json = @import("invoke_wire_schema.zig");
const runner = @import("invoke_execute.zig");
const Value = std.json.Value;

/// The subset of the `invoke` command line this route currently accepts.
pub const usage = "usage: mylang invoke <entry.my> --function 'module::name' (--describe | --input=FILE)\n" ++
    "  --format=json        the only response format\n" ++
    "  --max-memory=BYTES   per-call byte ceiling (K/M/G suffixes; default 512M)\n" ++
    "  --timeout=SECONDS    wall-clock ceiling for one call (default 60)\n" ++
    "  --max-steps=N --max-frames=N --max-calls=N  guest execution quotas\n" ++
    "  --cache-dir=DIR --zig=PATH --qbe=PATH --mode=Debug|ReleaseFast\n" ++
    "  --report             print a work-report-v1 reuse line on stderr\n";

/// One parsed `invoke` command line: the entry and target, exactly one of the
/// describe or input actions, and the toolchain and execution-bound overrides.
pub const Request = struct {
    entry: []const u8 = "",
    function: []const u8 = "",
    describe: bool = false,
    input: ?[]const u8 = null,
    report: bool = false,
    bounds: Bounds = .{},
    tools: Tools = .{},
};

/// Execution-bound overrides the request may carry; null keeps the default.
const Bounds = struct {
    max_memory: ?u64 = null,
    timeout_seconds: ?u64 = null,
    max_steps: ?u64 = null,
    max_frames: ?u64 = null,
    max_calls: ?u64 = null,
};

/// Toolchain and cache paths the request may override.
const Tools = struct {
    cache: []const u8 = ".mylang-cache/tests",
    zig: []const u8 = "zig",
    qbe: []const u8 = "qbe",
    mode: []const u8 = "Debug",
};

/// Invalid command lines are usage failures, never guest failures.
pub const ParseError = error{ InvalidInvocationArguments, OutOfMemory };
/// Every failure `mylang invoke` can propagate before it can render a response:
/// a malformed command line, allocation failure, or a host-side filesystem,
/// toolchain or process failure. A guest trap, a returned language error, a
/// refused source and an invalid request are rendered as responses instead.
pub const Error = ParseError || fs.Error || invoke.Error || runner.Error;

/// Run `mylang invoke`. Returns the process exit status: 0 for a completed
/// call, 1 for a source or runtime failure, 2 for a request or setup failure.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    const a = process.arena.allocator();
    const request = parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return emit(process.io, a, .{
            .status = invoke.statusText(.@"invalid-request"),
            .failure = .{ .kind = invoke.invalid_request_kind, .reason = "the command line is incomplete or malformed; see the usage on stderr" },
        });
    };
    var context = try fs.Context.init(a, process.io, process.environ_map);
    defer context.deinit();
    return dispatch(a, context, request);
}

/// Answer one well-formed request: describe the target, or call it.
fn dispatch(a: std.mem.Allocator, context: fs.Context, request: Request) !u8 {
    const quotas = resolveQuotas(context, request) orelse {
        try std.Io.File.stderr().writeStreamingAll(context.io, usage);
        return emit(context.io, a, .{
            .status = invoke.statusText(.@"invalid-request"),
            .target = .{ .function = request.function, .entry = request.entry },
            .failure = .{ .kind = invoke.invalid_request_kind, .reason = "--max-memory or --timeout is not a valid bound" },
        });
    };
    const opts: options.Options = .{
        .source = request.entry,
        .cache = request.tools.cache,
        .zig = request.tools.zig,
        .qbe = request.tools.qbe,
        .mode = request.tools.mode,
        .limits = quotas,
        .flags = .{ .output = .{ .report = request.report } },
    };
    var check = runner.check(context, opts, if (request.describe) .frontend else .native) catch |err| switch (err) {
        error.InvalidTestArguments => {
            try std.Io.File.stderr().writeStreamingAll(context.io, usage);
            return emit(context.io, a, .{
                .status = invoke.statusText(.@"invalid-request"),
                .target = .{ .function = request.function, .entry = request.entry },
                .failure = .{ .kind = invoke.invalid_request_kind, .reason = "the invocation options are malformed" },
            });
        },
        else => return emit(context.io, a, .{
            .status = invoke.statusText(.@"setup-failure"),
            .target = .{ .function = request.function, .entry = request.entry },
            .failure = .{
                .kind = "setup-failure",
                .reason = "the project could not be checked or the native toolchain is unavailable",
                .diagnostics = @errorName(err),
            },
        }),
    };
    switch (check) {
        .rejected => |diagnostics| return emit(context.io, a, .{
            .status = invoke.statusText(.@"source-error"),
            .target = .{ .function = request.function, .entry = request.entry },
            .failure = .{ .kind = "source-error", .reason = "the project did not check", .diagnostics = diagnostics },
        }),
        .ok => |*prepared| {
            defer context.remove(prepared.session.temporary);
            var work: invalidation.Work = .{ .command = "invoke" };
            if (request.report) prepared.session.work = &work;
            const status = answer(a, context, request, prepared, quotas);
            if (request.report) try report(context, a, &work);
            return status;
        },
    }
}

/// Describe the target, or validate and execute one call of it.
fn answer(a: std.mem.Allocator, context: fs.Context, request: Request, prepared: *runner.Prepared, quotas: execute.Limits) !u8 {
    const schema = runner.schema(prepared);
    const response_context: invoke.Context = .{ .limits = runner.limits(quotas), .identities = try runner.identities(prepared) };
    const target: invoke.Target = .{ .function = request.function, .entry = request.entry };
    const function = invoke.select(schema, request.function) orelse return emit(context.io, a, .{
        .status = invoke.statusText(.@"invalid-request"),
        .target = target,
        .failure = try missingTarget(a, prepared, request.function),
        .context = response_context,
    });
    const verdict = try invoke.eligibility(a, schema, function);
    if (request.describe) return emit(context.io, a, .{
        .status = invoke.statusText(.described),
        .target = target,
        .description = try describe(a, schema, function, verdict),
        .context = response_context,
    });
    if (!verdict.eligible) return emit(context.io, a, .{
        .status = invoke.statusText(.unsupported),
        .target = target,
        .failure = .{ .kind = verdict.refusal.?.kind, .path = verdict.refusal.?.path, .reason = verdict.refusal.?.reason },
        .context = response_context,
    });
    const bytes = context.read(request.input.?) catch return emit(context.io, a, .{
        .status = invoke.statusText(.@"invalid-request"),
        .target = target,
        .failure = .{ .kind = invoke.invalid_request_kind, .reason = "the request file could not be read" },
        .context = response_context,
    });
    // A parsed object has already lost the first spelling of a repeated key,
    // so the raw request text is the only place a duplicate is still visible.
    if (try invoke.duplicateKey(a, bytes)) |key| return emit(context.io, a, .{
        .status = invoke.statusText(.@"invalid-request"),
        .target = target,
        .failure = .{ .kind = invoke.invalid_request_kind, .reason = try std.fmt.allocPrint(a, "argument '{s}' is given more than once", .{key}) },
        .context = response_context,
    });
    const values = try requestValues(a, bytes) orelse return emit(context.io, a, .{
        .status = invoke.statusText(.@"invalid-request"),
        .target = target,
        .failure = .{ .kind = invoke.invalid_request_kind, .reason = "the request file must hold one JSON object of named arguments" },
        .context = response_context,
    });
    var codec: wire.Codec = .{ .allocator = a, .types = invoke.types(schema) };
    defer codec.deinit();
    if (try invoke.arguments(&codec, a, function, values)) |failure| return emit(context.io, a, .{
        .status = invoke.statusText(.@"invalid-request"),
        .target = target,
        .failure = failure,
        .context = response_context,
    });
    runner.build(prepared, request.function) catch |err| return emit(context.io, a, .{
        .status = invoke.statusText(.@"setup-failure"),
        .target = target,
        .failure = .{
            .kind = "setup-failure",
            .reason = "the selected export could not be built into a native library",
            .diagnostics = @errorName(err),
        },
        .context = response_context,
    });
    const attempt = runner.run(prepared, function, values, quotas) catch |err| return emit(context.io, a, .{
        .status = invoke.statusText(.@"setup-failure"),
        .target = target,
        .failure = .{
            .kind = "host-failure",
            .reason = "the native child process could not run the call",
            .diagnostics = @errorName(err),
        },
        .context = response_context,
    });
    return emit(context.io, a, invocation(a, target, attempt, response_context));
}

/// Name one unselectable target precisely: an unqualified spelling, a generic
/// template with no concrete signature, a private declaration, or a name no
/// published module carries.
fn missingTarget(a: std.mem.Allocator, prepared: *runner.Prepared, qualified: []const u8) !invoke.Failure {
    if (std.mem.indexOf(u8, qualified, "::") == null) return .{
        .kind = "unqualified-name",
        .reason = "the target must be the qualified name of an exported function, spelled 'module::name'",
    };
    return switch (runner.declaration(prepared, qualified)) {
        .generic_template => .{
            .kind = "generic-template",
            .reason = try std.fmt.allocPrint(a, "'{s}' is a generic template, so it has no concrete checked signature; add a concrete exported wrapper for the instantiation you need and invoke that wrapper", .{qualified}),
        },
        .private_target => .{
            .kind = "private-target",
            .reason = try std.fmt.allocPrint(a, "the module publishes no exported declaration named '{s}'; make it public or invoke an exported wrapper", .{qualified}),
        },
        .unknown => .{
            .kind = "unknown-function",
            .reason = try std.fmt.allocPrint(a, "no published module carries '{s}'; check the module name and the entry's import graph", .{qualified}),
        },
    };
}

/// Build the `--describe` payload: contract, authority, wire schema and why the
/// target is not eligible when it is not.
fn describe(a: std.mem.Allocator, schema: Value, function: Value, verdict: invoke.Verdict) !invoke.Description {
    const definitions = invoke.types(schema);
    const parameters = v.array(v.get(function, "parameters"));
    const arguments = try a.alloc(invoke.Argument, parameters.len);
    for (parameters, arguments) |parameter, *argument| {
        const type_name = v.text(v.get(parameter, "type"));
        argument.* = .{
            .name = v.text(v.get(parameter, "name")),
            .type = type_name,
            .wire = invoke.wireKind(definitions, type_name),
            .injected = std.mem.eql(u8, type_name, "stream_cap"),
        };
    }
    var needed: std.ArrayList([]const u8) = .empty;
    for (verdict.effects) |effect| {
        const granted = for ([_][]const u8{ "managed_allocation", "output", "mutation" }) |allowed| {
            if (std.mem.eql(u8, allowed, effect)) break true;
        } else false;
        if (!granted) try needed.append(a, effect);
    }
    const result_type = v.text(v.get(function, "result"));
    return .{
        .eligible = verdict.eligible,
        .wire_supported = verdict.wire_supported,
        .contract = .{
            .arguments = arguments,
            .result = .{ .type = result_type, .wire = invoke.wireKind(definitions, result_type) },
            .effects = verdict.effects,
            .mutates = try invoke.mutates(a, function),
            .return_origin = invoke.returnOrigin(function),
        },
        .authority = .{ .capabilities = verdict.capabilities, .effects = needed.items },
        .wire_schema = if (verdict.wire_supported) .{
            .request = try schema_json.request(a, definitions, function),
            .result = try schema_json.result(a, definitions, function),
        } else null,
        .unsupported = if (verdict.refusal) |refusal| .{
            .kind = refusal.kind,
            .path = refusal.path,
            .reason = refusal.reason,
        } else null,
    };
}

/// Classify one executed child attempt into the response object.
fn invocation(a: std.mem.Allocator, target: invoke.Target, attempt: execute.Attempt, context: invoke.Context) invoke.Response {
    const outcome = attempt.outcome;
    var response: invoke.Response = .{
        .status = invoke.statusText(.completed),
        .target = target,
        .invocation = .{ .kind = "value", .value = outcome.actual, .steps = outcome.steps, .output = outcome.output },
        .context = context,
    };
    if (std.mem.eql(u8, outcome.status, "value")) {
        if (invoke.returnedError(outcome.actual)) response.invocation.?.kind = "returned-error";
        return response;
    }
    if (std.mem.eql(u8, outcome.status, "trap")) {
        response.status = invoke.statusText(.trap);
        response.invocation.?.kind = "trap";
        response.invocation.?.value = null;
        response.invocation.?.diagnostics = outcome.diagnostics;
        response.invocation.?.trap = invoke.trapDetail(a, outcome.diagnostics) catch null;
        return response;
    }
    if (attempt.timed_out) {
        response.status = invoke.statusText(.timeout);
        response.invocation.?.kind = "timeout";
    } else {
        response.status = invoke.statusText(.@"setup-failure");
        response.invocation.?.kind = "host-failure";
    }
    response.invocation.?.value = null;
    response.invocation.?.diagnostics = outcome.diagnostics;
    return response;
}

/// Parse one request file into a JSON object value, or null when it is not one.
fn requestValues(a: std.mem.Allocator, bytes: []const u8) !?Value {
    const parsed = std.json.parseFromSlice(Value, a, bytes, .{ .allocate = .alloc_always }) catch return null;
    if (parsed.value != .object) return null;
    return parsed.value;
}

/// Resolve the effective quotas from the flags, the environment and defaults.
fn resolveQuotas(context: fs.Context, request: Request) ?execute.Limits {
    var resolved = execute.Limits{};
    if (request.bounds.max_steps) |value| resolved.max_steps = value;
    if (request.bounds.max_frames) |value| resolved.max_frames = value;
    if (request.bounds.max_calls) |value| resolved.max_calls = value;
    if (request.bounds.timeout_seconds) |seconds| {
        if (seconds == 0 or seconds > std.math.maxInt(u32) / 1000) return null;
        resolved.timeout_ms = @intCast(seconds * 1000);
    }
    resolved.max_memory = budget.resolve(request.bounds.max_memory, context.environ, budget.variable, budget.test_default) catch return null;
    return resolved;
}

/// Print the folded compiler work report on stderr, never on stdout.
fn report(context: fs.Context, a: std.mem.Allocator, work: *invalidation.Work) !void {
    const rendered = invalidation.renderWork(a, work.*) catch return;
    try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{rendered}));
}

/// Write one `native-invocation-v1` object on stdout and return its exit status.
fn emit(io: std.Io, a: std.mem.Allocator, response: invoke.Response) !u8 {
    const rendered = try std.json.Stringify.valueAlloc(a, response, .{ .emit_null_optional_fields = false });
    try std.Io.File.stdout().writeStreamingAll(io, rendered);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
    return invoke.exitStatusText(response.status);
}

/// Parse the `invoke` command line, rejecting unknown or contradictory flags.
pub fn parse(args: []const []const u8) ParseError!Request {
    var result: Request = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (!std.mem.startsWith(u8, argument, "--")) {
            if (result.entry.len != 0) return error.InvalidInvocationArguments;
            result.entry = argument;
            continue;
        }
        if (std.mem.eql(u8, argument, "--describe")) {
            if (result.describe) return error.InvalidInvocationArguments;
            result.describe = true;
            continue;
        }
        if (std.mem.eql(u8, argument, "--report")) {
            result.report = true;
            continue;
        }
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse argument.len;
        const name = argument[0..split];
        const value = if (split < argument.len) argument[split + 1 ..] else fallback: {
            index += 1;
            if (index == args.len) return error.InvalidInvocationArguments;
            break :fallback args[index];
        };
        if (value.len == 0 or !try assign(&result, name, value)) return error.InvalidInvocationArguments;
    }
    if (result.entry.len == 0 or result.function.len == 0 or result.describe == (result.input != null)) return error.InvalidInvocationArguments;
    return result;
}

/// Apply one `--flag=value` pair; false means the flag is unknown.
fn assign(result: *Request, name: []const u8, value: []const u8) ParseError!bool {
    if (std.mem.eql(u8, name, "--function")) {
        if (result.function.len != 0) return error.InvalidInvocationArguments;
        result.function = value;
        return true;
    }
    if (std.mem.eql(u8, name, "--input")) {
        if (result.input != null) return error.InvalidInvocationArguments;
        result.input = value;
        return true;
    }
    if (std.mem.eql(u8, name, "--format")) {
        if (!std.mem.eql(u8, value, "json")) return error.InvalidInvocationArguments;
        return true;
    }
    if (std.mem.eql(u8, name, "--cache-dir")) return record(&result.tools.cache, value);
    if (std.mem.eql(u8, name, "--zig")) return record(&result.tools.zig, value);
    if (std.mem.eql(u8, name, "--qbe")) return record(&result.tools.qbe, value);
    if (std.mem.eql(u8, name, "--mode")) {
        if (!std.mem.eql(u8, value, "Debug") and !std.mem.eql(u8, value, "ReleaseFast")) return error.InvalidInvocationArguments;
        return record(&result.tools.mode, value);
    }
    if (std.mem.eql(u8, name, "--max-memory")) {
        if (result.bounds.max_memory != null) return error.InvalidInvocationArguments;
        result.bounds.max_memory = budget.parse(value) catch return error.InvalidInvocationArguments;
        return true;
    }
    if (std.mem.eql(u8, name, "--timeout")) return number(&result.bounds.timeout_seconds, value);
    if (std.mem.eql(u8, name, "--max-steps")) return number(&result.bounds.max_steps, value);
    if (std.mem.eql(u8, name, "--max-frames")) return number(&result.bounds.max_frames, value);
    if (std.mem.eql(u8, name, "--max-calls")) return number(&result.bounds.max_calls, value);
    return false;
}

fn record(slot: *[]const u8, value: []const u8) bool {
    slot.* = value;
    return true;
}

/// Parse one positive bounded number; zero and junk are rejected.
fn number(slot: *?u64, value: []const u8) ParseError!bool {
    const parsed = std.fmt.parseInt(u64, value, 10) catch return error.InvalidInvocationArguments;
    if (parsed == 0 or parsed > std.math.maxInt(u32)) return error.InvalidInvocationArguments;
    slot.* = parsed;
    return true;
}

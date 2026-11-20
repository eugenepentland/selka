//! What a `selka test` run is keyed by (the name is the receipts' time; the receipts are gone). The run's `Context`, the
//! settings digest that binds the compiler, the toolchain, the cases, the configuration and the keyed environment, the digest
//! of a test's reachable IR and source positions (`programKey`, the test's IR key), and the digests the engine's `test-exec`
//! arguments are built from (`executionSettings`, `executionInputs`, `environmentDigest`). No key names an absolute path:
//! every path is relative to the entry's root. The files a check read (`captured`) are what a stored report depends on, and
//! `renderReplay` turns a stored report into the replay of a later run.
const std = @import("std");
const product = @import("selka").product;
const fast_blake3 = @import("fast_blake3.zig");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const project_entry = @import("project_entry.zig");
const report = @import("test_runner_report.zig");
const test_work = @import("test_work.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const emit_units = @import("emit_units.zig");
const emit_llvm = @import("emit_llvm.zig");
const ir = @import("ir.zig");
const Error = @import("test_runner_property.zig").Error;
const Digest = [32]u8;
const planner = @import("selka").cache_plan_adapter;
const environment_identity = @import("selka").environment_identity;

/// Command resources and freshly resolved project configuration.
pub const Context = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    options: options.Options,
    entry: project_entry.Entry,
    case_bytes: []const u8 = "",
    identity: Identities,
};

/// The identities a run's keys bind besides its options: the guest toolchain, the cache planner and the compiler
/// (`compiler`). Production takes the build's own; tests substitute others to simulate an edit.
pub const Identities = struct {
    tool: tool_identity.Identity,
    cache_plan: ?planner.Bound = null,
    compiler: []const u8 = frontend.compiler_identity,
};
/// A file's exact identity, including absence for optional generated interfaces.
pub const Dependency = struct { path: []const u8, digest: ?Digest };
/// Complete settings, compiler/runtime/toolchain identity, native inputs and the
/// environment variables that can change an outcome. Field lengths prevent
/// concatenation ambiguities. Every path is relative to the entry's root
/// (RECEIPT-PATHS-1): two checkouts of one project key alike.
pub fn settings(context: Context, inputs: *std.ArrayList(Dependency)) Error!Digest {
    return settingsWithBudget(context, inputs, "core-test-settings-v4", context.options.properties.runs);
}

/// Budget-independent settings exist only for the explicit stable indexed generator.
/// The caller binds these settings through the ordinary complete target-closure key.
pub fn campaignSettings(context: Context, inputs: *std.ArrayList(Dependency)) Error!?Digest {
    if (context.options.properties.policy != .indexed_v1) return null;
    const indexed = try settingsWithBudget(context, inputs, "core-property-indexed-settings-v2", 0);
    return indexed;
}

/// The entry's path relative to its root, as every key names it: the same project
/// at two absolute locations keys alike (RECEIPT-PATHS-1). A single-file entry's is
/// its basename within its directory root.
pub fn entryPath(context: Context) Error![]const u8 {
    return rooted(context, context.entry.path);
}

/// `path` relative to the entry's root, resolving a relative `path` against the
/// working directory first. Configuration found above the root keeps its `..`
/// steps; its bytes are keyed beside the name.
fn rooted(context: Context, path: []const u8) Error![]const u8 {
    const a = context.arena;
    const absolute = if (std.fs.path.isAbsolute(path)) path else std.Io.Dir.cwd().realPathFileAlloc(context.io, path, a) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return path;
    };
    return std.fs.path.relativePosix(a, "/", context.entry.root, absolute);
}

/// The execution settings both tiers bind, as JSON: the ownership mode
/// (constant `zero-rc` fields), build mode, fact mode (`verify` included), code
/// generation choices, the property seed and `runs`, the trial
/// budgets and the leak-check mode (`SELKA_CORE_LEAKCHECK`, EXEC-RECEIPT-4), so a
/// fact-verification, a leak-checked and a plain run never share a receipt.
fn settingsJson(context: Context, runs: u32) Error![]const u8 {
    const json = try std.json.Stringify.valueAlloc(context.arena, .{
        .single_owner = "zero-rc",
        .zero_rc = "zero-rc",
        .mode = context.options.build.mode,
        .compile = context.options.build.mode.keyed(),
        .facts = context.options.build.facts,
        .vectors = context.options.build.show.codegen.generic_vectors,
        .frames = context.options.build.show.codegen.trap_frames,
        .counters = context.options.build.show.codegen.counters,
        .seed = context.options.properties.seed,
        .runs = runs,
        .timeout = context.options.controls.timeout_ms,
        .steps = context.options.controls.max_steps,
        .call_frames = context.options.controls.ceilings.frames,
        .memory = context.options.controls.ceilings.memory,
        .leakcheck = leakCheck(context),
        .local_stdlib = context.options.build.show.codegen.local_stdlib,
    }, .{});
    // A run for a CPU model other than the machine's (`--cpu`) never shares a receipt with a native one; a native run's settings
    // stay the bytes they were.
    const model = context.options.build.show.codegen.target.cpuModel();
    if (model == .native) return json;
    return std.fmt.allocPrint(context.arena, "{s}\x00cpu={s}", .{ json, model.spelling() }) catch return error.OutOfMemory;
}

/// The leak-check mode of the test processes: `SELKA_CORE_LEAKCHECK`, `0` when unset.
fn leakCheck(context: Context) []const u8 {
    return context.environment.get("SELKA_CORE_LEAKCHECK") orelse "0";
}

/// The serialized settings an execution key binds (`ExecutionInputs.settings`).
pub fn executionSettings(context: Context) Error![]const u8 {
    return settingsJson(context, context.options.properties.runs);
}

fn optionalBytes(hash: *fast_blake3.Blake3, role: []const u8, bytes: ?[]const u8) void {
    field(hash, role);
    field(hash, if (bytes != null) "present" else "absent");
    if (bytes) |value| field(hash, value);
}

fn settingsWithBudget(context: Context, inputs: *std.ArrayList(Dependency), domain: []const u8, runs: u32) Error!Digest {
    const a = context.arena;
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, domain);
    if (context.identity.cache_plan) |bound| field(&hash, &bound.identity) else field(&hash, "missing-cache-plan");
    field(&hash, context.identity.compiler);
    // The entry's path is not here: a pass is the test's under any root of the project (D-TL2-1 of
    // experiments/test-loop-20261109/DECISIONS.md). What a pass can depend on of its entry is bound below (cases,
    // configuration, policy) or in the IR key.
    field(&hash, context.options.build.zig);
    field(&hash, &context.identity.tool.digest);
    field(&hash, &context.identity.tool.native_target);
    optionalBytes(&hash, "cases", if (context.options.controls.cases) |path| try rooted(context, path) else null);
    if (context.options.controls.cases != null) field(&hash, context.case_bytes);
    field(&hash, try settingsJson(context, runs));
    if (context.entry.configuration) |configured| {
        field(&hash, try rooted(context, configured.path));
        // Less the `stores` member (FR8): where the stores are is placement, and a file without one keys as it always did.
        field(&hash, try configured.keyBytes(a));
        if (configured.policy) |policy| {
            field(&hash, try rooted(context, policy.path));
            field(&hash, policy.bytes);
        }
    }
    for (context.options.build.links) |link| {
        field(&hash, std.Io.Dir.cwd().realPathFileAlloc(context.io, link, a) catch link);
        const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, link, a, .limited(64 << 20)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.ReadFailed;
        };
        field(&hash, bytes);
        var digest: Digest = undefined;
        fast_blake3.hash(bytes, &digest);
        try inputs.append(a, .{ .path = link, .digest = digest });
    }
    try environmentSettings(context, &hash);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// The keyed environment as one digest: what `environmentSettings` feeds every key, hashed alone. The engine's `test-exec`
/// argument carries it, so each environment state has its own record and a flip between two states never overwrites one
/// with the other.
pub fn environmentDigest(context: Context) error{OutOfMemory}!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-test-environment-v1");
    environmentSettings(context, &hash) catch return error.OutOfMemory;
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn environmentSettings(context: Context, hash: *fast_blake3.Blake3) Error!void {
    const a = context.arena;
    var environment: std.ArrayList([]const u8) = .empty;
    var entries = context.environment.iterator();
    while (entries.next()) |item| {
        if (!keyedVariable(item.key_ptr.*)) continue;
        try environment.append(a, try std.fmt.allocPrint(a, "{s}={s}", .{ item.key_ptr.*, item.value_ptr.* }));
    }
    std.mem.sort([]const u8, environment.items, {}, before);
    for (environment.items) |item| field(hash, item);
}

/// Whether a variable can change a test's outcome: the keyed class of the
/// environment identity contract (ENV-IDENTITY-1). A shell's `_` and `OLDPWD`, a
/// terminal's variables, cache and telemetry placement cannot; a test that reads
/// the environment is never reused.
fn keyedVariable(name: []const u8) bool {
    return environment_identity.keyed(name);
}

/// What emission reads from one test's program besides the keyed settings.
pub const Program = struct {
    /// The test's Core IR before passes.
    module: *const ir.Module,
    /// Where each span is: the only way emission reads the source.
    locator: emit_llvm.Locator,
    /// Whether the key binds each span's line and column. A test's per-test IR key does not (`programIdentity`): a passing
    /// verdict cannot observe a position and a failure is never recorded (`experiments/test-keys-20261106/DECISIONS.md`, D-T1-1).
    positions: bool = true,
};

/// A test's program key, computed without emitting it: passes and LLVM emission are
/// pure functions of the IR, the settings in `base` and the positions the locator
/// gives, so the IR is hashed field by field with every span replaced by its file,
/// line and column. An edit that only moves code in other files keeps the key.
pub fn programKey(base: Digest, name: []const u8, program: Program) Digest {
    var walker: Walker = .{ .hash = fast_blake3.Blake3.init(.{}), .locator = program.locator, .positions = program.positions };
    field(&walker.hash, "core-test-ir-v5");
    field(&walker.hash, &base);
    field(&walker.hash, name);
    field(&walker.hash, emit_units.native_extension);
    walker.value(program.module.*);
    walker.flush();
    var digest: Digest = undefined;
    walker.hash.final(&digest);
    return digest;
}

/// Feeds a value's fields to the hash in declaration order through a small buffer.
const Walker = struct {
    hash: fast_blake3.Blake3,
    locator: emit_llvm.Locator,
    buffer: [4096]u8 = undefined,
    used: usize = 0,
    last: ?struct { span: u32, at: emit_llvm.Location } = null,
    positions: bool = true,

    fn bytes(self: *Walker, data: []const u8) void {
        if (self.used + data.len > self.buffer.len) self.flush();
        if (data.len > self.buffer.len) return self.hash.update(data);
        @memcpy(self.buffer[self.used..][0..data.len], data);
        self.used += data.len;
    }

    fn flush(self: *Walker) void {
        self.hash.update(self.buffer[0..self.used]);
        self.used = 0;
    }

    fn integer(self: *Walker, comptime Width: type, number: Width) void {
        var encoded: [@sizeOf(Width)]u8 = undefined;
        std.mem.writeInt(Width, &encoded, number, .little);
        self.bytes(&encoded);
    }

    /// The `@freestanding` names of a module (`ir.Module.freestanding`) whatever the map's order: the count, and the sum and
    /// the exclusive or of the name keys.
    fn freestandingSet(self: *Walker, set: std.AutoHashMapUnmanaged(u128, void)) void {
        if (set.count() == 0) return;
        var sum: u128 = 0;
        var mixed: u128 = 0;
        var keys = set.keyIterator();
        while (keys.next()) |key| {
            sum +%= key.*;
            mixed ^= key.*;
        }
        self.integer(u64, set.count());
        self.integer(u128, sum);
        self.integer(u128, mixed);
    }

    fn value(self: *Walker, item: anytype) void {
        const T = @TypeOf(item);
        switch (@typeInfo(T)) {
            .void => {},
            .bool => self.integer(u8, @intFromBool(item)),
            .int => |info| {
                const Width = @Int(.unsigned, @max(8, std.math.ceilPowerOfTwoAssert(u16, info.bits)));
                const Wide = @Int(info.signedness, @bitSizeOf(Width));
                self.integer(Width, @bitCast(@as(Wide, item)));
            },
            .@"enum" => self.value(@backingInt(item)),
            .optional => if (item) |present| {
                self.integer(u8, 1);
                self.value(present);
            } else self.integer(u8, 0),
            .pointer => |info| switch (info.size) {
                .slice => {
                    self.integer(u64, item.len);
                    if (info.child == u8) self.bytes(item) else for (item) |element| self.value(element);
                },
                .one => self.value(item.*),
                else => @compileError("no receipt hashing for " ++ @typeName(T)),
            },
            .@"union" => switch (item) {
                inline else => |payload, tag| {
                    self.value(tag);
                    self.value(payload);
                },
            },
            .@"struct" => |info| if (@hasField(T, "items") and @hasField(T, "capacity")) self.value(item.items) else inline for (info.field_names, info.field_types) |member, Member| {
                // A loop's `id` counts the checker's loops program-wide, so it moves with which
                // modules were rechecked; the loop itself is its blocks (NEW-CORE-TEST-KEYS-2).
                if (comptime T == ir.Loop and std.mem.eql(u8, member, "id")) continue;
                // The observer of `Module.intern` is no part of the program, and `Function.module` is a function of the
                // function's span, which is hashed by its position.
                if (comptime T == ir.ModuleLowering and std.mem.eql(u8, member, "tap")) continue;
                // The stable names of the nominal compounds only let the optimizer's records find a type again; the program
                // they describe is hashed by structure.
                if (comptime T == ir.Module and std.mem.eql(u8, member, "nominal")) continue;
                // Which functions are private to their unit decides the linkage of the emitted text, not what the program does.
                if (comptime T == ir.Module and std.mem.eql(u8, member, "private")) continue;
                // Which functions are `@freestanding` decides how their failed checks fault: hashed in no order, as a set.
                if (comptime T == ir.Module and std.mem.eql(u8, member, "freestanding")) {
                    self.freestandingSet(item.freestanding);
                    continue;
                }
                // Which are `@freestanding(ram)` decides their section on a device: the same set hash.
                if (comptime T == ir.Module and std.mem.eql(u8, member, "ram")) {
                    self.freestandingSet(item.ram);
                    continue;
                }
                if (comptime T == ir.Function and std.mem.eql(u8, member, "module")) continue;
                if (comptime std.mem.eql(u8, member, "span") and Member == u32) self.position(@field(item, member)) else self.value(@field(item, member));
            },
            else => @compileError("no receipt hashing for " ++ @typeName(T)),
        }
    }

    fn position(self: *Walker, span: u32) void {
        if (!self.positions) return;
        const at = if (self.last) |last| if (last.span == span) last.at else self.locator.locate(self.locator.context, span) else self.locator.locate(self.locator.context, span);
        self.last = .{ .span = span, .at = at };
        self.integer(u32, at.line);
        self.integer(u32, at.column);
        self.integer(u64, at.path.len);
        self.bytes(at.path);
    }
};

/// A selected case's declarative arguments and expectation join its program key.
pub fn configuredKey(program: Digest, json: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-test-case-v1");
    field(&hash, &program);
    field(&hash, json);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// What an execution-tier key binds besides the runner, the program and the test, as one digest: the serialized settings
/// (`executionSettings`) and the cases, configuration and policy bytes. It is the settings part of the engine's `test-exec`
/// argument; the keyed environment is that kind's read, not part of the argument.
pub fn executionInputs(context: Context, settings_json: []const u8) error{OutOfMemory}!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-test-exec-inputs-v1");
    field(&hash, settings_json);
    optionalBytes(&hash, "cases", if (context.options.controls.cases != null) context.case_bytes else null);
    const configured = context.entry.configuration;
    optionalBytes(&hash, "configuration", if (configured) |found| try found.keyBytes(context.arena) else null);
    optionalBytes(&hash, "policy", if (configured) |found| if (found.policy) |policy| policy.bytes else null else null);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// A validated report and the warnings to emit only when the caller accepts it. `engine` says the engine's record served it
/// (not the manifest) and `receipts` that the receipts' manifest would have too: the observation counts the two sides
/// from them.
pub const Replay = struct { report: []const u8, warnings: []const u8, seen: Seen, renew: ?Renewal = null };

/// A report a replay found through its sources' tokens, to record again under the files' bytes once the replay is accepted
/// (test-loop stage 6, D-TL6-7): the bytes argument, every file the report reads, and the stored document.
pub const Renewal = struct { argument: []const u8, files: []const []const u8, payload: []const u8 };

/// Why a replayed test is `cached` and how its key was found: the explanation its replayed verdict carries.
pub const Why = struct { reason: []const u8 = "engine-report-hit", key_method: []const u8 = "engine-record" };

/// What the engine's shadow needs to ask about a replayed report: the run's settings digest, the entry's root and its path
/// within it, the name filter, and how many tests the report holds.
pub const Seen = struct { base: Digest, root: []const u8, entry: []const u8, filter: []const u8, tests: usize };

/// Whether this run may replay a recorded report at all: the IR tier admits it and its configuration names no interface
/// files (whose inputs a replay cannot see).
pub fn replayAdmitted(context: Context) bool {
    if (!reusable(context)) return false;
    if (context.entry.configuration) |configured| if (configured.document.interface_files) return false;
    return true;
}

/// A recorded successful report as the report of a replay: every test `cached` with `why`'s explanation, the counts of a
/// run that executed nothing. Null when `recorded` is not a report whose tests all passed.
pub fn renderReplay(context: Context, base: Digest, recorded: []const u8, warnings: []const u8, why: Why) Error!?Replay {
    const a = context.arena;
    var value = std.json.parseFromSliceLeaky(std.json.Value, a, recorded, .{}) catch return null;
    if (value != .object) return null;
    const tests = value.object.get("tests") orelse return null;
    if (tests != .array or tests.array.items.len == 0) return null;
    for (tests.array.items) |*test_value| {
        if (test_value.* != .object) return null;
        const status = test_value.object.get("status") orelse return null;
        if (status != .string) return null;
        const succeeded = std.mem.eql(u8, status.string, "passed") or std.mem.eql(u8, status.string, "cached");
        if (!succeeded) return null;
        try test_value.object.put(a, "status", .{ .string = "cached" });
        var explanation: std.json.ObjectMap = .empty;
        try explanation.put(a, "action", .{ .string = "reuse" });
        try explanation.put(a, "reason", .{ .string = why.reason });
        try explanation.put(a, "component", .{ .string = try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(context.identity.cache_plan.?.identity, .lower)}) });
        try explanation.put(a, "key_method", .{ .string = why.key_method });
        if (test_value.object.get("cache")) |previous| if (previous == .object) if (previous.object.get("key")) |key| try explanation.put(a, "key", key);
        try test_value.object.put(a, "cache", .{ .object = explanation });
    }
    try value.object.put(a, "passed", .{ .integer = 0 });
    try value.object.put(a, "cached", .{ .integer = @intCast(tests.array.items.len) });
    var executions: std.json.ObjectMap = .empty;
    try executions.put(a, "hits", .{ .integer = 0 });
    try executions.put(a, "saves", .{ .integer = 0 });
    try value.object.put(a, "exec_receipts", .{ .object = executions });
    try validatePlan(context);
    if (@import("selka").profile_history.enabled()) @import("selka").profile_history.capture(value);
    if (context.options.json) {
        const encoded = try std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, value, .{})});
        return .{ .report = encoded, .warnings = warnings, .seen = try replaySeen(context, base, tests.array.items.len) };
    }
    const verdicts = try a.alloc(report.Verdict, tests.array.items.len);
    for (tests.array.items, verdicts) |test_value, *verdict| {
        const name = test_value.object.get("name") orelse return null;
        if (name != .string) return null;
        verdict.* = .{ .name = name.string, .status = .cached };
    }
    const rendered = try report.text(a, verdicts);
    return .{ .report = rendered, .warnings = warnings, .seen = try replaySeen(context, base, tests.array.items.len) };
}

fn replaySeen(context: Context, base: Digest, tests: usize) Error!Seen {
    return .{ .base = base, .root = context.entry.root, .entry = try entryPath(context), .filter = context.options.filter, .tests = tests };
}

/// Explain the execution contract that prevents reusing successful evidence.
/// `no-success-receipt` means admission is permitted, subject to receipt lookup.
/// Fact verification and leak checking are keyed modes, not refusals
/// (EXEC-RECEIPT-4); `missing-cache-plan` refuses only the IR tier.
pub fn reuseReason(context: Context) []const u8 {
    if (context.identity.cache_plan == null) return "missing-cache-plan";
    return admission(context) orelse "no-success-receipt";
}

/// The refusal both tiers share, or null when a receipt may be looked up.
fn admission(context: Context) ?[]const u8 {
    if (!context.identity.tool.cacheable) return "uncacheable-toolchain";
    if (context.options.controls.force) return "force";
    if (context.options.build.links.len != 0) return "native-links";
    var entries = context.environment.iterator();
    while (entries.next()) |entry| if (std.mem.startsWith(u8, entry.key_ptr.*, "LD_") and entry.value_ptr.len != 0) return "untracked-loader-environment";
    return null;
}

/// Revalidate the component deployment before accepting replay or publishing receipts.
pub fn validatePlan(context: Context) Error!void {
    const bound = context.identity.cache_plan orelse return;
    bound.validate(context.arena) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const message = try std.fmt.allocPrint(context.arena, "error: cache-plan component: {s}\n", .{@errorName(err)});
        var writer = std.Io.File.stderr().writer(context.io, &.{});
        writer.interface.writeAll(message) catch return error.WriteFailed;
        return error.ComponentUnavailable;
    };
}

/// Whether the IR tier may look up or replay receipts.
fn reusable(context: Context) bool {
    return context.identity.cache_plan != null and admission(context) == null;
}

/// Whether the execution tier may look up receipts: the IR tier's admission
/// without the cache planner.
pub fn executionReusable(context: Context) bool {
    return admission(context) == null;
}

/// Capture identities before execution and check them again before publication.
pub fn dependencies(context: Context, paths: []const []const u8) Error![]const Dependency {
    const found = try context.arena.alloc(Dependency, paths.len);
    for (paths, found) |path, *item| item.* = .{ .path = path, .digest = try fileDigest(context, path) };
    return found;
}

/// Record the exact loaded sources and embedded assets, before execution. Standard
/// library bytes are covered by compiler_identity rather than fictitious disk paths.
pub fn captured(context: Context, session: *const frontend.Session, providers: []const frontend.Provider) Error![]const Dependency {
    var files: std.ArrayList(Dependency) = .empty;
    if (session.single) |unit| {
        const relative = try std.fs.path.relative(context.arena, context.entry.root, null, context.entry.root, context.entry.path);
        var overridden = false;
        for (providers) |provider| overridden = overridden or std.mem.eql(u8, provider.path, relative);
        try loaded(context, &files, context.entry.path, unit.src, session.entry.suffix, overridden);
    } else for (session.project.modules.items) |*module| try moduleInputs(context, &files, module, .{ .suffix = session.entry.suffix, .providers = providers });
    return settingsInputs(context, &files);
}

/// `captured` for a root's share of a directory run's shared check
/// (NEW-CORE-TEST-UNION-1): the modules its own graph reaches, read without the
/// stub `main` its own check would have appended, which `loaded` strips anyway.
pub fn capturedModules(context: Context, modules: []const *const frontend.Module) Error![]const Dependency {
    var files: std.ArrayList(Dependency) = .empty;
    for (modules) |module| try moduleInputs(context, &files, module, .{});
    return settingsInputs(context, &files);
}

/// How one module was read: the stub appended to the entry, and the providers
/// that replace modules.
const Reading = struct { suffix: []const u8 = "", providers: []const frontend.Provider = &.{} };

fn moduleInputs(context: Context, files: *std.ArrayList(Dependency), module: *const frontend.Module, reading: Reading) Error!void {
    const a = context.arena;
    if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) return;
    const path = try std.fs.path.join(a, &.{ context.entry.root, module.src.path });
    var overridden = false;
    for (reading.providers) |provider| overridden = overridden or std.mem.eql(u8, module.src.path, provider.path);
    try loaded(context, files, path, module.src, if (std.mem.eql(u8, module.name, context.entry.name)) reading.suffix else "", overridden);
    if (context.entry.configuration) |configured| if (configured.document.interface_files) {
        const api = try std.fmt.allocPrint(a, "{s}.api", .{product.chopSource(path)});
        try files.append(a, .{ .path = api, .digest = try fileDigest(context, api) });
    };
}

/// Append the cases file, configuration and policy a run read to `files`.
fn settingsInputs(context: Context, files: *std.ArrayList(Dependency)) Error![]const Dependency {
    const a = context.arena;
    if (context.options.controls.cases) |path| {
        var digest: Digest = undefined;
        fast_blake3.hash(context.case_bytes, &digest);
        try files.append(a, .{ .path = path, .digest = digest });
    }
    if (context.entry.configuration) |configured| {
        var digest: Digest = undefined;
        fast_blake3.hash(configured.bytes, &digest);
        try files.append(a, .{ .path = configured.path, .digest = digest });
        if (configured.policy) |policy| {
            fast_blake3.hash(policy.bytes, &digest);
            try files.append(a, .{ .path = policy.path, .digest = digest });
        }
    }
    return files.items;
}

fn loaded(context: Context, files: *std.ArrayList(Dependency), path: []const u8, source: @import("selka").source.Source, suffix: []const u8, overridden: bool) Error!void {
    const a = context.arena;
    const bytes = if (suffix.len != 0 and std.mem.endsWith(u8, source.bytes, suffix)) source.bytes[0 .. source.bytes.len - suffix.len] else source.bytes;
    var digest: Digest = undefined;
    fast_blake3.hash(bytes, &digest);
    if (!overridden) try files.append(a, .{ .path = path, .digest = digest });
    for (source.embeds) |embed| {
        if (embed.status != .ok) continue;
        const asset = try std.fs.path.resolve(a, &.{ std.fs.path.dirname(path) orelse ".", embed.path });
        try files.append(a, .{ .path = asset, .digest = embed.digest });
    }
}

/// A source edit during a run prevents reuse of its results.
pub fn unchanged(context: Context, files: []const Dependency) Error!bool {
    for (files) |file| {
        const current = try fileDigest(context, file.path);
        if (current == null or file.digest == null) {
            if ((current == null) != (file.digest == null)) return false;
        } else if (!std.mem.eql(u8, &current.?, &file.digest.?)) return false;
    }
    return true;
}

/// The captured executable, CPU and library tree must remain the same generation.
pub fn toolUnchanged(context: Context) Error!bool {
    return tool_identity.unchanged(.{ .arena = context.arena, .io = context.io, .environment = context.environment, .executable = context.options.build.zig, .cache = context.options.build.cache }, context.identity.tool) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
}

fn fileDigest(context: Context, path: []const u8) Error!?Digest {
    return readDigest(context.arena, context.io, path);
}

/// Hash one bounded disk input; absence is recorded while unreadable inputs and
/// allocation failures propagate. Directory and file snapshots share this rule.
pub fn readDigest(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error!?Digest {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (err == error.FileNotFound) return null;
        return error.ReadFailed;
    };
    defer arena.free(bytes);
    var digest: Digest = undefined;
    fast_blake3.hash(bytes, &digest);
    return digest;
}
fn field(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
fn before(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

/// Test positions: files of 1000 bytes and 100-byte lines, `a.selka` first; `shift` is
/// how far an edit to `a.selka` moved `b.selka`.
const Lines = struct {
    shift: u32,
    fn locate(context: *const anyopaque, offset: u32) emit_llvm.Location {
        const self: *const Lines = @ptrCast(@alignCast(context));
        const in_b = offset >= 1000 + self.shift;
        const local = if (in_b) offset - 1000 - self.shift else offset;
        return .{ .line = local / 100 + 1, .column = local % 100 + 1, .path = if (in_b) "b.selka" else "a.selka" };
    }
};

fn sampleModule(a: std.mem.Allocator, span: u32, data: u64) !ir.Module {
    var module: ir.Module = .{};
    var function: ir.Function = .{ .name = "b.helper", .signature = .{ .params = &.{.i64}, .ret = .i64 }, .span = span };
    try function.insts.append(a, .{ .op = .copy, .ty = .i64, .data = data, .span = span + 7 });
    try module.functions.append(a, function);
    try module.strings.append(a, "text");
    return module;
}

// spec: NEW-CORE-S4-TEST-6
test "receipt keys hash the test's IR and source positions, not where other files moved them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unmoved: Lines = .{ .shift = 0 };
    const shifted: Lines = .{ .shift = 200 };
    const base: Digest = @splat(9);
    const module = try sampleModule(a, 1105, 3);
    const one = programKey(base, "ab", .{ .module = &module, .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    const moved = try sampleModule(a, 1305, 3);
    try std.testing.expectEqual(one, programKey(base, "ab", .{ .module = &moved, .locator = .{ .context = &shifted, .locate = Lines.locate } }));
    const line = try sampleModule(a, 1205, 3);
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &line, .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    const data = try sampleModule(a, 1105, 4);
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &data, .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    var named = try sampleModule(a, 1105, 3);
    named.strings.items[0] = "texts";
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &named, .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "a", .{ .module = &module, .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(@splat(8), "ab", .{ .module = &module, .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
}

test "a receipt key leaves out the module's op-log tap and keeps its target's pointer width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unmoved: Lines = .{ .shift = 0 };
    const locator: emit_llvm.Locator = .{ .context = &unmoved, .locate = Lines.locate };
    const module = try sampleModule(a, 1105, 3);
    const one = programKey(@splat(9), "ab", .{ .module = &module, .locator = locator });
    var tap: ir.Module.Tap = .{ .on_intern = struct {
        fn ignore(_: *ir.Module.Tap, _: *const ir.Module, _: ir.Type) void {}
    }.ignore };
    var tapped = try sampleModule(a, 1105, 3);
    tapped.lowering.tap = &tap;
    try std.testing.expectEqual(one, programKey(@splat(9), "ab", .{ .module = &tapped, .locator = locator }));
    var narrow = try sampleModule(a, 1105, 3);
    narrow.lowering.pointer_bytes = 4;
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(@splat(9), "ab", .{ .module = &narrow, .locator = locator })));
}

// spec-case: T1-SHIFT-1
test "a per-test key without positions keeps a function moved to another line and still sees its instructions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unmoved: Lines = .{ .shift = 0 };
    const base: Digest = @splat(9);
    const module = try sampleModule(a, 1105, 3);
    const locator: emit_llvm.Locator = .{ .context = &unmoved, .locate = Lines.locate };
    const one = programKey(base, "ab", .{ .module = &module, .locator = locator, .positions = false });
    const line = try sampleModule(a, 1205, 3);
    try std.testing.expectEqual(one, programKey(base, "ab", .{ .module = &line, .locator = locator, .positions = false }));
    const data = try sampleModule(a, 1205, 4);
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &data, .locator = locator, .positions = false })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &module, .locator = locator })));
}

// spec-case: NEW-CORE-S4-TEST-3
test "receipt keys bind declarative cases" {
    const original: Digest = @splat(7);
    const configured = configuredKey(original, "{\"expected\":7}");
    try std.testing.expect(!std.mem.eql(u8, &configured, &configuredKey(original, "{\"expected\":8}")));
    try std.testing.expect(!std.mem.eql(u8, &configured, &configuredKey(@splat(8), "{\"expected\":7}")));
}

// spec-case: NEW-CORE-S4-TEST-3
test "readDigest fileDigest and toolUnchanged refuse missing inputs, and a recorded report renders as a replay of cached tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const tool = try std.fs.path.join(a, &.{ root, "zig" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "owned fake tool" });
    try temporary.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    var captured_tool = try tool_identity.capture(.{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = tool, .cache = root });
    // This envelope test executes no compiler; trust its owned synthetic bytes
    // explicitly. Actual tool closure eligibility has independent native tests.
    captured_tool.cacheable = true;
    const context: Context = .{
        .arena = a,
        .io = std.testing.io,
        .environment = &environment,
        .options = .{ .path = "app.selka", .build = .{ .zig = tool, .cache = root }, .json = true },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.selka" }), .root = root, .name = "app" },
        .identity = .{ .tool = captured_tool, .cache_plan = .{ .identity = @splat(11), .mode = .reference, .io = std.testing.io, .environ = &environment, .directory = null, .artifact = null } },
    };
    var setting_inputs: std.ArrayList(Dependency) = .empty;
    const without_ticket = try settings(context, &setting_inputs);
    try environment.put(tool_ticket.hint, "1");
    try std.testing.expectEqual(without_ticket, try settings(context, &setting_inputs));
    try environment.put(tool_ticket.hint, "");
    try std.testing.expect(try fileDigest(context, context.entry.path) == null);
    try std.testing.expect(try readDigest(a, std.testing.io, context.entry.path) == null);
    try std.testing.expect(try toolUnchanged(context));
    try std.testing.expectError(error.ReadFailed, fileDigest(context, root));
    try environment.put("LD_PRELOAD", "/mutable-library.so");
    try std.testing.expect(!replayAdmitted(context));
    try environment.put("LD_PRELOAD", "");
    try std.testing.expect(replayAdmitted(context));
    const identity: Digest = @splat(3);
    const valid = try report.jsonSources(a, &.{.{ .name = "app::test_one", .status = .passed }}, &.{context.entry.path});
    const replayed = (try renderReplay(context, identity, valid, "warning: w\n", .{ .reason = "engine-report-hit", .key_method = "engine-record" })).?;
    try std.testing.expectEqualStrings("warning: w\n", replayed.warnings);
    try std.testing.expectEqual(@as(usize, 1), replayed.seen.tests);
    const parsed_replay = try std.json.parseFromSliceLeaky(std.json.Value, a, replayed.report, .{});
    const explanation = parsed_replay.object.get("tests").?.array.items[0].object.get("cache").?;
    try std.testing.expectEqualStrings("engine-report-hit", explanation.object.get("reason").?.string);
    try std.testing.expectEqualStrings("reuse", explanation.object.get("action").?.string);
    // A report with a failed test is not replayed, and neither is bytes that are no report.
    const failed = try report.jsonSources(a, &.{.{ .name = "app::test_one", .status = .failed }}, &.{context.entry.path});
    try std.testing.expect(try renderReplay(context, identity, failed, "", .{}) == null);
    try std.testing.expect(try renderReplay(context, identity, "not json", "", .{}) == null);
    try temporary.dir.deleteFile(context.io, "zig");
    try std.testing.expect(!try toolUnchanged(context));
}

fn fakeToolContext(a: std.mem.Allocator, root: []const u8, environment: *const std.process.Environ.Map) !Context {
    const tool = try std.fs.path.join(a, &.{ root, "zig" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = tool, .data = "owned fake tool" });
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, tool, .executable_file, .{});
    const identity = try tool_identity.capture(.{ .arena = a, .io = std.testing.io, .environment = environment, .executable = tool, .cache = root });
    return .{
        .arena = a,
        .io = std.testing.io,
        .environment = environment,
        .options = .{ .path = "app.selka", .build = .{ .zig = tool, .cache = root }, .json = true },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.selka" }), .root = root, .name = "app" },
        .identity = .{ .tool = identity, .cache_plan = .{ .identity = @splat(11), .mode = .reference, .io = std.testing.io, .environ = environment, .directory = null, .artifact = null } },
    };
}

// spec: NEW-CORE-S4-TEST-5
test "receipt settings ignore --threads: a test run with a thread count keys the same as one without (E1c)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    var inputs: std.ArrayList(Dependency) = .empty;
    const plain = try settings(context, &inputs);
    var threaded = context;
    threaded.options.controls.ceilings.threads = 4;
    try std.testing.expectEqual(plain, try settings(threaded, &inputs));
    try std.testing.expectEqualStrings(try executionSettings(context), try executionSettings(threaded));
}

test "receipt settings ignore shell and terminal variables and key toolchain and runtime ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    var inputs: std.ArrayList(Dependency) = .empty;
    const plain = try settings(context, &inputs);
    var other_planner = context;
    other_planner.identity.cache_plan.?.identity[0] ^= 1;
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settings(other_planner, &inputs)));
    var unoptimized = context;
    unoptimized.options.build.mode = .debug;
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settings(unoptimized, &inputs)));
    // A test run's records are the -O0 build's; the lean debug build compiles the same program with other flags and never shares them.
    var lean = context;
    lean.options.build.mode = .lean_debug;
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settings(lean, &inputs)));
    try std.testing.expect(!std.mem.eql(u8, try executionSettings(context), try executionSettings(lean)));
    // A run for the AVX2 floor (`--cpu=x86-64-v3`) compiles other code than a native one and never shares its receipts; a native
    // run's settings carry no CPU word, so they are the bytes they were.
    var floor = context;
    floor.options.build.show.codegen.target = context.options.build.show.codegen.target.forCpu(.x86_64_v3).?;
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settings(floor, &inputs)));
    try std.testing.expect(!std.mem.eql(u8, try executionSettings(context), try executionSettings(floor)));
    try std.testing.expect(std.mem.indexOf(u8, try executionSettings(floor), "cpu=x86-64-v3") != null);
    try std.testing.expect(std.mem.indexOf(u8, try executionSettings(context), "cpu=") == null);
    try environment.put("_", "/usr/bin/time");
    try environment.put("OLDPWD", "/elsewhere");
    try environment.put("SELKA_JOBS", "3");
    try environment.put("SELKA_TEST_ISOLATE", "1");
    try environment.put("SELKA_TEST_CHILDREN", "1");
    try std.testing.expectEqual(plain, try settings(context, &inputs));
    try environment.put("SELKA_OPTIONS", "--allow-random=7");
    const optioned = try settings(context, &inputs);
    try std.testing.expect(!std.mem.eql(u8, &plain, &optioned));
    try environment.put("ZIG_LIB_DIR", "/other-lib");
    try std.testing.expect(!std.mem.eql(u8, &optioned, &try settings(context, &inputs)));
}

/// The toolchain variables the receipt keyed through its own list before the
/// environment identity contract replaced it, two `MYL_`/`SELKA_` samples, and
/// the `SELKA_` and `ZERO_AR_DATE` variables the contract's keyed class adds.
const formerly_keyed = [_][]const u8{
    "CCC_OVERRIDE_OPTIONS", "COMPILER_PATH",     "CPATH",             "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "GCC_EXEC_PREFIX",
    "LIBRARY_PATH",         "OBJC_INCLUDE_PATH", "SOURCE_DATE_EPOCH", "ZIG",            "ZIG_LIB_DIR",        "ZIG_LIBC",
    "SELKA_CORE_TEXTWALK",  "SELKA_OPTIONS",     "SELKA_PROFILE",     "ZERO_AR_DATE",
};
/// The placement variables the receipt ignored before the contract, the
/// verification telemetry directories that once invalidated every receipt, and
/// host-only variables (Python, locale, time zone) no guest outcome depends on.
const never_keyed = [_][]const u8{
    "SELKA_JOBS",                       "SELKA_CORE_RUNTIME_CACHE", "SELKA_COMPILER_SHARED_CACHE", tool_ticket.hint,
    "SELKA_TEST_ISOLATE",               "SELKA_TEST_CHILDREN",      options.shared_cache_variable, "SELKA_TEST_TELEMETRY_DIR",
    "SELKA_VERIFICATION_TELEMETRY_DIR", "_",                        "OLDPWD",                      "PYTHONPATH",
    "LANG",                             "TZ",
};

/// The first name whose `keyedVariable` answer differs from `expected`, or "".
fn firstKeyedMismatch(names: []const []const u8, expected: bool) []const u8 {
    for (names) |name| if (keyedVariable(name) != expected) return name;
    return "";
}

/// `settings` after putting `value` under every name in `names`.
fn settingsWith(context: Context, environment: *std.process.Environ.Map, names: []const []const u8, value: []const u8) !Digest {
    for (names) |name| try environment.put(name, value);
    var inputs: std.ArrayList(Dependency) = .empty;
    return settings(context, &inputs);
}

// spec-case: ENV-IDENTITY-1
test "receipt environment keys what the old lists keyed and never placement, telemetry or host-only variables" {
    try std.testing.expectEqualStrings("", firstKeyedMismatch(&formerly_keyed, true));
    try std.testing.expectEqualStrings("", firstKeyedMismatch(&never_keyed, false));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    const plain = try settingsWith(context, &environment, &.{}, "");
    try std.testing.expectEqual(plain, try settingsWith(context, &environment, &never_keyed, "/per-request/telemetry-1"));
    try std.testing.expectEqual(plain, try settingsWith(context, &environment, &never_keyed, "/per-request/telemetry-2"));
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settingsWith(context, &environment, &.{"SELKA_MEMORY_LIMIT"}, "1G")));
}

test "the environment digest moves with a keyed variable and never with placement or terminal ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    const plain = try environmentDigest(context);
    try environment.put("TMPDIR", "/scratch");
    try environment.put("TERM", "xterm");
    try std.testing.expectEqual(plain, try environmentDigest(context));
    try environment.put("SELKA_MEMORY_LIMIT", "1G");
    const limited = try environmentDigest(context);
    try std.testing.expect(!std.mem.eql(u8, &plain, &limited));
    try environment.put("SELKA_MEMORY_LIMIT", "2G");
    try std.testing.expect(!std.mem.eql(u8, &limited, &try environmentDigest(context)));
}

// spec-case: SELFHOST-CACHE-IDENTITY-1
test "validatePlan returns ComponentUnavailable when a verified component changes before receipt admission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("SELKA_COMPONENT_DIR", root);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache-plan", .data = "original planner" });
    var digest: Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash("original planner", &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const manifest = try std.json.Stringify.valueAlloc(a, .{ .format = 1, .component = "cache-plan", .protocol = 2, .schema = 2, .artifact = "cache-plan", .sha256 = @as([]const u8, &hex) }, .{});
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache-plan.json", .data = manifest });
    var context = try fakeToolContext(a, root, &environment);
    context.identity.cache_plan = try planner.bind(a, std.testing.io, &environment);
    try validatePlan(context);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache-plan", .data = "changed planner" });
    try std.testing.expectError(error.ComponentUnavailable, validatePlan(context));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "receipt campaignSettings excludes only indexed passing budget and binds seed and providers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    var inputs: std.ArrayList(Dependency) = .empty;
    try std.testing.expect(try campaignSettings(context, &inputs) == null);
    const legacy = try settings(context, &inputs);
    context.options.properties.runs += 1;
    try std.testing.expect(!std.mem.eql(u8, &legacy, &try settings(context, &inputs)));
    context.options.properties.policy = .indexed_v1;
    const indexed = (try campaignSettings(context, &inputs)).?;
    context.options.properties.runs += 100;
    try std.testing.expectEqual(indexed, (try campaignSettings(context, &inputs)).?);
    context.options.properties.seed = 17;
    try std.testing.expect(!std.mem.eql(u8, &indexed, &(try campaignSettings(context, &inputs)).?));
    const seeded = (try campaignSettings(context, &inputs)).?;
    context.options.controls.cases = "cases.json";
    context.case_bytes = "provider fixture";
    try std.testing.expect(!std.mem.eql(u8, &seeded, &(try campaignSettings(context, &inputs)).?));
    const provider = (try campaignSettings(context, &inputs)).?;
    context.case_bytes = "changed provider fixture";
    try std.testing.expect(!std.mem.eql(u8, &provider, &(try campaignSettings(context, &inputs)).?));
}

/// `fakeToolContext` with a proved toolchain, so its receipts are admitted.
fn admittedContext(a: std.mem.Allocator, root: []const u8, environment: *const std.process.Environ.Map) !Context {
    var context = try fakeToolContext(a, root, environment);
    context.identity.tool.cacheable = true;
    return context;
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "ownership receipt settings retain constant mode fields across local execution and indexed keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    context.options.properties.policy = .indexed_v1;
    var inputs: std.ArrayList(Dependency) = .empty;
    const local = try settings(context, &inputs);
    const execution = try executionSettings(context);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, execution, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("zero-rc", parsed.value.object.get("single_owner").?.string);
    try std.testing.expectEqualStrings("zero-rc", parsed.value.object.get("zero_rc").?.string);
    const indexed = (try campaignSettings(context, &inputs)).?;
    try std.testing.expect(!std.mem.eql(u8, &local, &indexed));
    try std.testing.expectEqual(local, try settings(context, &inputs));
    try std.testing.expectEqualStrings(execution, try executionSettings(context));
    try std.testing.expectEqual(indexed, (try campaignSettings(context, &inputs)).?);
}

/// A run's IR settings digest and the digest of its execution inputs, the two digests every `test-exec` argument carries.
const ModeKeys = struct { settings: Digest, execution: Digest };

fn modeKeys(context: Context) !ModeKeys {
    var inputs: std.ArrayList(Dependency) = .empty;
    return .{
        .settings = try settings(context, &inputs),
        .execution = try executionInputs(context, try executionSettings(context)),
    };
}

// spec: EXEC-RECEIPT-4
test "fact-verification, leak-check and plain runs are admitted under three distinct keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const plain = try admittedContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    var verified = plain;
    verified.options.build.facts = .verify;
    const plain_keys = try modeKeys(plain);
    const verified_keys = try modeKeys(verified);
    try std.testing.expect(reusable(plain) and reusable(verified));
    try std.testing.expectEqualStrings("no-success-receipt", reuseReason(verified));
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const leak_keys = try modeKeys(plain);
    try std.testing.expect(reusable(plain) and executionReusable(plain));
    try std.testing.expectEqualStrings("no-success-receipt", reuseReason(plain));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.settings, &verified_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.settings, &leak_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &verified_keys.settings, &leak_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.execution, &verified_keys.execution));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.execution, &leak_keys.execution));
    try std.testing.expect(!std.mem.eql(u8, &verified_keys.execution, &leak_keys.execution));
    _ = environment.swapRemove("SELKA_CORE_LEAKCHECK");
    try std.testing.expectEqual(plain_keys.execution, (try modeKeys(plain)).execution);
}

/// A context for `root/app.selka` with a fixed toolchain identity, a fixed tool path and
/// a cache directory outside both roots: only the entry's absolute root varies.
fn rootContext(a: std.mem.Allocator, root: []const u8, cache: []const u8, environment: *const std.process.Environ.Map) !Context {
    return rootContextWith(a, root, cache, .{ .tool = .{ .path = "pinned-zig", .digest = @splat(5), .generation = @splat(0), .native_target = @splat(6), .inputs = 0, .memo_hit = false, .cacheable = true } }, environment);
}

/// `rootContext` with given identities; its cache planner is a fixed reference one.
fn rootContextWith(a: std.mem.Allocator, root: []const u8, cache: []const u8, identities: Identities, environment: *const std.process.Environ.Map) !Context {
    var identity = identities;
    identity.cache_plan = .{ .identity = @splat(11), .mode = .reference, .io = std.testing.io, .environ = environment, .directory = null, .artifact = null };
    return .{
        .arena = a,
        .io = std.testing.io,
        .environment = environment,
        .options = .{ .path = try std.fs.path.join(a, &.{ root, "app.selka" }), .build = .{ .zig = identity.tool.path, .cache = cache }, .controls = .{ .cases = try std.fs.path.join(a, &.{ root, "app.cases.json" }) } },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.selka" }), .root = root, .name = "app" },
        .case_bytes = "{}",
        .identity = identity,
    };
}

// spec: RECEIPT-PATHS-1
test "the settings and IR keys name the root's inputs relative to the root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var left_root = std.testing.tmpDir(.{});
    defer left_root.cleanup();
    var right_root = std.testing.tmpDir(.{});
    defer right_root.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const cache = "shared-receipt-cache";
    const left = try rootContext(a, try left_root.dir.realPathFileAlloc(std.testing.io, ".", a), cache, &environment);
    const right = try rootContext(a, try right_root.dir.realPathFileAlloc(std.testing.io, ".", a), cache, &environment);
    try std.testing.expect(!std.mem.eql(u8, left.entry.root, right.entry.root));
    try std.testing.expectEqualStrings("app.selka", try entryPath(left));
    try std.testing.expectEqualStrings("app.selka", try entryPath(right));
    var inputs: std.ArrayList(Dependency) = .empty;
    const base = try settings(left, &inputs);
    try std.testing.expectEqual(base, try settings(right, &inputs));
    const unmoved: Lines = .{ .shift = 0 };
    const module = try sampleModule(a, 1105, 3);
    const left_key = programKey(base, "app::test_one", .{ .module = &module, .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    const right_key = programKey(try settings(right, &inputs), "app::test_one", .{ .module = &module, .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    try std.testing.expectEqual(left_key, right_key);
}

// spec: TEST-LOOP-ENTRY-FREE-1
test "the settings and IR keys leave out the entry's path; the cases it brings stay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try rootContext(a, try root.dir.realPathFileAlloc(std.testing.io, ".", a), "receipt-cache", &environment);
    var inputs: std.ArrayList(Dependency) = .empty;
    const base = try settings(context, &inputs);
    // Another entry of the same root, with the same cases file and configuration: one test, one key (D-TL2-1).
    var nested = context;
    nested.entry.path = try std.fs.path.join(a, &.{ context.entry.root, "inner", "app.selka" });
    try std.testing.expectEqualStrings("inner/app.selka", try entryPath(nested));
    try std.testing.expectEqual(base, try settings(nested, &inputs));
    // What an entry brings that a pass can depend on still separates two entries: its cases bytes and its cases file (the
    // configuration's path and bytes are keyed as before).
    var other_bytes = nested;
    other_bytes.case_bytes = "{\"app::test_one\":{\"skip\":\"no\"}}";
    try std.testing.expect(!std.mem.eql(u8, &base, &try settings(other_bytes, &inputs)));
    var other_file = nested;
    other_file.options.controls.cases = try std.fs.path.join(a, &.{ context.entry.root, "inner", "app.cases.json" });
    try std.testing.expect(!std.mem.eql(u8, &base, &try settings(other_file, &inputs)));
}

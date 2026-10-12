//! Successful test receipts, in two tiers. The IR tier keys the reachable program's IR
//! and source positions, the compiler and all execution inputs; the execution tier keys
//! the linked program's exact bytes (`driver.Outcome.program_key`), the runner and the
//! same execution inputs, so a compiler edit that leaves a program unchanged still hits.
//! No key names an absolute path. A checked-file manifest only bypasses checking while
//! every dependency still has its recorded bytes. Damaged records are ordinary misses.
const std = @import("std");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const project_entry = @import("project_entry.zig");
const report = @import("test_runner_report.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const emit_units = @import("emit_units.zig");
const emit_llvm = @import("emit_llvm.zig");
const ir = @import("ir.zig");
const Error = @import("test_runner_property.zig").Error;
const Digest = [32]u8;
const planner = @import("mylang").cache_plan_adapter;
const environment_identity = @import("mylang").environment_identity;

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

/// The identities a run's keys bind besides its options: the guest toolchain, the
/// cache planner, the compiler (`compiler`, which the IR tier binds) and the test
/// runner (`runner`, which the execution tier binds). Production takes the build's
/// own; tests substitute others to simulate an edit to either.
pub const Identities = struct {
    tool: tool_identity.Identity,
    cache_plan: ?planner.Bound = null,
    compiler: []const u8 = frontend.compiler_identity,
    runner: []const u8 = frontend.runner_identity,
};
/// A file's exact identity, including absence for optional generated interfaces.
pub const Dependency = struct { path: []const u8, digest: ?Digest };
/// A manifest's payload. `root` is where the run that wrote it was, so a manifest
/// keyed by root-relative paths never replays another root's checked files.
const Snapshot = struct { base: Digest, root: []const u8, dependencies: []const Dependency, report: []const u8, warnings: []const u8 = "" };
const Envelope = struct { version: []const u8, payload: []const u8, checksum: Digest };

/// Complete settings, compiler/runtime/toolchain identity, native inputs and the
/// environment variables that can change an outcome. Field lengths prevent
/// concatenation ambiguities. Every path is relative to the entry's root
/// (RECEIPT-PATHS-1): the private store and the shared store hold the same key.
pub fn settings(context: Context, inputs: *std.ArrayList(Dependency)) Error!Digest {
    return settingsWithBudget(context, inputs, "core-test-settings-v3", context.options.properties.runs);
}

/// Budget-independent settings exist only for the explicit stable indexed generator.
/// The caller binds these settings through the ordinary complete target-closure key.
pub fn campaignSettings(context: Context, inputs: *std.ArrayList(Dependency)) Error!?Digest {
    if (context.options.properties.policy != .indexed_v1) return null;
    const indexed = try settingsWithBudget(context, inputs, "core-property-indexed-settings-v1", 0);
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
/// (`single_owner`, `zero_rc`), build mode, fact mode (`verify` included), code
/// generation choices, the property seed and `runs`, the trial
/// budgets and the leak-check mode (`MYL_CORE_LEAKCHECK`, EXEC-RECEIPT-4), so a
/// fact-verification, a leak-checked and a plain run never share a receipt.
fn settingsJson(context: Context, runs: u32) Error![]const u8 {
    return std.json.Stringify.valueAlloc(context.arena, .{
        .single_owner = context.options.build.show.codegen.single_owner,
        .zero_rc = context.options.build.show.codegen.zero_rc,
        .mode = context.options.build.mode,
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
    }, .{});
}

/// The leak-check mode of the test processes: `MYL_CORE_LEAKCHECK`, `0` when unset.
fn leakCheck(context: Context) []const u8 {
    return context.environment.get("MYL_CORE_LEAKCHECK") orelse "0";
}

/// The serialized settings an execution key binds (`ExecutionInputs.settings`).
pub fn executionSettings(context: Context) Error![]const u8 {
    return settingsJson(context, context.options.properties.runs);
}

fn optionalBytes(hash: *std.crypto.hash.Blake3, role: []const u8, bytes: ?[]const u8) void {
    field(hash, role);
    field(hash, if (bytes != null) "present" else "absent");
    if (bytes) |value| field(hash, value);
}

fn settingsWithBudget(context: Context, inputs: *std.ArrayList(Dependency), domain: []const u8, runs: u32) Error!Digest {
    const a = context.arena;
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, domain);
    if (context.identity.cache_plan) |bound| field(&hash, &bound.identity) else field(&hash, "missing-cache-plan");
    field(&hash, context.identity.compiler);
    field(&hash, try entryPath(context));
    field(&hash, context.options.build.zig);
    field(&hash, &context.identity.tool.digest);
    field(&hash, &context.identity.tool.native_target);
    optionalBytes(&hash, "cases", if (context.options.controls.cases) |path| try rooted(context, path) else null);
    if (context.options.controls.cases != null) field(&hash, context.case_bytes);
    field(&hash, try settingsJson(context, runs));
    if (context.entry.configuration) |configured| {
        field(&hash, try rooted(context, configured.path));
        field(&hash, configured.bytes);
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
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        try inputs.append(a, .{ .path = link, .digest = digest });
    }
    try environmentSettings(context, &hash);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn environmentSettings(context: Context, hash: *std.crypto.hash.Blake3) Error!void {
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
    /// The entry's root-relative path (`entryPath`): what traps report when a span
    /// has no file of its own, named the way every root names it.
    source_path: []const u8,
    /// Where each span is: the only way emission reads the source.
    locator: emit_llvm.Locator,
};

/// A test's program key, computed without emitting it: passes and LLVM emission are
/// pure functions of the IR, the settings in `base` and the positions the locator
/// gives, so the IR is hashed field by field with every span replaced by its file,
/// line and column. An edit that only moves code in other files keeps the key.
pub fn programKey(base: Digest, name: []const u8, program: Program) Digest {
    var walker: Walker = .{ .locator = program.locator };
    field(&walker.hash, "core-test-ir-v3");
    field(&walker.hash, &base);
    field(&walker.hash, name);
    field(&walker.hash, emit_units.native_extension);
    field(&walker.hash, program.source_path);
    walker.value(program.module.*);
    walker.flush();
    var digest: Digest = undefined;
    walker.hash.final(&digest);
    return digest;
}

/// Feeds a value's fields to the hash in declaration order through a small buffer.
const Walker = struct {
    hash: std.crypto.hash.Blake3 = .init(.{}),
    locator: emit_llvm.Locator,
    buffer: [4096]u8 = undefined,
    used: usize = 0,
    last: ?struct { span: u32, at: emit_llvm.Location } = null,

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
                if (comptime std.mem.eql(u8, member, "span") and Member == u32) self.position(@field(item, member)) else self.value(@field(item, member));
            },
            else => @compileError("no receipt hashing for " ++ @typeName(T)),
        }
    }

    fn position(self: *Walker, span: u32) void {
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
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-test-case-v1");
    field(&hash, &program);
    field(&hash, json);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Only an exact, checksummed success record can bypass execution.
pub fn hit(context: Context, identity: Digest) Error!bool {
    if (!reusable(context)) return false;
    return recorded(context, identity);
}

/// An execution-tier lookup: `hit` without the cache planner, which only the IR
/// tier's keys depend on.
pub fn executionHit(context: Context, identity: Digest) Error!bool {
    if (!executionReusable(context)) return false;
    return recorded(context, identity);
}

fn recorded(context: Context, identity: Digest) Error!bool {
    const path = try receiptPath(context, identity);
    const found = std.Io.Dir.cwd().readFileAlloc(context.io, path, context.arena, .limited(4096)) catch return false;
    const expected = try success(context.arena, identity);
    return std.mem.eql(u8, found, expected);
}

/// What an execution receipt binds besides the run's context: the linked program's
/// exact key (`driver.Outcome.program_key`), the test and the serialized settings
/// (`executionSettings`).
pub const ExecutionInputs = struct { program_key: Digest, name: []const u8, settings: []const u8 };

/// A test's execution-tier key (EXEC-RECEIPT-1): the runner's identity, the linked
/// program's exact key, the settings, the test's name, the cases, configuration and
/// policy bytes and the keyed environment. It binds neither the compiler nor the
/// cache planner nor a path: the program key already covers the toolchain, the
/// runtime and every object, so a compiler edit that leaves the program's bytes
/// unchanged keeps it, and a runner edit (EXEC-RECEIPT-2) changes it.
pub fn executionKey(context: Context, inputs: ExecutionInputs) Error!Digest {
    var hash = executionHash(context, "core-test-exec-v3", inputs.program_key, inputs.settings);
    field(&hash, inputs.name);
    return executionFinal(context, &hash);
}

/// One program's execution-tier key for all its ready tests at once
/// (EXEC-RECEIPT-3): `executionKey`'s inputs with the sorted test names in place of
/// one name, so adding, removing or renaming a test misses.
pub fn wholeExecutionKey(context: Context, program_key: Digest, names: []const []const u8, settings_json: []const u8) Error!Digest {
    var hash = executionHash(context, "core-test-whole-exec-v3", program_key, settings_json);
    const sorted = try context.arena.dupe([]const u8, names);
    std.mem.sort([]const u8, sorted, {}, before);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, sorted.len, .little);
    hash.update(&count);
    for (sorted) |name| field(&hash, name);
    return executionFinal(context, &hash);
}

fn executionHash(context: Context, domain: []const u8, program_key: Digest, settings_json: []const u8) std.crypto.hash.Blake3 {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, domain);
    field(&hash, context.identity.runner);
    field(&hash, &program_key);
    field(&hash, settings_json);
    optionalBytes(&hash, "cases", if (context.options.controls.cases != null) context.case_bytes else null);
    const configured = context.entry.configuration;
    optionalBytes(&hash, "configuration", if (configured) |found| found.bytes else null);
    optionalBytes(&hash, "policy", if (configured) |found| if (found.policy) |policy| policy.bytes else null else null);
    return hash;
}

fn executionFinal(context: Context, hash: *std.crypto.hash.Blake3) Error!Digest {
    try environmentSettings(context, hash);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Publish successes atomically; a failed run never writes a receipt.
pub fn save(context: Context, identity: Digest) Error!void {
    try atomic(context, try receiptPath(context, identity), try success(context.arena, identity));
}

/// A validated report and the warnings to emit only when the caller accepts it.
pub const Replay = struct { report: []const u8, warnings: []const u8 };

/// Look up a complete successful file run after resolving configuration anew.
pub fn replay(context: Context, base: Digest) Error!?Replay {
    if (!reusable(context)) return null;
    if (!try toolUnchanged(context)) return null;
    return replayProvisional(context, base);
}

/// Read-only replay for a verified same-compiler parent ticket. The parent must
/// validate its full tool generation before accepting any borrowed child result.
/// A miss must establish a local identity before checking or cache publication.
pub fn replayProvisional(context: Context, base: Digest) Error!?Replay {
    if (!reusable(context)) return null;
    if (context.entry.configuration) |configured| if (configured.document.interface_files) return null;
    const a = context.arena;
    const path = try manifestPath(context);
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, path, a, .limited(64 << 20)) catch return null;
    const envelope = std.json.parseFromSliceLeaky(Envelope, a, bytes, .{}) catch return null;
    if (!std.mem.eql(u8, envelope.version, manifest_version)) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(envelope.payload, &checksum, .{});
    if (!std.mem.eql(u8, &checksum, &envelope.checksum)) return null;
    const snapshot = std.json.parseFromSliceLeaky(Snapshot, a, envelope.payload, .{}) catch return null;
    if (!std.mem.eql(u8, &snapshot.base, &base) or !std.mem.eql(u8, snapshot.root, context.entry.root)) return null;
    if (!try unchanged(context, snapshot.dependencies)) return null;
    var value = std.json.parseFromSliceLeaky(std.json.Value, a, snapshot.report, .{}) catch return null;
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
        try explanation.put(a, "reason", .{ .string = "whole-report-hit" });
        try explanation.put(a, "component", .{ .string = try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(context.identity.cache_plan.?.identity, .lower)}) });
        try explanation.put(a, "key_method", .{ .string = "checked-file-manifest" });
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
    if (context.options.json) {
        const encoded = try std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, value, .{})});
        return .{ .report = encoded, .warnings = snapshot.warnings };
    }
    const verdicts = try a.alloc(report.Verdict, tests.array.items.len);
    for (tests.array.items, verdicts) |test_value, *verdict| {
        const name = test_value.object.get("name") orelse return null;
        if (name != .string) return null;
        verdict.* = .{ .name = name.string, .status = .cached };
    }
    const rendered = try report.text(a, verdicts);
    return .{ .report = rendered, .warnings = snapshot.warnings };
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
        try loaded(context, &files, context.entry.path, unit.src, session.entry_suffix, false);
    } else for (session.project.modules.items) |*module| try moduleInputs(context, &files, module, .{ .suffix = session.entry_suffix, .providers = providers });
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
        const api = try std.fmt.allocPrint(a, "{s}.api", .{path[0 .. path.len - 3]});
        try files.append(a, .{ .path = api, .digest = try fileDigest(context, api) });
    };
}

/// Append the cases file, configuration and policy a run read to `files`.
fn settingsInputs(context: Context, files: *std.ArrayList(Dependency)) Error![]const Dependency {
    const a = context.arena;
    if (context.options.controls.cases) |path| {
        var digest: Digest = undefined;
        std.crypto.hash.Blake3.hash(context.case_bytes, &digest, .{});
        try files.append(a, .{ .path = path, .digest = digest });
    }
    if (context.entry.configuration) |configured| {
        var digest: Digest = undefined;
        std.crypto.hash.Blake3.hash(configured.bytes, &digest, .{});
        try files.append(a, .{ .path = configured.path, .digest = digest });
        if (configured.policy) |policy| {
            std.crypto.hash.Blake3.hash(policy.bytes, &digest, .{});
            try files.append(a, .{ .path = policy.path, .digest = digest });
        }
    }
    return files.items;
}

fn loaded(context: Context, files: *std.ArrayList(Dependency), path: []const u8, source: @import("mylang").source.Source, suffix: []const u8, overridden: bool) Error!void {
    const a = context.arena;
    const bytes = if (suffix.len != 0 and std.mem.endsWith(u8, source.bytes, suffix)) source.bytes[0 .. source.bytes.len - suffix.len] else source.bytes;
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
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

/// Save a manifest only after all selected tests succeeded under unchanged inputs.
pub fn remember(context: Context, base: Digest, files: []const Dependency, json: []const u8, warnings: []const u8) Error!void {
    if (!try unchanged(context, files) or !try toolUnchanged(context)) return;
    const payload = try std.json.Stringify.valueAlloc(context.arena, Snapshot{ .base = base, .root = context.entry.root, .dependencies = files, .report = json, .warnings = warnings }, .{});
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &checksum, .{});
    const envelope: Envelope = .{ .version = manifest_version, .payload = payload, .checksum = checksum };
    try atomic(context, try manifestPath(context), try std.json.Stringify.valueAlloc(context.arena, envelope, .{}));
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
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return digest;
}
const manifest_version = "core-test-manifest-v3";
fn receiptPath(context: Context, identity: Digest) Error![]const u8 {
    return std.fmt.allocPrint(context.arena, "{s}/tests/receipts-v3/{s}", .{ context.options.build.cache, std.fmt.bytesToHex(identity, .lower) });
}
/// Which manifest a run reads and writes: its root-relative entry, filter and cases.
fn manifestKey(context: Context) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, try entryPath(context));
    field(&hash, context.options.filter);
    field(&hash, if (context.options.controls.cases) |path| try rooted(context, path) else "");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn manifestPath(context: Context) Error![]const u8 {
    return std.fmt.allocPrint(context.arena, "{s}/tests/manifests-v3/{s}.json", .{ context.options.build.cache, std.fmt.bytesToHex(try manifestKey(context), .lower) });
}
fn success(a: std.mem.Allocator, identity: Digest) Error![]const u8 {
    const payload = try std.fmt.allocPrint(a, "core-test-receipt-v3\n{s}\npassed\n", .{std.fmt.bytesToHex(identity, .lower)});
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &checksum, .{});
    return std.fmt.allocPrint(a, "{s}{s}\n", .{ payload, std.fmt.bytesToHex(checksum, .lower) });
}
fn atomic(context: Context, path: []const u8, bytes: []const u8) Error!void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(context.io, std.fs.path.dirname(path).?) catch return error.WriteFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(context.io, &nonce);
    const temporary = try std.fmt.allocPrint(context.arena, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer deletePartial(context.io, temporary);
    cwd.writeFile(context.io, .{ .sub_path = temporary, .data = bytes }) catch return error.WriteFailed;
    cwd.rename(temporary, cwd, path, context.io) catch return error.WriteFailed;
}
fn field(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
fn before(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

/// Test positions: files of 1000 bytes and 100-byte lines, `a.my` first; `shift` is
/// how far an edit to `a.my` moved `b.my`.
const Lines = struct {
    shift: u32,
    fn locate(context: *const anyopaque, offset: u32) emit_llvm.Location {
        const self: *const Lines = @ptrCast(@alignCast(context));
        const in_b = offset >= 1000 + self.shift;
        const local = if (in_b) offset - 1000 - self.shift else offset;
        return .{ .line = local / 100 + 1, .column = local % 100 + 1, .path = if (in_b) "b.my" else "a.my" };
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
    const one = programKey(base, "ab", .{ .module = &module, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    const moved = try sampleModule(a, 1305, 3);
    try std.testing.expectEqual(one, programKey(base, "ab", .{ .module = &moved, .source_path = "app.my", .locator = .{ .context = &shifted, .locate = Lines.locate } }));
    const line = try sampleModule(a, 1205, 3);
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &line, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    const data = try sampleModule(a, 1105, 4);
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &data, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    var named = try sampleModule(a, 1105, 3);
    named.strings.items[0] = "texts";
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &named, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "a", .{ .module = &module, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(base, "ab", .{ .module = &module, .source_path = "other.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
    try std.testing.expect(!std.mem.eql(u8, &one, &programKey(@splat(8), "ab", .{ .module = &module, .source_path = "app.my", .locator = .{ .context = &unmoved, .locate = Lines.locate } })));
}

// spec-case: NEW-CORE-S4-TEST-3
test "receipt keys bind declarative cases" {
    const original: Digest = @splat(7);
    const configured = configuredKey(original, "{\"expected\":7}");
    try std.testing.expect(!std.mem.eql(u8, &configured, &configuredKey(original, "{\"expected\":8}")));
    try std.testing.expect(!std.mem.eql(u8, &configured, &configuredKey(@splat(8), "{\"expected\":7}")));
}

fn deletePartial(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

// spec-case: NEW-CORE-S4-TEST-3
test "readDigest fileDigest and toolUnchanged refuse missing inputs and damaged receipts and manifests become misses" {
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
        .options = .{ .path = "app.my", .build = .{ .zig = tool, .cache = root }, .json = true },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.my" }), .root = root, .name = "app" },
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
    const identity: Digest = @splat(3);
    try save(context, identity);
    try std.testing.expect(try hit(context, identity));
    try environment.put("LD_PRELOAD", "/mutable-library.so");
    try std.testing.expect(!try hit(context, identity));
    try environment.put("LD_PRELOAD", "");
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = try receiptPath(context, identity), .data = "damaged" });
    try std.testing.expect(!try hit(context, identity));
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = context.entry.path, .data = "source" });
    const files = try dependencies(context, &.{context.entry.path});
    const valid = try report.jsonSources(a, &.{.{ .name = "app::test_one", .status = .passed }}, &.{context.entry.path});
    try remember(context, identity, files, valid, "");
    try std.testing.expect(try replay(context, identity) != null);
    const replayed = (try replayProvisional(context, identity)).?;
    const parsed_replay = try std.json.parseFromSliceLeaky(std.json.Value, a, replayed.report, .{});
    const explanation = parsed_replay.object.get("tests").?.array.items[0].object.get("cache").?;
    try std.testing.expectEqualStrings("whole-report-hit", explanation.object.get("reason").?.string);
    try std.testing.expectEqualStrings("reuse", explanation.object.get("action").?.string);
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = context.entry.path, .data = "edited" });
    try std.testing.expect(try replay(context, identity) == null);
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = try manifestPath(context), .data = "damaged" });
    try std.testing.expect(try replay(context, identity) == null);
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
        .options = .{ .path = "app.my", .build = .{ .zig = tool, .cache = root }, .json = true },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.my" }), .root = root, .name = "app" },
        .identity = .{ .tool = identity, .cache_plan = .{ .identity = @splat(11), .mode = .reference, .io = std.testing.io, .environ = environment, .directory = null, .artifact = null } },
    };
}

// spec: NEW-CORE-S4-TEST-5
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
    try environment.put("_", "/usr/bin/time");
    try environment.put("OLDPWD", "/elsewhere");
    try environment.put("MYLANG_JOBS", "3");
    try environment.put("MYLANG_TEST_ISOLATE", "1");
    try environment.put("MYLANG_TEST_CHILDREN", "1");
    try std.testing.expectEqual(plain, try settings(context, &inputs));
    try environment.put("MYLANG_OPTIONS", "--allow-random=7");
    const optioned = try settings(context, &inputs);
    try std.testing.expect(!std.mem.eql(u8, &plain, &optioned));
    try environment.put("ZIG_LIB_DIR", "/other-lib");
    try std.testing.expect(!std.mem.eql(u8, &optioned, &try settings(context, &inputs)));
}

/// The toolchain variables the receipt keyed through its own list before the
/// environment identity contract replaced it, two `MYL_`/`MYLANG_` samples, and
/// the `SELKA_` and `ZERO_AR_DATE` variables the contract's keyed class adds.
const formerly_keyed = [_][]const u8{
    "CCC_OVERRIDE_OPTIONS", "COMPILER_PATH",     "CPATH",             "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "GCC_EXEC_PREFIX",
    "LIBRARY_PATH",         "OBJC_INCLUDE_PATH", "SOURCE_DATE_EPOCH", "ZIG",            "ZIG_LIB_DIR",        "ZIG_LIBC",
    "MYL_CORE_TEXTWALK",    "MYLANG_OPTIONS",    "SELKA_PROFILE",     "ZERO_AR_DATE",
};
/// The placement variables the receipt ignored before the contract, the
/// verification telemetry directories that once invalidated every receipt, and
/// host-only variables (Python, locale, time zone) no guest outcome depends on.
const never_keyed = [_][]const u8{
    "MYLANG_JOBS",                      "MYLANG_CORE_RUNTIME_CACHE", "MYLANG_COMPILER_SHARED_CACHE", tool_ticket.hint,
    "MYLANG_TEST_ISOLATE",              "MYLANG_TEST_CHILDREN",      options.shared_cache_variable,  "MYLANG_TEST_TELEMETRY_DIR",
    "SELKA_VERIFICATION_TELEMETRY_DIR", "_",                         "OLDPWD",                       "PYTHONPATH",
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
    try std.testing.expect(!std.mem.eql(u8, &plain, &try settingsWith(context, &environment, &.{"MYLANG_MEMORY_LIMIT"}, "1G")));
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
    try environment.put("MYLANG_COMPONENT_DIR", root);
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

// spec: EXEC-RECEIPT-1
test "execution receipts key the linked program, not the compiler, and hit after a compiler edit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var context = try admittedContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    context.identity.compiler = "compiler before a front-end comment edit";
    var edited = context;
    edited.identity.compiler = "compiler after a front-end comment edit";
    const inputs: ExecutionInputs = .{ .program_key = @splat(4), .name = "app::test_one", .settings = try executionSettings(context) };
    const key = try executionKey(context, inputs);
    try std.testing.expectEqual(key, try executionKey(edited, inputs));
    var ir_inputs: std.ArrayList(Dependency) = .empty;
    try std.testing.expect(!std.mem.eql(u8, &try settings(context, &ir_inputs), &try settings(edited, &ir_inputs)));
    try std.testing.expect(!try executionHit(edited, key));
    try save(context, key);
    try std.testing.expect(try executionHit(edited, key));
    edited.identity.cache_plan = null;
    try std.testing.expect(try executionHit(edited, key));
    try std.testing.expect(!try hit(edited, key));
    try std.testing.expectEqualStrings("missing-cache-plan", reuseReason(edited));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "zero RC test receipts isolate local, execution and indexed ownership modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var context = try fakeToolContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    var inputs: std.ArrayList(Dependency) = .empty;
    context.options.properties.policy = .indexed_v1;
    const plain = try settings(context, &inputs);
    const execution_plain = try executionSettings(context);
    const indexed_plain = (try campaignSettings(context, &inputs)).?;
    context.options.build.show.codegen.single_owner = true;
    const single = try settings(context, &inputs);
    try std.testing.expect(!std.mem.eql(u8, &plain, &single));
    context.options.build.show.codegen.zero_rc = true;
    const owned = try settings(context, &inputs);
    try std.testing.expect(!std.mem.eql(u8, &single, &owned));
    try std.testing.expect(!std.mem.eql(u8, &plain, &owned));
    try std.testing.expect(!std.mem.eql(u8, execution_plain, try executionSettings(context)));
    try std.testing.expect(!std.mem.eql(u8, &indexed_plain, &(try campaignSettings(context, &inputs)).?));
}

// spec: EXEC-RECEIPT-2
test "execution receipts miss after a runner edit and for another program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try admittedContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    const inputs: ExecutionInputs = .{ .program_key = @splat(4), .name = "app::test_one", .settings = try executionSettings(context) };
    const key = try executionKey(context, inputs);
    try save(context, key);
    var runner = context;
    runner.identity.runner = "runner after an edit to test_runner_execute.zig";
    const moved = try executionKey(runner, inputs);
    try std.testing.expect(!std.mem.eql(u8, &key, &moved));
    try std.testing.expect(!try executionHit(runner, moved));
    var relinked = inputs;
    relinked.program_key = @splat(5);
    try std.testing.expect(!try executionHit(context, try executionKey(context, relinked)));
    var renamed = inputs;
    renamed.name = "app::test_two";
    try std.testing.expect(!try executionHit(context, try executionKey(context, renamed)));
    var forced = context;
    forced.options.controls.force = true;
    try std.testing.expect(!try executionHit(forced, key));
    try std.testing.expect(try executionHit(context, key));
}

// spec: EXEC-RECEIPT-3
test "whole-program execution keys cover the sorted ready test names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context = try admittedContext(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), &environment);
    const program: Digest = @splat(6);
    const json = try executionSettings(context);
    const whole = try wholeExecutionKey(context, program, &.{ "app::test_b", "app::test_a" }, json);
    try std.testing.expectEqual(whole, try wholeExecutionKey(context, program, &.{ "app::test_a", "app::test_b" }, json));
    try std.testing.expect(!std.mem.eql(u8, &whole, &try wholeExecutionKey(context, program, &.{ "app::test_a", "app::test_b", "app::test_c" }, json)));
    try std.testing.expect(!std.mem.eql(u8, &whole, &try wholeExecutionKey(context, @splat(7), &.{ "app::test_a", "app::test_b" }, json)));
    const single = try wholeExecutionKey(context, program, &.{"app::test_a"}, json);
    try std.testing.expect(!std.mem.eql(u8, &single, &try executionKey(context, .{ .program_key = program, .name = "app::test_a", .settings = json })));
    try save(context, whole);
    try std.testing.expect(try executionHit(context, try wholeExecutionKey(context, program, &.{ "app::test_a", "app::test_b" }, json)));
    try std.testing.expect(!try executionHit(context, try wholeExecutionKey(context, program, &.{ "app::test_a", "app::test_b", "app::test_c" }, json)));
}

/// A run's IR settings and execution key for program `@splat(8)`'s `app::test_one`.
const ModeKeys = struct { settings: Digest, execution: Digest };

fn modeKeys(context: Context) !ModeKeys {
    var inputs: std.ArrayList(Dependency) = .empty;
    return .{
        .settings = try settings(context, &inputs),
        .execution = try executionKey(context, .{ .program_key = @splat(8), .name = "app::test_one", .settings = try executionSettings(context) }),
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
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const leak_keys = try modeKeys(plain);
    try std.testing.expect(reusable(plain) and executionReusable(plain));
    try std.testing.expectEqualStrings("no-success-receipt", reuseReason(plain));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.settings, &verified_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.settings, &leak_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &verified_keys.settings, &leak_keys.settings));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.execution, &verified_keys.execution));
    try std.testing.expect(!std.mem.eql(u8, &plain_keys.execution, &leak_keys.execution));
    try std.testing.expect(!std.mem.eql(u8, &verified_keys.execution, &leak_keys.execution));
    try save(plain, leak_keys.execution);
    _ = environment.swapRemove("MYL_CORE_LEAKCHECK");
    try std.testing.expect(!try executionHit(plain, plain_keys.execution));
    try std.testing.expect(!try executionHit(verified, verified_keys.execution));
}

/// A context for `root/app.my` with a fixed toolchain identity, a fixed tool path and
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
        .options = .{ .path = try std.fs.path.join(a, &.{ root, "app.my" }), .build = .{ .zig = identity.tool.path, .cache = cache }, .controls = .{ .cases = try std.fs.path.join(a, &.{ root, "app.cases.json" }) } },
        .entry = .{ .path = try std.fs.path.join(a, &.{ root, "app.my" }), .root = root, .name = "app" },
        .case_bytes = "{}",
        .identity = identity,
    };
}

// spec: RECEIPT-PATHS-1
test "receipt settings, manifest and IR keys name the entry relative to its root" {
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
    try std.testing.expectEqualStrings("app.my", try entryPath(left));
    try std.testing.expectEqualStrings("app.my", try entryPath(right));
    var inputs: std.ArrayList(Dependency) = .empty;
    const base = try settings(left, &inputs);
    try std.testing.expectEqual(base, try settings(right, &inputs));
    try std.testing.expectEqual(try manifestKey(left), try manifestKey(right));
    const unmoved: Lines = .{ .shift = 0 };
    const module = try sampleModule(a, 1105, 3);
    const left_key = programKey(base, "app::test_one", .{ .module = &module, .source_path = try entryPath(left), .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    const right_key = programKey(try settings(right, &inputs), "app::test_one", .{ .module = &module, .source_path = try entryPath(right), .locator = .{ .context = &unmoved, .locate = Lines.locate } });
    try std.testing.expectEqual(left_key, right_key);
    var nested = right;
    nested.entry.path = try std.fs.path.join(a, &.{ right.entry.root, "inner", "app.my" });
    try std.testing.expectEqualStrings("inner/app.my", try entryPath(nested));
    try std.testing.expect(!std.mem.eql(u8, &base, &try settings(nested, &inputs)));
    try std.testing.expect(!std.mem.eql(u8, &try manifestKey(left), &try manifestKey(nested)));
}

// spec-case: RECEIPT-PATHS-1
test "a root-relative manifest never replays another root's checked files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var left_root = std.testing.tmpDir(.{});
    defer left_root.cleanup();
    var right_root = std.testing.tmpDir(.{});
    defer right_root.cleanup();
    var cache_root = std.testing.tmpDir(.{});
    defer cache_root.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const cache = try cache_root.dir.realPathFileAlloc(std.testing.io, ".", a);
    // One owned fake toolchain, so `remember` can revalidate it before publishing.
    var tool = (try fakeToolContext(a, cache, &environment)).identity.tool;
    tool.cacheable = true;
    const left = try rootContextWith(a, try left_root.dir.realPathFileAlloc(std.testing.io, ".", a), cache, .{ .tool = tool }, &environment);
    const right = try rootContextWith(a, try right_root.dir.realPathFileAlloc(std.testing.io, ".", a), cache, .{ .tool = tool }, &environment);
    try left_root.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "left source" });
    try right_root.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "right source" });
    var inputs: std.ArrayList(Dependency) = .empty;
    const base = try settings(left, &inputs);
    const files = try dependencies(left, &.{left.entry.path});
    const passed = try report.jsonSources(a, &.{.{ .name = "app::test_one", .status = .passed }}, &.{left.entry.path});
    try remember(left, base, files, passed, "");
    try std.testing.expect(try replayProvisional(left, base) != null);
    try std.testing.expectEqualStrings(try manifestPath(left), try manifestPath(right));
    try std.testing.expect(try replayProvisional(right, base) == null);
}

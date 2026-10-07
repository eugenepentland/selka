//! Successful test receipts key the reachable emitted program and all execution
//! inputs. A checked-file manifest only bypasses checking while every dependency
//! still has its recorded bytes. Damaged records are ordinary cache misses.
const std = @import("std");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const project_entry = @import("project_entry.zig");
const report = @import("test_runner_report.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const emit_units = @import("emit_units.zig");
const Error = @import("test_runner_property.zig").Error;
const Digest = [32]u8;

/// Command resources and freshly resolved project configuration.
pub const Context = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    options: options.Options,
    entry: project_entry.Entry,
    case_bytes: []const u8 = "",
    tool: tool_identity.Identity,
};
/// A file's exact identity, including absence for optional generated interfaces.
pub const Dependency = struct { path: []const u8, digest: ?Digest };
const Snapshot = struct { base: Digest, dependencies: []const Dependency, report: []const u8 };
const Envelope = struct { version: []const u8, payload: []const u8, checksum: Digest };

/// Complete settings, compiler/runtime/toolchain identity, native inputs and
/// guest environment. Field lengths prevent concatenation ambiguities.
pub fn settings(context: Context, inputs: *std.ArrayList(Dependency)) Error!Digest {
    const a = context.arena;
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-test-settings-v4");
    field(&hash, frontend.compiler_identity);
    field(&hash, context.entry.path);
    field(&hash, context.entry.root);
    field(&hash, context.options.build.zig);
    field(&hash, &context.tool.digest);
    if (context.options.controls.cases) |path| {
        field(&hash, path);
        field(&hash, context.case_bytes);
    }
    field(&hash, try std.json.Stringify.valueAlloc(a, .{
        .release = context.options.build.release,
        .facts = context.options.build.facts,
        .vectors = context.options.build.show.generic_vectors,
        .frames = context.options.build.show.trap_frames,
        .seed = context.options.seed,
        .runs = context.options.property_runs,
        .timeout = context.options.controls.timeout_ms,
        .steps = context.options.controls.max_steps,
        .call_frames = context.options.controls.ceilings.frames,
        .memory = context.options.controls.ceilings.memory,
    }, .{}));
    if (context.entry.configuration) |configured| {
        field(&hash, configured.path);
        field(&hash, configured.bytes);
        if (configured.policy) |policy| {
            field(&hash, policy.path);
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
    var environment: std.ArrayList([]const u8) = .empty;
    var entries = context.environment.iterator();
    while (entries.next()) |item| {
        if (std.mem.eql(u8, item.key_ptr.*, tool_ticket.hint)) continue;
        try environment.append(a, try std.fmt.allocPrint(a, "{s}={s}", .{ item.key_ptr.*, item.value_ptr.* }));
    }
    std.mem.sort([]const u8, environment.items, {}, before);
    for (environment.items) |item| field(&hash, item);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Bind every native unit in its emitted order, including canonical filenames
/// and dependency flags; LLVM includes the copied-value schema and seed adapter.
pub fn key(base: Digest, name: []const u8, units: []const emit_units.Unit) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-test-program-v2");
    field(&hash, &base);
    field(&hash, name);
    field(&hash, emit_units.native_extension);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, @intCast(units.len), .little);
    field(&hash, &count);
    for (units) |unit| {
        field(&hash, unit.name);
        field(&hash, unit.source_path);
        field(&hash, @tagName(unit.kind));
        field(&hash, unit.llvm);
        field(&hash, if (unit.number) "number" else "no-number");
        field(&hash, if (unit.math) "math" else "no-math");
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

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
    const path = try receiptPath(context, identity);
    const found = std.Io.Dir.cwd().readFileAlloc(context.io, path, context.arena, .limited(4096)) catch return false;
    const expected = try success(context.arena, identity);
    return std.mem.eql(u8, found, expected);
}

/// Publish successes atomically; a failed run never writes a receipt.
pub fn save(context: Context, identity: Digest) Error!void {
    try atomic(context, try receiptPath(context, identity), try success(context.arena, identity));
}

/// Look up a complete successful file run after resolving configuration anew.
pub fn replay(context: Context, base: Digest) Error!?[]const u8 {
    if (!reusable(context)) return null;
    if (!try toolUnchanged(context)) return null;
    return replayProvisional(context, base);
}

/// Read-only replay for a verified same-compiler parent ticket. The parent must
/// validate its full tool generation before accepting any borrowed child result.
/// A miss must establish a local identity before checking or cache publication.
pub fn replayProvisional(context: Context, base: Digest) Error!?[]const u8 {
    if (!reusable(context)) return null;
    if (context.entry.configuration) |configured| if (configured.document.interface_files) return null;
    const a = context.arena;
    const path = try manifestPath(context);
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, path, a, .limited(64 << 20)) catch return null;
    const envelope = std.json.parseFromSliceLeaky(Envelope, a, bytes, .{}) catch return null;
    if (!std.mem.eql(u8, envelope.version, "core-test-manifest-v2")) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(envelope.payload, &checksum, .{});
    if (!std.mem.eql(u8, &checksum, &envelope.checksum)) return null;
    const snapshot = std.json.parseFromSliceLeaky(Snapshot, a, envelope.payload, .{}) catch return null;
    if (!std.mem.eql(u8, &snapshot.base, &base) or !try unchanged(context, snapshot.dependencies)) return null;
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
    }
    try value.object.put(a, "passed", .{ .integer = 0 });
    try value.object.put(a, "cached", .{ .integer = @intCast(tests.array.items.len) });
    if (context.options.json) {
        const encoded = try std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, value, .{})});
        return encoded;
    }
    const verdicts = try a.alloc(report.Verdict, tests.array.items.len);
    for (tests.array.items, verdicts) |test_value, *verdict| {
        const name = test_value.object.get("name") orelse return null;
        if (name != .string) return null;
        verdict.* = .{ .name = name.string, .status = .cached };
    }
    const rendered = try report.text(a, verdicts);
    return rendered;
}

// Explicit native links may include headers not captured by this runner. Until
// the driver supplies their complete dependency set, run them every time.
fn reusable(context: Context) bool {
    if (!context.tool.cacheable) return false;
    if (context.options.controls.force or context.options.build.facts == .verify or context.options.build.links.len != 0) return false;
    const checking = context.environment.get("MYL_CORE_LEAKCHECK") orelse "0";
    if (!std.mem.eql(u8, checking, "0")) return false;
    var entries = context.environment.iterator();
    while (entries.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "LD_") and entry.value_ptr.len != 0) return false;
    }
    return true;
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
    const a = context.arena;
    var files: std.ArrayList(Dependency) = .empty;
    if (session.single) |unit| {
        try loaded(context, &files, context.entry.path, unit.src, session.entry_suffix, false);
    } else for (session.project.modules.items) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const path = try std.fs.path.join(a, &.{ context.entry.root, module.src.path });
        var overridden = false;
        for (providers) |provider| overridden = overridden or std.mem.eql(u8, module.src.path, provider.path);
        try loaded(context, &files, path, module.src, if (std.mem.eql(u8, module.name, context.entry.name)) session.entry_suffix else "", overridden);
        if (context.entry.configuration) |configured| if (configured.document.interface_files) {
            const api = try std.fmt.allocPrint(a, "{s}.api", .{path[0 .. path.len - 3]});
            try files.append(a, .{ .path = api, .digest = try fileDigest(context, api) });
        };
    }
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
pub fn remember(context: Context, base: Digest, files: []const Dependency, json: []const u8) Error!void {
    if (!try unchanged(context, files) or !try toolUnchanged(context)) return;
    const payload = try std.json.Stringify.valueAlloc(context.arena, Snapshot{ .base = base, .dependencies = files, .report = json }, .{});
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &checksum, .{});
    const envelope: Envelope = .{ .version = "core-test-manifest-v2", .payload = payload, .checksum = checksum };
    try atomic(context, try manifestPath(context), try std.json.Stringify.valueAlloc(context.arena, envelope, .{}));
}

/// The captured executable, CPU and library tree must remain the same generation.
pub fn toolUnchanged(context: Context) Error!bool {
    return tool_identity.unchanged(.{ .arena = context.arena, .io = context.io, .environment = context.environment, .executable = context.options.build.zig, .cache = context.options.build.cache }, context.tool) catch |err| {
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
fn receiptPath(context: Context, identity: Digest) Error![]const u8 {
    return std.fmt.allocPrint(context.arena, "{s}/tests/receipts-v2/{s}", .{ context.options.build.cache, std.fmt.bytesToHex(identity, .lower) });
}
fn manifestPath(context: Context) Error![]const u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, context.entry.path);
    field(&hash, context.options.filter);
    field(&hash, context.options.controls.cases orelse "");
    var digest: Digest = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(context.arena, "{s}/tests/manifests-v2/{s}.json", .{ context.options.build.cache, std.fmt.bytesToHex(digest, .lower) });
}
fn success(a: std.mem.Allocator, identity: Digest) Error![]const u8 {
    const payload = try std.fmt.allocPrint(a, "core-test-receipt-v2\n{s}\npassed\n", .{std.fmt.bytesToHex(identity, .lower)});
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

// spec-case: NEW-CORE-S4-TEST-3
test "receipt keys delimit fields and include the exact ordered native units" {
    const base: Digest = @splat(9);
    const first: emit_units.Unit = .{ .name = "module-a", .source_path = "a.my", .kind = .module, .llvm = "c", .number = false, .math = false };
    const second: emit_units.Unit = .{ .name = "entry", .source_path = "entry", .kind = .entry, .llvm = "entry", .number = false, .math = false };
    const one = key(base, "ab", &.{first});
    var changed = first;
    changed.llvm = "bc";
    try std.testing.expect(!std.mem.eql(u8, &one, &key(base, "a", &.{changed})));
    changed.llvm = "changed";
    try std.testing.expect(!std.mem.eql(u8, &one, &key(base, "ab", &.{changed})));
    const ordered = key(base, "ab", &.{ first, second });
    try std.testing.expect(!std.mem.eql(u8, &one, &ordered));
    try std.testing.expect(!std.mem.eql(u8, &ordered, &key(base, "ab", &.{ second, first })));
    try std.testing.expect(!std.mem.eql(u8, &one, &key(@splat(8), "ab", &.{first})));
}

// spec-case: NEW-CORE-S4-TEST-3
test "receipt keys bind canonical basenames unit metadata dependencies and declarative cases" {
    const base: Digest = @splat(7);
    const unit: emit_units.Unit = .{ .name = "module-a", .source_path = "a.my", .kind = .module, .llvm = "program", .number = false, .math = false };
    const original = key(base, "test", &.{unit});
    var changed = [_]emit_units.Unit{ unit, unit, unit, unit, unit };
    changed[0].name = "module-b";
    changed[1].source_path = "b.my";
    changed[2].kind = .helper;
    changed[3].number = true;
    changed[4].math = true;
    for (changed) |other| try std.testing.expect(!std.mem.eql(u8, &original, &key(base, "test", &.{other})));
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
        .tool = captured_tool,
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
    try remember(context, identity, files, valid);
    try std.testing.expect(try replay(context, identity) != null);
    try std.testing.expect(try replayProvisional(context, identity) != null);
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = context.entry.path, .data = "edited" });
    try std.testing.expect(try replay(context, identity) == null);
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = try manifestPath(context), .data = "damaged" });
    try std.testing.expect(try replay(context, identity) == null);
    try temporary.dir.deleteFile(context.io, "zig");
    try std.testing.expect(!try toolUnchanged(context));
}

//! Command-scoped compiler artifact policy, independent of guest execution.
const std = @import("std");
const artifacts = @import("mylang").shared_artifact_store;
const policy = @import("mylang").shared_cache_policy;

/// Explicitly configured storage failures are host failures with a diagnosis.
pub const Error = error{ OutOfMemory, WriteFailed };

/// Disable sharing in a command-owned environment or validate it before replay.
/// The original environment remains available to the executed guest program.
pub fn prepare(init: std.process.Init, disabled: bool) Error!std.process.Init {
    return prepareWith(init, disabled, policy.default_sharing);
}

// `sharing` is the default-location switch, a parameter so tests cover both
// positions. An unusable explicit store fails the command; an unusable default
// store prints one warning and the command builds without sharing. A usable
// default is written into the command's environment, so every later lookup in
// this command sees one resolved store.
fn prepareWith(init: std.process.Init, disabled: bool, sharing: bool) Error!std.process.Init {
    if (disabled) return withStore(init, "");
    const a = init.arena.allocator();
    const selection = try policy.resolveWith(a, init.environ_map, .compiler, null, sharing) orelse return init;
    var store = artifacts.Store.open(init.gpa, init.io, selection.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        var buffer: [512]u8 = undefined;
        if (selection.origin == .default) {
            const warning = std.fmt.bufPrint(&buffer, "warning: shared compiler cache {s}: {s}; sharing disabled\n", .{ selection.path, @errorName(err) }) catch "warning: shared compiler cache unusable; sharing disabled\n";
            std.Io.File.stderr().writeStreamingAll(init.io, warning) catch return error.WriteFailed;
            return withStore(init, "");
        }
        const text = std.fmt.bufPrint(&buffer, "error: shared compiler cache: {s}\n", .{@errorName(err)}) catch return error.WriteFailed;
        std.Io.File.stderr().writeStreamingAll(init.io, text) catch return error.WriteFailed;
        return error.WriteFailed;
    };
    store.deinit();
    return if (selection.origin == .default) withStore(init, selection.path) else init;
}

// A command-owned copy of the environment naming `directory` ("" disables).
fn withStore(init: std.process.Init, directory: []const u8) Error!std.process.Init {
    const a = init.arena.allocator();
    const environment = try a.create(std.process.Environ.Map);
    environment.* = try init.environ_map.clone(a);
    try environment.put(artifacts.environment_variable, directory);
    var prepared = init;
    prepared.environ_map = environment;
    return prepared;
}

// spec-case: COMPILER-SHARED-CACHE-1
test "compiler sharing suppression leaves the guest environment intact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    defer environment.deinit();
    try environment.put(artifacts.environment_variable, "guest-visible-cache");
    try environment.put("MYLANG_OPTIONS", "--restrict");
    const init: std.process.Init = .{
        .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environment,
        .preopens = .empty,
    };
    const compilation = try prepare(init, true);
    try std.testing.expect(compilation.environ_map != init.environ_map);
    try std.testing.expectEqualStrings("", compilation.environ_map.get(artifacts.environment_variable).?);
    try std.testing.expectEqualStrings("guest-visible-cache", init.environ_map.get(artifacts.environment_variable).?);
    try std.testing.expectEqualStrings("--restrict", compilation.environ_map.get("MYLANG_OPTIONS").?);
}

// spec-case: SHARED-STORE-4
test "an unusable default compiler store warns and disables sharing while an explicit one fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = ".cache", .data = "a file where the cache directory belongs" });
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", root);
    const init: std.process.Init = .{
        .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environment,
        .preopens = .empty,
    };
    const off = try prepareWith(init, false, false);
    try std.testing.expect(off.environ_map == init.environ_map);
    const degraded = try prepareWith(init, false, true);
    try std.testing.expectEqualStrings("", degraded.environ_map.get(artifacts.environment_variable).?);
    try std.testing.expect(init.environ_map.get(artifacts.environment_variable) == null);
    try temporary.dir.deleteFile(std.testing.io, ".cache");
    const usable = try prepareWith(init, false, true);
    const expected = try std.fs.path.join(a, &.{ root, ".cache", "mylang", "compiler-artifacts" });
    try std.testing.expectEqualStrings(expected, usable.environ_map.get(artifacts.environment_variable).?);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "blocked", .data = "not a directory" });
    try environment.put(artifacts.environment_variable, try std.fs.path.join(a, &.{ root, "blocked" }));
    try std.testing.expectError(error.WriteFailed, prepareWith(init, false, true));
    try std.testing.expectError(error.WriteFailed, prepareWith(init, false, false));
}

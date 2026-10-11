//! Command-scoped compiler artifact policy, independent of guest execution.
const std = @import("std");
const artifacts = @import("mylang").shared_artifact_store;

/// Explicitly configured storage failures are host failures with a diagnosis.
pub const Error = error{ OutOfMemory, WriteFailed };

/// Disable sharing in a command-owned environment or validate it before replay.
/// The original environment remains available to the executed guest program.
pub fn prepare(init: std.process.Init, disabled: bool) Error!std.process.Init {
    if (disabled) {
        const a = init.arena.allocator();
        const environment = try a.create(std.process.Environ.Map);
        environment.* = try init.environ_map.clone(a);
        try environment.put(artifacts.environment_variable, "");
        var prepared = init;
        prepared.environ_map = environment;
        return prepared;
    }
    const directory = artifacts.selected(init.environ_map) orelse return init;
    var store = artifacts.Store.open(init.gpa, init.io, directory) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "error: shared compiler cache: {s}\n", .{@errorName(err)}) catch return error.WriteFailed;
        std.Io.File.stderr().writeStreamingAll(init.io, text) catch return error.WriteFailed;
        return error.WriteFailed;
    };
    store.deinit();
    return init;
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

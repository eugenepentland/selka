//! Native durable publication, refusal paths and crash-released directory ownership.
const std = @import("std");
const driver = @import("driver.zig");
const support = @import("test_support.zig");

fn nativeFixture(a: std.mem.Allocator) !std.process.RunResult {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const io = std.testing.io;
    const root = try directory.dir.realPathFileAlloc(io, ".", a);
    try directory.dir.writeFile(io, .{ .sub_path = "core_rt.c", .data = driver.runtime_source });
    try directory.dir.writeFile(io, .{ .sub_path = "fixture.c", .data = @embedFile("durable_fixture.c") });
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const binary = try std.fs.path.join(a, &.{ root, "fixture" });
    const source = try std.fs.path.join(a, &.{ root, "fixture.c" });
    const built = try std.process.run(a, io, .{
        .argv = &.{ environment.get("ZIG") orelse "zig", "cc", "-O2", "-std=c11", "-pthread", source, "-o", binary },
        .environ_map = &environment,
    });
    try std.testing.expectEqualStrings("", built.stderr);
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    return std.process.run(a, io, .{ .argv = &.{ binary, "all" }, .cwd = .{ .path = root }, .environ_map = &environment });
}

// spec: NEW-CORE-DURABLE-STORAGE-1
test "durable storage completes short writes refuses unsafe paths and recovers actual SIGKILL publication and ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ran = try nativeFixture(arena.allocator());
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "partial writes, exact bounded reads") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "uncertain rename is explicit") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "actual SIGKILL before and after publication") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "SIGKILL, File drop and completion release directory ownership") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "includes hidden entries beyond 256 and refuses partial readdir") != null);
}

// spec-case: NEW-CORE-DURABLE-STORAGE-1
test "durable storage lowers fallible capability operations and with try lock cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\func stored(fs: Filesystem) -> Result[int, str]:
        \\    with try lock_directory(fs, "") as lease:
        \\        _ = try atomic_write_file(fs, "data", b"value")
        \\        _ = try sync_directory(fs, "")
        \\        const value = try read_regular_file(fs, "data", 64)
        \\        return Ok(len(value))
        \\func methods(fs: Filesystem) -> Result[int, str]:
        \\    with try fs.lock_directory("") as lease:
        \\        _ = try fs.atomic_write_file("data", b"method")
        \\        _ = try fs.sync_directory("")
        \\        const value = try fs.read_regular_file("data", 64)
        \\        const names = try fs.list_directory("", 4096)
        \\        return Ok(len(value) + len(names))
        \\func main(fs: Filesystem) -> int:
        \\    match stored(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_durable_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_file_scope_close") != null);
}

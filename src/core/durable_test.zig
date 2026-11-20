//! Native durable publication, refusal paths and crash-released directory ownership.
const std = @import("std");
const native = @import("native_fixture.zig");
const support = @import("test_support.zig");

fn nativeFixture(a: std.mem.Allocator) !std.process.RunResult {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const io = std.testing.io;
    const root = try directory.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const binary = try native.buildProgram(a, root, .{ .source = @embedFile("durable_fixture.c") });
    return std.process.run(a, io, .{ .argv = &.{ binary, "all" }, .cwd = .{ .path = root }, .environ_map = &environment });
}

// spec: NEW-CORE-DURABLE-STORAGE-1
// spec-case: NEW-CORE-ZERO-RC-RESOURCES-1
test "durable storage completes short writes refuses unsafe paths and recovers actual SIGKILL publication and ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ran = try nativeFixture(arena.allocator());
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "partial writes, exact bounded reads") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "canonical names, followed stat, permissions, times and atomic modes") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "stat names the device, statfs the space of the filesystem that holds a path, and read_at reads from an offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "read_link names the text a link stores and refuses what stat refuses, and stat names the owner, the group and the hard links") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "link_path makes a second name for a regular file inside the grants and mkdir_mode makes a folder with its mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "uncertain rename is explicit") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "actual SIGKILL before and after publication") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "SIGKILL, File drop and completion release directory ownership") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "replace_file publishes whole through a temporary and a rename, and forces nothing to disk") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "replace_file_synced forces the file to disk before the rename and not the directory after it") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "stat opens no descriptor of its own: one fstatat from the root, one confined openat2 below it") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "a listing carries each entry's kind from the directory record, one fstatat only without a type") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "includes hidden entries beyond 256 and 4096, names its bound, and refuses partial readdir") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "a failed write says why: the table, the durable calls, the whole-file calls, the open-file traps and the in-memory filesystem") != null);
}

// spec-case: NEW-CORE-DURABLE-STORAGE-1
test "durable storage lowers fallible capability operations and with try lock cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\func stored(fs: Filesystem) -> int fails str:
        \\    with try fs.lock_directory("") as lease:
        \\        _ = try fs.atomic_write_file("data", b"value")
        \\        _ = try fs.sync_directory("")
        \\        const value = try fs.read_regular_file("data", 64)
        \\        return len(value)
        \\func methods(fs: Filesystem) -> int fails str:
        \\    with try fs.lock_directory("") as lease:
        \\        _ = try fs.atomic_write_file("data", b"method")
        \\        _ = try fs.sync_directory("")
        \\        const value = try fs.read_regular_file("data", 64)
        \\        const names = try fs.list_directory("", 4096)
        \\        return len(value) + len(names)
        \\func main(fs: Filesystem) -> int:
        \\    match stored(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_durable_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_owned_file_scope_end") != null);
}

// spec-case: NEW-CORE-DURABLE-STORAGE-1
test "rename stat and file locks lower to the durable access call, with a borrowed path as a span and a with scope cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\func swap(fs: Filesystem, from: str, to: str) -> int fails str:
        \\    with try fs.lock_file("store.lock") as lease:
        \\        _ = try fs.rename_path(from, to)
        \\        const packed = try fs.stat_path(to)
        \\        return len(packed)
        \\func probe(fs: Filesystem) -> int fails str:
        \\    with try fs.try_lock_file("store.lock") as lease:
        \\        return 1
        \\func main(fs: Filesystem) -> int:
        \\    match swap(fs, "a", "b"):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_span_durable_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_owned_file_scope_end") != null);
}

// spec-case: NEW-CORE-DURABLE-STORAGE-1
test "canonical, mode, time and followed-stat operations lower to the durable access call with a borrowed path as a span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\func tidy(fs: Filesystem, path: str, data: bytes) -> int fails str:
        \\    const name = try fs.canonical_path(path)
        \\    _ = try fs.chmod_path(path, 0o640)
        \\    _ = try fs.touch_path(path)
        \\    _ = try fs.set_modified_path(path, 1000000000)
        \\    _ = try fs.atomic_write_file_mode(path, data, 0o644)
        \\    const packed = try fs.stat_follow_path(path)
        \\    return len(name) + len(packed)
        \\func main(fs: Filesystem) -> int:
        \\    match tidy(fs, "a", b"x"):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_span_durable_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_durable_access") == null);
}

//! `replace_file`, `replace_file_mode` and the `replace_file_synced[_mode]` pair on a real directory: the publication that is
//! atomic but not durable. The destination holds the old file or the new one whole, a replaced file gets the asked
//! permissions, a failure names the verb "replace" and the reason, and no temporary is left beside the destination. Which
//! `fsync`s happen (none for `replace_file`, the file's alone for `replace_file_synced`, never the directory's) is pinned in
//! the durable fixture, which counts the calls (src/core/durable_fixture.c). The in-memory counterpart is
//! tests/lang/filesystem_replace.selka.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

/// The guest of every test here: publish, replace, permissions, refusals, and no temporary left behind.
const guest =
    \\import filesystem
    \\import strings
    \\func mode_of(fs: Filesystem, path: str) -> int:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return info.mode
    \\        case Err(_):
    \\            return -1
    \\func run(fs: Filesystem) -> int fails str:
    \\    _ = try fs.replace_file("private.bin", b"one")
    \\    if mode_of(fs, "private.bin") != 0o600:
    \\        return 1
    \\    _ = try fs.replace_file("private.bin", b"two, a longer second version")
    \\    const second = try fs.read_text("private.bin")
    \\    if second != "two, a longer second version":
    \\        return 2
    \\    _ = try fs.replace_file("private.bin", b"short")
    \\    const third = try fs.read_text("private.bin")
    \\    if third != "short":
    \\        return 3
    \\    _ = try fs.replace_file_mode("shared.bin", b"x", 0o666)
    \\    const shared = mode_of(fs, "shared.bin")
    \\    if bit_and(shared, 0o600) != 0o600 or bit_and(shared, 0o7111) != 0 or bit_or(shared, 0o666) != 0o666:
    \\        return 4
    \\    _ = try fs.replace_file_mode("private.bin", b"three", 0o644)
    \\    const replaced = mode_of(fs, "private.bin")
    \\    if bit_and(replaced, 0o600) != 0o600 or bit_or(replaced, 0o644) != 0o644:
    \\        return 5
    \\    match fs.replace_file_mode("bad.bin", b"x", 0o10000):
    \\        case Ok(_):
    \\            return 6
    \\        case Err(message):
    \\            if message != "replace 'bad.bin': the mode must be between 0 and 0o7777":
    \\                return 7
    \\    match fs.replace_file("no/such/dir/file", b"x"):
    \\        case Ok(_):
    \\            return 8
    \\        case Err(message):
    \\            if message != "replace 'no/such/dir/file': a folder on the way does not exist":
    \\                return 9
    \\    match fs.replace_file("../no-such-folder/escape", b"x"):
    \\        case Ok(_):
    \\            return 10
    \\        case Err(message):
    \\            if not strings.starts_with(message, "replace '../no-such-folder/escape': "):
    \\                return 11
    \\    if fs.exists("bad.bin"):
    \\        return 12
    \\    const names = try fs.listdir("")
    \\    for name in names:
    \\        if strings.starts_with(name, ".myl-durable-"):
    \\            return 13
    \\    return 42
    \\func main(fs: Filesystem) -> int:
    \\    match run(fs):
    \\        case Ok(value):
    \\            return value
    \\        case Err(_):
    \\            return 98
;

test "replace_file publishes and replaces whole, with the asked permissions and no temporary left, under a grant" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, guest, sandbox.options(), 42);
}

test "replace_file works with no restriction too" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, guest, .{ .directory = sandbox.path }, 42);
}

test "replace_file refuses a read-only grant, a directory and a symbolic link, and leaves them alone" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "keep.txt", .data = "old" });
    try fixture.expect(t.allocator,
        \\import strings
        \\func main(fs: Filesystem) -> int:
        \\    match fs.replace_file("keep.txt", b"new"):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(message):
        \\            if not strings.starts_with(message, "replace 'keep.txt': denied: writing needs a write grant (--allow-write); '"):
        \\                return 2
        \\    match fs.replace_file_mode("keep.txt", b"new", 0o644):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(_):
        \\            pass
        \\    match fs.read_text("keep.txt"):
        \\        case Ok(text):
        \\            if text != "old":
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    return 42
    , sandbox.options(), 42);
}

test "replace_file_synced publishes and replaces whole, with the asked permissions and no temporary left, under a grant" {
    const source = try std.mem.replaceOwned(u8, t.allocator, guest, "replace_file", "replace_file_synced");
    defer t.allocator.free(source);
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, source, sandbox.options(), 42);
}

test "replace_file_synced works with no restriction too" {
    const source = try std.mem.replaceOwned(u8, t.allocator, guest, "replace_file", "replace_file_synced");
    defer t.allocator.free(source);
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator, source, .{ .directory = sandbox.path }, 42);
}

test "replace_file_synced refuses a read-only grant and leaves the file alone" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = "keep.txt", .data = "old" });
    try fixture.expect(t.allocator,
        \\import strings
        \\func main(fs: Filesystem) -> int:
        \\    match fs.replace_file_synced("keep.txt", b"new"):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(message):
        \\            if not strings.starts_with(message, "replace 'keep.txt': denied: writing needs a write grant (--allow-write); '"):
        \\                return 2
        \\    match fs.replace_file_synced_mode("keep.txt", b"new", 0o644):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(_):
        \\            pass
        \\    match fs.read_text("keep.txt"):
        \\        case Ok(text):
        \\            if text != "old":
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    return 42
    , sandbox.options(), 42);
}

//! Directory listings of a real directory: `listdir`, the bounded `list_directory` and a loop over the names answer a
//! directory of any size whole (the runtime once refused more than 256 entries, and a `list_directory` bound over 4,096,
//! in words that blamed the grants), under a granted directory and with no restriction. The in-memory counterpart is
//! tests/lang/filesystem_listings.selka.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

/// Directories of these many empty files are created next to each other, as `d257`, `d1000` and `d5000`.
const sizes = [_]usize{ 257, 1000, 5000 };

/// Create `d<N>` holding N empty files named `f<index>` for every size.
fn seed(sandbox: *files.Sandbox) !void {
    const dir = sandbox.temporary.dir;
    var name: [64]u8 = undefined;
    for (sizes) |size| {
        const directory = try std.fmt.bufPrint(&name, "d{d}", .{size});
        try dir.createDirPath(t.io, directory);
        for (0..size) |index| {
            const path = try std.fmt.allocPrint(t.allocator, "{s}/f{d:0>5}", .{ directory, index });
            defer t.allocator.free(path);
            try dir.writeFile(t.io, .{ .sub_path = path, .data = "" });
        }
    }
}

/// The guest every listing test runs: each size lists whole through `listdir`, `list_directory` and `list_entries`, a
/// loop sees every name, and a bound the directory outgrows is refused in words that name the bound.
const guest =
    \\import filesystem
    \\import strings
    \\func regular(fs: Filesystem, path: str) -> int:
    \\    match filesystem.list_entries(fs, path):
    \\        case Ok(entries):
    \\            mut count = 0
    \\            for entry in entries:
    \\                if entry.kind == filesystem.PathKind.Regular:
    \\                    count += 1
    \\            return count
    \\        case Err(_):
    \\            return -1
    \\func seen(fs: Filesystem, path: str) -> int:
    \\    match fs.listdir(path):
    \\        case Ok(names):
    \\            mut count = 0
    \\            for name in names:
    \\                if strings.starts_with(name, "f"):
    \\                    count += 1
    \\            return count
    \\        case Err(_):
    \\            return -1
    \\func bounded(fs: Filesystem, path: str, bound: int) -> str:
    \\    match fs.list_directory(path, bound):
    \\        case Ok(names):
    \\            return "ok " + str(len(names))
    \\        case Err(message):
    \\            return copy(message)
    \\func main(fs: Filesystem) -> int:
    \\    if seen(fs, "d257") != 257:
    \\        return 1
    \\    if seen(fs, "d1000") != 1000:
    \\        return 2
    \\    if seen(fs, "d5000") != 5000:
    \\        return 3
    \\    if bounded(fs, "d257", 257) != "ok 257" or bounded(fs, "d1000", 1000) != "ok 1000":
    \\        return 4
    \\    if bounded(fs, "d5000", 100000) != "ok 5000":
    \\        return 5
    \\    if bounded(fs, "d5000", 4999) != "directory listing 'd5000': has more than 4999 entries (the max_entries bound)":
    \\        return 6
    \\    if bounded(fs, "d257", -1) != "directory listing 'd257': max_entries must not be negative":
    \\        return 7
    \\    if regular(fs, "d257") != 257 or regular(fs, "d1000") != 1000 or regular(fs, "d5000") != 5000:
    \\        return 8
    \\    return 42
;

test "257, 1000 and 5000 entries list whole under a granted directory" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seed(&sandbox);
    try fixture.expect(t.allocator, guest, sandbox.options(), 42);
}

test "257, 1000 and 5000 entries list whole with no restriction" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seed(&sandbox);
    try fixture.expect(t.allocator, guest, .{ .directory = sandbox.path }, 42);
}

test "a narrowed capability lists a large directory too" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seed(&sandbox);
    try fixture.expect(t.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    const narrow = fs.dir("d1000")
        \\    match narrow.listdir(""):
        \\        case Ok(names):
        \\            if len(names) != 1000:
        \\                return 1
        \\            return 42
        \\        case Err(_):
        \\            return 2
    , sandbox.options(), 42);
}

/// Create a directory of every kind a listing reports: a file, a subdirectory, a link to the file, a link to the
/// directory and a link to nothing.
fn seedKinds(sandbox: *files.Sandbox) !void {
    const dir = sandbox.temporary.dir;
    try dir.createDirPath(t.io, "mixed/sub");
    try dir.writeFile(t.io, .{ .sub_path = "mixed/file.txt", .data = "hello" });
    try dir.symLink(t.io, "file.txt", "mixed/filelink", .{});
    try dir.symLink(t.io, "sub", "mixed/dirlink", .{});
    try dir.symLink(t.io, "nothing", "mixed/dangling", .{});
}

/// The guest of the kind tests: every entry's kind equals what `stat` of it says, and each is the expected one.
const kinds_guest =
    \\import filesystem
    \\func kind_code(kind: filesystem.PathKind) -> int:
    \\    match kind:
    \\        case Regular:
    \\            return 1
    \\        case Directory:
    \\            return 2
    \\        case Symlink:
    \\            return 3
    \\        case Other:
    \\            return 0
    \\func expected(name: str) -> int:
    \\    if name == "file.txt":
    \\        return 1
    \\    if name == "sub":
    \\        return 2
    \\    if name == "filelink" or name == "dirlink" or name == "dangling":
    \\        return 3
    \\    return -1
    \\func main(fs: Filesystem) -> int:
    \\    match filesystem.list_entries(fs, "mixed"):
    \\        case Ok(entries):
    \\            if len(entries) != 5:
    \\                return 1
    \\            for entry in entries:
    \\                if kind_code(entry.kind) != expected(entry.name):
    \\                    return 2
    \\                match filesystem.stat(fs, "mixed/" + entry.name):
    \\                    case Ok(info):
    \\                        if info.kind != entry.kind:
    \\                            return 3
    \\                    case Err(_):
    \\                        return 4
    \\        case Err(_):
    \\            return 5
    \\    match filesystem.list_entries(fs, "mixed/dirlink"):
    \\        case Ok(_):
    \\            return 6
    \\        case Err(_):
    \\            pass
    \\    match filesystem.list_entries(fs, "mixed/file.txt"):
    \\        case Ok(_):
    \\            return 7
    \\        case Err(message):
    \\            if message != "directory listing 'mixed/file.txt': is not a directory":
    \\                return 8
    \\    return 42
;

test "list_entries reports file, directory and symbolic link kinds under a granted directory" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedKinds(&sandbox);
    try fixture.expect(t.allocator, kinds_guest, sandbox.options(), 42);
}

test "list_entries reports file, directory and symbolic link kinds with no restriction" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedKinds(&sandbox);
    try fixture.expect(t.allocator, kinds_guest, .{ .directory = sandbox.path }, 42);
}

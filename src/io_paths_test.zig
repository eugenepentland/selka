//! Atomic rename, stat, file locks and path metadata through a real granted directory: `rename_path`, `stat_path`,
//! `lock_file`, `try_lock_file`, `canonical_path`, `chmod_path`, `touch_path`, `set_modified_path`,
//! `atomic_write_file_mode` and `stat_follow_path`, the typed `filesystem` module over them, and the grant bounds they
//! share with the other calls.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

/// Run `text` as a project in a fresh granted directory and require its entry value to be 42.
fn expectPasses(writable: bool, seed: ?[]const u8, text: []const u8) !void {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(writable);
    defer sandbox.deinit();
    if (seed) |name| try sandbox.temporary.dir.writeFile(t.io, .{ .sub_path = name, .data = "seed" });
    try expectRooted(&sandbox, text, sandbox.options());
}

/// Run `text`, `@ROOT@` replaced by the sandbox's real path and `@UP@` by the folder that holds it, under `options`, and
/// require its entry value to be 42.
fn expectRooted(sandbox: *files.Sandbox, text: []const u8, options: @import("native_execute.zig").Options) !void {
    const rooted = try std.mem.replaceOwned(u8, t.allocator, text, "@ROOT@", sandbox.path);
    defer t.allocator.free(rooted);
    const source = try std.mem.replaceOwned(u8, t.allocator, rooted, "@UP@", std.fs.path.dirname(sandbox.path).?);
    defer t.allocator.free(source);
    try fixture.expect(t.allocator, source, options, 42);
}

test "rename_path moves a file, replaces a file destination and names both paths in a failure" {
    try expectPasses(true, null,
        \\func run(fs: Filesystem) -> int fails str:
        \\    _ = try fs.write_text("a.txt", "one")
        \\    _ = try fs.write_text("b.txt", "two")
        \\    _ = try fs.rename_path("a.txt", "b.txt")
        \\    if fs.exists("a.txt") or not fs.exists("b.txt"):
        \\        return 1
        \\    const text = try fs.read_text("b.txt")
        \\    if text != "one":
        \\        return 2
        \\    _ = try fs.mkdir("dir")
        \\    _ = try fs.rename_path("b.txt", "dir/c.txt")
        \\    if not fs.exists("dir/c.txt") or fs.exists("b.txt"):
        \\        return 3
        \\    match fs.rename_path("absent.txt", "x.txt"):
        \\        case Ok(_):
        \\            return 4
        \\        case Err(message):
        \\            if message != "rename 'absent.txt' to 'x.txt': the path does not exist":
        \\                return 5
        \\    match fs.rename_path("dir/c.txt", "../out.txt"):
        \\        case Ok(_):
        \\            return 6
        \\        case Err(_):
        \\            return 42
        \\func main(fs: Filesystem) -> int:
        \\    match run(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 99
    );
}

test "filesystem.stat reports kind, size, time and inode, keeps the inode across a rename and matches Missing" {
    try expectPasses(true, null,
        \\import filesystem
        \\func measure(fs: Filesystem, path: str) -> filesystem.Stat fails filesystem.StatError:
        \\    return try filesystem.stat(fs, path)
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.write_text("f.txt", "hello")
        \\    _ = fs.mkdir("d")
        \\    match measure(fs, "f.txt"):
        \\        case Ok(first):
        \\            if first.kind != filesystem.PathKind.Regular or first.size != 5 or first.modified <= 0 or first.inode == 0u64:
        \\                return 1
        \\            _ = fs.rename_path("f.txt", "g.txt")
        \\            match measure(fs, "g.txt"):
        \\                case Ok(second):
        \\                    if second.inode != first.inode or second.size != 5:
        \\                        return 2
        \\                case Err(_):
        \\                    return 3
        \\        case Err(_):
        \\            return 4
        \\    match measure(fs, "d"):
        \\        case Ok(dir):
        \\            if dir.kind != filesystem.PathKind.Directory:
        \\                return 5
        \\        case Err(_):
        \\            return 6
        \\    match measure(fs, "nothing/here"):
        \\        case Ok(_):
        \\            return 7
        \\        case Err(error):
        \\            match error:
        \\                case Missing:
        \\                    return 42
        \\                case Failed(message=_):
        \\                    return 8
    );
}

test "a file lock excludes a second lock until its scope ends, and try_lock_file reports the holder" {
    try expectPasses(true, null,
        \\import filesystem
        \\func second(fs: Filesystem) -> bool fails str:
        \\    with try fs.try_lock_file("store.lock") as other:
        \\        return True
        \\func main(fs: Filesystem) -> int:
        \\    with fs.lock_file("store.lock") as first:
        \\        match second(fs):
        \\            case Ok(_):
        \\                return 1
        \\            case Err(message):
        \\                if not filesystem.is_lock_busy(message) or message != "try lock file 'store.lock': the lock is held by another holder":
        \\                    return 2
        \\    match second(fs):
        \\        case Ok(free):
        \\            if not free:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    with fs.try_lock_file("store.lock") as again:
        \\        return 42
    );
}

test "a second directory lease reports the holder with the busy text and is granted after the first ends" {
    try expectPasses(true, null,
        \\import filesystem
        \\func second(fs: Filesystem) -> str fails str:
        \\    with try fs.lock_directory("") as other:
        \\        return "granted"
        \\func main(fs: Filesystem) -> int:
        \\    with fs.lock_directory("") as first:
        \\        match second(fs):
        \\            case Ok(_):
        \\                return 1
        \\            case Err(message):
        \\                if not filesystem.is_lock_busy(message) or message != "directory lock '': the lock is held by another holder":
        \\                    return 2
        \\    match second(fs):
        \\        case Ok(text):
        \\            if text != "granted":
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    return 42
    );
}

test "a read-only grant stats and refuses to rename or lock" {
    try expectPasses(false, "seed.txt",
        \\import filesystem
        \\func lock_it(fs: Filesystem) -> int fails str:
        \\    with try fs.try_lock_file("x.lock") as held:
        \\        return 7
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.stat(fs, "seed.txt"):
        \\        case Ok(info):
        \\            if info.size != 4:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    match fs.rename_path("seed.txt", "moved.txt"):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(message):
        \\            if message != "rename 'seed.txt' to 'moved.txt': denied: writing needs a write grant (--allow-write); '@ROOT@/seed.txt' is granted for reading only":
        \\                return 4
        \\    match fs.stat_path("absent"):
        \\        case Ok(octets):
        \\            if len(octets) != 0:
        \\                return 5
        \\        case Err(_):
        \\            return 6
        \\    match lock_it(fs):
        \\        case Ok(_):
        \\            return 7
        \\        case Err(message):
        \\            if message != "try lock file 'x.lock': denied: writing needs a write grant (--allow-write); '@ROOT@/x.lock' is granted for reading only":
        \\                return 8
        \\    return 42
    );
}

/// Make `real/file.txt` (5 octets) and the links the canonical-path tests resolve: a relative link to the file, one to
/// the directory, one that climbs out of the sandbox and an absolute one.
fn seedLinks(sandbox: *files.Sandbox) !void {
    const dir = sandbox.temporary.dir;
    try dir.createDirPath(t.io, "real");
    try dir.writeFile(t.io, .{ .sub_path = "real/file.txt", .data = "hello" });
    try dir.symLink(t.io, "real/file.txt", "ln", .{});
    try dir.symLink(t.io, "real", "dirln", .{});
    try dir.symLink(t.io, "../outside", "esc", .{});
    try dir.symLink(t.io, sandbox.path, "abs", .{});
}

/// Run `text` with no restriction, the sandbox as its working directory, `@ROOT@` replaced by the sandbox's real path.
fn expectUnrestricted(sandbox: *files.Sandbox, text: []const u8) !void {
    const source = try std.mem.replaceOwned(u8, t.allocator, text, "@ROOT@", sandbox.path);
    defer t.allocator.free(source);
    try fixture.expect(t.allocator, source, .{ .directory = sandbox.path }, 42);
}

test "canonical_path under a grant answers the absolute name, as a plain run does, and refuses a link that leaves the directory" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try expectRooted(&sandbox,
        \\import filesystem
        \\func named(fs: Filesystem, path: str, wanted: str) -> bool:
        \\    match filesystem.realpath(fs, path):
        \\        case Ok(name):
        \\            return name == wanted
        \\        case Err(_):
        \\            return False
        \\func refused(fs: Filesystem, path: str, text: str) -> bool:
        \\    match fs.canonical_path(path):
        \\        case Ok(_):
        \\            return False
        \\        case Err(message):
        \\            return message == f"realpath '{path}': {text}"
        \\func main(fs: Filesystem) -> int:
        \\    if not named(fs, "real/file.txt", "@ROOT@/real/file.txt") or not named(fs, "ln", "@ROOT@/real/file.txt"):
        \\        return 1
        \\    if not named(fs, "dirln/file.txt", "@ROOT@/real/file.txt") or not named(fs, "dirln", "@ROOT@/real") or not named(fs, "real", "@ROOT@/real"):
        \\        return 2
        \\    if not named(fs, "", "@ROOT@") or not named(fs, ".", "@ROOT@"):
        \\        return 3
        \\    match filesystem.cwd(fs):
        \\        case Ok(name):
        \\            if name != "@ROOT@":
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    if not refused(fs, "esc", "resolves outside the granted directory") or not refused(fs, "abs", "resolves outside the granted directory"):
        \\        return 6
        \\    if not refused(fs, "nothing", "the path does not exist"):
        \\        return 7
        \\    if not refused(fs, "esc/x", "resolves outside the granted directory"):
        \\        return 8
        \\    if not named(fs, "real/../real", "@ROOT@/real") or not named(fs, "@ROOT@/real/", "@ROOT@/real"):
        \\        return 9
        \\    if not refused(fs, "/etc", "denied: '/etc' is outside the granted directories"):
        \\        return 10
        \\    return 42
    , sandbox.options());
}

test "canonical_path through a narrowed directory names the path relative to the narrowing and stays inside it" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try sandbox.temporary.dir.createDirPath(t.io, "other");
    try sandbox.temporary.dir.symLink(t.io, "../real", "real/up", .{});
    try sandbox.temporary.dir.symLink(t.io, "../other", "real/out", .{});
    try sandbox.temporary.dir.symLink(t.io, "file.txt", "real/same", .{});
    try fixture.expect(t.allocator,
        \\import filesystem
        \\func named(fs: Filesystem, path: str, wanted: str) -> bool:
        \\    match filesystem.realpath(fs, path):
        \\        case Ok(name):
        \\            return name == wanted
        \\        case Err(_):
        \\            return False
        \\func main(fs: Filesystem) -> int:
        \\    with fs.dir("real") as narrow:
        \\        if not named(narrow, "file.txt", "file.txt") or not named(narrow, "same", "file.txt") or not named(narrow, "", ""):
        \\            return 1
        \\        if not named(narrow, "up", "") or not named(narrow, "up/file.txt", "file.txt") or named(narrow, "out", "") or named(narrow, "out/x", ""):
        \\            return 2
        \\        match filesystem.stat_follow(narrow, "out"):
        \\            case Ok(_):
        \\                return 3
        \\            case Err(error):
        \\                match error:
        \\                    case Missing:
        \\                        return 4
        \\                    case Failed(message=text):
        \\                        if text != "stat 'out': resolves outside the granted directory":
        \\                            return 5
        \\    return 42
    , sandbox.options(), 42);
}

test "an unrestricted canonical_path answers the absolute symlink-free path and cwd is the working directory" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try expectUnrestricted(&sandbox,
        \\import filesystem
        \\func named(fs: Filesystem, path: str, wanted: str) -> bool:
        \\    match filesystem.realpath(fs, path):
        \\        case Ok(name):
        \\            return name == wanted
        \\        case Err(_):
        \\            return False
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.cwd(fs):
        \\        case Ok(name):
        \\            if name != "@ROOT@":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    if not named(fs, "ln", "@ROOT@/real/file.txt") or not named(fs, "dirln/file.txt", "@ROOT@/real/file.txt"):
        \\        return 3
        \\    if not named(fs, "abs", "@ROOT@") or not named(fs, "@ROOT@/dirln", "@ROOT@/real") or not named(fs, ".", "@ROOT@"):
        \\        return 4
        \\    if named(fs, "esc", "") or named(fs, "nothing", "") or named(fs, "real/../real", ""):
        \\        return 5
        \\    if not named(fs, "/", "/"):
        \\        return 6
        \\    return 42
    );
}

test "an unrestricted stat and listdir pass through a symbolic link, and stat_follow describes its target" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try expectUnrestricted(&sandbox,
        \\import filesystem
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.stat(fs, "dirln/file.txt"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Regular or info.size != 5:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    match fs.listdir("dirln"):
        \\        case Ok(names):
        \\            if names != ["file.txt"]:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    match filesystem.stat(fs, "ln"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Symlink:
        \\                return 5
        \\        case Err(_):
        \\            return 6
        \\    match filesystem.stat_follow(fs, "ln"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Regular or info.size != 5:
        \\                return 7
        \\        case Err(_):
        \\            return 8
        \\    match filesystem.stat_follow(fs, "dirln"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Directory:
        \\                return 9
        \\        case Err(_):
        \\            return 10
        \\    match filesystem.stat_follow(fs, "esc"):
        \\        case Ok(_):
        \\            return 11
        \\        case Err(error):
        \\            match error:
        \\                case Missing:
        \\                    return 42
        \\                case Failed(message=_):
        \\                    return 12
    );
}

test "a granted directory still refuses a link on the way for stat and listdir, and follows none for stat" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try fixture.expect(t.allocator,
        \\import filesystem
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.stat(fs, "dirln/file.txt"):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(_):
        \\            pass
        \\    match fs.listdir("dirln"):
        \\        case Ok(_):
        \\            return 2
        \\        case Err(message):
        \\            if message != "listdir 'dirln': is not a directory":
        \\                return 3
        \\    match filesystem.stat(fs, "ln"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Symlink:
        \\                return 4
        \\        case Err(_):
        \\            return 5
        \\    match filesystem.stat_follow(fs, "ln"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Regular or info.size != 5:
        \\                return 6
        \\        case Err(_):
        \\            return 7
        \\    return 42
    , sandbox.options(), 42);
}

test "chmod, touch, set_modified and Stat.mode change and report the metadata of a file, not following a link" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try fixture.expect(t.allocator,
        \\import filesystem
        \\func mode_of(fs: Filesystem, path: str) -> int:
        \\    match filesystem.stat(fs, path):
        \\        case Ok(info):
        \\            return info.mode
        \\        case Err(_):
        \\            return -1
        \\func modified_of(fs: Filesystem, path: str) -> int:
        \\    match filesystem.stat(fs, path):
        \\        case Ok(info):
        \\            return info.modified
        \\        case Err(_):
        \\            return -1
        \\func run(fs: Filesystem) -> int fails str:
        \\    _ = try filesystem.chmod(fs, "real/file.txt", 0o640)
        \\    if mode_of(fs, "real/file.txt") != 0o640:
        \\        return 1
        \\    _ = try filesystem.chmod(fs, "real/file.txt", 0o4755)
        \\    if mode_of(fs, "real/file.txt") != 0o4755:
        \\        return 2
        \\    _ = try fs.chmod_path("real/file.txt", 0o600)
        \\    match filesystem.chmod(fs, "ln", 0o644):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(message):
        \\            if message != "chmod 'ln': a symbolic link has no permission bits of its own":
        \\                return 4
        \\    if mode_of(fs, "real/file.txt") != 0o600:
        \\        return 5
        \\    match filesystem.chmod(fs, "real/file.txt", 0o10000):
        \\        case Ok(_):
        \\            return 6
        \\        case Err(message):
        \\            if message != "chmod 'real/file.txt': the mode must be between 0 and 0o7777":
        \\                return 7
        \\    match filesystem.chmod(fs, "real/absent", 0o600):
        \\        case Ok(_):
        \\            return 8
        \\        case Err(message):
        \\            if message != "chmod 'real/absent': the path does not exist":
        \\                return 9
        \\    _ = try filesystem.set_modified(fs, "real/file.txt", 1000000000123456789)
        \\    if modified_of(fs, "real/file.txt") != 1000000000123456789:
        \\        return 10
        \\    _ = try fs.set_modified_path("real/file.txt", -1500000000)
        \\    if modified_of(fs, "real/file.txt") != -1500000000:
        \\        return 11
        \\    _ = try filesystem.touch(fs, "real/file.txt")
        \\    if modified_of(fs, "real/file.txt") < 1700000000000000000:
        \\        return 12
        \\    _ = try filesystem.set_modified(fs, "ln", 5000000000)
        \\    if modified_of(fs, "ln") != 5000000000 or modified_of(fs, "real/file.txt") == 5000000000:
        \\        return 13
        \\    match filesystem.touch(fs, "real/absent"):
        \\        case Ok(_):
        \\            return 14
        \\        case Err(message):
        \\            if message != "touch 'real/absent': the path does not exist":
        \\                return 15
        \\    if fs.exists("real/absent"):
        \\        return 16
        \\    match filesystem.touch(fs, "../escape"):
        \\        case Ok(_):
        \\            return 17
        \\        case Err(_):
        \\            return 42
        \\func main(fs: Filesystem) -> int:
        \\    match run(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 98
    , sandbox.options(), 42);
}

test "atomic_write_file_mode publishes with the asked permissions where atomic_write_file keeps 0600" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator,
        \\import filesystem
        \\import strings
        \\func mode_of(fs: Filesystem, path: str) -> int:
        \\    match filesystem.stat(fs, path):
        \\        case Ok(info):
        \\            return info.mode
        \\        case Err(_):
        \\            return -1
        \\func run(fs: Filesystem) -> int fails str:
        \\    _ = try fs.atomic_write_file("private.bin", b"one")
        \\    if mode_of(fs, "private.bin") != 0o600:
        \\        return 1
        \\    _ = try fs.atomic_write_file_mode("shared.bin", b"two", 0o666)
        \\    const shared = mode_of(fs, "shared.bin")
        \\    if bit_and(shared, 0o600) != 0o600 or bit_and(shared, 0o7111) != 0 or bit_or(shared, 0o666) != 0o666:
        \\        return 2
        \\    _ = try fs.atomic_write_file_mode("private.bin", b"three", 0o644)
        \\    const replaced = mode_of(fs, "private.bin")
        \\    if bit_and(replaced, 0o600) != 0o600 or bit_or(replaced, 0o644) != 0o644:
        \\        return 3
        \\    const text = try fs.read_text("private.bin")
        \\    if text != "three":
        \\        return 4
        \\    match fs.atomic_write_file_mode("bad.bin", b"x", 0o10000):
        \\        case Ok(_):
        \\            return 5
        \\        case Err(message):
        \\            if message != "atomic write 'bad.bin': the mode must be between 0 and 0o7777":
        \\                return 6
        \\    match fs.atomic_write_file_mode("bad.bin", b"x", -1):
        \\        case Ok(_):
        \\            return 7
        \\        case Err(_):
        \\            pass
        \\    if fs.exists("bad.bin"):
        \\        return 8
        \\    const names = try fs.listdir("")
        \\    for name in names:
        \\        if strings.starts_with(name, ".myl-durable-"):
        \\            return 9
        \\    return 42
        \\func main(fs: Filesystem) -> int:
        \\    match run(fs):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 98
    , sandbox.options(), 42);
}

test "a read-only grant reads canonical names and stats but refuses chmod, touch, set_modified and a mode write" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedLinks(&sandbox);
    try expectRooted(&sandbox,
        \\import filesystem
        \\func denied(message: str, verb: str, path: str) -> bool:
        \\    return message == f"{verb} '{path}': denied: writing needs a write grant (--allow-write); '@ROOT@/{path}' is granted for reading only"
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.realpath(fs, "ln"):
        \\        case Ok(name):
        \\            if name != "@ROOT@/real/file.txt":
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    match filesystem.stat_follow(fs, "ln"):
        \\        case Ok(info):
        \\            if info.size != 5:
        \\                return 3
        \\        case Err(_):
        \\            return 4
        \\    match fs.chmod_path("real/file.txt", 0o600):
        \\        case Ok(_):
        \\            return 5
        \\        case Err(message):
        \\            if not denied(message, "chmod", "real/file.txt"):
        \\                return 6
        \\    match fs.touch_path("real/file.txt"):
        \\        case Ok(_):
        \\            return 7
        \\        case Err(message):
        \\            if not denied(message, "touch", "real/file.txt"):
        \\                return 8
        \\    match fs.set_modified_path("real/file.txt", 1):
        \\        case Ok(_):
        \\            return 9
        \\        case Err(message):
        \\            if not denied(message, "set modified", "real/file.txt"):
        \\                return 10
        \\    match fs.atomic_write_file_mode("new.bin", b"x", 0o644):
        \\        case Ok(_):
        \\            return 11
        \\        case Err(message):
        \\            if not denied(message, "atomic write", "new.bin"):
        \\                return 12
        \\    return 42
    , sandbox.options());
}

test "Stat.mode may be left out of a constructor and defaults to zero" {
    try fixture.run(t.allocator,
        \\import filesystem
        \\func main() -> int:
        \\    const info = filesystem.Stat(kind=filesystem.PathKind.Regular, size=3, modified=4, inode=5u64)
        \\    if info.mode != 0:
        \\        return 1
        \\    const full = filesystem.Stat(kind=filesystem.PathKind.Directory, size=0, modified=0, inode=1u64, mode=0o755)
        \\    return full.mode - 0o755 + 42
    , 42);
}

test "the new durable operations check their argument types and arity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.chmod_path("a", "644")
        \\    return 0
    , "E_TYPE");
    try fixture.rejectsWith(arena.allocator(),
        \\func main(fs: Filesystem) -> int:
        \\    _ = atomic_write_file_mode(fs, "a", b"x")
        \\    return 0
    , "E_ARITY");
    try fixture.rejectsWith(arena.allocator(),
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.set_modified_path("a", 1.5)
        \\    return 0
    , "E_TYPE");
    // The bare spelling is refused first (FR28): its rewrite is certain, and the type error is then about the form the program will have.
    try fixture.rejectsWith(arena.allocator(),
        \\func main(fs: Filesystem) -> int:
        \\    _ = set_modified_path(fs, "a", 1.5)
        \\    return 0
    , "E_REMOVED_SPELLING");
}

test "symlink_path makes a link under a grant, stores its target as written and refuses what every other write refuses" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try expectRooted(&sandbox,
        \\import filesystem
        \\func note(result: Result[Unit, str]) -> str:
        \\    match result:
        \\        case Ok(_):
        \\            return "ok"
        \\        case Err(message):
        \\            return copy(message)
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.mkdir("d")
        \\    _ = fs.write_text("f", "hello")
        \\    if note(filesystem.symlink(fs, "f", "ln")) != "ok" or note(filesystem.symlink(fs, "d", "dirln")) != "ok":
        \\        return 1
        \\    if note(filesystem.symlink(fs, "/etc/passwd", "abs")) != "ok" or note(filesystem.symlink(fs, "../outside", "esc")) != "ok":
        \\        return 2
        \\    if note(filesystem.symlink(fs, "nothing", "dangling")) != "ok":
        \\        return 3
        \\    if note(filesystem.symlink(fs, "f", "ln")) != "symlink 'ln': already exists":
        \\        return 4
        \\    if note(filesystem.symlink(fs, "f", "no/dir/ln")) != "symlink 'no/dir/ln': a folder on the way does not exist":
        \\        return 5
        \\    if note(filesystem.symlink(fs, "f", "../escape")) != "symlink '../escape': denied: '@UP@/escape' is outside the granted directories":
        \\        return 6
        \\    if note(filesystem.symlink(fs, "f", "f/ln")) != "symlink 'f/ln': a parent of the path is not a directory":
        \\        return 7
        \\    if note(filesystem.symlink(fs, "", "empty")) != "symlink 'empty': the link target must be text of 1 to 4094 octets with no NUL":
        \\        return 8
        \\    if note(filesystem.symlink(fs, "f", "dirln/inner")) != "symlink 'dirln/inner': a parent of the path is not a directory":
        \\        return 9
        \\    if note(filesystem.symlink(fs.read_only(), "f", "ro")) != "symlink 'ro': denied: this Filesystem was narrowed by fs.read_only() and does not write":
        \\        return 10
        \\    return 42
    , sandbox.options());
    var buffer: [64]u8 = undefined;
    const dir = sandbox.temporary.dir;
    try t.expectEqualStrings("f", buffer[0..try dir.readLink(t.io, "ln", &buffer)]);
    try t.expectEqualStrings("d", buffer[0..try dir.readLink(t.io, "dirln", &buffer)]);
    try t.expectEqualStrings("/etc/passwd", buffer[0..try dir.readLink(t.io, "abs", &buffer)]);
    try t.expectEqualStrings("../outside", buffer[0..try dir.readLink(t.io, "esc", &buffer)]);
    try t.expectEqualStrings("nothing", buffer[0..try dir.readLink(t.io, "dangling", &buffer)]);
    try t.expectError(error.FileNotFound, dir.readLink(t.io, "ro", &buffer));
    try t.expectError(error.FileNotFound, dir.readLink(t.io, "empty", &buffer));
}

test "a read-only grant refuses symlink_path and creates nothing" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try expectRooted(&sandbox,
        \\import filesystem
        \\func main(fs: Filesystem) -> int:
        \\    match filesystem.symlink(fs, "f", "ln"):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(message):
        \\            if message == "symlink 'ln': denied: writing needs a write grant (--allow-write); '@ROOT@/ln' is granted for reading only":
        \\                return 42
        \\            return 2
    , sandbox.options());
    var buffer: [8]u8 = undefined;
    try t.expectError(error.FileNotFound, sandbox.temporary.dir.readLink(t.io, "ln", &buffer));
}

test "a link made through symlink_path is seen by stat, followed only inside the grant and refused by every other call" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try expectRooted(&sandbox,
        \\import filesystem
        \\func name(result: Result[str, str]) -> str:
        \\    match result:
        \\        case Ok(text):
        \\            return "ok " + text
        \\        case Err(message):
        \\            return copy(message)
        \\func note(result: Result[Unit, str]) -> str:
        \\    match result:
        \\        case Ok(_):
        \\            return "ok"
        \\        case Err(message):
        \\            return copy(message)
        \\func kind(fs: Filesystem, path: str) -> str:
        \\    match filesystem.stat(fs, path):
        \\        case Ok(info):
        \\            match info.kind:
        \\                case Symlink:
        \\                    return f"symlink {info.size} {info.mode}"
        \\                case Regular:
        \\                    return f"regular {info.size}"
        \\                case Directory:
        \\                    return "directory"
        \\                case Other:
        \\                    return "other"
        \\        case Err(error):
        \\            match error:
        \\                case Missing:
        \\                    return "missing"
        \\                case Failed(message=text):
        \\                    return copy(text)
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.mkdir("d")
        \\    _ = fs.write_text("d/f", "hello")
        \\    _ = filesystem.symlink(fs, "d/f", "ln")
        \\    _ = filesystem.symlink(fs, "d", "dl")
        \\    _ = filesystem.symlink(fs, "/etc", "abs")
        \\    _ = filesystem.symlink(fs, "..", "up")
        \\    if kind(fs, "ln") != "symlink 3 511" or kind(fs, "d/f") != "regular 5":
        \\        return 1
        \\    if name(filesystem.realpath(fs, "ln")) != "ok @ROOT@/d/f" or name(filesystem.realpath(fs, "dl/f")) != "ok @ROOT@/d/f":
        \\        return 2
        \\    if name(filesystem.realpath(fs, "abs")) != "realpath 'abs': resolves outside the granted directory":
        \\        return 3
        \\    if name(filesystem.realpath(fs, "up")) != "realpath 'up': resolves outside the granted directory":
        \\        return 4
        \\    if name(fs.read_text("ln")) != "read 'ln': is a symbolic link the sandbox does not follow, or links nest too deeply":
        \\        return 5
        \\    if name(fs.read_text("dl/f")) != "read 'dl/f': a parent of the path is not a directory":
        \\        return 6
        \\    if kind(fs, "dl/f") != "stat 'dl/f': is a symbolic link the sandbox does not follow, or links nest too deeply":
        \\        return 7
        \\    if note(filesystem.chmod(fs, "ln", 0o600)) != "chmod 'ln': a symbolic link has no permission bits of its own":
        \\        return 8
        \\    if note(fs.remove("ln")) != "ok" or kind(fs, "ln") != "missing" or kind(fs, "d/f") != "regular 5":
        \\        return 9
        \\    return 42
    , sandbox.options());
}

test "Stat.changed is the kernel's status-change time: set_modified can put the modification time back and cannot hide the change" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try fixture.expect(t.allocator,
        \\import filesystem
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.write_text("f", "hello")
        \\    _ = filesystem.set_modified(fs, "f", 1000000000123456789)
        \\    match filesystem.stat(fs, "f"):
        \\        case Ok(info):
        \\            if info.modified != 1000000000123456789:
        \\                return 1
        \\            if info.changed < 1700000000000000000 or info.changed == info.modified:
        \\                return 2
        \\            return 42
        \\        case Err(_):
        \\            return 3
    , sandbox.options(), 42);
}

/// `box` holds a file, a directory `sub` with a file and a link `up` back to `box`, and links that leave it (`link` to the
/// directory `outside`, `flink` to a file there) or stay inside it (`inlink`); `outside` holds a secret and a victim.
fn seedBox(sandbox: *files.Sandbox) !void {
    const dir = sandbox.temporary.dir;
    try dir.createDirPath(t.io, "box/sub");
    try dir.createDirPath(t.io, "outside");
    try dir.writeFile(t.io, .{ .sub_path = "outside/secret.txt", .data = "SECRET" });
    try dir.writeFile(t.io, .{ .sub_path = "outside/victim.txt", .data = "VICTIM" });
    try dir.writeFile(t.io, .{ .sub_path = "box/file.txt", .data = "inside" });
    try dir.writeFile(t.io, .{ .sub_path = "box/sub/in.txt", .data = "nested" });
    try dir.symLink(t.io, "../outside", "box/link", .{ .is_directory = true });
    try dir.symLink(t.io, "../outside/secret.txt", "box/flink", .{});
    try dir.symLink(t.io, "sub", "box/inlink", .{ .is_directory = true });
    try dir.symLink(t.io, "../../box", "box/sub/up", .{ .is_directory = true });
}

/// Require that nothing a program did through a narrowed handle reached `outside`: no file made, none changed, none removed.
fn expectOutsideUntouched(sandbox: *files.Sandbox) !void {
    const secret = try sandbox.temporary.dir.readFileAlloc(t.io, "outside/secret.txt", t.allocator, .limited(64));
    defer t.allocator.free(secret);
    try t.expectEqualStrings("SECRET", secret);
    const victim = try sandbox.temporary.dir.readFileAlloc(t.io, "outside/victim.txt", t.allocator, .limited(64));
    defer t.allocator.free(victim);
    try t.expectEqualStrings("VICTIM", victim);
    var outside = try sandbox.temporary.dir.openDir(t.io, "outside", .{ .iterate = true });
    defer outside.close(t.io);
    var count: usize = 0;
    var walker = outside.iterate();
    while (try walker.next(t.io)) |_| count += 1;
    try t.expectEqual(@as(usize, 2), count);
}

/// A narrowed handle on a program's own `Filesystem`, in any run: `narrowed` answers 0 when every call below refuses a link as a
/// granted directory does, and the number of the first that does not otherwise.
const narrowed_refusals =
    \\import filesystem
    \\func name(result: Result[str, str]) -> str:
    \\    match result:
    \\        case Ok(text):
    \\            return "ok " + text
    \\        case Err(message):
    \\            return copy(message)
    \\func note(result: Result[Unit, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func kind(fs: Filesystem, path: str) -> str:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            match info.kind:
    \\                case Symlink:
    \\                    return "symlink"
    \\                case Regular:
    \\                    return "regular"
    \\                case Directory:
    \\                    return "directory"
    \\                case Other:
    \\                    return "other"
    \\        case Err(error):
    \\            match error:
    \\                case Missing:
    \\                    return "missing"
    \\                case Failed(message=text):
    \\                    return copy(text)
    \\func listing(fs: Filesystem, path: str) -> str:
    \\    match fs.listdir(path):
    \\        case Ok(names):
    \\            return f"ok {len(names)}"
    \\        case Err(message):
    \\            return copy(message)
    \\func narrowed(fs: Filesystem) -> int:
    \\    const link = "is a symbolic link the sandbox does not follow, or links nest too deeply"
    \\    const parent = "a parent of the path is not a directory"
    \\    const box = fs.dir("box")
    \\    if name(box.read_text("file.txt")) != "ok inside" or name(box.read_text("sub/in.txt")) != "ok nested":
    \\        return 1
    \\    if name(box.read_text("link/secret.txt")) != f"read 'link/secret.txt': {parent}":
    \\        return 2
    \\    if name(box.read_text("flink")) != f"read 'flink': {link}":
    \\        return 3
    \\    if name(box.read_text("inlink/in.txt")) != f"read 'inlink/in.txt': {parent}":
    \\        return 4
    \\    if name(box.read_only().read_text("link/secret.txt")) != f"read 'link/secret.txt': {parent}":
    \\        return 5
    \\    const nested = fs.dir("box").dir("sub")
    \\    if name(nested.read_text("in.txt")) != "ok nested" or name(nested.read_text("up/file.txt")) != f"read 'up/file.txt': {parent}":
    \\        return 6
    \\    if name(fs.dir("box/link").read_text("secret.txt")) != f"read 'secret.txt': {parent}":
    \\        return 7
    \\    if listing(box, "sub") != "ok 2" or listing(box, "link") != "listdir 'link': is not a directory":
    \\        return 8
    \\    if listing(fs.dir("box/link"), "") != "listdir '': is not a directory":
    \\        return 9
    \\    if note(box.write_text("link/w.txt", "w")) != f"write 'link/w.txt': {parent}":
    \\        return 10
    \\    if note(box.write_text("flink", "w")) != f"write 'flink': {link}":
    \\        return 11
    \\    if note(box.mkdir("link/made")) != f"mkdir 'link/made': {parent}":
    \\        return 12
    \\    if note(box.remove("link/victim.txt")) != f"remove 'link/victim.txt': {parent}":
    \\        return 13
    \\    if kind(box, "link/secret.txt") != f"stat 'link/secret.txt': {link}" or kind(box, "flink") != "symlink":
    \\        return 14
    \\    if note(box.rename_path("link/victim.txt", "moved.txt")) != f"rename 'link/victim.txt' to 'moved.txt': {parent}":
    \\        return 15
    \\    if note(box.atomic_write_file("link/aw.txt", b"x")) != f"atomic write 'link/aw.txt': {parent}":
    \\        return 16
    \\    if note(filesystem.touch(box, "link/secret.txt")) != f"touch 'link/secret.txt': {parent}":
    \\        return 17
    \\    return 0
;

test "a directory narrowing refuses a link on the way, at the end and as its prefix under a grant" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedBox(&sandbox);
    try fixture.expect(t.allocator, narrowed_refusals ++ "\n" ++
        \\func main(fs: Filesystem) -> int:
        \\    return narrowed(fs)
    , sandbox.options(), 0);
    try expectOutsideUntouched(&sandbox);
}

test "a directory narrowing refuses them the same way in a run with no restriction, an unnarrowed handle follows them" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedBox(&sandbox);
    try expectUnrestricted(&sandbox, narrowed_refusals ++ "\n" ++
        \\func appended(fs: Filesystem, path: str) -> Unit fails str:
        \\    with try fs.open(path, "a") as file:
        \\        _ = file.write("A")
        \\    return
        \\func main(fs: Filesystem) -> int:
        \\    const link = "is a symbolic link the sandbox does not follow, or links nest too deeply"
        \\    const first = narrowed(fs)
        \\    if first != 0:
        \\        return first
        \\    if note(appended(fs.dir("box"), "flink")) != f"open 'flink': {link}":
        \\        return 30
        \\    if name(fs.read_text("box/link/secret.txt")) != "ok SECRET" or name(fs.read_text("box/flink")) != "ok SECRET":
        \\        return 31
        \\    if listing(fs, "box/link") != "ok 2" or kind(fs, "box/link/secret.txt") != "regular":
        \\        return 32
        \\    if name(fs.read_only().read_text("box/link/secret.txt")) != "ok SECRET":
        \\        return 33
        \\    if name(fs.dir("box/sub").read_text("in.txt")) != "ok nested":
        \\        return 34
        \\    match filesystem.stat_follow(fs.dir("box"), "inlink"):
        \\        case Ok(info):
        \\            if info.kind != filesystem.PathKind.Directory:
        \\                return 35
        \\        case Err(_):
        \\            return 36
        \\    match fs.dir("box").canonical_path("inlink/in.txt"):
        \\        case Ok(path):
        \\            if path != "sub/in.txt":
        \\                return 37
        \\        case Err(_):
        \\            return 38
        \\    return 42
    );
    try expectOutsideUntouched(&sandbox);
}

/// A `Filesystem` handle appends text to `path` and answers `Ok` or the refusal; the same three lines as the guest's own log.
const appended_to =
    \\func appended(fs: Filesystem, path: str, text: str) -> Unit fails str:
    \\    with try fs.open(path, "a") as file:
    \\        _ = file.write(text)
    \\    return
;

test "an append under a grant refuses a final link, writes nothing through it and creates nothing, a plain append still works" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedBox(&sandbox);
    try sandbox.temporary.dir.symLink(t.io, "../outside/new.txt", "box/dangling", .{});
    try sandbox.temporary.dir.symLink(t.io, "file.txt", "box/inside", .{});
    const granted = try std.fs.path.join(t.allocator, &.{ sandbox.path, "box" });
    defer t.allocator.free(granted);
    try fixture.expect(t.allocator, narrowed_refusals ++ "\n" ++ appended_to ++ "\n" ++
        \\func main(fs: Filesystem) -> int:
        \\    const link = "is a symbolic link the sandbox does not follow, or links nest too deeply"
        \\    if note(appended(fs, "flink", "A")) != f"open 'flink': {link}":
        \\        return 1
        \\    if note(appended(fs, "dangling", "A")) != f"open 'dangling': {link}":
        \\        return 2
        \\    if note(appended(fs, "inside", "A")) != f"open 'inside': {link}":
        \\        return 3
        \\    if note(appended(fs, "link/secret.txt", "A")) != f"open 'link/secret.txt': a parent of the path is not a directory":
        \\        return 4
        \\    if note(appended(fs, "file.txt", "+1")) != "ok" or note(appended(fs, "fresh.txt", "new")) != "ok":
        \\        return 5
        \\    if name(fs.read_text("file.txt")) != "ok inside+1" or name(fs.read_text("fresh.txt")) != "ok new":
        \\        return 6
        \\    if kind(fs, "dangling") != "symlink" or name(fs.read_text("flink")) != f"read 'flink': {link}":
        \\        return 7
        \\    return 0
    , .{ .directory = granted, .arguments = &sandbox.grant }, 0);
    try expectOutsideUntouched(&sandbox);
}

test "an unnarrowed Filesystem in a run with no restriction still appends through a final link, as an ordinary process does" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedBox(&sandbox);
    try sandbox.temporary.dir.symLink(t.io, "../outside/new.txt", "box/dangling", .{});
    try expectUnrestricted(&sandbox, narrowed_refusals ++ "\n" ++ appended_to ++ "\n" ++
        \\func main(fs: Filesystem) -> int:
        \\    if note(appended(fs, "box/flink", "A")) != "ok" or note(appended(fs, "box/dangling", "N")) != "ok":
        \\        return 1
        \\    if name(fs.read_text("box/flink")) != "ok SECRETA" or name(fs.read_text("outside/new.txt")) != "ok N":
        \\        return 2
        \\    return 42
    );
    const secret = try sandbox.temporary.dir.readFileAlloc(t.io, "outside/secret.txt", t.allocator, .limited(64));
    defer t.allocator.free(secret);
    try t.expectEqualStrings("SECRETA", secret);
    const created = try sandbox.temporary.dir.readFileAlloc(t.io, "outside/new.txt", t.allocator, .limited(64));
    defer t.allocator.free(created);
    try t.expectEqualStrings("N", created);
}

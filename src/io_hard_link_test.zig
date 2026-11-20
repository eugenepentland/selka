//! `filesystem.link` (a hard link) and `filesystem.mkdir_mode` (a folder made with its mode) through real directories. The
//! two names of a link are resolved as every durable call resolves a path (docs/io.md, "How a path is read"), so these tests
//! try to get out through the new calls the way `io_paths_escape_test.zig` does through the old ones: a source outside every
//! grant, a new name outside, a source that is only readable, a `..`, a symbolic link on the way or at the end, and a handle
//! narrowed by `fs.dir` or `fs.read_only`. Each states the refusal and checks that nothing outside the grants changed. Then
//! the archiver's case: two names for one file, and `Stat.links` reading 2 for both. The in-memory filesystem is pinned in
//! `tests/lang/filesystem_links.selka`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// The layout every test starts from, under one fresh directory `@ROOT@`: `g` (granted for writing) holding `a.txt`, `sub`,
/// a link out of it on the way (`out`, to `../secret`) and at the end (`outfile`, to `../secret/s.txt`); `g2` (a second
/// folder granted for writing, or a neighbour whose name starts with `g`); `r` (granted for reading); `secret` (granted to
/// nobody); and `glink`, a link to `g`.
const Box = struct {
    temporary: std.testing.TmpDir,
    root: [:0]u8,

    fn init() !Box {
        var box: Box = .{ .temporary = t.tmpDir(.{}), .root = undefined };
        errdefer box.temporary.cleanup();
        const dir = box.temporary.dir;
        try dir.createDirPath(t.io, "g/sub");
        try dir.createDirPath(t.io, "g2");
        try dir.createDirPath(t.io, "r");
        try dir.createDirPath(t.io, "secret");
        try dir.writeFile(t.io, .{ .sub_path = "g/a.txt", .data = "A" });
        try dir.writeFile(t.io, .{ .sub_path = "g/sub/b.txt", .data = "B" });
        try dir.writeFile(t.io, .{ .sub_path = "g2/x.txt", .data = "X2" });
        try dir.writeFile(t.io, .{ .sub_path = "r/c.txt", .data = "C" });
        try dir.writeFile(t.io, .{ .sub_path = "secret/s.txt", .data = "SECRET" });
        try dir.symLink(t.io, "../secret", "g/out", .{ .is_directory = true });
        try dir.symLink(t.io, "../secret/s.txt", "g/outfile", .{});
        try dir.symLink(t.io, "g", "glink", .{ .is_directory = true });
        box.root = try dir.realPathFileAlloc(t.io, ".", t.allocator);
        return box;
    }

    fn deinit(self: *Box) void {
        t.allocator.free(self.root);
        self.temporary.cleanup();
    }

    /// `@ROOT@` and `@UP@` (the folder that holds the root) in `text` replaced by their absolute names; the caller frees it.
    fn named(self: *const Box, text: []const u8) ![]u8 {
        const rooted = try std.mem.replaceOwned(u8, t.allocator, text, "@ROOT@", self.root);
        defer t.allocator.free(rooted);
        return std.mem.replaceOwned(u8, t.allocator, rooted, "@UP@", std.fs.path.dirname(self.root).?);
    }

    /// Run `program` from `@ROOT@/cwd` with `grants` (an empty list is a run with no restriction), and require its output to be
    /// `expected`; `@ROOT@` and `@UP@` are named in all three.
    fn expectPrinted(self: *const Box, cwd: []const u8, grants: []const []const u8, program: []const u8, expected: []const u8) !void {
        var arguments: std.ArrayList([]const u8) = .empty;
        defer {
            for (arguments.items[@min(arguments.items.len, 1)..]) |argument| t.allocator.free(argument);
            arguments.deinit(t.allocator);
        }
        if (grants.len > 0) try arguments.append(t.allocator, "--restrict");
        for (grants) |grant| try arguments.append(t.allocator, try self.named(grant));
        const directory = try std.fs.path.join(t.allocator, &.{ self.root, cwd });
        defer t.allocator.free(directory);
        const source = try self.named(program);
        defer t.allocator.free(source);
        const wanted = try self.named(expected);
        defer t.allocator.free(wanted);
        const outcome = try fixture.runOutcome(t.allocator, source, .{ .directory = directory, .arguments = arguments.items });
        try t.expectEqualStrings("", outcome.trap.code);
        try t.expectEqualStrings(wanted, outcome.stdout);
    }

    /// Nothing outside the grants changed, and nothing was made inside `g` either: `secret` holds only `s.txt` and it still reads
    /// `SECRET` (a hard link to it would share the inode, so a write through the link would change it), `g2` and `r` hold only what
    /// `init` made, `g` holds its four entries and the root its five.
    fn expectUntouched(self: *const Box) !void {
        try self.expectOutsideUntouched(4);
    }

    /// The same with `inside` entries in `g` (a test that makes folders there says how many).
    fn expectOutsideUntouched(self: *const Box, inside: usize) !void {
        const secret = try self.temporary.dir.readFileAlloc(t.io, "secret/s.txt", t.allocator, .limited(64));
        defer t.allocator.free(secret);
        try t.expectEqualStrings("SECRET", secret);
        try expectEntries(self.temporary.dir, "secret", 1);
        try expectEntries(self.temporary.dir, "g2", 1);
        try expectEntries(self.temporary.dir, "r", 1);
        try expectEntries(self.temporary.dir, "g", inside);
        try expectEntries(self.temporary.dir, ".", 5);
        try expectEntries(self.temporary.dir, "g/sub", 1);
    }
};

fn expectEntries(dir: std.Io.Dir, path: []const u8, wanted: usize) !void {
    var opened = try dir.openDir(t.io, path, .{ .iterate = true });
    defer opened.close(t.io);
    var count: usize = 0;
    var walker = opened.iterate();
    while (try walker.next(t.io)) |_| count += 1;
    try t.expectEqual(wanted, count);
}

/// The helpers every program shares: one `link` or `mkdir_mode` as one line (`ok` or the failure), and the number of links and
/// the permission bits `stat` reports (`-1` when it fails).
const helpers =
    \\import filesystem
    \\func done(result: Result[Unit, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func tried(fs: Filesystem, out: Stream, target: str, path: str) -> int:
    \\    print(out, done(filesystem.link(fs, target, path)))
    \\    return 0
    \\func made(fs: Filesystem, out: Stream, path: str, mode: int) -> int:
    \\    print(out, done(filesystem.mkdir_mode(fs, path, mode)))
    \\    return 0
    \\func links_of(fs: Filesystem, path: str) -> int:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return info.links
    \\        case Err(_):
    \\            return -1
    \\func mode_of(fs: Filesystem, path: str) -> int:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return info.mode
    \\        case Err(_):
    \\            return -1
    \\func inode_of(fs: Filesystem, path: str) -> u64:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return info.inode
    \\        case Err(_):
    \\            return 0
    \\
;

const outside = "denied: '@ROOT@/secret/s.txt' is outside the granted directories";
const link_text = "is a symbolic link the sandbox does not follow, or links nest too deeply";
const parent_text = "a parent of the path is not a directory";

test "from a restricted run a link whose source is outside every grant, only readable or outside by any spelling is refused and nothing changes" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = tried(fs, out, "secret/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "@ROOT@/secret/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "g/../secret/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "g/sub/../../secret/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "g2/x.txt", "g/stolen")
        \\    _ = tried(fs, out, "../secret/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "r/c.txt", "g/readable")
        \\    _ = tried(fs, out, "@ROOT@/r/c.txt", "g/readable")
        \\    return 0
        \\
    , "link 'secret/s.txt' to 'g/stolen': denied: '@ROOT@/secret/s.txt' is outside the granted directories\n" ++
        "link '@ROOT@/secret/s.txt' to 'g/stolen': denied: '@ROOT@/secret/s.txt' is outside the granted directories\n" ++
        "link 'g/../secret/s.txt' to 'g/stolen': denied: '@ROOT@/secret/s.txt' is outside the granted directories\n" ++
        "link 'g/sub/../../secret/s.txt' to 'g/stolen': denied: '@ROOT@/secret/s.txt' is outside the granted directories\n" ++
        "link 'g2/x.txt' to 'g/stolen': denied: '@ROOT@/g2/x.txt' is outside the granted directories\n" ++
        "link '../secret/s.txt' to 'g/stolen': denied: '@UP@/secret/s.txt' is outside the granted directories\n" ++
        "link 'r/c.txt' to 'g/readable': denied: writing needs a write grant (--allow-write); '@ROOT@/r/c.txt' is granted for reading only\n" ++
        "link '@ROOT@/r/c.txt' to 'g/readable': denied: writing needs a write grant (--allow-write); '@ROOT@/r/c.txt' is granted for reading only\n");
    try box.expectUntouched();
}

test "from a restricted run a link whose new name is outside every grant or in a read grant is refused and nothing changes" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = tried(fs, out, "g/a.txt", "secret/copy")
        \\    _ = tried(fs, out, "g/a.txt", "@ROOT@/secret/copy")
        \\    _ = tried(fs, out, "g/a.txt", "g/../secret/copy")
        \\    _ = tried(fs, out, "g/a.txt", "g/sub/../../secret/copy")
        \\    _ = tried(fs, out, "g/a.txt", "g2/copy")
        \\    _ = tried(fs, out, "g/a.txt", "../escape")
        \\    _ = tried(fs, out, "g/a.txt", "r/copy")
        \\    _ = tried(fs, out, "g/a.txt", "@ROOT@/g2/copy")
        \\    return 0
        \\
    , "link 'g/a.txt' to 'secret/copy': denied: '@ROOT@/secret/copy' is outside the granted directories\n" ++
        "link 'g/a.txt' to '@ROOT@/secret/copy': denied: '@ROOT@/secret/copy' is outside the granted directories\n" ++
        "link 'g/a.txt' to 'g/../secret/copy': denied: '@ROOT@/secret/copy' is outside the granted directories\n" ++
        "link 'g/a.txt' to 'g/sub/../../secret/copy': denied: '@ROOT@/secret/copy' is outside the granted directories\n" ++
        "link 'g/a.txt' to 'g2/copy': denied: '@ROOT@/g2/copy' is outside the granted directories\n" ++
        "link 'g/a.txt' to '../escape': denied: '@UP@/escape' is outside the granted directories\n" ++
        "link 'g/a.txt' to 'r/copy': denied: writing needs a write grant (--allow-write); '@ROOT@/r/copy' is granted for reading only\n" ++
        "link 'g/a.txt' to '@ROOT@/g2/copy': denied: '@ROOT@/g2/copy' is outside the granted directories\n");
    try box.expectUntouched();
}

test "from a restricted run a link through a symbolic link on the way or at the end, to a folder or onto a taken name is refused" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{"--allow-write=@ROOT@/g"}, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = tried(fs, out, "g/out/s.txt", "g/stolen")
        \\    _ = tried(fs, out, "g/a.txt", "g/out/copy")
        \\    _ = tried(fs, out, "g/outfile", "g/stolen")
        \\    _ = tried(fs, out, "g/out", "g/stolen")
        \\    _ = tried(fs, out, "glink/a.txt", "g/viaglink")
        \\    _ = tried(fs, out, "g/a.txt", "glink/viaglink")
        \\    _ = tried(fs, out, "g/sub", "g/folder")
        \\    _ = tried(fs, out, "g", "g/self")
        \\    _ = tried(fs, out, "g/a.txt", "g/sub/b.txt")
        \\    _ = tried(fs, out, "g/a.txt", "g/outfile")
        \\    _ = tried(fs, out, "g/nothing", "g/copy")
        \\    _ = tried(fs, out, "g/a.txt", "g/no/folder/copy")
        \\    return 0
        \\
    , "link 'g/out/s.txt' to 'g/stolen': " ++ parent_text ++ "\n" ++
        "link 'g/a.txt' to 'g/out/copy': " ++ parent_text ++ "\n" ++
        "link 'g/outfile' to 'g/stolen': " ++ link_text ++ "\n" ++
        "link 'g/out' to 'g/stolen': " ++ link_text ++ "\n" ++
        "link 'glink/a.txt' to 'g/viaglink': denied: '@ROOT@/glink/a.txt' is outside the granted directories\n" ++
        "link 'g/a.txt' to 'glink/viaglink': denied: '@ROOT@/glink/viaglink' is outside the granted directories\n" ++
        "link 'g/sub' to 'g/folder': is a directory\n" ++
        "link 'g' to 'g/self': is a directory\n" ++
        "link 'g/a.txt' to 'g/sub/b.txt': already exists\n" ++
        "link 'g/a.txt' to 'g/outfile': already exists\n" ++
        "link 'g/nothing' to 'g/copy': the path does not exist\n" ++
        "link 'g/a.txt' to 'g/no/folder/copy': the path does not exist\n");
    try box.expectUntouched();
}

test "a link whose source and new name are both in write grants works across two grants and across a working directory inside one" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("g", &.{ "--allow-write=@ROOT@/g", "--allow-write=@ROOT@/g2" }, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = tried(fs, out, "a.txt", "b.txt")
        \\    _ = tried(fs, out, "sub/b.txt", "sub/c.txt")
        \\    _ = tried(fs, out, "./a.txt", "sub/../d.txt")
        \\    _ = tried(fs, out, "@ROOT@/g/a.txt", "@ROOT@/g2/e.txt")
        \\    _ = tried(fs, out, "../secret/s.txt", "stolen")
        \\    print(out, links_of(fs, "a.txt"), links_of(fs, "b.txt"), links_of(fs, "d.txt"), links_of(fs, "../g2/e.txt"), links_of(fs, "sub/b.txt"))
        \\    print(out, inode_of(fs, "a.txt") == inode_of(fs, "b.txt"), inode_of(fs, "a.txt") == inode_of(fs, "../g2/e.txt"), inode_of(fs, "a.txt") == inode_of(fs, "sub/b.txt"))
        \\    _ = fs.write_text("b.txt", "written through b")
        \\    print(out, fs.read_text("a.txt"), fs.read_text("../g2/e.txt"))
        \\    _ = fs.remove("a.txt")
        \\    print(out, fs.exists("a.txt"), fs.read_text("b.txt"), links_of(fs, "b.txt"))
        \\    return 0
        \\
    , "ok\nok\nok\nok\n" ++
        "link '../secret/s.txt' to 'stolen': denied: '@ROOT@/secret/s.txt' is outside the granted directories\n" ++
        "4 4 4 4 2\n" ++
        "True True False\n" ++
        "Ok('written through b') Ok('written through b')\n" ++
        "False Ok('written through b') 3\n");
    const secret = try box.temporary.dir.readFileAlloc(t.io, "secret/s.txt", t.allocator, .limited(64));
    defer t.allocator.free(secret);
    try t.expectEqualStrings("SECRET", secret);
    try expectEntries(box.temporary.dir, "secret", 1);
}

const narrowed_text = "denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'";

test "on a handle narrowed to a folder a link whose source or new name leaves it, or goes through a link, is refused and nothing changes" {
    var box = try Box.init();
    defer box.deinit();
    // The same refusals with no restriction, under a read-write grant and under `--allow-write` of a parent: the narrowing's own rule.
    const program = helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    const narrow = fs.dir("g")
        \\    _ = tried(narrow, out, "../secret/s.txt", "stolen")
        \\    _ = tried(narrow, out, "a.txt", "../secret/copy")
        \\    _ = tried(narrow, out, "@ROOT@/secret/s.txt", "stolen")
        \\    _ = tried(narrow, out, "a.txt", "@ROOT@/secret/copy")
        \\    _ = tried(narrow, out, "sub/../../secret/s.txt", "stolen")
        \\    _ = tried(narrow, out, "a.txt", "sub/../../secret/copy")
        \\    _ = tried(narrow, out, "./a.txt", "dot")
        \\    _ = tried(narrow, out, "a.txt", "./dot")
        \\    _ = tried(narrow, out, "out/s.txt", "stolen")
        \\    _ = tried(narrow, out, "a.txt", "out/copy")
        \\    _ = tried(narrow, out, "outfile", "stolen")
        \\    _ = tried(narrow, out, "sub", "folder")
        \\    _ = tried(narrow, out, "", "empty")
        \\    _ = tried(narrow, out, "a.txt", "")
        \\    _ = tried(narrow, out, "a.txt", "sub/b.txt")
        \\    const readonly = fs.read_only()
        \\    _ = tried(readonly, out, "g/a.txt", "g/copy")
        \\    const reading = narrow.read_only()
        \\    _ = tried(reading, out, "a.txt", "copy")
        \\    return 0
        \\
    ;
    const expected = "link '../secret/s.txt' to 'stolen': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to '../secret/copy': " ++ narrowed_text ++ "\n" ++
        "link '@ROOT@/secret/s.txt' to 'stolen': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to '@ROOT@/secret/copy': " ++ narrowed_text ++ "\n" ++
        "link 'sub/../../secret/s.txt' to 'stolen': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to 'sub/../../secret/copy': " ++ narrowed_text ++ "\n" ++
        "link './a.txt' to 'dot': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to './dot': " ++ narrowed_text ++ "\n" ++
        "link 'out/s.txt' to 'stolen': " ++ parent_text ++ "\n" ++
        "link 'a.txt' to 'out/copy': " ++ parent_text ++ "\n" ++
        "link 'outfile' to 'stolen': " ++ link_text ++ "\n" ++
        "link 'sub' to 'folder': is a directory\n" ++
        "link '' to 'empty': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to '': " ++ narrowed_text ++ "\n" ++
        "link 'a.txt' to 'sub/b.txt': already exists\n" ++
        "link 'g/a.txt' to 'g/copy': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "link 'a.txt' to 'copy': denied: this Filesystem was narrowed by fs.read_only() and does not write\n";
    try box.expectPrinted("", &.{"--allow-write=@ROOT@"}, program, expected);
    try box.expectUntouched();
    try box.expectPrinted("", &.{}, program, expected);
    try box.expectUntouched();
}

test "an unrestricted run links as an ordinary process does and still refuses a folder and a symbolic link as the source" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("g", &.{}, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = tried(fs, out, "a.txt", "b.txt")
        \\    _ = tried(fs, out, "../g2/x.txt", "sub/../x2.txt")
        \\    _ = tried(fs, out, "@ROOT@/r/c.txt", "@ROOT@/r/c2.txt")
        \\    _ = tried(fs, out, "../glink", "folder")
        \\    _ = tried(fs, out, "outfile", "stolen")
        \\    _ = tried(fs, out, "out", "stolen")
        \\    _ = tried(fs, out, "sub", "folder")
        \\    _ = tried(fs, out, ".", "folder")
        \\    _ = tried(fs, out, "a.txt", "b.txt")
        \\    print(out, links_of(fs, "a.txt"), links_of(fs, "b.txt"), links_of(fs, "../g2/x.txt"), links_of(fs, "x2.txt"), links_of(fs, "../r/c2.txt"))
        \\    print(out, inode_of(fs, "a.txt") == inode_of(fs, "b.txt"), inode_of(fs, "a.txt") == inode_of(fs, "x2.txt"))
        \\    return 0
        \\
    , "ok\nok\nok\n" ++
        "link '../glink' to 'folder': " ++ link_text ++ "\n" ++
        "link 'outfile' to 'stolen': " ++ link_text ++ "\n" ++
        "link 'out' to 'stolen': " ++ link_text ++ "\n" ++
        "link 'sub' to 'folder': is a directory\n" ++
        "link '.' to 'folder': is a directory\n" ++
        "link 'a.txt' to 'b.txt': already exists\n" ++
        "2 2 2 2 2\nTrue False\n");
    // The kernel agrees: the two names are one file with two links, and a write through one is seen through the other.
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "g/b.txt", .data = "through b" });
    const seen = try box.temporary.dir.readFileAlloc(t.io, "g/a.txt", t.allocator, .limited(64));
    defer t.allocator.free(seen);
    try t.expectEqualStrings("through b", seen);
    const secret = try box.temporary.dir.readFileAlloc(t.io, "secret/s.txt", t.allocator, .limited(64));
    defer t.allocator.free(secret);
    try t.expectEqualStrings("SECRET", secret);
}

test "mkdir_mode makes a folder with its mode at creation, so a mode no umask could give is there before anything else" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = made(fs, out, "g/private", 0o700)
        \\    _ = made(fs, out, "g/trailing/", 0o500)
        \\    _ = made(fs, out, "g/closed", 0o000)
        \\    print(out, mode_of(fs, "g/private"), mode_of(fs, "g/trailing"), mode_of(fs, "g/closed"))
        \\    print(out, done(filesystem.chmod(fs, "g/closed", 0o755)), mode_of(fs, "g/closed"))
        \\    _ = made(fs, out, "g/private/inner", 0o700)
        \\    _ = made(fs, out, "g/private", 0o700)
        \\    _ = made(fs, out, "g/sub", 0o700)
        \\    _ = made(fs, out, "g/a.txt", 0o700)
        \\    _ = made(fs, out, "g/outfile", 0o700)
        \\    _ = made(fs, out, "g/no/deeper", 0o700)
        \\    _ = made(fs, out, "g/a.txt/inside", 0o700)
        \\    _ = made(fs, out, "g/bad", 0o10000)
        \\    _ = made(fs, out, "g/bad", -1)
        \\    print(out, mode_of(fs, "g/bad"))
        \\    return 0
        \\
    , "ok\nok\nok\n" ++
        "448 320 0\n" ++
        "ok 493\n" ++
        "ok\n" ++
        "mkdir 'g/private': already exists\n" ++
        "mkdir 'g/sub': already exists\n" ++
        "mkdir 'g/a.txt': already exists\n" ++
        "mkdir 'g/outfile': already exists\n" ++
        "mkdir 'g/no/deeper': the parent directory does not exist\n" ++
        "mkdir 'g/a.txt/inside': " ++ parent_text ++ "\n" ++
        "mkdir 'g/bad': the mode must be between 0 and 0o7777\n" ++
        "mkdir 'g/bad': the mode must be between 0 and 0o7777\n" ++
        "-1\n");
    try box.expectOutsideUntouched(7);
}

test "from a restricted run mkdir_mode outside every grant, in a read grant or through a link makes nothing" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = made(fs, out, "secret/new", 0o700)
        \\    _ = made(fs, out, "@ROOT@/secret/new", 0o700)
        \\    _ = made(fs, out, "g/../secret/new", 0o700)
        \\    _ = made(fs, out, "g/sub/../../secret/new", 0o700)
        \\    _ = made(fs, out, "g/../g2/new", 0o700)
        \\    _ = made(fs, out, "../new", 0o700)
        \\    _ = made(fs, out, "r/new", 0o700)
        \\    _ = made(fs, out, "g/out/new", 0o700)
        \\    _ = made(fs, out, "glink/new", 0o700)
        \\    _ = made(fs, out, "g/out/", 0o700)
        \\    _ = made(fs, out, "", 0o700)
        \\    _ = made(fs, out, "g/..", 0o700)
        \\    return 0
        \\
    , "mkdir 'secret/new': denied: '@ROOT@/secret/new' is outside the granted directories\n" ++
        "mkdir '@ROOT@/secret/new': denied: '@ROOT@/secret/new' is outside the granted directories\n" ++
        "mkdir 'g/../secret/new': denied: '@ROOT@/secret/new' is outside the granted directories\n" ++
        "mkdir 'g/sub/../../secret/new': denied: '@ROOT@/secret/new' is outside the granted directories\n" ++
        "mkdir 'g/../g2/new': denied: '@ROOT@/g2/new' is outside the granted directories\n" ++
        "mkdir '../new': denied: '@UP@/new' is outside the granted directories\n" ++
        "mkdir 'r/new': denied: writing needs a write grant (--allow-write); '@ROOT@/r/new' is granted for reading only\n" ++
        "mkdir 'g/out/new': " ++ parent_text ++ "\n" ++
        "mkdir 'glink/new': denied: '@ROOT@/glink/new' is outside the granted directories\n" ++
        "mkdir 'g/out/': already exists\n" ++
        "mkdir '': denied: '@ROOT@' is outside the granted directories\n" ++
        "mkdir 'g/..': denied: '@ROOT@' is outside the granted directories\n");
    try box.expectUntouched();
}

test "on a narrowed or read-only handle mkdir_mode makes a folder only inside the folder, and the plain run makes it as a process does" {
    var box = try Box.init();
    defer box.deinit();
    const program = helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    const narrow = fs.dir("g")
        \\    _ = made(narrow, out, "../secret/new", 0o700)
        \\    _ = made(narrow, out, "@ROOT@/secret/new", 0o700)
        \\    _ = made(narrow, out, "sub/../../secret/new", 0o700)
        \\    _ = made(narrow, out, "./dot", 0o700)
        \\    _ = made(narrow, out, "out/new", 0o700)
        \\    _ = made(narrow, out, "", 0o700)
        \\    _ = made(fs.read_only(), out, "g/new", 0o700)
        \\    _ = made(narrow.read_only(), out, "new", 0o700)
        \\    _ = made(narrow, out, "made", 0o700)
        \\    print(out, mode_of(fs, "g/made"))
        \\    return 0
        \\
    ;
    const expected = "mkdir '../secret/new': " ++ narrowed_text ++ "\n" ++
        "mkdir '@ROOT@/secret/new': " ++ narrowed_text ++ "\n" ++
        "mkdir 'sub/../../secret/new': " ++ narrowed_text ++ "\n" ++
        "mkdir './dot': " ++ narrowed_text ++ "\n" ++
        "mkdir 'out/new': " ++ parent_text ++ "\n" ++
        "mkdir '': " ++ narrowed_text ++ "\n" ++
        "mkdir 'g/new': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "mkdir 'new': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "ok\n448\n";
    try box.expectPrinted("", &.{"--allow-write=@ROOT@"}, program, expected);
    try box.expectOutsideUntouched(5);
    try box.temporary.dir.deleteDir(t.io, "g/made");
    try box.expectPrinted("", &.{}, program, expected);
    try box.expectOutsideUntouched(5);
    try box.temporary.dir.deleteDir(t.io, "g/made");
    try box.expectPrinted("g", &.{}, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    _ = made(fs, out, "sub/../plain", 0o700)
        \\    _ = made(fs, out, "../g2/plain", 0o700)
        \\    _ = made(fs, out, "@ROOT@/r/plain", 0o700)
        \\    print(out, mode_of(fs, "plain"), mode_of(fs, "../g2/plain"), mode_of(fs, "../r/plain"))
        \\    return 0
        \\
    , "ok\nok\nok\n448 448 448\n");
}

//! `filesystem.dir_at(fs, path)` narrows a `Filesystem` to a folder the program learns at run time (docs/io.md, "A folder
//! named at run time"), and narrowing only removes access. These tests try to get out of the folder through the handle it
//! returns, from a plain run and a restricted one, by a relative and an absolute name, and state the refusal each attempt
//! gets; then they check that nothing outside the folder changed. Then they run the folders the sample programs needed.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// The layout every test starts from, under one fresh directory `@ROOT@`: the working directory `work` with the folder
/// `out` (a file `in.txt`, a folder `sub`, and `link`, a link to `secret` that points out of it), a file and a link to
/// `secret` beside it (`file.txt`, `lk`); `secret`, which no handle narrowed to `out` may reach; and `far`, a working
/// directory away from `work`.
const Box = struct {
    temporary: std.testing.TmpDir,
    root: [:0]u8,

    fn init() !Box {
        var box: Box = .{ .temporary = t.tmpDir(.{}), .root = undefined };
        errdefer box.temporary.cleanup();
        const dir = box.temporary.dir;
        try dir.createDirPath(t.io, "work/out/sub");
        try dir.createDirPath(t.io, "secret");
        try dir.createDirPath(t.io, "far");
        try dir.writeFile(t.io, .{ .sub_path = "work/out/in.txt", .data = "IN\n" });
        try dir.writeFile(t.io, .{ .sub_path = "work/out/sub/b.txt", .data = "B\n" });
        try dir.writeFile(t.io, .{ .sub_path = "work/top.txt", .data = "TOP\n" });
        try dir.writeFile(t.io, .{ .sub_path = "work/file.txt", .data = "F\n" });
        try dir.writeFile(t.io, .{ .sub_path = "secret/s.txt", .data = "SECRET" });
        try dir.symLink(t.io, "../../secret", "work/out/link", .{ .is_directory = true });
        try dir.symLink(t.io, "../secret", "work/lk", .{ .is_directory = true });
        box.root = try dir.realPathFileAlloc(t.io, ".", t.allocator);
        return box;
    }

    fn deinit(self: *Box) void {
        t.allocator.free(self.root);
        self.temporary.cleanup();
    }

    /// `text` with `@DIR@` replaced by `folder` and then `@ROOT@` by the root's absolute name; the caller frees it.
    fn named(self: *const Box, text: []const u8, folder: []const u8) ![]u8 {
        const placed = try std.mem.replaceOwned(u8, t.allocator, text, "@DIR@", folder);
        defer t.allocator.free(placed);
        return std.mem.replaceOwned(u8, t.allocator, placed, "@ROOT@", self.root);
    }

    /// Run `program` (`@DIR@` naming `folder`) from `@ROOT@/cwd` with `grants` (none: a run with no restriction) and
    /// require its output to be `expected`, `@ROOT@` named in all three.
    fn expectPrinted(self: *const Box, run: Run, program: []const u8, expected: []const u8) !void {
        var arguments: std.ArrayList([]const u8) = .empty;
        defer {
            for (arguments.items[@min(arguments.items.len, 1)..]) |argument| t.allocator.free(argument);
            arguments.deinit(t.allocator);
        }
        if (run.grants.len > 0) try arguments.append(t.allocator, "--restrict");
        for (run.grants) |grant| try arguments.append(t.allocator, try self.named(grant, run.folder));
        const directory = try std.fs.path.join(t.allocator, &.{ self.root, run.cwd });
        defer t.allocator.free(directory);
        const source = try self.named(program, run.folder);
        defer t.allocator.free(source);
        const wanted = try self.named(expected, run.folder);
        defer t.allocator.free(wanted);
        const outcome = try fixture.runOutcome(t.allocator, source, .{ .directory = directory, .arguments = arguments.items });
        try t.expectEqualStrings("", outcome.trap.code);
        try t.expectEqualStrings(wanted, outcome.stdout);
    }

    /// Nothing outside the folder changed: `secret` holds only `s.txt`, which still reads `SECRET`, the root holds only
    /// what `init` made, and so does `work` when `work_entries` is its count.
    fn expectOutsideUntouched(self: *const Box, work_entries: usize) !void {
        const secret = try self.temporary.dir.readFileAlloc(t.io, "secret/s.txt", t.allocator, .limited(64));
        defer t.allocator.free(secret);
        try t.expectEqualStrings("SECRET", secret);
        try expectEntries(self.temporary.dir, "secret", 1);
        try expectEntries(self.temporary.dir, ".", 3);
        try expectEntries(self.temporary.dir, "work", work_entries);
        const top = try self.temporary.dir.readFileAlloc(t.io, "work/top.txt", t.allocator, .limited(64));
        defer t.allocator.free(top);
        try t.expectEqualStrings("TOP\n", top);
    }
};

/// One run: the working directory below `@ROOT@`, the grants (none for a plain run) and the folder `@DIR@` names.
const Run = struct { cwd: []const u8, grants: []const []const u8 = &.{}, folder: []const u8 = "out" };

fn expectEntries(dir: std.Io.Dir, path: []const u8, wanted: usize) !void {
    var opened = try dir.openDir(t.io, path, .{ .iterate = true });
    defer opened.close(t.io);
    var count: usize = 0;
    var walker = opened.iterate();
    while (try walker.next(t.io)) |_| count += 1;
    try t.expectEqual(wanted, count);
}

/// Run `program` in a fresh box for each of `runs`, require `expected` of every one and nothing outside to change.
fn expectEveryRun(runs: []const Run, program: []const u8, expected: []const u8, work_entries: usize) !void {
    for (runs) |run| {
        var box = try Box.init();
        defer box.deinit();
        try box.expectPrinted(run, program, expected);
        try box.expectOutsideUntouched(work_entries);
    }
}

/// Each result as one word: `ok`, `narrowed`, or the failure's text.
const helpers =
    \\import filesystem
    \\func said(result: Result[str, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func done(result: Result[Unit, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func listed(result: Result[str[], str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func described(result: Result[bytes, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func narrowed(result: Result[Filesystem, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "narrowed"
    \\        case Err(message):
    \\            return copy(message)
    \\
;

/// The four ways to name `out`: relative from `work` and absolute from `far`, each plain and under `--allow-write=work`.
const every_way = [_]Run{
    .{ .cwd = "work" },
    .{ .cwd = "far", .folder = "@ROOT@/work/out" },
    .{ .cwd = "work", .grants = &.{"--allow-write=@ROOT@/work"} },
    .{ .cwd = "far", .grants = &.{"--allow-write=@ROOT@/work"}, .folder = "@ROOT@/work/out" },
};

const narrowed_refusal = "denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'";
const parent = "a parent of the path is not a directory";

test "through a dir_at handle no spelling reaches outside its folder, plain or restricted, by a relative or an absolute name" {
    try expectEveryRun(&every_way, helpers ++
        \\func attempts(h: Filesystem, out: Stream):
        \\    print(out, said(h.read_text("../top.txt")))
        \\    print(out, said(h.read_text("@ROOT@/secret/s.txt")))
        \\    print(out, said(h.read_text("link/s.txt")))
        \\    print(out, done(h.write_text("link/new.txt", "x")))
        \\    print(out, done(h.write_text("../new.txt", "x")))
        \\    print(out, done(h.mkdir("../made")))
        \\    print(out, done(h.rename_path("in.txt", "../moved.txt")))
        \\    print(out, done(h.symlink_path("../../secret", "way")))
        \\    print(out, said(h.read_text("way/s.txt")))
        \\    print(out, said(h.read_text("in.txt/x")))
        \\    print(out, done(h.write_text("in.txt/x", "x")))
        \\    print(out, said(h.read_text("")))
        \\    print(out, listed(h.listdir("link")))
        \\    print(out, described(h.stat_path("..")))
        \\    print(out, said(filesystem.realpath(h, "link")))
        \\    print(out, h.exists("../top.txt"), h.exists("link/s.txt"))
        \\    print(out, narrowed(filesystem.dir_at(h, "..")))
        \\    print(out, narrowed(filesystem.dir_at(h, "link")))
        \\    print(out, narrowed(filesystem.dir_at(h, "@ROOT@/secret")))
        \\    print(out, h.read_text("in.txt"), filesystem.cwd(h))
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    match filesystem.dir_at(fs, "@DIR@"):
        \\        case Ok(h):
        \\            attempts(h, out)
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
        \\
    , "read '../top.txt': " ++ narrowed_refusal ++ "\n" ++
        "read '@ROOT@/secret/s.txt': " ++ narrowed_refusal ++ "\n" ++
        "read 'link/s.txt': " ++ parent ++ "\n" ++
        "write 'link/new.txt': " ++ parent ++ "\n" ++
        "write '../new.txt': " ++ narrowed_refusal ++ "\n" ++
        "mkdir '../made': " ++ narrowed_refusal ++ "\n" ++
        "rename 'in.txt' to '../moved.txt': " ++ narrowed_refusal ++ "\n" ++
        "ok\n" ++
        "read 'way/s.txt': " ++ parent ++ "\n" ++
        "read 'in.txt/x': " ++ parent ++ "\n" ++
        "write 'in.txt/x': " ++ parent ++ "\n" ++
        "read '': " ++ narrowed_refusal ++ "\n" ++
        "listdir 'link': is not a directory\n" ++
        "stat '..': " ++ narrowed_refusal ++ "\n" ++
        "realpath 'link': resolves outside the granted directory\n" ++
        "False False\n" ++
        "dir_at '..': " ++ narrowed_refusal ++ "\n" ++
        "dir_at 'link': is a symbolic link the sandbox does not follow\n" ++
        "dir_at '@ROOT@/secret': " ++ narrowed_refusal ++ "\n" ++
        "Ok('IN\\n') Ok('')\n", 4);
}

test "a link made in the folder after the narrowing, and the folder replaced by a link, are refused at the next call" {
    // The folder is renamed away and `@DIR@` becomes a link to `secret`; then a real folder is put back at the name, which
    // the handle names from then on, as a `fs.dir` handle does (it keeps the name, not the folder).
    try expectEveryRun(&every_way, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    match filesystem.dir_at(fs, "@DIR@"):
        \\        case Ok(h):
        \\            print(out, done(filesystem.symlink(fs, "../../secret", "@DIR@/later")))
        \\            print(out, said(h.read_text("later/s.txt")))
        \\            print(out, done(h.write_text("later/new.txt", "x")))
        \\            print(out, narrowed(filesystem.dir_at(h, "later")))
        \\            print(out, done(fs.rename_path("@DIR@", "@DIR@.old")))
        \\            print(out, done(filesystem.symlink(fs, "@ROOT@/secret", "@DIR@")))
        \\            print(out, said(h.read_text("s.txt")))
        \\            print(out, done(h.write_text("s.txt", "overwritten")))
        \\            print(out, done(h.write_text("fresh.txt", "x")))
        \\            print(out, listed(h.listdir("")))
        \\            print(out, described(h.stat_path("s.txt")))
        \\            print(out, h.exists("s.txt"))
        \\            print(out, done(fs.remove("@DIR@")), done(fs.mkdir("@DIR@")))
        \\            print(out, done(h.write_text("again.txt", "y")), fs.exists("@DIR@/again.txt"))
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
        \\
    , "ok\n" ++
        "read 'later/s.txt': " ++ parent ++ "\n" ++
        "write 'later/new.txt': " ++ parent ++ "\n" ++
        "dir_at 'later': is a symbolic link the sandbox does not follow\n" ++
        "ok\nok\n" ++
        "read 's.txt': " ++ parent ++ "\n" ++
        "write 's.txt': " ++ parent ++ "\n" ++
        "write 'fresh.txt': " ++ parent ++ "\n" ++
        "listdir '': is not a directory\n" ++
        "stat 's.txt': is a symbolic link the sandbox does not follow, or links nest too deeply\n" ++
        "False\n" ++
        "ok ok\n" ++
        "ok True\n", 5);
}

test "a dir_at handle narrowed again goes further in and never names its parent, and a read-only one stays read-only" {
    const runs = [_]Run{ .{ .cwd = "work" }, .{ .cwd = "work", .grants = &.{"--allow-write=@ROOT@/work"} } };
    try expectEveryRun(&runs, helpers ++
        \\func body(fs: Filesystem, out: Stream) -> Unit fails str:
        \\    const h = try filesystem.dir_at(fs, "out")
        \\    const s = try filesystem.dir_at(h, "sub")
        \\    print(out, s.read_text("b.txt"), filesystem.cwd(s))
        \\    print(out, said(s.read_text("../in.txt")))
        \\    print(out, narrowed(filesystem.dir_at(s, "..")))
        \\    print(out, narrowed(filesystem.dir_at(s, ".")))
        \\    print(out, narrowed(filesystem.dir_at(h, "sub/..")))
        \\    print(out, narrowed(filesystem.dir_at(h, "../out")))
        \\    print(out, described(s.stat_path("..")))
        \\    print(out, said(filesystem.realpath(s, "..")))
        \\    print(out, listed(s.listdir("..")))
        \\    const ro = try filesystem.dir_at(fs.read_only(), "out")
        \\    print(out, ro.read_text("in.txt"))
        \\    print(out, done(ro.write_text("in.txt", "changed")))
        \\    print(out, done(ro.mkdir("made")))
        \\    print(out, done(filesystem.touch(ro, "in.txt")))
        \\    const deeper = try filesystem.dir_at(ro, "sub")
        \\    print(out, done(deeper.write_text("b.txt", "changed")))
        \\    print(out, fs.read_text("out/in.txt"), fs.read_text("out/sub/b.txt"))
        \\    return ()
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    match body(fs, out):
        \\        case Ok(_):
        \\            return 0
        \\        case Err(message):
        \\            print(out, message)
        \\            return 1
        \\
    , "Ok('B\\n') Ok('')\n" ++
        "read '../in.txt': " ++ narrowed_refusal ++ "\n" ++
        "dir_at '..': " ++ narrowed_refusal ++ "\n" ++
        "dir_at '.': " ++ narrowed_refusal ++ "\n" ++
        "dir_at 'sub/..': " ++ narrowed_refusal ++ "\n" ++
        "dir_at '../out': " ++ narrowed_refusal ++ "\n" ++
        "stat '..': " ++ narrowed_refusal ++ "\n" ++
        "realpath '..': " ++ narrowed_refusal ++ "\n" ++
        "listdir '..': " ++ narrowed_refusal ++ "\n" ++
        "Ok('IN\\n')\n" ++
        "write 'in.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "mkdir 'made': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "touch 'in.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "write 'b.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write\n" ++
        "Ok('IN\\n') Ok('B\\n')\n", 4);
}

test "under a read grant alone a dir_at handle reads and does not write" {
    try expectEveryRun(&.{.{ .cwd = "work", .grants = &.{"--allow-read=@ROOT@/work"} }}, helpers ++
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    match filesystem.dir_at(fs, "out"):
        \\        case Ok(h):
        \\            print(out, h.read_text("in.txt"))
        \\            print(out, done(h.write_text("in.txt", "changed")))
        \\            print(out, done(h.mkdir("made")))
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
        \\
    , "Ok('IN\\n')\n" ++
        "write 'in.txt': denied: writing needs a write grant (--allow-write); '@ROOT@/work/out/in.txt' is granted for reading only\n" ++
        "mkdir 'made': denied: writing needs a write grant (--allow-write); '@ROOT@/work/out/made' is granted for reading only\n", 4);
}

/// `dir_at` on each path that must not be narrowed to, and on two that name a folder outside `work`.
const refused_paths = helpers ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    for path in ["", "lk", "lk/", "out/link", "lk/..", "out/link/..", "file.txt", "absent", "out/in.txt/..", "out\x00x", "../secret", "@ROOT@/secret"]:
    \\        print(out, narrowed(filesystem.dir_at(fs, path)))
    \\    return 0
    \\
;

test "dir_at refuses an empty path, a link, a link on the way, a .. out of a link, a file, nothing and a NUL" {
    const common = "dir_at '': the path is empty; '.' names the working directory\n" ++
        "dir_at 'lk': is a symbolic link the sandbox does not follow\n";
    const end = "dir_at 'out/link': is a symbolic link the sandbox does not follow\n";
    const tail = "dir_at 'file.txt': is not a directory\n" ++
        "dir_at 'absent': no such file or directory\n" ++
        "dir_at 'out/in.txt/..': " ++ parent ++ "\n" ++
        "dir_at 'out\x00x': the path contains a NUL octet\n";
    // A plain run reaches every folder, so `../secret` is narrowed to; a `..` out of a link is the climb check's refusal.
    try expectEveryRun(&.{.{ .cwd = "work" }}, refused_paths, common ++
        "dir_at 'lk/': is a symbolic link the sandbox does not follow\n" ++ end ++
        "dir_at 'lk/..': is a symbolic link the sandbox does not follow\n" ++
        "dir_at 'out/link/..': is a symbolic link the sandbox does not follow\n" ++ tail ++
        "narrowed\nnarrowed\n", 4);
    // Under `--restrict` the grant's resolver meets the links first, in its own words, and `secret` is outside.
    try expectEveryRun(&.{.{ .cwd = "work", .grants = &.{"--allow-write=@ROOT@/work"} }}, refused_paths, common ++
        "dir_at 'lk/': is a symbolic link the sandbox does not follow, or links nest too deeply\n" ++ end ++
        "dir_at 'lk/..': " ++ parent ++ "\n" ++
        "dir_at 'out/link/..': " ++ parent ++ "\n" ++ tail ++
        "dir_at '../secret': denied: '@ROOT@/secret' is outside the granted directories\n" ++
        "dir_at '@ROOT@/secret': denied: '@ROOT@/secret' is outside the granted directories\n", 4);
}

/// A plain read through `alias` (a link to `out`), `dir_at` on the link, on it with a slash, by its absolute name, on a
/// folder through it, on the real folder and one below it, `fs.dir("alias")` (a literal) and `dir_at` on a `read_only()`
/// handle and on the literal's handle.
const through_alias = helpers ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("alias/in.txt")))
    \\    for path in ["alias", "alias/", "@ROOT@/work/alias", "alias/sub", "out", "out/sub"]:
    \\        print(out, narrowed(filesystem.dir_at(fs, path)))
    \\    const literal = fs.dir("alias")
    \\    print(out, said(literal.read_text("in.txt")))
    \\    print(out, narrowed(filesystem.dir_at(fs.read_only(), "alias")), narrowed(filesystem.dir_at(literal, "sub")))
    \\    return 0
    \\
;

/// Run `through_alias` from `work` with `grants`, the link `work/alias` to `out` made first, and require `expected`.
fn expectThroughAlias(grants: []const []const u8, expected: []const u8) !void {
    var box = try Box.init();
    defer box.deinit();
    try box.temporary.dir.symLink(t.io, "out", "work/alias", .{ .is_directory = true });
    try box.expectPrinted(.{ .cwd = "work", .grants = grants }, through_alias, expected);
    try box.expectOutsideUntouched(5);
}

// DIRAT-LINK: `dir_at` refuses a folder its path reaches through a symbolic link under a grant as in a plain run, whether
// the grant names the link, its parent or the real folder; a plain read through a grant that names the link still works.
test "dir_at refuses a symbolic link under a grant that names the link, its parent or the real folder, as a plain run does" {
    const link = "is a symbolic link the sandbox does not follow";
    const on_the_way = link ++ ", or links nest too deeply";
    const refusals = "dir_at 'alias': " ++ link ++ "\n";
    const absolute = "dir_at '@ROOT@/work/alias': " ++ link ++ "\n" ++ "dir_at 'alias/sub': " ++ on_the_way ++ "\n";
    const below = "dir_at 'sub': " ++ on_the_way ++ "\n";
    // A plain run follows the link for a plain read and refuses it everywhere else.
    try expectThroughAlias(&.{}, "ok\n" ++ refusals ++ "dir_at 'alias/': " ++ link ++ "\n" ++ absolute ++
        "narrowed\nnarrowed\nread 'in.txt': " ++ parent ++ "\n" ++ "dir_at 'alias': " ++ link ++ " " ++ below);
    // A grant that names the link: a plain read follows it, `dir_at` and `fs.dir("alias")` do not (DIR-LITERAL-LINK).
    try expectThroughAlias(&.{"--allow-read=@ROOT@/work/alias"}, "ok\n" ++ refusals ++ "dir_at 'alias/': " ++ link ++ "\n" ++
        absolute ++ "narrowed\nnarrowed\nread 'in.txt': " ++ parent ++ "\n" ++ "dir_at 'alias': " ++ link ++ " " ++ below);
    // A grant that names the parent: the walk below it meets the link.
    try expectThroughAlias(&.{"--allow-read=@ROOT@/work"}, "read 'alias/in.txt': " ++ parent ++ "\n" ++ refusals ++
        "dir_at 'alias/': " ++ on_the_way ++ "\n" ++ absolute ++ "narrowed\nnarrowed\nread 'in.txt': " ++ parent ++ "\n" ++
        "dir_at 'alias': " ++ link ++ " " ++ below);
    // A grant that names the real folder: the link's own name is outside it, which is the refusal, as for a plain read.
    const outside = "' is outside the granted directories";
    try expectThroughAlias(&.{"--allow-read=@ROOT@/work/out"}, "read 'alias/in.txt': denied: '@ROOT@/work/alias/in.txt" ++
        outside ++ "\n" ++ "dir_at 'alias': denied: '@ROOT@/work/alias" ++ outside ++ "\n" ++
        "dir_at 'alias/': denied: '@ROOT@/work/alias" ++ outside ++ "\n" ++
        "dir_at '@ROOT@/work/alias': denied: '@ROOT@/work/alias" ++ outside ++ "\n" ++
        "dir_at 'alias/sub': denied: '@ROOT@/work/alias/sub" ++ outside ++ "\n" ++ "narrowed\nnarrowed\n" ++
        "read 'in.txt': denied: '@ROOT@/work/alias/in.txt" ++ outside ++ "\n" ++
        "dir_at 'alias': denied: '@ROOT@/work/alias" ++ outside ++ " dir_at 'sub': denied: '@ROOT@/work/alias/sub" ++ outside ++ "\n");
}

/// A plain read through `alias` (a link to `out`), then a read, a write, two listings and a `stat` through `fs.dir("alias")`,
/// through it narrowed by `read_only()` first, and through `fs.dir("alias/sub")`, each written as a literal.
const literal_alias = helpers ++
    \\func show(out: Stream, h: Filesystem):
    \\    print(out, said(h.read_text("in.txt")), "|", done(h.write_text("w.txt", "x")), "|", listed(h.listdir("")))
    \\    print(out, listed(h.listdir("sub")), "|", described(h.stat_path("in.txt")))
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("alias/in.txt")))
    \\    show(out, fs.dir("alias"))
    \\    show(out, fs.read_only().dir("alias"))
    \\    show(out, fs.dir("alias/sub"))
    \\    return 0
    \\
;

/// Run `literal_alias` from `work` with `grants`, the link `work/alias` to `out` made first, and require `expected`.
fn expectLiteralAlias(grants: []const []const u8, expected: []const u8) !void {
    var box = try Box.init();
    defer box.deinit();
    try box.temporary.dir.symLink(t.io, "out", "work/alias", .{ .is_directory = true });
    try box.expectPrinted(.{ .cwd = "work", .grants = grants }, literal_alias, expected);
    try box.expectOutsideUntouched(5);
}

// DIR-LITERAL-LINK: every call on `fs.dir` with a literal whose folder a grant's name reaches through a symbolic link is
// refused under `--restrict` as in a plain run, with the same reasons; a plain read through a grant on the link still works.
test "fs.dir with a literal through a symbolic link is refused under a grant on the link or its parent as in a plain run" {
    const loop = "is a symbolic link the sandbox does not follow, or links nest too deeply";
    const read_only = "write 'w.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write";
    const tail = "listdir 'sub': " ++ parent ++ " | stat 'in.txt': " ++ loop ++ "\n";
    const handles = "read 'in.txt': " ++ parent ++ " | write 'w.txt': " ++ parent ++ " | listdir '': is not a directory\n" ++ tail ++
        "read 'in.txt': " ++ parent ++ " | " ++ read_only ++ " | listdir '': is not a directory\n" ++ tail ++
        "read 'in.txt': " ++ parent ++ " | write 'w.txt': " ++ parent ++ " | listdir '': " ++ parent ++ "\n" ++ tail;
    try expectLiteralAlias(&.{}, "ok\n" ++ handles);
    try expectLiteralAlias(&.{"--allow-write=@ROOT@/work/alias"}, "ok\n" ++ handles);
    try expectLiteralAlias(&.{"--allow-write=@ROOT@/work"}, "read 'alias/in.txt': " ++ parent ++ "\n" ++ handles);
    // A grant on the real folder: the link's own name is outside it, for the plain read and every handle.
    const outside = "' is outside the granted directories";
    const away = "listdir 'sub': denied: '@ROOT@/work/alias/sub" ++ outside ++ " | stat 'in.txt': denied: '@ROOT@/work/alias/in.txt" ++
        outside ++ "\n";
    try expectLiteralAlias(&.{"--allow-write=@ROOT@/work/out"}, "read 'alias/in.txt': denied: '@ROOT@/work/alias/in.txt" ++ outside ++
        "\n" ++ "read 'in.txt': denied: '@ROOT@/work/alias/in.txt" ++ outside ++ " | write 'w.txt': denied: '@ROOT@/work/alias/w.txt" ++
        outside ++ " | listdir '': denied: '@ROOT@/work/alias" ++ outside ++ "\n" ++ away ++
        "read 'in.txt': denied: '@ROOT@/work/alias/in.txt" ++ outside ++ " | " ++ read_only ++ " | listdir '': denied: '@ROOT@/work/alias" ++
        outside ++ "\n" ++ away ++ "read 'in.txt': denied: '@ROOT@/work/alias/sub/in.txt" ++ outside ++
        " | write 'w.txt': denied: '@ROOT@/work/alias/sub/w.txt" ++ outside ++ " | listdir '': denied: '@ROOT@/work/alias/sub" ++ outside ++
        "\n" ++ "listdir 'sub': denied: '@ROOT@/work/alias/sub/sub" ++ outside ++ " | stat 'in.txt': denied: '@ROOT@/work/alias/sub/in.txt" ++
        outside ++ "\n");
}

/// The folders the sample programs needed (SP1-F-1, SP2-F-7): one written, listed, linked inside and cleaned up through
/// each spelling, its contents checked through the unnarrowed handle.
const sample_folders = helpers ++
    \\func use(fs: Filesystem, out: Stream, path: str, check: str):
    \\    match filesystem.dir_at(fs, path):
    \\        case Ok(h):
    \\            print(out, done(h.write_text("made.txt", "by dir_at")), filesystem.cwd(h), fs.read_text(check))
    \\            print(out, done(h.mkdir("d")), done(h.write_text("d/deeper.txt", "x")), h.listdir("d"))
    \\            print(out, done(filesystem.symlink(h, "made.txt", "alias")), filesystem.read_link(h, "alias"), filesystem.realpath(h, "d"))
    \\            print(out, done(h.remove("d/deeper.txt")), done(h.remove("d")), done(h.remove("alias")), done(h.remove("made.txt")))
    \\        case Err(message):
    \\            print(out, message)
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    use(fs, out, "@ROOT@/work/out", "@ROOT@/work/out/made.txt")
    \\    use(fs, out, "@ROOT@/work/out/sub/", "@ROOT@/work/out/sub/made.txt")
    \\    use(fs, out, "@DIR@out", "@ROOT@/work/out/made.txt")
    \\    use(fs, out, "@DIR@./out/sub/../sub", "@ROOT@/work/out/sub/made.txt")
    \\    use(fs, out, ".", "made.txt")
    \\    return 0
    \\
;

test "the sample programs' folders work: absolute, relative and ., from inside the grant and far from it, restricted or not" {
    const one = "ok Ok('') Ok('by dir_at')\n" ++
        "ok ok Ok(['deeper.txt'])\n" ++
        "ok Ok('made.txt') Ok('d')\n" ++
        "ok ok ok ok\n";
    const five = one ++ one ++ one ++ one ++ one;
    const runs = [_]Run{
        .{ .cwd = "work", .folder = "" },
        .{ .cwd = "work", .grants = &.{"--allow-write=@ROOT@/work"}, .folder = "" },
        .{ .cwd = "far", .folder = "../work/" },
        .{ .cwd = "far", .grants = &.{ "--allow-write=@ROOT@/work", "--allow-write=@ROOT@/far" }, .folder = "../work/" },
    };
    try expectEveryRun(&runs, sample_folders, five, 4);
}

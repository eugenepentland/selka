//! A path means the same file in a restricted run and a plain one (docs/io.md, "How a path is read"): under `--restrict`
//! it is resolved as an ordinary process resolves it and must then fall inside a granted directory. These tests try to
//! get out of the grants with every spelling the rule has to survive, through every kind of call, from a working
//! directory inside a grant, beside it and far from it, and state the refusal each one gets. Then they run the
//! spellings that must now work, restricted and plain, and require the same answers.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// The layout every test starts from, under one fresh directory `@ROOT@`: `g` (granted for writing) with a link out of it
/// on the way (`g/out`) and at the end (`g/outfile`), `g2` (a neighbour whose name starts with `g`), `r` (granted for
/// reading), `secret` (granted to nobody), a far working directory and `glink`, a link to `g`.
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
        try dir.createDirPath(t.io, "far/deep");
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

    /// Run `program` (with `@ROOT@` named) from `@ROOT@/cwd` with `grants` (each with `@ROOT@` named), and require its
    /// output to be `expected` (with `@ROOT@` and `@UP@` named). An empty `grants` is a run with no restriction.
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

    /// Nothing outside the grants changed: `secret` holds only `s.txt` and it still reads `SECRET`, `g2` holds only
    /// `x.txt`, and the root holds only what `init` made.
    fn expectOutsideUntouched(self: *const Box) !void {
        const secret = try self.temporary.dir.readFileAlloc(t.io, "secret/s.txt", t.allocator, .limited(64));
        defer t.allocator.free(secret);
        try t.expectEqualStrings("SECRET", secret);
        try expectEntries(self.temporary.dir, "secret", 1);
        try expectEntries(self.temporary.dir, "g2", 1);
        try expectEntries(self.temporary.dir, ".", 6);
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

/// Every kind of call on one path, one line each: read, write, append, mkdir, rename into and out of it (the other end
/// `@ROOT@/g/a.txt`), symlink, listdir, list_entries, stat and exists. A call that succeeds prints `ok`.
const every_call =
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
    \\func entries(fs: Filesystem, path: str) -> str:
    \\    match filesystem.list_entries(fs, path):
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func appended(fs: Filesystem, path: str) -> Unit fails str:
    \\    with try fs.open(path, "a") as file:
    \\        _ = file.write("!")
    \\    return
    \\func every(fs: Filesystem, out: Stream, path: str) -> int:
    \\    const inside = "@ROOT@/g/a.txt"
    \\    print(out, said(fs.read_text(path)))
    \\    print(out, done(fs.write_text(path, "x")))
    \\    print(out, done(appended(fs, path)))
    \\    print(out, done(fs.mkdir(path)))
    \\    print(out, done(fs.rename_path(inside, path)))
    \\    print(out, done(fs.rename_path(path, inside)))
    \\    print(out, done(fs.symlink_path("x", path)))
    \\    print(out, listed(fs.listdir(path)))
    \\    print(out, entries(fs, path))
    \\    print(out, described(fs.stat_path(path)))
    \\    print(out, fs.exists(path))
    \\    return 0
    \\
;

/// The eleven lines `every` prints for `path` when each call is refused because it resolves to `resolved`, outside
/// every grant. The caller frees the text.
fn refusedEverywhere(path: []const u8, resolved: []const u8) ![]u8 {
    const outside = try std.fmt.allocPrint(t.allocator, "denied: '{s}' is outside the granted directories", .{resolved});
    defer t.allocator.free(outside);
    return std.fmt.allocPrint(t.allocator,
        \\read '{0s}': {1s}
        \\write '{0s}': {1s}
        \\open '{0s}': {1s}
        \\mkdir '{0s}': {1s}
        \\rename '@ROOT@/g/a.txt' to '{0s}': {1s}
        \\rename '{0s}' to '@ROOT@/g/a.txt': {1s}
        \\symlink '{0s}': {1s}
        \\listdir '{0s}': {1s}
        \\directory listing '{0s}': {1s}
        \\stat '{0s}': {1s}
        \\False
        \\
    , .{ path, outside });
}

/// Run `every` on each of `cases` (a path and what it resolves to, `@ROOT@` and `@UP@` standing for the absolute names)
/// from `@ROOT@/cwd` under `--allow-write=@ROOT@/g --allow-read=@ROOT@/r`, require every call to be refused as outside
/// the grants, and nothing outside them to change.
fn expectEscapesRefused(cwd: []const u8, cases: []const [2][]const u8) !void {
    var box = try Box.init();
    defer box.deinit();
    var program: std.ArrayList(u8) = .empty;
    defer program.deinit(t.allocator);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(t.allocator);
    try program.appendSlice(t.allocator, every_call ++ "func main(fs: Filesystem, out: Stream) -> int:\n");
    for (cases) |case| {
        try program.print(t.allocator, "    _ = every(fs, out, \"{s}\")\n", .{case[0]});
        const lines = try refusedEverywhere(case[0], case[1]);
        defer t.allocator.free(lines);
        try expected.appendSlice(t.allocator, lines);
    }
    try program.appendSlice(t.allocator, "    return 0\n");
    try box.expectPrinted(cwd, &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, program.items, expected.items);
    try box.expectOutsideUntouched();
}

test "from a working directory inside the grant, no spelling of a path outside it reaches it through any call" {
    try expectEscapesRefused("g", &.{
        .{ "../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "./../secret//s.txt", "@ROOT@/secret/s.txt" },
        .{ "sub/../../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "../g2/x.txt", "@ROOT@/g2/x.txt" },
        .{ "../../escape", "@UP@/escape" },
        .{ "/etc/hostname", "/etc/hostname" },
        .{ "@ROOT@/secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "@ROOT@/g/../secret/s.txt", "@ROOT@/secret/s.txt" },
    });
}

test "from a working directory beside the grant, g/../../x, a neighbour named like the grant and the folder itself are outside" {
    try expectEscapesRefused("", &.{
        .{ "g/../../x", "@UP@/x" },
        .{ "g/../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "g/sub/../../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "g2/x.txt", "@ROOT@/g2/x.txt" },
        .{ "g/../g2/x.txt", "@ROOT@/g2/x.txt" },
        .{ "secret//s.txt", "@ROOT@/secret/s.txt" },
        .{ ".", "@ROOT@" },
        .{ "//", "/" },
    });
}

test "from a working directory far from the grant, a path climbing past it or into a neighbour is outside" {
    try expectEscapesRefused("far/deep", &.{
        .{ "../../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "../../g/../secret/s.txt", "@ROOT@/secret/s.txt" },
        .{ "../../g2/x.txt", "@ROOT@/g2/x.txt" },
        .{ "../../g/../../escape", "@UP@/escape" },
        .{ "@ROOT@/g2/x.txt", "@ROOT@/g2/x.txt" },
        .{ "a.txt", "@ROOT@/far/deep/a.txt" },
    });
}

/// Reads, appends, listings and stats through the links of `Box` and a link made after the run started, each line the
/// answer of one call.
const through_links = every_call ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("g/out/s.txt")))
    \\    print(out, done(fs.write_text("g/out/new.txt", "x")))
    \\    print(out, listed(fs.listdir("g/out")))
    \\    print(out, entries(fs, "g/out/"))
    \\    print(out, described(fs.stat_path("g/out/s.txt")))
    \\    print(out, said(fs.read_text("g/outfile")))
    \\    print(out, done(fs.write_text("g/outfile", "x")))
    \\    print(out, done(appended(fs, "g/outfile")))
    \\    print(out, said(fs.read_text("g/out/../a.txt")))
    \\    print(out, done(fs.symlink_path("../secret", "g/later")))
    \\    print(out, said(fs.read_text("g/later/s.txt")))
    \\    print(out, done(fs.write_text("g/later/s.txt", "x")))
    \\    print(out, said(fs.read_text("g/later/../a.txt")))
    \\    print(out, said(filesystem.realpath(fs, "g/later")))
    \\    return 0
;

test "a link inside the grant that points out of it, at the end, on the way or made after the start, is never followed" {
    var box = try Box.init();
    defer box.deinit();
    // A link on the way of a file call is met as the walk's `openat` meets it, a folder that is not a directory.
    const link = "is a symbolic link the sandbox does not follow, or links nest too deeply";
    const parent = "a parent of the path is not a directory";
    try box.expectPrinted("", &.{"--allow-write=@ROOT@/g"}, through_links, "read 'g/out/s.txt': " ++ parent ++ "\n" ++
        "write 'g/out/new.txt': " ++ parent ++ "\n" ++
        "listdir 'g/out': is not a directory\n" ++
        "directory listing 'g/out/': " ++ link ++ "\n" ++
        "stat 'g/out/s.txt': " ++ link ++ "\n" ++
        "read 'g/outfile': " ++ link ++ "\n" ++
        "write 'g/outfile': " ++ link ++ "\n" ++
        "open 'g/outfile': " ++ link ++ "\n" ++
        "read 'g/out/../a.txt': " ++ parent ++ "\n" ++
        "ok\n" ++
        "read 'g/later/s.txt': " ++ parent ++ "\n" ++
        "write 'g/later/s.txt': " ++ parent ++ "\n" ++
        "read 'g/later/../a.txt': " ++ parent ++ "\n" ++
        "realpath 'g/later': resolves outside the granted directory\n");
    try box.expectOutsideUntouched();
}

/// The grant given through the link `glink`, and the calls that read, list or climb out of it by either name.
const through_a_linked_grant = every_call ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("glink/a.txt")))
    \\    print(out, said(fs.read_text("g/a.txt")))
    \\    print(out, said(fs.read_text("glink/sub/../a.txt")))
    \\    print(out, said(fs.read_text("glink/../g/a.txt")))
    \\    print(out, said(fs.read_text("glink/../secret/s.txt")))
    \\    print(out, said(fs.read_text("g/../secret/s.txt")))
    \\    return 0
;

test "a grant given through a link answers by both names, and a .. out of the link's name is refused" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{"--allow-read=@ROOT@/glink"}, through_a_linked_grant,
        \\ok
        \\ok
        \\ok
        \\read 'glink/../g/a.txt': denied: '@ROOT@/glink/..' climbs out of a granted directory named through a symbolic link
        \\read 'glink/../secret/s.txt': denied: '@ROOT@/glink/..' climbs out of a granted directory named through a symbolic link
        \\read 'g/../secret/s.txt': denied: '@ROOT@/secret/s.txt' is outside the granted directories
        \\
    );
}

/// The grant itself, a trailing slash, the empty path, a NUL octet and a path longer than the system takes.
const odd_spellings = "import strings\n" ++ every_call ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, listed(fs.listdir("g")), described(fs.stat_path("g/")), entries(fs, "@ROOT@/g"))
    \\    print(out, done(fs.mkdir("g")))
    \\    print(out, done(fs.remove("g/")))
    \\    print(out, said(fs.read_text("g/")))
    \\    print(out, said(fs.read_text("g/a.txt/")))
    \\    print(out, done(fs.write_text("g/new/", "x")))
    \\    print(out, described(fs.stat_path("g/a.txt/")))
    \\    print(out, said(fs.read_text("")))
    \\    match fs.read_text("g/a\x00.txt"):
    \\        case Ok(_):
    \\            print(out, "ok")
    \\        case Err(message):
    \\            print(out, strings.ends_with(message, "': the path contains a NUL octet"))
    \\    mut long = "g/"
    \\    mut i = 0
    \\    while i < 5000:
    \\        long = long + "a"
    \\        i = i + 1
    \\    match fs.read_text(long):
    \\        case Ok(_):
    \\            print(out, "ok")
    \\        case Err(message):
    \\            print(out, strings.ends_with(message, "': the path, or a name in it, is too long"))
    \\    print(out, said(fs.read_text("g/sub/../../g/./a.txt")))
    \\    return 0
;

test "the grant itself, a trailing slash, an empty path, a NUL and a very long path each get the system's answer" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{"--allow-write=@ROOT@/g"}, odd_spellings,
        \\ok ok ok
        \\mkdir 'g': already exists
        \\remove 'g/': denied: a granted directory itself is not removed
        \\read 'g/': is a directory
        \\read 'g/a.txt/': a parent of the path is not a directory
        \\write 'g/new/': is a directory
        \\stat 'g/a.txt/': a parent of the path is not a directory
        \\read '': the path does not exist
        \\True
        \\True
        \\ok
        \\
    );
    try box.expectOutsideUntouched();
}

/// A write under a read grant, and the two narrowed handles, each refused with its own text.
const three_refusals = every_call ++
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("r/c.txt")))
    \\    print(out, done(fs.write_text("r/new.txt", "x")))
    \\    print(out, done(appended(fs, "r/c.txt")))
    \\    print(out, done(fs.symlink_path("x", "r/link")))
    \\    print(out, said(fs.read_text("secret/s.txt")))
    \\    const reader = fs.read_only()
    \\    print(out, done(reader.write_text("g/new.txt", "x")))
    \\    print(out, done(filesystem.chmod(reader, "g/a.txt", 0o600)))
    \\    with fs.dir("g") as inner:
    \\        print(out, said(inner.read_text("sub/b.txt")))
    \\        print(out, said(inner.read_text("../secret/s.txt")))
    \\        print(out, said(inner.read_text("@ROOT@/secret/s.txt")))
    \\        print(out, said(filesystem.realpath(inner, "sub/b.txt")))
    \\    return 0
;

test "outside every grant, a write under a read grant and a narrowed handle are three refusals with three texts" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=@ROOT@/g", "--allow-read=@ROOT@/r" }, three_refusals,
        \\ok
        \\write 'r/new.txt': denied: writing needs a write grant (--allow-write); '@ROOT@/r/new.txt' is granted for reading only
        \\open 'r/c.txt': denied: writing needs a write grant (--allow-write); '@ROOT@/r/c.txt' is granted for reading only
        \\symlink 'r/link': denied: writing needs a write grant (--allow-write); '@ROOT@/r/link' is granted for reading only
        \\read 'secret/s.txt': denied: '@ROOT@/secret/s.txt' is outside the granted directories
        \\write 'g/new.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write
        \\chmod 'g/a.txt': denied: this Filesystem was narrowed by fs.read_only() and does not write
        \\ok
        \\read '../secret/s.txt': denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'
        \\read '@ROOT@/secret/s.txt': denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'
        \\ok
        \\
    );
    try box.expectOutsideUntouched();
}

/// The spellings the three sample programs met (SP1-F-6, SP2-F-7, SP3-F-8), each of which must work and print the same in
/// a plain run and a restricted one started in the same folder.
const spellings_that_work = every_call ++
    \\func kind(fs: Filesystem, path: str) -> str:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return f"{info.size}"
    \\        case Err(_):
    \\            return "refused"
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, said(fs.read_text("g/a.txt")), said(fs.read_text("./g/a.txt")), said(fs.read_text("@ROOT@/g/a.txt")))
    \\    print(out, done(fs.write_text("g/made.txt", "M")), said(fs.read_text("g//made.txt")))
    \\    print(out, kind(fs, "g/sub/../a.txt"), kind(fs, "./g/a.txt"), kind(fs, "g//sub//b.txt"), described(fs.stat_path("g/sub/")))
    \\    print(out, entries(fs, "g/sub/"), entries(fs, "./g/sub"), listed(fs.listdir("g/sub/..")))
    \\    match filesystem.read_at(fs, "g/sub/../a.txt", 0, 1):
    \\        case Ok(data):
    \\            print(out, data)
    \\        case Err(message):
    \\            print(out, message)
    \\    print(out, done(filesystem.set_modified(fs, "./g/a.txt", 1000000000)), done(filesystem.chmod(fs, "g/sub/../a.txt", 0o644)))
    \\    print(out, done(filesystem.symlink(fs, "a.txt", "g/sub/../alias")), said(filesystem.read_link(fs, "./g/alias")))
    \\    print(out, done(fs.rename_path("g/made.txt", "g/sub/../renamed.txt")), fs.exists("g/renamed.txt"))
    \\    match filesystem.stat_follow(fs, "g/sub/"):
    \\        case Ok(_):
    \\            print(out, "ok")
    \\        case Err(_):
    \\            print(out, "refused")
    \\    return 0
;

const spellings_answers =
    \\ok ok ok
    \\ok ok
    \\1 1 1 ok
    \\ok ok ok
    \\b'A'
    \\ok ok
    \\ok ok
    \\ok True
    \\ok
    \\
;

test "the spellings the sample programs met work restricted, beside the grant, as they work in a plain run" {
    var plain = try Box.init();
    defer plain.deinit();
    try plain.expectPrinted("", &.{}, spellings_that_work, spellings_answers);
    var restricted = try Box.init();
    defer restricted.deinit();
    try restricted.expectPrinted("", &.{"--allow-write=g"}, spellings_that_work, spellings_answers);
    try restricted.expectOutsideUntouched();
}

/// The working directory inside the grant: `..` that climbs out of the working directory and back into the grant.
const from_inside =
    \\import filesystem
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, fs.read_text("a.txt"), fs.read_text("../g/a.txt"), fs.read_text("sub/../a.txt"), fs.read_text("./sub/b.txt"))
    \\    print(out, filesystem.cwd(fs), filesystem.realpath(fs, "../g/sub"))
    \\    return 0
;

test "from inside the grant a relative path, and a .. that climbs back into it, name the same files as in a plain run" {
    var box = try Box.init();
    defer box.deinit();
    const answers =
        \\Ok('A') Ok('A') Ok('A') Ok('B')
        \\Ok('@ROOT@/g') Ok('@ROOT@/g/sub')
        \\
    ;
    try box.expectPrinted("g", &.{}, from_inside, answers);
    try box.expectPrinted("g", &.{"--allow-read=."}, from_inside, answers);
    try box.expectPrinted("far/deep", &.{"--allow-read=../../g"}, "func main(fs: Filesystem, out: Stream) -> int:\n" ++
        "    print(out, fs.read_text(\"../../g/a.txt\"), fs.exists(\"../../g/sub/\"))\n    return 0\n", "Ok('A') True\n");
}

/// `stat_follow` and `fs.open` of the paths that name a descriptor of the process (W2B-F-5). The guest's standard output is
/// the harness's pipe, so `/dev/stdout`, `/dev/fd/1` and `/proc/self/fd/1` lead through a link the kernel names `pipe:[N]`,
/// with no path; `/dev/null` is a character device. The narrowed handle is `/dev` itself.
const descriptor_paths =
    \\import filesystem
    \\func kind(fs: Filesystem, path: str) -> str:
    \\    match filesystem.stat_follow(fs, path):
    \\        case Ok(info):
    \\            return f"{info.kind}"
    \\        case Err(failure):
    \\            return f"{failure}"
    \\func opened(fs: Filesystem, path: str) -> str:
    \\    match fs.open(path, "rb"):
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    for path in ["/dev/stdout", "/dev/fd/1", "/proc/self/fd/1", "/dev/null"]:
    \\        print(out, kind(fs, path), "|", opened(fs, path))
    \\    match filesystem.dir_at(fs, "/dev"):
    \\        case Ok(dev):
    \\            for path in ["stdout", "fd/1", "null"]:
    \\                print(out, kind(dev, path), "|", opened(dev, path))
    \\        case Err(message):
    \\            print(out, message)
    \\    return 0
;

test "stat_follow of a path that names a pipe answers Other in a plain run, and is refused wherever fs.open of it is" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{}, descriptor_paths,
        \\PathKind.Other | ok
        \\PathKind.Other | ok
        \\PathKind.Other | ok
        \\PathKind.Other | ok
        \\StatError.Failed(message="stat 'stdout': resolves outside the granted directory") | open 'stdout': is a symbolic link the sandbox does not follow, or links nest too deeply
        \\StatError.Failed(message="stat 'fd/1': resolves outside the granted directory") | open 'fd/1': a parent of the path is not a directory
        \\PathKind.Other | ok
        \\
    );
    try box.expectPrinted("", &.{"--allow-write=g"}, descriptor_paths,
        \\StatError.Failed(message="stat '/dev/stdout': denied: '/dev/stdout' is outside the granted directories") | open '/dev/stdout': denied: '/dev/stdout' is outside the granted directories
        \\StatError.Failed(message="stat '/dev/fd/1': denied: '/dev/fd/1' is outside the granted directories") | open '/dev/fd/1': denied: '/dev/fd/1' is outside the granted directories
        \\StatError.Failed(message="stat '/proc/self/fd/1': denied: '/proc/self/fd/1' is outside the granted directories") | open '/proc/self/fd/1': denied: '/proc/self/fd/1' is outside the granted directories
        \\StatError.Failed(message="stat '/dev/null': denied: '/dev/null' is outside the granted directories") | open '/dev/null': denied: '/dev/null' is outside the granted directories
        \\dir_at '/dev': denied: '/dev' is outside the granted directories
        \\
    );
    try box.expectPrinted("", &.{ "--allow-read=/dev", "--allow-read=/proc" }, descriptor_paths,
        \\StatError.Failed(message="stat '/dev/stdout': resolves outside the granted directory") | open '/dev/stdout': is a symbolic link the sandbox does not follow, or links nest too deeply
        \\StatError.Failed(message="stat '/dev/fd/1': resolves outside the granted directory") | open '/dev/fd/1': a parent of the path is not a directory
        \\StatError.Failed(message="stat '/proc/self/fd/1': is a symbolic link the sandbox does not follow, or links nest too deeply") | open '/proc/self/fd/1': a parent of the path is not a directory
        \\PathKind.Other | open '/dev/null': is not a regular file
        \\StatError.Failed(message="stat 'stdout': resolves outside the granted directory") | open 'stdout': is a symbolic link the sandbox does not follow, or links nest too deeply
        \\StatError.Failed(message="stat 'fd/1': resolves outside the granted directory") | open 'fd/1': a parent of the path is not a directory
        \\PathKind.Other | open 'null': is not a regular file
        \\
    );
}

/// A backslash is a byte of a name on Linux (SP1B-F-6): a narrowed handle (`fs.dir` of a literal, `dir_at`, `read_only()` of
/// one, and the same on `memory()`) names `a\b` in its folder as the plain `fs` does, and `a\..\b` and `..\x` are names in
/// the folder too, not a climb out of it.
const backslash_names =
    \\import filesystem
    \\func done(result: Result[Unit, str]) -> str:
    \\    match result:
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return copy(message)
    \\func said(result: Result[str, str]) -> str:
    \\    match result:
    \\        case Ok(text):
    \\            return copy(text)
    \\        case Err(message):
    \\            return copy(message)
    \\func line(d: Filesystem) -> str:
    \\    const wrote = done(d.write_text("a\\b", "x"))
    \\    const climbed = done(d.write_text("a\\..\\b", "y"))
    \\    const above = done(d.write_text("..\\x", "z"))
    \\    const folder = done(d.mkdir("w\\v"))
    \\    const first = said(d.read_text("a\\b"))
    \\    const second = said(d.read_text("a\\..\\b"))
    \\    const third = said(d.read_text("..\\x"))
    \\    const made = d.exists("w\\v")
    \\    const plain = d.exists("b")
    \\    return f"{wrote} {first} {climbed} {second} {above} {third} {folder} {made} {plain}"
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, line(fs.dir("g")))
    \\    match filesystem.dir_at(fs, "g/sub"):
    \\        case Ok(sub):
    \\            print(out, line(sub))
    \\        case Err(message):
    \\            print(out, message)
    \\    const held = fs.dir("g").read_only()
    \\    print(out, said(held.read_text("a\\b")), done(held.write_text("c\\d", "x")), held.exists("c\\d"))
    \\    print(out, said(fs.dir("g/w\\v").read_text("../a\\b")), done(fs.dir("g/w\\v").write_text("in", "i")), fs.exists("g/w\\v/in"))
    \\    const memory = filesystem.memory()
    \\    _ = memory.mkdir("m")
    \\    print(out, line(memory.dir("m")), memory.exists("a\\b"), memory.exists("x"))
    \\    print(out, fs.exists("a\\b"), fs.exists("x"), fs.exists("g/b"), fs.exists("b"))
    \\    return 0
;

test "a narrowed handle names a file that holds a backslash, and a backslash never climbs out of its folder" {
    const answers =
        \\ok x ok y ok z ok True False
        \\ok x ok y ok z ok True False
        \\x write 'c\d': denied: this Filesystem was narrowed by fs.read_only() and does not write False
        \\read '../a\b': denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/' ok True
        \\ok x ok y ok z ok True False False False
        \\False False False False
        \\
    ;
    for ([_][]const []const u8{ &.{}, &.{"--allow-write=g"} }) |grants| {
        var box = try Box.init();
        defer box.deinit();
        try box.expectPrinted("", grants, backslash_names, answers);
        try box.expectOutsideUntouched();
        for ([_][]const u8{ "g/a\\b", "g/a\\..\\b", "g/..\\x", "g/sub/a\\b", "g/sub/..\\x", "g/w\\v/in" }) |name| try box.temporary.dir.access(t.io, name, .{});
        try t.expectError(error.FileNotFound, box.temporary.dir.access(t.io, "g/b", .{}));
        try t.expectError(error.FileNotFound, box.temporary.dir.access(t.io, "x", .{}));
    }
}

/// `filesystem.create_mode` (SP1B-F-8): a new file has its mode while it is still open and being filled, a file that exists
/// is truncated with its own mode kept, as `fs.open(path, "wb")` leaves it, and the path rule is that of every write.
const create_with_mode =
    \\import filesystem
    \\func mode_of(fs: Filesystem, path: str) -> int:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(info):
    \\            return info.mode
    \\        case Err(_):
    \\            return -1
    \\func made(fs: Filesystem, path: str, mode: int) -> str:
    \\    match filesystem.create_mode(fs, path, mode):
    \\        case Ok(f):
    \\            const during = mode_of(fs, path)
    \\            _ = f.write(b"new")
    \\            _ = f.close()
    \\            return f"{during:o}"
    \\        case Err(message):
    \\            return message
    \\func wb(fs: Filesystem, path: str) -> str:
    \\    match fs.open(path, "wb"):
    \\        case Ok(_):
    \\            return "ok"
    \\        case Err(message):
    \\            return message
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, made(fs, "g/new.bin", 0o600), made(fs, "g/sub/group.bin", 0o640), fs.read_text("g/new.bin"))
    \\    const before = mode_of(fs, "g/a.txt")
    \\    const during = made(fs, "g/a.txt", 0o600)
    \\    print(out, during == f"{before:o}", mode_of(fs, "g/a.txt") == before, fs.read_text("g/a.txt"))
    \\    print(out, made(fs, "secret/new.bin", 0o600))
    \\    print(out, made(fs, "g/../secret/new.bin", 0o600))
    \\    print(out, made(fs, "g/out/new.bin", 0o600))
    \\    print(out, made(fs, "g/outfile", 0o600))
    \\    print(out, made(fs, "r/new.bin", 0o600))
    \\    for path in ["secret/new.bin", "g/../secret/new.bin", "g/out/new.bin", "g/outfile", "r/new.bin", "g/sub", "g/missing/x"]:
    \\        print(out, made(fs, path, 0o600) == wb(fs, path))
    \\    const d = fs.dir("g")
    \\    print(out, made(d, "sub/narrowed.bin", 0o600), made(d, "../secret/new.bin", 0o600))
    \\    print(out, made(d, "out/new.bin", 0o600), made(d, "outfile", 0o600))
    \\    print(out, made(fs.dir("g").read_only(), "held.bin", 0o600))
    \\    print(out, made(fs, "g/sub", 0o600), made(fs, "g/missing/x", 0o600), made(fs, "g/bad", 0o10000))
    \\    const memory = filesystem.memory()
    \\    _ = memory.write_text("kept.txt", "old")
    \\    print(out, made(memory, "m.bin", 0o600), made(memory, "kept.txt", 0o600), mode_of(memory, "kept.txt"), memory.read_text("kept.txt"))
    \\    print(out, made(memory, "../up.bin", 0o600), made(memory.read_only(), "ro.bin", 0o600))
    \\    return 0
;

test "create_mode makes a file with its mode while it is open, truncates one that exists, and writes only where a write may" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{ "--allow-write=g", "--allow-read=r" }, create_with_mode,
        \\600 640 Ok('new')
        \\True True Ok('new')
        \\open 'secret/new.bin': denied: '@ROOT@/secret/new.bin' is outside the granted directories
        \\open 'g/../secret/new.bin': denied: '@ROOT@/secret/new.bin' is outside the granted directories
        \\open 'g/out/new.bin': a parent of the path is not a directory
        \\open 'g/outfile': is a symbolic link the sandbox does not follow, or links nest too deeply
        \\open 'r/new.bin': denied: writing needs a write grant (--allow-write); '@ROOT@/r/new.bin' is granted for reading only
        \\True
        \\True
        \\True
        \\True
        \\True
        \\True
        \\True
        \\600 open '../secret/new.bin': denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'
        \\open 'out/new.bin': a parent of the path is not a directory open 'outfile': is a symbolic link the sandbox does not follow, or links nest too deeply
        \\open 'held.bin': denied: this Filesystem was narrowed by fs.read_only() and does not write
        \\open 'g/sub': is a directory open 'g/missing/x': a folder on the way does not exist open 'g/bad': the mode must be between 0 and 0o7777
        \\600 644 420 Ok('new')
        \\open '../up.bin': denied: '../up.bin' is outside the granted directories open 'ro.bin': denied: this Filesystem was narrowed by fs.read_only() and does not write
        \\
    );
    try box.expectOutsideUntouched();
}

/// Without a restriction `create_mode` opens what `fs.open(path, "wb")` opens: a final link to an existing file is followed
/// and the file truncated, and a device is written.
const create_plain =
    \\import filesystem
    \\func made(fs: Filesystem, path: str) -> str:
    \\    match filesystem.create_mode(fs, path, 0o600):
    \\        case Ok(f):
    \\            _ = f.write(b"new")
    \\            _ = f.close()
    \\            return "ok"
    \\        case Err(message):
    \\            return message
    \\func main(fs: Filesystem, out: Stream) -> int:
    \\    print(out, made(fs, "g/outfile"), fs.read_text("secret/s.txt"), made(fs, "/dev/null"), made(fs, "g/out/made.bin"))
    \\    print(out, fs.read_text("secret/made.bin"))
    \\    return 0
;

test "without a restriction create_mode follows a final link and writes a device, as fs.open with wb does" {
    var box = try Box.init();
    defer box.deinit();
    try box.expectPrinted("", &.{}, create_plain, "ok Ok('new') ok ok\nOk('new')\n");
}

//! `filesystem.read_link` through real directories: the text of a symbolic link as stored, on an unrestricted root, a
//! `--restrict` grant (read-write and read-only) and a directory narrowed with `fs.dir`, and the rule that it refuses what
//! `filesystem.stat` refuses for the same path, because both resolve a path the same way. The in-memory filesystem is pinned
//! in `tests/lang/filesystem_symlinks.selka`; `Stat.owner`, `Stat.group` and `Stat.links` of a real entry are pinned here too.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const files = @import("io_files_test.zig");

/// A tree with a link of every kind: `real/file.txt` (5 octets) and `real/sub`, the relative link `rel` to the file, the
/// absolute one `abs`, the dangling `dangling`, the link to a link `chain`, `esc` whose target is outside the sandbox's
/// grant, `dirln` to the directory `real`, `real/inner` beside the file, `bad` whose target is not UTF-8 text and `long`
/// whose target is 4000 octets.
fn seedTree(sandbox: *files.Sandbox) !void {
    const dir = sandbox.temporary.dir;
    try dir.createDirPath(t.io, "real/sub");
    try dir.writeFile(t.io, .{ .sub_path = "real/file.txt", .data = "hello" });
    try dir.symLink(t.io, "real/file.txt", "rel", .{});
    const absolute = try std.fs.path.join(t.allocator, &.{ sandbox.path, "real/file.txt" });
    defer t.allocator.free(absolute);
    try dir.symLink(t.io, absolute, "abs", .{});
    try dir.symLink(t.io, "nowhere/at/all", "dangling", .{});
    try dir.symLink(t.io, "rel", "chain", .{});
    try dir.symLink(t.io, "../outside/secret", "esc", .{});
    try dir.symLink(t.io, "real", "dirln", .{ .is_directory = true });
    try dir.symLink(t.io, "file.txt", "real/inner", .{});
    try dir.symLink(t.io, "\xff\xfe-not-text", "bad", .{});
    const long = try t.allocator.alloc(u8, 4000);
    defer t.allocator.free(long);
    @memset(long, 'a');
    try dir.symLink(t.io, long, "long", .{});
}

/// The guest functions every program below shares: the answer of `read_link` as one line, the same for `stat`, and whether
/// `read_link` of a path says what `stat` says of it (the failure text with the other call's verb), where `stat` refuses it.
const helpers =
    \\import filesystem
    \\import strings
    \\const NOT_A_LINK: str = "is not a symbolic link"
    \\const NOT_TEXT: str = "the bytes read are not valid UTF-8 text"
    \\const MISSING: str = "the path does not exist"
    \\const LINK: str = "is a symbolic link the sandbox does not follow, or links nest too deeply"
    \\const NARROWED: str = "denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'"
    \\func text_of(fs: Filesystem, path: str) -> str:
    \\    match filesystem.read_link(fs, path):
    \\        case Ok(text):
    \\            return "ok " + text
    \\        case Err(message):
    \\            return copy(message)
    \\func statted(fs: Filesystem, path: str) -> str:
    \\    match filesystem.stat(fs, path):
    \\        case Ok(_):
    \\            return "found"
    \\        case Err(error):
    \\            match error:
    \\                case Missing:
    \\                    return f"stat '{path}': {MISSING}"
    \\                case Failed(message=text):
    \\                    return copy(text)
    \\func agrees(fs: Filesystem, path: str) -> bool:
    \\    const seen = statted(fs, path)
    \\    const read = text_of(fs, path)
    \\    if seen == "found":
    \\        return read == f"read link '{path}': {NOT_A_LINK}" or read == f"read link '{path}': {NOT_TEXT}" or strings.starts_with_at(read, "ok ", 0)
    \\    return read == "read link" + seen[4:]
    \\func every_path_agrees(fs: Filesystem) -> int:
    \\    const paths = ["rel", "abs", "dangling", "chain", "esc", "dirln", "real", "real/file.txt", "real/inner", "real/sub", "bad", "long", "", "nope", "real/nope", "nope/x", "rel/x", "esc/secret", "abs/x", "dirln/inner", "dirln/file.txt", "dirln/nope", "dirln/sub", "real/file.txt/x", "real/../rel", "./rel", "../rel", "real/", "@ROOT@/rel", "@ROOT@/real", "@ROOT@/nope", "/rel"]
    \\    mut at = 0
    \\    for path in paths:
    \\        at += 1
    \\        if not agrees(fs, path):
    \\            return at
    \\    return 0
    \\func texts(fs: Filesystem) -> int:
    \\    if text_of(fs, "rel") != "ok real/file.txt":
    \\        return 1
    \\    if text_of(fs, "abs") != "ok @ROOT@/real/file.txt":
    \\        return 2
    \\    if text_of(fs, "dangling") != "ok nowhere/at/all":
    \\        return 3
    \\    if text_of(fs, "chain") != "ok rel":
    \\        return 4
    \\    if text_of(fs, "esc") != "ok ../outside/secret":
    \\        return 5
    \\    if text_of(fs, "dirln") != "ok real":
    \\        return 6
    \\    if text_of(fs, "real/inner") != "ok file.txt":
    \\        return 7
    \\    if text_of(fs, "bad") != f"read link 'bad': {NOT_TEXT}":
    \\        return 8
    \\    if text_of(fs, "long") != "ok " + strings.repeat("a", 4000):
    \\        return 9
    \\    if text_of(fs, "real/file.txt") != f"read link 'real/file.txt': {NOT_A_LINK}":
    \\        return 10
    \\    if text_of(fs, "real") != f"read link 'real': {NOT_A_LINK}" or text_of(fs, "") != f"read link '': {NOT_A_LINK}":
    \\        return 11
    \\    if text_of(fs, "nope") != f"read link 'nope': {MISSING}" or text_of(fs, "real/nope") != f"read link 'real/nope': {MISSING}":
    \\        return 12
    \\    if text_of(fs, "real/../rel") != "ok real/file.txt" or text_of(fs, "./rel") != "ok real/file.txt" or text_of(fs, ".//rel") != "ok real/file.txt":
    \\        return 13
    \\    return 0
;

/// Run `body` after the shared helpers in `sandbox`'s grant (`--restrict`), `@ROOT@` replaced by the sandbox's real path and
/// `@UP@` by the folder that holds it.
fn expectGranted(sandbox: *files.Sandbox, body: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ helpers, "\n", body });
    defer t.allocator.free(text);
    const rooted = try std.mem.replaceOwned(u8, t.allocator, text, "@ROOT@", sandbox.path);
    defer t.allocator.free(rooted);
    const source = try std.mem.replaceOwned(u8, t.allocator, rooted, "@UP@", std.fs.path.dirname(sandbox.path).?);
    defer t.allocator.free(source);
    try fixture.expect(t.allocator, source, sandbox.options(), 42);
}

/// The same with no restriction, the sandbox as the working directory.
fn expectUnrestricted(sandbox: *files.Sandbox, body: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ helpers, "\n", body });
    defer t.allocator.free(text);
    const source = try std.mem.replaceOwned(u8, t.allocator, text, "@ROOT@", sandbox.path);
    defer t.allocator.free(source);
    try fixture.expect(t.allocator, source, .{ .directory = sandbox.path }, 42);
}

test "read_link with no restriction answers the stored text, follows links on the way as stat does and refuses what stat refuses" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try expectUnrestricted(&sandbox,
        \\func main(fs: Filesystem) -> int:
        \\    const first = texts(fs)
        \\    if first != 0:
        \\        return first
        \\    if text_of(fs, "dirln/inner") != "ok file.txt" or text_of(fs, "dirln") != "ok real":
        \\        return 20
        \\    if text_of(fs, "@ROOT@/rel") != "ok real/file.txt" or text_of(fs, "@ROOT@/dirln/inner") != "ok file.txt":
        \\        return 21
        \\    if text_of(fs, "rel/x") != "read link 'rel/x': a parent of the path is not a directory" and text_of(fs, "rel/x") != "read link 'rel/x': the path does not exist":
        \\        return 22
        \\    if text_of(fs.read_only(), "esc") != "ok ../outside/secret":
        \\        return 23
        \\    const parity = every_path_agrees(fs)
        \\    if parity != 0:
        \\        return 100 + parity
        \\    return 42
    );
}

test "read_link under a read-write grant answers the stored text of every link, outside targets included, and refuses a link on the way" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try expectGranted(&sandbox,
        \\func main(fs: Filesystem) -> int:
        \\    const first = texts(fs)
        \\    if first != 0:
        \\        return first
        \\    if text_of(fs, "dirln/inner") != f"read link 'dirln/inner': {LINK}" or text_of(fs, "dirln/nope") != f"read link 'dirln/nope': {LINK}":
        \\        return 20
        \\    if text_of(fs, "@ROOT@/rel") != "ok real/file.txt":
        \\        return 21
        \\    if text_of(fs, "../rel") != "read link '../rel': denied: '@UP@/rel' is outside the granted directories":
        \\        return 22
        \\    if text_of(fs, "rel/x") != f"read link 'rel/x': {LINK}":
        \\        return 23
        \\    const parity = every_path_agrees(fs)
        \\    if parity != 0:
        \\        return 100 + parity
        \\    return 42
    );
}

test "read_link under a read-only grant reads the same links and refuses the same paths" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(false);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try expectGranted(&sandbox,
        \\func main(fs: Filesystem) -> int:
        \\    const first = texts(fs)
        \\    if first != 0:
        \\        return first
        \\    if text_of(fs, "dirln/inner") != f"read link 'dirln/inner': {LINK}":
        \\        return 20
        \\    const parity = every_path_agrees(fs)
        \\    if parity != 0:
        \\        return 100 + parity
        \\    return 42
    );
}

/// Run the narrowed handle's checks: `fs.dir("real")` and a handle narrowed to a directory that is itself a link.
const narrowed =
    \\func narrowed(fs: Filesystem) -> int:
    \\    const real = fs.dir("real")
    \\    if text_of(real, "inner") != "ok file.txt":
    \\        return 1
    \\    if text_of(real, "file.txt") != f"read link 'file.txt': {NOT_A_LINK}" or text_of(real, "") != f"read link '': {NOT_A_LINK}":
    \\        return 2
    \\    if text_of(real, "sub") != f"read link 'sub': {NOT_A_LINK}" or text_of(real, "nope") != f"read link 'nope': {MISSING}":
    \\        return 3
    \\    if text_of(real, "../rel") != f"read link '../rel': {NARROWED}" or text_of(real, "/rel") != f"read link '/rel': {NARROWED}":
    \\        return 4
    \\    if text_of(real.read_only(), "inner") != "ok file.txt":
    \\        return 5
    \\    const through = fs.dir("dirln")
    \\    if text_of(through, "inner") != f"read link 'inner': {LINK}" or text_of(through, "") != "ok real":
    \\        return 6
    \\    if text_of(fs.dir("real/sub"), "x") != f"read link 'x': {MISSING}":
    \\        return 7
    \\    if every_path_agrees(real) != 0 or every_path_agrees(through) != 0:
    \\        return 8
    \\    return 0
;

test "read_link through a narrowed directory reads a link whose target is outside it and refuses a link as the narrowing" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try expectGranted(&sandbox, narrowed ++ "\n" ++
        \\func main(fs: Filesystem) -> int:
        \\    const first = narrowed(fs)
        \\    if first != 0:
        \\        return first
        \\    if text_of(fs.dir("real"), "inner") != "ok file.txt":
        \\        return 30
        \\    return 42
    );
}

test "read_link through a narrowed directory refuses the same way in a run with no restriction" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try expectUnrestricted(&sandbox, narrowed ++ "\n" ++
        \\func main(fs: Filesystem) -> int:
        \\    const first = narrowed(fs)
        \\    if first != 0:
        \\        return first
        \\    return 42
    );
}

/// What the kernel says of the entry `path` (not followed) of the sandbox, written as the guest writes `Stat`'s three fields:
/// `owner group links`.
fn kernelOwnership(sandbox: *files.Sandbox, path: [:0]const u8) ![]u8 {
    var buffer: std.os.linux.Statx = undefined;
    const status = std.os.linux.statx(sandbox.temporary.dir.handle, path, std.os.linux.AT.SYMLINK_NOFOLLOW, .{ .NLINK = true, .UID = true, .GID = true }, &buffer);
    try t.expectEqual(@as(usize, 0), status);
    return std.fmt.allocPrint(t.allocator, "{d} {d} {d}", .{ buffer.uid, buffer.gid, buffer.nlink });
}

test "Stat.owner, Stat.group and Stat.links are the user, the group and the link count the kernel keeps for a real entry" {
    var sandbox: files.Sandbox = undefined;
    try sandbox.init(true);
    defer sandbox.deinit();
    try seedTree(&sandbox);
    try sandbox.temporary.dir.hardLink("real/file.txt", sandbox.temporary.dir, "real/second.txt", t.io, .{});
    const file = try kernelOwnership(&sandbox, "real/file.txt");
    defer t.allocator.free(file);
    const directory = try kernelOwnership(&sandbox, "real");
    defer t.allocator.free(directory);
    const link = try kernelOwnership(&sandbox, "rel");
    defer t.allocator.free(link);
    try t.expect(std.mem.endsWith(u8, file, " 2"));
    const mine = try std.fmt.allocPrint(t.allocator, "{d} ", .{std.os.linux.getuid()});
    defer t.allocator.free(mine);
    try t.expect(std.mem.startsWith(u8, file, mine));
    const body = try std.fmt.allocPrint(t.allocator,
        \\import filesystem
        \\func owned(fs: Filesystem, path: str) -> str:
        \\    match filesystem.stat(fs, path):
        \\        case Ok(info):
        \\            return f"{{info.owner}} {{info.group}} {{info.links}}"
        \\        case Err(_):
        \\            return "error"
        \\func followed(fs: Filesystem, path: str) -> str:
        \\    match filesystem.stat_follow(fs, path):
        \\        case Ok(info):
        \\            return f"{{info.owner}} {{info.group}} {{info.links}}"
        \\        case Err(_):
        \\            return "error"
        \\func main(fs: Filesystem) -> int:
        \\    if owned(fs, "real/file.txt") != "{[file]s}" or owned(fs, "real/second.txt") != "{[file]s}":
        \\        return 1
        \\    if owned(fs, "real") != "{[directory]s}":
        \\        return 2
        \\    if owned(fs, "rel") != "{[link]s}":
        \\        return 3
        \\    if followed(fs, "rel") != "{[file]s}" or followed(fs, "dirln") != "{[directory]s}":
        \\        return 4
        \\    return 42
    , .{ .file = file, .directory = directory, .link = link });
    defer t.allocator.free(body);
    try fixture.expect(t.allocator, body, sandbox.options(), 42);
    try fixture.expect(t.allocator, body, .{ .directory = sandbox.path }, 42);
}

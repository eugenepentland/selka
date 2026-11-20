//! `selka --version`: the one line that says which compiler this is, and the small file the install step writes to
//! say which commit it was built from (D-FR22-4).
//!
//! The compiler's identity (`build_identity.zig`) keys every cached result and digests the sources under `src` and the
//! products `build.zig` embeds. A commit hash inside that digest would change it at every commit, including one that
//! changes only a guide, and empty every cache. So the commit is not inside the binary: the install step writes it to
//! `selka.commit` beside the executable (`file_name`), outside everything the identity digests, and this line reads it
//! when it is asked. The line always carries the identity, which does not move for a commit that leaves the sources
//! alone, and the commit when the file is there; a binary copied without its file says `commit unknown`.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;

/// The file beside the executable that holds the commit the install step was run at.
pub const file_name = product.commit_file;

/// Hexadecimal digits of the commit and of the identity a line shows.
pub const shown_digits = 12;

/// What the commit file says about the tree the build was made from.
pub const Commit = union(enum) {
    /// No file, an unreadable one, or one that does not name a commit.
    unknown,
    /// The commit `hash` (hexadecimal, as written) the tree was at, and whether it had changes `git` could see: a
    /// modified or staged tracked file, or an untracked file under `src`.
    built: struct { hash: []const u8, dirty: bool },
};

/// The compiler's own facts a line shows.
pub const Info = struct {
    /// The compiler identity in hexadecimal (64 digits).
    identity: []const u8,
    zig_version: []const u8,
    mode: []const u8,
    architecture: []const u8,
    os: []const u8,
    commit: Commit,
};

/// The text the install step writes: `commit HASH` and `tree clean` or `tree dirty`, one to a line.
pub fn commitFile(allocator: std.mem.Allocator, hash: []const u8, dirty: bool) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "commit {s}\ntree {s}\n", .{ hash, if (dirty) "dirty" else "clean" });
}

/// Read a commit file. Anything but a `commit` line naming 7 to 64 hexadecimal digits is `unknown`; a missing or
/// unrecognized `tree` line counts as dirty, since nothing then says the tree was clean.
pub fn parseCommitFile(bytes: []const u8) Commit {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const first = std.mem.trim(u8, lines.next() orelse return .unknown, " \t\r");
    const prefix = "commit ";
    if (!std.mem.startsWith(u8, first, prefix)) return .unknown;
    const hash = std.mem.trim(u8, first[prefix.len..], " \t");
    if (hash.len < 7 or hash.len > 64) return .unknown;
    for (hash) |byte| if (!std.ascii.isHex(byte)) return .unknown;
    const second = std.mem.trim(u8, lines.next() orelse "", " \t\r");
    return .{ .built = .{ .hash = hash, .dirty = !std.mem.eql(u8, second, "tree clean") } };
}

/// The version line, without its newline: `selka commit 11419ef271ab, identity 9f2c4e1a7b30, Debug, zig 0.17.0-dev.1683+5ceec001b,
/// x86_64-linux`; `commit 11419ef271ab+dirty` when the tree had uncommitted changes and `commit unknown` without the file.
pub fn render(allocator: std.mem.Allocator, info: Info) std.mem.Allocator.Error![]u8 {
    const identity = info.identity[0..@min(info.identity.len, shown_digits)];
    return switch (info.commit) {
        .unknown => std.fmt.allocPrint(allocator, "selka commit unknown, identity {s}, {s}, zig {s}, {s}-{s}", .{ identity, info.mode, info.zig_version, info.architecture, info.os }),
        .built => |built| std.fmt.allocPrint(allocator, "selka commit {s}{s}, identity {s}, {s}, zig {s}, {s}-{s}", .{
            built.hash[0..@min(built.hash.len, shown_digits)], if (built.dirty) "+dirty" else "", identity, info.mode, info.zig_version, info.architecture, info.os,
        }),
    };
}

/// The commit file beside `executable_directory`, read for `render`; `unknown` when there is none.
pub fn readCommit(allocator: std.mem.Allocator, io: std.Io, executable_directory: []const u8) Commit {
    const path = std.fs.path.join(allocator, &.{ executable_directory, file_name }) catch return .unknown;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4096)) catch return .unknown;
    return parseCommitFile(bytes);
}

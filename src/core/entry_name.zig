//! The name a cache key gives the entry file: its realpath relative to the project root, or its absolute realpath when it
//! lies outside that root. The root is the directory of the loaded `selka.json`, else the working directory. A name is never
//! a stand-in for content: every key that holds one also holds the digest of the bytes it names (`lowering_demand.zig`
//! binds the checked bytes; `lowering_cache.sourceProof` hashes the proven span), so two checkouts with different files at one
//! relative path key differently, and identical files key alike.
const std = @import("std");

/// The key name of `path` under the project root `root` (empty `root` names the working directory). A path that cannot be
/// resolved keeps its spelling: such a file cannot be read, so its name matches only itself.
pub fn of(a: std.mem.Allocator, io: std.Io, root: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    const directory = std.Io.Dir.cwd();
    const real = directory.realPathFileAlloc(io, path, a) catch return a.dupe(u8, path);
    const base = directory.realPathFileAlloc(io, if (root.len == 0) "." else root, a) catch return real;
    return relativeTo(real, base);
}

/// `real` relative to the directory `base` when it lies beneath it, and `real` itself otherwise.
fn relativeTo(real: []const u8, base: []const u8) []const u8 {
    const prefix = if (base.len > 1 and base[base.len - 1] == '/') base[0 .. base.len - 1] else base;
    if (std.mem.eql(u8, prefix, "/")) return if (real.len > 1) real[1..] else real;
    if (real.len <= prefix.len + 1 or !std.mem.startsWith(u8, real, prefix) or real[prefix.len] != '/') return real;
    return real[prefix.len + 1 ..];
}

test "an entry under its root is named by its root-relative realpath, whatever its spelling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.createDirPath(std.testing.io, "app");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.selka", .data = "func main() -> int:\n    return 0\n" });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const direct = try std.fs.path.join(a, &.{ root, "app", "main.selka" });
    const detour = try std.fs.path.join(a, &.{ root, "app", "..", "app", "main.selka" });
    try std.testing.expectEqualStrings("app/main.selka", try of(a, std.testing.io, root, direct));
    try std.testing.expectEqualStrings("app/main.selka", try of(a, std.testing.io, root, detour));
}

test "an entry outside its root keeps its absolute realpath, so it names nothing under another root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.createDirPath(std.testing.io, "inside");
    try directory.dir.createDirPath(std.testing.io, "outside");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "outside/main.selka", .data = "x" });
    const top = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const root = try std.fs.path.join(a, &.{ top, "inside" });
    const file = try std.fs.path.join(a, &.{ top, "outside", "main.selka" });
    const real = try directory.dir.realPathFileAlloc(std.testing.io, "outside/main.selka", a);
    try std.testing.expectEqualStrings(real, try of(a, std.testing.io, root, file));
}

test "a path that does not resolve keeps its spelling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("no/such/main.selka", try of(a, std.testing.io, "/no/such/root", "no/such/main.selka"));
}

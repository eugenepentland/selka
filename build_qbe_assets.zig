//! Bundle only the native runtime build inputs, plus build-time identities, into the compiler.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;
/// Zig runtime translation units `mylang build` compiles directly; their transitive
/// `@import`/`@embedFile` closure is bundled with them.
const zig_roots = [_][]const u8{"native_format.zig"};
/// Source bytes read once at compiler build time, keyed by path relative to `src`.
const Sources = std.StringArrayHashMapUnmanaged([]const u8);
/// Every source input, the selected runtime subset, and the Zig units still to scan.
const Selection = struct { sources: Sources, chosen: std.StringArrayHashMapUnmanaged(void) = .empty, pending: std.ArrayList([]const u8) = .empty };
/// Build the embedded runtime asset module: the selected inputs, their content hash,
/// and the compiler identity derived from every source input and the toolchain.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    b.dependOnDirectory(b.path("src"));
    const sources = read(b);
    var selection: Selection = .{ .sources = sources };
    select(b, &selection);
    const paths = selection.chosen.keys();
    std.mem.sort([]const u8, paths, {}, order);
    const files = b.addWriteFiles();
    var text: std.Io.Writer.Allocating = .init(b.allocator);
    text.writer.writeAll("pub const Asset = struct { path: []const u8, bytes: []const u8 };\npub const files = [_]Asset{\n") catch @panic("OOM");
    for (paths) |path| {
        _ = files.addCopyFile(b.path(b.pathJoin(&.{ "src", path })), b.pathJoin(&.{ "src", path }));
        text.writer.print(".{{ .path=\"{s}\", .bytes=@embedFile(\"src/{s}\") }},\n", .{ path, path }) catch @panic("OOM");
    }
    text.writer.print("}};\npub const zig_version = \"{s}\";\n", .{@import("builtin").zig_version_string}) catch @panic("OOM");
    text.writer.print("pub const content_hash = \"{s}\";\n", .{digest(b, manifest(b, sources, paths))}) catch @panic("OOM");
    text.writer.print("pub const compiler_identity = \"{s}\";\n", .{identity(b, sources, optimize)}) catch @panic("OOM");
    return b.createModule(.{ .root_source_file = files.add("assets.zig", text.written()), .target = target, .optimize = optimize });
}
/// Read every compiler source input once; the same bytes feed identity and selection.
fn read(b: *std.Build) Sources {
    var directory = b.root.openDir(b.graph.io, "src", .{ .iterate = true }) catch @panic("open native assets");
    defer directory.close(b.graph.io);
    var walker = directory.walk(b.allocator) catch @panic("walk native assets");
    defer walker.deinit();
    var sources: Sources = .empty;
    while (walker.next(b.graph.io) catch @panic("read native assets")) |entry| {
        const relative = b.pathJoin(&.{ "src", entry.path });
        if (entry.kind == .directory) b.dependOnDirectory(b.path(relative));
        if (entry.kind != .file) continue;
        // A directory dependency only repeats the configure phase when a name is
        // added, removed or renamed; an in-place content edit would otherwise
        // leave `content_hash`/`compiler_identity` at their cached values while
        // the `@embedFile` copies tracked by the write-file step move to the new
        // bytes. Bind every input's contents so the identity the artifact embeds
        // and the bytes it bundles can never disagree.
        b.dependOnFileContents(b.path(relative));
        const bytes = directory.readFileAlloc(b.graph.io, entry.path, b.allocator, .unlimited) catch @panic("read native asset");
        sources.put(b.allocator, b.dupe(entry.path), bytes) catch @panic("OOM");
    }
    return sources;
}
/// Keep every native runtime C translation unit, every header, and the Zig runtime closure.
fn select(b: *std.Build, selection: *Selection) void {
    for (selection.sources.keys()) |path| {
        if (std.mem.indexOfScalar(u8, path, '/') != null) continue;
        if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) keep(b, selection, path, false);
    }
    for (zig_roots) |root| keep(b, selection, root, true);
    while (selection.pending.pop()) |path| {
        const bytes = selection.sources.get(path) orelse continue;
        const parent = std.fs.path.dirname(path) orelse "";
        references(b, selection, .{ .parent = parent, .bytes = bytes, .marker = "@import(\"", .scan = true });
        references(b, selection, .{ .parent = parent, .bytes = bytes, .marker = "@embedFile(\"", .scan = false });
    }
}
/// One reference scan over a Zig unit: which builtin, and whether hits are scanned in turn.
const Scan = struct { parent: []const u8, bytes: []const u8, marker: []const u8, scan: bool };
/// Follow `@import`/`@embedFile` operands so a new runtime dependency is bundled automatically.
fn references(b: *std.Build, selection: *Selection, scan: Scan) void {
    var rest = scan.bytes;
    while (std.mem.indexOf(u8, rest, scan.marker)) |found| {
        rest = rest[found + scan.marker.len ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return;
        const operand = rest[0..end];
        rest = rest[end..];
        if (scan.scan and !std.mem.endsWith(u8, operand, ".zig")) continue;
        if (std.mem.indexOfScalar(u8, operand, '\\') != null) continue;
        keep(b, selection, b.pathJoin(&.{ scan.parent, operand }), scan.scan);
    }
}
/// Record a real source input once; Zig units are queued so their references are followed.
/// A reference that does not name a file under `src` (a module name, a generated path)
/// is simply not an asset.
fn keep(b: *std.Build, selection: *Selection, path: []const u8, scan: bool) void {
    if (!selection.sources.contains(path)) return;
    const entry = selection.chosen.getOrPut(b.allocator, path) catch @panic("OOM");
    if (entry.found_existing) return;
    entry.key_ptr.* = b.dupe(path);
    if (scan) selection.pending.append(b.allocator, entry.key_ptr.*) catch @panic("OOM");
}
/// Summarize named inputs as path, length and content hash without a cryptographic pass.
fn manifest(b: *std.Build, sources: Sources, paths: []const []const u8) []const u8 {
    var text: std.Io.Writer.Allocating = .init(b.allocator);
    for (paths) |path| {
        const bytes = sources.get(path) orelse continue;
        text.writer.print("{s}\x00{d}\x00{x}\n", .{ path, bytes.len, std.hash.Wyhash.hash(0, bytes) }) catch @panic("OOM");
    }
    return text.written();
}
/// The compiler's own identity: every source input, the Zig toolchain, and the optimize mode.
fn identity(b: *std.Build, sources: Sources, optimize: std.builtin.OptimizeMode) []const u8 {
    const paths = b.allocator.dupe([]const u8, sources.keys()) catch @panic("OOM");
    std.mem.sort([]const u8, paths, {}, order);
    const summary = std.fmt.allocPrint(b.allocator, "mylang-compiler-identity-v1\n{s}\n{s}\n{s}", .{
        @import("builtin").zig_version_string, @tagName(optimize), manifest(b, sources, paths),
    }) catch @panic("OOM");
    return digest(b, summary);
}
/// Lowercase hexadecimal SHA-256 of a canonical build-time summary.
fn digest(b: *std.Build, bytes: []const u8) []const u8 {
    var hash: [32]u8 = undefined;
    Sha.hash(bytes, &hash, .{});
    return b.dupe(&std.fmt.bytesToHex(hash, .lower));
}
fn order(_: void, a: []const u8, c: []const u8) bool {
    return std.mem.lessThan(u8, a, c);
}

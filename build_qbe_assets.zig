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
/// the compiler identity derived from every *production* source input and the
/// toolchain, and the narrower native-driver identity over just the sources that
/// decide how emitted IL becomes an object or an executable. Test-only sources are
/// read by their own test roots, so they neither bundle nor participate in either.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    b.dependOnDirectory(b.path("src"));
    const sources = read(b);
    var selection: Selection = .{ .sources = sources };
    select(b, &selection);
    const paths = selection.chosen.keys();
    std.mem.sort([]const u8, paths, {}, order);
    // The identity is a sorted list of every production source; exposing it lets a
    // test root assert the split, and keeps the digest and the emitted list in step.
    const identity_paths = b.allocator.dupe([]const u8, sources.keys()) catch @panic("OOM");
    std.mem.sort([]const u8, identity_paths, {}, order);
    const files = b.addWriteFiles();
    var text: std.Io.Writer.Allocating = .init(b.allocator);
    text.writer.writeAll("pub const Asset = struct { path: []const u8, bytes: []const u8 };\npub const files = [_]Asset{\n") catch @panic("OOM");
    for (paths) |path| {
        _ = files.addCopyFile(b.path(b.pathJoin(&.{ "src", path })), b.pathJoin(&.{ "src", path }));
        text.writer.print(".{{ .path=\"{s}\", .bytes=@embedFile(\"src/{s}\") }},\n", .{ path, path }) catch @panic("OOM");
    }
    text.writer.print("}};\npub const zig_version = \"{s}\";\n", .{@import("builtin").zig_version_string}) catch @panic("OOM");
    text.writer.writeAll("pub const identity_inputs = [_][]const u8{\n") catch @panic("OOM");
    for (identity_paths) |path| text.writer.print("    \"{s}\",\n", .{path}) catch @panic("OOM");
    text.writer.writeAll("};\n") catch @panic("OOM");
    const driver_paths = drivers(b, identity_paths);
    text.writer.writeAll("pub const driver_inputs = [_][]const u8{\n") catch @panic("OOM");
    for (driver_paths) |path| text.writer.print("    \"{s}\",\n", .{path}) catch @panic("OOM");
    text.writer.writeAll("};\n") catch @panic("OOM");
    text.writer.print("pub const content_hash = \"{s}\";\n", .{digest(b, manifest(b, sources, paths))}) catch @panic("OOM");
    text.writer.print("pub const compiler_identity = \"{s}\";\n", .{identity(b, sources, identity_paths, optimize, "mylang-compiler-identity-v1")}) catch @panic("OOM");
    text.writer.print("pub const driver_identity = \"{s}\";\n", .{identity(b, sources, driver_paths, optimize, "mylang-native-driver-identity-v1")}) catch @panic("OOM");
    return b.createModule(.{ .root_source_file = files.add("assets.zig", text.written()), .target = target, .optimize = optimize });
}
/// True when a source decides how already-emitted QBE IL becomes a native object
/// or executable: the native build driver itself and the link-argument policy.
/// Everything else about a build is already keyed separately — the IL text names
/// each object, `content_hash` covers the bundled runtime sources, the tool
/// stamps cover QBE and Zig — so only these files, the optimize mode and the Zig
/// version can change an object whose IL did not change.
fn drivesNativeBuilds(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, '/') != null) return false;
    return std.mem.startsWith(u8, path, "qbe_build") or std.mem.startsWith(u8, path, "native_link");
}
/// The sorted subset of production inputs that drive native builds.
fn drivers(b: *std.Build, identity_paths: []const []const u8) []const []const u8 {
    var chosen: std.ArrayList([]const u8) = .empty;
    for (identity_paths) |path| {
        if (!drivesNativeBuilds(path)) continue;
        chosen.append(b.allocator, path) catch @panic("OOM");
    }
    return chosen.toOwnedSlice(b.allocator) catch @panic("OOM");
}
/// True when a source path is consumed only by a test root. The production
/// compiler and runtime never import these, so they must neither bundle nor
/// invalidate `compiler_identity`; a Zig test root already tracks them directly.
fn testOnly(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, name, "_test.zig")) return true;
    if (std.mem.eql(u8, name, "tests.zig")) return true;
    return std.mem.eql(u8, name, "test_support.zig") or
        std.mem.eql(u8, name, "unit_test.zig") or
        std.mem.eql(u8, name, "nominal_provider_fixture.zig") or
        std.mem.eql(u8, name, "stdlib_fixture.zig");
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
        // A test-only file is compiled by its test root, which Zig tracks on its
        // own. Binding it here would rebuild the compiler for an edit that cannot
        // affect it, so drop it from both the content dependency and the identity.
        if (testOnly(entry.path)) continue;
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
/// A build-time identity over a named subset of the production source inputs, the
/// Zig toolchain and the optimize mode. `domain` separates the compiler's whole
/// identity from the narrower native-driver one, so a digest computed for one can
/// never be mistaken for the other. Test-only edits leave both unchanged.
fn identity(b: *std.Build, sources: Sources, paths: []const []const u8, optimize: std.builtin.OptimizeMode, domain: []const u8) []const u8 {
    const summary = std.fmt.allocPrint(b.allocator, "{s}\n{s}\n{s}\n{s}", .{
        domain, @import("builtin").zig_version_string, @tagName(optimize), manifest(b, sources, paths),
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

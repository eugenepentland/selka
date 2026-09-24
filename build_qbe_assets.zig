//! Bundle only the native runtime build inputs, plus build-time identities, into the compiler.
//!
//! The file has two halves. `module` runs in `build.zig`'s configure phase and
//! only wires steps: it reads no source contents. `main` is the same file compiled
//! as a host tool and run in the make phase. It walks `src`, selects the runtime
//! closure, copies it beside a generated `assets.zig`, and computes
//! `content_hash`, `compiler_identity` and `driver_identity` from the bytes it
//! just copied.
//!
//! The digests cannot be computed at configure time. Zig caches the configure
//! phase under a key that ignores the build root, and it records a
//! `dependOnFileContents` input by absolute path. Two trees built with one
//! `ZIG_LOCAL_CACHE_DIR` therefore share a configuration: the second tree
//! embedded the first tree's `content_hash` next to its own `@embedFile` bytes,
//! and none of its later edits invalidated that. A make-phase `Run` step is keyed
//! on its absolute `src` argument and on the contents of every file its depfile
//! names, so the digests always describe the bytes this tree bundles.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;
/// Zig runtime translation units `mylang build` compiles directly; their transitive
/// `@import`/`@embedFile` closure is bundled with them.
const zig_roots = [_][]const u8{"native_format.zig"};
/// Source bytes read once per tool run, keyed by path relative to `src`.
const Sources = std.StringArrayHashMapUnmanaged([]const u8);
/// Every source input, the selected runtime subset, and the Zig units still to scan.
const Selection = struct { sources: Sources, chosen: std.StringArrayHashMapUnmanaged(void) = .empty, pending: std.ArrayList([]const u8) = .empty };
/// Resident-memory ceilings for the asset tool's compilation and its run.
pub const Budget = struct { compile: u64, run: u64 };
/// Build the embedded runtime asset module. The module's root is `assets.zig`,
/// which a make-phase run of this file writes: the selected inputs, their content
/// hash, the compiler identity derived from every *production* source input and
/// the toolchain, and the narrower native-driver identity over just the sources
/// that decide how emitted IL becomes an object or an executable. Test-only
/// sources are read by their own test roots, so they neither bundle nor
/// participate in either identity.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, budget: Budget) *std.Build.Module {
    const tool = b.addExecutable(.{ .max_rss = budget.compile, .name = "qbe-build-assets", .root_module = b.createModule(.{
        .root_source_file = b.path("build_qbe_assets.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }) });
    const run = b.addRunArtifact(tool);
    run.step.max_rss = budget.run;
    // The configured build root travels as a plain string, while `src` resolves
    // when the step runs. They disagree only when this configuration was cached
    // for another tree that shares the Zig cache; the tool then refuses to run,
    // because every absolute path this configuration holds names that other tree.
    run.addArg(buildRoot(b));
    // Absolute, so the step's cache key names this tree's `src`. A relative
    // argument would give every tree the same key and hand this one another
    // tree's recorded outputs.
    run.addDirectoryArg2(b.path("src"), .{ .make_absolute = true });
    run.addArg(@import("builtin").zig_version_string);
    run.addArg(@tagName(optimize));
    const out = run.addOutputDirectoryArg("qbe_build_assets");
    // The tool lists every file it read. Their contents join the step's cache
    // key, so an edit to any production source re-runs it.
    _ = run.addDepFileOutputArg("assets.d");
    return b.createModule(.{ .root_source_file = out.path(b, "assets.zig"), .target = target, .optimize = optimize });
}
/// The configure phase's real path of the build root.
fn buildRoot(b: *std.Build) []const u8 {
    var root = b.root.openDir(b.graph.io, ".", .{}) catch @panic("open build root");
    defer root.close(b.graph.io);
    return root.realPathFileAlloc(b.graph.io, ".", b.allocator) catch @panic("resolve build root");
}
/// Make-phase entry point, run by the step `module` wires:
/// `<configured build root> <src dir> <zig version> <optimize> <out dir> <depfile>`.
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 7) fail("usage: qbe-build-assets ROOT SRC ZIG_VERSION OPTIMIZE OUT DEPFILE", .{});
    const cwd = std.Io.Dir.cwd();
    const src = try cwd.realPathFileAlloc(io, args[2], a);
    const tree = std.fs.path.dirname(src) orelse src;
    if (!std.mem.eql(u8, tree, args[1])) fail(
        \\this build configuration belongs to {s}, not {s}.
        \\Two source trees shared one Zig cache and the configure phase was reused
        \\across them, so its absolute paths name the other tree. Give each tree its
        \\own ZIG_LOCAL_CACHE_DIR (or --cache-dir).
    , .{ args[1], tree });
    const identities: Identities = .{ .zig_version = args[3], .optimize = args[4] };
    var directory = try cwd.openDir(io, src, .{ .iterate = true });
    defer directory.close(io);
    const sources = try read(a, io, directory);
    var selection: Selection = .{ .sources = sources };
    try select(a, &selection);
    const paths = selection.chosen.keys();
    std.mem.sort([]const u8, paths, {}, order);
    var out = try cwd.createDirPathOpen(io, args[5], .{});
    defer out.close(io);
    for (paths) |path| {
        const target = try std.fs.path.join(a, &.{ "src", path });
        if (std.fs.path.dirname(target)) |parent| try out.createDirPath(io, parent);
        try out.writeFile(io, .{ .sub_path = target, .data = sources.get(path).? });
    }
    try out.writeFile(io, .{ .sub_path = "assets.zig", .data = try render(a, sources, paths, identities) });
    try cwd.writeFile(io, .{ .sub_path = args[6], .data = try depfile(a, src, sources.keys()) });
}
/// Report a tool failure on standard error and exit with status 1.
fn fail(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print("qbe-build-assets: " ++ format ++ "\n", arguments);
    std.process.exit(1);
}
/// The toolchain and optimize mode every identity digest includes.
const Identities = struct { zig_version: []const u8, optimize: []const u8 };
/// The generated `assets.zig`: the bundled files and every build-time identity.
fn render(a: std.mem.Allocator, sources: Sources, paths: []const []const u8, identities: Identities) ![]const u8 {
    // The identity is a sorted list of every production source; exposing it lets a
    // test root assert the split, and keeps the digest and the emitted list in step.
    const identity_paths = try a.dupe([]const u8, sources.keys());
    std.mem.sort([]const u8, identity_paths, {}, order);
    const driver_paths = try drivers(a, identity_paths);
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    try w.writeAll("pub const Asset = struct { path: []const u8, bytes: []const u8 };\npub const files = [_]Asset{\n");
    for (paths) |path| try w.print(".{{ .path=\"{s}\", .bytes=@embedFile(\"src/{s}\") }},\n", .{ path, path });
    try w.print("}};\npub const zig_version = \"{s}\";\n", .{identities.zig_version});
    try w.writeAll("pub const identity_inputs = [_][]const u8{\n");
    for (identity_paths) |path| try w.print("    \"{s}\",\n", .{path});
    try w.writeAll("};\npub const driver_inputs = [_][]const u8{\n");
    for (driver_paths) |path| try w.print("    \"{s}\",\n", .{path});
    try w.writeAll("};\n");
    try w.print("pub const content_hash = \"{s}\";\n", .{&digest(try manifest(a, sources, paths))});
    try w.print("pub const compiler_identity = \"{s}\";\n", .{&try identity(a, sources, identity_paths, identities, "mylang-compiler-identity-v1")});
    try w.print("pub const driver_identity = \"{s}\";\n", .{&try identity(a, sources, driver_paths, identities, "mylang-native-driver-identity-v1")});
    return text.written();
}
/// A Makefile-style dependency list naming every file the tool read, by absolute path.
fn depfile(a: std.mem.Allocator, src: []const u8, paths: []const []const u8) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("assets.zig:");
    for (paths) |path| {
        try text.writer.writeAll(" \\\n ");
        for (try std.fs.path.join(a, &.{ src, path })) |byte| {
            if (byte == ' ' or byte == '#' or byte == '\\') try text.writer.writeByte('\\');
            try text.writer.writeByte(byte);
        }
    }
    try text.writer.writeByte('\n');
    return text.written();
}
/// True when a source decides how already-emitted QBE IL becomes a native object
/// or executable: the native build driver itself, the link-argument policy, and
/// the frame-map annotator that rewrites every unit's assembly before it is
/// assembled. Everything else about a build is already keyed separately — the IL
/// text names each object, `content_hash` covers the bundled runtime sources,
/// the tool stamps cover QBE and Zig — so only these files, the optimize mode
/// and the Zig version can change an object whose IL did not change.
fn drivesNativeBuilds(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, '/') != null) return false;
    if (std.mem.eql(u8, path, "qbe_frame_map.zig")) return true;
    return std.mem.startsWith(u8, path, "qbe_build") or std.mem.startsWith(u8, path, "native_link");
}
/// The sorted subset of production inputs that drive native builds.
fn drivers(a: std.mem.Allocator, identity_paths: []const []const u8) ![]const []const u8 {
    var chosen: std.ArrayList([]const u8) = .empty;
    for (identity_paths) |path| {
        if (!drivesNativeBuilds(path)) continue;
        try chosen.append(a, path);
    }
    return chosen.toOwnedSlice(a);
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
/// Read every production source input once; the same bytes feed identity and selection.
/// A test-only file is compiled by its test root, which Zig tracks on its own, so
/// it is neither read nor named in the depfile: editing it cannot rebuild the compiler.
fn read(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir) !Sources {
    var walker = try directory.walk(a);
    defer walker.deinit();
    var sources: Sources = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or testOnly(entry.path)) continue;
        const bytes = try directory.readFileAlloc(io, entry.path, a, .unlimited);
        try sources.put(a, try a.dupe(u8, entry.path), bytes);
    }
    return sources;
}
/// Keep every native runtime C translation unit, every header, and the Zig runtime closure.
fn select(a: std.mem.Allocator, selection: *Selection) !void {
    for (selection.sources.keys()) |path| {
        if (std.mem.indexOfScalar(u8, path, '/') != null) continue;
        if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) try keep(a, selection, path, false);
    }
    for (zig_roots) |root| try keep(a, selection, root, true);
    while (selection.pending.pop()) |path| {
        const bytes = selection.sources.get(path) orelse continue;
        const parent = std.fs.path.dirname(path) orelse "";
        try references(a, selection, .{ .parent = parent, .bytes = bytes, .marker = "@import(\"", .scan = true });
        try references(a, selection, .{ .parent = parent, .bytes = bytes, .marker = "@embedFile(\"", .scan = false });
    }
}
/// One reference scan over a Zig unit: which builtin, and whether hits are scanned in turn.
const Scan = struct { parent: []const u8, bytes: []const u8, marker: []const u8, scan: bool };
/// Follow `@import`/`@embedFile` operands so a new runtime dependency is bundled automatically.
fn references(a: std.mem.Allocator, selection: *Selection, scan: Scan) !void {
    var rest = scan.bytes;
    while (std.mem.indexOf(u8, rest, scan.marker)) |found| {
        rest = rest[found + scan.marker.len ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return;
        const operand = rest[0..end];
        rest = rest[end..];
        if (scan.scan and !std.mem.endsWith(u8, operand, ".zig")) continue;
        if (std.mem.indexOfScalar(u8, operand, '\\') != null) continue;
        try keep(a, selection, try std.fs.path.join(a, &.{ scan.parent, operand }), scan.scan);
    }
}
/// Record a real source input once; Zig units are queued so their references are followed.
/// A reference that does not name a file under `src` (a module name, a generated path)
/// is simply not an asset.
fn keep(a: std.mem.Allocator, selection: *Selection, path: []const u8, scan: bool) !void {
    if (!selection.sources.contains(path)) return;
    const entry = try selection.chosen.getOrPut(a, path);
    if (entry.found_existing) return;
    entry.key_ptr.* = try a.dupe(u8, path);
    if (scan) try selection.pending.append(a, entry.key_ptr.*);
}
/// Summarize named inputs as path, length and content hash without a cryptographic pass.
/// `src/qbe_build_test.zig` recomputes `content_hash` from the embedded bytes with
/// this exact encoding; keep them in step.
fn manifest(a: std.mem.Allocator, sources: Sources, paths: []const []const u8) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    for (paths) |path| {
        const bytes = sources.get(path) orelse continue;
        try text.writer.print("{s}\x00{d}\x00{x}\n", .{ path, bytes.len, std.hash.Wyhash.hash(0, bytes) });
    }
    return text.written();
}
/// A build-time identity over a named subset of the production source inputs, the
/// Zig toolchain and the optimize mode. `domain` separates the compiler's whole
/// identity from the narrower native-driver one, so a digest computed for one can
/// never be mistaken for the other. Test-only edits leave both unchanged.
fn identity(a: std.mem.Allocator, sources: Sources, paths: []const []const u8, identities: Identities, domain: []const u8) ![64]u8 {
    const summary = try std.fmt.allocPrint(a, "{s}\n{s}\n{s}\n{s}", .{
        domain, identities.zig_version, identities.optimize, try manifest(a, sources, paths),
    });
    return digest(summary);
}
/// Lowercase hexadecimal SHA-256 of a canonical build-time summary.
fn digest(bytes: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    Sha.hash(bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}
fn order(_: void, a: []const u8, c: []const u8) bool {
    return std.mem.lessThan(u8, a, c);
}

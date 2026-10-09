//! The compiler's build-time identity: a digest of every production source under
//! `src`, the Zig toolchain and the optimize mode.
//!
//! The file has two halves. `module` runs in `build.zig`'s configure phase and
//! only wires steps: it reads no source contents. `main` is the same file compiled
//! as a host tool and run in the make phase. It walks `src`, reads every
//! production source, and writes a generated `identity.zig` holding
//! `compiler_identity` and the sorted list of the sources it covers.
//!
//! The digest cannot be computed at configure time. Zig caches the configure
//! phase under a key that ignores the build root, and it records a
//! `dependOnFileContents` input by absolute path. Two trees built with one
//! `ZIG_LOCAL_CACHE_DIR` therefore share a configuration: the second tree
//! embedded the first tree's digest, and none of its later edits invalidated
//! that. A make-phase `Run` step is keyed on its absolute `src` argument and on
//! the contents of every file its depfile names, so the digest always describes
//! the bytes of this tree.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;
/// Source bytes read once per tool run, keyed by path relative to `src`.
const Sources = std.StringArrayHashMapUnmanaged([]const u8);
/// Resident-memory ceilings for the identity tool's compilation and its run.
pub const Budget = struct { compile: u64, run: u64 };
/// Build the identity module. Its root is `identity.zig`, which a make-phase run
/// of this file writes: the compiler identity derived from every *production*
/// source and the toolchain, and the list of sources it covers. Test-only sources
/// are read by their own test roots, so they never move the identity.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, budget: Budget) *std.Build.Module {
    const tool = b.addExecutable(.{ .max_rss = budget.compile, .name = "build-identity", .root_module = b.createModule(.{
        .root_source_file = b.path("build_identity.zig"),
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
    const out = run.addOutputDirectoryArg("build_identity");
    // The tool lists every file it read. Their contents join the step's cache
    // key, so an edit to any production source re-runs it.
    _ = run.addDepFileOutputArg("identity.d");
    return b.createModule(.{ .root_source_file = out.path(b, "identity.zig"), .target = target, .optimize = optimize });
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
    if (args.len != 7) fail("usage: build-identity ROOT SRC ZIG_VERSION OPTIMIZE OUT DEPFILE", .{});
    const cwd = std.Io.Dir.cwd();
    const src = try cwd.realPathFileAlloc(io, args[2], a);
    const tree = std.fs.path.dirname(src) orelse src;
    if (!std.mem.eql(u8, tree, args[1])) fail(
        \\this build configuration belongs to {s}, not {s}.
        \\Two source trees shared one Zig cache and the configure phase was reused
        \\across them, so its absolute paths name the other tree. Give each tree its
        \\own ZIG_LOCAL_CACHE_DIR (or --cache-dir).
    , .{ args[1], tree });
    var directory = try cwd.openDir(io, src, .{ .iterate = true });
    defer directory.close(io);
    const sources = try read(a, io, directory);
    var out = try cwd.createDirPathOpen(io, args[5], .{});
    defer out.close(io);
    try out.writeFile(io, .{ .sub_path = "identity.zig", .data = try render(a, sources, .{ .zig_version = args[3], .optimize = args[4] }) });
    try cwd.writeFile(io, .{ .sub_path = args[6], .data = try depfile(a, src, sources.keys()) });
}
/// Report a tool failure on standard error and exit with status 1.
fn fail(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print("build-identity: " ++ format ++ "\n", arguments);
    std.process.exit(1);
}
/// The toolchain and optimize mode the identity digest includes.
const Toolchain = struct { zig_version: []const u8, optimize: []const u8 };
/// The generated `identity.zig`: the covered sources and the compiler identity.
fn render(a: std.mem.Allocator, sources: Sources, toolchain: Toolchain) ![]const u8 {
    const paths = try a.dupe([]const u8, sources.keys());
    std.mem.sort([]const u8, paths, {}, order);
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    try w.print("/// The Zig toolchain this compiler was built with.\npub const zig_version = \"{s}\";\n", .{toolchain.zig_version});
    try w.writeAll("/// Every production source the identity covers, sorted, relative to `src`.\npub const identity_inputs = [_][]const u8{\n");
    for (paths) |path| try w.print("    \"{s}\",\n", .{path});
    try w.writeAll("};\n");
    try w.print("/// SHA-256 over the sources above, the toolchain and the optimize mode.\npub const compiler_identity = \"{s}\";\n", .{&try identity(a, sources, paths, toolchain)});
    return text.written();
}
/// A Makefile-style dependency list naming every file the tool read, by absolute path.
fn depfile(a: std.mem.Allocator, src: []const u8, paths: []const []const u8) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("identity.zig:");
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
/// True when a source path is consumed only by a test root. The production
/// compiler never imports these, so they must not move `compiler_identity`; a
/// Zig test root already tracks them directly.
fn testOnly(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, name, "_test.zig")) return true;
    return std.mem.eql(u8, name, "test_support.zig") or
        std.mem.eql(u8, name, "unit_test.zig") or
        std.mem.eql(u8, name, "nominal_provider_fixture.zig") or
        std.mem.eql(u8, name, "stdlib_fixture.zig");
}
/// Read every production source once. A test-only file is compiled by its test
/// root, which Zig tracks on its own, so it is neither read nor named in the
/// depfile: editing it cannot rebuild the compiler.
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
/// SHA-256, as lowercase hexadecimal, over a domain tag, the toolchain, the
/// optimize mode and each source's path, length and content hash.
fn identity(a: std.mem.Allocator, sources: Sources, paths: []const []const u8, toolchain: Toolchain) ![64]u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.print("selka-compiler-identity-v2\n{s}\n{s}\n", .{ toolchain.zig_version, toolchain.optimize });
    for (paths) |path| {
        const bytes = sources.get(path) orelse continue;
        try text.writer.print("{s}\x00{d}\x00{x}\n", .{ path, bytes.len, std.hash.Wyhash.hash(0, bytes) });
    }
    var hash: [32]u8 = undefined;
    Sha.hash(text.written(), &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}
fn order(_: void, a: []const u8, c: []const u8) bool {
    return std.mem.lessThan(u8, a, c);
}

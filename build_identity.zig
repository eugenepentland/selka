//! The compiler's build-time identity: a digest of every production source under
//! `src`, the Zig toolchain, the optimize mode and the bytes of every build product
//! `build.zig` embeds in the compiler.
//!
//! The file has two halves. `module` runs in `build.zig`'s configure phase and
//! only wires steps: it reads no source contents. `main` is the same file compiled
//! as a host tool and run in the make phase. It walks `src`, reads every
//! production source, and writes a generated `identity.zig` holding
//! `compiler_identity` and the sorted list of the sources it covers. Which sources it covers, and the digest itself, live in
//! `src/build_identity_rules.zig`, where unit tests reach them.
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
const rules = @import("src/build_identity_rules.zig");
const linux = std.os.linux;
/// Source bytes read once per tool run, keyed by path relative to `src`.
const Sources = rules.Sources;
/// Resident-memory ceilings for the identity tool's compilation and its run.
pub const Budget = struct { compile: u64, run: u64 };
/// A build product `build.zig` embeds in the compiler as bytes (`rules.named_files` marks each): the name the code
/// imports it by and the file it embeds. The identity digests the file's bytes, not the settings that built it, so a
/// change to how the product is built moves the identity exactly when it changes the product.
pub const Product = struct { name: []const u8, file: std.Build.LazyPath };
/// The admitted watch launcher may select this file's private live-identity option.
pub const admission_watch_identity = true;
/// How the identity tool uses its per-file record (the record section of `src/build_identity_rules.zig`): `off`
/// analyzes every source, `on` analyzes only the sources whose bytes the record does not hold (every source is still
/// read and hashed), and `check` computes the identity both ways and fails the build on any difference.
pub const RecordMode = enum { off, on, check };
var watch_mode: ?bool = null;
/// Whether this configuration is the admitted incremental watch (`-Dwatch-identity=true`, which `build-slot.sh` and
/// `scripts/dev_loop.py` pass): the option is declared once, here, and read by `module` and by `build.zig`'s installs.
pub fn watchMode(b: *std.Build) bool {
    if (watch_mode == null) watch_mode = b.option(bool, "watch-identity", "Use a private live identity module for an admitted incremental watch") orelse false;
    return watch_mode.?;
}
/// Build the identity module. Its root is `identity.zig`, which a make-phase run
/// of this file writes: the compiler identity derived from every *production*
/// source and the toolchain, and the list of sources it covers. Test-only sources
/// are read by their own test roots, so they never move the identity.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, budget: Budget, products: []const Product) *std.Build.Module {
    const watch_identity = watchMode(b);
    // The record serves the admitted watch by default; an ordinary build, and so every gate, analyzes every source
    // unless it asks for the record (D-DL3-5).
    const record_mode = b.option(RecordMode, "identity-record", "The identity tool's per-file record: off, on, or check (compute both ways and fail on a difference); default on under -Dwatch-identity, else off") orelse
        if (watch_identity) RecordMode.on else RecordMode.off;
    // The tool analyzes each source once (its token digest and its import edges under both walks) and forms every
    // closure and digest from those facts. It reads all of `src` (17 MB) every time; with the record it parses only the
    // files whose bytes changed.
    const tool = b.addExecutable(.{ .max_rss = budget.compile, .name = "build-identity", .root_module = b.createModule(.{
        .root_source_file = b.path("build_identity.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    }) });
    // Watchers must never share a mutable incremental host-tool executable.
    if (watch_identity) tool.incremental = false;
    const run = b.addRunArtifact(tool);
    run.step.max_rss = budget.run;
    // Under the watch the cached run only lists the sources: its depfile keys the step and registers the watch, while
    // the live run below forms the identity the compiler imports (D-DL3-1). Otherwise it forms the identity itself.
    if (watch_identity) run.addArg("--list-only") else addRecordArgs(run, record_mode);
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
    // Each embedded product: its name, then the file itself, whose content joins the step's cache key.
    for (products) |product| {
        run.addArg(product.name);
        run.addFileArg(product.file);
    }
    // Ordinary builds keep immutable, content-addressed identity modules. The
    // explicit watch option is injected only by the admitted watch launcher.
    if (!watch_identity) {
        return b.createModule(.{ .root_source_file = out.path(b, "identity.zig"), .target = target, .optimize = optimize });
    }
    // A persistent Zig child retains its initial module argv. Two input-free tmp
    // steps provide 128 bits of fresh make-process owner salt. They have no watched
    // inputs, so their generated pathnames remain stable across watch iterations.
    // Native cleanup deletes these directories after each successful build. Their
    // names remain salts; the owner-local tool is recreated before each live run.
    const owner_a = b.addWriteFiles();
    owner_a.mode = .tmp;
    const owner_b = b.addWriteFiles();
    owner_b.mode = .tmp;
    // The compiled tool's content-addressed pathname changes when its own
    // sources change. Copy it to this owner's fixed pathname before every
    // source-driven identity update, or that change would move the live module
    // pathname despite the owner salt. The tmp copy is never shared by Makers.
    const live_tool = b.addWriteFiles();
    live_tool.mode = .{ .mutate = owner_a.getDirectory() };
    live_tool.step.dependOn(&owner_a.step);
    live_tool.step.dependOn(&run.step);
    const live = b.addRunFile(live_tool.addCopyFile(tool.getEmittedBin(), "build-identity"));
    live.step.max_rss = budget.run;
    live.has_side_effects = true;
    live.addArg("--live-owner");
    live.addDirectoryArg2(owner_a.getDirectory(), .{ .make_absolute = true });
    live.addDirectoryArg2(owner_b.getDirectory(), .{ .make_absolute = true });
    addRecordArgs(live, record_mode);
    live.addArg(buildRoot(b));
    live.addDirectoryArg2(b.path("src"), .{ .make_absolute = true });
    live.addArg(@import("builtin").zig_version_string);
    live.addArg(@tagName(optimize));
    const live_out = live.addOutputDirectoryArg("build_identity");
    // Do not use a depfile output here: the original cached Run above owns all
    // source invalidation. The side-effect Run's static argv hash includes owner,
    // absolute tree, actual toolchain and optimization, keeping its pathname
    // private to this Maker session and stable across production-source edits.
    _ = live.addOutputFileArg("identity.d");
    for (products) |product| {
        live.addArg(product.name);
        live.addFileArg(product.file);
    }
    live.step.dependOn(&run.step);
    return b.createModule(.{ .root_source_file = live_out.path(b, "identity.zig"), .target = target, .optimize = optimize });
}
/// Pass the record options of `mode`: the record lives in this tree's local Zig cache, whose absolute path is a plain
/// argument (it joins the step's key as a string, never its contents).
fn addRecordArgs(run: *std.Build.Step.Run, mode: RecordMode) void {
    if (mode == .off) return;
    run.addArg("--record");
    run.addDirectoryArg2(std.Build.LazyPath.cache_root, .{ .make_absolute = true });
    if (mode == .check) run.addArg("--record-check");
}
/// The configure phase's real path of the build root.
fn buildRoot(b: *std.Build) []const u8 {
    var root = b.root.openDir(b.graph.io, ".", .{}) catch @panic("open build root");
    defer root.close(b.graph.io);
    return root.realPathFileAlloc(b.graph.io, ".", b.allocator) catch @panic("resolve build root");
}
/// The options that precede the positional arguments.
const Options = struct {
    /// The directory whose `selka-identity-record/record` holds the per-file record, when the record is used.
    record: ?[]const u8 = null,
    /// Compute the identity with and without the record and fail on any difference (`RecordMode.check`).
    check: bool = false,
    /// List the production sources (the depfile) and form no identity: the watch's cached run.
    list_only: bool = false,
    /// Print how many sources the record served and how many were read.
    report: bool = false,
};
/// Make-phase entry point, run by the step `module` wires:
/// `[--live-owner OWNER_A OWNER_B] [--list-only] [--record DIR [--record-check]] [--report] <configured build root>
/// <src dir> <zig version> <optimize> <out dir> <depfile> [<product name> <product file>]...`.
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const raw_args = try init.minimal.args.toSlice(a);
    var args = raw_args[1..];
    var options: Options = .{};
    while (args.len != 0 and std.mem.startsWith(u8, args[0], "--")) {
        if (std.mem.eql(u8, args[0], "--live-owner") and args.len > 2) {
            // Owner pathnames participate in the build Run's output key only. They are
            // deliberately not source inputs and need not remain present after a build.
            args = args[3..];
        } else if (std.mem.eql(u8, args[0], "--record") and args.len > 1) {
            options.record = args[1];
            args = args[2..];
        } else if (std.mem.eql(u8, args[0], "--record-check")) {
            options.check = true;
            args = args[1..];
        } else if (std.mem.eql(u8, args[0], "--list-only")) {
            options.list_only = true;
            args = args[1..];
        } else if (std.mem.eql(u8, args[0], "--report")) {
            options.report = true;
            args = args[1..];
        } else fail("unknown option {s}", .{args[0]});
    }
    if (args.len < 6 or (args.len - 6) % 2 != 0) fail("usage: build-identity [--live-owner OWNER_A OWNER_B] [--list-only] [--record DIR [--record-check]] [--report] ROOT SRC ZIG_VERSION OPTIMIZE OUT DEPFILE [PRODUCT_NAME PRODUCT_FILE]...", .{});
    if (options.check and options.record == null) fail("--record-check needs --record", .{});
    const cwd = std.Io.Dir.cwd();
    const src = try cwd.realPathFileAlloc(io, args[1], a);
    const tree = std.fs.path.dirname(src) orelse src;
    if (!std.mem.eql(u8, tree, args[0])) fail(
        \\this build configuration belongs to {s}, not {s}.
        \\Two source trees shared one Zig cache and the configure phase was reused
        \\across them, so its absolute paths name the other tree. Give each tree its
        \\own ZIG_LOCAL_CACHE_DIR (or --cache-dir).
    , .{ args[0], tree });
    var directory = try cwd.openDir(io, src, .{ .iterate = true });
    defer directory.close(io);
    var out = try cwd.createDirPathOpen(io, args[4], .{});
    defer out.close(io);
    if (options.list_only) {
        const paths = try listSources(a, io, directory);
        try out.writeFile(io, .{ .sub_path = "identity.zig", .data = "//! A list-only run of the build-identity tool: the watch build imports the live identity module.\n" });
        try cwd.writeFile(io, .{ .sub_path = args[5], .data = try depfile(a, src, paths) });
        return;
    }
    const products = try readProducts(a, io, args[6..]);
    rules.checkProducts(products) catch |err| fail("the embedded products do not match build_identity_rules.named_files ({s})", .{@errorName(err)});
    const toolchain: Toolchain = .{ .zig_version = args[2], .optimize = args[3], .products = products };
    const read_result = if (options.record) |dir|
        try recorded(a, io, directory, src, dir)
    else
        try readFacts(a, io, directory, null, null);
    const facts = read_result.facts;
    const corpus: rules.Corpus = .{ .facts = &facts };
    var identity = try render(a, corpus, toolchain);
    var dependencies = try depfile(a, src, facts.keys());
    if (options.report) std.debug.print("build-identity record: {d} served, {d} read\n", .{ read_result.served, facts.count() - read_result.served });
    if (options.check) {
        // The uncached tool: every source read again and every closure parsed from bytes, as before the record existed.
        const sources = try read(a, io, directory);
        // Each file's parse is freed once its edges are copied out, so the check's peak stays near one file's parse.
        const plain = try render(a, .{ .parsed = .{ .sources = &sources, .scratch = std.heap.page_allocator } }, toolchain);
        const plain_dependencies = try depfile(a, src, sources.keys());
        if (!std.mem.eql(u8, plain, identity)) fail("the record's identity differs from the uncached identity:\n--- uncached\n{s}\n--- record\n{s}", .{ plain, identity });
        if (!std.mem.eql(u8, plain_dependencies, dependencies)) fail("the record's depfile differs from the uncached depfile", .{});
        identity = plain;
        dependencies = plain_dependencies;
    }
    try writeIfChanged(a, io, out, "identity.zig", identity);
    try writeIfChanged(a, io, cwd, args[5], dependencies);
}
/// Write `data` to `sub_path` unless the file already holds exactly those bytes. Under the watch the live run's output
/// directory persists, and the compile steps watch `identity.zig`: rewriting an unchanged file made the watch build
/// everything once more after every edit (DL-3 part 2, proposal 1(iii)). A changed identity is still written.
fn writeIfChanged(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, sub_path: []const u8, data: []const u8) !void {
    if (dir.readFileAlloc(io, sub_path, a, .limited(data.len + 1))) |existing| {
        if (std.mem.eql(u8, existing, data)) return;
    } else |_| {}
    try dir.writeFile(io, .{ .sub_path = sub_path, .data = data });
}
/// Read each `NAME FILE` pair of the command line and digest the file's bytes. The result is sorted by name, so the
/// digested text does not depend on the order `build.zig` listed the products in.
fn readProducts(a: std.mem.Allocator, io: std.Io, pairs: []const []const u8) ![]const rules.Embedded {
    const products = try a.alloc(rules.Embedded, pairs.len / 2);
    for (products, 0..) |*product, index| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, pairs[2 * index + 1], a, .unlimited) catch |err| fail("cannot read the embedded product {s} at {s} ({s})", .{ pairs[2 * index], pairs[2 * index + 1], @errorName(err) });
        product.* = .{ .name = pairs[2 * index], .digest = rules.productDigest(bytes) };
    }
    std.mem.sort(rules.Embedded, products, {}, struct {
        fn less(_: void, left: rules.Embedded, right: rules.Embedded) bool {
            return std.mem.lessThan(u8, left.name, right.name);
        }
    }.less);
    return products;
}
/// Report a tool failure on standard error and exit with status 1.
fn fail(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print("build-identity: " ++ format ++ "\n", arguments);
    std.process.exit(1);
}
/// The toolchain and optimize mode the identity digests include.
const Toolchain = rules.Toolchain;
/// The generated `identity.zig`: the covered sources and the compiler identity.
fn render(a: std.mem.Allocator, corpus: rules.Corpus, toolchain: Toolchain) ![]const u8 {
    const paths = try corpus.sortedPaths(a);
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    try w.print("/// The Zig toolchain this compiler was built with.\npub const zig_version = \"{s}\";\n", .{toolchain.zig_version});
    try w.writeAll("/// Every production source the identity covers, sorted, relative to `src`.\npub const identity_inputs = [_][]const u8{\n");
    for (paths) |path| try w.print("    \"{s}\",\n", .{path});
    try w.writeAll("};\n");
    try w.writeAll("/// The build products embedded in the compiler as bytes, by the name the code imports them by, with the SHA-256 of their bytes.\npub const embedded_products = [_]struct { name: []const u8, digest: []const u8 }{\n");
    for (toolchain.products) |product| try w.print("    .{{ .name = \"{s}\", .digest = \"{s}\" }},\n", .{ product.name, &product.digest });
    try w.writeAll("};\n");
    try w.print("/// SHA-256 over the sources above, the toolchain, the optimize mode and the embedded products' bytes.\npub const compiler_identity = \"{s}\";\n", .{&try rules.digestChainedIn(a, rules.compiler_domain, toolchain, "", corpus, paths)});
    // Stage identities in `rules.stage_names` order. Each chains the identity of its upstream stage (`rules.stage_upstream`),
    // so a stage moves with every stage upstream of it. A refused closure fails the build, naming the stage (never narrowed).
    try w.writeAll("/// The stage identities, in pipeline order: each covers its import closure and the identity of its upstream stage.\npub const stage_identities = [_][]const u8{\n");
    var identities: [rules.stage_names.len][]const u8 = undefined;
    for (rules.stage_roots, 0..) |roots, index| {
        const closure = rules.closureIn(a, corpus, roots, .{}) catch |err| fail("stage {s}: the import closure is refused ({s})", .{ rules.stage_names[index], @errorName(err) });
        const upstream = if (rules.stage_upstream[index]) |earlier| identities[earlier] else "";
        // A stage whose closure reaches an embedded product's `@embedFile` carries that product's bytes.
        const stage_toolchain: Toolchain = .{ .zig_version = toolchain.zig_version, .optimize = toolchain.optimize, .products = try rules.reachedProducts(a, toolchain.products, closure) };
        const hex = try rules.digestChainedIn(a, rules.stage_domain, stage_toolchain, upstream, corpus, closure);
        identities[index] = try a.dupe(u8, &hex);
        try w.print("    \"{s}\",\n", .{identities[index]});
    }
    try w.writeAll("};\n");
    try renderKinds(a, w, corpus, toolchain);
    return text.written();
}

/// The engine kinds' names, identities and import closures, in `rules.engine_kinds` order. A refused closure fails the
/// build, naming the kind.
fn renderKinds(a: std.mem.Allocator, w: *std.Io.Writer, corpus: rules.Corpus, toolchain: Toolchain) !void {
    var identities: [rules.engine_kinds.len][]const u8 = undefined;
    try w.writeAll("/// The engine kinds' names, in the order of the tables below.\npub const kind_names = [_][]const u8{\n");
    for (rules.engine_kinds) |kind| try w.print("    \"{s}\",\n", .{kind.name});
    try w.writeAll("};\n/// The engine kinds' code identities (spec §3): the closure of each kind's roots, chained from its upstream kinds.\npub const kind_identities = [_][]const u8{\n");
    for (rules.engine_kinds, 0..) |_, index| {
        const hex = rules.engineKindIdentityIn(a, toolchain, corpus, index, identities[0..index]) catch |err| fail("engine kind {s}: the identity cannot be formed ({s})", .{ rules.engine_kinds[index].name, @errorName(err) });
        identities[index] = try a.dupe(u8, &hex);
        try w.print("    \"{s}\",\n", .{identities[index]});
    }
    try w.writeAll("};\n/// The files each engine kind's identity covers, relative to `src`, in the order of `kind_names`.\npub const kind_inputs = [_][]const []const u8{\n");
    for (rules.engine_kinds) |kind| {
        const files = rules.engineKindClosureIn(a, corpus, kind) catch |err| fail("engine kind {s}: the import closure is refused ({s})", .{ kind.name, @errorName(err) });
        try writePaths(w, files);
    }
    try w.writeAll("};\n/// The files each engine kind implements (the closure of its roots alone), which the no-raw-access scan reads.\npub const kind_code = [_][]const []const u8{\n");
    for (rules.engine_kinds) |kind| {
        const files = rules.engineKindCodeIn(a, corpus, kind) catch |err| fail("engine kind {s}: the code closure is refused ({s})", .{ kind.name, @errorName(err) });
        try writePaths(w, files);
    }
    try w.writeAll("};\n");
}

fn writePaths(w: *std.Io.Writer, files: []const []const u8) !void {
    try w.writeAll("    &.{\n");
    for (files) |path| try w.print("        \"{s}\",\n", .{path});
    try w.writeAll("    },\n");
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
/// The production source a walk entry names, or null for anything else: a directory, or a test-only file (compiled by
/// its test root, which Zig tracks on its own, so it is neither read nor named in the depfile). A symbolic link under
/// `src` fails the tool: no source of this tree is one (13 November 2026), and following one or skipping it would each
/// let the identity miss bytes a compile can read.
fn production(entry: std.Io.Dir.Walker.Entry) ?[]const u8 {
    if (entry.kind == .sym_link) fail("src/{s} is a symbolic link; the build identity covers regular files only, so replace it with the file it names", .{entry.path});
    if (entry.kind != .file or rules.isTestOnly(entry.path)) return null;
    return entry.path;
}
/// Read every production source once.
fn read(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir) !Sources {
    var walker = try directory.walk(a);
    defer walker.deinit();
    var sources: Sources = .empty;
    while (try walker.next(io)) |entry| {
        const path = production(entry) orelse continue;
        const bytes = try directory.readFileAlloc(io, path, a, .unlimited);
        try sources.put(a, try a.dupe(u8, path), bytes);
    }
    return sources;
}
/// The production sources in walk order, by path relative to `src`, without reading them.
fn listSources(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir) ![]const []const u8 {
    var walker = try directory.walk(a);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        const path = production(entry) orelse continue;
        try paths.append(a, try a.dupe(u8, path));
    }
    return paths.items;
}
/// Every production source's facts, in walk order. With a record (`old`), a source whose bytes hash to an entry's key is
/// served that entry's facts; every other source is analyzed. Each source is read once, and its key and its facts come
/// from those same bytes. `entries` receives this run's entries.
fn readFacts(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, old: ?*const rules.RecordEntries, entries: ?*rules.RecordEntries) !Read {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var walker = try directory.walk(a);
    defer walker.deinit();
    var result: Read = .{ .facts = .empty };
    while (try walker.next(io)) |entry| {
        const found = production(entry) orelse continue;
        const path = try a.dupe(u8, found);
        const bytes = try directory.readFileAlloc(io, path, scratch.allocator(), .unlimited);
        const key = rules.contentKey(bytes);
        const known = if (old) |record| record.get(path) else null;
        const facts = if (known != null and rules.recordServes(known.?, key)) served: {
            result.served += 1;
            break :served known.?.facts;
        } else try rules.analyze(a, &scratch, path, bytes);
        _ = scratch.reset(.retain_capacity);
        try result.facts.put(a, path, facts);
        if (entries) |out| try out.put(a, path, .{ .content = key, .facts = facts });
    }
    return result;
}
/// The facts of a run and how many of them the record served.
const Read = struct { facts: rules.Facts, served: usize = 0 };
/// The tool's own sources: a record written by any other version of them, or by a tool compiled with another Zig, is
/// ignored (`rules.recordToolKey`).
const tool_sources = [_][]const u8{ @embedFile("build_identity.zig"), @embedFile("src/build_identity_rules.zig") };
/// The production sources' facts, served from the record at `record_dir` for every source whose bytes it holds, then the
/// record replaced by one holding this run's entries. A record that cannot be read is ignored and one that cannot be
/// written is skipped: the record only saves analysis.
fn recorded(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, src: []const u8, record_dir: []const u8) !Read {
    const header: rules.RecordHeader = .{ .tool = rules.recordToolKey(@import("builtin").zig_version_string, &tool_sources), .root = src };
    const cwd = std.Io.Dir.cwd();
    var store = cwd.createDirPathOpen(io, try std.fs.path.join(a, &.{ record_dir, "selka-identity-record" }), .{}) catch
        return readFacts(a, io, directory, null, null);
    defer store.close(io);
    const old: rules.RecordEntries = blk: {
        const bytes = store.readFileAlloc(io, "record", a, .limited(rules.max_record_bytes)) catch break :blk .empty;
        break :blk (try rules.decodeRecord(a, bytes, header)) orelse .empty;
    };
    var entries: rules.RecordEntries = .empty;
    const result = try readFacts(a, io, directory, &old, &entries);
    // A new file in the record's directory, renamed over the record when it is whole.
    const temporary = try std.fmt.allocPrint(a, "record.{d}.tmp", .{linux.getpid()});
    store.deleteFile(io, temporary) catch {};
    const file = store.createFile(io, temporary, .{ .exclusive = true }) catch return result;
    var renamed = false;
    defer if (!renamed) store.deleteFile(io, temporary) catch {};
    file.writeStreamingAll(io, try rules.encodeRecord(a, header, &entries)) catch {
        file.close(io);
        return result;
    };
    file.close(io);
    std.Io.Dir.rename(store, temporary, store, "record", io) catch return result;
    renamed = true;
    return result;
}

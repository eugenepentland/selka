//! Focused native build-driver and adapter tests, independent of interpreter suites.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const bundled = @import("qbe_build_assets");
const runtime_options_variable = "MYLANG_OPTIONS";
const memory_limit_variable = "MYLANG_MEMORY_LIMIT";
const counting_contract = @import("runtime_contract");

test {
    _ = @import("qbe_build.zig");
    _ = @import("runtime_options.zig");
    _ = @import("qbe_build_cache.zig");
    _ = @import("qbe_build_io.zig");
    _ = @import("qbe_build_options.zig");
    _ = @import("qbe_build_outputs.zig");
    _ = @import("qbe_build_sites.zig");
    _ = @import("qbe_build_host.zig");
    _ = @import("qbe_build_embed.zig");
    _ = @import("qbe_build_shapes.zig");
    _ = @import("qbe_build_units.zig");
    _ = @import("qbe_build_receipt.zig");
    _ = @import("qbe_build_batch.zig");
    _ = @import("qbe_build_spawn.zig");
    _ = @import("qbe_build_link.zig");
}

// The two scenarios below spawn the installed compiler end to end, the way the
// deleted `tests/qbe_build_cli.py` driver did, so the prebuilt-runtime-archive
// and shared-runtime-tree paths keep coverage that exercises the real binary.

/// The build tools the suite drives, discovered from the environment the build
/// sets for this test root: `MYLANG_QBE`/`MYLANG_ZIG` name the tools, and the
/// compiler installs beside `qbe`.
const Tools = struct { compiler: []const u8, qbe: []const u8, zig: []const u8 };

/// One native-build invocation: the tools, the source and output paths, an
/// optional `--cache-dir` (empty selects the default cache), an optional working
/// directory (empty inherits the test's), and an optional child environment.
const Spec = struct {
    tools: Tools,
    source: []const u8,
    output: []const u8,
    cache: []const u8 = "",
    cwd: []const u8 = "",
    environment: ?*const std.process.Environ.Map = null,
};

/// The observable facts of one reported build the installed-runtime test checks.
const BuildReport = struct { installed: bool, reused: bool, cache_archives: usize, output: []const u8 };

/// The archive and formatter-object counts a runtime install directory holds.
const Installed = struct { archives: usize, objects: usize, stems_ok: bool };

fn tools(allocator: std.mem.Allocator) !Tools {
    const qbe = std.testing.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const zig = std.testing.environ.getPosix("MYLANG_ZIG") orelse return error.ToolNotFound;
    const directory = std.fs.path.dirname(qbe) orelse return error.ToolNotFound;
    return .{
        .compiler = try std.fs.path.join(allocator, &.{ directory, "mylang" }),
        .qbe = try allocator.dupe(u8, qbe),
        .zig = try allocator.dupe(u8, zig),
    };
}

fn join(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(allocator, parts);
}

/// Spawn a child, forwarding its diagnostics on failure, and return its stdout.
fn spawnOk(context: fs.Context, argv: []const []const u8, cwd: std.process.Child.Cwd, environment: ?*const std.process.Environ.Map) ![]u8 {
    const result = try std.process.run(context.allocator, context.io, .{ .argv = argv, .cwd = cwd, .environ_map = environment });
    if (fs.exitCode(result.term) != 0) {
        try std.Io.File.stderr().writeStreamingAll(context.io, result.stderr);
        return error.NativeToolFailed;
    }
    return result.stdout;
}

/// Run a built guest and return its stdout. The entry's `int` result is now the
/// process exit status, so a nonzero exit is the returned value rather than a
/// tool failure; only an abnormal termination (a signal or crash) is a failure.
fn runOutput(context: fs.Context, argv: []const []const u8, environment: ?*const std.process.Environ.Map) ![]u8 {
    const result = try std.process.run(context.allocator, context.io, .{ .argv = argv, .cwd = .inherit, .environ_map = environment });
    if (result.term != .exited) {
        try std.Io.File.stderr().writeStreamingAll(context.io, result.stderr);
        return error.NativeToolFailed;
    }
    return result.stdout;
}

fn cwdOf(spec: Spec) std.process.Child.Cwd {
    return if (spec.cwd.len == 0) .inherit else .{ .path = spec.cwd };
}

fn buildArgv(context: fs.Context, spec: Spec, report: bool) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    const a = context.allocator;
    try argv.appendSlice(a, &.{ spec.tools.compiler, "build", spec.source, "-o", spec.output, "--qbe", spec.tools.qbe, "--zig", spec.tools.zig });
    if (spec.cache.len != 0) try argv.appendSlice(a, &.{ "--cache-dir", spec.cache });
    if (report) try argv.append(a, "--report");
    return argv.items;
}

/// Build without inspecting the report, used for the shared-tree scenario.
fn buildOnly(context: fs.Context, spec: Spec) !void {
    _ = try spawnOk(context, try buildArgv(context, spec, false), cwdOf(spec), spec.environment);
}

// spec-case: QBE-FRAMEMAP-ASM-1
// spec-case: RC-STARTUP-IMAGE-1
test "optional registration images link and run through direct and frame-map full and ThinLTO" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "entry.my" });
    try context.write(source, "module entry\n" ++
        "def main(out: Stream) -> int:\n" ++
        "    values = [0, 1, 2, 3, 4, 5, 6, 7]\n" ++
        "    out.print(len(values))\n" ++
        "    return 0\n");
    const Case = struct { rc: bool = true, image: bool = false, framed: bool = true, lto: []const u8 };
    const cases = [_]Case{
        .{ .framed = false, .lto = "--lto" },
        .{ .framed = false, .lto = "--lto=thin" },
        .{ .lto = "--lto" },
        .{ .lto = "--lto=thin" },
        .{ .image = true, .lto = "--lto" },
        .{ .image = true, .lto = "--lto=thin" },
        .{ .rc = false, .lto = "--lto" },
        .{ .rc = false, .lto = "--lto=thin" },
    };
    const cache = try join(a, &.{ root, "cache" });
    for (cases, 0..) |case, index| {
        var emission: std.ArrayList([]const u8) = .empty;
        try emission.appendSlice(a, &.{ resolved.compiler, "emit-project-qbe", source, if (case.rc) "--rc-runtime" else "--gc-runtime", "--drop-step-checks", "--drop-frame-checks" });
        if (!case.framed) try emission.append(a, "--drop-debug");
        const original = try spawnOk(context, emission.items, .inherit, null);
        var manifest = try std.json.parseFromSliceLeaky(std.json.Value, a, original, .{ .allocate = .alloc_always });
        if (case.rc and !case.image) {
            const text = manifest.object.getPtr("runtime_data").?;
            const definition = "const myl_rc_image myl_rc_generated_image =";
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text.string, definition));
            // A public ABI4 module remains valid without the separate optional
            // startup image, as for foreign/legacy native metadata producers.
            text.string = try std.mem.replaceOwned(u8, a, text.string, definition, "const myl_rc_image myl_rc_generated_image_unused =");
        }
        const manifest_file = try std.fmt.allocPrint(a, "{s}/manifest-{d}.json", .{ root, index });
        try context.write(manifest_file, try std.json.Stringify.valueAlloc(a, manifest, .{}));
        const binary = try std.fmt.allocPrint(a, "{s}/program-{d}", .{ root, index });
        _ = try spawnOk(context, &.{
            resolved.compiler, "build",        source,        "--manifest-file", manifest_file,
            "-o",              binary,         "--cache-dir", cache,             if (case.rc) "--rc-runtime" else "--gc-runtime",
            "--backend=llvm",  "--llvm-opt=3", case.lto,      "--zig",           resolved.zig,
        }, .inherit, null);
        const ran = try std.process.run(a, context.io, .{ .argv = &.{binary} });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
        try std.testing.expectEqualStrings("8\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

/// Build with `--report`, then run the program, returning the facts the
/// installed-runtime scenario asserts on.
fn buildAndRun(context: fs.Context, spec: Spec) !BuildReport {
    const stdout = try spawnOk(context, try buildArgv(context, spec, true), cwdOf(spec), spec.environment);
    const parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, stdout, .{ .allocate = .alloc_always });
    // A built program reads its runtime options from the environment, never
    // from its own arguments.
    var reporting = if (spec.environment) |environment| try environment.clone(context.allocator) else try std.process.Environ.createMap(std.testing.environ, context.allocator);
    try reporting.put(runtime_options_variable, "--print-result");
    const output = try runOutput(context, &.{spec.output}, &reporting);
    return .{
        .installed = v.boolean(v.get(parsed.value, "runtime_installed")),
        .reused = v.boolean(v.get(parsed.value, "runtime_reused")),
        .cache_archives = try archives(context, spec.cache),
        .output = output,
    };
}

/// The names of every entry directly under `directory`; an absent directory is empty.
fn entries(context: fs.Context, directory: []const u8) ![]const []const u8 {
    var handle = std.Io.Dir.cwd().openDir(context.io, directory, .{ .iterate = true }) catch return &.{};
    defer handle.close(context.io);
    var iterator = handle.iterate();
    var list: std.ArrayList([]const u8) = .empty;
    while (try iterator.next(context.io)) |entry| try list.append(context.allocator, try context.allocator.dupe(u8, entry.name));
    return list.items;
}

/// How many files directly under `directory` end with `suffix`; a `.a` count
/// excludes the `.a.digest` sidecar because that ends in `.digest`.
fn countSuffix(context: fs.Context, directory: []const u8, suffix: []const u8) !usize {
    var found: usize = 0;
    for (try entries(context, directory)) |name| {
        if (std.mem.endsWith(u8, name, suffix)) found += 1;
    }
    return found;
}

/// How many runtime archives the cache holds across its object generations, which
/// live one directory deep under `objects/`.
fn archives(context: fs.Context, cache: []const u8) !usize {
    var found: usize = 0;
    const objects = try join(context.allocator, &.{ cache, "objects" });
    for (try entries(context, objects)) |name| found += try countSuffix(context, try join(context.allocator, &.{ objects, name }), ".a");
    return found;
}

/// Emit the runtime install beside a compiler and report its archive/object shape.
fn emitInstalled(context: fs.Context, resolved: Tools, out: []const u8, work: []const u8) !Installed {
    _ = try spawnOk(context, &.{ resolved.compiler, "emit-runtime", "--zig", resolved.zig, "--qbe", resolved.qbe, "--out", out, "--work", work }, .inherit, null);
    var result: Installed = .{ .archives = 0, .objects = 0, .stems_ok = true };
    for (try entries(context, out)) |name| {
        if (std.mem.endsWith(u8, name, ".a")) {
            result.archives += 1;
            if (name.len - 2 != 64) result.stems_ok = false;
        } else if (std.mem.endsWith(u8, name, ".o")) result.objects += 1;
    }
    return result;
}

/// Overwrite every installed archive so its fingerprint no longer matches.
fn corruptArchives(context: fs.Context, directory: []const u8) !void {
    for (try entries(context, directory)) |name| {
        if (std.mem.endsWith(u8, name, ".a")) try context.write(try join(context.allocator, &.{ directory, name }), "not an archive");
    }
}

/// Copy the built compiler into `destination` and mark it executable.
fn install(context: fs.Context, from: []const u8, destination: []const u8) !void {
    try context.write(destination, try context.read(from));
    try std.Io.Dir.cwd().setFilePermissions(context.io, destination, .executable_file, .{});
}

// spec-case: QBE-RUNTIME-INSTALLED-1
test "a prebuilt runtime installed beside the compiler links directly, and damage falls back to source" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const bin = try join(a, &.{ root, "install", "bin" });
    const lib = try join(a, &.{ root, "install", "lib", "mylang-runtime" });
    try context.mkdir(bin);
    try context.mkdir(lib);
    const compiler = try join(a, &.{ bin, "mylang" });
    try install(context, resolved.compiler, compiler);
    const beside: Tools = .{ .compiler = compiler, .qbe = resolved.qbe, .zig = resolved.zig };

    const shaped = try emitInstalled(context, beside, lib, try join(a, &.{ root, "emit-work" }));
    // QBE in Debug and ReleaseFast, and the LLVM flavors, which need only Zig
    // now that the translator is built in: `llvm`, `llvm-lto`, `llvm-thinlto`.
    try std.testing.expectEqual(@as(usize, 5), shaped.archives);
    try std.testing.expectEqual(@as(usize, 2), shaped.objects);
    try std.testing.expect(shaped.stems_ok);

    const source = try join(a, &.{ root, "installed main.my" });
    try context.write(source, "def main() -> i64:\n    return 7\n");
    const program = try join(a, &.{ root, "prog" });
    const hit = try buildAndRun(context, .{ .tools = beside, .source = source, .output = program, .cache = try join(a, &.{ root, "installed cache" }) });
    try std.testing.expect(hit.installed);
    try std.testing.expect(hit.reused);
    try std.testing.expectEqual(@as(usize, 0), hit.cache_archives);
    try std.testing.expectEqualStrings("7\n", hit.output);

    try corruptArchives(context, lib);
    const miss = try buildAndRun(context, .{ .tools = beside, .source = source, .output = program, .cache = try join(a, &.{ root, "fallback cache" }) });
    try std.testing.expect(!miss.installed);
    try std.testing.expectEqual(@as(usize, 1), miss.cache_archives);
    try std.testing.expectEqualStrings("7\n", miss.output);
}

/// A three-module program whose modules each hold several functions, so a
/// batched build puts more than one function in an object. It prints, then
/// traps two modules deep, so the trace crosses batches.
const batch_program = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "main.my", .text =
    \\module main
    \\import shapes
    \\import walk
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    total = 0
    \\    for i in range(12):
    \\        total += shapes.area(i) + walk.step(i) + shapes.scaled(i, 3)
    \\    out.print(total)
    \\    out.print(walk.pick([4, 5, 6], 1))
    \\    out.print(walk.pick([4, 5, 6], 7))
    \\    return 0
    \\
    },
    .{ .name = "shapes.my", .text =
    \\module shapes
    \\
    \\
    \\public record Box:
    \\    w: int
    \\    h: int
    \\
    \\
    \\public def area(n: int) -> int:
    \\    b = Box(w=n, h=n + 1)
    \\    return b.w * b.h
    \\
    \\
    \\public def perimeter(n: int) -> int:
    \\    return 2 * (n + n + 1)
    \\
    \\
    \\public def scaled(n: int, k: int) -> int:
    \\    return area(n) * k - perimeter(n)
    \\
    \\
    \\public def diagonal(n: int) -> int:
    \\    return n * n + (n + 1) * (n + 1)
    \\
    },
    .{ .name = "walk.my", .text =
    \\module walk
    \\import shapes
    \\
    \\
    \\public def step(n: int) -> int:
    \\    return shapes.perimeter(n) - n + shapes.diagonal(n) % 7
    \\
    \\
    \\public def pick(xs: list[int], i: int) -> int:
    \\    return xs[i] + twice(i)
    \\
    \\
    \\def twice(n: int) -> int:
    \\    return n + n
    \\
    },
};

/// What one build of `batch_program` reported and what its executable did.
const BatchRun = struct { functions: usize, objects: usize, stdout: []const u8, stderr: []const u8, term: std.process.Child.Term };

/// Build `batch_program` in `directory` with `extra` build flags, grouping
/// functions as `MYLANG_QBE_BATCH` (empty: the default) says, then run it.
fn batchRun(context: fs.Context, resolved: Tools, directory: []const u8, grouping: []const u8, extra: []const []const u8) !BatchRun {
    const a = context.allocator;
    var environment = try std.process.Environ.createMap(std.testing.environ, a);
    _ = environment.swapRemove("MYLANG_QBE_BATCH");
    if (grouping.len != 0) try environment.put("MYLANG_QBE_BATCH", grouping);
    const output = try join(a, &.{ directory, try std.fmt.allocPrint(a, "program-{s}", .{if (grouping.len == 0) "batched" else grouping}) });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ resolved.compiler, "build", "main.my", "-o", output, "--qbe", resolved.qbe, "--zig", resolved.zig, "--report" });
    try argv.appendSlice(a, &.{ "--cache-dir", try join(a, &.{ directory, try std.fmt.allocPrint(a, "cache-{s}", .{if (grouping.len == 0) "batched" else grouping}) }) });
    try argv.appendSlice(a, extra);
    const report = try spawnOk(context, argv.items, .{ .path = directory }, &environment);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, report, .{ .allocate = .alloc_always });
    const ran = try std.process.run(a, context.io, .{ .argv = &.{output}, .cwd = .inherit });
    return .{
        .functions = v.array(v.get(parsed.value, "functions")).len,
        .objects = v.number(v.get(parsed.value, "function_objects")),
        .stdout = ran.stdout,
        .stderr = ran.stderr,
        .term = ran.term,
    };
}

/// Build and run `batch_program` batched and one function per object with
/// the same flags; both runs, batched first.
fn batchPair(context: fs.Context, resolved: Tools, directory: []const u8, extra: []const []const u8) ![2]BatchRun {
    return .{ try batchRun(context, resolved, directory, "", extra), try batchRun(context, resolved, directory, "1", extra) };
}

// spec: QBE-BATCH-2
test "a batched build and an unbatched build of one program behave identically" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (batch_program) |file| try context.write(try join(a, &.{ root, file.name }), file.text);
    // Debug: the frame record protocol and exact step accounting.
    const debug = try batchPair(context, resolved, root, &.{ "--mode", "Debug" });
    try std.testing.expect(debug[0].objects < debug[0].functions);
    try std.testing.expectEqual(debug[1].functions, debug[1].objects);
    try std.testing.expectEqual(debug[0].functions, debug[1].functions);
    try std.testing.expectEqualStrings("2272\n7\n", debug[0].stdout);
    try std.testing.expectEqualStrings(debug[1].stdout, debug[0].stdout);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, debug[0].term);
    try std.testing.expectEqual(debug[1].term, debug[0].term);
    try std.testing.expect(std.mem.indexOf(u8, debug[0].stderr, "R_LIST_BOUNDS") != null);
    try std.testing.expectEqualStrings(debug[1].stderr, debug[0].stderr);
    // A QBE ReleaseFast executable carries no frame record: its trap trace
    // comes from the frame map each batch's assembly was annotated with.
    const fast = try batchPair(context, resolved, root, &.{ "--mode", "ReleaseFast" });
    try std.testing.expect(fast[0].objects < fast[0].functions);
    try std.testing.expectEqualStrings(debug[0].stdout, fast[0].stdout);
    try std.testing.expectEqualStrings(fast[1].stdout, fast[0].stdout);
    try std.testing.expectEqual(fast[1].term, fast[0].term);
    try std.testing.expect(std.mem.indexOf(u8, fast[0].stderr, "in walk::pick") != null or std.mem.indexOf(u8, fast[0].stderr, "pick") != null);
    try std.testing.expectEqualStrings(fast[1].stderr, fast[0].stderr);
}

// spec-case: EXIT-STATUS-1
test "a native executable exits with its entry int result truncated to a byte" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const cache = try join(a, &.{ root, "cache" });
    const seven = try join(a, &.{ root, "seven.my" });
    try context.write(seven, "def main() -> i64:\n    return 7\n");
    const seven_bin = try join(a, &.{ root, "seven" });
    _ = try spawnOk(context, try buildArgv(context, .{ .tools = resolved, .source = seven, .output = seven_bin, .cache = cache }, false), .inherit, null);
    const ran = try std.process.run(a, context.io, .{ .argv = &.{seven_bin}, .cwd = .inherit });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 7 }, ran.term);
    const wide = try join(a, &.{ root, "wide.my" });
    try context.write(wide, "def main() -> i64:\n    return 256\n");
    const wide_bin = try join(a, &.{ root, "wide" });
    _ = try spawnOk(context, try buildArgv(context, .{ .tools = resolved, .source = wide, .output = wide_bin, .cache = cache }, false), .inherit, null);
    const wrapped = try std.process.run(a, context.io, .{ .argv = &.{wide_bin}, .cwd = .inherit });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, wrapped.term);
}

/// QBE IL for one loop whose header carries `count` phis, each live around the
/// loop and summed after it, so the edge into the header is one parallel move
/// of `count` copies plus the counter's.
fn widePhiLoop(allocator: std.mem.Allocator, count: usize) ![]const u8 {
    var il: std.Io.Writer.Allocating = .init(allocator);
    const w = &il.writer;
    try w.writeAll("export function l $wide(l %n) {\n@start\n");
    for (0..count) |i| try w.print(" %a{d}.0 =l copy {d}\n", .{ i, i });
    try w.writeAll(" %i.0 =l copy 0\n@loop\n");
    for (0..count) |i| try w.print(" %a{d} =l phi @start %a{d}.0, @body %a{d}.1\n", .{ i, i, i });
    try w.writeAll(" %i =l phi @start %i.0, @body %i.1\n %c =w csltl %i, %n\n jnz %c, @body, @done\n@body\n");
    for (0..count) |i| try w.print(" %a{d}.1 =l add %a{d}, 1\n", .{ i, (i + 1) % count });
    try w.writeAll(" %i.1 =l add %i, 1\n jmp @loop\n@done\n %s0 =l copy %a0\n");
    for (1..count) |i| try w.print(" %s{d} =l add %s{d}, %a{d}\n", .{ i, i - 1, i });
    try w.print(" ret %s{d}\n}}\n", .{count - 1});
    return il.written();
}

// Upstream QBE 1.3 keeps a block edge's parallel move in a fixed 64-entry table
// and dies with `no more pm slots` beyond it; the vendored copy grows the table.
// spec: QBE-PARALLEL-MOVE-1
test "the vendored QBE allocates a parallel move wider than its initial table" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "wide.ssa" });
    try context.write(source, try widePhiLoop(a, 200));
    const assembly = try join(a, &.{ root, "wide.s" });
    _ = try spawnOk(context, &.{ resolved.qbe, "-o", assembly, source }, .inherit, null);
    try std.testing.expect(std.mem.indexOf(u8, try context.read(assembly), "wide:") != null);
}

// spec-case: QBE-3
test "a default build shares its runtime tree under XDG while an explicit cache-dir stays hermetic" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const resolved = try tools(a);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const xdg = try join(a, &.{ root, "xdg cache" });
    var child = try std.process.Environ.createMap(std.testing.environ, a);
    try child.put("XDG_CACHE_HOME", xdg);

    // Hermetic: an explicit --cache-dir keeps the runtime tree under the cache and never touches XDG.
    const hermetic_source = try join(a, &.{ root, "hermetic main.my" });
    try context.write(hermetic_source, "def main() -> i64:\n    return 5\n");
    const hermetic_cache = try join(a, &.{ root, "hermetic cache" });
    try buildOnly(context, .{ .tools = resolved, .source = hermetic_source, .output = try join(a, &.{ root, "hermetic prog" }), .cache = hermetic_cache, .environment = &child });
    try std.testing.expect(context.exists(try join(a, &.{ hermetic_cache, "runtime" })));
    try std.testing.expect(!context.exists(try join(a, &.{ xdg, "mylang" })));

    // Default: the runtime tree materializes once under XDG and a second project reuses it.
    const first = try join(a, &.{ root, "default one" });
    const second = try join(a, &.{ root, "default two" });
    try context.mkdir(first);
    try context.mkdir(second);
    try context.write(try join(a, &.{ first, "m.my" }), "def main() -> i64:\n    return 6\n");
    try context.write(try join(a, &.{ second, "m.my" }), "def main() -> i64:\n    return 8\n");
    const shared_root = try join(a, &.{ xdg, "mylang", "runtime" });
    try buildOnly(context, .{ .tools = resolved, .source = "m.my", .output = "prog", .cwd = first, .environment = &child });
    const after_first = try entries(context, shared_root);
    try std.testing.expectEqual(@as(usize, 1), after_first.len);
    try std.testing.expectEqual(@as(usize, 64), after_first[0].len);
    const marker = try join(a, &.{ shared_root, after_first[0], "reuse marker" });
    try context.write(marker, "kept");
    try buildOnly(context, .{ .tools = resolved, .source = "m.my", .output = "prog", .cwd = second, .environment = &child });
    try std.testing.expectEqual(@as(usize, 1), (try entries(context, shared_root)).len);
    try std.testing.expectEqualStrings("kept", try context.read(marker));
}

// `content_hash` is the build-time identity every materialized runtime tree and
// installed runtime archive is named by. It must be the digest of exactly the
// bytes `assets.zig` embeds. Twice a cached configure phase broke that: once
// when its directory dependency watched only names, and once when two trees
// shared one Zig cache. Each time a runtime edit left the old `content_hash`
// beside freshly copied `@embedFile` bytes, and a later build could resolve an
// archive under the old identity. Recompute the canonical manifest from the
// embedded bytes; the encoding deliberately mirrors `manifest`/`digest` in
// `build_qbe_assets.zig` (the build script cannot be imported here). Keep them
// in step.
// spec-case: QBE-3
test "bundled content hash digests exactly the embedded runtime bytes" {
    var text: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer text.deinit();
    for (bundled.files) |asset| {
        text.writer.print("{s}\x00{d}\x00{x}\n", .{
            asset.path,
            asset.bytes.len,
            std.hash.Wyhash.hash(0, asset.bytes),
        }) catch return error.OutOfMemory;
    }
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(text.written(), &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(bundled.content_hash, &hex);
}

// The embedded runtime must be this tree's runtime, not a copy another tree or an
// older configuration chose: every bundled file equals `src/<path>` on disk now.
// With the digest test above, the installed compiler's `content_hash` names the
// bytes a `mylang build` from this checkout should link. The test runs from the
// build root, as every `zig build` step here does.
// spec: QBE-RUNTIME-IDENTITY-1
test "the bundled runtime is byte for byte this tree's runtime sources" {
    const a = std.testing.allocator;
    for (bundled.files) |asset| {
        const path = try std.fs.path.join(a, &.{ "src", asset.path });
        defer a.free(path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
        defer a.free(bytes);
        try std.testing.expectEqualStrings(bytes, asset.bytes);
    }
    try std.testing.expect(bundled.files.len > 0);
}

/// True when the generated compiler identity names `path`.
fn identityNames(path: []const u8) bool {
    for (bundled.identity_inputs) |input| {
        if (std.mem.eql(u8, input, path)) return true;
    }
    return false;
}

// `compiler_identity` names every production source input, the toolchain and the
// optimize mode. A test-only edit must not invalidate the production compiler, so
// the generated list omits test roots and their helpers while still naming the
// compiler and runtime inputs that a real edit must invalidate.
test "compiler identity omits test-only sources and names production inputs" {
    try std.testing.expect(identityNames("main.zig"));
    try std.testing.expect(identityNames("compiler.zig"));
    try std.testing.expect(identityNames("sema.zig"));
    try std.testing.expect(identityNames("qbe_build.zig"));
    try std.testing.expect(identityNames("native_format.zig"));
    try std.testing.expect(!identityNames("root_test.zig"));
    try std.testing.expect(!identityNames("compiler_test.zig"));
    try std.testing.expect(!identityNames("qbe_build_test.zig"));
    try std.testing.expect(!identityNames("byte_io/tests.zig"));
    try std.testing.expect(!identityNames("test_support.zig"));
}

/// True when the generated native-driver identity names `path`.
fn driverNames(path: []const u8) bool {
    for (bundled.driver_inputs) |input| {
        if (std.mem.eql(u8, input, path)) return true;
    }
    return false;
}

// `driver_identity` covers only what decides how already-emitted QBE IL becomes an
// object or an executable: the native build driver and the link-argument policy.
// A frontend or checker edit moves `compiler_identity` alone, so every cached
// object and guest executable whose IL is unchanged survives it.
// spec-case: QBE-DRIVER-IDENTITY-1
test "the native driver identity names the build driver and link policy only" {
    try std.testing.expect(driverNames("qbe_build.zig"));
    try std.testing.expect(driverNames("qbe_build_cache.zig"));
    try std.testing.expect(driverNames("qbe_build_io.zig"));
    try std.testing.expect(driverNames("qbe_build_outputs.zig"));
    try std.testing.expect(driverNames("native_link.zig"));
    // The frame-map annotator rewrites every unit's assembly, so it decides object bytes too.
    try std.testing.expect(driverNames("qbe_frame_map.zig"));
    try std.testing.expect(!driverNames("qbe_frame_map_test.zig"));
    try std.testing.expect(!driverNames("qbe_build_test.zig"));
    try std.testing.expect(!driverNames("sema.zig"));
    try std.testing.expect(!driverNames("parser.zig"));
    try std.testing.expect(!driverNames("main.zig"));
    try std.testing.expect(!driverNames("compiler.zig"));
    try std.testing.expect(!driverNames("native_format.zig"));
    try std.testing.expect(bundled.driver_inputs.len < bundled.identity_inputs.len);
}

const argv_program =
    \\def main(args: list[str], fs: Filesystem, out: Stream) -> int:
    \\    out.print(len(args))
    \\    if len(args) == 0:
    \\        return 0
    \\    if args[0] == "trap":
    \\        empty: list[int] = []
    \\        return empty[0]
    \\    if args[0] == "file":
    \\        match fs.read_file(args[1]):
    \\            case Ok(data):
    \\                return len(data)
    \\            case Err(_):
    \\                return 23
    \\    return 7
    \\
;

fn argvRun(context: fs.Context, command: []const []const u8, environment: *std.process.Environ.Map, expected: u8, output: []const u8) !void {
    const result = try std.process.run(context.allocator, context.io, .{ .argv = command, .environ_map = environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = expected }, result.term);
    try std.testing.expectEqualStrings(output, result.stdout);
    const marker = "MYLANG_RC_COUNTS ";
    const marker_at = std.mem.indexOf(u8, result.stderr, marker);
    try std.testing.expect(marker_at != null);
    const start = marker_at.?;
    const rest = result.stderr[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, rest[0..end], .{});
    const counts = parsed.value;
    const allocated = v.number(v.get(counts, "heap_allocate"));
    try std.testing.expect(!v.boolean(v.get(counts, "saturated")));
    try std.testing.expectEqual(allocated, v.number(v.get(counts, "retire")));
    try std.testing.expectEqual(allocated + v.number(v.get(counts, "owner_acquire")), v.number(v.get(counts, "owner_release")));
    try std.testing.expectEqual(v.number(v.get(counts, "hold_acquire")), v.number(v.get(counts, "hold_release")));
}

fn argvLifecycle(allocator: std.mem.Allocator) !usize {
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    const contract = @import("runtime_contract");
    try environment.put(contract.variable, contract.Selection.rc_counting.identity());
    try environment.put(runtime_options_variable, "");
    var context = try fs.Context.init(allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "argv.my" });
    const binary = try join(a, &.{ root, "argv" });
    try context.write(source, argv_program);
    try buildOnly(context, .{ .tools = try tools(a), .source = source, .output = binary, .cache = try join(a, &.{ root, "cache" }), .environment = &environment });
    try argvRun(context, &.{binary}, &environment, 0, "0\n");
    try argvRun(context, &.{ binary, "return" }, &environment, 7, "1\n");
    try argvRun(context, &.{ binary, "trap" }, &environment, 1, "1\n");
    try argvRun(context, &.{ binary, "file", try join(a, &.{ root, "absent" }) }, &environment, 23, "2\n");
    const many = try a.alloc([]const u8, 258);
    many[0] = binary;
    @memset(many[1..], "héllo");
    try argvRun(context, many, &environment, 7, "257\n");
    try environment.put(runtime_options_variable, "--restrict");
    try argvRun(context, &.{ binary, "return" }, &environment, 2, "");
    return 6;
}

// spec-case: RC-ARGV-OWNERSHIP-1
test "native RC argv owner balances borrowed entry returns capability refusal and traps" {
    try std.testing.expectEqual(@as(usize, 6), try argvLifecycle(std.testing.allocator));
}

const closed_field_program =
    \\record Holder:
    \\    items: list[int]
    \\def grow(items: mut list[int], amount: int, index: int):
    \\    i = 0
    \\    while i < amount:
    \\        items.append(i)
    \\        i += 1
    \\    assert items[index] == 1
    \\def change(holder: mut Holder, amount: int, index: int):
    \\    work = holder.items
    \\    grow(mut work, amount, index)
    \\    holder.items = work
    \\def heap_case(out: Stream, amount: int, index: int):
    \\    holder = Holder([1])
    \\    saved = holder
    \\    out.print(len(saved.items))
    \\    change(mut holder, amount, index)
    \\    out.print(len(holder.items))
    \\    assert saved.items == [1]
    \\def arena_case(out: Stream):
    \\    with arena():
    \\        holder = Holder([1])
    \\        saved = holder
    \\        out.print(len(saved.items))
    \\        change(mut holder, 1, 100)
    \\        assert saved.items == [1]
    \\def main(args: list[str], out: Stream) -> int:
    \\    if len(args) == 0:
    \\        heap_case(out, 1, 0)
    \\    elif args[0] == "trap":
    \\        heap_case(out, 1, 100)
    \\    elif args[0] == "arena":
    \\        arena_case(out)
    \\    else:
    \\        heap_case(out, 1000000, 0)
    \\    return 0
;

fn closedFieldLifecycle(allocator: std.mem.Allocator) !usize {
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    try environment.put(counting_contract.variable, counting_contract.Selection.rc_counting.identity());
    try environment.put(runtime_options_variable, "");
    try environment.put(memory_limit_variable, "128M");
    var context = try fs.Context.init(allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "field.my" });
    const binary = try join(a, &.{ root, "field" });
    try context.write(source, closed_field_program);
    try buildOnly(context, .{ .tools = try tools(a), .source = source, .output = binary, .cache = try join(a, &.{ root, "cache" }), .environment = &environment });
    try argvRun(context, &.{binary}, &environment, 0, "1\n2\n");
    try argvRun(context, &.{ binary, "trap" }, &environment, 1, "1\n");
    try argvRun(context, &.{ binary, "arena" }, &environment, 1, "1\n");
    try environment.put(memory_limit_variable, "1M");
    try argvRun(context, &.{ binary, "budget" }, &environment, 1, "1\n");
    return 4;
}

// spec-case: RC-CLOSED-FIELD-TRANSFER-1
test "native RC closed field owner balances storeback snapshot traps and arena refusal" {
    try std.testing.expectEqual(@as(usize, 4), try closedFieldLifecycle(std.testing.allocator));
}

const record_transfer_program =
    \\record Rt:
    \\    objects: list[int]
    \\    names: dict[str, int]
    \\    last: Option[list[int]]
    \\record It:
    \\    rt: Rt
    \\    tag: str
    \\def grow(rt: mut Rt, amount: int, index: int):
    \\    i = 0
    \\    while i < amount:
    \\        rt.objects.append(i)
    \\        i += 1
    \\    rt.names["k"] = amount
    \\    rt.last = Some([amount])
    \\    assert rt.objects[index] >= 0
    \\def change(it: mut It, amount: int, index: int):
    \\    wb = it.rt
    \\    grow(mut wb, amount, index)
    \\    it.rt = wb
    \\def owned_case(out: Stream, amount: int, index: int):
    \\    it = It(Rt([1], {}, None), "t")
    \\    saved = it
    \\    i = 0
    \\    while i < 3:
    \\        wb = it.rt
    \\        grow(mut wb, amount, index)
    \\        it.rt = wb
    \\        i += 1
    \\    out.print(len(it.rt.objects))
    \\    assert saved.rt.objects == [1]
    \\def caller_case(out: Stream, amount: int, index: int):
    \\    it = It(Rt([1], {}, None), "t")
    \\    saved = it
    \\    change(mut it, amount, index)
    \\    out.print(len(it.rt.objects))
    \\    assert saved.rt.objects == [1] and saved.rt.last is None
    \\def arena_case(out: Stream):
    \\    with arena():
    \\        it = It(Rt([1], {}, None), "t")
    \\        saved = it
    \\        out.print(len(saved.rt.objects))
    \\        change(mut it, 1, 100)
    \\def main(args: list[str], out: Stream) -> int:
    \\    if len(args) == 0:
    \\        owned_case(out, 1, 0)
    \\        caller_case(out, 1, 0)
    \\    elif args[0] == "trap-owned":
    \\        owned_case(out, 1, 100)
    \\    elif args[0] == "trap-caller":
    \\        caller_case(out, 1, 100)
    \\    elif args[0] == "arena":
    \\        arena_case(out)
    \\    else:
    \\        owned_case(out, 1000000, 0)
    \\    return 0
;

fn recordTransferLifecycle(allocator: std.mem.Allocator) !usize {
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    try environment.put(counting_contract.variable, counting_contract.Selection.rc_counting.identity());
    try environment.put(runtime_options_variable, "");
    try environment.put(memory_limit_variable, "128M");
    var context = try fs.Context.init(allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "record.my" });
    const binary = try join(a, &.{ root, "record" });
    try context.write(source, record_transfer_program);
    try buildOnly(context, .{ .tools = try tools(a), .source = source, .output = binary, .cache = try join(a, &.{ root, "cache" }), .environment = &environment });
    try argvRun(context, &.{binary}, &environment, 0, "4\n2\n");
    try argvRun(context, &.{ binary, "trap-owned" }, &environment, 1, "");
    try argvRun(context, &.{ binary, "trap-caller" }, &environment, 1, "");
    try argvRun(context, &.{ binary, "arena" }, &environment, 1, "1\n");
    try environment.put(memory_limit_variable, "1M");
    try argvRun(context, &.{ binary, "budget" }, &environment, 1, "");
    return 5;
}

// spec-case: RC-CLOSED-FIELD-TRANSFER-2
test "native RC record field transfers balance owned and caller traps, arenas and budgets" {
    try std.testing.expectEqual(@as(usize, 5), try recordTransferLifecycle(std.testing.allocator));
}

const sites_program =
    \\record Node:
    \\    value: int
    \\    children: list[Node]
    \\def build(depth: int) -> Node:
    \\    kids: list[Node] = []
    \\    if depth > 0:
    \\        kids.append(build(depth - 1))
    \\        kids.append(build(depth - 1))
    \\    return Node(depth, kids)
    \\def total(node: Node) -> int:
    \\    sum = node.value
    \\    for child in node.children:
    \\        sum += total(child)
    \\    return sum
    \\def main(args: list[str], out: Stream) -> int:
    \\    tree = build(4)
    \\    out.print(total(tree))
    \\    if len(args) != 0:
    \\        empty: list[int] = []
    \\        return empty[0]
    \\    return 0
;

/// Run a sites build once and check its report: the JSON file parses, its
/// sites' counts add up to the program's `MYLANG_RC_COUNTS` totals event by
/// event, and the list allocation in `build` is one site at its source line.
fn sitesRun(context: fs.Context, command: []const []const u8, environment: *std.process.Environ.Map, expected: u8, report: []const u8) !void {
    const result = try std.process.run(context.allocator, context.io, .{ .argv = command, .environ_map = environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = expected }, result.term);
    try std.testing.expectEqualStrings("26\n", result.stdout);
    const marker = "MYLANG_RC_COUNTS ";
    const start = std.mem.indexOf(u8, result.stderr, marker).? + marker.len;
    const end = std.mem.indexOfScalarPos(u8, result.stderr, start, '\n').?;
    const counts = try std.json.parseFromSlice(std.json.Value, context.allocator, result.stderr[start..end], .{});
    try std.testing.expectEqualStrings("rc-v4-sites", v.text(v.get(counts.value, "runtime")));
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "\nMYLANG_RC_SITES {\"version\":1,") != null);
    const parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, try context.read(report), .{});
    const sites = v.array(v.get(parsed.value, "sites"));
    var list_site: ?std.json.Value = null;
    for (sites) |site| {
        if (!std.mem.eql(u8, v.text(v.get(site, "operation")), "myl_native_list_new")) continue;
        if (std.mem.eql(u8, v.text(v.get(site, "function")), "build")) list_site = site;
    }
    const found = list_site.?;
    try std.testing.expectEqual(@as(u64, 5), v.number(v.get(found, "line")));
    try std.testing.expectEqualStrings("Node", v.text(v.get(found, "type")));
    const events = [_][]const u8{ "owner_acquire", "owner_release", "hold_acquire", "hold_release", "heap_allocate", "retire", "clone_shell", "unique_check" };
    try std.testing.expectEqual(@as(u64, 31), v.number(v.get(v.get(found, "counts"), events[4])));
    for (events) |event| {
        var sum: u64 = 0;
        for (sites) |site| {
            const count = v.get(site, "counts").object.get(event) orelse continue;
            sum += @intCast(count.integer);
        }
        try std.testing.expectEqual(v.number(v.get(counts.value, event)), sum);
    }
}

fn sitesLifecycle(allocator: std.mem.Allocator) !usize {
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    try environment.put(counting_contract.variable, counting_contract.Selection.rc_sites.identity());
    try environment.put(runtime_options_variable, "");
    var context = try fs.Context.init(allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try join(a, &.{ root, "sites.my" });
    const binary = try join(a, &.{ root, "sites" });
    const report = try join(a, &.{ root, "sites.json" });
    try context.write(source, sites_program);
    try buildOnly(context, .{ .tools = try tools(a), .source = source, .output = binary, .cache = try join(a, &.{ root, "cache" }), .environment = &environment });
    try environment.put("MYLANG_RC_SITES", report);
    try sitesRun(context, &.{binary}, &environment, 0, report);
    // A trap unwinds the frames it leaves; their drops still land in sites.
    try sitesRun(context, &.{ binary, "trap" }, &environment, 1, report);
    return 2;
}

// spec-case: RC-SITES-1
test "native RC sites build attributes every counted event to a source site" {
    try std.testing.expectEqual(@as(usize, 2), try sitesLifecycle(std.testing.allocator));
}

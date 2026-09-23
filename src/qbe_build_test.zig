//! Focused native build-driver and adapter tests, independent of interpreter suites.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const bundled = @import("qbe_build_assets");

test {
    _ = @import("qbe_build.zig");
    _ = @import("runtime_options.zig");
    _ = @import("qbe_build_cache.zig");
    _ = @import("qbe_build_io.zig");
    _ = @import("qbe_build_options.zig");
    _ = @import("qbe_build_outputs.zig");
    _ = @import("qbe_build_host.zig");
    _ = @import("qbe_build_embed.zig");
    _ = @import("qbe_build_shapes.zig");
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

/// Build with `--report`, then run the program, returning the facts the
/// installed-runtime scenario asserts on.
fn buildAndRun(context: fs.Context, spec: Spec) !BuildReport {
    const stdout = try spawnOk(context, try buildArgv(context, spec, true), cwdOf(spec), spec.environment);
    const parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, stdout, .{ .allocate = .alloc_always });
    // A built program reads its runtime options from the environment, never
    // from its own arguments.
    var reporting = if (spec.environment) |environment| try environment.clone(context.allocator) else try std.process.Environ.createMap(std.testing.environ, context.allocator);
    try reporting.put("MYLANG_OPTIONS", "--print-result");
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
    try std.testing.expectEqual(@as(usize, 2), shaped.archives);
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
// bytes `assets.zig` embeds: a warm `.zig-cache` once reused a configure phase
// whose directory dependency only watched for added/removed/renamed names, so
// an in-place runtime edit left the old `content_hash` beside freshly copied
// `@embedFile` bytes and a later build could resolve an archive under the old
// identity. Recompute the canonical manifest from the embedded bytes; the
// encoding deliberately mirrors `manifest`/`digest` in `build_qbe_assets.zig`
// (the build script cannot be imported here). Keep them in step.
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
    try std.testing.expect(!driverNames("qbe_build_test.zig"));
    try std.testing.expect(!driverNames("sema.zig"));
    try std.testing.expect(!driverNames("parser.zig"));
    try std.testing.expect(!driverNames("main.zig"));
    try std.testing.expect(!driverNames("compiler.zig"));
    try std.testing.expect(!driverNames("native_format.zig"));
    try std.testing.expect(bundled.driver_inputs.len < bundled.identity_inputs.len);
}

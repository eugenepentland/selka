//! Counting builds (`--counters`, NEW-CORE-COUNTERS-1..4): the counts a program
//! records, the counting runtime's insertions, and that a build without the flag
//! emits no counter.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const driver = @import("driver.zig");
const count_runtime = @import("count_runtime.zig");
const emit_count = @import("emit_count.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");
const passes = @import("passes.zig");
const pipeline = @import("pipeline.zig");
const build = @import("build.zig");
const report = std.debug.print;

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// What one run of `test/core/counters.my` printed and the counters it wrote.
const Counted = struct { stdout: []const u8, stderr: []const u8, status: u8, counts: std.json.Value };

/// Build `test/core/counters.my` with `flags` and run it with `arguments`, its
/// counters written to `<root>/<label>.json`.
fn counted(a: std.mem.Allocator, root: []const u8, flags: []const []const u8, arguments: []const []const u8) !Counted {
    const source = try std.fmt.allocPrint(a, "{s}/counters.my", .{options.fixtures});
    const label = try std.fmt.allocPrint(a, "run{d}{d}", .{ flags.len, arguments.len });
    const binary = try std.fs.path.join(a, &.{ root, label });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", binary, "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("counting build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_COUNTERS", path);
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(a, binary);
    try run_argv.appendSlice(a, arguments);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    const status: u8 = if (ran.term == .exited) ran.term.exited else 255;
    const text = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)) catch "null";
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = status, .counts = counts };
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

/// The sum of `name` over the sites of `kind` whose detail is `detail` and whose
/// emitting function is `function`.
fn sites(counts: std.json.Value, kind: []const u8, detail: []const u8, function: []const u8, name: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("detail").?.string, detail)) continue;
        if (!std.mem.eql(u8, object.get("function").?.string, function)) continue;
        total += object.get(name).?.integer;
    }
    return total;
}

fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn calls(counts: std.json.Value, function: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return row.object.get("calls").?.integer;
    }
    return -1;
}

// spec: NEW-CORE-COUNTERS-1
test "a counting build records copies, count updates, uniqueness tests and memory, and prints what an ordinary build prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const plain = try counted(a, root, &.{}, &.{});
    const debug = try counted(a, root, &.{"--counters"}, &.{});
    try std.testing.expectEqualStrings("100 101 4\n", plain.stdout);
    try std.testing.expectEqualStrings(plain.stdout, debug.stdout);
    try std.testing.expectEqualStrings(plain.stderr, debug.stderr);
    try std.testing.expectEqual(plain.status, debug.status);
    try std.testing.expectEqualStrings("mylang-counters-v1", debug.counts.object.get("version").?.string);
    // `ys = xs; ys.append(5)` copies the hundred elements of `xs` once.
    try std.testing.expectEqual(@as(i64, 1), field(debug.counts, &.{ "kinds", "list_copy", "count" }));
    try std.testing.expectEqual(@as(i64, 800), field(debug.counts, &.{ "kinds", "list_copy", "bytes" }));
    try std.testing.expectEqual(@as(i64, 800), field(debug.counts, &.{ "totals", "list_copy_bytes" }));
    // `bump` copies its 40-byte record out of the list, before the field store, and back in.
    try std.testing.expectEqual(@as(i64, 10), calls(debug.counts, "bump"));
    try std.testing.expectEqual(@as(i64, 400), sites(debug.counts, "record_copy", "list_get", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 400), sites(debug.counts, "record_copy", "list_set", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 400), sites(debug.counts, "record_copy", "list_set.old", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 10), sites(debug.counts, "unique_test", "is_unique", "bump", "count"));
    try std.testing.expectEqual(@as(i64, 10), sites(debug.counts, "unique_test", "is_unique", "bump", "extra"));
    try std.testing.expectEqual(@as(i64, 121), sites(debug.counts, "list_push", "list_push", "main", "count"));
    try std.testing.expect(field(debug.counts, &.{ "kinds", "retain", "count" }) >= 10);
    try std.testing.expect(field(debug.counts, &.{ "totals", "list_grows" }) > 0);
    try std.testing.expectEqual(field(debug.counts, &.{ "totals", "allocs" }), field(debug.counts, &.{ "totals", "frees" }));
    try std.testing.expectEqual(@as(i64, 0), field(debug.counts, &.{ "totals", "live_bytes_at_exit" }));
    try std.testing.expect(field(debug.counts, &.{ "totals", "peak_live_bytes" }) >= 800);
    // A release build counts the same copy; a trap still writes the counts.
    const release = try counted(a, root, &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, release.stdout);
    try std.testing.expectEqual(@as(i64, 800), field(release.counts, &.{ "kinds", "list_copy", "bytes" }));
    const trapped = try counted(a, root, &.{"--counters"}, &.{"trap"});
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "R_LIST_BOUNDS"));
    try std.testing.expectEqual(@as(i64, 800), field(trapped.counts, &.{ "kinds", "list_copy", "bytes" }));
}

// spec: NEW-CORE-COUNTERS-2
test "the counting runtime inserts every hook once into the unchanged runtime source and refuses a runtime that moved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const counting = try count_runtime.source(a, driver.runtime_source);
    try std.testing.expect(std.mem.startsWith(u8, counting, driver.runtime_source[0..64]));
    try std.testing.expect(std.mem.endsWith(u8, counting, count_runtime.body));
    try std.testing.expect(!contains(driver.runtime_source, "myl_count_"));
    try std.testing.expectEqual(driver.runtime_source.len + count_runtime.inserted + 1 + count_runtime.body.len, counting.len);
    try std.testing.expect(contains(counting, "    myl_count_dump();\n    leak_report();\n"));
    try std.testing.expectError(error.AnchorMissing, count_runtime.source(a, "int main(void) { return 0; }\n"));
    const doubled = try std.mem.concat(a, u8, &.{ driver.runtime_source, driver.runtime_source });
    try std.testing.expectError(error.AnchorMissing, count_runtime.source(a, doubled));
    // The runtime's site kind names are `emit_count.Kind`'s, in order.
    var expected: std.ArrayList(u8) = .empty;
    inline for (@typeInfo(emit_count.Kind).@"enum".field_names, 0..) |kind, i| try expected.print(a, "{s}\"{s}\"", .{ if (i == 0) "" else ", ", kind });
    const listed = std.mem.collapseRepeats(u8, try std.mem.replaceOwned(u8, a, kindList(count_runtime.body), "\n    ", " "), ' ');
    try std.testing.expectEqualStrings(expected.items, std.mem.trim(u8, listed, " ,"));
}

/// The initializer of `myl_count_kinds` in core_count.c.
fn kindList(body: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, body, "myl_count_kinds[] = {").? + "myl_count_kinds[] = {".len;
    const end = std.mem.indexOfPos(u8, body, start, "};").?;
    return std.mem.trim(u8, body[start..end], " \n");
}

// spec: NEW-CORE-COUNTERS-3
test "without --counters the emitted text names no counter and links the ordinary runtime; with it every function is counted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program =
        \\def twice(xs: list[int]) -> list[int]:
        \\    ys = xs
        \\    ys.append(1)
        \\    return ys
        \\def main(out: Stream) -> int:
        \\    out.print(len(twice([1, 2])))
        \\    return 0
    ;
    const plain = try support.llvmText(a, program);
    try std.testing.expect(!contains(plain, "myl_count"));
    try std.testing.expect(!contains(plain, "myl.cs."));
    try std.testing.expect(!emit_units.unit("whole", "", .program, plain).counting);
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    const result = try passes.debug(a, &module);
    const context: u8 = 0;
    const counting = try emit_llvm.emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = firstLine },
        .source_path = "counters.my",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
        .counters = true,
    });
    try std.testing.expect(emit_units.unit("whole", "", .program, counting).counting);
    try std.testing.expect(contains(counting, "section \"myl_count_fns\""));
    try std.testing.expect(contains(counting, "section \"myl_count_sites\""));
    try std.testing.expect(contains(counting, "@llvm.used = appending global"));
    try std.testing.expect(contains(counting, ", ptr @myl_count_copy_site, align 8\n"));
    try std.testing.expect(contains(counting, emit_count.epilogue));
    try std.testing.expect(contains(counting, "call ptr @myl_core_list_new_slow(i64 %cap, i64 %size)\n  ret ptr %made"));
    try std.testing.expectEqual(std.mem.count(u8, counting, "%myl.cnt.saved = load ptr"), std.mem.count(u8, counting, "section \"myl_count_fns\""));
}

// spec: NEW-CORE-COUNTERS-4
test "--counters is a build and run flag given once, and part of the build's replay key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cli_args = @import("cli_args.zig");
    var failure: cli_args.Failure = .usage;
    const built = try cli_args.parse(a, .build, &.{ "p.my", "-o", "p", "--counters" }, "zig", &failure);
    try std.testing.expect(built.build.show.codegen.counters);
    const ran = try cli_args.parse(a, .run, &.{ "p.my", "--counters", "--release" }, "zig", &failure);
    try std.testing.expect(ran.build.show.codegen.counters and ran.build.release);
    try std.testing.expectError(error.Usage, cli_args.parse(a, .build, &.{ "p.my", "-o", "p", "--counters", "--counters" }, "zig", &failure));
    const plain = try cli_args.parse(a, .build, &.{ "p.my", "-o", "p" }, "zig", &failure);
    try std.testing.expect(!plain.build.show.codegen.counters);
    const default: pipeline.Codegen = .{};
    try std.testing.expect(!default.counters);
}

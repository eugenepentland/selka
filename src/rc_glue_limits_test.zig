//! Execute the compiler's generated ownership glue at the active count limit.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const t = std.testing;
const runtime = @import("runtime_mode.zig");
const fixture_path = "test/fixtures/native-rc/glue-limit.c";

fn exercise() !bool {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "glue_limit.my",
        \\record Pair:
        \\    left: list[int]
        \\    right: list[int]
        \\union Choice:
        \\    none,
        \\    pair: Pair
        \\record Nested:
        \\    pair: Pair
        \\    choice: Result[bytes, int]
        \\    array: [2]bytes
        \\    wide: [17]bytes
        \\    plain: [10000]int
        \\    nested: [1][1]Result[bytes, int]
        \\record Node:
        \\    next: Option[Node]
        \\    label: bytes
        \\record Raw:
        \\    file: File
        \\def main() -> int:
        \\    pair = Pair([1], [2])
        \\    return len(pair.left)
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    const manifest = try std.json.parseFromSlice(struct { runtime_data: []const u8 }, t.allocator, text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    var catalog = try native.Catalog.initRecords(t.allocator, compilation.program.?.records);
    defer catalog.deinit();
    const fixture = try std.Io.Dir.cwd().readFileAlloc(t.io, fixture_path, t.allocator, .unlimited);
    defer t.allocator.free(fixture);
    var harness: []const u8 = fixture;
    var replacements: std.ArrayList([]const u8) = .empty;
    defer {
        for (replacements.items) |replacement| t.allocator.free(replacement);
        replacements.deinit(t.allocator);
    }
    inline for (.{ "Pair", "Choice" }, .{ "PAIR_SYMBOL", "CHOICE_SYMBOL" }) |record, marker| {
        const symbol = try recordSymbol(&catalog, record);
        defer t.allocator.free(symbol);
        harness = try std.mem.replaceOwned(u8, t.allocator, harness, marker, symbol);
        try replacements.append(t.allocator, harness);
    }
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "glue.c", .data = manifest.value.runtime_data });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "harness.c", .data = harness });
    try copyRuntime(temporary.dir);
    return compileRun(temporary.dir);
}

fn recordSymbol(catalog: *native.Catalog, name: []const u8) ![]const u8 {
    for (catalog.records) |record| if (std.mem.eql(u8, record.name, name)) return descriptors.symbol(t.allocator, catalog, record.id);
    return error.TestUnexpectedResult;
}

fn copyRuntime(directory: std.Io.Dir) !void {
    for (@import("qbe_build_assets").files) |asset| {
        if (std.mem.indexOfScalar(u8, asset.path, '/') != null) continue;
        try directory.writeFile(t.io, .{ .sub_path = asset.path, .data = asset.bytes });
    }
}

fn compileRun(directory: std.Io.Dir) !bool {
    const sources = &.{
        "native_heap.c",        "native_arena.c",     "native_collections.c", "native_text.c",
        "native_dictionary.c",  "native_equal.c",     "native_bytes.c",       "native_rc.c",
        "native_rc_stats.c",    "native_rc_shapes.c", "native_rc_walk.c",     "native_rc_scope.c",
        "native_rc_transfer.c", "native_rc_alloc.c",  "native_rc_values.c",   "native_regions.c",
    };
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(t.allocator);
    try argv.appendSlice(t.allocator, &.{
        @import("native_test_options").zig_path, "cc",              "-std=c11",          "-Werror",           "-O1",                "-fsanitize=undefined",
        "-ffunction-sections",                   "-fdata-sections", "-Wl,--gc-sections", "-DMYL_NATIVE_RC=1", "-DMYL_RC_CHECKED=1", "-DMYL_RC_GLUE_CHECKED=1",
    });
    try argv.appendSlice(t.allocator, sources);
    try argv.appendSlice(t.allocator, &.{ "harness.c", "-o", "harness" });
    const build = try std.process.run(t.allocator, t.io, .{ .argv = argv.items, .cwd = .{ .dir = directory } });
    defer t.allocator.free(build.stdout);
    defer t.allocator.free(build.stderr);
    if (build.term != .exited or build.term.exited != 0) {
        try std.Io.File.stderr().writeStreamingAll(t.io, build.stderr);
        return false;
    }
    const run = try std.process.run(t.allocator, t.io, .{ .argv = &.{"./harness"}, .cwd = .{ .dir = directory } });
    defer t.allocator.free(run.stdout);
    defer t.allocator.free(run.stderr);
    try std.Io.File.stderr().writeStreamingAll(t.io, run.stderr);
    return run.term == .exited and run.term.exited == 0;
}

// spec-case: RC-COUNTS-1
// spec-case: RC-LAYOUT-1
// spec-case: RC-STARTUP-IMAGE-1
// spec: RC-ACQUIRE-COPY-1
test "generated acquisition admission preserves aliased O and H counts, inactive arms, arenas and staged moves" {
    try t.expect(try exercise());
}

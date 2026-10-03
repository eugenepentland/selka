//! Execute the emitted tagged-case branches against real checked generated glue.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const shapes = @import("rc_shape.zig");
const runtime = @import("runtime_mode.zig");
const glue = @import("qbe_rc_glue.zig");
const t = std.testing;
const fixture_path = "test/fixtures/native-rc/variant-native.c";
/// Probe emission needs native layouts and a schema with its declared Choice.
pub const ProbeError = glue.Error || error{TestUnexpectedResult};
const schema =
    \\record Pair:
    \\    left: list[int]
    \\    right: list[int]
    \\union Choice:
    \\    empty,
    \\    pair: Pair,
    \\    number: int,
    \\    held: DictValues[int, int]
    \\def main() -> int:
    \\    return 0
;

const State = struct { catalog: shapes.Catalog };
const Cow = struct { rc: ?*State };
const Emitter = struct {
    native_variants: @import("runtime_contract").native_variants.Policy = .qbe_v2,
    layouts: *native.Catalog,
    cow: ?*Cow,
    output: std.Io.Writer.Allocating,
    next: usize = 3,

    /// Reserve a fresh temporary after the function's three input names.
    pub fn temp(self: *Emitter) usize {
        defer self.next += 1;
        return self.next;
    }

    /// Append actual ownership-emitter instructions to the probe module.
    pub fn print(self: *Emitter, comptime format: []const u8, args: anytype) glue.Error!void {
        self.output.writer.print(format, args) catch return error.OutOfMemory;
    }

    /// Route slow calls through counters that delegate to real generated glue.
    pub fn descriptor(_: *Emitter, _: @import("typed.zig").Type) glue.Error![]const u8 {
        return "probe";
    }
};

fn choice(catalog: *native.Catalog) !@import("typed.zig").Type {
    for (catalog.records) |item| if (std.mem.eql(u8, item.name, "Choice")) return item.id;
    return error.TestUnexpectedResult;
}

/// Emit both uncertified and certified take probes against the same real layout.
pub fn wrappers(catalog: *native.Catalog) ProbeError![]const u8 {
    var state: State = .{ .catalog = try shapes.Catalog.init(t.allocator, catalog) };
    defer state.catalog.deinit();
    var cow: Cow = .{ .rc = &state };
    var emitter: Emitter = .{ .layouts = catalog, .cow = &cow, .output = .init(t.allocator) };
    defer emitter.output.deinit();
    const ty = try choice(catalog);
    try emitter.print("export function w $fast_take(l %heap, l %ctx, l %v0, l %v1, w %v2) {{\n@start\n", .{});
    try glue.take(Emitter, &emitter, .{ .ty = ty, .destination = 0, .source = 1, .region = 2 });
    try emitter.print(" ret 1\n@failure\n ret 0\n}}\n", .{});
    try emitter.print("export function w $fast_take_private(l %heap, l %ctx, l %v0, l %v1, w %v2) {{\n@start\n", .{});
    try glue.take(Emitter, &emitter, .{ .ty = ty, .destination = 0, .source = 1, .region = 2, .disjoint = true });
    try emitter.print(" ret 1\n@failure\n ret 0\n}}\n", .{});
    try emitter.print("export function $fast_drop(l %heap, l %v0) {{\n@start\n", .{});
    try glue.drop(Emitter, &emitter, .{ .ty = ty, .address = 0 });
    try emitter.print(" ret\n}}\nexport function $fast_unloan(l %heap, l %v0) {{\n@start\n", .{});
    try glue.unloan(Emitter, &emitter, .{ .ty = ty, .address = 0 });
    try emitter.print(" ret\n}}\n", .{});
    return t.allocator.dupe(u8, emitter.output.written());
}

fn assets(directory: std.Io.Dir) !void {
    for (@import("qbe_build_assets").files) |asset| {
        if (std.mem.indexOfScalar(u8, asset.path, '/') != null) continue;
        try directory.writeFile(t.io, .{ .sub_path = asset.path, .data = asset.bytes });
    }
}

fn command(directory: std.Io.Dir, argv: []const []const u8) !void {
    const outcome = try std.process.run(t.allocator, t.io, .{ .argv = argv, .cwd = .{ .dir = directory } });
    defer t.allocator.free(outcome.stdout);
    defer t.allocator.free(outcome.stderr);
    if (outcome.term != .exited or outcome.term.exited != 0)
        try std.Io.File.stderr().writeStreamingAll(t.io, outcome.stderr);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
}

fn compileRun(directory: std.Io.Dir) !void {
    const qbe = t.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    try command(directory, &.{ qbe, "-o", "probe.s", "probe.ssa" });
    const zig = @import("native_test_options").zig_path;
    try command(directory, &.{ zig, "cc", "-c", "probe.s", "-o", "probe.o" });
    const sources = &.{
        "native_heap.c",        "native_arena.c",     "native_collections.c", "native_text.c",
        "native_dictionary.c",  "native_equal.c",     "native_bytes.c",       "native_rc.c",
        "native_rc_stats.c",    "native_rc_shapes.c", "native_rc_walk.c",     "native_rc_scope.c",
        "native_rc_transfer.c", "native_rc_alloc.c",  "native_rc_values.c",   "native_regions.c",
    };
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(t.allocator);
    try argv.appendSlice(t.allocator, &.{
        zig,                   "cc",              "-std=c11",          "-Werror",           "-O1",                "-fsanitize=undefined",
        "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections", "-DMYL_NATIVE_RC=1", "-DMYL_RC_CHECKED=1", "-DMYL_RC_GLUE_CHECKED=1",
        "-UNDEBUG",
    });
    try argv.appendSlice(t.allocator, sources);
    try argv.appendSlice(t.allocator, &.{ "harness.c", "probe.o", "-o", "harness" });
    try command(directory, argv.items);
    try command(directory, &.{"./harness"});
}

// spec-case: RC-NATIVE-VARIANT-1
test "RC-NATIVE-VARIANT-1 emitted native tags region overlap and pending-death protocol match checked glue" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "variant_native.my", schema);
    defer compilation.deinit();
    const manifest_text = try compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = .qbe_v2 });
    defer t.allocator.free(manifest_text);
    const manifest = try std.json.parseFromSlice(struct { runtime_data: []const u8 }, t.allocator, manifest_text, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    var catalog = try native.Catalog.initRecords(t.allocator, compilation.program.?.records);
    defer catalog.deinit();
    const il = try wrappers(&catalog);
    defer t.allocator.free(il);
    const symbol = try descriptors.symbol(t.allocator, &catalog, try choice(&catalog));
    defer t.allocator.free(symbol);
    const fixture = try std.Io.Dir.cwd().readFileAlloc(t.io, fixture_path, t.allocator, .unlimited);
    defer t.allocator.free(fixture);
    const harness = try std.mem.replaceOwned(u8, t.allocator, fixture, "CHOICE_SYMBOL", symbol);
    defer t.allocator.free(harness);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try assets(directory.dir);
    try directory.dir.writeFile(t.io, .{ .sub_path = "glue.c", .data = manifest.value.runtime_data });
    try directory.dir.writeFile(t.io, .{ .sub_path = "harness.c", .data = harness });
    try directory.dir.writeFile(t.io, .{ .sub_path = "probe.ssa", .data = il });
    try compileRun(directory.dir);
}

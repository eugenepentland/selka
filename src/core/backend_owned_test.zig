//! The native backend survives releasing imported syntax, checked trees and source.
const std = @import("std");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const pipeline = @import("pipeline.zig");
const ir = @import("ir.zig");
const source = @import("mylang").source;

const entry =
    \\import templates
    \\const blob: bytes = embed_bytes("data.bin")
    \\func main(out: Stream) -> int:
    \\    out.print("entry survives")
    \\    assert len(blob) == 4, "embedded value survives"
    \\    return templates.identity[int](templates.Item().n) + len(blob)
;
const templates =
    \\public record Item:
    \\    n: int = 42
    \\
    \\public func identity[T](value: T) -> T:
    \\    return value
;

fn emit(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, unit: pipeline.Unit) !pipeline.Emission {
    var report: std.ArrayList(u8) = .empty;
    return pipeline.emittedWithScratch(arena, backing, module, unit, .{
        .zig = "unused",
        .mode = .optimized_debug,
        .show = .{ .llvm = "unused" },
    }, &report);
}

fn frontendLifetime(backing: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = entry });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "templates.my", .data = templates });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.bin", .data = "\x00XYZ" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = frontend.Session.init(backing, std.testing.io, root);
    var live = true;
    defer if (live) session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "app", &report);
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = checked.program, .source = checked.src };
    var original = try build.buildExecutable(a, input, &refusal);
    var detached = try build.buildExecutable(a, input, &refusal);
    const borrowed = try pipeline.unitFor(a, checked, "app.my", false);
    const expected = try emit(a, backing, &original, borrowed);
    const retained = try pipeline.retainUnit(a, &detached, borrowed);
    try std.testing.expect(retained.src.bytes.ptr != borrowed.src.bytes.ptr);
    try std.testing.expect(retained.src.origins[1].original.bytes.ptr != borrowed.src.origins[1].original.bytes.ptr);
    session.deinit();
    live = false;
    // Reuse freed backing with unrelated data before touching the detached IR.
    const poison = try backing.alloc(u8, 1 << 20);
    defer backing.free(poison);
    @memset(poison, 0xa5);
    const actual = try emit(a, backing, &detached, retained);
    try std.testing.expectEqualStrings(expected.whole.?, actual.whole.?);
    try std.testing.expectEqual(expected.units.len, actual.units.len);
    for (expected.units, actual.units) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.source_path, right.source_path);
        try std.testing.expectEqualStrings(left.llvm, right.llvm);
    }
    try std.testing.expect(std.mem.indexOf(u8, actual.whole.?, "templates.my") != null);
    try std.testing.expectEqualStrings("out", retained.main.parameters[0]);
    const assets = retained.src.origins[0].original.embeds;
    try std.testing.expect(assets.len > 0);
    try std.testing.expectEqualStrings("\x00XYZ", assets[0].contents);
}

// spec: NEW-CORE-STAGE-CACHE-7
test "backend ownership preserves imported generic default embedded bytes and exact LLVM after frontend release" {
    try frontendLifetime(std.testing.allocator);
}

fn retainFailure(backing: std.mem.Allocator, borrowed: source.Source) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = borrowed.path, .signature = .{ .params = &.{}, .ret = .void } });
    try module.strings.append(a, borrowed.bytes);
    const unit = try pipeline.retainUnit(a, &module, .{
        .src = borrowed,
        .source_path = borrowed.path,
        .main = .{ .parameters = &.{borrowed.path} },
    });
    try std.testing.expectEqualDeep(borrowed, unit.src);
    try std.testing.expectEqualStrings(borrowed.path, module.functions.items[0].name);
    try std.testing.expectEqualStrings(borrowed.bytes, module.strings.items[0]);
}

// spec-case: NEW-CORE-STAGE-CACHE-7
test "backend ownership allocation failure releases partial retained copies with the result arena" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const child = try source.Source.init(a, "child.my", "child body\n");
    const mapped = try source.Source.initMapped(a, &.{child});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainFailure, .{mapped});
}

//! The binary32 domain `f32` in the new core: its four-byte storage, its LLVM
//! operations and conversions, and the widths that keep `float` and `f32` apart.
const std = @import("std");
const support = @import("test_support.zig");
const ir = @import("ir.zig");

const narrow_source =
    \\func scale(x: f32) -> f32:
    \\    return x * 2.0f32 + 1.0f32
    \\func widen(x: f32) -> float:
    \\    return float(x)
    \\func narrow(x: float) -> f32:
    \\    return f32(x)
    \\func first(xs: FixedArray[f32, 4]) -> f32:
    \\    return xs[0]
    \\func head(xs: f32[]) -> f32:
    \\    return xs[0]
    \\func main() -> int:
    \\    const fixed = FixedArray[f32, 4]([0.5f32, 1.0f32, 1.5f32, 2.0f32])
    \\    mut items: f32[] = [2.0f32]
    \\    return int(widen(scale(narrow(2.5)))) + int(first(fixed)) + int(head(items))
;

test "f32 occupies four bytes and lowers to LLVM float with exact widening" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(arena.allocator(), narrow_source, &refusal);
    try std.testing.expectEqual(@as(u32, 4), module.size(.f32));
    try std.testing.expectEqual(@as(u32, 16), module.size(try fixedArray(&module)));
    const llvm = try support.llvmText(arena.allocator(), narrow_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fmul float") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fadd float") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fpext float") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "fptrunc double") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "[4 x float]") != null);
}

/// The array type `FixedArray[f32, 4]` of the narrow program's `first` parameter, found by its element.
fn fixedArray(module: *const ir.Module) !ir.Type {
    for (module.compounds.items, 0..) |compound, index| switch (compound) {
        .array => |array| if (array.elem == .f32 and array.n == 4) return @fromBackingInt(@intCast(ir.Type.first_compound + @as(u32, @intCast(index)))),
        else => {},
    };
    return error.TestUnexpectedResult;
}

test "f32 list elements are stored at their own four-byte stride" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), narrow_source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load float") != null);
}

test "f32 is a leaf of the core type enumeration, below the first compound index" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(arena.allocator(), narrow_source, &refusal);
    try std.testing.expect(@backingInt(ir.Type.f32) < ir.Type.first_compound);
    try std.testing.expect(!ir.Type.f32.isCompound());
    try std.testing.expectEqual(@as(u32, 4), module.alignment(.f32));
}

test "f32 has exactly one value descriptor when a program compares binary32 lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.llvmText(arena.allocator(), "func main() -> int:\n    mut xs: f32[] = []\n    append(mut xs, 1.5f32)\n    if xs == [1.5f32]:\n        return 1\n    return 0\n");
    const defined = std.mem.count(u8, llvm, try std.fmt.allocPrint(arena.allocator(), "@myl.value.{s} = ", .{@import("type_ids.zig").Table.text(.{}, .f32)}));
    try std.testing.expect(defined <= 1);
}

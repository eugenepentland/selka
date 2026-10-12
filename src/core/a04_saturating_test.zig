//! Saturating helper admission is scalar and its generated ABI is width bounded.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const zero = @import("zero_rc.zig");

// spec-case: NEW-CORE-S3-NUMERIC-1
test "A04 saturation admits only the exact scalar helper" {
    const contract = zero.contract("myl_core_saturating_integer") orelse return error.TestUnexpectedResult;
    try std.testing.expect(contract.result == .scalar);
    try std.testing.expectEqual(@as(u64, 0), contract.owned);
    try std.testing.expectEqual(@as(u64, 0), contract.views);
    for ([_][]const u8{ "myl_core_saturating_integer_extra", "myl_core_saturating", "myl_core_saturating_integer_" }) |name| try std.testing.expect(zero.contract(name) == null);
}

fn source(a: std.mem.Allocator, ty: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a,
        \\func difference(left: {s}, right: {s}) -> {s}:
        \\    return saturating_sub(left, right)
        \\func product(left: {s}, right: {s}) -> {s}:
        \\    return saturating_mul(left, right)
        \\func main() -> int:
        \\    return int(difference(0{s}, 0{s})) + int(product(0{s}, 0{s}))
    , .{ ty, ty, ty, ty, ty, ty, ty, ty, ty, ty });
}

fn signature(function: ir.Function) !void {
    try std.testing.expect(function.signature.linkage == .extern_c);
    try std.testing.expectEqualSlices(ir.Type, &.{ .u64, .u64, .u32, .u32 }, function.signature.params);
    try std.testing.expect(function.signature.ret == .u64);
    try std.testing.expectEqual(@as(u64, 0), function.signature.owned);
}

// spec-case: NEW-CORE-S3-NUMERIC-1
test "A04 saturation generates exact scalar signatures and bounded widths and modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]ir.Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 }) |ty| {
        var unit = try language.Compilation.init(a, "saturation.my", try source(a, @tagName(ty)));
        try unit.check();
        var refusal: build.Refusal = .{};
        const module = try build.buildExecutable(a, .{ .program = unit.program.?, .zero_rc = true, .single_owner = true }, &refusal);
        var calls: usize = 0;
        for (module.functions.items) |function| {
            for (function.insts.items) |inst| {
                if (inst.op != .call) continue;
                const declaration = module.functions.items[inst.a.index()];
                if (!std.mem.eql(u8, declaration.name, "myl_core_saturating_integer")) continue;
                try signature(declaration);
                const operands = function.operands(inst.data);
                try std.testing.expectEqual(@as(usize, 4), operands.len);
                const width = function.inst(operands[2]);
                const mode = function.inst(operands[3]);
                try std.testing.expect(width.op == .iconst and mode.op == .iconst);
                try std.testing.expectEqual(@as(u64, ty.integer().?.bits), width.data);
                const signed: u64 = @intFromBool(ty.integer().?.signed);
                const operation: u64 = if (std.mem.eql(u8, function.name, "product")) 2 else 0;
                try std.testing.expectEqual(signed | operation, mode.data);
                calls += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 2), calls);
    }
}

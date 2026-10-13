//! Compact internal transport leaves logical mut-result tuples unchanged.
const std = @import("std");
const support = @import("test_support.zig");

const source =
    \\record Big:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\    f: int
    \\func step(mut big: Big, mut scalar: int, n: int) -> int:
    \\    big.a += n
    \\    scalar += 1
    \\    return big.a + scalar
    \\func main(out: Stream) -> int:
    \\    mut big = Big(a=1, b=2, c=3, d=4, e=5, f=6)
    \\    mut scalar = 10
    \\    out.print(step(mut big, mut scalar, 4), big.a, scalar)
    \\    return 0
;

test "compact internal sret transports declared result and scalar final without the in-out field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const debug = try support.llvmText(a, source);
    const verified = try support.verifyLlvmText(a, source);
    for ([_][]const u8{ debug, verified }) |llvm| {
        try std.testing.expect(std.mem.indexOf(u8, llvm, "@\"my.step\"(ptr noalias sret([16 x i8]) align 8 %ret, ptr noalias align 8 %p0") != null);
        try std.testing.expect(std.mem.indexOf(u8, llvm, "call fastcc void @\"my.step\"(ptr sret([16 x i8])") != null);
    }
}

test "compact internal sret aligns narrow results before scalar and managed finals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source_narrow = @embedFile("compact_sret_narrow.my");
    const debug = try support.llvmText(a, source_narrow);
    const verified = try support.verifyLlvmText(a, source_narrow);
    for ([_][]const u8{ debug, verified }) |llvm| {
        for ([_][]const u8{ "bool_step", "byte_step", "word_step", "dword_step" }) |name| {
            const definition = try std.fmt.allocPrint(a, "@\"my.{s}\"(ptr noalias sret([16 x i8]) align 8 %ret", .{name});
            const start = std.mem.indexOf(u8, llvm, definition).?;
            const end = std.mem.indexOfPos(u8, llvm, start, "\n}").?;
            const body = llvm[start..end];
            try std.testing.expect(std.mem.indexOf(u8, body, "getelementptr inbounds i8, ptr %ret, i64 8") != null);
        }
    }
}

fn mixedWholeModule(a: std.mem.Allocator, checked: bool) !@import("ir.zig").Module {
    const ir = @import("ir.zig");
    const Hand = support.Hand;
    var module: ir.Module = .{ .zero_rc = checked };
    try module.strings.append(a, "managed");
    const wide = try module.intern(a, .{ .record = &.{ .i64, .i64, .i64, .i64, .i64, .i64 } });
    const tuple = try module.intern(a, .{ .record = &.{ .bool, wide, .u8, .i64, .str } });
    const list = try module.intern(a, .{ .list = tuple });
    var target = try Hand.init(a, &module, "mixed", .{ .params = try a.dupe(ir.Type, &.{ wide, .u8, .i64, .str }), .ret = tuple, .owned = 15 });
    const first = try target.emit(.{ .op = .record_get, .ty = .i64, .a = try target.param(0), .data = 0 });
    const sum = try target.emit(.{ .op = .add, .ty = .i64, .a = first, .b = try target.int(.i64, 7), .check = .exact });
    const updated = try target.emit(.{ .op = .record_set, .ty = wide, .a = try target.param(0), .b = sum, .data = 0 });
    const final = try target.emit(.{ .op = .record_make, .ty = tuple, .data = try target.extra(&.{ try target.int(.bool, 1), updated, try target.param(1), try target.param(2), try target.param(3) }) });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = final });
    _ = try target.finish();
    module.entry = 1;
    var main = try Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const one = try main.int(.i64, 1);
    const initial = try main.emit(.{ .op = .record_make, .ty = wide, .data = try main.extra(&.{ one, one, one, one, one, one }) });
    const text = try main.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    const called = try main.emit(.{ .op = .call, .ty = tuple, .a = @fromBackingInt(0), .data = try main.extra(&.{ initial, try main.int(.u8, 251), try main.int(.i64, 123), text }) });
    const empty = try main.emit(.{ .op = .list_new, .ty = list, .a = try main.int(.u64, 1) });
    const pushed = try main.emit(.{ .op = .list_push, .ty = list, .a = empty, .b = called });
    const element = try main.emit(.{ .op = .list_get, .ty = tuple, .a = pushed, .b = try main.int(.i64, 0), .check = .exact });
    const inner = try main.emit(.{ .op = .record_get, .ty = wide, .a = element, .data = 1 });
    const first_after = try main.emit(.{ .op = .record_get, .ty = .i64, .a = inner, .data = 0 });
    const flag = try main.emit(.{ .op = .record_get, .ty = .bool, .a = element, .data = 0 });
    const byte = try main.emit(.{ .op = .record_get, .ty = .u8, .a = element, .data = 2 });
    const scalar = try main.emit(.{ .op = .record_get, .ty = .i64, .a = element, .data = 3 });
    const managed = try main.emit(.{ .op = .record_get, .ty = .str, .a = element, .data = 4 });
    try main.printValues(try main.param(0), &.{ flag, first_after, byte, scalar, managed });
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    _ = try main.finish();
    return module;
}

test "compact internal sret reconstructs mixed narrow scalar and managed whole tuples leak-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |checked| {
        for ([_]bool{ false, true }) |release| {
            var module = try mixedWholeModule(a, checked);
            const result = try support.runOwned(a, &module, .{ .release = release });
            try std.testing.expectEqual(@as(u8, 0), result.status);
            try std.testing.expectEqualStrings("True 8 251 123 managed\n", result.stdout);
            try std.testing.expectEqualStrings("", result.stderr);
            try std.testing.expect(std.mem.indexOf(u8, result.llvm, "@\"my.mixed\"(ptr noalias sret([24 x i8])") != null);
        }
    }
}

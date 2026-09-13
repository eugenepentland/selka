//! Text-sized byte literals share array semantics through checking and VM execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const program = "fn first<T:copy>(x:T)->T{return x;}fn main()->i64{let a=first::<[4]u8>(\"A\\x00\\xffB\");return cast<i64>(a[0])+cast<i64>(a[2])+cast<i64>(len(\"µ\"));}";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "bytes.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 322), (try c.execute(allocator)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 322), (try again.execute(allocator)).value);
}
// spec: BYTE-LITERAL-1
test "byte literals preserve arbitrary bytes UTF8 lengths generic arrays and formatting" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "byte literals reject invalid escapes and retain ordinary array type checks" {
    const Case = struct { text: []const u8, code: []const u8 };
    for ([_]Case{
        .{ .text = "fn main()->i64{return len(\"\\q\");}", .code = "E_BYTE_ESCAPE" },
        .{ .text = "fn main()->i64{return len(\"\\x+f\");}", .code = "E_BYTE_ESCAPE" },
        .{ .text = "fn main()->i64{return len(\"\\x0\");}", .code = "E_BYTE_ESCAPE" },
        .{ .text = "fn main()->i64{return len(\"x\n\");}", .code = "E_BYTE_LITERAL" },
        .{ .text = "fn f()->[1]u8{return \"ab\";}fn main()->i64{return 0;}", .code = "E_TYPE" },
    }) |case| {
        var c = try language.Compilation.init(t.allocator, "bad-byte.my", case.text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings(case.code, c.diagnostics.items[0].code);
    }
}

test "byte literal decoded size limit reports E_BYTE_LITERAL_LIMIT before lowering" {
    const text = try t.allocator.alloc(u8, 65536 + 1 + 40);
    defer t.allocator.free(text);
    const prefix = "fn main()->i64{return len(\"";
    @memcpy(text[0..prefix.len], prefix);
    @memset(text[prefix.len..][0..65537], 'a');
    const suffix = "\");}";
    @memcpy(text[prefix.len + 65537 ..][0..suffix.len], suffix);
    var c = try language.Compilation.init(t.allocator, "large.my", text[0 .. prefix.len + 65537 + suffix.len]);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_BYTE_LITERAL_LIMIT", c.diagnostics.items[0].code);
}

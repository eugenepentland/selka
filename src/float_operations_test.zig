//! Binary64 bit patterns have specified NaNs, signed zeros, conversions and rounding.
const std = @import("std");
const t = std.testing;
const floats = @import("floats.zig");
const language = @import("compiler.zig");
fn binary(op: @import("typed.zig").BinaryOp, a: f64, b: f64) !u64 {
    return @intCast((try floats.binary(op, @bitCast(a), @bitCast(b))).integer.value);
}
// spec: FLOAT-DOMAIN-1
test "binary64 IEEE boundaries canonical NaNs signed zero and FloatConversion" {
    try t.expectEqual(@as(u64, 0), try binary(.f64_add, -0.0, 0.0));
    try t.expectEqual(@as(u64, 0x8000000000000000), try binary(.f64_mul, -0.0, 1.0));
    try t.expectEqual(@as(u64, 0x7ff0000000000000), try binary(.f64_div, 1.0, 0.0));
    try t.expectEqual(floats.canonical_nan, try binary(.f64_div, 0.0, 0.0));
    try t.expectEqual(floats.canonical_nan, try floats.unary(.f64_sqrt, @bitCast(@as(f64, -1.0))));
    try t.expectEqual(@as(u64, 1), try binary(.f64_mul, @bitCast(@as(u64, 2)), 0.5));
    try t.expectEqual(@as(u64, @bitCast(@as(f64, 1.0))), try binary(.f64_add, 1.0, 0x1p-53));
    try t.expect((try floats.binary(.f64_eq, 0, 0x8000000000000000)).bool);
    try t.expect(!(try floats.binary(.f64_eq, floats.canonical_nan, floats.canonical_nan)).bool);
    try t.expectError(error.FloatConversion, floats.unary(.f64_to_u64, 0x7ff0000000000000));
    try t.expectError(error.FloatConversion, floats.unary(.f64_to_u64, @bitCast(@as(f64, 18446744073709551616.0))));
    try t.expectEqual(@as(u64, 0), try floats.unary(.f64_to_u64, @bitCast(@as(f64, -0.75))));
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "module main;import std_math as m;" ++
        "fn main()->i64{let a=m::sqrt(m::from_i64(1764));" ++
        "if !m::eq(m::neg(m::from_i64(0)),m::from_i64(0)){return 1;}" ++
        "let limit=m::from_i64(-9223372036854775808);" ++
        "match m::to_i64(limit){m::Signed.ok(n)=>{if n != -9223372036854775808{return 2;}},m::Signed.err(e)=>{return e;}}" ++
        "match m::to_i64(a){m::Signed.ok(n)=>{return n;},m::Signed.err(e)=>{return e;}}}");
}
fn scenario(allocator: std.mem.Allocator) !void {
    var program: language.embedded_project.Program = undefined;
    try program.init(allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    const result = try language.vm.run(allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 42), result.value);
}
test "std_math nominal F64 operations and signed conversions clean allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "float intrinsics evaluate constants and reject Bool or signed raw operands" {
    var good = try language.Compilation.init(t.allocator, "float.my", "const V:u64=f64_to_u64(f64_sqrt(f64_from_u64(1764u64)));fn main()->i64{return cast<i64>(V);}");
    defer good.deinit();
    try t.expectEqual(@as(i64, 42), (try good.execute(t.allocator)).value);
    var bad = try language.Compilation.init(t.allocator, "float.my", "fn main()->i64{return f64_sqrt(1);}");
    defer bad.deinit();
    try t.expectError(error.SourceError, bad.check());
    try t.expectEqualStrings("E_TYPE", bad.diagnostics.items[0].code);
}

test "std_math F64 codecs preserve noncanonical NaN representation exactly" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    const code = program.compilation.code.?;
    const codec = @import("codec_json.zig");
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    var found = false;
    for (code.records) |record| {
        if (!std.mem.endsWith(u8, record.name, "::F64")) continue;
        found = true;
        const bytes = try std.fmt.allocPrint(t.allocator, "{{\"version\":\"typed-json-v1\",\"type\":\"{s}\",\"value\":\"9218868437227405313\"}}", .{record.name});
        defer t.allocator.free(bytes);
        const value = try codec.decode(t.allocator, code, record.id, bytes, .{}, &failure);
        defer value.release(t.allocator);
        const encoded = try codec.encode(t.allocator, code, record.id, value, .{}, &failure);
        defer t.allocator.free(encoded);
        try t.expectEqualStrings(bytes, encoded);
    }
    try t.expect(found);
}

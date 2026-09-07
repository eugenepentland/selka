//! Plain JSON transport validation is independent of EDA schemas.
const std = @import("std");
const t = std.testing;
const document = @import("json_document.zig");
// spec: PLAIN-JSON-1
test "plain document distinguishes decoded strings integers fractions and missing sentinel" {
    const words = try document.parse(t.allocator, "{\"key\":[-9223372036854775808,1.0,true,false,null,\"é\\ud83d\\ude00\"]}");
    defer t.allocator.free(words);
    try t.expectEqual(@as(i64, 0), words[0]);
    try t.expectEqual(@as(i64, 1), words[6]);
    try t.expectEqual(@as(i64, 2), words[18]);
    try t.expectEqual(@as(i64, 6), words[22]);
    try t.expectEqual(std.math.minInt(i64), words[29]);
    try t.expectEqual(@as(i64, 5), words[30]);
    try t.expectEqual(@as(i64, 6), words[36]);
    try t.expectEqual(@as(i64, 7), words[42]);
    try t.expectEqual(@as(i64, 8), words[48]);
}
// spec: PLAIN-JSON-2
test "plain document rejects DuplicateField InvalidCharacter Overflow and excessive depth" {
    try t.expectError(error.DuplicateField, document.parse(t.allocator, "{\"x\":1,\"\\u0078\":2}"));
    try t.expectError(error.InvalidCharacter, document.parse(t.allocator, "\"\xff\""));
    try t.expectError(error.Overflow, document.parse(t.allocator, "9223372036854775808"));
    try t.expectError(error.InvalidNumber, document.parse(t.allocator, "1e309"));
    try t.expectError(error.SyntaxError, document.parse(t.allocator, "true false"));
    var deep: [131]u8 = undefined;
    @memset(deep[0..65], '[');
    deep[65] = '0';
    @memset(deep[66..], ']');
    try t.expectError(error.CodecDepthLimit, document.parse(t.allocator, &deep));
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    const words = try document.parse(allocator, "{\"left\":[1,2,3],\"right\":\"decoded\\ntext\"}");
    defer allocator.free(words);
}
// spec: PLAIN-JSON-3
test "plain document releases every partial tree and tape on allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

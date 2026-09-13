const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const Manifest = language.input_manifest.Manifest;
const valid = "{\"version\":1,\"module\":\"config.values\",\"values\":[{\"name\":\"limit\",\"type\":\"u64\",\"value\":\"18446744073709551615\"},{\"name\":\"enabled\",\"type\":\"bool\",\"value\":\"true\"}]}";
fn scenario(allocator: std.mem.Allocator) !void {
    var manifest = try Manifest.parse(allocator, valid);
    defer manifest.deinit();
    const generated = try manifest.generate(allocator);
    defer allocator.free(generated);
    var c = try language.Compilation.init(allocator, "config/values.my", generated);
    defer c.deinit();
    const formatted = try c.formatModule(allocator);
    defer allocator.free(formatted);
    try t.expectEqualStrings(generated, formatted);
    try t.expect(std.mem.indexOf(u8, generated, "return 18446744073709551615u64;") != null);
}
test "input manifests generate canonical syntax and release every failed allocation" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "input manifest parsing retains concrete malformed JSON errors" {
    const cases = .{
        .{ "{}", error.MissingField },
        .{ "{\"version\":1,\"version\":1,\"module\":\"m\",\"values\":[]}", error.DuplicateField },
        .{ "{\"extra\":0,\"version\":1,\"module\":\"m\",\"values\":[]}", error.UnknownField },
        .{ "{\"version\":\"invalid\",\"module\":\"m\",\"values\":[]}", error.InvalidCharacter },
        .{ "{\"version\":1.5,\"module\":\"m\",\"values\":[]}", error.InvalidNumber },
        .{ "{\"version\":4294967296,\"module\":\"m\",\"values\":[]}", error.Overflow },
        .{ "@", error.SyntaxError },
        .{ "{", error.UnexpectedEndOfInput },
        .{ "[]", error.UnexpectedToken },
    };
    inline for (cases) |case| try t.expectError(case[1], Manifest.parse(t.allocator, case[0]));
}
test "input manifests reject byte and entry count budgets before name validation" {
    const oversized = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(oversized);
    @memset(oversized, ' ');
    try t.expectError(error.ManifestTooLarge, Manifest.parse(t.allocator, oversized));
    const entries = try t.allocator.alloc(language.input_manifest.Entry, 1025);
    defer t.allocator.free(entries);
    @memset(entries, .{ .name = "same", .type = "i64", .value = "0" });
    const bytes = try std.json.Stringify.valueAlloc(t.allocator, language.input_manifest.Document{ .version = 1, .module = "m", .values = entries }, .{});
    defer t.allocator.free(bytes);
    try t.expectError(error.TooManyInputs, Manifest.parse(t.allocator, bytes));
}

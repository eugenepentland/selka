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
test "input manifest validation rejects duplicate names keywords types and noncanonical values" {
    for ([_][]const u8{
        "{\"name\":\"fn\",\"type\":\"i64\",\"value\":\"1\"}",
        "{\"name\":\"value\",\"type\":\"allocator\",\"value\":\"1\"}",
        "{\"name\":\"value\",\"type\":\"u8\",\"value\":\"256\"}",
        "{\"name\":\"value\",\"type\":\"bool\",\"value\":\"1\"}",
        "{\"name\":\"value\",\"type\":\"i64\",\"value\":\"-0\"}",
        "{\"name\":\"value\",\"type\":\"i64\",\"value\":\"01\"}",
        "{\"name\":\"value\",\"type\":\"i64\",\"value\":\"1;return 2\"}",
        "{\"name\":\"value\",\"type\":\"i64\",\"value\":\"1\"},{\"name\":\"value\",\"type\":\"i64\",\"value\":\"2\"}",
    }, [_]anyerror{ error.InvalidInputName, error.InvalidInputType, error.InputValueOutOfRange, error.InvalidInputValue, error.InvalidInputValue, error.InvalidInputValue, error.InvalidInputValue, error.DuplicateInputName }) |entry, expected| {
        const text = try std.fmt.allocPrint(t.allocator, "{{\"version\":1,\"module\":\"inputs\",\"values\":[{s}]}}", .{entry});
        defer t.allocator.free(text);
        try t.expectError(expected, Manifest.parse(t.allocator, text));
    }
    try t.expectError(error.InvalidInputModule, Manifest.parse(t.allocator, "{\"version\":1,\"module\":\"config.fn\",\"values\":[]}"));
    try t.expectError(error.UnsupportedInputVersion, Manifest.parse(t.allocator, "{\"version\":2,\"module\":\"config\",\"values\":[]}"));
}

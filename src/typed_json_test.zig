const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const codec = @import("typed_json.zig");
const typed = @import("typed.zig");
const Value = typed.Value;
const source = "enum Flag { yes, no } struct Point { x: u64, flags: [Flag]bool } union Choice { none, point: Point } result Outcome { ok: Choice, err: i8 } fn main() -> i64 { return 0; }";
const document = "{\"value\":{\"value\":{\"value\":{\"flags\":{\"no\":false,\"yes\":true},\"x\":\"18446744073709551615\"},\"case\":\"point\"},\"case\":\"ok\"},\"type\":\"Outcome\",\"version\":\"typed-json-v1\"}";
const canonical = "{\"version\":\"typed-json-v1\",\"type\":\"Outcome\",\"value\":{\"case\":\"ok\",\"value\":{\"case\":\"point\",\"value\":{\"x\":\"18446744073709551615\",\"flags\":{\"yes\":true,\"no\":false}}}}}";
fn find(records: []const typed.Record, name: []const u8) typed.Type {
    for (records) |record| if (std.mem.eql(u8, name, record.name)) return record.id;
    unreachable;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "codec.my", source);
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    const ty = find(records, "Outcome");
    var parsed = try codec.Document.parse(allocator, document, .{});
    // The materialized value must outlive all JSON parsing storage.
    const value = parsed.decode(allocator, records, ty) catch |err| {
        parsed.deinit();
        return err;
    };
    parsed.deinit();
    defer value.release(allocator);
    const point = value.aggregate.fields[0].aggregate.fields[0];
    try t.expectEqual(@as(i128, 18446744073709551615), try point.aggregate.fields[0].asInteger());
    try t.expect(point.aggregate.fields[1].aggregate.fields[0].bool);
    const output = try codec.encode(allocator, records, ty, value, .{});
    defer allocator.free(output);
    try t.expectEqualStrings(canonical, output);
}
test "typed JSON materializes nominal values independently and cleans up every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "typed JSON encodes independently constructed values without consuming ownership" {
    var compilation = try language.Compilation.init(t.allocator, "codec.my", "struct Pair { n: i16, ok: bool } fn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    const ty = find(records, "Pair");
    const value = try Value.create(t.allocator, ty, &.{ Value.number(.i16, -32768), .{ .bool = true } });
    defer value.release(t.allocator);
    const output = try codec.encode(t.allocator, records, ty, value, .{});
    defer t.allocator.free(output);
    try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"Pair\",\"value\":{\"n\":\"-32768\",\"ok\":true}}", output);
    try t.expectEqual(@as(usize, 1), value.aggregate.references);
    try t.expectError(error.CodecByteLimit, codec.encode(t.allocator, records, ty, value, .{ .max_bytes = output.len - 1 }));
    try t.expectError(error.CodecValueLimit, codec.encode(t.allocator, records, ty, value, .{ .max_values = 2 }));
    try t.expectError(error.CodecDepthLimit, codec.encode(t.allocator, records, ty, value, .{ .max_depth = 1 }));
    const boundary = try codec.encode(t.allocator, records, ty, value, .{ .max_bytes = output.len, .max_values = 3, .max_depth = 2 });
    defer t.allocator.free(boundary);
    try t.expectEqualStrings(output, boundary);
    var parsed = try codec.Document.parse(t.allocator, boundary, .{ .max_bytes = output.len, .max_values = 3, .max_depth = 2 });
    defer parsed.deinit();
    const decoded = try parsed.decode(t.allocator, records, ty);
    defer decoded.release(t.allocator);
}
test "typed JSON budgets bound raw syntax and typed materialization separately" {
    try t.expectError(error.CodecByteLimit, codec.Document.parse(t.allocator, document, .{ .max_bytes = document.len - 1 }));
    try t.expectError(error.CodecTokenLimit, codec.Document.parse(t.allocator, document, .{ .max_tokens = 1 }));
    try t.expectError(error.CodecDepthLimit, codec.Document.parse(t.allocator, document, .{ .max_depth = 1 }));
    try t.expectError(error.InvalidCodecLimits, codec.Document.parse(t.allocator, document, .{ .max_depth = 129 }));
    var compilation = try language.Compilation.init(t.allocator, "codec.my", source);
    defer compilation.deinit();
    try compilation.check();
    var parsed = try codec.Document.parse(t.allocator, document, .{ .max_values = 3 });
    defer parsed.deinit();
    try t.expectError(error.CodecValueLimit, parsed.decode(t.allocator, compilation.program.?.records, find(compilation.program.?.records, "Outcome")));
}
test "typed JSON rejects authority or private construction anywhere in the selected type graph" {
    var compilation = try language.Compilation.init(t.allocator, "codec.my", "domain D: i64 { fn make(x: i64) -> D { return wrap<D>(x); } } union Maybe { none, some: D } buffer B: i64; resource F: filesystem; pool P(H): i64; struct Wrapped { data: [0]D } fn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    for ([_][]const u8{ "D", "Maybe", "B", "F", "P", "H", "Wrapped" }) |name| try t.expectError(error.NoImplicitCodec, codec.checkType(t.allocator, records, find(records, name)));
    try t.expectError(error.NoImplicitCodec, codec.checkType(t.allocator, records, .allocator));
    try t.expectError(error.InvalidCodecType, codec.checkType(t.allocator, records, @fromBackingInt(999999)));
}
test "typed JSON rejects malformed host values before emitting bytes" {
    try t.expectError(error.InvalidCodecValue, codec.encode(t.allocator, &.{}, .bool, .{ .integer = .{ .ty = .bool, .value = 1 } }, .{}));
    try t.expectError(error.CodecIntegerOutOfRange, codec.encode(t.allocator, &.{}, .u8, .{ .integer = .{ .ty = .u8, .value = 256 } }, .{}));
    var compilation = try language.Compilation.init(t.allocator, "codec.my", source);
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    const ty = find(records, "Choice");
    const invalid = try Value.createVariant(t.allocator, ty, 99, null);
    defer invalid.release(t.allocator);
    try t.expectError(error.InvalidCodecValue, codec.encode(t.allocator, records, ty, invalid, .{}));
    const missing = try Value.createVariant(t.allocator, ty, 1, null);
    defer missing.release(t.allocator);
    try t.expectError(error.InvalidCodecValue, codec.encode(t.allocator, records, ty, missing, .{}));
}

test "typed JSON rejects later fields after releasing already decoded aggregates" {
    var compilation = try language.Compilation.init(t.allocator, "codec.my", "struct Inner { n: i64 } struct Outer { a: Inner, b: bool } fn main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    var parsed = try codec.Document.parse(t.allocator, "{\"version\":\"typed-json-v1\",\"type\":\"Outer\",\"value\":{\"a\":{\"n\":\"7\"},\"b\":\"wrong\"}}", .{});
    defer parsed.deinit();
    try t.expectError(error.ValueTypeMismatch, parsed.decode(t.allocator, records, find(records, "Outer")));
    try t.expectError(error.ValueTypeMismatch, parsed.decode(t.allocator, records, find(records, "Inner")));
}

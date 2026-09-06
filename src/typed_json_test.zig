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
    var location: codec.Location = .{};
    const value = parsed.decodeWithLocation(allocator, records, ty, &location) catch |err| {
        parsed.deinit();
        if (err == error.OutOfMemory) try t.expect(!location.has_path);
        return err;
    };
    parsed.deinit();
    defer value.release(allocator);
    const point = value.aggregate.fields[0].aggregate.fields[0];
    try t.expectEqual(@as(i128, 18446744073709551615), try point.aggregate.fields[0].asInteger());
    try t.expect(point.aggregate.fields[1].aggregate.fields[0].bool);
    const output = try codec.encodeWithLocation(allocator, records, ty, value, .{}, &location);
    try t.expect(!location.has_path);
    defer allocator.free(output);
    try t.expectEqualStrings(canonical, output);
}
test "typed JSON materializes nominal values independently and cleans up every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
// spec: WIRE-3
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
    var compilation = try language.Compilation.init(t.allocator, "codec.my", "domain D: i64 { fn make(x: i64) -> D { return wrap<D>(x); } } union Maybe { none, " ++
        "some: D } buffer B: i64; resource F: filesystem; pool P(H): i64; struct Wrapped { " ++
        "data: [0]D } fn main() -> i64 { return 0; }");
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

test "typed JSON failure locations survive document and checked catalog teardown" {
    var location: codec.Location = .{};
    {
        var compilation = try language.Compilation.init(t.allocator, "codec.my", source);
        defer compilation.deinit();
        try compilation.check();
        const records = compilation.program.?.records;
        const invalid = "{\"version\":\"typed-json-v1\",\"type\":\"Outcome\",\"value\":{\"case\":\"ok\",\"value\":{\"case\":\"point\",\"value\":{\"x\":\"7\",\"flags\":{\"yes\":true,\"no\":\"wrong\"}}}}}";
        var parsed = try codec.Document.parse(t.allocator, invalid, .{});
        defer parsed.deinit();
        try t.expectError(error.ValueTypeMismatch, parsed.decodeWithLocation(t.allocator, records, find(records, "Outcome"), &location));
    }
    try t.expect(location.has_path and !location.truncated);
    try t.expectEqualStrings("/value/value/value/flags/no", location.text());
    // Reusing a diagnostic cannot retain a stale path after success.
    const text = try codec.encodeWithLocation(t.allocator, &.{}, .bool, .{ .bool = true }, .{}, &location);
    defer t.allocator.free(text);
    try t.expect(!location.has_path);
}
test "typed JSON encoding locates malformed nested native values without consuming them" {
    var compilation = try language.Compilation.init(t.allocator, "codec.my", "struct R { values: [2]u8 } fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    const array = try Value.create(t.allocator, find(records, "[2]u8"), &.{ Value.number(.u8, 1), .{ .bool = false } });
    defer array.release(t.allocator);
    const value = try Value.create(t.allocator, find(records, "R"), &.{array});
    defer value.release(t.allocator);
    var location: codec.Location = .{};
    try t.expectError(error.ValueTypeMismatch, codec.encodeWithLocation(t.allocator, records, find(records, "R"), value, .{}, &location));
    try t.expectEqualStrings("/value/values/1", location.text());
    try t.expectEqual(@as(usize, 1), value.aggregate.references);
    try t.expectEqual(@as(usize, 2), array.aggregate.references);
}
test "typed JSON location escaping truncation and mutated limits remain bounded" {
    var location: codec.Location = .{};
    location.field("a/b~c");
    try t.expectEqualStrings("/a~1b~0c", location.text());
    const long: [5000]u8 = @splat('x');
    location.field(&long);
    try t.expect(location.truncated and location.len == 4096);
    var unicode_name: [5000]u8 = undefined;
    for (0..2500) |i| {
        unicode_name[i * 2] = 0xc3;
        unicode_name[i * 2 + 1] = 0xa9;
    }
    location.field(&unicode_name);
    try t.expect(location.truncated and std.unicode.utf8ValidateSlice(location.text()));
    var parsed = try codec.Document.parse(t.allocator, "{\"version\":\"typed-json-v1\",\"type\":\"bool\",\"value\":true}", .{});
    defer parsed.deinit();
    parsed.limits.max_depth = 129;
    try t.expectError(error.InvalidCodecLimits, parsed.decodeWithLocation(t.allocator, &.{}, .bool, &location));
    try t.expect(!location.has_path);
    try t.expectError(error.NoImplicitCodec, codec.encodeWithLocation(t.allocator, &.{}, .allocator, .{ .bool = false }, .{}, &location));
    try t.expectEqualStrings("/type", location.text());
}

test "typed JSON rejects incomplete unexpected and unknown wire fields with precise errors" {
    var c = try language.Compilation.init(t.allocator, "wire-errors.my", source);
    defer c.deinit();
    try c.check();
    const cases = .{
        .{ "i64", "\"01\"", error.InvalidCodecInteger },
        .{ "Point", "{}", error.IncompleteCodecValue },
        .{ "Point", "{\"x\":\"0\",\"flags\":{\"yes\":true,\"no\":false},\"extra\":true}", error.UnexpectedCodecField },
        .{ "Choice", "{\"case\":\"missing\"}", error.UnknownCodecCase },
    };
    inline for (cases) |case| {
        const bytes = try std.fmt.allocPrint(t.allocator, "{{\"version\":\"typed-json-v1\",\"type\":\"{s}\",\"value\":{s}}}", .{ case[0], case[1] });
        defer t.allocator.free(bytes);
        var parsed = try codec.Document.parse(t.allocator, bytes, .{});
        defer parsed.deinit();
        const ty = typed.Type.fromName(case[0]) orelse find(c.program.?.records, case[0]);
        try t.expectError(case[2], parsed.decode(t.allocator, c.program.?.records, ty));
    }
}
test "typed JSON rejects UnsupportedCodecVersion before materialization" {
    try t.expectError(error.UnsupportedCodecVersion, codec.Document.parse(t.allocator, "{\"version\":\"typed-json-v2\",\"type\":\"i64\",\"value\":\"0\"}", .{}));
}

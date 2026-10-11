//! Exact-width numeric transport and forged typed operand regressions.
const std = @import("std");
const source = @import("source.zig");
const typed = @import("typed.zig");
const numeric = @import("body_check_numeric_validate.zig");
const logical = @import("parser_value.zig");
const wire = @import("body_check_wire_io.zig");
const value = @import("body_check_value.zig");
const validate = @import("body_check_validate.zig");
const signature = "SLKNUM01";
const widths = [_]typed.Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 };

// spec: SELFHOST-BODY-NUMERIC-1
test "body numeric canonical full unsigned constants and IEEE bit payloads roundtrip" {
    const a = std.testing.allocator;
    const numbers = [_]i128{ std.math.minInt(i64), -1, 0, std.math.maxInt(i64), @as(i128, 1) << 63, std.math.maxInt(u64), 0xbff8000000000000, 0x8000000000000000 };
    for (numbers) |number| {
        const encoded = try wire.encode(a, i128, number, signature);
        defer a.free(encoded);
        try std.testing.expectEqual(@as(u8, if (number > std.math.maxInt(i64)) 8 else 1), encoded[16]);
        var decoded = try wire.decode(a, i128, encoded, signature);
        defer decoded.arena.deinit();
        try std.testing.expectEqual(number, decoded.value);
        if (number > std.math.maxInt(i64)) {
            try std.testing.expectError(error.ComponentProtocol, logical.encodeTree(a, i128, number, signature));
            try std.testing.expectError(error.ComponentProtocol, logical.decodeTree(i128, a, encoded, signature));
            try std.testing.expectError(error.ComponentProtocol, wire.decode(a, i64, encoded, signature));
            try std.testing.expectError(error.ComponentProtocol, wire.decode(a, usize, encoded, signature));
        }
    }
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric refuses noncanonical upper unsigned rows and out of language range" {
    const a = std.testing.allocator;
    const encoded = try wire.encode(a, i128, std.math.maxInt(u64), signature);
    defer a.free(encoded);
    std.mem.writeInt(i64, encoded[17..25], 7, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, i128, encoded, signature));
    std.mem.writeInt(i64, encoded[17..25], -1, .little);
    encoded[16] = 1;
    var signed = try wire.decode(a, i128, encoded, signature);
    defer signed.arena.deinit();
    try std.testing.expectEqual(@as(i128, -1), signed.value);
    try std.testing.expectError(error.ComponentProtocol, wire.encode(a, i128, @as(i128, std.math.maxInt(u64)) + 1, signature));
    try std.testing.expectError(error.ComponentProtocol, wire.encode(a, i128, @as(i128, std.math.minInt(i64)) - 1, signature));
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric constants conversions and operators retain exact integer widths" {
    for (widths) |ty| {
        try std.testing.expect(numeric.integer(ty, ty.min()));
        try std.testing.expect(numeric.integer(ty, ty.max()));
        try std.testing.expect(!numeric.integer(ty, ty.min() - 1));
        try std.testing.expect(!numeric.integer(ty, ty.max() + 1));
        try std.testing.expect(numeric.unary(.neg, ty, ty));
        for (widths) |target| try std.testing.expect(numeric.cast(target, ty));
        inline for (.{ .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .wrapping_add, .saturating_mul }) |op| {
            try std.testing.expect(numeric.binary(op, ty, ty));
            try std.testing.expect(!numeric.binary(op, .bool, ty));
        }
        try std.testing.expect(numeric.binary(.lt, .bool, ty));
        try std.testing.expect(!numeric.binary(.lt, ty, ty));
    }
    try std.testing.expect(!numeric.binary(.add, .bool, .bool));
    try std.testing.expect(!numeric.unary(.f64_to_i8, .i64, .u64));
    try std.testing.expect(numeric.unary(.f64_to_i8, .i8, .u64));
    try std.testing.expect(!numeric.unary(.f64_from_i64, .u64, .u64));
    try std.testing.expect(numeric.binary(.f64_eq, .bool, .u64));
    try std.testing.expect(!numeric.binary(.f64_eq, .u64, .u64));
}

const Fixture = struct { input: value.Input, output: value.Output };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    const src = try source.Source.init(a, "numeric.my", text);
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try parser.parse();
    const catalog = try @import("records.zig").collectWithNames(a, src, syntax, &sink, null);
    const input: value.Input = .{
        .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false },
        .program = syntax,
        .modules = &.{},
        .catalog = try @import("body_check_materialize.zig").project(a, catalog),
    };
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, &sink, null);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    const output: value.Output = .{ .batch = .{ .nodes = program.nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{} };
    return .{ .input = input, .output = output };
}
const authentic =
    \\func numeric(value: u64) -> int:
    \\    const narrow: i8 = -128i8
    \\    const maximum = 18446744073709551615u64
    \\    const real = -1.5
    \\    const converted = float(value)
    \\    return int(floor(converted / real)) + int(narrow) + int(maximum & 7u64)
    \\
;
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric authentic float promotion and high unsigned graphs retain owned clone parity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, authentic);
    try validate.outcome(a, f.input, .{ .success = f.output });
    const encoded = try wire.encode(a, value.Output, f.output, signature);
    var decoded = try wire.decode(a, value.Output, encoded, signature);
    try std.testing.expectEqualDeep(f.output, decoded.value);
    const clone = try value.cloneBatch(a, decoded.value.batch);
    decoded.arena.deinit();
    try std.testing.expectEqualDeep(f.output.batch, clone);
    try std.testing.expect(try value.equal(a, .{ .success = f.output }, .{ .success = .{ .batch = clone, .import_used = &.{}, .diagnostics = &.{} } }));
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric rejects foreign float domains and forged wrap operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, authentic);
    const rows = try a.dupe(typed.Node, f.output.batch.nodes);
    var forged = f.output;
    forged.batch.nodes = rows;
    try forgeWrap(rows);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
    try rejectForeignFloat(a, f.input.catalog);
}
fn forgeWrap(rows: []typed.Node) !void {
    var attacked = false;
    for (rows) |*node| if (node.data == .wrap) {
        rows[@backingInt(node.data.wrap)].ty = .bool;
        attacked = true;
        break;
    };
    try std.testing.expect(attacked);
}
fn rejectForeignFloat(a: std.mem.Allocator, original: value.Catalog) !void {
    for (original.records) |record| if (numeric.floating(original, record.id)) {
        const records = try a.dupe(typed.Record, original.records);
        records[record.id.recordIndex()].declaration = .{ .start = 1, .end = 2 };
        var catalog = original;
        catalog.records = records;
        try std.testing.expect(!numeric.floating(catalog, record.id));
    };
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric owned clone retains high bits and refuses beyond unsigned64" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nodes = [_]typed.Node{.{ .ty = .u64, .span = .{ .start = 0, .end = 0 }, .data = .{ .integer = std.math.maxInt(u64) } }};
    const batch: value.Batch = .{ .nodes = &nodes, .statements = &.{}, .functions = &.{}, .ranges = &.{} };
    const cloned = try value.cloneBatch(a, batch);
    try std.testing.expectEqualDeep(batch, cloned);
    nodes[0].data.integer += 1;
    try std.testing.expectError(error.ComponentProtocol, value.cloneBatch(a, batch));
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric schema rejects old frames while raw oversized literals preserve source diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, authentic);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(9));
    const reply = try protocol.response(a, .{ .success = f.output }, request.identity);
    std.mem.writeInt(u32, reply[12..16], 8, .little);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, reply, request.identity, f.input));
    try sourceFailure(a, "18446744073709551616u64", "integer literal does not fit its type; signed minimum magnitudes must be directly negated");
    try sourceFailure(a, "340282366920938463463374607431768211456", "integer literal magnitude is too large");
}
fn sourceFailure(a: std.mem.Allocator, spelling: []const u8, message: []const u8) !void {
    const text = try std.fmt.allocPrint(a, "func value() -> int:\n    return {s}\n", .{spelling});
    const src = try source.Source.init(a, "numeric.my", text);
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try parser.parse();
    const bytes = try logical.encode(a, syntax);
    var decoded = try logical.decode(a, bytes, text.len);
    defer decoded.deinit();
    try std.testing.expectError(error.SourceError, @import("sema.zig").checkLibraryProgram(a, src, decoded.program, &sink, null));
    try std.testing.expectEqual(@as(usize, 1), sink.items.items.len);
    const problem = sink.items.items[0];
    try std.testing.expectEqualStrings("E_INTEGER_RANGE", problem.code);
    try std.testing.expectEqualStrings(message, problem.message);
    const begin = std.mem.indexOf(u8, text, spelling).?;
    try std.testing.expectEqualDeep(source.Span{ .start = begin, .end = begin + spelling.len }, problem.span);
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric parsing binds canonical float Option and exact immutable receiver forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "text.parse_float()", "text[0:len(text)].parse_float()" }) |call| {
        const text = try std.fmt.allocPrint(a, "func value(text: str, prior: float?) -> int:\n    _ = prior\n    match {s}:\n        case Some(number):\n            return int(number)\n        case None:\n            return 0\n", .{call});
        const f = try fixture(a, text);
        try validate.outcome(a, f.input, .{ .success = f.output });
        const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
        var forged = f.output;
        forged.batch.nodes = nodes;
        var attacked = false;
        for (nodes) |*node| if (node.data == .buffer_operation) {
            const kind = node.data.buffer_operation.kind;
            if (kind == .parse_float or kind == .parse_float_range) {
                node.ty = .i64;
                attacked = true;
                break;
            }
        };
        try std.testing.expect(attacked);
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
    }
}
// spec-case: SELFHOST-BODY-NUMERIC-1
test "body numeric full unsigned32 constants do not relax Unicode array elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    const point: u32 = 4294967295u32\n    const text = \"x\"\n    return int(point) + len(text)\n");
    try validate.outcome(a, f.input, .{ .success = f.output });
    const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
    var forged = f.output;
    forged.batch.nodes = nodes;
    try forgeUnicode(nodes, f.input.catalog.string.?.id);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
}
fn forgeUnicode(nodes: []typed.Node, string: typed.Type) !void {
    var attacked = false;
    for (nodes) |node| if (node.ty == string and node.data == .array and node.data.array.len != 0) {
        const child = @backingInt(node.data.array[0]);
        nodes[child].data.integer = 0xd800;
        attacked = true;
        break;
    };
    try std.testing.expect(attacked);
}

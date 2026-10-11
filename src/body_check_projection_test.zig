//! The body boundary receives identities from the retained native type catalog.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const records = @import("records.zig");
const projection = @import("body_check_projection.zig");
const typed = @import("typed.zig");
const Fixture = struct { src: source.Source, program: @import("ast.zig").Program, catalog: records.Catalog };

fn fixture(a: std.mem.Allocator) !Fixture {
    const src = try source.Source.init(a, "managed-body.my", "func main() -> int:\n    return 0\n");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const program = try p.parse();
    return .{ .src = src, .program = program, .catalog = try records.collectWithNames(a, src, program, &sink, null) };
}

// spec: SELFHOST-BODY-MANAGED-1
test "body check projection snapshots authoritative managed prelude identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const input = try projection.input(a, f.src, f.program, null, true, f.catalog);
    try std.testing.expectEqual(f.catalog.names.get("str").?, input.catalog.string.?.id);
    try std.testing.expectEqual(f.catalog.names.get("bytes").?, input.catalog.bytes.?.id);
    try std.testing.expectEqual(typed.Type.u32, input.catalog.string.?.element);
    try std.testing.expectEqual(typed.Type.u8, input.catalog.bytes.?.element);
    try f.catalog.names.put(a, "bytes", .i64);
    const changed = try projection.input(a, f.src, f.program, null, true, f.catalog);
    try std.testing.expectEqual(@as(?@import("body_check_value.zig").Sequence, null), changed.catalog.bytes);
    try std.testing.expectEqual(input.catalog.string, changed.catalog.string);
    try std.testing.expect(input.catalog.bytes.?.id.isAggregate());
}

// spec-case: SELFHOST-BODY-MANAGED-1
test "body check projection refuses a mismatched managed representation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const copied = try a.dupe(typed.Record, f.catalog.records);
    copied[f.catalog.names.get("str").?.recordIndex()].shape.buffer = .u8;
    f.catalog.records = copied;
    const input = try projection.input(a, f.src, f.program, null, true, f.catalog);
    try std.testing.expectEqual(@as(?@import("body_check_value.zig").Sequence, null), input.catalog.string);
    try std.testing.expect(input.catalog.bytes != null);
}

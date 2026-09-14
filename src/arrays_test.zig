//! Fixed-array construction, index bounds, copy behavior, and malformed native/VM metadata tests.
const fixture_path = "arrays.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;

fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
fn trapped(source: []const u8, code: []const u8, span: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqualStrings(code, outcome.trap.code);
    try testing.expectEqualStrings(span, compilation.src.text(outcome.trap.span));
}

// spec: CORE-6
test "fixed arrays have structural types preserve copies and support every integer index width" {
    try result(
        \\def first(a: [2]i64) -> i64:
        \\    return a[0]
        \\
        \\
        \\def main() -> i64:
        \\    a: [02]i64 = [3, 4]
        \\    b = replace(a, 0, 8)
        \\    return first(a) + b[0] + b[1]
    , 15);
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(testing.allocator, "def main() -> i64:\n    a: [2]u8 = [7u8, 9u8]\n    return i64(a[1{s}])\n", .{width});
        defer testing.allocator.free(source);
        try result(source, 9);
    }
    try result(
        \\def empty(a: [0]bool) -> [0]bool:
        \\    return a
        \\
        \\
        \\def main() -> i64:
        \\    return i64(len(empty([])))
    , 0);
    try result(
        \\def main() -> i64:
        \\    return -[4][0] + 10
    , 6);
}

const allocation_source =
    \\class Box:
    \\    n: i64
    \\
    \\
    \\def id(a: [2]Box) -> [2]Box:
    \\    return a
    \\
    \\
    \\def main() -> i64:
    \\    a = id([Box(n=7), Box(n=9)])
    \\    b = replace(a, 1u8, Box(n=11))
    \\    return a[1].n + b[1].n + i64(len(b))
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 22), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "array compiler execution dump and discovery clean up at every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "array duplicate identity preserves length element type index replacement and order" {
    const source =
        \\def a(x: [2]i64) -> i64:
        \\    return x[0]
        \\
        \\
        \\def b(y: [02]i64) -> i64:
        \\    return y[0]
        \\
        \\
        \\def c(x: [3]i64) -> i64:
        \\    return x[0]
        \\
        \\
        \\def d(x: [2]i64) -> i64:
        \\    return x[1]
        \\
        \\
        \\def e(x: [2]u8) -> i64:
        \\    return i64(x[0])
        \\
        \\
        \\def f(x: [2]i64) -> i64:
        \\    return replace(x, 0, 1)[0]
        \\
        \\
        \\def g() -> [2]i64:
        \\    return [1, 2]
        \\
        \\
        \\def h() -> [2]i64:
        \\    return [2, 1]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    const members = discovery.groups[0].members;
    try testing.expectEqual(@as(usize, 2), members.len);
    try testing.expectEqualStrings("a", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("b", compilation.program.?.functions[@backingInt(members[1])].name);
}

test "deep array type syntax observes the shared parser budget" {
    var source: std.Io.Writer.Allocating = .init(testing.allocator);
    defer source.deinit();
    try source.writer.writeAll("class Deep:\n    value: ");
    for (0..300) |_| try source.writer.writeAll("[1]");
    try source.writer.writeAll("i64\n\n\ndef main() -> i64:\n    return 0\n");
    try reject(source.written(), "E_NESTING_LIMIT");
}

test "array bytecode validates schema kinds stack counts and runtime element types" {
    const typed = @import("typed.zig");
    const bc = language.bytecode;
    const span: language.source.Span = .{ .start = 0, .end = 1 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    const schema: typed.Record = .{
        .id = ty,
        .name = "[1]i64",
        .declaration = span,
        .fields = &.{},
        .shape = .{
            .array = .{ .element = .i64, .length = 1 },
        },
    };
    const Op = @FieldType(bc.Instruction, "op");
    for ([_]Op{ .{ .get_index = .i64 }, .{ .array_length = ty }, .{ .replace_index = ty }, .{ .make_record = .{ .ty = ty, .fields = 2 } } }) |op| {
        const instructions = [_]bc.Instruction{ .{ .span = span, .op = op }, .{ .span = span, .op = .ret } };
        const program: bc.Program = .{ .records = &.{schema}, .functions = &.{.{
            .id = @fromBackingInt(0),
            .name = "main",
            .scope = .{
                .instructions = &instructions,
            },
        }} };
        try testing.expectError(error.InternalError, bc.validate(testing.allocator, program));
    }
    const invalid = [_]bc.Instruction{
        .{ .span = span, .op = .{ .push_bool = true } },
        .{ .span = span, .op = .{ .make_record = .{ .ty = ty, .fields = 1 } } },
        .{ .span = span, .op = .{ .push_i64 = 0 } },
        .{ .span = span, .op = .{ .get_index = ty } },
        .{ .span = span, .op = .ret },
    };
    const program: bc.Program = .{ .records = &.{schema}, .functions = &.{.{
        .id = @fromBackingInt(0),
        .name = "main",
        .scope = .{
            .instructions = &invalid,
        },
    }} };
    try testing.expectError(error.InternalError, language.vm.run(testing.allocator, program));
}

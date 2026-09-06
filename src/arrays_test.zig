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
    try result("fn first(a: [2]i64) -> i64 { return a[0]; } fn main() -> i64 { let a: [02] i64 = new [2]i64 [3, 4]; let b = replace(a, 0, 8); return first(a) + b[0] + b[1]; }", 15);
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ let a = new [2]u8 [7u8, 9u8]; return cast<i64>(a[1{s}]); }}", .{width});
        defer testing.allocator.free(source);
        try result(source, 9);
    }
    try result("fn empty(a: [0]bool) -> [0]bool { return a; } fn main() -> i64 { return cast<i64>(len(empty(new [0]bool []))); }", 0);
    try result("fn main() -> i64 { return -new [1]i64 [4][0] + 10; }", 6);
}

test "nested arrays records and conversion field accounting compose" {
    try result("struct Cell { n: i64 } struct Grid { rows: [2][1]Cell } fn id(a: [2][1]Cell) -> " ++
        "[2][1]Cell { return a; } fn main() -> i64 { let a = new Grid { rows: id(new " ++
        "[2][1]Cell [new [1]Cell [new Cell { n: 3 }], new [1]Cell [new Cell { n: 7 }]]) }; " ++
        "let b = update(a) { rows: replace(a.rows, 0, new [1]Cell [new Cell { n: 9 }]) }; " ++
        "return a.rows[0][0].n + b.rows[0][0].n + b.rows[1][0].n; }", 19);
    try result("struct Source { values: [2]i64 } struct Target { total: i64 } conversion fn " ++
        "convert(src: Source) -> Target { return new Target { total: src.values[0] + " ++
        "src.values[1] }; } fn main() -> i64 { return convert(new Source { values: new [2]i64 " ++
        "[4, 7] }).total; }", 11);
    try reject("struct Source { values: [2]i64, added: bool } struct Target { total: i64 } " ++
        "conversion fn convert(src: Source) -> Target { return new Target { total: " ++
        "src.values[0] }; } fn main() -> i64 { return 0; }", "E_INCOMPLETE_CONVERSION");
}

test "array schemas reject type length shape and recursive layout errors" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn main() -> i64 { discard new [2]i64 [1]; return 0; }", .code = "E_ARRAY_ARITY" },
        .{ .text = "fn main() -> i64 { discard new [0]i64 [1]; return 0; }", .code = "E_ARRAY_ARITY" },
        .{ .text = "fn main() -> i64 { discard new [1]u8 [1]; return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { let a: [2]i64 = new [1]i64 [1]; return a[0]; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard new [1]i64 [1][true]; return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard 1[0]; return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard len(1); return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard replace(new [1]i64 [1], 0, true); return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard update(new [1]i64 [1]) {}; return 0; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { discard new [1]i64 { x: 1 }; return 0; }", .code = "E_TYPE" },
        .{ .text = "struct A {} fn main() -> i64 { discard new A []; return 0; }", .code = "E_TYPE" },
        .{ .text = "struct A {} fn main() -> i64 { discard new [1]A [new A {}].x; return 0; }", .code = "E_TYPE" },
        .{ .text = "struct A { x: [1]B } struct B { x: [2]A } fn main() -> i64 { return 0; }", .code = "E_RECURSIVE_RECORD" },
        .{ .text = "struct A { x: [0]A } fn main() -> i64 { return 0; }", .code = "E_RECURSIVE_RECORD" },
        .{ .text = "fn main() -> i64 { discard new [1u8]i64 [1]; return 0; }", .code = "E_ARRAY_LENGTH" },
        .{ .text = "fn main() -> i64 { discard new [18446744073709551616]i64 []; return 0; }", .code = "E_ARRAY_LENGTH" },
        .{ .text = "fn main() -> i64 { discard new [18446744073709551615]i64 []; return 0; }", .code = "E_ARRAY_LENGTH" },
        .{ .text = "fn main() -> i64 { discard new [1]Unknown []; return 0; }", .code = "E_UNKNOWN_TYPE" },
        .{ .text = "fn main() -> i64 { discard new [1][1]i64 [new [2]i64 [1, 2]]; return 0; }", .code = "E_TYPE" },
        .{ .text = "conversion fn convert(a: [1]i64) -> [1]i64 { return new [1]i64 [a[0]]; } fn main() -> i64 { return 0; }", .code = "E_TYPE" },
    };
    for (cases) |case| try reject(case.text, case.code);
    // Large type metadata stays constant-sized; no array value is constructed.
    try result("struct Large { values: [1000000000]u8 } fn main() -> i64 { return 0; }", 0);
}

test "array bounds traps include negative maximum unsigned and empty arrays" {
    for ([_][]const u8{ "-1", "2", "18446744073709551615u64" }) |index| {
        const expr = try std.fmt.allocPrint(testing.allocator, "new [2]i64 [3, 4][{s}]", .{index});
        defer testing.allocator.free(expr);
        const source = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ return {s}; }}", .{expr});
        defer testing.allocator.free(source);
        try trapped(source, "R_INDEX_BOUNDS", expr);
    }
    try trapped("fn main() -> i64 { return new [0]i64 [][0]; }", "R_INDEX_BOUNDS", "new [0]i64 [][0]");
    try trapped("fn main() -> i64 { discard replace(new [1]i64 [7], -1, 8); return 0; }", "R_INDEX_BOUNDS", "replace(new [1]i64 [7], -1, 8)");
    try trapped("fn main() -> i64 { discard replace(new [0]i64 [], 0u64, 8); return 0; }", "R_INDEX_BOUNDS", "replace(new [0]i64 [], 0u64, 8)");
}

test "arrays evaluate base index and replacement in order and length retains evaluation" {
    try trapped("fn main() -> i64 { discard new [2]i64 [1 / 0, 9223372036854775807 + 1]; return 0; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("fn main() -> i64 { discard new [1]i64 [1 / 0][9223372036854775807 + 1]; return 0; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("fn main() -> i64 { discard replace(new [1]i64 [7], 1 / 0, 9223372036854775807 + 1); return 0; }", "R_DIVISION_BY_ZERO", "/");
    // All arguments are evaluated before the replacement's bounds check.
    try trapped("fn main() -> i64 { discard replace(new [1]i64 [7], 9, 1 / 0); return 0; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("fn main() -> i64 { discard len(new [1]i64 [1 / 0]); return 0; }", "R_DIVISION_BY_ZERO", "/");
}

const allocation_source = "struct Box { n: i64 } fn id(a: [2]Box) -> [2]Box { return a; } fn main() -> i64 { " ++
    "let a = id(new [2]Box [new Box { n: 7 }, new Box { n: 9 }]); let b = replace(a, 1u8, " ++
    "new Box { n: 11 }); return a[1].n + b[1].n + cast<i64>(len(b)); }";
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

test "array replacement loops and traps release bounded runtime storage" {
    const source = "fn main() -> i64 { let mut a = new [2]i64 [0, 7]; while a[0] < 10000 { a = replace(a, 0, a[0] + 1); } return a[0] + a[1]; }";
    var compilation = try language.Compilation.init(testing.allocator, "loop.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    try testing.expectEqual(@as(i64, 10007), (try compilation.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    try testing.expectEqualStrings("R_STEP_LIMIT", (try compilation.executeWithOptions(limiter.allocator(), .{ .max_steps = 50 })).trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    var bounds = try language.Compilation.init(testing.allocator, "bounds.my", "struct Box { n: i64 } fn main() -> i64 { discard replace(new [1]Box [new Box { n: 1 }], 2, new Box { n: 3 }); return 0; }");
    defer bounds.deinit();
    try bounds.emit();
    try testing.expectEqualStrings("R_INDEX_BOUNDS", (try bounds.execute(limiter.allocator())).trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "array duplicate identity preserves length element type index replacement and order" {
    const source = "fn a(x: [2]i64) -> i64 { return x[0]; } fn b(y: [02] i64) -> i64 { return y[0]; } fn " ++
        "c(x: [3]i64) -> i64 { return x[0]; } fn d(x: [2]i64) -> i64 { return x[1]; } fn e(x: " ++
        "[2]u8) -> i64 { return cast<i64>(x[0]); } fn f(x: [2]i64) -> i64 { return replace(x, " ++
        "0, 1)[0]; } fn g() -> [2]i64 { return new [2]i64 [1, 2]; } fn h() -> [2]i64 { return " ++
        "new [2]i64 [2, 1]; } fn main() -> i64 { return 0; }";
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
    try source.writer.writeAll("struct Deep { value: ");
    for (0..300) |_| try source.writer.writeAll("[1]");
    try source.writer.writeAll("i64 } fn main() -> i64 { return 0; }");
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

//! Closed variant construction and matching tests, including nominal identity, allocation failures, and forged bytecode.
const fixture_path = "variants.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const choice =
    \\enum Choice:
    \\    first,
    \\    second,
    \\    third
    \\
    \\
    \\
;
const event =
    \\union Event:
    \\    count: i64,
    \\    flag: bool,
    \\    empty
    \\
    \\
    \\
;

// spec: CORE-8
test "exhaustive matching detects added variants even on statically known values" {
    const source =
        \\enum Choice:
        \\    first,
        \\    second,
        \\    added
        \\
        \\
        \\def main() -> i64:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            return 1
        \\        case Choice.second:
        \\            return 2
    ;
    var compilation = try language.Compilation.init(testing.allocator, "added.my", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try testing.expectEqualStrings("E_INCOMPLETE_MATCH", diagnostic.code);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "added") != null);
    try testing.expectEqualStrings("added", compilation.src.text(diagnostic.related.?.span));
    try reject(event ++
        \\def main() -> i64:
        \\    match Event.empty:
        \\        case Event.empty:
        \\            return 0
    , "E_INCOMPLETE_MATCH");
    try reject(choice ++
        \\def main() -> i64:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            return 1
        \\    return 0
    , "E_INCOMPLETE_MATCH");
}

test "match return analysis and control flow joins handle empty arms loops and nesting" {
    try reject(choice ++
        \\def main() -> i64:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            return 1
        \\        case Choice.second:
        \\            pass
        \\        case Choice.third:
        \\            return 3
    , "E_MISSING_RETURN");
    try reject(
        \\enum One:
        \\    only
        \\
        \\
        \\def main() -> i64:
        \\    match One.only:
        \\        case One.only:
        \\            return 1
        \\    return 2
    , "E_UNREACHABLE");
    try result(choice ++
        \\def main() -> i64:
        \\    n = 0
        \\    while n < 4:
        \\        match Choice.first:
        \\            case Choice.second:
        \\                return 90
        \\            case Choice.first:
        \\                n += 1
        \\            case Choice.third:
        \\                pass
        \\    return n
    , 4);
    try result(
        \\enum One:
        \\    only
        \\
        \\
        \\union U:
        \\    item: One
        \\
        \\
        \\def main() -> i64:
        \\    match U.item(One.only):
        \\        case U.item(x):
        \\            match x:
        \\                case One.only:
        \\                    return 9
    , 9);
    try result(choice ++
        \\def main() -> i64:
        \\    n = 7
        \\    match Choice.second:
        \\        case Choice.first:
        \\            n = 8
        \\        case Choice.second:
        \\            pass
        \\        case Choice.third:
        \\            n = 9
        \\    return n
    , 7);
}

const nested =
    \\record Box:
    \\    n: i64
    \\
    \\
    \\union Item:
    \\    boxes: [2]Box,
    \\    empty
    \\
    \\
    \\def value(x: Item) -> i64:
    \\    match x:
    \\        case Item.empty:
    \\            return 0
    \\        case Item.boxes(values):
    \\            return values[0].n + values[1].n
    \\
    \\
    \\def main() -> i64:
    \\    a = Item.boxes([Box(n=3), Box(n=7)])
    \\    b = a
    \\    return value(a) + value(b)
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, nested);
    defer compilation.deinit();
    try compilation.check();
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "variant payloads dispatch fixups dumps and discovery clean up at every allocation failure" {
    try result(nested, 20);
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "duplicate identity retains resolved variants arms and payload bindings" {
    const source =
        \\union U:
        \\    a: i64,
        \\    b: i64
        \\
        \\
        \\def one(x: U) -> i64:
        \\    match x:
        \\        case U.a(n):
        \\            return n
        \\        case U.b(n):
        \\            return n + 1
        \\
        \\
        \\def two(y: U) -> i64:
        \\    match y:
        \\        case U.a(v):
        \\            return v
        \\        case U.b(w):
        \\            return w + 1
        \\
        \\
        \\def changed(x: U) -> i64:
        \\    match x:
        \\        case U.a(n):
        \\            return n + 1
        \\        case U.b(n):
        \\            return n
        \\
        \\
        \\def a() -> U:
        \\    return U.a(1)
        \\
        \\
        \\def b() -> U:
        \\    return U.b(1)
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
    try testing.expectEqualStrings("one", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("two", compilation.program.?.functions[@backingInt(members[1])].name);
}

test "variant bytecode validates tags exhaustive targets and payload destination types" {
    const typed = @import("typed.zig");
    const bc = language.bytecode;
    const span: language.source.Span = .{ .start = 0, .end = 1 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    const schema: typed.Record = .{
        .id = ty,
        .name = "U",
        .declaration = span,
        .fields = &.{},
        .shape = .{
            .variants = .{
                .is_union = true,
                .cases = &.{ .{
                    .name = "a",
                    .declaration = span,
                    .payload = .i64,
                }, .{
                    .name = "b",
                    .declaration = span,
                    .payload = null,
                } },
            },
        },
    };
    const Op = @FieldType(bc.Instruction, "op");
    const operations = [_]Op{
        .{ .make_variant = .{ .ty = ty, .tag = 2 } },
        .{ .make_variant = .{ .ty = .i64, .tag = 0 } },
        .{ .switch_variant = .{ .ty = ty, .arms = &.{.{ .target = 1, .slot = null }} } },
        .{ .switch_variant = .{ .ty = ty, .arms = &.{ .{ .target = 99, .slot = null }, .{ .target = 1, .slot = null } } } },
        .{ .switch_variant = .{ .ty = ty, .arms = &.{ .{ .target = 1, .slot = @fromBackingInt(0) }, .{ .target = 1, .slot = null } } } },
        .{ .cmp_enum = .{ .ty = ty, .predicate = .eq } },
        .{ .make_record = .{ .ty = ty, .fields = 0 } },
    };
    for (operations) |op| {
        const instructions = [_]bc.Instruction{ .{ .span = span, .op = op }, .{ .span = span, .op = .ret } };
        const program: bc.Program = .{
            .records = &.{
                schema,
            },
            .functions = &.{.{
                .id = @fromBackingInt(0),
                .name = "main",
                .scope = .{
                    .locals = &.{.{
                        .name = "payload",
                        .declaration = span,
                        .ty = .bool,
                        .mutable = false,
                    }},
                    .instructions = &instructions,
                },
            }},
        };
        try testing.expectError(error.InternalError, bc.validate(testing.allocator, program));
    }
}

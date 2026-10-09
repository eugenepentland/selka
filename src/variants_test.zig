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
    \\    first
    \\    second
    \\    third
    \\
    \\
    \\
;
const event =
    \\enum Event:
    \\    count(value: i64)
    \\    flag(value: bool)
    \\    empty
    \\
    \\
    \\
;

// spec: CORE-8
test "exhaustive matching detects added variants even on statically known values" {
    const source =
        \\enum Choice:
        \\    first
        \\    second
        \\    added
        \\
        \\
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    match Event.empty:
        \\        case Event.empty:
        \\            return 0
    , "E_INCOMPLETE_MATCH");
    try reject(choice ++
        \\func main() -> i64:
        \\    match Choice.first:
        \\        case Choice.first:
        \\            return 1
        \\    return 0
    , "E_INCOMPLETE_MATCH");
}

test "match return analysis and control flow joins handle empty arms loops and nesting" {
    try reject(choice ++
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    match One.only:
        \\        case One.only:
        \\            return 1
        \\    return 2
    , "E_UNREACHABLE");
    try result(choice ++
        \\func main() -> i64:
        \\    mut n = 0
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
        \\enum U:
        \\    item(value: One)
        \\
        \\
        \\func main() -> i64:
        \\    match U.item(value=One.only):
        \\        case U.item(value=x):
        \\            match x:
        \\                case One.only:
        \\                    return 9
    , 9);
    try result(choice ++
        \\func main() -> i64:
        \\    mut n = 7
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
    \\enum Item:
    \\    boxes(value: FixedArray[Box, 2])
    \\    empty
    \\
    \\
    \\func value(x: Item) -> i64:
    \\    match x:
    \\        case Item.empty:
    \\            return 0
    \\        case Item.boxes(value=values):
    \\            return values[0].n + values[1].n
    \\
    \\
    \\func main() -> i64:
    \\    mut a = Item.boxes(value=FixedArray[Box, 2]([Box(n=3), Box(n=7)]))
    \\    mut b = a
    \\    return value(a) + value(b)
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, nested);
    defer compilation.deinit();
    try compilation.check();
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
        \\enum U:
        \\    a(value: i64)
        \\    b(value: i64)
        \\
        \\
        \\func one(x: U) -> i64:
        \\    match x:
        \\        case U.a(value=n):
        \\            return n
        \\        case U.b(value=n):
        \\            return n + 1
        \\
        \\
        \\func two(y: U) -> i64:
        \\    match y:
        \\        case U.a(value=v):
        \\            return v
        \\        case U.b(value=w):
        \\            return w + 1
        \\
        \\
        \\func changed(x: U) -> i64:
        \\    match x:
        \\        case U.a(value=n):
        \\            return n + 1
        \\        case U.b(value=n):
        \\            return n
        \\
        \\
        \\func a() -> U:
        \\    return U.a(value=1)
        \\
        \\
        \\func b() -> U:
        \\    return U.b(value=1)
        \\
        \\
        \\func main() -> i64:
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

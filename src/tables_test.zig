//! Enum-keyed table completeness, lookup, and type identity.
const fixture_path = "tables.my";
const typed = @import("typed.zig");
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
const color =
    \\enum Color:
    \\    red
    \\    green
    \\    blue
    \\
    \\
    \\
;
const other =
    \\enum Other:
    \\    red
    \\    green
    \\    blue
    \\
    \\
    \\
;

// spec: CORE-9
test "enum table construction follows names across enum and initializer reordering" {
    const body =
        \\func lookup(table: [Color]i64, key: Color) -> i64:
        \\    return table[key]
        \\
        \\
        \\func main() -> i64:
        \\    mut t: [Color]i64 = {Color.blue: 30, Color.red: 10, Color.green: 20}
        \\    return lookup(t, Color.red) + t[Color.green] * 10 + t[Color.blue] * 100
    ;
    try result(color ++ body, 3210);
    try result(
        \\enum Color:
        \\    blue
        \\    red
        \\    green
        \\
        \\
        \\
    ++ body, 3210);
    try result(
        \\enum One:
        \\    only
        \\
        \\
        \\func main() -> i64:
        \\    mut t: [One]bool = {One.only: True}
        \\    if t[One.only]:
        \\        return i64(len(t))
        \\    return 0
    , 1);
    try result(color ++
        \\func main() -> i64:
        \\    mut old: [Color]i64 = {Color.red: 1, Color.green: 2, Color.blue: 3}
        \\    mut changed = replace(old, Color.red, 9)
        \\    return old[Color.red] + changed[Color.red] + changed[Color.green] + i64(len(changed))
    , 15);
}

const allocation_source =
    \\enum Key:
    \\    a
    \\    b
    \\
    \\
    \\record Box:
    \\    n: i64
    \\
    \\
    \\func make() -> [Key]Box:
    \\    return {Key.b: Box(n=7), Key.a: Box(n=3)}
    \\
    \\
    \\func main() -> i64:
    \\    mut old = make()
    \\    mut next = replace(old, Key.a, Box(n=9))
    \\    return old[Key.a].n + next[Key.a].n + next[Key.b].n
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "table schemas named construction replacement and discovery clean up on allocation failure" {
    try result(allocation_source, 19);
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "table duplicate identity retains key type named mapping and initializer order" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", color ++ other ++
        \\func a(n: i64) -> [Color]i64:
        \\    return {Color.red: n, Color.green: 2, Color.blue: 3}
        \\
        \\
        \\func b(x: i64) -> [Color]i64:
        \\    return {Color.red: x, Color.green: 2, Color.blue: 3}
        \\
        \\
        \\func c(n: i64) -> [Other]i64:
        \\    return {Other.red: n, Other.green: 2, Other.blue: 3}
        \\
        \\
        \\func d(n: i64) -> [Color]i64:
        \\    return {Color.green: n, Color.red: 2, Color.blue: 3}
        \\
        \\
        \\func e(n: i64) -> [Color]i64:
        \\    return {Color.green: 2, Color.red: n, Color.blue: 3}
        \\
        \\
        \\func f(n: i64) -> FixedArray[i64, 3]:
        \\    return FixedArray[int, 3]([n, 2, 3])
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
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

fn schemaType(records: []const typed.Record, name: []const u8) !typed.Type {
    for (records) |schema| if (std.mem.eql(u8, schema.name, name)) return schema.id;
    return error.TestExpectedSchema;
}

test "missing named schema returns TestExpectedSchema" {
    try testing.expectError(error.TestExpectedSchema, schemaType(&.{}, "Other"));
}

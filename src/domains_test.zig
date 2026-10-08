//! Domain invariants, explicit wrapping, nominal conversions, and backend schema rejection tests.
const fixture_path = "domains.my";
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
const units =
    \\domain Millimeters: i64:
    \\    private def raw(n: i64) -> Millimeters:
    \\        return wrap[Millimeters](n)
    \\
    \\    def from(n: i64) -> Millimeters:
    \\        if n < 0:
    \\            return Millimeters.raw(0)
    \\        return Millimeters.raw(n)
    \\
    \\    def number(n: Millimeters) -> i64:
    \\        return unwrap(n)
    \\
    \\
    \\domain Seconds: i64:
    \\    def from(n: i64) -> Seconds:
    \\        return wrap[Seconds](n)
    \\
    \\    def number(n: Seconds) -> i64:
    \\        return unwrap(n)
    \\
    \\
    \\
;

test "domain backing types require built-in scalars and exact wrapping types" {
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(testing.allocator,
            \\domain Count: {s}:
            \\    def from(n: {s}) -> Count:
            \\        return wrap[Count](n)
            \\
            \\    def number(n: Count) -> {s}:
            \\        return unwrap(n)
            \\
            \\
            \\def main() -> i64:
            \\    return i64(Count.number(Count.from(7{s})))
        , .{ width, width, width, width });
        defer testing.allocator.free(source);
        try result(source, 7);
    }
    try result(
        \\domain Flag: bool:
        \\    def from(n: bool) -> Flag:
        \\        return wrap[Flag](n)
        \\
        \\    def test(n: Flag) -> bool:
        \\        return unwrap(n)
        \\
        \\
        \\def main() -> i64:
        \\    if Flag.test(Flag.from(True)):
        \\        return 1
        \\    return 0
    , 1);
    try reject(
        \\domain Bad: [1]i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DOMAIN_BASE");
    try reject(
        \\record Record:
        \\    pass
        \\
        \\
        \\domain Bad: Record:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DOMAIN_BASE");
    try reject(
        \\domain First: i64:
        \\    pass
        \\
        \\
        \\domain Bad: First:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DOMAIN_BASE");
    try reject(
        \\domain Bad: Missing:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_TYPE");
    try reject(
        \\domain Byte: u8:
        \\    def from(n: i64) -> Byte:
        \\        return wrap[Byte](n)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_TYPE");
    try reject(
        \\domain Byte: u8:
        \\    def from(n: u8) -> Byte:
        \\        return wrap[u8](n)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_TYPE");
    try reject(
        \\domain Byte: u8:
        \\    def from(n: u8) -> Byte:
        \\        return unwrap(n)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_TYPE");
}

test "domain namespaces support forward calls recursion private helpers and shared member names" {
    try result(
        \\def from(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\domain D: i64:
        \\    def from(n: i64) -> D:
        \\        if n > 0:
        \\            return D.from(n - 1)
        \\        return D.raw(from(7))
        \\
        \\    private def raw(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\    def number(n: D) -> i64:
        \\        return unwrap(n)
        \\
        \\
        \\def main() -> i64:
        \\    return D.number(D.from(20))
    , 8);
    try reject(
        \\domain D: i64:
        \\    def f() -> i64:
        \\        return 0
        \\
        \\    def f() -> i64:
        \\        return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_FUNCTION");
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_TYPE");
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\record D:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_TYPE");
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\def D() -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_NAME");
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    D = 1
        \\    return D
    , "E_SHADOWING");
    try reject(
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return D.missing()
    , "E_UNKNOWN_FUNCTION");
    try reject(
        \\record D:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return D.missing()
    , "E_TYPE");
    try reject(
        \\domain D: i64:
        \\    def main() -> i64:
        \\        return 0
    , "E_MAIN");
    try reject(
        \\private def helper() -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_PRIVATE_SCOPE");
}

const allocation_source = units ++
    \\def main() -> i64:
    \\    a: [2]Millimeters = [Millimeters.from(3), Millimeters.from(8)]
    \\    b = replace(a, 0, Millimeters.from(-1))
    \\    return Millimeters.number(a[0]) + Millimeters.number(b[0])
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 3), (try native.run(&compilation)).value);
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "domain factories accessors qualified names and discovery clean up on allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "duplicate discovery preserves domain ownership visibility and qualified callees" {
    const source =
        \\domain none: i64:
        \\    def a(n: i64) -> i64:
        \\        return n + 1
        \\
        \\    def b(x: i64) -> i64:
        \\        return x + 1
        \\
        \\    private def c(n: i64) -> i64:
        \\        return n + 1
        \\
        \\
        \\domain Other: i64:
        \\    def a(n: i64) -> i64:
        \\        return n + 1
        \\
        \\
        \\def a(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\def b(n: i64) -> i64:
        \\    return none.a(n)
        \\
        \\
        \\def c(n: i64) -> i64:
        \\    return Other.a(n)
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
    try testing.expectEqualStrings("none.a", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("none.b", compilation.program.?.functions[@backingInt(members[1])].name);
}

// spec: CORE-7
test "nominal domains prevent mixing units and preserve validated factory values" {
    try result(units ++
        \\def main() -> i64:
        \\    return Millimeters.number(Millimeters.from(-8)) + Seconds.number(Seconds.from(3))
    , 3);
    try reject(units ++
        \\def move(distance: Millimeters) -> i64:
        \\    return Millimeters.number(distance)
        \\
        \\
        \\def main() -> i64:
        \\    return move(Seconds.from(3))
    , "E_TYPE");
    try reject(units ++
        \\def main() -> i64:
        \\    distance: Millimeters = Seconds.from(3)
        \\    return Millimeters.number(distance)
    , "E_TYPE");
    try reject(units ++
        \\def main() -> i64:
        \\    return Millimeters.number(4)
    , "E_TYPE");
    try reject(units ++
        \\def main() -> i64:
        \\    return Millimeters.from(4)
    , "E_TYPE");
    try reject(units ++
        \\def main() -> i64:
        \\    _ = Millimeters.from(4) + Millimeters.from(2)
        \\    return 0
    , "E_TYPE");
    const conversion =
        \\domain Seconds: u64:
        \\    def from(n: u64) -> Seconds:
        \\        return wrap[Seconds](n)
        \\
        \\    def number(n: Seconds) -> u64:
        \\        return unwrap(n)
        \\
        \\
        \\domain Millimeters: u8:
        \\    def from(n: u8) -> Millimeters:
        \\        return wrap[Millimeters](n)
        \\
        \\    def number(n: Millimeters) -> u8:
        \\        return unwrap(n)
        \\
        \\
        \\def distance(time: Seconds) -> Millimeters:
        \\    return Millimeters.from(u8(Seconds.number(time) * 10u64))
        \\
        \\
        \\
    ;
    try result(conversion ++
        \\def main() -> i64:
        \\    return i64(Millimeters.number(distance(Seconds.from(7u64))))
    , 70);
    var overflow = try language.Compilation.init(testing.allocator, "conversion.my", conversion ++
        \\def main() -> i64:
        \\    _ = distance(Seconds.from(26u64))
        \\    return 0
    );
    defer overflow.deinit();
    try testing.expectEqualStrings("R_OVERFLOW", (try native.run(&overflow)).trap.code);
}

test "domain creation loops complete and factory traps name the failing frame" {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, units ++
        \\def main() -> i64:
        \\    current = Millimeters.from(0)
        \\    while Millimeters.number(current) < 10000:
        \\        current = Millimeters.from(Millimeters.number(current) + 1)
        \\    return Millimeters.number(current)
    );
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 10000), (try native.run(&compilation)).value);
    const budgeted = try native.runWithOptions(&compilation, .{ .max_steps = 50 });
    try testing.expectEqualStrings("R_STEP_LIMIT", budgeted.trap.code);
    var trapped = try language.Compilation.init(testing.allocator, "trapped.my",
        \\domain Byte: u8:
        \\    def from(n: i64) -> Byte:
        \\        return wrap[Byte](u8(n))
        \\
        \\
        \\def main() -> i64:
        \\    _ = Byte.from(256)
        \\    return 0
    );
    defer trapped.deinit();
    const outcome = try native.run(&trapped);
    try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try testing.expectEqualStrings("Byte.from", outcome.trap.frames[0].function);
}

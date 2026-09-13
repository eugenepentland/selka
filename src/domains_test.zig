//! Domain invariants, explicit wrapping, nominal conversions, and backend schema rejection tests.
const fixture_path = "domains.my";
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
const units = "domain Millimeters: i64 { private fn raw(n: i64) -> Millimeters { return " ++
    "wrap<Millimeters>(n); } fn from(n: i64) -> Millimeters { if n < 0 { return " ++
    "Millimeters.raw(0); } return Millimeters.raw(n); } fn number(n: Millimeters) -> i64 " ++
    "{ return unwrap(n); } } domain Seconds: i64 { fn from(n: i64) -> Seconds { return " ++
    "wrap<Seconds>(n); } fn number(n: Seconds) -> i64 { return unwrap(n); } } ";

test "domain backing types require built-in scalars and exact wrapping types" {
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |width| {
        const source = try std.fmt.allocPrint(testing.allocator, "domain Count: {s} {{ fn from(n: {s}) -> Count {{ return wrap<Count>(n); }} fn " ++
            "number(n: Count) -> {s} {{ return unwrap(n); }} }} fn main() -> i64 {{ return " ++
            "cast<i64>(Count.number(Count.from(7{s}))); }}", .{ width, width, width, width });
        defer testing.allocator.free(source);
        try result(source, 7);
    }
    try result("domain Flag: bool { fn from(n: bool) -> Flag { return wrap<Flag>(n); } fn test(n: Flag) -> bool { return unwrap(n); } } fn main() -> i64 { if Flag.test(Flag.from(true)) { return 1; } return 0; }", 1);
    try reject("domain Bad: [1]i64 {} fn main() -> i64 { return 0; }", "E_DOMAIN_BASE");
    try reject("struct Record {} domain Bad: Record {} fn main() -> i64 { return 0; }", "E_DOMAIN_BASE");
    try reject("domain First: i64 {} domain Bad: First {} fn main() -> i64 { return 0; }", "E_DOMAIN_BASE");
    try reject("domain Bad: Missing {} fn main() -> i64 { return 0; }", "E_UNKNOWN_TYPE");
    try reject("domain Byte: u8 { fn from(n: i64) -> Byte { return wrap<Byte>(n); } } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("domain Byte: u8 { fn from(n: u8) -> Byte { return wrap<u8>(n); } } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("domain Byte: u8 { fn from(n: u8) -> Byte { return unwrap(n); } } fn main() -> i64 { return 0; }", "E_TYPE");
}

test "domain namespaces support forward calls recursion private helpers and shared member names" {
    try result("fn from(n: i64) -> i64 { return n + 1; } domain D: i64 { fn from(n: i64) -> D { if n " ++
        "> 0 { return D.from(n - 1); } return D.raw(from(7)); } private fn raw(n: i64) -> D { " ++
        "return wrap<D>(n); } fn number(n: D) -> i64 { return unwrap(n); } } fn main() -> i64 " ++
        "{ return D . number(D . from(20)); }", 8);
    try reject("domain D: i64 { fn f() -> i64 { return 0; } fn f() -> i64 { return 1; } } fn main() -> i64 { return 0; }", "E_DUPLICATE_FUNCTION");
    try reject("domain D: i64 {} domain D: i64 {} fn main() -> i64 { return 0; }", "E_DUPLICATE_TYPE");
    try reject("domain D: i64 {} struct D {} fn main() -> i64 { return 0; }", "E_DUPLICATE_TYPE");
    try reject("domain D: i64 {} fn D() -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_DUPLICATE_NAME");
    try reject("domain D: i64 {} fn main() -> i64 { let D = 1; return D; }", "E_SHADOWING");
    try reject("domain D: i64 {} fn main() -> i64 { return D.missing(); }", "E_UNKNOWN_FUNCTION");
    try reject("struct D {} fn main() -> i64 { return D.missing(); }", "E_TYPE");
    try reject("domain D: i64 { fn main() -> i64 { return 0; } }", "E_MAIN");
    try reject("private fn helper() -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_PRIVATE_SCOPE");
}

const allocation_source = units ++ "fn main() -> i64 { let a = new [2]Millimeters [Millimeters.from(3), Millimeters.from(8)]; let b = replace(a, 0, Millimeters.from(-1)); return Millimeters.number(a[0]) + Millimeters.number(b[0]); }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 3), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "domain factories accessors qualified names and discovery clean up on allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "duplicate discovery preserves domain ownership visibility and qualified callees" {
    const source = "domain none: i64 { fn a(n: i64) -> i64 { return n + 1; } fn b(x: i64) -> i64 { " ++
        "return x + 1; } private fn c(n: i64) -> i64 { return n + 1; } } domain Other: i64 { " ++
        "fn a(n: i64) -> i64 { return n + 1; } } fn a(n: i64) -> i64 { return n + 1; } fn " ++
        "b(n: i64) -> i64 { return none.a(n); } fn c(n: i64) -> i64 { return Other.a(n); } fn " ++
        "main() -> i64 { return 0; }";
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

test "domain bytecode rejects unowned representation access and private calls" {
    const bc = language.bytecode;
    const typed = @import("typed.zig");
    const span: language.source.Span = .{ .start = 0, .end = 1 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    const schema: typed.Record = .{
        .id = ty,
        .name = "D",
        .declaration = span,
        .fields = &.{},
        .shape = .{
            .domain = .i64,
        },
    };
    const Op = @FieldType(bc.Instruction, "op");
    for ([_]Op{ .{ .wrap_domain = ty }, .{ .unwrap_domain = ty }, .{ .make_record = .{ .ty = ty, .fields = 1 } } }) |op| {
        const instructions = [_]bc.Instruction{ .{ .span = span, .op = .{ .push_i64 = 1 } }, .{ .span = span, .op = op }, .{ .span = span, .op = .ret } };
        const program: bc.Program = .{ .records = &.{schema}, .functions = &.{.{
            .id = @fromBackingInt(0),
            .name = "main",
            .scope = .{
                .instructions = &instructions,
            },
        }} };
        try testing.expectError(error.InternalError, bc.validate(testing.allocator, program));
    }
    const program: bc.Program = .{ .records = &.{schema}, .functions = &.{
        .{
            .id = @fromBackingInt(0),
            .name = "main",
            .scope = .{
                .instructions = &.{ .{ .span = span, .op = .{ .call = @fromBackingInt(1) } }, .{ .span = span, .op = .ret } },
            },
        },
        .{
            .id = @fromBackingInt(1),
            .policy = .{
                .owner = ty,
                .restricted = true,
            },
            .name = "D.private",
            .scope = .{
                .instructions = &.{ .{ .span = span, .op = .{ .push_i64 = 1 } }, .{ .span = span, .op = .ret } },
            },
        },
    } };
    try testing.expectError(error.InternalError, bc.validate(testing.allocator, program));
}

// spec: CORE-7
test "nominal domains prevent mixing units and preserve validated factory values" {
    try result(units ++ "fn main() -> i64 { return Millimeters.number(Millimeters.from(-8)) + Seconds.number(Seconds.from(3)); }", 3);
    try reject(units ++ "fn move(distance: Millimeters) -> i64 { return Millimeters.number(distance); } fn main() -> i64 { return move(Seconds.from(3)); }", "E_TYPE");
    try reject(units ++ "fn main() -> i64 { let distance: Millimeters = Seconds.from(3); return Millimeters.number(distance); }", "E_TYPE");
    try reject(units ++ "fn main() -> i64 { return Millimeters.number(4); }", "E_TYPE");
    try reject(units ++ "fn main() -> i64 { return Millimeters.from(4); }", "E_TYPE");
    try reject(units ++ "fn main() -> i64 { _ = Millimeters.from(4) + Millimeters.from(2); return 0; }", "E_TYPE");
    const conversion = "domain Seconds: u64 { fn from(n: u64) -> Seconds { return wrap<Seconds>(n); } fn " ++
        "number(n: Seconds) -> u64 { return unwrap(n); } } domain Millimeters: u8 { fn " ++
        "from(n: u8) -> Millimeters { return wrap<Millimeters>(n); } fn number(n: " ++
        "Millimeters) -> u8 { return unwrap(n); } } fn distance(time: Seconds) -> Millimeters " ++
        "{ return Millimeters.from(cast<u8>(Seconds.number(time) * 10u64)); } ";
    try result(conversion ++ "fn main() -> i64 { return cast<i64>(Millimeters.number(distance(Seconds.from(7u64)))); }", 70);
    var overflow = try language.Compilation.init(testing.allocator, "conversion.my", conversion ++ "fn main() -> i64 { _ = distance(Seconds.from(26u64)); return 0; }");
    defer overflow.deinit();
    try testing.expectEqualStrings("R_OVERFLOW", (try overflow.execute(testing.allocator)).trap.code);
}

test "domain creation loops and factory traps release bounded runtime storage" {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, units ++ "fn main() -> i64 { let mut current = Millimeters.from(0); while " ++
        "Millimeters.number(current) < 10000 { current = " ++
        "Millimeters.from(Millimeters.number(current) + 1); } return " ++
        "Millimeters.number(current); }");
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    try testing.expectEqual(@as(i64, 10000), (try compilation.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    try testing.expectEqualStrings("R_STEP_LIMIT", (try compilation.executeWithOptions(limiter.allocator(), .{ .max_steps = 50 })).trap.code);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    var trapped = try language.Compilation.init(testing.allocator, "trapped.my", "domain Byte: u8 { fn from(n: i64) -> Byte { return wrap<Byte>(cast<u8>(n)); } } fn main() -> i64 { _ = Byte.from(256); return 0; }");
    defer trapped.deinit();
    try trapped.emit();
    const outcome = try trapped.execute(limiter.allocator());
    try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try testing.expectEqualStrings("Byte.from", outcome.trap.stack.frames[0].function);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

//! Closed variant construction and matching tests, including nominal identity, allocation failures, and forged bytecode.
const fixture_path = "variants.my";
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
const choice = "enum Choice { first, second, third } ";
const event = "union Event { count: i64, flag: bool, empty } ";

// spec: CORE-8
test "exhaustive matching detects added variants even on statically known values" {
    const source = "enum Choice { first, second, added } fn main() -> i64 { match new Choice.first { Choice.first => { return 1; }, Choice.second => { return 2; } } }";
    var compilation = try language.Compilation.init(testing.allocator, "added.my", source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try testing.expectEqualStrings("E_INCOMPLETE_MATCH", diagnostic.code);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "added") != null);
    try testing.expectEqualStrings("added", compilation.src.text(diagnostic.related.?.span));
    try reject(event ++ "fn main() -> i64 { match new Event.empty { Event.empty => { return 0; } } }", "E_INCOMPLETE_MATCH");
    try reject(choice ++ "fn main() -> i64 { match new Choice.first {} return 0; }", "E_INCOMPLETE_MATCH");
    try reject(choice ++ "fn main() -> i64 { match new Choice.first { else => { return 0; } } }", "E_SYNTAX");
}

test "match return analysis and control flow joins handle empty arms loops and nesting" {
    try reject(choice ++ "fn main() -> i64 { match new Choice.first { Choice.first => { return 1; }, Choice.second => {}, Choice.third => { return 3; } } }", "E_MISSING_RETURN");
    try reject("enum One { only } fn main() -> i64 { match new One.only { One.only => { return 1; } } return 2; }", "E_UNREACHABLE");
    try result(choice ++ "fn main() -> i64 { let mut n = 0; while n < 4 { match new Choice.first { Choice.second => { return 90; }, Choice.first => { n += 1; }, Choice.third => {} } } return n; }", 4);
    try result("enum One { only } union U { item: One } fn main() -> i64 { match new U.item(new One.only) { U.item(x) => { match x { One.only => { return 9; } } } } }", 9);
    try result(choice ++ "fn main() -> i64 { let mut n = 7; match new Choice.second { Choice.first => { n = 8; }, Choice.second => {}, Choice.third => { n = 9; } } return n; }", 7);
}

const nested = "struct Box { n: i64 } union Item { boxes: [2]Box, empty } fn value(x: Item) -> i64 { " ++
    "match x { Item.empty => { return 0; }, Item.boxes(values) => { return values[0].n + " ++
    "values[1].n; } } } fn main() -> i64 { let a = new Item.boxes(new [2]Box [new Box { " ++
    "n: 3 }, new Box { n: 7 }]); let b = a; return value(a) + value(b); }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, nested);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 20), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "variant payloads dispatch fixups dumps and discovery clean up at every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "variant copies and payload bindings retain bounded storage across overwrites and traps" {
    const source = "union State { running: i64, stopped } fn main() -> i64 { let mut state = new " ++
        "State.running(0); let mut done = false; while !done { match state { State.running(n) " ++
        "=> { if n < 10000 { state = new State.running(n + 1); } else { state = new " ++
        "State.stopped; } }, State.stopped => { done = true; } } } return 10000; }";
    var compilation = try language.Compilation.init(testing.allocator, "loop.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    try testing.expectEqual(@as(i64, 10000), (try compilation.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    // Trap at every executed boundary of a program owning nested aggregate payloads.
    var payload = try language.Compilation.init(testing.allocator, "payload.my", nested);
    defer payload.deinit();
    try payload.emit();
    var completed = false;
    for (1..100) |budget| {
        const outcome = try payload.executeWithOptions(limiter.allocator(), .{ .max_steps = budget });
        try testing.expectEqual(@as(usize, 0), limiter.live);
        if (outcome == .value) {
            completed = true;
            break;
        }
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
    try testing.expect(completed);
}

test "duplicate identity retains resolved variants arms and payload bindings" {
    const source = "union U { a: i64, b: i64 } fn one(x: U) -> i64 { match x { U.a(n) => { return n; }, " ++
        "U.b(n) => { return n + 1; } } } fn two(y: U) -> i64 { match y { U.a(v) => { return v;" ++
        " }, U.b(w) => { return w + 1; } } } fn changed(x: U) -> i64 { match x { U.a(n) => { " ++
        "return n + 1; }, U.b(n) => { return n; } } } fn a() -> U { return new U.a(1); } fn " ++
        "b() -> U { return new U.b(1); } fn main() -> i64 { return 0; }";
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

//! Enum-keyed table completeness, lookup, and type identity tests with invalid bytecode fixtures.
const fixture_path = "tables.my";
const typed = @import("typed.zig");
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
const color = "enum Color { red, green, blue } ";
const other = "enum Other { red, green, blue } ";

// spec: CORE-9
test "enum table construction follows names across enum and initializer reordering" {
    const body = "fn lookup(table: [Color]i64, key: Color) -> i64 { return table[key]; } fn main() -> " ++
        "i64 { let t: [ Color ] i64 = new [Color]i64 { blue: 30, red: 10, green: 20 }; return " ++
        "lookup(t, new Color.red) + t[new Color.green] * 10 + t[new Color.blue] * 100; }";
    try result(color ++ body, 3210);
    try result("enum Color { blue, red, green } " ++ body, 3210);
    try result("enum One { only } fn main() -> i64 { let t = new [One]bool { only: true }; if t[new One.only] { return cast<i64>(len(t)); } return 0; }", 1);
    try result(color ++ "fn main() -> i64 { let old = new [Color]i64 { red: 1, green: 2, blue: 3 }; let " ++
        "changed = replace(old, new Color.red, 9); return old[new Color.red] + changed[new " ++
        "Color.red] + changed[new Color.green] + cast<i64>(len(changed)); }", 15);
}

test "adding an enum case exposes incomplete tables at the new case declaration" {
    var compilation = try language.Compilation.init(testing.allocator, "added.my", "enum Color { red, green, added } fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2 }; return t[new Color.red]; }");
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try testing.expectEqualStrings("E_INCOMPLETE_TABLE", diagnostic.code);
    try testing.expect(std.mem.indexOf(u8, diagnostic.message, "added") != null);
    try testing.expectEqualStrings("added", compilation.src.text(diagnostic.related.?.span));
    try reject(color ++ "fn main() -> i64 { discard new [Color]i64 {}; return 0; }", "E_INCOMPLETE_TABLE");
    // A complete addition also survives updates that change only another key.
    try result("enum Color { red, green, added } fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, added: 99 }; let next = replace(t, new Color.red, 7); return next[new Color.added]; }", 99);
}

test "table key types stay nominal and cannot be substituted with numeric arrays" {
    try reject(color ++ other ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; return t[new Other.red]; }", "E_TYPE");
    try reject(color ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; return t[0]; }", "E_TYPE");
    try reject(color ++ "fn main() -> i64 { let a = new [3]i64 [1, 2, 3]; return a[new Color.red]; }", "E_TYPE");
    try reject(color ++ "fn main() -> i64 { let t: [Color]i64 = new [3]i64 [1, 2, 3]; return t[new Color.red]; }", "E_TYPE");
    try reject(color ++ other ++ "fn read(t: [Color]i64) -> i64 { return t[new Color.red]; } fn main() -> i64 { return read(new [Other]i64 { red: 1, green: 2, blue: 3 }); }", "E_TYPE");
    try reject(color ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; discard replace(t, 0u8, 4); return 0; }", "E_TYPE");
    try reject(color ++ other ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; discard replace(t, new Other.red, 4); return 0; }", "E_TYPE");
}

test "table declarations and initialization reject invalid keys shapes values and duplicates" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source = "struct Bad { t: [i64]bool } fn main() -> i64 { return 0; }", .code = "E_TABLE_KEY" },
        .{ .source = "domain D: i64 {} struct Bad { t: [D]bool } fn main() -> i64 { return 0; }", .code = "E_TABLE_KEY" },
        .{ .source = "union U { a, b } struct Bad { t: [U]bool } fn main() -> i64 { return 0; }", .code = "E_TABLE_KEY" },
        .{ .source = "struct R {} struct Bad { t: [R]bool } fn main() -> i64 { return 0; }", .code = "E_TABLE_KEY" },
        .{ .source = "struct Bad { t: [[1]i64]bool } fn main() -> i64 { return 0; }", .code = "E_TABLE_KEY" },
        .{ .source = "struct Bad { t: [Missing]bool } fn main() -> i64 { return 0; }", .code = "E_UNKNOWN_TYPE" },
        .{ .source = color ++ "fn main() -> i64 { discard new [Color]i64 [1, 2, 3]; return 0; }", .code = "E_TABLE_CONSTRUCTION" },
        .{ .source = color ++ "fn main() -> i64 { discard new [Color]i64 { red: 1, red: 2, blue: 3 }; return 0; }", .code = "E_DUPLICATE_KEY" },
        .{ .source = color ++ "fn main() -> i64 { discard new [Color]i64 { red: 1, unknown: 2, blue: 3 }; return 0; }", .code = "E_UNKNOWN_VARIANT" },
        .{ .source = color ++ "fn main() -> i64 { discard new [Color]u8 { red: 1, green: 2u8, blue: 3u8 }; return 0; }", .code = "E_TYPE" },
        .{ .source = color ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; discard replace(t, new Color.red, true); return 0; }", .code = "E_TYPE" },
        .{ .source = color ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; return t.red; }", .code = "E_TYPE" },
        .{ .source = color ++ "fn main() -> i64 { let t = new [Color]i64 { red: 1, green: 2, blue: 3 }; discard update(t) { red: 4 }; return 0; }", .code = "E_TYPE" },
        .{ .source = "enum Key { a } struct Loop { t: [Key]Loop } fn main() -> i64 { return 0; }", .code = "E_RECURSIVE_RECORD" },
    };
    for (cases) |case| try reject(case.source, case.code);
}

test "tables compose with forward enums arrays nested tables domains unions and conversions" {
    try result("struct Store { t: [Key][1]i64 } enum Key { a, b } fn main() -> i64 { let s = new Store { t: new [Key][1]i64 { a: new [1]i64 [3], b: new [1]i64 [7] } }; return s.t[new Key.a][0] + s.t[new Key.b][0]; }", 10);
    try result("enum Row { first, second } enum Col { x, y } fn main() -> i64 { let grid = new " ++
        "[Row][Col]i64 { second: new [Col]i64 { y: 4, x: 3 }, first: new [Col]i64 { x: 1, y: " ++
        "2 } }; return grid[new Row.first][new Col.y] + grid[new Row.second][new Col.x]; }", 5);
    try result("enum Key { a } domain Count: i64 { fn from(n: i64) -> Count { return wrap<Count>(n); " ++
        "} fn number(n: Count) -> i64 { return unwrap(n); } } union U { table: [Key]Count, " ++
        "empty } fn main() -> i64 { match new U.table(new [Key]Count { a: Count.from(9) }) { " ++
        "U.empty => { return 0; }, U.table(t) => { return Count.number(t[new Key.a]); } } }", 9);
    try result("enum Key { a } struct Source { mapping: [Key]i64, ignored: bool } struct Target { n: " ++
        "i64 } conversion fn convert(s: Source) -> Target { discard s.ignored; return new " ++
        "Target { n: s.mapping[new Key.a] }; } fn main() -> i64 { return convert(new Source { " ++
        "mapping: new [Key]i64 { a: 11 }, ignored: false }).n; }", 11);
    // External numeric codes use an explicit decoder; unknown values remain visible.
    try result("enum Message { ping, pong } union Decoded { known: Message, unknown: u8 } fn " ++
        "decode(raw: u8) -> Decoded { if raw == 1u8 { return new Decoded.known(new " ++
        "Message.ping); } if raw == 2u8 { return new Decoded.known(new Message.pong); } " ++
        "return new Decoded.unknown(raw); } fn code(raw: u8) -> i64 { let mapping = new " ++
        "[Message]i64 { pong: 20, ping: 10 }; match decode(raw) { Decoded.known(message) => { " ++
        "return mapping[message]; }, Decoded.unknown(value) => { return -cast<i64>(value); } }" ++
        " } fn main() -> i64 { return code(1u8) + code(255u8); }", -245);
}

test "table evaluation preserves written initializer order and base key replacement order" {
    try trapped(color ++ "fn main() -> i64 { discard new [Color]i64 { blue: 1 / 0, red: 9223372036854775807 + 1, green: 2 }; return 0; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("enum Key { a } fn key() -> Key { discard 9223372036854775807 + 1; return new Key.a; } fn main() -> i64 { return new [Key]i64 { a: 1 / 0 }[key()]; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("enum Key { a } fn key() -> Key { discard 1 / 0; return new Key.a; } fn main() -> i64 { discard replace(new [Key]i64 { a: 1 }, key(), 9223372036854775807 + 1); return 0; }", "R_DIVISION_BY_ZERO", "/");
    try trapped("enum Key { a } fn main() -> i64 { discard len(new [Key]i64 { a: 1 / 0 }); return 0; }", "R_DIVISION_BY_ZERO", "/");
}

const allocation_source = "enum Key { a, b } struct Box { n: i64 } fn make() -> [Key]Box { return new [Key]Box " ++
    "{ b: new Box { n: 7 }, a: new Box { n: 3 } }; } fn main() -> i64 { let old = make(); " ++
    "let next = replace(old, new Key.a, new Box { n: 9 }); return old[new Key.a].n + " ++
    "next[new Key.a].n + next[new Key.b].n; }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, allocation_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 19), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "table schemas named construction replacement and discovery clean up on allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "table replacement loops and traps retain bounded live runtime storage" {
    const source = "enum Key { count, keep } fn main() -> i64 { let mut t = new [Key]i64 { count: 0, " ++
        "keep: 7 }; while t[new Key.count] < 10000 { t = replace(t, new Key.count, t[new " ++
        "Key.count] + 1); } return t[new Key.count] + t[new Key.keep]; }";
    var compilation = try language.Compilation.init(testing.allocator, "loop.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    try testing.expectEqual(@as(i64, 10007), (try compilation.execute(limiter.allocator())).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
    var nested = try language.Compilation.init(testing.allocator, "nested.my", allocation_source);
    defer nested.deinit();
    try nested.emit();
    var completed = false;
    for (1..100) |budget| {
        const outcome = try nested.executeWithOptions(limiter.allocator(), .{ .max_steps = budget });
        try testing.expectEqual(@as(usize, 0), limiter.live);
        if (outcome == .value) {
            completed = true;
            break;
        }
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
    try testing.expect(completed);
}

test "table duplicate identity retains key type named mapping and initializer order" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", color ++ other ++ "fn a(n: i64) -> [Color]i64 { return new [Color]i64 { red: n, green: 2, blue: 3 }; } " ++
        "fn b(x: i64) -> [Color]i64 { return new [Color]i64 { red: x, green: 2, blue: 3 }; } " ++
        "fn c(n: i64) -> [Other]i64 { return new [Other]i64 { red: n, green: 2, blue: 3 }; } " ++
        "fn d(n: i64) -> [Color]i64 { return new [Color]i64 { green: n, red: 2, blue: 3 }; } " ++
        "fn e(n: i64) -> [Color]i64 { return new [Color]i64 { green: 2, red: n, blue: 3 }; } " ++
        "fn f(n: i64) -> [3]i64 { return new [3]i64 [n, 2, 3]; } fn main() -> i64 { return 0; " ++
        "}");
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

test "table VM rejects forged numeric and foreign enum keys and releases operands" {
    var compilation = try language.Compilation.init(testing.allocator, "invalid.my", "enum Key { a } enum Other { a } fn main() -> i64 { return new [Key]i64 { a: 7 }[new Key.a]; }");
    defer compilation.deinit();
    try compilation.emit();
    const other_type = try schemaType(compilation.code.?.records, "Other");
    const instructions = try testing.allocator.dupe(language.bytecode.Instruction, compilation.code.?.functions[0].scope.instructions);
    defer testing.allocator.free(instructions);
    for ([_]@FieldType(language.bytecode.Instruction, "op"){ .{ .push_i64 = 0 }, .{ .make_variant = .{ .ty = other_type, .tag = 0 } } }) |replacement| {
        @memcpy(instructions, compilation.code.?.functions[0].scope.instructions);
        for (instructions) |*instruction| if (instruction.op == .make_variant) {
            instruction.op = replacement;
        };
        var function = compilation.code.?.functions[0];
        function.scope.instructions = instructions;
        const invalid: language.bytecode.Program = .{ .records = compilation.code.?.records, .functions = &.{function} };
        var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
        defer limiter.deinit();
        try testing.expectError(error.InternalError, language.vm.run(limiter.allocator(), invalid));
        try testing.expectEqual(@as(usize, 0), limiter.live);
    }
}

fn schemaType(records: []const typed.Record, name: []const u8) !typed.Type {
    for (records) |schema| if (std.mem.eql(u8, schema.name, name)) return schema.id;
    return error.TestExpectedSchema;
}

test "missing named schema returns TestExpectedSchema" {
    try testing.expectError(error.TestExpectedSchema, schemaType(&.{}, "Other"));
}

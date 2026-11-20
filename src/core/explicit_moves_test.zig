//! Core owns named move markers and the ownership of const aliases.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const report = std.debug.print;

fn accepted(a: std.mem.Allocator, source: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        report("{s}: {s} at {d}\n", .{ failure.code, failure.message, failure.span.start });
        return err;
    };
}

fn repaired(a: std.mem.Allocator, source: []const u8, rule: language.ownership_rules.Rule, before: []const u8, after: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    const edit = edits[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const expected = try std.mem.replaceOwned(u8, a, source, before, after);
    try std.testing.expectEqualStrings(expected, fixed);
    try accepted(a, fixed);
}

fn refused(a: std.mem.Allocator, source: []const u8, code: []const u8, rule: language.ownership_rules.Rule) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
}

fn withWritebackKey(a: std.mem.Allocator, program: language.typed.Program, key: language.typed.NodeId) !language.typed.Program {
    const nodes = try a.dupe(language.typed.Node, program.nodes);
    const changed = for (nodes) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .write) continue;
        const arguments = try a.dupe(language.typed.NodeId, node.data.buffer_operation.arguments);
        arguments[0] = key;
        node.data.buffer_operation.arguments = arguments;
        break true;
    } else false;
    try std.testing.expect(changed);
    var rewritten = program;
    rewritten.nodes = nodes;
    return rewritten;
}

fn slotInitializer(program: language.typed.Program, function: language.typed.Function, name: []const u8) !language.typed.NodeId {
    for (program.statements) |statement| {
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        if (std.mem.eql(u8, function.scope.locals[@backingInt(store.slot)].name, name)) return store.value;
    }
    return error.TestUnexpectedResult;
}

const MarkerEdit = struct { rule: language.ownership_rules.Rule, before: []const u8, after: []const u8 };

fn repairedSequence(a: std.mem.Allocator, source: []const u8, changes: []const MarkerEdit) !void {
    var current = source;
    for (changes) |change| {
        const unit = try support.checkSource(a, current);
        try std.testing.expect(unit.passed);
        var failure: ownership.Failure = .{};
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
        try std.testing.expectEqual(change.rule, failure.rule.?);
        try std.testing.expect(failure.repair == .explicit_fix);
        try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
        const edit = failure.repair.explicit_fix[0];
        const fixed = try std.mem.concat(a, u8, &.{ current[0..edit.span.start], edit.text, current[edit.span.end..] });
        const expected = try std.mem.replaceOwned(u8, a, current, change.before, change.after);
        try std.testing.expectEqualStrings(expected, fixed);
        current = fixed;
    }
    try accepted(a, current);
}

fn constEscapeRepair(a: std.mem.Allocator, source: []const u8, copied: bool) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B9, failure.rule.?);
    try std.testing.expect(failure.repair == .none);
    try std.testing.expectEqual(copied, failure.copy.span != null);
}

test "O4 explicit moves insert markers at stores constructors and nested return operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const setup =
        \\record Box:
        \\    items: int[]
        \\record Outer:
        \\    box: Box
        \\
    ;
    const cases = [_]struct { body: []const u8, before: []const u8, after: []const u8 }{
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut moved = values
        \\    moved = copy(moved)
        \\    return moved[0]
        , .before = "= values", .after = "= own values" },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut moved = Box(items=values)
        \\    moved = copy(moved)
        \\    return moved.items[0]
        , .before = "items=values", .after = "items=own values" },
        .{
            .body =
            // A list that also takes a fresh element owns its elements; one that only lends them borrows `values` (RB2).
            \\func main() -> int:
            \\    const values = [1]
            \\    mut moved = [values]
            \\    append(mut moved, [2])
            \\    return moved[0][0]
            ,
            .before = "[values]",
            .after = "[own values]",
        },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut box = Box(items=[])
        \\    box.items = values
        \\    return box.items[0]
        , .before = "box.items = values", .after = "box.items = own values" },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut outer = Outer(box=Box(items=[]))
        \\    outer.box.items = values
        \\    return outer.box.items[0]
        , .before = "outer.box.items = values", .after = "outer.box.items = own values" },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut boxes: FixedArray[Box, 1] = FixedArray[Box, 1]([Box(items=[])])
        \\    boxes[0].items = values
        \\    return boxes[0].items[0]
        , .before = "boxes[0].items = values", .after = "boxes[0].items = own values" },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut rows: int[][] = [[]]
        \\    rows[0] = values
        \\    return rows[0][0]
        , .before = "rows[0] = values", .after = "rows[0] = own values" },
        .{ .body =
        \\func main() -> int:
        \\    const values = [1]
        \\    mut mapping: dict[str, int[]] = {}
        \\    mapping["kept"] = values
        \\    mapping["fresh"] = [2]
        \\    return mapping["kept"][0]
        , .before = "mapping[\"kept\"] = values", .after = "mapping[\"kept\"] = own values" },
        .{ .body =
        \\func result(own values: int[]) -> int[]?:
        \\    return Some(values)
        \\func main() -> int:
        \\    match result([1]):
        \\        case Some(values):
        \\            return values[0]
        \\        case None:
        \\            return 0
        , .before = "return Some(values)", .after = "return Some(own values)" },
    };
    for (cases) |case| try repaired(a, try std.mem.concat(a, u8, &.{ setup, case.body }), .B2, case.before, case.after);
}

test "O4 dictionary field writeback reads its lookup key while insertion transfers it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const setup =
        \\record Box:
        \\    items: int[]
        \\
    ;
    try accepted(a, setup ++
        \\func main() -> int:
        \\    const key = "key-" + str(1)
        \\    mut mapping = {"key-1": Box(items=[1])}
        \\    const source = [2]
        \\    mapping[key].items = own source
        \\    return len(key) + mapping[key].items[0]
    );
    try accepted(a,
        \\record Counter:
        \\    value: int
        \\func change(mut mapping: dict[str, Counter], key: str) -> int:
        \\    mapping[key].value = 7
        \\    return len(key)
        \\func main() -> int:
        \\    const key = "key-" + str(1)
        \\    mut mapping = {"key-1": Counter(value=1)}
        \\    return change(mut mapping, key) + mapping[key].value
    );
    try repaired(a, setup ++
        \\func main() -> int:
        \\    const key = "key-" + str(1)
        \\    mut mapping = {"key-1": Box(items=[1])}
        \\    const source = [2]
        \\    mapping[key].items = source
        \\    return len(key) + mapping[key].items[0]
    , .B2, "mapping[key].items = source", "mapping[key].items = own source");
    try repaired(a, setup ++
        \\func main() -> int:
        \\    const key = "key-" + str(1)
        \\    mut mapping = {"key-1": Box(items=[1])}
        \\    const source = [2]
        \\    mapping[own key].items = own source
        \\    return len(key) + mapping[key].items[0]
    , .W2, "mapping[own key]", "mapping[key]");
    // A store with a key written as a place borrows it and copies it only when it is new, so no marker is required.
    try accepted(a, setup ++
        \\func main() -> int:
        \\    const key = "key-" + str(1)
        \\    mut mapping: dict[str, Box] = {}
        \\    const source = Box(items=[2])
        \\    mapping[key] = own source
        \\    return mapping["key-1"].items[0] + len(key)
    );
    try refused(a, setup ++
        \\func main() -> int:
        \\    mut mapping = {0: Box(items=[1]), 1: Box(items=[2])}
        \\    mapping[0] = mapping[1]
        \\    return mapping[0].items[0]
    , "E_SINGLE_OWNER_BORROW", .B7);
    try refused(a, setup ++
        \\func main() -> int:
        \\    mut mapping = {0: Box(items=[1])}
        \\    const alias = mapping[0]
        \\    mut escaped = own alias
        \\    return escaped.items[0]
    , "E_OWN_MARKER", .B9);
    try refused(a, setup ++
        \\func change(mut mapping: dict[str, Box]) -> str:
        \\    mapping["other"] = Box(items=[])
        \\    return "key-1"
        \\func main() -> int:
        \\    mut mapping = {"key-1": Box(items=[1])}
        \\    const source = [2]
        \\    mapping[change(mut mapping)].items = own source
        \\    return mapping["key-1"].items[0]
    , "E_SINGLE_OWNER_OVERLAP", .R2);
}

test "O4 dictionary field writeback requires the exact saved lookup key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\record Box:
        \\    items: int[]
        \\func main() -> int:
        \\    mut mapping = {0: Box(items=[2]), 1: Box(items=[3])}
        \\    const source = [4]
        \\    mapping[0].items = own source
        \\    return mapping[0].items[0]
    );
    try std.testing.expect(unit.passed);
    var program = unit.program.?;
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, program, unit.src.?, &failure);
    const other_key: language.typed.NodeId = for (program.nodes, 0..) |node, index| {
        if (node.data == .integer and node.data.integer == 1) break @fromBackingInt(index);
    } else return error.TestUnexpectedResult;
    program = try withWritebackKey(a, program, other_key);
    failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, program, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R2, failure.rule.?);
}

test "O4 explicit moves remove scalar fresh and bare return markers with applied repairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a,
        \\func main() -> int:
        \\    const scalar = 1
        \\    const alias = own scalar
        \\    return alias
    , .B2, "own scalar", "scalar");
    try repaired(a,
        \\func fresh() -> int[]:
        \\    return [1]
        \\func main() -> int:
        \\    const values = own fresh()
        \\    return values[0]
    , .B2, "own fresh()", "fresh()");
    try repaired(a,
        \\func main() -> int:
        \\    const count = 1 + 2
        \\    return (own count) + 3
    , .B2, "own count", "count");
    try repaired(a,
        \\func main() -> int:
        \\    const count = 1
        \\    return (own count)
    , .B2, "own count", "count");
    try repaired(a,
        \\func main() -> int:
        \\    const count = 1
        \\    return (
        \\        # Preserve the grouped expression and its comment.
        \\        own count
        \\    )
    , .B2, "own count", "count");
    try repaired(a,
        \\func result(own values: int[]) -> int[] fails str:
        \\    return own values
        \\func main() -> int:
        \\    match result([1]):
        \\        case Ok(values):
        \\            return values[0]
        \\        case Err(_):
        \\            return 0
    , .B2, "return own values", "return values");
}

test "O4 const aliases borrow bare owners and own parameters until their last read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func inspect(own values: int[]) -> int:
        \\    const alias = values
        \\    return alias[0] + values[0]
        \\func main() -> int:
        \\    mut values = [1]
        \\    const alias = values
        \\    const head = alias[0]
        \\    append(mut values, 2)
        \\    return head + inspect([3]) + len(values)
    );
    try accepted(a,
        \\func read(source: int[]) -> int[] from source:
        \\    const alias = source
        \\    return alias
        \\func main() -> int:
        \\    const values = [1]
        \\    return len(read(values))
    );
    try refused(a,
        \\func main() -> int:
        \\    mut values = [1]
        \\    const alias = values
        \\    append(mut values, 2)
        \\    return len(alias)
    , "E_SINGLE_OWNER_OVERLAP", .R2);
}

test "O4 const alias escapes repair the initializer instead of transferring a borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a,
        \\func result(own source: int[]) -> int[]:
        \\    const alias = source
        \\    return alias
        \\func main() -> int:
        \\    return len(result([1]))
    , .B9, "alias = source", "alias = own source");
    try repaired(a,
        \\func main() -> int:
        \\    const source = [1]
        \\    const alias = source
        \\    mut moved = own alias
        \\    return moved[0]
    , .B9, "alias = source", "alias = own source");
}

test "O4 probeBindingOwn progresses through other missing markers with a complete joint proof" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repairedSequence(a,
        \\func main() -> int:
        \\    mut first_rows: int[][] = []
        \\    for i in range(2):
        \\        mut first = [i]
        \\        const first_alias = first
        \\        append(mut first_rows, own first_alias)
        \\    mut first_moved = first_rows
        \\    first_moved = copy(first_moved)
        \\    mut second_rows: int[][] = []
        \\    for i in range(2):
        \\        mut second = [i]
        \\        const second_alias = second
        \\        append(mut second_rows, own second_alias)
        \\    mut second_moved = second_rows
        \\    second_moved = copy(second_moved)
        \\    return first_moved[0][0] + second_moved[0][0]
    , &.{
        .{ .rule = .B9, .before = "first_alias = first", .after = "first_alias = own first" },
        .{ .rule = .B2, .before = "first_moved = first_rows", .after = "first_moved = own first_rows" },
        .{ .rule = .B9, .before = "second_alias = second", .after = "second_alias = own second" },
        .{ .rule = .B2, .before = "second_moved = second_rows", .after = "second_moved = own second_rows" },
    });
    try repairedSequence(a,
        \\func main() -> int:
        \\    const source = [1]
        \\    const first = source
        \\    const second = first
        \\    mut kept = own second
        \\    return kept[0]
    , &.{
        .{ .rule = .B9, .before = "second = first", .after = "second = own first" },
        .{ .rule = .B9, .before = "first = source", .after = "first = own source" },
    });
}

test "O4 const initializer joint proofs retain owner uses and declared return contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try constEscapeRepair(a,
        \\func main() -> int:
        \\    const source = [1]
        \\    const alias = source
        \\    const count = len(source)
        \\    mut kept = own alias
        \\    return count + len(kept)
    , true);
    try constEscapeRepair(a,
        \\func result(mut source: int[]) -> int[] from source:
        \\    const alias = source
        \\    mut kept = own alias
        \\    return kept
        \\func main() -> int:
        \\    return 0
    , false);
}

test "O4 deferred const joins read fresh and borrowed alternatives until their last use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func fresh() -> int[]:
        \\    return [3, 4, 5]
        \\func measure(take: bool) -> int:
        \\    mut owner = [1, 2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = owner
        \\    else:
        \\        selected = fresh()
        \\    const count = len(selected)
        \\    append(mut owner, 9)
        \\    return count + len(owner)
        \\func main() -> int:
        \\    return measure(True) + measure(False)
    );
    try accepted(a,
        \\func fresh() -> int[]:
        \\    return [3, 4, 5]
        \\func measure(take: bool) -> int:
        \\    mut owner = [1, 2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = fresh()
        \\    else:
        \\        selected = owner
        \\    const count = len(selected)
        \\    append(mut owner, 9)
        \\    return count + len(owner)
        \\func main() -> int:
        \\    return measure(True) + measure(False)
    );
    try accepted(a,
        \\func measure(take: bool) -> int:
        \\    mut left = [1]
        \\    mut right = [2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = left
        \\    else:
        \\        selected = right
        \\    const count = len(selected)
        \\    append(mut left, 3)
        \\    append(mut right, 4)
        \\    return count + len(left) + len(right)
        \\func main() -> int:
        \\    return measure(True) + measure(False)
    );
    try accepted(a,
        \\func measure(take: bool) -> int:
        \\    const selected: int[]
        \\    if take:
        \\        const local = [1, 2]
        \\        selected = local
        \\    else:
        \\        selected = [3, 4, 5]
        \\    return len(selected)
        \\func main() -> int:
        \\    return measure(True) + measure(False)
    );
    try accepted(a,
        \\func choose(left: int[], right: int[], take: bool) -> int[] from left, right:
        \\    const selected: int[]
        \\    if take:
        \\        selected = left
        \\    else:
        \\        selected = right
        \\    return selected
        \\func main() -> int:
        \\    return len(choose([1], [2], True)) + len(choose([1], [2], False))
    );
    try accepted(a,
        \\func measure(flag: bool, inner: bool) -> int:
        \\    mut owner = [1]
        \\    const alias = owner
        \\    const count = len(alias)
        \\    if flag:
        \\        if inner:
        \\            _ = 0
        \\        append(mut owner, 2)
        \\    return count
        \\func main() -> int:
        \\    return measure(True, True) + measure(True, False) + measure(False, False)
    );
}

test "O4 deferred const joins repair actual borrowed initializers in either arm" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a,
        \\func choose(take: bool) -> int[]:
        \\    const owner = [1, 2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = (owner)
        \\    else:
        \\        selected = [3, 4]
        \\    return selected
        \\func main() -> int:
        \\    return len(choose(True)) + len(choose(False))
    , .B9, "selected = (owner)", "selected = (own owner)");
    try repaired(a,
        \\func choose(take: bool) -> int[]:
        \\    const owner = [1, 2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = [3, 4]
        \\    else:
        \\        selected = owner
        \\    return selected
        \\func main() -> int:
        \\    return len(choose(True)) + len(choose(False))
    , .B9, "selected = owner", "selected = own owner");
    try repairedSequence(a,
        \\func choose(take: bool) -> int[]:
        \\    const left = [1]
        \\    const right = [2]
        \\    const selected: int[]
        \\    if take:
        \\        selected = left
        \\    else:
        \\        selected = right
        \\    return selected
        \\func main() -> int:
        \\    return len(choose(True)) + len(choose(False))
    , &.{
        .{ .rule = .B9, .before = "selected = left", .after = "selected = own left" },
        .{ .rule = .B9, .before = "selected = right", .after = "selected = own right" },
    });
}

test "O4 deferred const join loans block changes inside and after the supplying arm" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try refused(a,
        \\func measure(take: bool) -> int:
        \\    mut owner = [1]
        \\    const selected: int[]
        \\    if take:
        \\        selected = owner
        \\    else:
        \\        selected = [2]
        \\    append(mut owner, 9)
        \\    return len(selected)
        \\func main() -> int:
        \\    return measure(True)
    , "E_SINGLE_OWNER_OVERLAP", .R2);
    try refused(a,
        \\func measure(take: bool) -> int:
        \\    mut owner = [1]
        \\    const selected: int[]
        \\    if take:
        \\        selected = owner
        \\        append(mut owner, 9)
        \\    else:
        \\        selected = [2]
        \\    return len(selected)
        \\func main() -> int:
        \\    return measure(True)
    , "E_SINGLE_OWNER_OVERLAP", .R2);
    try refused(a,
        \\func main() -> int:
        \\    const owner = [1]
        \\    mut moved = own owner
        \\    return len(owner) + len(moved)
    , "E_SINGLE_OWNER_MOVED", .B3);
}

test "O4 matchArms restores deferred const loans after removing the match hold" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func measure(option: int?) -> int:
        \\    mut owner = [1]
        \\    const selected: int[]
        \\    match option:
        \\        case Some(_):
        \\            selected = owner
        \\        case None:
        \\            selected = [2, 3]
        \\    const count = len(selected)
        \\    append(mut owner, 9)
        \\    return count + len(owner)
        \\func main() -> int:
        \\    return measure(Some(1)) + measure(None)
    );
    try refused(a,
        \\func measure(option: int?) -> int:
        \\    mut owner = [1]
        \\    const selected: int[]
        \\    match option:
        \\        case Some(_):
        \\            selected = owner
        \\        case None:
        \\            selected = [2, 3]
        \\    append(mut owner, 9)
        \\    return len(selected)
        \\func main() -> int:
        \\    return measure(Some(1))
    , "E_SINGLE_OWNER_OVERLAP", .R2);
    try repaired(a,
        \\func choose(option: int?) -> int[]:
        \\    const owner = [1]
        \\    const selected: int[]
        \\    match option:
        \\        case Some(_):
        \\            selected = owner
        \\        case None:
        \\            selected = [2, 3]
        \\    return selected
        \\func main() -> int:
        \\    return len(choose(Some(1))) + len(choose(None))
    , .B9, "selected = owner", "selected = own owner");
}

test "O4 branch merges retain persistent R7 iteration loans alongside const joins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func main() -> int:
        \\    const outer = [1, 2]
        \\    mut inner = [3, 4]
        \\    mut total = 0
        \\    for value in outer:
        \\        for item in inner:
        \\            total += item
        \\        append(mut inner, value)
        \\    return total
    );
    try refused(a,
        \\func main() -> int:
        \\    mut values = [1]
        \\    for value in values:
        \\        append(mut values, value)
        \\    return len(values)
    , "E_SINGLE_OWNER_OVERLAP", .R7);
    try refused(a,
        \\func mutate(flag: bool) -> int:
        \\    mut values = [1]
        \\    for value in values:
        \\        if flag:
        \\            append(mut values, value)
        \\        else:
        \\            _ = value
        \\    return len(values)
        \\func main() -> int:
        \\    return mutate(True)
    , "E_SINGLE_OWNER_OVERLAP", .R7);
    try refused(a,
        \\func mutate(option: int?) -> int:
        \\    mut values = [1]
        \\    for value in values:
        \\        match option:
        \\            case Some(_):
        \\                append(mut values, value)
        \\            case None:
        \\                _ = value
        \\    return len(values)
        \\func main() -> int:
        \\    return mutate(Some(1))
    , "E_SINGLE_OWNER_OVERLAP", .R7);
}

test "O4 const aliases of named iteration and pattern places retain their owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func inspect(rows: int[][]) -> int:
        \\    for row in rows:
        \\        const alias = row
        \\        return alias[0]
        \\    return 0
        \\func main() -> int:
        \\    return inspect([[1]])
    );
    try accepted(a,
        \\func main() -> int:
        \\    mut source: int[][]? = Some([[1]])
        \\    mut count = 0
        \\    match source:
        \\        case Some(rows):
        \\            const alias = rows
        \\            count = len(alias)
        \\        case None:
        \\            count = 0
        \\    source = None
        \\    return count
    );
    try refused(a,
        \\func main() -> int:
        \\    mut source: int[][]? = Some([[1]])
        \\    match source:
        \\        case Some(rows):
        \\            const alias = rows
        \\            source = None
        \\            return len(alias)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_OVERLAP", .X1);
}

test "O4 const aliases of move-only file owners borrow rather than transfer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a,
        \\func keep(own file: File) -> File:
        \\    const alias = file
        \\    return file
        \\func main() -> int:
        \\    return 0
    );
    try repaired(a,
        \\func keep(own file: File) -> File:
        \\    const alias = file
        \\    return alias
        \\func main() -> int:
        \\    return 0
    , .B9, "alias = file", "alias = own file");
}

test "O4 own markers on a fresh call field remain misplaced in intrinsic receivers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const declarations =
        \\record Box:
        \\    items: int[]
        \\func make() -> Box:
        \\    return Box(items=[1])
        \\
    ;
    try repaired(a, declarations ++
        \\func main() -> int:
        \\    return len(own make().items)
    , .B2, "own make().items", "make().items");
    try repaired(a, declarations ++
        \\func main() -> int:
        \\    const kept = copy(own make().items)
        \\    return kept[0]
    , .B2, "own make().items", "make().items");
}

test "O4 borrowed return analysis checks markers on every peeled wrapper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a,
        \\func result(values: int[]) -> int[]? from values:
        \\    return own Some(values)
        \\func main() -> int:
        \\    return 0
    , .B2, "own Some(values)", "Some(values)");
    try repaired(a,
        \\func result(values: int[]) -> int[]?? from values:
        \\    return Some(own Some(values))
        \\func main() -> int:
        \\    return 0
    , .B2, "own Some(values)", "Some(values)");
}

test "O4 carrier field returns require their own marker and consume every sibling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const declarations =
        \\record Box:
        \\    left: int[]
        \\    right: int[]
        \\
    ;
    try repaired(a, declarations ++
        \\func result(own box: Box) -> int[]:
        \\    return box.left
        \\func main() -> int:
        \\    return len(result(Box(left=[1], right=[2])))
    , .B2, "return box.left", "return own box.left");
    try refused(a, declarations ++
        \\func main() -> int:
        \\    const box = Box(left=[1], right=[2])
        \\    const left = own box.left
        \\    return len(left) + len(box.right)
    , "E_SINGLE_OWNER_MOVED", .B3);
}

test "O4 field RHS staging consumes its marked source before the destination refresh" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try refused(arena.allocator(),
        \\record Box:
        \\    items: int[]
        \\func main() -> int:
        \\    const source = [1]
        \\    mut box = Box(items=[])
        \\    box.items = own source
        \\    return len(source)
    , "E_SINGLE_OWNER_MOVED", .B3);
}

test "O4 generic carrier fields use symbolic type dependency instead of concrete equality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const declarations =
        \\record Holder[T]:
        \\    value: T
        \\    count: int
        \\
    ;
    try accepted(a, declarations ++
        \\func extract[T](own holder: Holder[T]) -> T:
        \\    return own holder.value
        \\func main() -> int:
        \\    const number = extract[int](Holder[int](value=3, count=7))
        \\    const text = extract[str](Holder[str](value="text", count=7))
        \\    return number + len(text)
    );
    try refused(a, declarations ++
        \\func extract[T](own holder: Holder[T]) -> int:
        \\    return own holder.count
        \\func main() -> int:
        \\    return extract[int](Holder[int](value=3, count=7))
    , "E_OWN_MARKER", .B2);
}

test "O4 constBorrowPlace preserves canonical receiver reads and rejects arbitrary hidden results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        \\func main() -> int:
        \\    const source = [[1]]
        \\    const alias = source[0]
        \\    return alias[0]
    );
    try std.testing.expect(unit.passed);
    var program = unit.program.?;
    const function = program.functions[@backingInt(program.main)];
    const source: language.typed.LocalId = for (function.scope.locals, 0..) |local, index| {
        if (std.mem.eql(u8, local.name, "source")) break @fromBackingInt(index);
    } else return error.TestUnexpectedResult;
    const initializer = try slotInitializer(program, function, "alias");
    try std.testing.expectEqual(source, ownership.constBorrowPlace(program, function, initializer).?);
    const wrapper = program.nodes[@backingInt(initializer)].data.block_value;
    const setup = program.statements[@backingInt(wrapper.body)].data.block;
    const receiver = program.statements[@backingInt(setup[0])].data.initialize;
    try std.testing.expectEqual(source, ownership.constBorrowPlace(program, function, receiver.value).?);
    // The same staging body may produce its hidden owner rather than read an
    // element. That is an ordinary result, not the canonical source-place form.
    const nodes = try a.dupe(language.typed.Node, program.nodes);
    nodes[@backingInt(wrapper.value)] = .{
        .ty = function.scope.locals[@backingInt(receiver.slot)].ty,
        .span = nodes[@backingInt(wrapper.value)].span,
        .data = .{ .local = receiver.slot },
    };
    nodes[@backingInt(initializer)].ty = nodes[@backingInt(wrapper.value)].ty;
    program.nodes = nodes;
    try std.testing.expect(ownership.constBorrowPlace(program, function, initializer) == null);
}

const f2_grouped_records =
    \\record Inner:
    \\    items: int[]
    \\record Box:
    \\    inner: Inner
    \\    items: int[]
    \\    name: str
    \\
;

test "F2 marker insertion repairs grouped bases without transferring only the carrier prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 missing marker on a grouped field base.
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    mut values = (owner).items
        \\    values = copy(values)
        \\    return values[0]
    , .B2, "(owner).items", "(own owner.items)");
    try repaired(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 missing marker on a doubly grouped field base.
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    mut values = ((owner)).items
        \\    values = copy(values)
        \\    return values[0]
    , .B2, "((owner)).items", "(own owner.items)");
    try repaired(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 missing marker on nested grouped projections.
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    mut values = ((owner).inner).items
        \\    values = copy(values)
        \\    return values[0]
    , .B2, "((owner).inner).items", "(own owner.inner.items)");
    try repaired(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 owning argument from a grouped field base.
        \\func width(own items: int[]) -> int:
        \\    return len(items)
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    return width((owner).items)
    , .W2, "(owner).items", "(own owner.items)");
    try repaired(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 returned grouped field without its marker.
        \\func my_take(own owner: Box) -> int[]:
        \\    return ((owner)).items
        \\func main() -> int:
        \\    return 0
    , .B2, "((owner)).items", "(own owner.items)");
}

test "F2 marker insertion repairs grouped const origins and still consumes the complete record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try repaired(a,
        // migrate-embedded: skip intentional F2 missing const-initializer transfer inside grouping.
        \\func my_take() -> int[]:
        \\    const owner = [1]
        \\    const alias = ((owner))
        \\    return alias
        \\func main() -> int:
        \\    return 0
    , .B9, "((owner))", "((own owner))");
    try refused(a, f2_grouped_records ++
        // migrate-embedded: skip intentional F2 carrier is unavailable after the corrected field move.
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    mut values = (own owner.items)
        \\    return values[0] + len(owner.name)
    , "E_SINGLE_OWNER_MOVED", .B3);
}

test "F2 marker insertion reparses a multiline grouped field and preserves its comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try repaired(arena.allocator(), f2_grouped_records ++
        // migrate-embedded: skip intentional F2 missing marker around a commented grouped field.
        \\func main() -> int:
        \\    const owner = Box(inner=Inner(items=[1]), items=[2], name="done")
        \\    mut values = (
        \\        # Keep (this) comment.
        \\        owner
        \\    ).items
        \\    values = copy(values)
        \\    return values[0]
    , .B2, "(\n        # Keep (this) comment.\n        owner\n    ).items", "(own \n        # Keep (this) comment.\n        owner\n    .items)");
}

test "F5 fail shares bare-name transfer and field carrier rules with return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a, "func parse(text: str) -> int fails str:\n" ++
        "    mut message = \"bad: \" + text\n" ++
        "    if len(text) == 0:\n" ++
        "        fail message\n" ++
        "    return 1\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
    try repaired(a, "func parse(text: str) -> int fails str:\n" ++
        "    mut message = \"bad: \" + text\n" ++
        "    if len(text) == 0:\n" ++
        "        fail own message\n" ++
        "    return 1\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", .B2, "fail own message", "fail message");
    try accepted(a, "record Error:\n" ++
        "    text: str\n" ++
        "func parse() -> int fails str:\n" ++
        "    const error = Error(text=\"bad\" + str(1))\n" ++
        "    fail own error.text\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
}

const F6Repair = struct {
    before: []const u8,
    after: []const u8,
    code: []const u8 = "E_OWN_MARKER",
    rule: language.ownership_rules.Rule = .W2,
    copy: bool = false,
};

fn f6Repair(a: std.mem.Allocator, source: []const u8, wanted: F6Repair) !void {
    const unit = try support.checkSource(a, source);
    if (!unit.passed) for (unit.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(wanted.rule, failure.rule.?);
    try std.testing.expectEqual(wanted.copy, failure.copy.span != null);
    var edits: []const language.diagnostic.Edit = undefined;
    if (wanted.copy) {
        try std.testing.expect(failure.repair == .none);
        const span = failure.copy.span.?;
        edits = try a.dupe(language.diagnostic.Edit, &.{
            .{ .span = .{ .start = span.start, .end = span.start }, .text = "copy(" },
            .{ .span = .{ .start = span.end, .end = span.end }, .text = ")" },
        });
    } else {
        try std.testing.expect(failure.repair == .explicit_fix);
        edits = failure.repair.explicit_fix;
    }
    const fixed = try f6ApplyEdits(a, source, edits);
    const expected = try std.mem.replaceOwned(u8, a, source, wanted.before, wanted.after);
    try std.testing.expectEqualStrings(expected, fixed);
    try accepted(a, fixed);
}

fn f6ApplyEdits(a: std.mem.Allocator, source: []const u8, edits: []const language.diagnostic.Edit) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    for (edits) |edit| {
        try std.testing.expect(edit.span.start >= offset);
        try out.appendSlice(a, source[offset..edit.span.start]);
        try out.appendSlice(a, edit.text);
        offset = edit.span.end;
    }
    try out.appendSlice(a, source[offset..]);
    return out.toOwnedSlice(a);
}

const f6_take =
    \\func my_take(own value: int[]) -> int:
    \\    return len(value)
    \\
;

const f6_box =
    \\record Box:
    \\    items: int[]
    \\    name: str
    \\
;

test "F6 marker repair copies later binding reads including the same expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 missing move marker.
        \\func main() -> int:
        \\    const values = [1]
        \\    const size = my_take(values)
        \\    return size + len(values)
    , .{ .before = "my_take(values)", .after = "my_take(copy(values))", .copy = true });
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 missing move marker before a later operand.
        \\func main() -> int:
        \\    const values = [1]
        \\    return my_take(values) + len(values)
    , .{ .before = "my_take(values)", .after = "my_take(copy(values))", .copy = true });
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 missing move marker on the final use.
        \\func main() -> int:
        \\    const values = [1]
        \\    return my_take(values)
    , .{ .before = "my_take(values)", .after = "my_take(own values)" });
}

test "F6 marker repair preserves later sibling and enclosing block reads of carriers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6Repair(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 missing field move marker.
        \\func main() -> int:
        \\    const box = Box(items=[1], name="kept")
        \\    const size = my_take(box.items)
        \\    return size + len(box.name)
    , .{ .before = "my_take(box.items)", .after = "my_take(copy(box.items))", .copy = true });
    try f6Repair(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 missing grouped field move marker.
        \\func main() -> int:
        \\    const box = Box(items=[1], name="kept")
        \\    const size = my_take((box).items)
        \\    return size + len(box.name)
    , .{ .before = "my_take((box).items)", .after = "my_take(copy((box).items))", .copy = true });
    try f6Repair(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 field move with a read outside the nested block.
        \\func inspect(flag: bool) -> int:
        \\    const box = Box(items=[1], name="kept")
        \\    if flag:
        \\        _ = my_take(box.items)
        \\    return len(box.name)
        \\func main() -> int:
        \\    return inspect(True)
    , .{ .before = "my_take(box.items)", .after = "my_take(copy(box.items))", .copy = true });
    try f6Repair(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 last-use field move without a marker.
        \\func main() -> int:
        \\    const box = Box(items=[1], name="done")
        \\    return my_take(box.items)
    , .{ .before = "my_take(box.items)", .after = "my_take(own box.items)" });
}

test "F6 generic repairs follow the moved occurrence type dependency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6Repair(a,
        // migrate-embedded: skip intentional F6 concrete move inside a generic body.
        \\func count[T](values: T[]) -> int:
        \\    mut gathered: int[] = []
        \\    append(mut gathered, 1)
        \\    mut order = gathered
        \\    order = copy(order)
        \\    return len(order) + len(values)
        \\func main() -> int:
        \\    return count([1])
    , .{ .before = "order = gathered", .after = "order = own gathered", .rule = .B2 });
    try f6Repair(a,
        // migrate-embedded: skip intentional F6 concrete const escape inside a generic body.
        \\func count[T](value: T) -> int:
        \\    const gathered: int[] = [1]
        \\    const alias = gathered
        \\    mut order = own alias
        \\    return len(order)
        \\func main() -> int:
        \\    return count(1)
    , .{ .before = "alias = gathered", .after = "alias = own gathered", .rule = .B9 });
    try f6Repair(a,
        // migrate-embedded: skip intentional F6 generic const escape with a later owner read.
        \\func count[T](value: T) -> int:
        \\    const gathered: int[] = [1]
        \\    const alias = gathered
        \\    mut order = own alias
        \\    return len(order) + len(gathered)
        \\func main() -> int:
        \\    return count(1)
    , .{ .before = "alias = gathered", .after = "alias = copy(gathered)", .rule = .B9, .copy = true });
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 concrete move with later reads inside a generic body.
        \\func count[T](value: T) -> int:
        \\    const gathered: int[] = [1]
        \\    const size = my_take(gathered)
        \\    return size + len(gathered)
        \\func main() -> int:
        \\    return count(1)
    , .{ .before = "my_take(gathered)", .after = "my_take(copy(gathered))", .copy = true });
    try f6Repair(a,
        // migrate-embedded: skip intentional F6 concrete scalar marker inside a generic body.
        \\func count[T](value: T) -> int:
        \\    const fixed = 3
        \\    const moved = own fixed
        \\    return moved
        \\func main() -> int:
        \\    return count(1)
    , .{ .before = "own fixed", .after = "fixed", .rule = .B2 });
}

fn f6ProjectionRefusal(a: std.mem.Allocator, source: []const u8, rule: language.ownership_rules.Rule, message: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, message) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "prototype") == null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "fresh") == null);
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 2), failure.repair.explicit_fix.len);
    const fixed = try f6ApplyEdits(a, source, failure.repair.explicit_fix);
    try accepted(a, fixed);
}

test "F6 marked projections report the actual element call and parameter borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6ProjectionRefusal(a, f6_box ++
        // migrate-embedded: skip intentional F6 move from an element.
        \\func my_take(xs: Box[]) -> int:
        \\    const items = own xs[0].items
        \\    return len(items)
        \\func main() -> int:
        \\    return 0
    , .B7, "plain parameter `xs`");
    try f6ProjectionRefusal(a, f6_box ++
        // migrate-embedded: skip intentional F6 move from a borrowed result.
        \\func pick(box: Box) -> Box from box:
        \\    return box
        \\func main() -> int:
        \\    const box = Box(items=[1], name="kept")
        \\    const name = own pick(box).name
        \\    return len(name)
    , .R3, "lent by the local `box`");
    try f6ProjectionRefusal(a, f6_box ++
        // migrate-embedded: skip intentional F6 return of a mut parameter field.
        \\func my_take(mut box: Box) -> int[]:
        \\    return own box.items
        \\func main() -> int:
        \\    return 0
    , .M1, "`mut` parameter `box`");
    try f6ProjectionRefusal(a, f6_box ++
        // migrate-embedded: skip intentional F6 move from a plain borrowed record.
        \\func my_take(box: Box) -> int:
        \\    const items = own box.items
        \\    return len(items)
        \\func main() -> int:
        \\    return 0
    , .B8, "plain parameter `box`");
}

test "F6 repeated move-only values receive neither a destructive marker nor a copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a,
        // migrate-embedded: skip intentional F6 missing transfer of a repeated resource.
        \\func consume(own file: File) -> int:
        \\    return 1
        \\func repeat(own file: File) -> int:
        \\    const first = consume(file)
        \\    return first + consume(file)
        \\func main() -> int:
        \\    return 0
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.W2, failure.rule.?);
    try std.testing.expect(failure.repair == .none);
    try std.testing.expect(failure.copy.span == null);
}

fn f6BorrowedReturnRepair(a: std.mem.Allocator, source: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.M1, failure.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "remove `own` to return the declared borrow") != null);
    try std.testing.expect(failure.copy.span == null);
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
    try std.testing.expectEqualStrings("", failure.repair.explicit_fix[0].text);
    const fixed = try f6ApplyEdits(a, source, failure.repair.explicit_fix);
    const expected = try std.mem.replaceOwned(u8, a, source, "own box.items", "box.items");
    try std.testing.expectEqualStrings(expected, fixed);
    try accepted(a, fixed);
}

test "F6 M1 marked field returns preserve declared borrows through direct and Some returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6BorrowedReturnRepair(a, f6_box ++
        // migrate-embedded: skip intentional F6 marked field under a borrowed return contract.
        \\func my_take(mut box: Box) -> int[] from box:
        \\    return own box.items
        \\func main() -> int:
        \\    return 0
    );
    try f6BorrowedReturnRepair(a, f6_box ++
        // migrate-embedded: skip intentional F6 marked Some payload under a borrowed return contract.
        \\func my_take(mut box: Box) -> int[]? from box:
        \\    return Some(own box.items)
        \\func main() -> int:
        \\    return 0
    );
}

fn f6M1WithoutRepair(a: std.mem.Allocator, source: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.M1, failure.rule.?);
    try std.testing.expect(failure.copy.span == null);
    try std.testing.expect(failure.repair == .none);
}

test "F6 M1 marked field repairs require a matching lender and a type-independent occurrence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6M1WithoutRepair(a, f6_box ++
        // migrate-embedded: skip intentional F6 marker whose removal and copy both violate the declared contract.
        \\func my_take(mut box: Box, other: Box) -> int[] from other:
        \\    return own box.items
        \\func main() -> int:
        \\    return 0
    );
    try f6M1WithoutRepair(a,
        // migrate-embedded: skip intentional F6 dependent marked field shared by generic instances.
        \\record GenericBox[T]:
        \\    items: T[]
        \\func my_take[T: copy + storable](mut box: GenericBox[T]) -> T[] from box:
        \\    return own box.items
        \\func main() -> int:
        \\    mut box = GenericBox[int](items=[1])
        \\    const values = my_take[int](mut box)
        \\    return len(values)
    );
}

test "F6 missing move markers distinguish loop-carried owners from owners created per iteration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 repeated transfer of an outer owner.
        \\func main() -> int:
        \\    const values = [1]
        \\    mut total = 0
        \\    for i in range(2):
        \\        total += my_take(values)
        \\    return total
    , .{ .before = "my_take(values)", .after = "my_take(copy(values))", .copy = true });
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 last-use transfer of an owner created each iteration.
        \\func main() -> int:
        \\    mut total = 0
        \\    for i in range(2):
        \\        const values = [i]
        \\        total += my_take(values)
        \\    return total
    , .{ .before = "my_take(values)", .after = "my_take(own values)" });
}

test "F6 M1 checks without source cannot leak a copy around a still-written own marker" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, f6_box ++
        // migrate-embedded: skip intentional F6 marked borrowed return checked without repair source.
        \\func my_take(mut box: Box) -> int[] from box:
        \\    return own box.items
        \\func main() -> int:
        \\    return 0
    );
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, unit.program.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.M1, failure.rule.?);
    try std.testing.expect(failure.copy.span == null);
    try std.testing.expect(failure.repair == .none);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\":") == null);
}

fn f6CopyProofNoRepair(a: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    const unit = try support.checkSource(a, source);
    if (!unit.passed) for (unit.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.copy.span == null);
    try std.testing.expect(failure.repair == .none);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\":") == null);
}

/// FR61: the marker refusal of `source` carries the `own` repair beside the function's other refusal, which it did not cause:
/// with the marker written, that refusal is what the check stops at, after the marker, and the marker's refusal is gone.
fn fr61OwnBeside(a: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.copy.span == null);
    try fr61OwnEdit(failure, unit.src.?.text(failure.span));
    const edit = failure.repair.explicit_fix[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const after = try support.checkSource(a, fixed);
    try std.testing.expect(after.passed);
    var other: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, after.program.?, after.src.?, &other));
    try std.testing.expect(other.span.start > edit.span.start + edit.text.len);
}

/// The repair of marker refusal `failure` is the one edit that writes `own ` before `marked`.
fn fr61OwnEdit(failure: ownership.Failure, marked: []const u8) !void {
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
    const edit = failure.repair.explicit_fix[0];
    try std.testing.expectEqualStrings("own ", edit.text);
    try std.testing.expectEqual(failure.span.start, edit.span.start);
    try std.testing.expectEqual(edit.span.start, edit.span.end);
    try std.testing.expect(marked.len != 0);
}

fn f6CopyProofRounds(a: std.mem.Allocator, source: []const u8, changes: []const F6Repair) !void {
    var current = source;
    for (changes) |change| {
        const unit = try support.checkSource(a, current);
        if (!unit.passed) for (unit.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
        try std.testing.expect(unit.passed);
        var failure: ownership.Failure = .{};
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        try std.testing.expectEqualStrings(change.code, failure.code);
        try std.testing.expectEqual(change.rule, failure.rule.?);
        try std.testing.expectEqual(change.copy, failure.copy.span != null or failure.copy.borrowed.len != 0);
        const edits = if (change.copy) copied: {
            try std.testing.expect(failure.repair == .none);
            const spans = if (failure.copy.span) |span| try a.dupe(language.source.Span, &.{span}) else failure.copy.borrowed;
            const copies = try a.alloc(language.diagnostic.Edit, spans.len * 2);
            for (spans, 0..) |span, index| {
                copies[index * 2] = .{ .span = .{ .start = span.start, .end = span.start }, .text = "copy(" };
                copies[index * 2 + 1] = .{ .span = .{ .start = span.end, .end = span.end }, .text = ")" };
            }
            break :copied copies;
        } else fixed: {
            try std.testing.expect(failure.repair == .explicit_fix);
            break :fixed failure.repair.explicit_fix;
        };
        const next = try f6ApplyEdits(a, current, edits);
        try std.testing.expectEqualStrings(try std.mem.replaceOwned(u8, a, current, change.before, change.after), next);
        current = next;
    }
    try accepted(a, current);
}

test "F6 copy proof withholds captured copy calls for missing and borrowed markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional F6 missing marker with a shadowed copy function.
        \\func copy(values: int[]) -> int:
        \\    return len(values)
        \\func main() -> int:
        \\    const values = [1]
        \\    const size = my_take(values)
        \\    return size + len(values)
    , "E_OWN_MARKER");
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional F6 missing marker with a shadowed copy binding.
        \\func size(values: int[]) -> int:
        \\    return len(values)
        \\func main() -> int:
        \\    const copy = size
        \\    const values = [1]
        \\    const count = my_take(values)
        \\    return count + copy(values)
    , "E_OWN_MARKER");
    try f6CopyProofNoRepair(a, f6_box ++
        // migrate-embedded: skip intentional F6 marked borrowed field with a shadowed copy function.
        \\func copy(values: int[]) -> int:
        \\    return len(values)
        \\func inspect(box: Box) -> int:
        \\    const values = own box.items
        \\    return len(values)
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

test "F6 copy proof repairs independent copies and preserves an independent final transfer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 independent missing markers requiring two copies.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const right = my_take(second)
        \\    return left + right + len(first) + len(second)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(copy(first))", .copy = true },
        .{ .before = "my_take(second)", .after = "my_take(copy(second))", .copy = true },
    });
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 final transfer beside an independent copy-required move.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const right = my_take(second)
        \\    return left + right + len(second)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "my_take(second)", .after = "my_take(copy(second))", .copy = true },
    });
}

test "F6 copy proof keeps generic copy requirements available without editing dependent moves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6Repair(a, f6_take ++
        // migrate-embedded: skip intentional F6 fixed-type copy repair in a constrained generic.
        \\func count[T: storable + copy](value: T) -> int:
        \\    const values = [1]
        \\    const size = my_take(values)
        \\    return size + len(values)
        \\func main() -> int:
        \\    return count(1)
    , .{ .before = "my_take(values)", .after = "my_take(copy(values))", .copy = true });
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional F6 independent dependent move that cannot receive a shared copy edit.
        \\func consume[T: copy + storable](own value: T) -> int:
        \\    return 1
        \\func count[T: copy + storable](own value: T) -> int:
        \\    const values = [1]
        \\    const first = my_take(values)
        \\    const second = consume(value)
        \\    return first + second + len(values) + consume(own value)
        \\func main() -> int:
        \\    return count([2])
    , "E_OWN_MARKER");
}

test "F6 copy proof proveRepair does not normalize explicit transfers or resources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional F6 explicit destructive transfer beside a missing marker.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const right = my_take(own second)
        \\    return left + right + len(first) + len(second)
    , "E_OWN_MARKER");
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional F6 resource transfer beside a copy-required move.
        \\func consume(own file: File) -> int:
        \\    return 1
        \\func count(own file: File) -> int:
        \\    const values = [1]
        \\    const first = my_take(values)
        \\    const second = consume(file)
        \\    return first + second + len(values) + consume(own file)
        \\func main() -> int:
        \\    return 0
    , "E_OWN_MARKER");
}

test "F6 copy proof withholds captured copy for a const initializer escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try f6CopyProofNoRepair(arena.allocator(), f6_take ++
        // migrate-embedded: skip intentional F6 borrowed const escape with a shadowed copy function.
        \\func copy(values: int[]) -> int:
        \\    return len(values)
        \\func main() -> int:
        \\    const values = [1]
        \\    const alias = values
        \\    const size = my_take(own alias)
        \\    return size + len(values)
    , "E_OWN_MARKER");
}

test "F6 copy proof normalizes independent field and loop transfers by their moved spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 independent missing field move markers.
        \\func main() -> int:
        \\    const first = Box(items=[1], name="first")
        \\    const second = Box(items=[2], name="second")
        \\    const left = my_take(first.items)
        \\    const right = my_take(second.items)
        \\    return left + right + len(first.name) + len(second.name)
    , &.{
        .{ .before = "my_take(first.items)", .after = "my_take(copy(first.items))", .copy = true },
        .{ .before = "my_take(second.items)", .after = "my_take(copy(second.items))", .copy = true },
    });
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 independent loop-carried missing move markers.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    mut total = 0
        \\    for i in range(2):
        \\        total += my_take(first)
        \\        total += my_take(second)
        \\    return total
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(copy(first))", .copy = true },
        .{ .before = "my_take(second)", .after = "my_take(copy(second))", .copy = true },
    });
}

test "F6 copy proof proveRepair and normalizeRepair change only provisional const initializer transfers into copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 final transfer beside an escaping const alias whose owner is read later.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const alias = second
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept) + len(second)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "alias = second", .after = "alias = copy(second)", .rule = .B9, .copy = true },
        .{ .before = "kept = alias", .after = "kept = own alias", .rule = .B2 },
    });
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 copy beside an escaping const alias whose owner is read later.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const alias = second
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept) + len(first) + len(second)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(copy(first))", .copy = true },
        .{ .before = "alias = second", .after = "alias = copy(second)", .rule = .B9, .copy = true },
        .{ .before = "kept = alias", .after = "kept = own alias", .rule = .B2 },
    });
    try fr61OwnBeside(a, f6_take ++
        // migrate-embedded: skip intentional F6 explicit const transfer invalidating its later owner read.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    const alias = own second
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept) + len(second)
    , "E_OWN_MARKER");
}

test "F6 copy proof normalizeRepair handles field and borrowed call initializers beside a final transfer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 final transfer beside a borrowed field initializer escape.
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = Box(items=[2], name="kept")
        \\    const left = my_take(first)
        \\    const alias = second.items
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept) + len(second.name)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "alias = second.items", .after = "alias = copy(second.items)", .rule = .B9, .copy = true },
        .{ .before = "kept = alias", .after = "kept = own alias", .rule = .B2 },
    });
    try fr61OwnBeside(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 unrelated R3 refusal beside a final transfer; no B9 repair is inferred.
        \\func pick(box: Box) -> int[] from box:
        \\    return box.items
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = Box(items=[2], name="kept")
        \\    const left = my_take(first)
        \\    const alias = pick(second)
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept) + len(second.name)
    , "E_OWN_MARKER");
}

test "F6 copy proof merge preserves the else arm move span without changing availability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = f6_take ++
        // migrate-embedded: skip intentional F6 later read after an unmarked else-only move.
        \\func inspect(flag: bool) -> int:
        \\    const first = [1]
        \\    const second = [2]
        \\    const left = my_take(first)
        \\    mut right = 0
        \\    if flag:
        \\        right = 0
        \\    else:
        \\        right = my_take(second)
        \\    return left + right + len(second)
        \\func main() -> int:
        \\    return inspect(False)
    ;
    try f6CopyProofRounds(a, source, &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "my_take(second)", .after = "my_take(copy(second))", .copy = true },
    });
    const marked_first = try std.mem.replaceOwned(u8, a, source, "my_take(first)", "my_take(own first)");
    const marked = try std.mem.replaceOwned(u8, a, marked_first, "my_take(second)", "my_take(own second)");
    const unit = try support.checkSource(a, marked);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B3, failure.rule.?);
    try std.testing.expectEqualStrings("own second", unit.src.?.text((failure.notes.related orelse return error.TestUnexpectedResult).span));
}

test "F6 copy proof normalizeRepair copies provisional B9 plain and mut parameter borrows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 provisional B9 ownership of a plain borrowed parameter.
        \\func inspect(source: int[]) -> int:
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    const alias = source
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept)
        \\func main() -> int:
        \\    return inspect([2])
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "alias = source", .after = "alias = copy(source)", .rule = .B9, .copy = true },
        .{ .before = "kept = alias", .after = "kept = own alias", .rule = .B2 },
    });
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 provisional B9 ownership of an exclusive borrowed parameter.
        \\func inspect(mut source: int[]) -> int:
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    const alias = source
        \\    mut kept = alias
        \\    kept = copy(kept)
        \\    return left + len(kept)
        \\func main() -> int:
        \\    mut values = [2]
        \\    return inspect(mut values)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "alias = source", .after = "alias = copy(source)", .rule = .B9, .copy = true },
        .{ .before = "kept = alias", .after = "kept = own alias", .rule = .B2 },
    });
}

test "F6 copy proof proveRepair composes final transfers with refused plain and mut stores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (.{ "", "mut " }) |mode| {
        try f6CopyProofRounds(a, f6_take ++
            // migrate-embedded: skip intentional F6 independent borrowed store beside a final transfer.
            "func inspect(" ++ mode ++ "source: int[]) -> int:\n" ++
            "    const first = [1]\n" ++
            "    const left = my_take(first)\n" ++
            "    return left + my_take(source)\n" ++
            "func main() -> int:\n" ++
            "    mut source = [2]\n" ++
            "    return inspect(" ++ mode ++ "source)\n", &.{
            .{ .before = "my_take(first)", .after = "my_take(own first)" },
            .{ .before = "my_take(source)", .after = "my_take(copy(source))", .code = "E_SINGLE_OWNER_BORROW", .rule = if (mode.len == 0) .R1 else .M1, .copy = true },
        });
    }
}

test "F6 copy proof proveRepair composes refused match payload moves and read marker removals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try f6CopyProofRounds(arena.allocator(),
        // migrate-embedded: skip intentional F6 explicit borrowed payload stores requiring independent copies.
        \\func main() -> int:
        \\    const left: str? = Some("left")
        \\    mut first: str
        \\    match left:
        \\        case Some(value):
        \\            first = own value
        \\        case None:
        \\            first = ""
        \\    return len(first) + second_len(Some("right"))
        \\func second_len(right: str?) -> int:
        \\    mut second: str
        \\    match own right:
        \\        case Some(value):
        \\            second = own value
        \\        case None:
        \\            second = ""
        \\    return len(second)
    , &.{
        .{ .before = "first = own value", .after = "first = copy(value)", .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X1 },
        .{ .before = "match own right:", .after = "match right:" },
        .{ .before = "second = own value", .after = "second = copy(value)", .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X1 },
    });
}

test "F6 copy proof proveRepair composes borrowed fields but preserves copy capture and requested ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, f6_box ++ f6_take ++
        // migrate-embedded: skip intentional F6 final transfer beside a marked borrowed field store.
        \\func inspect(mut box: Box) -> int:
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    return left + my_take(own box.items)
        \\func main() -> int:
        \\    mut box = Box(items=[2], name="kept")
        \\    return inspect(mut box)
    , &.{
        .{ .before = "my_take(first)", .after = "my_take(own first)" },
        .{ .before = "my_take(own box.items)", .after = "my_take(copy(box.items))", .code = "E_SINGLE_OWNER_BORROW", .rule = .M1 },
    });
    try f6CopyProofRounds(a, f6_take ++
        // migrate-embedded: skip intentional F6 const initializer of a plain borrowed parameter.
        \\func inspect(source: int[]) -> int:
        \\    const alias = source
        \\    return my_take(alias)
        \\func main() -> int:
        \\    return inspect([2])
    , &.{
        .{ .before = "alias = source", .after = "alias = copy(source)", .rule = .B9, .copy = true },
        .{ .before = "my_take(alias)", .after = "my_take(own alias)" },
    });
    try fr61OwnBeside(a, f6_take ++
        // migrate-embedded: skip intentional F6 independent borrowed store under a captured copy name.
        \\func inspect(source: int[]) -> int:
        \\    const copy = 1
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    return left + my_take(source) + copy
        \\func main() -> int:
        \\    return inspect([2])
    , "E_OWN_MARKER");
}

const c2_text_payload =
    \\func payload() -> str?:
    \\    return Some("payload")
    \\func main() -> int:
    \\    mut text = ""
    \\    match payload():
    \\        case Some(value):
    \\            text = value
    \\        case None:
    \\            return 1
    \\
;

const c2_strings_import =
    // migrate-embedded: skip import prefix for intentional marker-proof rejection sources below.
    \\import strings
    \\
;

test "C2 marker proof proveRepair composes payload transfers with direct B7 element copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try f6CopyProofRounds(arena.allocator(), c2_text_payload ++
        // migrate-embedded: skip intentional payload marker and independent borrowed element store.
        \\    const source = ["later"]
        \\    mut rows: str[] = []
        \\    append(mut rows, source[0])
        \\    append(mut rows, "fresh-" + "row")
        \\    return len(text) + len(rows)
    , &.{
        .{ .before = "text = value", .after = "text = own value", .rule = .B2 },
        .{ .before = "source[0]", .after = "copy(source[0])", .code = "E_SINGLE_OWNER_BORROW", .rule = .B7, .copy = true },
    });
}

test "C2 marker proof proveRepair composes payload transfers with direct V2 slice stores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    inline for (.{
        // migrate-embedded: skip intentional text payload marker and independent owned slice store.
        \\func payload() -> str?:
        \\    return Some("payload")
        \\func main() -> int:
        \\    mut data = ""
        \\    match payload():
        \\        case Some(value):
        \\            data = value
        \\        case None:
        \\            return 1
        \\    mut section = data[0:1]
        \\    if len(section) > 9:
        \\        section = copy(data)
        \\    return len(data) + len(section)
        ,
        // migrate-embedded: skip intentional bytes payload marker and independent owned slice store.
        \\func payload() -> bytes?:
        \\    return Some(b"payload")
        \\func main() -> int:
        \\    mut data = b""
        \\    match payload():
        \\        case Some(value):
        \\            data = value
        \\        case None:
        \\            return 1
        \\    mut section = data[0:1]
        \\    if len(section) > 9:
        \\        section = copy(data)
        \\    return len(data) + len(section)
        ,
        // migrate-embedded: skip intentional list payload marker and independent owned slice store.
        \\func payload() -> str[]?:
        \\    return Some(["payload"])
        \\func main() -> int:
        \\    mut data: str[] = []
        \\    match payload():
        \\        case Some(value):
        \\            data = value
        \\        case None:
        \\            return 1
        \\    mut section = data[0:1]
        \\    if len(section) > 9:
        \\        section = copy(data)
        \\    return len(data) + len(section)
        ,
    }) |source| {
        try f6CopyProofRounds(arena.allocator(), source, &.{
            .{ .before = "data = value", .after = "data = own value", .rule = .B2 },
            .{ .before = "data[0:1]", .after = "copy(data[0:1])", .code = "E_SLICE_ESCAPES", .rule = .V2, .copy = true },
        });
    }
}

test "C2 marker proof sourceScalarSlice composes the exact scalar helper result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try f6CopyProofRounds(arena.allocator(), c2_strings_import ++ c2_text_payload ++
        // migrate-embedded: skip intentional payload marker and independent owned scalar helper view.
        \\    mut section = strings.char_slice(text, 0, 1)
        \\    if len(section) > 9:
        \\        section = copy(text)
        \\    return len(text) + len(section)
    , &.{
        .{ .before = "text = value", .after = "text = own value", .rule = .B2 },
        .{ .before = "strings.char_slice(text, 0, 1)", .after = "copy(strings.char_slice(text, 0, 1))", .code = "E_SLICE_ESCAPES", .rule = .V2, .copy = true },
    });
}

test "C2 marker proof sourceScalarSlice keeps captured copies and ordinary view calls unavailable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try fr61OwnBeside(a, c2_strings_import ++ c2_text_payload ++
        // migrate-embedded: skip intentional captured copy beside a scalar helper view.
        \\    const copy = 1
        \\    mut section = strings.char_slice(text, 0, 1)
        \\    if len(section) > 9:
        \\        section = "x" + "y"
        \\    return len(text) + len(section) + copy
    , "E_OWN_MARKER");
    try fr61OwnBeside(a,
        // migrate-embedded: skip intentional unsupported ordinary view call beside a payload transfer.
        \\func view(text: str) -> str from text:
        \\    return text
        \\
    ++ c2_text_payload ++
        \\    mut section = view(text)
        \\    section = copy(section)
        \\    return len(text) + len(section)
    , "E_OWN_MARKER");
}

test "C2 marker proof sourceSubscript keeps captured and dependent copies unavailable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try fr61OwnBeside(a, c2_text_payload ++
        // migrate-embedded: skip intentional captured-copy refusal beside an independent payload transfer.
        \\    const copy = 1
        \\    const source = ["later"]
        \\    mut rows: str[] = []
        \\    append(mut rows, source[0])
        \\    append(mut rows, "fresh-" + "row")
        \\    return len(text) + len(rows) + copy
    , "E_OWN_MARKER");
    try fr61OwnBeside(a, f6_take ++
        // migrate-embedded: skip intentional dependent element-copy refusal beside a fixed-type transfer.
        \\func keep[T: storable + copy](own value: T) -> int:
        \\    return 1
        \\func inspect[T: storable + copy](source: T[]) -> int:
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    return left + keep[T](source[0])
        \\func main() -> int:
        \\    return inspect[str](["later"])
    , "E_OWN_MARKER");
    try fr61OwnBeside(a, f6_take ++
        // migrate-embedded: skip intentional dependent slice-copy refusal beside a fixed-type transfer.
        \\func inspect[T: storable + copy](source: T[]) -> int:
        \\    const first = [1]
        \\    const left = my_take(first)
        \\    mut section = source[0:1]
        \\    if len(section) > 9:
        \\        section = copy(source)
        \\    return left + len(section)
        \\func main() -> int:
        \\    return inspect[str](["later"])
    , "E_OWN_MARKER");
}

fn c2AppendNode(nodes: []const language.typed.Node) !language.typed.Node {
    for (nodes) |node| {
        if (node.data == .buffer_operation and node.data.buffer_operation.kind == .append) return node;
    }
    return error.TestUnexpectedResult;
}

fn c2FunctionBody(program: language.typed.Program, suffix: []const u8) !usize {
    for (program.functions) |function| {
        if (std.mem.endsWith(u8, function.name, suffix)) return @backingInt(function.scope.body);
    }
    return error.TestUnexpectedResult;
}

fn c2GeneratedReadNoRepair(a: std.mem.Allocator, shared_span: bool) !void {
    const source = c2_text_payload ++
        // migrate-embedded: skip intentional payload marker and borrowed element store for generated-node control.
        \\    const source = ["later"]
        \\    mut rows: str[] = []
        \\    append(mut rows, source[0])
        \\    append(mut rows, "fresh-" + "row")
        \\    return len(text) + len(rows)
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var program = unit.program.?;
    const nodes = try a.alloc(language.typed.Node, program.nodes.len + 1);
    @memcpy(nodes[0..program.nodes.len], program.nodes);
    const statements = try a.alloc(language.typed.Statement, program.statements.len + 1);
    @memcpy(statements[0..program.statements.len], program.statements);
    const root = for (nodes[0..program.nodes.len], 0..) |node, index| {
        if (node.data == .block_value and node.ty.isAggregate() and std.mem.eql(u8, unit.src.?.text(node.span), "source[0]")) break index;
    } else return error.TestUnexpectedResult;
    const value = nodes[root].data.block_value.value;
    try std.testing.expect(nodes[@backingInt(value)].data == .buffer_operation);
    var generated = try c2AppendNode(nodes[0..program.nodes.len]);
    if (shared_span) generated.span = nodes[root].span;
    generated.data.buffer_operation.arguments = try a.dupe(language.typed.NodeId, &.{value});
    nodes[program.nodes.len] = generated;
    const extra: language.typed.StatementId = @fromBackingInt(program.statements.len);
    statements[@backingInt(extra)] = .{ .span = generated.span, .terminates = false, .data = .{ .discard = @fromBackingInt(program.nodes.len) } };
    const body = @backingInt(nodes[root].data.block_value.body);
    const items = statements[body].data.block;
    const extended = try a.alloc(language.typed.StatementId, items.len + 1);
    @memcpy(extended[0..items.len], items);
    extended[items.len] = extra;
    statements[body].data.block = extended;
    program.nodes = nodes;
    program.statements = statements;
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, program, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expect(failure.copy.span == null);
    try fr61OwnEdit(failure, unit.src.?.text(failure.span));
}

test "C2 marker proof sourceSubscript refuses generated setup reads with shared nodes and equal or different outer spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try c2GeneratedReadNoRepair(arena.allocator(), true);
    try c2GeneratedReadNoRepair(arena.allocator(), false);
}

fn c2GeneratedSliceNoRepair(a: std.mem.Allocator, expression: []const u8, different_outer_span: bool) !void {
    const original = c2_strings_import ++ c2_text_payload ++
        // migrate-embedded: skip intentional payload marker and owned slice store for generated-node control.
        \\    mut section = text[0:1]
        \\    return len(text) + len(section)
    ;
    const source = try std.mem.replaceOwned(u8, a, original, "text[0:1]", expression);
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var program = unit.program.?;
    const nodes = try a.alloc(language.typed.Node, program.nodes.len + 2);
    @memcpy(nodes[0..program.nodes.len], program.nodes);
    const statements = try a.alloc(language.typed.Statement, program.statements.len + 2);
    @memcpy(statements[0..program.statements.len], program.statements);
    const root = for (nodes[0..program.nodes.len], 0..) |node, index| {
        if (node.data == .block_value and node.ty.isAggregate() and std.mem.eql(u8, unit.src.?.text(node.span), expression)) break index;
    } else return error.TestUnexpectedResult;
    const slot = for (statements[0..program.statements.len]) |statement| {
        if (statement.data == .initialize and statement.data.initialize.value == @as(language.typed.NodeId, @fromBackingInt(root))) break statement.data.initialize.slot;
    } else return error.TestUnexpectedResult;
    const extra: language.typed.StatementId = @fromBackingInt(program.statements.len);
    statements[@backingInt(extra)] = .{ .span = nodes[root].span, .terminates = false, .data = .{ .assign = .{ .slot = slot, .value = nodes[root].data.block_value.value } } };
    const wrapper: language.typed.NodeId = @fromBackingInt(program.nodes.len);
    const zero: language.typed.NodeId = @fromBackingInt(program.nodes.len + 1);
    const outer: language.source.Span = .{ .start = 0, .end = 6 };
    nodes[@backingInt(wrapper)] = .{ .ty = .i64, .span = outer, .data = .{ .block_value = .{ .body = extra, .value = zero } } };
    nodes[@backingInt(zero)] = .{ .ty = .i64, .span = outer, .data = .{ .integer = 0 } };
    const discarded: language.typed.StatementId = @fromBackingInt(program.statements.len + 1);
    statements[@backingInt(discarded)] = .{ .span = outer, .terminates = false, .data = .{ .discard = wrapper } };
    const body = @backingInt(nodes[root].data.block_value.body);
    const items = statements[body].data.block;
    const extended = try a.alloc(language.typed.StatementId, items.len + 1);
    @memcpy(extended[0..items.len], items);
    extended[items.len] = if (different_outer_span) discarded else extra;
    statements[body].data.block = extended;
    program.nodes = nodes;
    program.statements = statements;
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, program, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expect(failure.copy.span == null);
    try fr61OwnEdit(failure, unit.src.?.text(failure.span));
}

test "C2 marker proof sourceSubscript and sourceScalarSlice refuse generated setup stores sharing the result span and node" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try c2GeneratedSliceNoRepair(arena.allocator(), "text[0:1]", false);
    try c2GeneratedSliceNoRepair(arena.allocator(), "strings.char_slice(text, 0, 1)", false);
    try c2GeneratedSliceNoRepair(arena.allocator(), "text[0:1]", true);
    try c2GeneratedSliceNoRepair(arena.allocator(), "strings.char_slice(text, 0, 1)", true);
}

const c2_mixed_return = f6_take ++
    // migrate-embedded: skip intentional named transfer beside a mixed borrowed return.
    \\func inspect(source: int[], small: bool) -> int[]:
    \\    if small:
    \\        return source
    \\    const first = [1]
    \\    const size = my_take(first)
    \\    return [size]
    \\func main() -> int:
    \\    return len(inspect([2], False))
;

test "C2 marker proof noteMixedCopy composes an independent exact R5 return without changing the requested own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try f6CopyProofRounds(a, c2_mixed_return, &.{
        .{ .before = "take(first)", .after = "take(own first)" },
        .{ .before = "return source", .after = "return copy(source)", .code = "E_BORROW_MIXED", .rule = .R5, .copy = true },
    });
    const multiple = try std.mem.replaceOwned(u8, a, c2_mixed_return, "    const first = [1]", "    if len(source) == 2:\n        return source\n    const first = [1]");
    try f6CopyProofRounds(a, multiple, &.{
        .{ .before = "take(first)", .after = "take(own first)" },
        .{ .before = "return source", .after = "return copy(source)", .code = "E_BORROW_MIXED", .rule = .R5, .copy = true },
    });
    // The independent copy counterfactual already permits the final transfer.
    try f6Repair(a, try std.mem.replaceOwned(u8, a, c2_mixed_return, "return source", "return copy(source)"), .{ .before = "take(first)", .after = "take(own first)" });
}

test "C2 marker proof noteMixedCopy keeps captured dependent and declared return contracts unavailable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // migrate-embedded: skip intentional shadowed-copy replacement for the mixed-return rejection control.
    try f6CopyProofNoRepair(a, try std.mem.replaceOwned(u8, a, c2_mixed_return, "const first = [1]", "const copy = 1\n    const first = [copy]"), "E_OWN_MARKER");
    try f6CopyProofNoRepair(a, try std.mem.replaceOwned(u8, a, c2_mixed_return, "-> int[]:\n    if small:", "-> int[] from source:\n    if small:"), "E_OWN_MARKER");
    const pending = try std.mem.replaceOwned(u8, a, c2_mixed_return, "-> int[]:\n    if small:", "-> int[] fails str:\n    if small:");
    try f6CopyProofNoRepair(a, try std.mem.replaceOwned(u8, a, pending, "return len(inspect([2], False))", "return 0"), "E_OWN_MARKER");
    try f6CopyProofNoRepair(a, f6_take ++
        // migrate-embedded: skip intentional dependent mixed return beside an independent missing marker.
        \\func inspect[T: copy + storable](source: T[], small: bool) -> T[]:
        \\    if small:
        \\        return source
        \\    const first = [1]
        \\    const size = my_take(first)
        \\    return []
        \\func main() -> int:
        \\    return len(inspect[str](["later"], False))
    , "E_OWN_MARKER");
}

test "C2 marker proof noteMixedCopy refuses a shared generated return occurrence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, c2_mixed_return);
    try std.testing.expect(unit.passed);
    var program = unit.program.?;
    const statements = try a.alloc(language.typed.Statement, program.statements.len + 1);
    @memcpy(statements[0..program.statements.len], program.statements);
    const value: language.typed.NodeId = for (program.nodes, 0..) |node, index| {
        if (node.data == .local and std.mem.eql(u8, unit.src.?.text(node.span), "source")) break @fromBackingInt(index);
    } else return error.TestUnexpectedResult;
    const extra: language.typed.StatementId = @fromBackingInt(program.statements.len);
    statements[@backingInt(extra)] = .{ .span = program.nodes[@backingInt(value)].span, .terminates = false, .data = .{ .discard = value } };
    const body = try c2FunctionBody(program, "inspect");
    const items = statements[body].data.block;
    const extended = try a.alloc(language.typed.StatementId, items.len + 1);
    extended[0] = extra;
    @memcpy(extended[1..], items);
    statements[body].data.block = extended;
    program.statements = statements;
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, program, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expect(failure.copy.span == null);
    try std.testing.expect(failure.repair == .none);
}

/// Check that `body` (with a `main` after it) is refused with `code` and a message holding `piece`, that its one repair writes `after` where `before` stood
/// (the call with the reads first), and that the repaired program checks.
fn readFirstRepaired(backing: std.mem.Allocator, body: []const u8, code: []const u8, piece: []const u8, edit: [2][]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    if (!unit.passed) report("front end: {s}\n", .{unit.diagnostics[0].message});
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.indexOf(u8, failure.message, piece) == null) report("unexpected message: {s}\n", .{failure.message});
    try std.testing.expect(std.mem.indexOf(u8, failure.message, piece) != null);
    try std.testing.expect(failure.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
    const change = failure.repair.explicit_fix[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..change.span.start], change.text, source[change.span.end..] });
    try std.testing.expectEqualStrings(try std.mem.replaceOwned(u8, a, source, edit[0], edit[1]), fixed);
    try accepted(a, fixed);
}

/// Check that `body` (with a `main` after it) is refused with `code` and a message ending in `ending`, which names no call with the reads first and
/// offers no repair that writes one.
fn readFirstUnchanged(backing: std.mem.Allocator, body: []const u8, code: []const u8, ending: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (!std.mem.endsWith(u8, failure.message, ending)) report("unexpected message: {s}\n", .{failure.message});
    try std.testing.expect(std.mem.endsWith(u8, failure.message, ending));
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "is read before it moves") == null);
    try std.testing.expect(failure.repair != .explicit_fix);
}

const read_first_setup =
    \\record Source:
    \\    mem: bytes
    \\    total: int
    \\    flag: bool = False
    \\
    \\
    \\func make(own mem: bytes, total: int) -> Source:
    \\    return Source(mem=own mem, total=total)
    \\
    \\
    \\func count(items: bytes) -> int:
    \\    return len(items)
    \\
    \\
;

test "FR41 a field that gives a local beside a read of its length is told the read first, and the repair writes it" {
    const piece = "write `mem=own plain` after `total=len(plain)` so that `plain` is read before it moves, or write `copy(plain)` to keep both";
    // The program of the audit: a constructor field, in a return.
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return Source(mem=plain, total=len(plain))
    , "E_OWN_MARKER", piece, .{ "Source(mem=plain, total=len(plain))", "Source(total=len(plain), mem=own plain)" });
    // Two reads after it, over several lines, and a field that is left to its default.
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return Source(
        \\        mem=plain,
        \\        total=len(plain),
        \\        flag=len(plain) > 10,
        \\    )
    , "E_OWN_MARKER", "write `mem=own plain` after `total=len(plain), flag=len(plain) > 10` so that", .{
        "        mem=plain,\n        total=len(plain),\n        flag=len(plain) > 10,\n",
        "        total=len(plain),\n        flag=len(plain) > 10,\n        mem=own plain,\n",
    });
    // The moved argument in the middle: only the arguments after it are read after the move.
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return Source(total=len(plain), mem=plain, flag=len(plain) > 3)
    , "E_OWN_MARKER", "write `mem=own plain` after `flag=len(plain) > 3` so that", .{
        "Source(total=len(plain), mem=plain, flag=len(plain) > 3)",
        "Source(total=len(plain), flag=len(plain) > 3, mem=own plain)",
    });
    // A parameter that is `own` and a `mut` local are moved the same way.
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(own plain: bytes) -> Source:
        \\    return Source(mem=plain, total=len(plain))
    , "E_OWN_MARKER", "only lends the `own` parameter `plain`", .{ "Source(mem=plain, total=len(plain))", "Source(total=len(plain), mem=own plain)" });
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    mut plain = copy(raw)
        \\    return Source(mem=plain, total=len(plain))
    , "E_OWN_MARKER", piece, .{ "Source(mem=plain, total=len(plain))", "Source(total=len(plain), mem=own plain)" });
}

test "FR41 a call argument that gives a local beside a read of its length is told the read first, by name" {
    const callee = "the `own` parameter `mem` of ";
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return make(mem=plain, total=len(plain))
    , "E_OWN_MARKER", callee, .{ "make(mem=plain, total=len(plain))", "make(total=len(plain), mem=own plain)" });
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return make(mem=plain, total=len(plain))
    , "E_OWN_MARKER", "so that `plain` is read before it moves, or write `copy(plain)` to keep both", .{
        "make(mem=plain, total=len(plain))",
        "make(total=len(plain), mem=own plain)",
    });
}

test "FR41 a read after a written own move in the same call is told to come first, and the repair writes it" {
    const moved = "'plain' was moved or is unavailable on this path; write `total=len(plain)` before `mem=own plain` to read it before it moves, " ++
        "or use copy(value) when both values are needed";
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return Source(mem=own plain, total=len(plain))
    , "E_SINGLE_OWNER_MOVED", moved, .{ "Source(mem=own plain, total=len(plain))", "Source(total=len(plain), mem=own plain)" });
    try readFirstRepaired(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return make(mem=own plain, total=len(plain))
    , "E_SINGLE_OWNER_MOVED", moved, .{ "make(mem=own plain, total=len(plain))", "make(total=len(plain), mem=own plain)" });
}

test "FR41 a value read in a later statement, by a call, positionally or through a comment keeps the copy it was told" {
    const copy_alone = "write `copy(plain)` to keep both";
    // A later statement reads it: the move would come first whatever the call's order.
    try readFirstUnchanged(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> int:
        \\    const plain = copy(raw)
        \\    const first = make(mem=plain, total=len(plain))
        \\    return first.total + len(plain)
    , "E_OWN_MARKER", copy_alone);
    // A call over the value is not one of the reads the repair knows keep nothing of it.
    try readFirstUnchanged(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return make(mem=plain, total=count(plain))
    , "E_OWN_MARKER", copy_alone);
    // Positional arguments cannot change places.
    try readFirstUnchanged(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return make(plain, len(plain))
    , "E_OWN_MARKER", copy_alone);
    // A comment between the arguments would end up in the wrong place.
    try readFirstUnchanged(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> Source:
        \\    const plain = copy(raw)
        \\    return Source(
        \\        mem=plain,  # the bytes
        \\        total=len(plain),
        \\    )
    , "E_OWN_MARKER", copy_alone);
    // The read of the moved value is in a later statement of the same function: the refusal after a written move is unchanged.
    try readFirstUnchanged(std.testing.allocator, read_first_setup ++
        \\func open(raw: bytes) -> int:
        \\    const plain = copy(raw)
        \\    const first = make(mem=own plain, total=0)
        \\    return first.total + len(plain)
    , "E_SINGLE_OWNER_MOVED", "use copy(value) when both values are needed");
}

test "FR41 a slice of the moved value kept in another field keeps the text it had" {
    try readFirstUnchanged(std.testing.allocator,
        \\record Sliced:
        \\    mem: bytes
        \\    head: bytes
        \\
        \\
        \\func open(raw: bytes) -> Sliced:
        \\    const plain = copy(raw)
        \\    return Sliced(mem=plain, head=plain[0:4])
    , "E_OWN_MARKER", "write `own plain` to give it, or `copy(plain)` to keep both");
}

test "FR41 the length of a text, a bytes, a list, a dictionary and a set local is read first, as the length of a bytes is" {
    const told = "so that `plain` is read before it moves, or write `copy(plain)` to keep both";
    const repair = [2][]const u8{ "Held(mem=plain, total=len(plain))", "Held(total=len(plain), mem=own plain)" };
    // A text: the lowering reads its length through a hidden local of its own.
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: str
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = "ab" + str(n)
        \\    return Held(mem=plain, total=len(plain))
    , "E_OWN_MARKER", told, repair);
    // A bytes: its length is read from the local itself.
    try readFirstRepaired(std.testing.allocator,
        \\import strings
        \\
        \\
        \\record Held:
        \\    mem: bytes
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = strings.encode("ab" + str(n))
        \\    return Held(mem=plain, total=len(plain))
    , "E_OWN_MARKER", told, repair);
    // A list: the hidden local, and the length as a number of another width.
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: int[]
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = [n, n + 1]
        \\    return Held(mem=plain, total=len(plain))
    , "E_OWN_MARKER", told, repair);
    // A dictionary and a set.
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: dict[str, int]
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = {"a": n}
        \\    return Held(mem=plain, total=len(plain))
    , "E_OWN_MARKER", told, repair);
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: set[int]
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = {n}
        \\    return Held(mem=plain, total=len(plain))
    , "E_OWN_MARKER", told, repair);
}

test "FR41 a text or bytes literal after the moved argument reads nothing of it, and a text local does not qualify" {
    // A text literal, an empty one, and a bytes literal.
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: str
        \\    total: int
        \\    tag: str
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = "ab" + str(n)
        \\    return Held(mem=plain, total=len(plain), tag="t")
    , "E_OWN_MARKER", "write `mem=own plain` after `total=len(plain), tag=\"t\"` so that", .{
        "Held(mem=plain, total=len(plain), tag=\"t\")",
        "Held(total=len(plain), tag=\"t\", mem=own plain)",
    });
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: str
        \\    tag: str
        \\    total: int
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = "ab" + str(n)
        \\    return Held(mem=plain, tag="", total=len(plain))
    , "E_OWN_MARKER", "write `mem=own plain` after `tag=\"\", total=len(plain)` so that", .{
        "Held(mem=plain, tag=\"\", total=len(plain))",
        "Held(tag=\"\", total=len(plain), mem=own plain)",
    });
    try readFirstRepaired(std.testing.allocator,
        \\record Held:
        \\    mem: str
        \\    total: int
        \\    raw: bytes
        \\
        \\
        \\func open(n: int) -> Held:
        \\    const plain = "ab" + str(n)
        \\    return Held(mem=plain, total=len(plain), raw=b"t")
    , "E_OWN_MARKER", "write `mem=own plain` after `total=len(plain), raw=b\"t\"` so that", .{
        "Held(mem=plain, total=len(plain), raw=b\"t\")",
        "Held(total=len(plain), raw=b\"t\", mem=own plain)",
    });
    // A text that is a local is a value that may be the moved one's: the text keeps the copy.
    try readFirstUnchanged(std.testing.allocator,
        \\record Held:
        \\    mem: str
        \\    total: int
        \\    tag: str
        \\
        \\
        \\func open(n: int, label: str) -> Held:
        \\    const plain = "ab" + str(n)
        \\    return Held(mem=plain, total=len(plain), tag=label)
    , "E_OWN_MARKER", "write `copy(plain)` to keep both");
}

const field_moves_setup =
    \\record Pair:
    \\    lat: int[]
    \\    status: int[]
    \\    flag: bool
    \\    name: str
    \\
    \\
    \\record Tally:
    \\    lat: int[]
    \\    status: int[]
    \\    flag: bool
    \\
    \\
    \\record Flagged:
    \\    lat: int[]
    \\    flag: bool
    \\
    \\
    \\record Counted:
    \\    lat: int[]
    \\    n: int
    \\
    \\
;

/// Check that `body` (with a `main` after it) is refused `E_SINGLE_OWNER_MOVED` with a message holding `piece`, that the edits of its
/// repair, applied together, turn `before` into `after`, and that the repaired program checks.
fn fieldMovesRepaired(backing: std.mem.Allocator, body: []const u8, piece: []const u8, edit: [2][]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    if (std.mem.indexOf(u8, failure.message, piece) == null) report("unexpected message: {s}\n", .{failure.message});
    try std.testing.expect(std.mem.indexOf(u8, failure.message, piece) != null);
    try std.testing.expect(failure.repair == .explicit_fix);
    var fixed: []const u8 = source;
    var index = failure.repair.explicit_fix.len;
    while (index > 0) : (index -= 1) {
        const change = failure.repair.explicit_fix[index - 1];
        fixed = try std.mem.concat(a, u8, &.{ fixed[0..change.span.start], change.text, fixed[change.span.end..] });
    }
    try std.testing.expectEqualStrings(try std.mem.replaceOwned(u8, a, source, edit[0], edit[1]), fixed);
    try accepted(a, fixed);
}

test "FR63 a scalar field or the length of a text field read after a field is moved is told to come first, and the repair writes it" {
    const reorder = "write `flag=state.flag` before `lat=own state.lat` so that it is read before `state` is consumed, or write copy(...) to keep both";
    try fieldMovesRepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> Flagged:
        \\    mut state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    return Flagged(lat=own state.lat, flag=state.flag)
    , reorder, .{ "Flagged(lat=own state.lat, flag=state.flag)", "Flagged(flag=state.flag, lat=own state.lat)" });
    try fieldMovesRepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> Counted:
        \\    const state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    return Counted(lat=own state.lat, n=len(state.name))
    , "write `n=len(state.name)` before `lat=own state.lat` so that it is read before `state` is consumed", .{
        "Counted(lat=own state.lat, n=len(state.name))",
        "Counted(n=len(state.name), lat=own state.lat)",
    });
}

test "FR63 two fields moved out of one mut record are written with take, and the message names the first move" {
    const piece = "`own state.lat` at column 26 consumed `state`; write `take(mut state.lat)` and `take(mut state.status)` to move each field out " ++
        "and leave its default, or write copy(...) to keep both";
    try fieldMovesRepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> Tally:
        \\    mut state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    return Tally(lat=own state.lat, status=own state.status, flag=state.flag)
    , piece, .{
        "Tally(lat=own state.lat, status=own state.status, flag=state.flag)",
        "Tally(lat=take(mut state.lat), status=take(mut state.status), flag=state.flag)",
    });
}

/// Check that `body` (with a `main` after it) is refused `E_SINGLE_OWNER_MOVED` with the message of several fields moved out of one record
/// that names the first move and says to move them in one statement, with the two moves written so (FR91, FR91B), and that no
/// repair is offered.
fn fieldMovesUnrepaired(backing: std.mem.Allocator, body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    const ending = " consumed `state`; move its fields in one statement, each once, as in `f(own state.lat, own state.status)`, " ++
        "or write copy(...) to keep both";
    if (!std.mem.endsWith(u8, failure.message, ending)) report("unexpected message: {s}\n", .{failure.message});
    try std.testing.expect(std.mem.endsWith(u8, failure.message, ending));
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "`own state.lat` at ") != null);
    try std.testing.expect(failure.repair != .explicit_fix);
}

test "FR63 moving two fields keeps the copy advice where take would leave defaults a later use or a caller sees, or has none to leave" {
    // FR91: in one statement these moves check; written in two statements, each is refused at its second move.
    // A const record cannot be written through.
    try fieldMovesUnrepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> Tally:
        \\    const state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    const lat = own state.lat
        \\    return Tally(lat=own lat, status=own state.status, flag=False)
    );
    // The parameter's storage is the caller's.
    try fieldMovesUnrepaired(std.testing.allocator, field_moves_setup ++
        \\func open(own state: Pair) -> Tally:
        \\    const lat = own state.lat
        \\    return Tally(lat=own lat, status=own state.status, flag=False)
    );
    // A later statement reads the record, which would now read a default instead of being refused.
    try fieldMovesUnrepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> int:
        \\    mut state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    const lat = own state.lat
        \\    const t = Tally(lat=own lat, status=own state.status, flag=False)
        \\    return len(t.lat) + len(state.name)
    );
    // The moves run again in a loop the record is declared outside of.
    try fieldMovesUnrepaired(std.testing.allocator, field_moves_setup ++
        \\func open() -> int:
        \\    mut state = Pair(lat=[1], status=[2], flag=True, name="ab")
        \\    mut total = 0
        \\    for index in range(2):
        \\        const lat = own state.lat
        \\        const t = Tally(lat=own lat, status=own state.status, flag=False)
        \\        total += len(t.lat) + index
        \\    return total
    );
}

const own_fields_setup =
    \\record Piece:
    \\    order: func(int, int) -> int
    \\    items: int[]
    \\
    \\
    \\record Pair:
    \\    lo: Piece
    \\    hi: Piece
    \\    tag: str
    \\
    \\
    \\func cmp(a: int, b: int) -> int:
    \\    return a - b
    \\
    \\
    \\func total(own a: Piece, own b: Piece) -> int:
    \\    return len(a.items) + len(b.items)
    \\
    \\
    \\func make() -> Pair:
    \\    return Pair(lo=Piece(order=cmp, items=[1]), hi=Piece(order=cmp, items=[2]), tag="t")
    \\
    \\
;

/// FR91: `body` (with a `main` after it) checks.
fn ownFieldsAccepted(backing: std.mem.Allocator, body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    try accepted(a, try std.mem.concat(a, u8, &.{ own_fields_setup, body, "\n\nfunc main() -> int:\n    return 0\n" }));
}

/// FR91: `body` (with a `main` after it) is refused with `code`, and the message holds `piece`.
fn ownFieldsRefused(backing: std.mem.Allocator, body: []const u8, code: []const u8, piece: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ own_fields_setup, body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    if (!std.mem.eql(u8, code, failure.code) or std.mem.indexOf(u8, failure.message, piece) == null) report("unexpected refusal: {s}: {s}\n", .{ failure.code, failure.message });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, piece) != null);
}

test "FR91 several fields move out of one owned record in one statement: a parameter, a local, a constructor, a nested field" {
    try ownFieldsAccepted(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    return total(own p.lo, own p.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func both() -> int:
        \\    const p = make()
        \\    const n = len(p.tag)
        \\    return total(own p.hi, own p.lo) + n
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func both() -> int:
        \\    mut p = make()
        \\    p.tag = "x"
        \\    return total(own p.lo, own p.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    mut q = own p
        \\    return total(own q.lo, own q.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\record Halves:
        \\    lo: Piece
        \\    hi: Piece
        \\
        \\func split(own p: Pair) -> Halves:
        \\    return Halves(lo=own p.lo, hi=own p.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func items(own a: int[], own b: Piece) -> int:
        \\    return len(a) + len(b.items)
        \\
        \\func nested(own p: Pair) -> int:
        \\    return items(own p.lo.items, own p.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func check(n: int) -> int fails str:
        \\    if n < 0:
        \\        fail "negative"
        \\    return n
        \\
        \\func three(own a: Piece, n: int, own b: Piece) -> int:
        \\    return len(a.items) + n + len(b.items)
        \\
        \\func between(own p: Pair, n: int) -> int fails str:
        \\    return three(own p.lo, try check(n), own p.hi)
    );
}

test "FR91 the record stays consumed: a read after the moves, one field twice, and moves in two statements are refused" {
    try ownFieldsRefused(std.testing.allocator,
        \\func both() -> int:
        \\    const p = make()
        \\    const n = total(own p.lo, own p.hi)
        \\    return n + len(p.tag)
    , "E_SINGLE_OWNER_MOVED", "'p' was moved or is unavailable on this path");
    // A read in the statement after the moves, of a record no `take` can be written for: read it before the statement (FR91B).
    try ownFieldsRefused(std.testing.allocator,
        \\func both() -> int:
        \\    const p = make()
        \\    return total(own p.lo, own p.hi) + len(p.tag)
    , "E_SINGLE_OWNER_MOVED", "'p' was moved or is unavailable on this path; `own p.lo` at column 22 consumed `p` and destroyed its other " ++
        "fields; read `p.tag` into a local before this statement (`const tag = copy(p.tag)`) and use that, or write copy(...) to keep both");
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    return total(own p.lo, own p.lo)
    , "E_SINGLE_OWNER_MOVED", "'p' was moved or is unavailable on this path");
    // `Piece` holds a function, so it has no default: the message must not send the writer to `take`. It shows the call the
    // repair joins the two statements into (FR91B).
    const separate = "consumed `p`; move its fields in one statement, each once, as in `total(own p.lo, own p.hi)`, or write copy(...) to keep both";
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    return total(own lo, own hi)
    , "E_SINGLE_OWNER_MOVED", separate);
}

test "FR91 a borrowed record, a list element and a short-circuit operand still move no second field" {
    try ownFieldsRefused(std.testing.allocator,
        \\func both(p: Pair) -> int:
        \\    return total(own p.lo, own p.hi)
    , "E_SINGLE_OWNER_BORROW", "");
    try ownFieldsRefused(std.testing.allocator,
        \\func both(mut p: Pair) -> int:
        \\    return total(own p.lo, own p.hi)
    , "E_SINGLE_OWNER_BORROW", "");
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own ps: Pair[]) -> int:
        \\    return total(own ps[0].lo, own ps[0].hi)
    , "E_SINGLE_OWNER_BORROW", "");
    // The second operand of `and` runs only when the first is true: its move is a move of its own, after the first consumed `p`.
    try ownFieldsRefused(std.testing.allocator,
        \\func small(own a: Piece) -> bool:
        \\    return len(a.items) < 3
        \\
        \\func both(own p: Pair) -> bool:
        \\    return small(own p.lo) and small(own p.hi)
    , "E_SINGLE_OWNER_MOVED", "'p' was moved or is unavailable on this path");
}

const own_slot_setup =
    \\enum Slot:
    \\    full(value: Pair)
    \\    empty
    \\
    \\
;

test "FR91B a binding that owns what it names opens as a record does: a match own payload, an own-else payload, a loop's element" {
    try ownFieldsAccepted(std.testing.allocator, own_slot_setup ++
        \\func both(own s: Slot) -> int:
        \\    match own s:
        \\        case full(value=p):
        \\            return total(own p.lo, own p.hi)
        \\        case empty:
        \\            return 0
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func find(k: int) -> Pair?:
        \\    if k > 0:
        \\        return Some(make())
        \\    return None
        \\
        \\func both(k: int) -> int:
        \\    const found = find(k)
        \\    const p = own found else:
        \\        return 0
        \\    return total(own p.lo, own p.hi)
    );
    try ownFieldsAccepted(std.testing.allocator,
        \\func both(own ps: Pair[]) -> int:
        \\    mut n = 0
        \\    for p in own ps:
        \\        n += total(own p.lo, own p.hi)
        \\    return n
    );
}

test "FR91B a match mut binding and a read-only match binding lend their payload, so no field moves out of them" {
    try ownFieldsRefused(std.testing.allocator, own_slot_setup ++
        \\func both(mut s: Slot) -> int:
        \\    match mut s:
        \\        case full(value=p):
        \\            return total(own p.lo, own p.hi)
        \\        case empty:
        \\            return 0
    , "E_SINGLE_OWNER_BORROW", "");
    try ownFieldsRefused(std.testing.allocator, own_slot_setup ++
        \\func both(s: Slot) -> int:
        \\    match s:
        \\        case full(value=p):
        \\            return total(own p.lo, own p.hi)
        \\        case empty:
        \\            return 0
    , "E_SINGLE_OWNER_BORROW", "");
}

test "FR91B each refusal of a second field move names the way out in the words of the program" {
    try ownFieldsRefused(std.testing.allocator,
        \\func three(own a: Piece, n: int, own b: Piece) -> int:
        \\    return len(a.items) + n + len(b.items)
        \\
        \\func both(own p: Pair) -> int:
        \\    return three(own p.lo, len(p.tag), own p.hi)
    , "E_SINGLE_OWNER_MOVED", "`own p.lo` at column 22 consumed `p` and destroyed its other fields; read `p.tag` into a local before " ++
        "this statement (`const tag = copy(p.tag)`) and use that, or write copy(...) to keep both");
    try ownFieldsRefused(std.testing.allocator,
        \\func small(own a: Piece) -> bool:
        \\    return len(a.items) < 3
        \\
        \\func both(own p: Pair) -> bool:
        \\    return small(own p.lo) or small(own p.hi)
    , "E_SINGLE_OWNER_MOVED", "consumed `p`; fields leave one record together only when every move runs, and this one runs only on " ++
        "some paths: pass them to one function, `f(own p.lo, own p.hi)`, and test inside it, or write copy(...) to keep both");
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own p: Pair, flag: bool) -> int:
        \\    const lo = own p.lo
        \\    if flag:
        \\        return total(own lo, own p.hi)
        \\    return len(lo.items)
    , "E_SINGLE_OWNER_MOVED", "consumed `p`; fields leave one record together only in one statement that runs every move: move " ++
        "them in one statement inside this branch, as in `f(own p.lo, own p.hi)`, and the same on each other path that needs them");
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    return total(own p.lo, own p.lo)
    , "E_SINGLE_OWNER_MOVED", "`own p.lo` at column 22 consumed `p`; a field moves out once: write `copy(p.lo)` at the first use to keep both");
    // `append` is an operation whose operands no group reaches: the moves go in a statement before it.
    try ownFieldsRefused(std.testing.allocator,
        \\func both(own ps: Pair[]) -> int[]:
        \\    mut sums: int[] = []
        \\    for p in own ps:
        \\        append(mut sums, total(own p.lo, own p.hi))
        \\    return sums
    , "E_SINGLE_OWNER_MOVED", "and this place is inside another operation: write `const value = total(own p.lo, own p.hi)` in a " ++
        "statement before it and use `value`, or write copy(...) to keep both");
    const lent = "; declare the parameter `own p` of `both` to move several of its fields out, or write `copy(p.lo)` to keep both";
    try ownFieldsRefused(std.testing.allocator,
        \\func both(p: Pair) -> int:
        \\    return total(own p.lo, own p.hi)
    , "E_SINGLE_OWNER_BORROW", "`p.lo` is lent by the plain parameter `p`" ++ ", and the `own` parameter `a` of `total` needs its own value" ++ lent);
    try ownFieldsRefused(std.testing.allocator,
        \\func both(mut p: Pair) -> int:
        \\    return total(own p.lo, own p.hi)
    , "E_SINGLE_OWNER_BORROW", "`p.lo` is lent by the `mut` parameter `p`" ++ ", and the `own` parameter `a` of `total` needs its own value" ++ lent);
    // One field moved out of a borrowed parameter keeps the copy advice alone.
    try ownFieldsRefused(std.testing.allocator,
        \\func items(own a: Piece) -> int:
        \\    return len(a.items)
        \\
        \\func one(p: Pair) -> int:
        \\    return items(own p.lo)
    , "E_SINGLE_OWNER_BORROW", "needs its own value; write `copy(p.lo)` to keep both");
}

test "FR91B two fields moved into two const locals that the next call or constructor takes: the repair moves them there" {
    try fieldMovesRepaired(std.testing.allocator, own_fields_setup ++
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    return total(own lo, own hi)
    , "move its fields in one statement, each once, as in `total(own p.lo, own p.hi)`, or write copy(...) to keep both", .{
        "    const lo = own p.lo\n    const hi = own p.hi\n    return total(own lo, own hi)",
        "    return total(own p.lo, own p.hi)",
    });
    try fieldMovesRepaired(std.testing.allocator, own_fields_setup ++
        \\record Halves:
        \\    lo: Piece
        \\    hi: Piece
        \\
        \\func split() -> Halves:
        \\    const p = make()
        \\    const hi = own p.hi
        \\    const lo = own p.lo
        \\    const halves = Halves(lo=own lo, hi=own hi)
        \\    return halves
    , "as in `Halves(lo=own p.lo, hi=own p.hi)`", .{
        "    const hi = own p.hi\n    const lo = own p.lo\n    const halves = Halves(lo=own lo, hi=own hi)",
        "    const halves = Halves(lo=own p.lo, hi=own p.hi)",
    });
}

/// FR91B: `body` (with a `main` after it) is refused `E_SINGLE_OWNER_MOVED` with no repair.
fn ownFieldsUnjoined(backing: std.mem.Allocator, body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ own_fields_setup, body, "\n\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    if (failure.repair == .explicit_fix) report("unexpected repair: {s}\n", .{failure.message});
    try std.testing.expect(failure.repair != .explicit_fix);
}

test "FR91B the join is offered only for its one shape: each local used once, as `own`, in the next statement's one call" {
    // A statement between the moves and the call.
    try ownFieldsUnjoined(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    const n = len(lo.items)
        \\    return total(own lo, own hi) + n
    );
    // A local used twice.
    try ownFieldsUnjoined(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    return total(own lo, own hi) + len(lo.items)
    );
    // A `mut` local.
    try ownFieldsUnjoined(std.testing.allocator,
        \\func both(own p: Pair) -> int:
        \\    mut lo = own p.lo
        \\    const hi = own p.hi
        \\    return total(own lo, own hi)
    );
    // The two in different calls.
    try ownFieldsUnjoined(std.testing.allocator,
        \\func items(own a: Piece) -> int:
        \\    return len(a.items)
        \\
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    return items(own lo) + items(own hi)
    );
    // The record read in the call: the joined call would read it after the first move.
    try ownFieldsUnjoined(std.testing.allocator,
        \\func three(own a: Piece, n: int, own b: Piece) -> int:
        \\    return len(a.items) + n + len(b.items)
        \\
        \\func both(own p: Pair) -> int:
        \\    const lo = own p.lo
        \\    const hi = own p.hi
        \\    return three(own lo, len(p.tag), own hi)
    );
}

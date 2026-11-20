//! The developer layer audit and ordinary checking share Core ownership checks and retain Result obligations.
const std = @import("std");
const language = @import("selka");
const ownership = @import("single_owner.zig");
const Rule = language.ownership_rules.Rule;
const Observer = @import("ownership_observations.zig").Observer;

const Outcome = struct { accepted: bool, diagnostics: []const language.diagnostic.Diagnostic, report: []const u8 };

fn run(a: std.mem.Allocator, text: []const u8, reports: bool) !Outcome {
    var unit = try language.Compilation.init(a, "ownership-audit.selka", text);
    const checked = if (reports) unit.checkForOwnershipAudit(false) else unit.check();
    checked catch |err| switch (err) {
        error.SourceError => return .{ .accepted = false, .diagnostics = unit.diagnostics.items, .report = "" },
        else => return err,
    };
    var report: std.ArrayList(u8) = .empty;
    const accepted = try ownership.audit(a, unit.program.?, unit.src, &report);
    return .{ .accepted = accepted, .diagnostics = unit.diagnostics.items, .report = report.items };
}

test "ownership audit and ordinary checking both reach the Core overlap refusal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text =
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], mut rows[0])
        \\    return 0
    ;
    const strict = try run(arena.allocator(), text, false);
    try std.testing.expect(!strict.accepted);
    try std.testing.expectEqual(@as(usize, 0), strict.diagnostics.len);
    try std.testing.expect(std.mem.indexOf(u8, strict.report, "E_SINGLE_OWNER_OVERLAP") != null);
    const audit = try run(arena.allocator(), text, true);
    try std.testing.expect(!audit.accepted);
    try std.testing.expectEqual(@as(usize, 0), audit.diagnostics.len);
    try std.testing.expectEqualStrings(strict.report, audit.report);
}

test "ownership audit observes from explicit moves and carriers while const places borrow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try run(arena.allocator(),
        // migrate-embedded: skip ownership-audit observations distinguish explicit moves from const-place borrows
        \\record Row:
        \\    items: int[]
        \\func borrowed(rows: int[][]) -> int[] from rows:
        \\    return rows[0]
        \\func main() -> int:
        \\    const xs = [1]
        \\    const ys = xs
        \\    const observed = len(ys)
        \\    const row = Row(items=own xs)
        \\    mut moved = own row.items
        \\    return observed + len(moved)
    , true);
    try std.testing.expect(outcome.accepted);
    try std.testing.expect(std.mem.indexOf(u8, outcome.report, "\"kind\":\"from\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outcome.report, "\"kind\":\"move\"") != null);
    // The unmarked alias borrows; it must not be counted as an implicit owner transfer.
    try std.testing.expect(std.mem.indexOf(u8, outcome.report, "\"kind\":\"const_own\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, outcome.report, "\"kind\":\"carrier\"") != null);
}

test "ownership audit preserves Result consumption refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try run(arena.allocator(),
        \\result R:
        \\    ok: int,
        \\    err: int
        \\func main() -> int:
        \\    mut r = R.ok(7)
        \\    mut copied = r
        \\    _ = r
        \\    _ = copied
        \\    return 0
    , true);
    try std.testing.expect(!outcome.accepted);
    try std.testing.expectEqualStrings("E_RESULT_CONSUMED", outcome.diagnostics[0].code);
    try std.testing.expectEqual(.err, outcome.diagnostics[0].severity);
    try std.testing.expectEqualStrings("", outcome.report);
}

test "ownership audit checks specialized functions after an earlier refusal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try run(arena.allocator(),
        \\func consume[T](own xs: T[]) -> int:
        \\    const moved = own xs
        \\    return len(xs) + len(moved)
        \\func main() -> int:
        \\    return consume([1]) + consume(["a"])
    , true);
    try std.testing.expect(!outcome.accepted);
    try std.testing.expect(std.mem.indexOf(u8, outcome.report, "E_SINGLE_OWNER_MOVED") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, outcome.report, "\"specialized\":true,\"accepted\":false"));
}

test "ownership audit accepts source ordered direct and callback arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outcome = try run(arena.allocator(),
        \\func pair(named left: int, named right: int) -> int:
        \\    return left * 10 + right
        \\func main() -> int:
        \\    const callback = pair
        \\    return pair(right=2, left=1) + callback(right=4, left=3)
    , true);
    try std.testing.expect(outcome.accepted);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, outcome.report, "\"accepted\":true"));
}

const Defect = enum { tuple_staging, resource_scope };

fn constructedDefect(a: std.mem.Allocator, defect: Defect) !ownership.Failure {
    var unit = try language.Compilation.init(a, "constructed-defect.selka",
        \\func main() -> int:
        \\    const saved = [1]
        \\    return len(saved)
    );
    try unit.check();
    const program = unit.program.?;
    var tail: ?language.typed.StatementId = null;
    for (program.statements, 0..) |statement, index| if (statement.data == .ret) {
        tail = @fromBackingInt(index);
        break;
    };
    try std.testing.expect(tail != null);
    var changed = false;
    for (@constCast(program.statements)) |*statement| {
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        switch (defect) {
            .tuple_staging => statement.data.initialize.unpack = &.{null},
            .resource_scope => statement.data = .{ .with_scope = .{
                .slot = store.slot,
                .resource = null,
                .body = tail.?,
            } },
        }
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, program, &failure));
    return failure;
}

test "ownership audit malformed staging and resource scopes are compiler defects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const tuple = try constructedDefect(arena.allocator(), .tuple_staging);
    try std.testing.expectEqualStrings("E_INTERNAL_TUPLE_STAGING", tuple.code);
    try std.testing.expectEqual(@as(?Rule, null), tuple.rule);
    try std.testing.expect(std.mem.startsWith(u8, tuple.message, "compiler bug:"));
    const scope = try constructedDefect(arena.allocator(), .resource_scope);
    try std.testing.expectEqualStrings("E_INTERNAL_RESOURCE_SCOPE", scope.code);
    try std.testing.expectEqual(@as(?Rule, null), scope.rule);
    try std.testing.expect(std.mem.startsWith(u8, scope.message, "compiler bug:"));
}

fn expectCoreRule(a: std.mem.Allocator, text: []const u8, expected: language.ownership_rules.Refusal) !void {
    var unit = try language.Compilation.init(a, "ownership-rule.selka", text);
    try unit.checkForOwnershipAudit(false);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
}

test "ownership audit shared borrow code preserves parameter and binding rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectCoreRule(a,
        \\func keep(xs: int[]) -> int[][]:
        \\    return [xs]
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .R1 });
    try expectCoreRule(a,
        \\func keep(mut xs: int[]) -> int[][]:
        \\    return [xs]
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .M1 });
    try expectCoreRule(a,
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    const row = rows[0]
        \\    mut kept = [row]
        \\    append(mut kept, [2])
        \\    return len(kept)
    , .{ .code = "E_OWN_MARKER", .rule = .B9 });
    try expectCoreRule(a,
        \\record Row:
        \\    items: int[]
        \\func first(rows: Row[]) -> Row from rows:
        \\    return rows[0]
        \\func main() -> int:
        \\    const rows = [Row(items=[1])]
        \\    const row = first(rows)
        \\    mut kept = [row]
        \\    append(mut kept, Row(items=[2]))
        \\    return len(kept)
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .R3 });
}

test "ownership audit shared borrow code distinguishes element and field moves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectCoreRule(a,
        \\func main() -> int:
        \\    const rows = [[1]]
        \\    mut row = rows[0]
        \\    row = copy(row)
        \\    return len(row)
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B7 });
    try expectCoreRule(a,
        \\record Row:
        \\    items: int[]
        \\func keep(row: Row) -> int[][]:
        \\    return [row.items]
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8 });
}

test "ownership audit resource scope bindings preserve the scope rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // A narrowed capability is a handle since 5C and may leave its scope; an open file binding may not.
    try expectCoreRule(arena.allocator(),
        \\func escape(fs: Filesystem) -> int:
        \\    with fs.open("logs", "r") as file:
        \\        mut other = file
        \\        return 0
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_WITH_RESOURCE", .rule = .P4 });
}

test "ownership audit shared overlap code distinguishes bindings arguments and iteration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectCoreRule(a,
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    const row = rows[0]
        \\    append(mut rows, [2])
        \\    return len(row)
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 });
    try expectCoreRule(a,
        \\func both(xs: int[], mut ys: int[]) -> int:
        \\    append(mut ys, 3)
        \\    return len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return both(xs, mut xs)
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 });
    try expectCoreRule(a,
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    for row in rows:
        \\        append(mut rows, [2])
        \\    return len(rows)
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R7 });
}

test "ownership audit match holds preserve the match rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectCoreRule(a,
        \\func main() -> int:
        \\    const saved: int[]? = Some([1])
        \\    match saved:
        \\        case Some(payload):
        \\            const moved = own saved
        \\            return len(payload)
        \\        case None:
        \\            return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X1 });
    try expectCoreRule(a,
        \\func main() -> int:
        \\    mut saved: int[]? = Some([1])
        \\    match mut saved:
        \\        case Some(payload):
        \\            const moved = own saved
        \\            return len(payload)
        \\        case None:
        \\            return 0
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X2 });
}

test "ownership audit slice refusals distinguish storage invalidation and return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectCoreRule(a,
        \\record Holder:
        \\    text: str
        \\func keep(text: str) -> Holder:
        \\    return Holder(text=text[0:1])
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V2 });
    try expectCoreRule(a,
        \\func main() -> int:
        \\    mut text = "abc"
        \\    const held = text[0:1]
        \\    text += "d"
        \\    return len(held)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V3 });
    try expectCoreRule(a,
        \\func part() -> bytes:
        \\    const data = copy(b"local bytes")
        \\    return data[0:1]
        \\func main() -> int:
        \\    return 0
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V4 });
    try expectCoreRule(a,
        \\func choose(flag: bool) -> int:
        \\    const left = "ab"
        \\    const right = "cd"
        \\    const held: str
        \\    if flag:
        \\        held = left[0:1]
        \\    else:
        \\        held = right[0:1]
        \\    return len(held)
        \\func main() -> int:
        \\    return choose(True)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V2 });
}

fn constructedViewJoin(a: std.mem.Allocator) !ownership.Failure {
    var unit = try language.Compilation.init(a, "constructed-view-join.selka",
        // migrate-embedded: skip constructed view-join source witness; automatic copies erase the view initialization being mutated
        \\func choose(flag: bool) -> int:
        \\    const left = "ab"
        \\    const right = "cd"
        \\    const held: str
        \\    if flag:
        \\        held = left[0:1]
        \\    else:
        \\        held = right[0:1]
        \\    return len(held)
        \\func main() -> int:
        \\    return choose(True)
    );
    try unit.check();
    const program = unit.program.?;
    var changed = false;
    for (program.functions) |function| for (@constCast(function.scope.locals)) |*local| {
        if (!std.mem.eql(u8, local.name, "held")) continue;
        // The source initializer is refused by V2 first. A constructed view
        // binding exercises the later join guard without broadening acceptance.
        local.ownership.view = true;
        changed = true;
    };
    try std.testing.expect(changed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, program, &failure));
    return failure;
}

test "ownership audit incompatible constructed slice join preserves V5" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const failure = try constructedViewJoin(arena.allocator());
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expectEqual(Rule.V5, failure.rule.?);
}

test "ownership audit source resource intrinsic reaches resource type refusal" {
    var unit = try language.Compilation.init(std.testing.allocator, "resource-type.selka",
        \\func main() -> int:
        \\    mut scalar = 1
        \\    _ = read_resource[int](scalar)
        \\    return 0
    );
    defer unit.deinit();
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expectEqualStrings("E_RESOURCE_TYPE", unit.diagnostics.items[0].code);
}

fn expectMove(a: std.mem.Allocator, report: []const u8, function: []const u8, kind: []const u8, explicit: bool) !void {
    var lines = std.mem.splitScalar(u8, report, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
        defer parsed.deinit();
        const record = parsed.value.object;
        if (!std.mem.eql(u8, record.get("kind").?.string, kind)) continue;
        const detail = record.get("detail").?.object;
        if (!std.mem.eql(u8, detail.get("function").?.string, function)) continue;
        try std.testing.expectEqual(explicit, detail.get("explicit_own").?.bool);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "ownership audit distinguishes direct argument and return moves from nested stores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const outcome = try run(a,
        // migrate-embedded: skip ownership-audit observations distinguish explicit stores from bare returned transfers
        \\record Row:
        \\    items: int[]
        \\func returned_record(own xs: int[]) -> Row:
        \\    return Row(items=own xs)
        \\func returned_array(own xs: int[]) -> int[][]:
        \\    return [own xs]
        \\func returned_option(own xs: int[]) -> int[]?:
        \\    return Some(own xs)
        \\func my_take(own xs: int[]) -> int:
        \\    return len(xs)
        \\func through_call(own xs: int[]) -> int:
        \\    return my_take(own xs)
        \\func bare(own xs: int[]) -> int[]:
        \\    return xs
        \\func sink(row: Row) -> int:
        \\    return len(row.items)
        \\func nested(own xs: int[]) -> int:
        \\    return sink(Row(items=own xs))
        \\func appended(own xs: int[], mut rows: int[][]) -> Unit:
        \\    append(mut rows, own xs)
        \\func stored(own xs: int[], mut rows: int[][]) -> Unit:
        \\    rows[0] = own xs
        \\func fallible(own xs: int[]) -> int[] fails str:
        \\    return xs
        \\func carried(own row: Row) -> int[]:
        \\    return own row.items
        \\func fresh() -> int[]?:
        \\    return Some([1])
        \\func patterned() -> int[][]:
        \\    match fresh():
        \\        case Some(xs):
        \\            return [own xs]
        \\        case None:
        \\            return []
        \\func generic_take[T](own xs: T[]) -> int:
        \\    return len(xs)
        \\func generic_call(own xs: int[]) -> int:
        \\    return generic_take[int](own xs)
        \\@ensures(len(result) > 0)
        \\func contracted(own xs: int[]) -> int[]:
        \\    return xs
        \\@ensures(len(result) > 0)
        \\func contracted_fallible(own xs: int[]) -> int[] fails str:
        \\    return xs
        \\@ensures(len(result) > 0)
        \\func contracted_fallible_nested(own xs: int[]) -> int[][] fails str:
        \\    return [own xs]
        \\func main() -> int:
        \\    return 0
    , true);
    try std.testing.expect(outcome.accepted);
    try expectMove(a, outcome.report, "returned_record", "move", true);
    try expectMove(a, outcome.report, "returned_array", "move", true);
    try expectMove(a, outcome.report, "returned_option", "move", true);
    try expectMove(a, outcome.report, "through_call", "argument_move", true);
    try expectMove(a, outcome.report, "bare", "return_move", false);
    try expectMove(a, outcome.report, "nested", "move", true);
    try expectMove(a, outcome.report, "appended", "argument_move", true);
    try expectMove(a, outcome.report, "stored", "move", true);
    try expectMove(a, outcome.report, "fallible", "return_move", false);
    try expectMove(a, outcome.report, "carried", "return_field_move", true);
    try expectMove(a, outcome.report, "patterned", "move", true);
    try expectMove(a, outcome.report, "generic_call", "argument_move", true);
    try expectMove(a, outcome.report, "contracted", "return_move", false);
    try expectMove(a, outcome.report, "contracted_fallible", "return_move", false);
    try expectMove(a, outcome.report, "contracted_fallible_nested", "move", true);
    const projected = try run(a,
        \\record Row:
        \\    items: int[]
        \\@ensures(len(result) > 0)
        \\func contracted_field(own row: Row) -> int[]:
        \\    return row.items
        \\func main() -> int:
        \\    return 0
    , true);
    try std.testing.expect(!projected.accepted);
    try std.testing.expect(std.mem.indexOf(u8, projected.report, "E_SINGLE_OWNER_BORROW") != null);
    try std.testing.expect(std.mem.indexOf(u8, projected.report, "\"kind\":\"move\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, projected.report, "\"kind\":\"return_field_move\"") == null);
}

fn expectSourceCall(a: std.mem.Allocator, text: []const u8, expected: bool) !void {
    const src = try language.source.Source.init(a, "call-span.selka", text);
    var output: std.ArrayList(u8) = .empty;
    const observer: Observer = .{ .source = src, .sink = .{ .allocator = a, .output = &output } };
    try std.testing.expectEqual(expected, observer.sourceCall(.{ .start = 0, .end = text.len }));
}

test "ownership audit distinguishes indexed receiver calls from stores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectSourceCall(arena.allocator(), "mapping[key].append(item)", true);
    try expectSourceCall(arena.allocator(), "mapping[indexes[key]].append(item)", true);
    try expectSourceCall(arena.allocator(), "mapping[lookup(key)].append(item)", true);
    try expectSourceCall(arena.allocator(), "mapping[key] = item", false);
}

//! M5 names both source arguments and advises a writable local plus explicit store-back.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");

const declarations =
    \\func nested(mut xs: int[][], mut ys: int[]):
    \\    append(mut xs, [5])
    \\    append(mut ys, 9)
    \\func reverse(mut ys: int[], mut xs: int[][]):
    \\    append(mut ys, 9)
    \\    append(mut xs, [5])
    \\func named_nested(named mut xs: int[][], named mut ys: int[]):
    \\    append(mut xs, [5])
    \\    append(mut ys, 9)
    \\
;

const Diagnosed = struct { unit: support.Checked, failure: ownership.Failure };

fn diagnosed(a: std.mem.Allocator, source: []const u8) !Diagnosed {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    return .{ .unit = unit, .failure = failure };
}

fn refusal(a: std.mem.Allocator, source: []const u8) !Diagnosed {
    const result = try diagnosed(a, source);
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", result.failure.code);
    return result;
}

fn arguments(a: std.mem.Allocator, body: []const u8, earlier: []const u8, later: []const u8, place: []const u8) !void {
    const source = try std.mem.concat(a, u8, &.{ declarations, "\n", body });
    const result = try refusal(a, source);
    const failure = result.failure;
    try std.testing.expectEqual(language.ownership_rules.Rule.M5, failure.rule.?);
    try std.testing.expectEqualStrings(later, result.unit.src.?.text(failure.span));
    const related = failure.notes.related orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(earlier, result.unit.src.?.text(related.span));
    try std.testing.expect(related.span.start < failure.span.start);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, try std.fmt.allocPrint(a, "argument '{s}'", .{later[4..]})) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, try std.fmt.allocPrint(a, "argument '{s}'", .{earlier[4..]})) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, try std.fmt.allocPrint(a, "mut part = copy({s})", .{place})) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "pass `mut part`") != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, try std.fmt.allocPrint(a, "{s} = own part", .{place})) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "copy(value)") == null);
    try std.testing.expect(failure.copy.span == null and failure.copy.borrowed.len == 0);
    try std.testing.expect(failure.repair == .none);
}

// spec-case: MUT-EXCLUSIVE-3
test "F6 M5 names both mut arguments and gives declaration and own writeback advice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // migrate-embedded: skip original overlapping-mutable-argument diagnostic subject
    try arguments(arena.allocator(),
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    nested(mut a, mut a[0])
        \\    return 0
    , "mut a", "mut a[0]", "a[0]");
    const result = try refusal(arena.allocator(), declarations ++
        // migrate-embedded: skip original overlapping-mutable-argument diagnostic subject
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    nested(mut a, mut a[0])
        \\    return 0
    );
    try std.testing.expectEqualStrings(
        "mutable argument 'a[0]' overlaps earlier argument 'a'; mutable arguments must name disjoint storage. " ++
            "For a separate writable value, write `mut part = copy(a[0])`, pass `mut part` in this position, " ++
            "then write `a[0] = own part` after the call",
        result.failure.message,
    );
}

test "F6 M5 related arguments follow source order for reversed keyword and callback calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // migrate-embedded: skip original reversed overlapping-mutable-argument diagnostic subject
    try arguments(arena.allocator(),
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    reverse(mut a[0], mut a)
        \\    return 0
    , "mut a[0]", "mut a", "a");
    // migrate-embedded: skip original named overlapping-mutable-argument diagnostic subject
    try arguments(arena.allocator(),
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    named_nested(ys=mut a[0], xs=mut a)
        \\    return 0
    , "mut a[0]", "mut a", "a");
    // migrate-embedded: skip original callback overlapping-mutable-argument diagnostic subject
    try arguments(arena.allocator(),
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    const action = named_nested
        \\    action(ys=mut a[0], xs=mut a)
        \\    return 0
    , "mut a[0]", "mut a", "a");
}

test "F6 M5 manual writeback advice is a checked and verified program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rejected: build.Refusal = .{};
    var module = try support.buildSource(a, declarations ++
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    mut part = copy(a[0])
        \\    nested(mut a, mut part)
        \\    a[0] = own part
        \\    return a[0][2] + len(a)
    , &rejected);
    try std.testing.expectEqualStrings("", rejected.reason);
    try std.testing.expect(rejected.rule == null);
    const checked = try passes.run(a, &module, .verify);
    try support.verified(a, &module, checked.plans);
}

test "F6 M5 scalar mutable argument advice omits own and verifies the applied rewrite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        // migrate-embedded: skip original scalar overlapping-mutable-argument diagnostic subject
        \\func nested(mut xs: int[], mut item: int):
        \\    append(mut xs, 5)
        \\    item = 9
        \\func main() -> int:
        \\    mut a = [1, 2]
        \\    nested(mut a, mut a[0])
        \\    return a[0] + len(a)
    ;
    const result = try refusal(a, source);
    try std.testing.expectEqual(language.ownership_rules.Rule.M5, result.failure.rule.?);
    try std.testing.expectEqualStrings("mut a[0]", result.unit.src.?.text(result.failure.span));
    const related = result.failure.notes.related orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("mut a", result.unit.src.?.text(related.span));
    try std.testing.expectEqualStrings(
        "mutable argument 'a[0]' overlaps earlier argument 'a'; mutable arguments must name disjoint storage. " ++
            "For a separate writable value, write `mut part = copy(a[0])`, pass `mut part` in this position, " ++
            "then write `a[0] = part` after the call",
        result.failure.message,
    );
    try std.testing.expect(result.failure.copy.span == null and result.failure.copy.borrowed.len == 0);
    try std.testing.expect(result.failure.repair == .none);
    const call = "    nested(mut a, mut a[0])";
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, call));
    const fixed = try std.mem.replaceOwned(u8, a, source, call,
        \\    mut part = copy(a[0])
        \\    nested(mut a, mut part)
        \\    a[0] = part
    );
    var rejected: build.Refusal = .{};
    var module = try support.buildSource(a, fixed, &rejected);
    try std.testing.expectEqualStrings("", rejected.reason);
    try std.testing.expect(rejected.rule == null);
    const checked = try passes.run(a, &module, .verify);
    try support.verified(a, &module, checked.plans);
}

test "F6 M5 metadata preserves const receiver and live task refusal priority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const alias = try refusal(a, declarations ++
        // migrate-embedded: skip original live named alias refusal priority
        \\func main() -> int:
        \\    mut a = [[1, 2], [3]]
        \\    const alias = a
        \\    nested(mut a, mut a[0])
        \\    return len(alias)
    );
    try std.testing.expectEqual(language.ownership_rules.Rule.R2, alias.failure.rule.?);
    const receiver = try refusal(a,
        // migrate-embedded: skip original receiver evaluation refusal priority
        \\func change(mut xs: int[]) -> int:
        \\    append(mut xs, 3)
        \\    return 0
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    xs[change(mut xs)] = 9
        \\    return len(xs)
    );
    try std.testing.expectEqual(language.ownership_rules.Rule.R2, receiver.failure.rule.?);
    const task = try diagnosed(a,
        // migrate-embedded: skip original task loan refusal priority
        \\import parallel
        \\func total(xs: int[]) -> int:
        \\    return len(xs)
        \\func two(mut left: int[], mut right: int[]):
        \\    append(mut left, 1)
        \\    append(mut right, 2)
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, xs)
        \\        const n = task.result()
        \\        two(mut xs, mut xs)
        \\        return n
    );
    try std.testing.expectEqualStrings("E_TASK_LOAN", task.failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.K1, task.failure.rule.?);
}

test "F6 M5 argument metadata preserves move-only argument overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try refusal(arena.allocator(),
        // migrate-embedded: skip original move-only mutable-argument overlap
        \\func both(mut left: File, mut right: File) -> int:
        \\    return 0
        \\func forward(mut file: File) -> int:
        \\    return both(mut file, mut file)
        \\func main() -> int:
        \\    return 0
    );
    try std.testing.expectEqual(language.ownership_rules.Rule.M5, result.failure.rule.?);
    try std.testing.expect(result.failure.copy.span == null);
    try std.testing.expect(std.mem.indexOf(u8, result.failure.message, "cannot be copied") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.failure.message, "copy(") == null);
}

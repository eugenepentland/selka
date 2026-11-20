//! Postcondition staging preserves the source return's exact move boundary.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");

test "O4 contract return staging preserves bare fallible transfers without hidden copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\@ensures(len(result) > 0)
        \\func contracted(own xs: int[]) -> int[] fails str:
        \\    if len(xs) == 0:
        \\        fail "empty"
        \\    return xs
        \\func main() -> int:
        \\    match contracted([42]):
        \\        case Ok(xs):
        \\            return xs[0]
        \\        case Err(_):
        \\            return 1
    ;
    const checked = try support.checkSource(a, source);
    try std.testing.expect(checked.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var controls: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.endsWith(u8, function.name, "contracted")) continue;
        controls += 1;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .list_copy and inst.op != .dict_copy and inst.op != .str_from_view);
            try std.testing.expect(inst.op != .list_new and inst.op != .list_push);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), controls);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}

test "O4 contract return staging keeps nested moves explicit and bare own misplaced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { source: []const u8, before: []const u8, after: []const u8 }{
        .{
            .source =
            // migrate-embedded: skip intentional OWN-MARKER-1 misplaced bare return marker
            \\@ensures(len(result) > 0)
            \\func contracted(own xs: int[]) -> int[] fails str:
            \\    return own xs
            \\func main() -> int:
            \\    return 0
            ,
            .before = "return own xs",
            .after = "return xs",
        },
        .{
            .source =
            // migrate-embedded: skip intentional OWN-MARKER-1 missing nested return marker
            \\@ensures(len(result) > 0)
            \\func contracted(own xs: int[]) -> int[][] fails str:
            \\    return [xs]
            \\func main() -> int:
            \\    return 0
            ,
            .before = "[xs]",
            .after = "[own xs]",
        },
    };
    for (cases) |case| {
        const checked = try support.checkSource(a, case.source);
        try std.testing.expect(checked.passed);
        var failure: ownership.Failure = .{};
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
        try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
        try std.testing.expectEqual(language.ownership_rules.Rule.B2, failure.rule.?);
        try std.testing.expect(failure.repair == .explicit_fix);
        try std.testing.expectEqual(@as(usize, 1), failure.repair.explicit_fix.len);
        const edit = failure.repair.explicit_fix[0];
        const fixed = try std.mem.concat(a, u8, &.{ case.source[0..edit.span.start], edit.text, case.source[edit.span.end..] });
        const expected = try std.mem.replaceOwned(u8, a, case.source, case.before, case.after);
        try std.testing.expectEqualStrings(expected, fixed);
        const repaired = try support.checkSource(a, fixed);
        try std.testing.expect(repaired.passed);
        try ownership.checkWithSource(a, repaired.program.?, repaired.src.?, &failure);
    }
}

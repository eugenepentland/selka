//! H5 (lane OC, plan Part B stage O3): a plain text, bytes or list parameter stored bare in a local list or dictionary is held
//! as its frame block (RB1, `ir.Op.block_frame`), so the collection is a collection of borrows (RB2). The lowering makes one
//! `block_frame` per store site, which emission turns into one copy per call at most (`emit_block_frame.zig`), never a copy per
//! store. A collection that leaves its call keeps the refusal it had before H5, with its copy. Guest behaviour is
//! `tests/lang/frame_block_collections.selka`. The tests assert codes, rules and lines, not message text.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const ownership = @import("single_owner.zig");

/// How many instructions with `op` the functions named `name` hold.
fn operations(module: *const ir.Module, name: []const u8, op: ir.Op) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        if (!std.mem.eql(u8, local, name)) continue;
        for (function.insts.items) |inst| if (inst.op == op) {
            count += 1;
        };
    }
    return count;
}

/// `source` is refused with `code` and `rule` on line `line`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, rule: language.ownership_rules.Rule, line: usize) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
    try std.testing.expectEqual(line, std.mem.count(u8, source[0..failure.span.start], "\n") + 1);
}

test "H5 a bare text, bytes or list parameter in a local list or dictionary is one frame block per store, with no copy per store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\func texts(p: str, k: int) -> int:
        \\    mut l: str[] = []
        \\    for i in range(k):
        \\        append(mut l, p)
        \\    mut d: dict[int, str] = {}
        \\    d[0] = p
        \\    return len(l) + len(d)
        \\func raw(p: bytes, k: int) -> int:
        \\    mut l: bytes[] = []
        \\    for i in range(k):
        \\        append(mut l, p)
        \\    return len(l)
        \\func ints(p: int[], q: int[]) -> int:
        \\    mut l: int[][] = [q]
        \\    l[0] = p
        \\    return len(l)
        \\func main() -> int:
        \\    return texts("abc", 2) + raw(b"ab", 3) + ints([1], [2])
    , &refusal);
    try std.testing.expectEqual(@as(usize, 2), operations(&module, "texts", .block_frame));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "texts", .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), operations(&module, "raw", .block_frame));
    // The literal `[q]` appends `q` and the write stores `p`: two frame sites.
    try std.testing.expectEqual(@as(usize, 2), operations(&module, "ints", .block_frame));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "ints", .list_copy));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

test "H5 a collection holding a bare parameter that leaves its call keeps its refusal" {
    try refuses(std.testing.allocator,
        \\func returned(p: str) -> str[]:
        \\    mut l: str[] = []
        \\    append(mut l, p)
        \\    return l
        \\func main() -> int:
        \\    return len(returned("a"))
    , "E_SINGLE_OWNER_BORROW", .R1, 3);
    try refuses(std.testing.allocator,
        \\func into_out(p: str, mut out: str[][]) -> int:
        \\    mut l: str[] = []
        \\    append(mut l, p)
        \\    append(mut out, own l)
        \\    return len(out)
        \\func main() -> int:
        \\    mut out: str[][] = []
        \\    return into_out("a", mut out)
    , "E_SINGLE_OWNER_BORROW", .R1, 3);
    try refuses(std.testing.allocator,
        \\func dict_returned(p: bytes) -> dict[int, bytes]:
        \\    mut d: dict[int, bytes] = {}
        \\    d[1] = p
        \\    return d
        \\func main() -> int:
        \\    return len(dict_returned(b"a"))
    , "E_SINGLE_OWNER_BORROW", .R1, 3);
    try refuses(std.testing.allocator,
        \\func first_of(p: str) -> str from p:
        \\    mut l: str[] = []
        \\    append(mut l, p)
        \\    return l[0]
        \\func main() -> int:
        \\    return len(first_of("abc"[0:2]))
    , "E_SINGLE_OWNER_BORROW", .R1, 3);
}

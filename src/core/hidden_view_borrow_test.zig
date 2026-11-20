//! A text or bytes view lent where a borrowed block is needed is refused by lowering (Z3), in every build mode, instead
//! of being copied by `view_materialize` with no `copy(...)` written: the compiler inserts no copy by itself. Before this,
//! only a `--verify-facts` build reported such a copy (E_CORE_HIDDEN_COPY) and a Debug compiler's ownership validation
//! caught some of them (J4); a ReleaseFast build copied silently. No program the check accepts reaches it: the check and
//! lowering share the tables that decide what is lent, a bare parameter is lent as its frame block (RB1, H5), and every
//! slice or `from` result in such a position is refused by the check (lane OC, no-silent-copy).
const std = @import("std");
const build = @import("build.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");

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

test "a text or bytes view where a borrowed block is needed is refused, and a block is lent" {
    try std.testing.expect(build.hiddenViewBorrow(.str_view) != null);
    try std.testing.expect(build.hiddenViewBorrow(.bytes_view) != null);
    try std.testing.expect(std.mem.indexOf(u8, build.hiddenViewBorrow(.str_view).?, "no copy(...) written") != null);
    try std.testing.expectEqual(@as(?[]const u8, null), build.hiddenViewBorrow(.str));
    try std.testing.expectEqual(@as(?[]const u8, null), build.hiddenViewBorrow(.bytes));
    try std.testing.expectEqual(@as(?[]const u8, null), build.hiddenViewBorrow(.i64));
}

test "the lent shapes that hold a view parameter build with no hidden copy: frame blocks, not borrows of the view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    // Unchecked lowering (no ownership check): a bytes parameter read in a loop is a phi, and a dictionary write stages its
    // value; both are still lent as frame blocks, so the refusal does not fire and nothing copies the view.
    var module = try support.buildSource(a,
        \\func raw(p: bytes, k: int) -> int:
        \\    mut l: bytes[] = []
        \\    mut d: dict[int, bytes] = {}
        \\    for i in range(k):
        \\        append(mut l, p)
        \\        d[i] = p
        \\    return len(l) + len(d)
        \\func main() -> int:
        \\    return raw(b"ab", 3)
    , &refusal);
    try std.testing.expectEqualStrings("", refusal.reason);
    try std.testing.expectEqual(@as(usize, 2), operations(&module, "raw", .block_frame));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

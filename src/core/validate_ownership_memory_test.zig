//! The ownership validator's memory (docs/design/ownership-certificates.md §5, plan §5a): a function with thousands of blocks
//! and values is validated under a byte bound that a counting allocator measures, so the test is deterministic and does not
//! read the process's resident set. The bound is what keeps the validator within a quarter of a compile's own peak.
const std = @import("std");
const validate = @import("validate_ownership.zig");
const parse = @import("ownership_parse.zig");

/// An allocator that counts the bytes it has handed out and not yet taken back, and their highest value.
const Counting = struct {
    parent: std.mem.Allocator,
    live: usize = 0,
    peak: usize = 0,

    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn grow(self: *Counting, bytes: usize) void {
        self.live += bytes;
        self.peak = @max(self.peak, self.live);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(context));
        const bytes = self.parent.rawAlloc(len, alignment, ra) orelse return null;
        self.grow(len);
        return bytes;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(context));
        if (!self.parent.rawResize(memory, alignment, new_len, ra)) return false;
        self.live -= memory.len;
        self.grow(new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(context));
        const moved = self.parent.rawRemap(memory, alignment, new_len, ra) orelse return null;
        self.live -= memory.len;
        self.grow(new_len);
        return moved;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *Counting = @ptrCast(@alignCast(context));
        self.parent.rawFree(memory, alignment, ra);
        self.live -= memory.len;
    }
};

/// A function of `units` diamonds in a row, `4 * units` blocks: each unit's first block makes an owner and a view of it, one
/// arm reads the view, the join reads it again and drops the owner. Roughly `7 * units` values live in `D` and `R` at once.
fn generated(a: std.mem.Allocator, units: usize) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "function big result scalar from - unchecked -\nparam 0 %0 scalar\nblock b- preds -\n");
    try text.appendSlice(a, "inst %0 param Parameter reads - consumes - state scalar parents -\n");
    try text.appendSlice(a, "inst %1 iconst Constant reads - consumes - state scalar parents - imm 1\n");
    for (0..units) |unit| {
        const base = 2 + unit * 7;
        const block = unit * 4;
        if (unit == 0) try text.appendSlice(a, "block b0 preds -\n") else try text.print(a, "block b{d} preds b{d}\n", .{ block, block - 1 });
        try text.print(a, "inst %{d} list_new Fresh reads %1 consumes - state owned parents -\n", .{base});
        try text.print(a, "inst %{d} list_view_of View reads %{d} consumes - state borrowed parents %{d}\n", .{ base + 1, base, base });
        try text.print(a, "term branch %0 b{d} b{d}\n", .{ block + 1, block + 2 });
        try text.print(a, "block b{d} preds b{d}\n", .{ block + 1, block });
        try text.print(a, "inst %{d} list_len Inspect reads %{d} consumes - state scalar parents -\n", .{ base + 2, base + 1 });
        try text.print(a, "term jump b{d}\n", .{block + 3});
        try text.print(a, "block b{d} preds b{d}\n", .{ block + 2, block });
        try text.print(a, "term jump b{d}\n", .{block + 3});
        try text.print(a, "block b{d} preds b{d},b{d}\n", .{ block + 3, block + 1, block + 2 });
        try text.print(a, "inst %{d} list_len Inspect reads %{d} consumes - state scalar parents -\n", .{ base + 3, base + 1 });
        try text.print(a, "inst - drop Drop reads - consumes %{d} state none parents -\n", .{base});
        if (unit + 1 == units) {
            try text.appendSlice(a, "term ret %1\n");
        } else try text.print(a, "term jump b{d}\n", .{block + 4});
    }
    try text.appendSlice(a, "end\n");
    return text.items;
}

test "a function of thousands of blocks and values is validated within a byte bound" {
    var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer backing.deinit();
    const units: usize = 1500;
    const text = try generated(backing.allocator(), units);
    var problem: parse.Problem = .{};
    const functions = try parse.parse(backing.allocator(), text, &problem);
    var counting: Counting = .{ .parent = std.testing.allocator };
    var arena = std.heap.ArenaAllocator.init(counting.allocator());
    const verdict = try validate.validate(arena.allocator(), functions[0]);
    arena.deinit();
    try std.testing.expectEqual(validate.Verdict.accepted, verdict);
    try std.testing.expectEqual(@as(usize, 0), counting.live);
    // About 4 KiB a block: the entry state of each block and the tables. Borrows whose owner was consumed leave `D` and `R`, so
    // the states do not grow with the number of units; before they were dropped the same function took 3.4 GB.
    try std.testing.expect(counting.peak <= 48 << 20);
}

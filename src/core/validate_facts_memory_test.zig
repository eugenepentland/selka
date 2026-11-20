//! The fact validator's memory (docs/design/fact-certificates.md §6, plan §5a): a function with thousands of blocks and values is
//! validated under a byte bound that a counting allocator measures, so the test is deterministic and does not read the process's
//! resident set. The bound is what keeps the validator within a quarter of a compile's own peak.
const std = @import("std");
const text = @import("fact_text.zig");
const validate = @import("validate_facts.zig");

/// An allocator that counts the bytes it has handed out and not yet taken back, and their highest value.
// twin-drift-ok: the ownership validator's memory test counts bytes the same way; the two files test different validators and share nothing else
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

/// A function of `units` diamonds in a row, `3 * units + 1` blocks: each header compares the running value with 5, one arm adds
/// one, the join takes the hull. Every value is stated in [0, 10]; about three values per unit, each viewed under the branch
/// refinements of every header above it.
fn generated(a: std.mem.Allocator, units: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "fact-certificate-v1\nfunction big linkage internal addr 0 params i64 ret i64\nparam 0 0 10\nreturns 0 10\nblock b- reach preds -\n");
    try out.appendSlice(a, "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 10\ninst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n");
    try out.appendSlice(a, "inst %2 iconst i64 none a - b - x - imm 5 aux 0 range -\n");
    for (0..units + 1) |unit| {
        const running: usize = if (unit == 0) 0 else 5 + 3 * (unit - 1);
        const header = 3 * unit;
        if (unit == 0) try out.appendSlice(a, "block b0 reach preds -\n") else try out.print(a, "block b{d} reach preds b{d},b{d}\n", .{ header, header - 2, header - 1 });
        if (unit > 0) try out.print(a, "phi %{d} i64 edges b{d}:%{d},b{d}:%{d} range 0 10\n", .{ running, header - 2, 4 + 3 * (unit - 1), header - 1, if (unit == 1) 0 else 5 + 3 * (unit - 2) });
        if (unit == units) {
            try out.print(a, "term ret %{d}\n", .{running});
            break;
        }
        try out.print(a, "inst %{d} cmp bool none a %{d} b %2 x - imm 2 aux 0 range 0 1\nterm branch %{d} b{d} b{d}\n", .{ 3 + 3 * unit, running, 3 + 3 * unit, header + 1, header + 2 });
        try out.print(a, "block b{d} reach preds b{d}\ninst %{d} add i64 exact a %{d} b %1 x - imm 0 aux 0 range 0 10\nterm jump b{d}\n", .{ header + 1, header, 4 + 3 * unit, running, header + 3 });
        try out.print(a, "block b{d} reach preds b{d}\nterm jump b{d}\n", .{ header + 2, header, header + 3 });
    }
    try out.appendSlice(a, "end\n");
    return out.items;
}

test "a function of thousands of blocks and values is validated within a byte bound" {
    var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer backing.deinit();
    const units: usize = 2000;
    const source = try generated(backing.allocator(), units);
    var problem: text.Problem = .{};
    const module = try text.parse(backing.allocator(), source, &problem);
    var counting: Counting = .{ .parent = std.testing.allocator };
    const verdicts = try validate.validate(backing.allocator(), counting.allocator(), module, null);
    try std.testing.expectEqual(@as(usize, 1), verdicts.len);
    try std.testing.expect(verdicts[0] == .accepted);
    try std.testing.expectEqual(@as(usize, 0), counting.live);
    // About 3.6 MB for the 6,001 blocks and 12,000 values: the tables are linear in them, and only the views an instruction asks
    // for are kept. A table of every (value, block) pair would take over a gigabyte here.
    try std.testing.expect(counting.peak <= 16 << 20);
}

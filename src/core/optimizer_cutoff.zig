//! The early cutoff of callers (G3p (c), D-G3p-15): which deferred functions a recomputed function reaches.
//!
//! A deferred function keeps the results its entry holds. Before the cutoff, every transitive caller of a function without an
//! entry was recomputed, whether or not anything it reads had changed. With the cutoff only the functions without an entry start
//! recomputed, and a deferred function is recomputed from the stage at which something it reads from a recomputed function
//! differs from what its entry was built under. This file holds the state that comparison needs: a record, per function, of what
//! this build changed (`Cut`). The comparisons themselves are `optimizer_shortcut.zig`'s, since they read the entries.
const std = @import("std");
const effects = @import("effects.zig");

/// How the optimizer decides which deferred functions a recomputed function reaches.
pub const Mode = enum {
    /// Every transitive caller of a function without an entry is recomputed (the rule before the cutoff).
    transitive,
    /// A deferred function is recomputed from the stage at which something it reads from a recomputed function differs from what
    /// its entry was built under.
    cutoff,
    /// `cutoff`, and each deferred function that reads a recomputed one is also derived afresh and compared with its entry; a
    /// difference is a finding (`Cut.findings`), a read the cutoff missed.
    verify,
};

/// How a function's raw body stands against the entry it started from.
pub const Base = enum(u8) {
    /// It differs from its entry's in more than its source positions, or it has no entry.
    changed,
    /// It differs only in source positions: the entry the second lookup found holds the same body (a comment above it moved it).
    shifted,
    /// It is its entry's.
    same,
};

/// The bits of `Cut.moved`: what this build changed about a function, against the entry it started from.
pub const Moved = struct {
    /// The output (digest or ancestry) of the checkpoint after the leaf inlining, the CFG inlining, the unswitching and the
    /// parameter inlining. `Phase` of `optimizer_shortcut.zig` minus one is the shift.
    pub const phases: u8 = 0x0f;
    /// The phases of `phases` whose checkpoint differs from the entry's in source positions only (the same body, inlined the same way):
    /// the bit of a phase here is that bit shifted left by eight. A reader that did not inline the function never sees the difference.
    pub const shifted: u16 = 0x0f00;
    /// The function's return interval of the last field round.
    pub const returned: u8 = 0x10;
    /// The function's effect after the parameter inlining.
    pub const effect: u8 = 0x20;
    /// The function's effect in its final body, for emission.
    pub const emission: u8 = 0x40;
};

/// What one build changed, against the entries it started from, indexed like the module.
pub const Cut = struct {
    mode: Mode = .transitive,
    /// Per function, the bits of `Moved` this build set.
    moved: []u16 = &.{},
    /// How the function's raw body stands against its entry's.
    base: []Base = &.{},
    /// Which manifest the function's entry came from (`slot_none` when none did): two entries of one manifest were built together.
    slot: []u8 = &.{},
    /// The emission effect a recomputed function's entry held before this build replaced it.
    old_emission: []?effects.Reused = &.{},
    /// Deferred functions the verify mode derived afresh and found different from their entry.
    findings: u32 = 0,
    /// The first of them, as the function's ordinal and the stage that found it (`cache.Stage` as an integer), for the report.
    first: ?[2]u32 = null,

    /// The marker of a function whose entry came from no manifest.
    pub const slot_none: u8 = 0xff;

    /// A cut for `count` functions: nothing moved yet and every function without an entry.
    pub fn init(a: std.mem.Allocator, count: usize, mode: Mode) std.mem.Allocator.Error!Cut {
        const moved = try a.alloc(u16, count);
        errdefer a.free(moved);
        @memset(moved, 0);
        const base = try a.alloc(Base, count);
        errdefer a.free(base);
        @memset(base, .changed);
        const slot = try a.alloc(u8, count);
        errdefer a.free(slot);
        @memset(slot, slot_none);
        const emission = try a.alloc(?effects.Reused, count);
        @memset(emission, null);
        return .{ .mode = mode, .moved = moved, .base = base, .slot = slot, .old_emission = emission };
    }

    /// Note whether function `index`'s raw body is the one its entry holds (`was`), as the build now has it (`now`).
    pub fn noteBase(self: *Cut, index: usize, was: ?[32]u8, now: ?[32]u8) void {
        if (index >= self.base.len) return;
        self.base[index] = if (was == null or now == null or !std.mem.eql(u8, &was.?, &now.?)) .changed else .same;
    }

    /// Note that function `index` is found by the second lookup and its raw body is the entry's but for source positions (`moved`: they
    /// differ).
    pub fn noteShifted(self: *Cut, index: usize, moved: bool) void {
        if (index >= self.base.len) return;
        self.base[index] = if (moved) .shifted else .same;
    }

    /// Whether the cutoff decides what is recomputed (`cutoff` and `verify`).
    pub fn active(self: *const Cut) bool {
        return self.mode != .transitive and self.moved.len != 0;
    }

    /// Whether `function` changed at checkpoint `phase` (1 leaf .. 4 parameter) or, for phase 0, in its raw body. A function
    /// outside the cut (a declaration a fusion appended) never changes.
    pub fn changedAt(self: *const Cut, function: u32, phase: u8) bool {
        if (function >= self.moved.len) return false;
        if (self.base[function] == .changed) return true;
        if (phase == 0) return false;
        return self.moved[function] & (@as(u16, 1) << @intCast(phase - 1)) != 0;
    }

    /// Whether `function` differs from its entry at checkpoint `phase` (0 for its raw body) in source positions only. It is not also
    /// `changedAt`: a reader inlines the difference or never sees it.
    pub fn shiftedAt(self: *const Cut, function: u32, phase: u8) bool {
        if (function >= self.moved.len or self.changedAt(function, phase)) return false;
        if (phase == 0) return self.base[function] == .shifted;
        return self.moved[function] & (@as(u16, 1) << @intCast(phase - 1 + 8)) != 0;
    }

    /// Note that function `index`'s checkpoint at the phase of `bit` (one of `Moved.phases`) is its entry's but for source positions
    /// (`moved`: they differ); it has not changed.
    pub fn noteSameBody(self: *Cut, index: usize, bit: u8, moved: bool) void {
        if (index >= self.moved.len) return;
        self.moved[index] &= ~@as(u16, bit);
        if (moved) self.moved[index] |= @as(u16, bit) << 8;
    }

    /// Whether `function` has the bits `bits` set, or no entry at all.
    pub fn has(self: *const Cut, function: u32, bits: u8) bool {
        if (function >= self.moved.len) return false;
        return self.base[function] == .changed or self.moved[function] & bits != 0;
    }

    /// Note a finding: deferred `function` derived afresh at `stage` differs from its entry.
    pub fn found(self: *Cut, function: u32, stage: u32) void {
        self.findings += 1;
        if (self.first == null) self.first = .{ function, stage };
    }

    /// Note that `function` changed in `bits`.
    pub fn mark(self: *Cut, function: usize, bits: u8) void {
        if (function < self.moved.len) self.moved[function] |= bits;
    }
};

/// The functions that share a call cycle with a function whose result is computed afresh (`fresh`), over `edges` (the callees of each
/// function). The effects are a least fixed point from nothing: a cycle's members reuse their stored effects only while none of the
/// cycle is recomputed, since a recomputed member that starts from a member's old effect cannot lose what that effect held.
pub fn sharesCycle(a: std.mem.Allocator, edges: []const []const u32, fresh: []const bool) std.mem.Allocator.Error![]bool {
    const count = edges.len;
    const marks = try a.alloc(bool, count);
    errdefer a.free(marks);
    @memset(marks, false);
    const order = try a.alloc(u32, count);
    defer a.free(order);
    const low = try a.alloc(u32, count);
    defer a.free(low);
    @memset(order, 0);
    const on_stack = try a.alloc(bool, count);
    defer a.free(on_stack);
    @memset(on_stack, false);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(a);
    var frames: std.ArrayList(struct { node: u32, next: u32 }) = .empty;
    defer frames.deinit(a);
    var clock: u32 = 0;
    for (0..count) |root| {
        if (order[root] != 0) continue;
        clock += 1;
        order[root] = clock;
        low[root] = clock;
        try stack.append(a, @intCast(root));
        on_stack[root] = true;
        try frames.append(a, .{ .node = @intCast(root), .next = 0 });
        while (frames.items.len != 0) {
            const top = &frames.items[frames.items.len - 1];
            const node = top.node;
            if (top.next < edges[node].len) {
                const target = edges[node][top.next];
                top.next += 1;
                if (target >= count) continue;
                if (order[target] == 0) {
                    clock += 1;
                    order[target] = clock;
                    low[target] = clock;
                    try stack.append(a, target);
                    on_stack[target] = true;
                    try frames.append(a, .{ .node = target, .next = 0 });
                } else if (on_stack[target]) low[node] = @min(low[node], order[target]);
                continue;
            }
            _ = frames.pop();
            if (frames.items.len != 0) {
                const parent = frames.items[frames.items.len - 1].node;
                low[parent] = @min(low[parent], low[node]);
            }
            if (low[node] != order[node]) continue;
            // `node` roots a component: its members are the stack above it.
            const start = std.mem.lastIndexOfScalar(u32, stack.items, node).?;
            const members = stack.items[start..];
            var any = false;
            for (members) |member| any = any or fresh[member];
            if (members.len > 1 and any) for (members) |member| {
                marks[member] = true;
            };
            for (members) |member| on_stack[member] = false;
            stack.shrinkRetainingCapacity(start);
        }
    }
    return marks;
}

test "a call cycle that holds a recomputed function marks all its members, and a plain chain marks none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 -> 1 -> 2 -> 1 (a cycle of 1 and 2), 2 -> 3, 3 -> 3 (a self call), 4 -> 0.
    const edges = [_][]const u32{ &.{1}, &.{2}, &.{ 1, 3 }, &.{3}, &.{0} };
    const none = try sharesCycle(a, &edges, &.{ false, false, false, false, false });
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false, false }, none);
    const fresh = try sharesCycle(a, &edges, &.{ false, true, false, false, false });
    try std.testing.expectEqualSlices(bool, &.{ false, true, true, false, false }, fresh);
    const outside = try sharesCycle(a, &edges, &.{ true, false, false, false, true });
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false, false }, outside);
}

test "a function without an entry changed at every phase, and a recomputed one only where it was marked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cut = try Cut.init(arena.allocator(), 3, .cutoff);
    cut.base[1] = .same;
    cut.mark(1, Moved.phases & 0b0010);
    try std.testing.expect(cut.changedAt(0, 0));
    try std.testing.expect(cut.changedAt(0, 3));
    try std.testing.expect(!cut.changedAt(1, 0));
    try std.testing.expect(!cut.changedAt(1, 1));
    try std.testing.expect(cut.changedAt(1, 2));
    try std.testing.expect(!cut.changedAt(7, 2));
    try std.testing.expect(cut.has(0, Moved.effect));
    try std.testing.expect(!cut.has(1, Moved.effect));
}

test "a function that only moved is shifted at the phases it moved, and changed where it differs in more" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var cut = try Cut.init(arena.allocator(), 3, .cutoff);
    cut.noteShifted(2, true);
    cut.noteSameBody(2, 0b0010, true);
    try std.testing.expect(!cut.changedAt(2, 0));
    try std.testing.expect(cut.shiftedAt(2, 0));
    try std.testing.expect(cut.shiftedAt(2, 2));
    try std.testing.expect(!cut.shiftedAt(2, 1));
    // A function with no entry is changed, not shifted; a phase that moved in more than its positions is changed only.
    try std.testing.expect(cut.changedAt(0, 0));
    try std.testing.expect(!cut.shiftedAt(0, 0));
    cut.mark(2, 0b0010);
    try std.testing.expect(cut.changedAt(2, 2));
    try std.testing.expect(!cut.shiftedAt(2, 2));
    cut.noteShifted(1, false);
    try std.testing.expect(!cut.changedAt(1, 0));
    try std.testing.expect(!cut.shiftedAt(1, 0));
}

//! What the ownership pass knows about each value, kept for the certificates
//! (docs/design/ownership-certificates.md §2, §4).
//!
//! `own.zig` classifies every value of a function (owned, borrowed, immortal, stack, emptied) and the
//! owners each borrowed value lives in. It used to discard that table once the drops were scheduled.
//! With a `Sink` set, it writes the table down instead: one `Capture` per function, indexed by the
//! instruction numbers the pass saw (the instructions it adds afterwards, and the scalar rewrites of the
//! later passes, are described by `ownership_export.zig`). This file holds only data, so the validator
//! can read it without reaching the pass.
const std = @import("std");
const ir = @import("ir.zig");

/// The ownership state of a value (design §2). `none` is a value-less instruction or a forwarded copy.
pub const State = enum(u8) {
    /// No value: a store, a terminator, a drop; or a `copy`, which names its operand.
    none,
    /// An unmanaged value: integers, floats, booleans, function references, inline scalar arrays.
    scalar,
    /// A static block or the null owner: never freed, and consuming it changes nothing.
    immortal,
    /// A managed value this function destroys or transfers exactly once.
    owned,
    /// An owned list the stack-promotion pass placed in the frame: no destruction, never escapes.
    stack,
    /// A managed value that lives inside, or is lent by, other values (its parents).
    borrowed,
    /// An aggregate whose managed parts were all taken by owned reads: it owns nothing itself
    /// and is never consumed.
    emptied,

    /// The spelling in the certificate format.
    pub fn token(self: State) []const u8 {
        return @tagName(self);
    }
};

/// An owner a trap path abandons (design §9, entry 55): live on the edge `from -> to` into a block every path of which ends in a
/// trap, and needed by nothing from `to` on. The pass skips its death there; the certificate lists it instead.
pub const Abandon = struct { from: u32, to: u32, value: ir.Ref };

/// The ownership table of one function as the pass left it, by instruction index.
pub const Capture = struct {
    /// How many instructions the table covers: the function's instruction count when the pass
    /// scheduled its drops. Later instructions are drops, cleanup phis and their `undef`s.
    len: u32,
    states: []const State,
    /// `parent_offsets[i]..parent_offsets[i + 1]` indexes `parent_values`: the values instruction `i`
    /// borrows from (a borrowed value) or is lent by (an owned aggregate holding a view).
    parent_offsets: []const u32,
    parent_values: []const ir.Ref,
    /// The owners the trap paths of the function abandon, by edge.
    abandons: []const Abandon = &.{},

    /// The state the pass gave instruction `index`, or null when the table does not cover it.
    pub fn state(self: Capture, index: usize) ?State {
        return if (index < self.len) self.states[index] else null;
    }

    /// The parents the pass recorded for instruction `index` (empty beyond the table).
    pub fn parents(self: Capture, index: usize) []const ir.Ref {
        if (index >= self.len) return &.{};
        return self.parent_values[self.parent_offsets[index]..self.parent_offsets[index + 1]];
    }
};

/// Where the pass writes its tables: one per function index. A sink that is asked to `check` also counts the
/// functions the passes validated and holds the message of the first rejection.
pub const Sink = struct {
    functions: std.AutoHashMapUnmanaged(u32, Capture) = .empty,
    /// The passes validate each function they finish (`validate_ownership.zig`).
    check: bool = false,
    /// A rejection does not stop the passes: the certificates are still written, and the build fails afterwards.
    keep_going: bool = false,
    validated: u32 = 0,
    unchecked: u32 = 0,
    /// The constructors the construct-read rule counted (`validate_ownership.build_mode`): owned or emptied ones that read a
    /// borrow they neither take the owner of nor list as a loan. A build counts them; the gate refuses them.
    construct_reads: u32 = 0,
    /// Why a function was rejected, once one was.
    rejection: ?[]const u8 = null,

    /// Keep `table` as the table of function `index`, replacing an earlier one.
    pub fn put(self: *Sink, a: std.mem.Allocator, index: u32, table: Capture) std.mem.Allocator.Error!void {
        try self.functions.put(a, index, table);
    }

    /// The table of function `index`, if the pass ran on it.
    pub fn get(self: *const Sink, index: u32) ?Capture {
        return self.functions.get(index);
    }
};

/// Build a table from per-instruction states and parent lists.
pub fn capture(a: std.mem.Allocator, states: []const State, parents: []const []const ir.Ref) std.mem.Allocator.Error!Capture {
    const offsets = try a.alloc(u32, states.len + 1);
    var total: usize = 0;
    for (parents) |list| total += list.len;
    const values = try a.alloc(ir.Ref, total);
    var next: u32 = 0;
    for (parents, 0..) |list, i| {
        offsets[i] = next;
        @memcpy(values[next..][0..list.len], list);
        next += @intCast(list.len);
    }
    offsets[states.len] = next;
    return .{ .len = @intCast(states.len), .states = try a.dupe(State, states), .parent_offsets = offsets, .parent_values = values };
}

test "a capture answers by instruction index and says nothing beyond its table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first: ir.Ref = @fromBackingInt(0);
    const table = try capture(a, &.{ .owned, .borrowed, .scalar }, &.{ &.{}, &.{first}, &.{} });
    try std.testing.expectEqual(@as(?State, .borrowed), table.state(1));
    try std.testing.expectEqual(@as(?State, null), table.state(3));
    try std.testing.expectEqual(@as(usize, 1), table.parents(1).len);
    try std.testing.expectEqual(@as(usize, 0), table.parents(2).len);
    try std.testing.expectEqual(@as(usize, 0), table.parents(9).len);
}

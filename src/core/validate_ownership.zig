//! The ownership validator (docs/design/ownership-certificates.md §5): J1–J8 over one function's certificate.
//!
//! It reads only the form of `ownership_function.zig`, the operation table of `ownership_ops.zig` and the operation
//! names of `ir.zig`, so a bug of `own.zig` cannot be shared with it. One forward pass over the reachable blocks in
//! reverse post-order proposes an entry state for each block; a recheck then runs every block again from its entry
//! state and compares each live outgoing edge, back edges included, with the entry state of its target.
//!
//! The state carried through a function is `(L, D, P)`:
//! - `L`, the owned values defined and not yet consumed;
//! - `D`, the borrowed values defined on every path to the point;
//! - `P`, the open takes: `(container, slot)` pairs of an owned container whose slot an owned read took and no store
//!   has refilled yet, and the slots an `emptied` aggregate still owes a take for.
const std = @import("std");
const ir = @import("ir.zig");
const ops = @import("ownership_ops.zig");
const form = @import("ownership_function.zig");

const Allocator = std.mem.Allocator;
const State = form.State;
const Bits = std.DynamicBitSetUnmanaged;

/// A debug compiler checks every function it compiles, as it checks the IR (`verify_ir.enabled`).
pub const enabled = @import("builtin").mode == .debug;

/// The judgments of design §5.
pub const Check = enum {
    j1,
    j2,
    j3,
    j4,
    j5,
    j6,
    j7,
    j8,

    /// `J1` … `J8`.
    pub fn label(self: Check) []const u8 {
        return switch (self) {
            .j1 => "J1",
            .j2 => "J2",
            .j3 => "J3",
            .j4 => "J4",
            .j5 => "J5",
            .j6 => "J6",
            .j7 => "J7",
            .j8 => "J8",
        };
    }

    /// What the judgment checks, for a report.
    pub fn title(self: Check) []const u8 {
        return switch (self) {
            .j1 => "states follow operations",
            .j2 => "exactly once",
            .j3 => "used only while live",
            .j4 => "loans end with their roots",
            .j5 => "borrowed values are never taken",
            .j6 => "one instruction never takes what it also reads",
            .j7 => "stack values stay put",
            .j8 => "takes are closed",
        };
    }

    /// The nearest source rules of the judgment (docs/ownership-rules.md, design §7).
    pub fn rules(self: Check) []const u8 {
        return switch (self) {
            .j1 => "R1, R3, R5, V1, M1",
            .j2 => "B3, B5, B6, C3, W1, Z1, K2",
            .j3 => "B3",
            .j4 => "R2, R3, V3, X1",
            .j5 => "R4, V2, V4, W4, P3",
            .j6 => "M5, M6",
            .j7 => "S1 stack promotion",
            .j8 => "B7",
        };
    }
};

/// Where and why a function was rejected. `block` and `index` locate the failure: the block id, and the instruction's
/// position in it (the number of instructions for the terminator and the edges leaving it); both are null for the
/// signature and the pseudo-block.
pub const Failure = struct {
    check: Check,
    block: ?u32 = null,
    index: ?u32 = null,
    detail: []const u8,
};

/// The answer for one function.
pub const Verdict = union(enum) {
    accepted,
    /// The function is skipped and counted, never counted as validated.
    unchecked: form.Reason,
    rejected: Failure,
};

/// What the construct-read rule (J6 `construct-read`, lane VAL) does with a constructor whose result is owned or emptied and
/// that reads a borrowed operand it neither takes the owner of nor lists as a loan: refuse the function, or count the
/// constructor and judge the rest of the function as if the rule did not exist.
pub const Mode = enum { refuse, count };

/// The mode of every build's validator: count (phase 1 of lane VAL, 12 November 2026, the way the union-tag rule went in,
/// D-VL-18). The gate refuses: `selka validate-certificates` and the Lean checker in the `ownership-proof` action, and
/// `dump-ir --certificate --validate`. Builds refuse too once the gate's corpora and the project sweeps have shown no count
/// for the period the coordinator sets, and the user says so: that is this one value, `.refuse`, and the test "a build counts
/// a constructor that reads a borrow it neither owns nor lends" then expects the refusal instead.
pub const build_mode: Mode = .count;

/// How one validation runs: what the construct-read rule does, and where a counting run adds the constructors it counted.
pub const Options = struct { construct_read: Mode = .refuse, counted: ?*u32 = null };

/// Check `f`; `a` holds the work and the text of a failure and may be reset by the caller afterwards. Every rule refuses.
pub fn validate(a: Allocator, f: form.Function) Allocator.Error!Verdict {
    return validateWith(a, f, .{});
}

/// Check `f` as `validate` does, with the construct-read rule in the mode `options` names.
pub fn validateWith(a: Allocator, f: form.Function, options: Options) Allocator.Error!Verdict {
    if (f.unchecked) |reason| return .{ .unchecked = reason };
    var checker = try Checker.begin(a, f);
    checker.options = options;
    if (try checker.pre()) |failure| return .{ .rejected = failure };
    if (try checker.solve()) |failure| return .{ .rejected = failure };
    if (try checker.recheck()) |failure| return .{ .rejected = failure };
    return .accepted;
}

/// A rejection as one report line: the function, the place, the judgment, its rules and what failed.
pub fn describe(a: Allocator, name: []const u8, failure: Failure) Allocator.Error![]const u8 {
    var where: []const u8 = "in the signature or the pseudo-block";
    if (failure.block) |block| where = try std.fmt.allocPrint(a, "at block b{d}, instruction {d}", .{ block, failure.index orelse 0 });
    return std.fmt.allocPrint(a, "ownership validation rejected {s} {s}: {s} ({s}; rules {s}): {s}", .{ name, where, failure.check.label(), failure.check.title(), failure.check.rules(), failure.detail });
}

/// What a comparison looks at: another value, or a constant, compared by value.
const Operand = union(enum) { value: u32, constant: u64 };

/// A test a branch decides. Two branches decide the same test when they branch on the same value, or on two
/// comparisons of the same operation and predicate over the same operands (design §5, guards).
const Test = union(enum) {
    value: u32,
    compare: struct { op: ir.Op, predicate: u64, lhs: Operand, rhs: Operand },

    /// Whether the test looks at value `v`: redefining `v` makes the test mean something else.
    fn mentions(self: Test, v: u32) bool {
        return switch (self) {
            .value => |u| u == v,
            .compare => |c| (c.lhs == .value and c.lhs.value == v) or (c.rhs == .value and c.rhs.value == v),
        };
    }
};

/// A decision taken on the way to a point: `cond` came out `when`.
const Guard = struct { cond: Test, when: bool };

fn sameGuard(x: ?Guard, y: ?Guard) bool {
    const one = x orelse return y == null;
    const two = y orelse return false;
    return one.when == two.when and std.meta.eql(one.cond, two.cond);
}

/// A slot of an owned container; the key `*` stands for any slot of it.
const SlotRoot = struct { owner: u32, key: []const u8 };

/// Where a loan lives (design §2): an owned value, one slot of an owned container, or the caller's allocation.
const Root = union(enum) { value: u32, caller: u32, slot: SlotRoot };

fn rootEql(x: Root, y: Root) bool {
    return switch (x) {
        .value => |v| y == .value and y.value == v,
        .caller => |v| y == .caller and y.caller == v,
        .slot => |v| y == .slot and y.slot.owner == v.owner and std.mem.eql(u8, y.slot.key, v.key),
    };
}

/// Whether the loan on `root` ends when slot `key` of `owner` is taken.
fn endsWithTake(root: Root, owner: u32, key: []const u8) bool {
    return switch (root) {
        .slot => |slot| slot.owner == owner and (std.mem.eql(u8, slot.key, "*") or std.mem.eql(u8, slot.key, key)),
        else => false,
    };
}

/// An owner that a phi consumes: its roots and the loans it held pass to the phi.
const Move = struct { from: u32, to: u32 };

/// A loan: `name` (a borrowed value, or an owned value that holds one) lives in `root` on this path. A `forward` loan
/// is on an owner that is defined later in the block (the take a view was written ahead of): it is dead until then.
const Held = struct { name: u32, root: Root, forward: bool = false };

/// An open take or an owed slot.
const Entry = struct {
    container: u32,
    key: []const u8,
    /// An `emptied` aggregate's slot that no owned read has taken yet.
    owed: bool,
    /// The slot is open only where `guard` holds: the take was made under a branch whose test a later branch decides
    /// again, and the paths that did not take it joined the paths that did.
    guard: ?Guard = null,

    /// Open on every path to the point.
    fn definite(self: Entry) bool {
        return self.guard == null;
    }
};

/// The state at a program point.
const Point = struct {
    l: Bits,
    d: Bits,
    p: std.ArrayList(Entry),
    /// The branch decisions known to hold at the point.
    path: std.ArrayList(Guard),
    /// For each borrowed value of `D`, and each owned value that holds a loan, the roots it lives in on this path (design
    /// §2). When an owned phi or a constructor takes an owner over, the roots that named the owner name the new holder:
    /// the storage does not move.
    r: std.ArrayList(Held),
    /// The owned values that were the group of some lend on the way here (design §10.4, `group-join`): only a call that
    /// returns nothing may consume one.
    groups: std.ArrayList(u32) = .empty,

    fn clone(self: *const Point, a: Allocator) Allocator.Error!Point {
        return .{ .l = try self.l.clone(a), .d = try self.d.clone(a), .p = try self.p.clone(a), .path = try self.path.clone(a), .r = try self.r.clone(a), .groups = try self.groups.clone(a) };
    }

    /// Whether `v` was the group of a lend on the way here.
    fn isGroup(self: *const Point, v: u32) bool {
        return std.mem.indexOfScalar(u32, self.groups.items, v) != null;
    }

    /// `v` is the group of a lend.
    fn markGroup(self: *Point, a: Allocator, v: u32) Allocator.Error!void {
        if (!self.isGroup(v)) try self.groups.append(a, v);
    }

    /// `v` is no longer a group (consumed, or defined again).
    fn unmarkGroup(self: *Point, v: u32) void {
        if (std.mem.indexOfScalar(u32, self.groups.items, v)) |at| _ = self.groups.swapRemove(at);
    }

    /// A phi took the group `from` over: the storage is the same, and so is the obligation to end it.
    fn moveGroup(self: *Point, from: u32, to: u32) void {
        if (!self.isGroup(from)) return;
        self.unmarkGroup(to);
        if (std.mem.indexOfScalar(u32, self.groups.items, from)) |at| self.groups.items[at] = to;
    }

    fn has(self: *const Point, name: u32, root: Root) bool {
        for (self.r.items) |held| if (held.name == name and rootEql(held.root, root)) return true;
        return false;
    }

    fn hold(self: *Point, a: Allocator, name: u32, root: Root, forward: bool) Allocator.Error!void {
        if (!self.has(name, root)) try self.r.append(a, .{ .name = name, .root = root, .forward = forward });
    }

    /// Forget the roots recorded for `name`.
    fn release(self: *Point, name: u32) void {
        var i: usize = 0;
        while (i < self.r.items.len) {
            if (self.r.items[i].name == name) _ = self.r.swapRemove(i) else i += 1;
        }
    }

    /// Drop the roots of every name that is neither in `D` nor in `L`.
    fn prune(self: *Point) void {
        var i: usize = 0;
        while (i < self.r.items.len) {
            const name = self.r.items[i].name;
            if (self.d.isSet(name) or self.l.isSet(name)) i += 1 else _ = self.r.swapRemove(i);
        }
    }

    /// The owner `from` became the owner `to`: every root that named it names the new holder. A constructor leaves of a
    /// slot root the wildcard slot of the aggregate; a phi keeps the slot.
    fn renameRoots(self: *Point, from: u32, to: u32, wild: bool) void {
        for (self.r.items) |*held| switch (held.root) {
            .value => |v| if (v == from) {
                held.root = .{ .value = to };
            },
            .slot => |slot| if (slot.owner == from) {
                held.root = .{ .slot = .{ .owner = to, .key = if (wild) "*" else slot.key } };
            },
            .caller => {},
        };
        var i: usize = 0;
        while (i < self.r.items.len) : (i += 1) {
            var j = i + 1;
            while (j < self.r.items.len) {
                if (self.r.items[j].name == self.r.items[i].name and rootEql(self.r.items[j].root, self.r.items[i].root)) _ = self.r.swapRemove(j) else j += 1;
            }
        }
    }

    /// A holder keeps no loan on its own storage: the roots that name `v` itself are dropped from the loans of `v`.
    fn dropSelf(self: *Point, v: u32) void {
        var i: usize = 0;
        while (i < self.r.items.len) {
            const held = self.r.items[i];
            const on_itself = held.name == v and switch (held.root) {
                .value => |r| r == v,
                .slot => |slot| slot.owner == v,
                .caller => false,
            };
            if (on_itself) _ = self.r.swapRemove(i) else i += 1;
        }
    }

    /// The holder `from` was consumed by a phi that now holds what it held.
    fn renameHolder(self: *Point, from: u32, to: u32) void {
        for (self.r.items) |*held| {
            if (held.name == from) held.name = to;
        }
    }

    /// Whether some entry is guarded by a test that looks at value `v`.
    fn guardedOn(self: *const Point, v: u32) bool {
        for (self.p.items) |entry| if (entry.guard) |g| {
            if (g.cond.mentions(v)) return true;
        };
        return false;
    }

    fn find(self: *const Point, container: u32, key: []const u8, owed: bool) ?usize {
        for (self.p.items, 0..) |entry, i| {
            if (entry.container == container and entry.owed == owed and std.mem.eql(u8, entry.key, key)) return i;
        }
        return null;
    }

    fn pending(self: *const Point, container: u32) bool {
        for (self.p.items) |entry| if (entry.container == container and !entry.owed) return true;
        return false;
    }

    /// Every entry of `container` that is not owed moves to `to`.
    fn rename(self: *Point, container: u32, to: u32) void {
        for (self.p.items) |*entry| {
            if (entry.container == container and !entry.owed) entry.container = to;
        }
    }

    /// Whether the decision `g` is known to hold here.
    fn holds(self: *const Point, g: Guard) bool {
        for (self.path.items) |known| if (sameGuard(known, g)) return true;
        return false;
    }

    /// Whether the opposite of `g` is known to hold here.
    fn holdsNot(self: *const Point, g: Guard) bool {
        return self.holds(.{ .cond = g.cond, .when = !g.when });
    }

    /// Value `v` was defined again: a decision about it is stale. (A guarded take that depends on it is refused before
    /// the definition: `guardedOn`.)
    fn forget(self: *Point, v: u32) void {
        var i: usize = 0;
        while (i < self.path.items.len) {
            if (self.path.items[i].cond.mentions(v)) _ = self.path.swapRemove(i) else i += 1;
        }
    }

    /// A branch decided `g` on the way here: remember it, and settle the entries that were guarded by the same test.
    fn decide(self: *Point, a: Allocator, g: Guard) Allocator.Error!void {
        var i: usize = 0;
        while (i < self.path.items.len) {
            if (std.meta.eql(self.path.items[i].cond, g.cond)) _ = self.path.swapRemove(i) else i += 1;
        }
        try self.path.append(a, g);
        i = 0;
        while (i < self.p.items.len) {
            const own_guard = self.p.items[i].guard orelse {
                i += 1;
                continue;
            };
            if (!std.meta.eql(own_guard.cond, g.cond)) {
                i += 1;
            } else if (own_guard.when == g.when) {
                self.p.items[i].guard = null;
                i += 1;
            } else _ = self.p.swapRemove(i);
        }
    }
};

/// Whether the entry `e` an edge carries is the entry `k` the block expects: unguarded where the block's is, and where
/// the block's is guarded, guarded the same way or unguarded with the decision known on the edge.
fn entryFits(k: Entry, e: Entry, edge: *const Point) bool {
    const g = k.guard orelse return e.guard == null;
    return sameGuard(e.guard, g) or (e.guard == null and edge.holds(g));
}

/// Whether `edge` may flow into a block whose entry state is `known` as far as the open takes go: every entry the edge
/// has is one the block expects (an unguarded one where the block's is guarded needs the guard to hold on the edge), every
/// entry the block expects that the edge lacks is guarded by a decision the edge made the other way, and every decision
/// the block relies on holds on the edge.
fn compatible(known: *const Point, edge: *const Point) bool {
    for (edge.p.items) |e| {
        const at = known.find(e.container, e.key, e.owed) orelse return false;
        if (!entryFits(known.p.items[at], e, edge)) return false;
    }
    for (known.p.items) |k| {
        // A guarded take names a container that is live where the take is open (design §9, entry 52).
        if (k.guard != null and !k.owed) {
            if (!known.l.isSet(k.container) or !edge.l.isSet(k.container)) return false;
        }
        if (edge.find(k.container, k.key, k.owed) != null) continue;
        const g = k.guard orelse return false;
        if (!edge.holdsNot(g)) return false;
    }
    for (known.path.items) |g| if (!edge.holds(g)) return false;
    for (edge.r.items) |held| {
        if (known.d.isSet(held.name) and !known.has(held.name, held.root)) return false;
    }
    return true;
}

/// Join the open takes of two arrivals: an entry on only one of them, or open on both only under a guard, is kept
/// under a decision the arrivals made differently. Null when some entry has no such decision.
fn joinEntries(a: Allocator, x: *const Point, y: *const Point) Allocator.Error!?std.ArrayList(Entry) {
    var out: std.ArrayList(Entry) = .empty;
    for (x.p.items) |one| {
        const other = if (y.find(one.container, one.key, one.owed)) |at| y.p.items[at] else null;
        const joined = guardedBetween(one, other, x, y) orelse return null;
        try out.append(a, joined);
    }
    for (y.p.items) |two| {
        if (x.find(two.container, two.key, two.owed) != null) continue;
        try out.append(a, guardedBetween(two, null, y, x) orelse return null);
    }
    return out;
}

/// The entry that stands for `mine` (on the arrival `here`) and `theirs` (its counterpart on `there`, if any).
fn guardedBetween(mine: Entry, theirs: ?Entry, here: *const Point, there: *const Point) ?Entry {
    if (mine.owed) return if (theirs != null and theirs.?.owed) mine else null;
    if (theirs) |other| {
        if (sameGuard(mine.guard, other.guard)) return mine;
        // Open on both, but guarded on one: it is open under that guard, which the other arrival must satisfy.
        if (mine.guard) |g| return if (other.guard == null and there.holds(g)) mine else null;
        const g = other.guard.?;
        var joined = mine;
        joined.guard = g;
        return if (here.holds(g)) joined else null;
    }
    if (mine.guard) |g| return if (there.holdsNot(g)) mine else null;
    for (here.path.items) |g| {
        if (!there.holdsNot(g)) continue;
        var joined = mine;
        joined.guard = g;
        return joined;
    }
    return null;
}

/// The decisions both arrivals know.
fn commonPath(a: Allocator, x: *const Point, y: *const Point) Allocator.Error!std.ArrayList(Guard) {
    var out: std.ArrayList(Guard) = .empty;
    for (x.path.items) |g| if (y.holds(g)) try out.append(a, g);
    return out;
}

const Checker = struct {
    /// Where the work of the current step goes: the checker's arena, or while a block is run, a scratch arena that is reset
    /// once its states are copied out.
    a: Allocator,
    /// The checker's arena: the tables, the entry state of each block and the text of a failure.
    keep: Allocator,
    f: form.Function,
    /// One more than the largest value id mentioned anywhere.
    n: usize,
    states: []State,
    parents: [][]const form.Parent,
    defs: []?*const form.Inst,
    /// Block id to position in `f.blocks`.
    index_of: []?u32,
    entry: []?Point,
    /// Per block position: every path from the block ends in `unreachable` (the trap region, design §9, entry 55).
    region: []bool = &.{},
    /// A message the current check builds before it fails.
    note: []const u8 = "",
    /// What the construct-read rule does (`Options`).
    options: Options = .{},
    /// The recheck is running: a counting rule counts there, once per instruction, and not in the forward passes.
    rechecking: bool = false,

    fn begin(a: Allocator, f: form.Function) Allocator.Error!Checker {
        var max_value: usize = 0;
        for (f.params) |param| max_value = @max(max_value, param.value);
        for (f.pre) |inst| max_value = scanInst(max_value, inst);
        var max_block: usize = 0;
        for (f.blocks) |block| {
            max_block = @max(max_block, block.id);
            for (block.phis) |phi| {
                max_value = @max(max_value, phi.value);
                for (phi.edges) |edge| max_value = @max(max_value, edge.value);
            }
            for (block.insts) |inst| max_value = scanInst(max_value, inst);
            switch (block.term) {
                .branch => |branch| max_value = @max(max_value, branch.condition),
                .ret => |value| if (value) |v| {
                    max_value = @max(max_value, v);
                },
                else => {},
            }
        }
        const n = max_value + 1;
        var self: Checker = .{
            .a = a,
            .keep = a,
            .f = f,
            .n = n,
            .states = try a.alloc(State, n),
            .parents = try a.alloc([]const form.Parent, n),
            .defs = try a.alloc(?*const form.Inst, n),
            .index_of = try a.alloc(?u32, max_block + 1),
            .entry = try a.alloc(?Point, f.blocks.len),
        };
        @memset(self.states, .none);
        @memset(self.parents, &.{});
        @memset(self.defs, null);
        @memset(self.index_of, null);
        @memset(self.entry, null);
        for (f.params) |param| self.states[param.value] = param.state;
        for (f.pre) |*inst| self.define(inst);
        for (f.blocks, 0..) |block, i| {
            self.index_of[block.id] = @intCast(i);
            for (block.phis) |phi| {
                self.states[phi.value] = phi.result.state;
                self.parents[phi.value] = phi.result.parents;
            }
            for (block.insts) |*inst| self.define(inst);
        }
        return self;
    }

    fn scanInst(seen: usize, inst: form.Inst) usize {
        var most = seen;
        if (inst.value) |v| most = @max(most, v);
        for (inst.reads) |r| most = @max(most, r);
        for (inst.consumes) |c| most = @max(most, c);
        for (inst.result.parents) |parent| switch (parent) {
            .value => |v| most = @max(most, v),
            .caller => {},
        };
        if (inst.extras.call.from) |values| for (values) |v| {
            most = @max(most, v);
        };
        if (inst.extras.loans.lent) |group| most = @max(most, group);
        return most;
    }

    fn define(self: *Checker, inst: *const form.Inst) void {
        const value = inst.value orelse return;
        self.states[value] = inst.result.state;
        self.parents[value] = inst.result.parents;
        self.defs[value] = inst;
    }

    /// A failure of `check` at the given place. The text is built in the arena the checker owns; should that run out
    /// the failure still stands, with a plain detail.
    fn fail(self: *Checker, check: Check, block: ?u32, index: ?u32, comptime format: []const u8, args: anytype) Failure {
        const detail = std.fmt.allocPrint(self.keep, format, args) catch "the detail of the failure did not fit in memory";
        return .{ .check = check, .block = block, .index = index, .detail = detail };
    }

    // ---- the signature and the pseudo-block ---------------------------------------------------------------

    fn pre(self: *Checker) Allocator.Error!?Failure {
        const f = self.f;
        for (f.returns.from) |position| {
            if (position >= f.params.len) return self.fail(.j1, null, null, "the result's from names parameter {d} of {d}", .{ position, f.params.len });
        }
        for (f.params, 0..) |param, i| {
            for (f.params[0..i]) |earlier| {
                if (earlier.value == param.value) return self.fail(.j2, null, null, "parameters {d} share a value", .{i});
            }
            const def = self.defs[param.value] orelse return self.fail(.j1, null, null, "parameter {d} (%{d}) has no line in the pseudo-block", .{ i, param.value });
            if (def.class != .parameter or def.result.state != param.state) return self.fail(.j1, null, null, "parameter {d} (%{d}) is stated {s} but its line says {s}", .{ i, param.value, param.state.token(), def.result.state.token() });
            switch (param.state) {
                .borrowed => {
                    if (def.result.parents.len != 1 or def.result.parents[0] != .caller or def.result.parents[0].caller != i)
                        return self.fail(.j1, null, null, "borrowed parameter {d} must be borrowed from caller({d}) alone", .{ i, i });
                },
                .owned, .scalar => if (def.result.parents.len != 0) return self.fail(.j1, null, null, "parameter {d} has parents", .{i}),
                else => return self.fail(.j1, null, null, "parameter {d} has state {s}", .{ i, param.state.token() }),
            }
        }
        for (f.pre) |inst| {
            if (inst.reads.len != 0 or inst.consumes.len != 0) return self.fail(.j1, null, null, "a pseudo-block line reads or consumes", .{});
            switch (inst.class) {
                .parameter => if (inst.value == null) return self.fail(.j1, null, null, "a parameter line defines no value", .{}),
                // An `undef` of the unit type defines no value.
                .constant => switch (inst.result.state) {
                    .scalar, .immortal => {},
                    // An `undef` of the unit type: named when something uses it as an operand.
                    .none => if (inst.op != .undef) return self.fail(.j1, null, null, "a {s} constant has state none", .{@tagName(inst.op)}),
                    else => return self.fail(.j1, null, null, "a constant has state {s}", .{inst.result.state.token()}),
                },
                else => return self.fail(.j1, null, null, "a {s} instruction in the pseudo-block", .{inst.class.token()}),
            }
            if (inst.class != ops.classOf(inst.op)) return self.fail(.j1, null, null, "a pseudo-block line is {s} but its operation is {s}", .{ inst.class.token(), ops.classOf(inst.op).token() });
        }
        if (try self.calleeTable()) |failure| return failure;
        for (f.blocks) |block| {
            if (try self.abandonShape(block)) |failure| return failure;
        }
        if (f.blocks.len == 0 or f.blocks[0].id != 0) return self.fail(.j1, null, null, "the function has no entry block b0", .{});
        if (f.blocks[0].phis.len != 0) return self.fail(.j1, null, null, "the entry block has phis", .{});
        // The proven checker judges `emptied` aggregates over every block with the other function-wide checks.
        if (try self.emptiedFault()) |failure| return failure;
        return null;
    }

    /// One use of a value that something reads, consumes, phis or terminates with: where it is, whether it is the first
    /// read of a projection, and the slot that projection takes.
    const Use = struct { block: u32, head: bool, slot: ?[]const u8 };

    /// The uses of each `emptied` value of the function, over every block; empty when no value is `emptied`. A phi that
    /// defines an `emptied` value is no use but a fault, reported by the second result.
    fn emptiedUses(self: *Checker) Allocator.Error!struct { uses: std.AutoHashMapUnmanaged(u32, std.ArrayList(Use)), phi: bool } {
        var emptied: std.AutoHashMapUnmanaged(u32, std.ArrayList(Use)) = .empty;
        for (self.f.blocks) |block| {
            for (block.phis) |phi| if (phi.result.state == .emptied) return .{ .uses = emptied, .phi = true };
            for (block.insts) |inst| if (inst.value) |value| if (inst.result.state == .emptied) try emptied.put(self.a, value, .empty);
        }
        if (emptied.count() == 0) return .{ .uses = emptied, .phi = false };
        for (self.f.blocks) |block| {
            for (block.insts) |inst| {
                for (inst.reads, 0..) |read, position| {
                    const head = inst.class == .project and position == 0 and !listed(inst.consumes, read);
                    if (emptied.getPtr(read)) |uses| try uses.append(self.a, .{ .block = block.id, .head = head, .slot = inst.extras.slot });
                }
                for (inst.consumes) |consumed| {
                    if (emptied.getPtr(consumed)) |uses| try uses.append(self.a, .{ .block = block.id, .head = false, .slot = null });
                }
            }
            for (block.phis) |phi| for (phi.edges) |edge| {
                if (emptied.getPtr(edge.value)) |uses| try uses.append(self.a, .{ .block = block.id, .head = false, .slot = null });
            };
            const last: ?u32 = switch (block.term) {
                .branch => |branch| branch.condition,
                .ret => |value| value,
                .jump, .unreachable_path => null,
            };
            if (last) |value| if (emptied.getPtr(value)) |uses| try uses.append(self.a, .{ .block = block.id, .head = false, .slot = null });
        }
        return .{ .uses = emptied, .phi = false };
    }

    /// J8 `emptiedOk` of the proven checker, over every block whether or not an edge reaches it: an `emptied` value is
    /// defined by an instruction, every use of it is the first read of a projection in the block that defines it, each slot
    /// it lists is taken exactly once, and no other slot is taken. When it fails the place is where `emptiedBadUse` of the
    /// checker finds a misuse (an instruction), or none when no one instruction is at fault.
    fn emptiedFault(self: *Checker) Allocator.Error!?Failure {
        const found = try self.emptiedUses();
        if (found.phi) return self.emptiedMisuse();
        if (found.uses.count() == 0) return null;
        for (self.f.blocks) |block| for (block.insts) |inst| {
            const value = inst.value orelse continue;
            const uses = (found.uses.get(value) orelse continue).items;
            if (!emptiedUsesFit(block.id, inst.extras.slots orelse &.{}, uses)) return self.emptiedMisuse();
        };
        return null;
    }

    /// Whether every use of an `emptied` value defined in block `home` is the first read of a projection there, each of its
    /// `slots` is taken once, and nothing takes another slot.
    fn emptiedUsesFit(home: u32, slots_listed: []const []const u8, uses: []const Use) bool {
        for (uses) |use| {
            if (!use.head or use.block != home) return false;
            if (use.slot) |key| if (!containsKey(slots_listed, key)) return false;
        }
        for (slots_listed) |key| {
            var taken: usize = 0;
            for (uses) |use| if (use.slot) |used| {
                taken += @intFromBool(std.mem.eql(u8, used, key));
            };
            if (taken != 1) return false;
        }
        return true;
    }

    fn containsKey(keys: []const []const u8, key: []const u8) bool {
        for (keys) |item| if (std.mem.eql(u8, item, key)) return true;
        return false;
    }

    /// Whether taking slot `key` of the `emptied` aggregate `container` is a misuse: the aggregate does not list the slot, or
    /// an earlier instruction of the block (`before`) took it already.
    fn takesTwice(self: *Checker, before: []const form.Inst, container: u32, key: []const u8) bool {
        if (self.states[container] != .emptied) return false;
        const defined = self.defs[container] orelse return false;
        if (!containsKey(defined.extras.slots orelse &.{}, key)) return true;
        for (before) |earlier| {
            if (earlier.class != .project or earlier.reads.len == 0 or earlier.reads[0] != container) continue;
            if (earlier.extras.slot) |taken| if (std.mem.eql(u8, taken, key)) return true;
        }
        return false;
    }

    /// The failure of a function whose `emptied` values are misused, placed as `emptiedBadUse` of the proven checker places
    /// it: at the first instruction that uses an `emptied` value as a whole (consumes it, or reads it other than as the
    /// container of a projection) or takes a slot its container does not list or an earlier instruction of the block took.
    fn emptiedMisuse(self: *Checker) Failure {
        for (self.f.blocks) |block| for (block.insts, 0..) |inst, k| {
            var whole = false;
            for (inst.consumes) |consumed| whole = whole or self.states[consumed] == .emptied;
            for (inst.reads, 0..) |read, position| whole = whole or (self.states[read] == .emptied and !(inst.class == .project and position == 0));
            var bad_take = false;
            if (inst.class == .project and inst.reads.len != 0) {
                if (inst.extras.slot) |key| bad_take = self.takesTwice(block.insts[0..k], inst.reads[0], key);
            }
            if (whole or bad_take) return self.fail(.j8, block.id, @intCast(k), "an emptied value is misused (emptied)", .{});
        };
        return self.fail(.j8, null, null, "an emptied value is misused (emptied)", .{});
    }

    /// J1 of the `abandon` lines of a block: each names a predecessor, once, and lists a value once.
    fn abandonShape(self: *Checker, block: form.Block) Allocator.Error!?Failure {
        for (block.abandons, 0..) |gone, i| {
            if (std.mem.indexOfScalar(u32, block.preds, gone.from) == null)
                return self.fail(.j1, block.id, null, "an abandon line names b{d}, which is not a predecessor (abandon-shape)", .{gone.from});
            for (block.abandons[0..i]) |earlier| {
                if (earlier.from == gone.from) return self.fail(.j1, block.id, null, "two abandon lines name b{d} (abandon-shape)", .{gone.from});
            }
            var k: usize = 1;
            while (k < gone.values.len) : (k += 1) {
                if (gone.values[k] <= gone.values[k - 1])
                    return self.fail(.j1, block.id, null, "the values abandoned on the edge from b{d} are not strictly ascending (abandon-shape)", .{gone.from});
            }
        }
        return null;
    }

    fn entryPoint(self: *Checker) Allocator.Error!Point {
        const l = try Bits.initEmpty(self.a, self.n);
        const d = try Bits.initEmpty(self.a, self.n);
        var point: Point = .{ .l = l, .d = d, .p = .empty, .path = .empty, .r = .empty };
        for (self.f.params) |param| switch (param.state) {
            .owned => point.l.set(param.value),
            .borrowed => {
                point.d.set(param.value);
                for (self.parents[param.value]) |parent| switch (parent) {
                    .caller => |i| try point.hold(self.a, param.value, .{ .caller = i }, false),
                    .value => {},
                };
            },
            else => {},
        };
        return point;
    }

    // ---- the forward pass and the recheck -----------------------------------------------------------------

    /// The reachable blocks in reverse post-order, by position in `f.blocks`.
    fn reversePostOrder(self: *Checker) Allocator.Error![]const u32 {
        const count = self.f.blocks.len;
        const seen = try self.a.alloc(bool, count);
        @memset(seen, false);
        var post: std.ArrayList(u32) = .empty;
        const Frame = struct { block: u32, next: u8 };
        var stack: std.ArrayList(Frame) = .empty;
        seen[0] = true;
        try stack.append(self.a, .{ .block = 0, .next = 0 });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const targets = successors(self.f.blocks[top.block].term);
            if (top.next < targets.len) {
                const id = targets.items[top.next];
                top.next += 1;
                const target = self.blockAt(id) orelse continue;
                if (seen[target]) continue;
                seen[target] = true;
                try stack.append(self.a, .{ .block = target, .next = 0 });
            } else {
                try post.append(self.a, top.block);
                _ = stack.pop();
            }
        }
        std.mem.reverse(u32, post.items);
        return post.items;
    }

    fn blockAt(self: *Checker, id: u32) ?u32 {
        return if (id < self.index_of.len) self.index_of[id] else null;
    }

    const Successors = struct {
        items: [2]u32 = undefined,
        len: u8 = 0,
    };

    fn successors(term: form.Term) Successors {
        var out: Successors = .{};
        switch (term) {
            .jump => |target| {
                out.items[0] = target;
                out.len = 1;
            },
            .branch => |branch| {
                out.items[0] = branch.then;
                out.len = 1;
                if (branch.otherwise != branch.then) {
                    out.items[1] = branch.otherwise;
                    out.len = 2;
                }
            },
            else => {},
        }
        return out;
    }

    /// Phase one: carry the state through the blocks in reverse post-order, again and again until no block's entry state
    /// changes, and record the entry state of each block. The first edge into a block sets it; every later edge, back
    /// edges included, only narrows `D`, widens the roots and joins the open takes. A failure here stops the propagation out
    /// of its block; the recheck reports it.
    fn solve(self: *Checker) Allocator.Error!?Failure {
        const order = try self.reversePostOrder();
        self.region = try self.regionOf();
        self.entry[0] = try self.entryPoint();
        const heads = try self.loopHeads(order);
        var scratch = std.heap.ArenaAllocator.init(self.keep);
        defer scratch.deinit();
        defer self.a = self.keep;
        var rounds: usize = 0;
        var changed = true;
        while (changed and rounds <= self.f.blocks.len + 2) : (rounds += 1) {
            changed = false;
            for (order) |bi| {
                self.a = scratch.allocator();
                defer _ = scratch.reset(.retain_capacity);
                if (try self.carry(bi, heads)) changed = true;
            }
        }
        return null;
    }

    /// Run block position `bi` from its entry state and send the state along each edge it can take to the entry state of its
    /// target. True when some entry state changed. The states of the step are scratch: what an entry keeps is copied.
    fn carry(self: *Checker, bi: u32, heads: []const bool) Allocator.Error!bool {
        const start = self.entry[bi] orelse return false;
        var point = try start.clone(self.a);
        const block = self.f.blocks[bi];
        if (try self.runBlock(bi, &point) != null) return false;
        var changed = false;
        const targets = successors(block.term);
        for (targets.items[0..targets.len]) |id| {
            const target = self.blockAt(id) orelse continue;
            if (self.infeasible(&point, bi, target)) continue;
            var edge = (try self.edgeState(bi, &point, target)) orelse continue;
            if (self.entry[target]) |*known| {
                if (try self.merge(known, &edge)) changed = true;
            } else {
                // The decisions known when a loop is entered need not hold on its back edges.
                if (heads[target]) edge.path.clearRetainingCapacity();
                self.entry[target] = try edge.clone(self.keep);
                changed = true;
            }
        }
        return changed;
    }

    /// The blocks some edge returns to: a successor that is not after its source in the order.
    fn loopHeads(self: *Checker, order: []const u32) Allocator.Error![]bool {
        const position = try self.a.alloc(usize, self.f.blocks.len);
        @memset(position, std.math.maxInt(usize));
        for (order, 0..) |bi, at| position[bi] = at;
        const heads = try self.a.alloc(bool, self.f.blocks.len);
        @memset(heads, false);
        for (order) |bi| {
            const targets = successors(self.f.blocks[bi].term);
            for (targets.items[0..targets.len]) |id| {
                const target = self.blockAt(id) orelse continue;
                if (position[target] <= position[bi]) heads[target] = true;
            }
        }
        return heads;
    }

    /// How much an entry state holds, so that a merge can tell whether it changed anything.
    fn measure(point: *const Point) [6]usize {
        var guarded: usize = 0;
        for (point.p.items) |entry| guarded += @intFromBool(entry.guard != null);
        return .{ point.l.count(), point.d.count(), point.r.items.len + point.p.items.len, guarded, point.path.items.len, point.groups.items.len };
    }

    /// A later edge into a block whose entry state is `known`: it narrows `D`, widens the roots and joins the open takes and the
    /// decisions known. When some take has no decision to hang on, the open takes stay as they were and the recheck reports the
    /// edges that differ. True when `known` changed.
    fn merge(self: *Checker, known: *Point, edge: *const Point) Allocator.Error!bool {
        const before = measure(known);
        for (edge.groups.items) |group| try known.markGroup(self.keep, group);
        known.d.setIntersection(edge.d);
        for (edge.r.items) |held| try known.hold(self.keep, held.name, held.root, held.forward);
        if (try joinEntries(self.keep, known, edge)) |joined| {
            known.p = joined;
            known.path = try commonPath(self.keep, known, edge);
        }
        known.prune();
        return !std.mem.eql(usize, &before, &measure(known));
    }

    /// Phase two: run every block again from its entry state and compare each live edge with its target's entry.
    fn recheck(self: *Checker) Allocator.Error!?Failure {
        var scratch = std.heap.ArenaAllocator.init(self.keep);
        defer scratch.deinit();
        defer self.a = self.keep;
        self.rechecking = true;
        defer self.rechecking = false;
        for (0..self.f.blocks.len) |bi| {
            self.a = scratch.allocator();
            defer _ = scratch.reset(.retain_capacity);
            if (try self.recheckBlock(@intCast(bi))) |failure| return failure;
        }
        return null;
    }

    /// Run block position `bi` again from its entry state and compare each edge it can take with its target's entry state.
    fn recheckBlock(self: *Checker, bi: u32) Allocator.Error!?Failure {
        const block = self.f.blocks[bi];
        const start = self.entry[bi] orelse return null;
        var point = try start.clone(self.a);
        if (try self.runBlock(bi, &point)) |failure| return failure;
        const targets = successors(block.term);
        const where: u32 = @intCast(block.insts.len);
        for (targets.items[0..targets.len]) |id| {
            const target = self.blockAt(id) orelse return self.fail(.j1, block.id, where, "block b{d} jumps to b{d}, which the function does not list", .{ block.id, id });
            if (self.infeasible(&point, bi, target)) continue;
            if (try self.edgeFailure(bi, &point, target)) |check| return self.fail(check, block.id, where, "{s}", .{self.note});
            const edge = (try self.edgeState(bi, &point, target)).?;
            const known = self.entry[target] orelse return self.fail(.j1, block.id, where, "the forward pass never reached b{d}", .{id});
            if (!sameBits(known.l, edge.l)) return self.fail(.j2, block.id, where, "the live owners differ between the edges into b{d}", .{id});
            if (!compatible(&known, &edge)) return self.fail(.j8, block.id, where, "the open takes differ between the edges into b{d}, or one is open only under a decision the edge did not make", .{id});
            if (!known.d.subsetOf(edge.d)) return self.fail(.j4, block.id, where, "b{d} needs a borrowed name that an edge into it does not define", .{id});
        }
        return null;
    }

    /// The trap region (design §9, entry 55): the blocks every path from which ends in `unreachable`. A block belongs to it when it
    /// ends in `unreachable`, or has successors and all of them belong. The pass schedules no drop in it (the process ends at the
    /// trap), so an `abandon` line may list owners on an edge into it; the region is nothing else for the checks. A cycle that
    /// never reaches a trap is not in it.
    fn regionOf(self: *Checker) Allocator.Error![]bool {
        const found = try self.a.alloc(bool, self.f.blocks.len);
        for (self.f.blocks, found) |block, *trap| trap.* = block.term == .unreachable_path;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.f.blocks, 0..) |block, bi| {
                if (found[bi]) continue;
                const targets = successors(block.term);
                if (targets.len == 0) continue;
                var all = true;
                for (targets.items[0..targets.len]) |id| {
                    const target = self.blockAt(id) orelse {
                        all = false;
                        break;
                    };
                    all = all and found[target];
                }
                if (all) {
                    found[bi] = true;
                    changed = true;
                }
            }
        }
        return found;
    }

    /// The owners block `target` says the edge from block id `origin` abandons, if it lists any.
    fn abandonedOn(target: form.Block, origin: u32) ?[]const u32 {
        for (target.abandons) |gone| if (gone.from == origin) return gone.values;
        return null;
    }

    /// Apply the abandons of an edge to its state: the owners leave `L`, and the open takes with a listed container leave `P`.
    /// `D` and `R` stay as they are: a view of an abandoned owner, and an owner that holds a loan on one, are unusable because
    /// an owned root of theirs is no longer live, as after a drop.
    fn abandon(point: *Point, values: []const u32) void {
        for (values) |v| {
            point.l.unset(v);
            point.unmarkGroup(v);
            var i: usize = 0;
            while (i < point.p.items.len) {
                if (point.p.items[i].container == v) _ = point.p.swapRemove(i) else i += 1;
            }
        }
    }

    /// J1 and J2 of the `abandon` lines of `target` on the edge from block id `origin`, at `point`; null when they are all right.
    /// The message is left in `note`.
    fn abandonFailure(self: *Checker, point: *const Point, target: u32, origin: u32) Allocator.Error!?Check {
        const values = abandonedOn(self.f.blocks[target], origin) orelse return null;
        if (!self.region[target]) {
            self.note = try std.fmt.allocPrint(self.a, "b{d} abandons owners on the edge from b{d} but some path from it does not end in a trap (abandon-region)", .{ self.f.blocks[target].id, origin });
            return .j2;
        }
        for (values) |v| {
            if (v >= self.n or self.states[v] != .owned or !point.l.isSet(v)) {
                self.note = try std.fmt.allocPrint(self.a, "%{d} is abandoned on the edge from b{d} into b{d} but is not an owned value live there (abandon-live)", .{ v, origin, self.f.blocks[target].id });
                return .j2;
            }
            if (point.isGroup(v)) {
                self.note = try std.fmt.allocPrint(self.a, "the group %{d} is abandoned on the edge from b{d} into b{d}; its tasks keep reading the lent cells (abandon-group)", .{ v, origin, self.f.blocks[target].id });
                return .j2;
            }
        }
        return null;
    }

    fn sameBits(x: Bits, y: Bits) bool {
        return x.eql(y);
    }

    /// Run the instructions and the terminator of block position `bi`; a failure ends the block.
    fn runBlock(self: *Checker, bi: u32, point: *Point) Allocator.Error!?Failure {
        const block = self.f.blocks[bi];
        for (block.insts, 0..) |*inst, k| {
            if (try self.instruction(point, inst, block.id, @intCast(k))) |failure| return failure;
        }
        return self.terminator(point, block);
    }

    // ---- usability ---------------------------------------------------------------------------------------

    /// Whether the allocation a root names is still there: an owner (or the container of a slot) while it is live, the
    /// caller's for the whole call.
    fn rootAlive(point: *const Point, root: Root) bool {
        return switch (root) {
            .caller => true,
            .value => |r| point.l.isSet(r),
            .slot => |slot| point.l.isSet(slot.owner),
        };
    }

    /// Every loan of `name` is on an allocation that is still there.
    fn loansAlive(point: *const Point, name: u32) bool {
        for (point.r.items) |held| if (held.name == name and !rootAlive(point, held.root)) return false;
        return true;
    }

    /// `name` takes on the loans `p` has at `point`: an owner is lent as it is (one slot of it, when `slot` names the
    /// slot the instruction reads in place), a borrow lends the roots recorded for it. A take that is defined later in
    /// the block (`forward`) lends nothing before it is defined.
    fn lendFrom(self: *Checker, point: *Point, name: u32, inst: *const form.Inst, p: u32) Allocator.Error!void {
        switch (self.states[p]) {
            .owned => {
                const in_place = inst.class == .project and inst.reads.len != 0 and inst.reads[0] == p;
                if (in_place) if (inst.extras.slot) |key| {
                    return point.hold(self.a, name, .{ .slot = .{ .owner = p, .key = key } }, false);
                };
                const forward = self.laterSibling(inst, p) and !point.l.isSet(p);
                try point.hold(self.a, name, .{ .value = p }, forward);
            },
            .borrowed => {
                const known = point.r.items.len;
                for (point.r.items[0..known]) |held| {
                    if (held.name == p) try point.hold(self.a, name, held.root, held.forward);
                }
            },
            else => {},
        }
    }

    /// `name` (a borrowed value, or an owned value a call returned) lives in what `parents` name.
    fn lend(self: *Checker, point: *Point, name: u32, inst: *const form.Inst) Allocator.Error!void {
        point.release(name);
        try self.holdParents(point, name, inst);
    }

    /// `name` holds the loans on what the parents of `inst`'s result name (an owned parent is its own root, a borrowed one has
    /// the roots recorded for it).
    fn holdParents(self: *Checker, point: *Point, name: u32, inst: *const form.Inst) Allocator.Error!void {
        for (inst.result.parents) |parent| switch (parent) {
            .caller => |i| try point.hold(self.a, name, .{ .caller = i }, false),
            .value => |p| if (p != name) try self.lendFrom(point, name, inst, p),
        };
    }

    /// The loans an owned result inherits: those of the owned values the instruction consumed, unless the instruction is a take
    /// marked `noloans` (design §9, entry 51). They are read before the consumed holders are forgotten.
    fn inheritedLoans(self: *Checker, point: *const Point, inst: *const form.Inst) Allocator.Error![]const Held {
        var out: std.ArrayList(Held) = .empty;
        if (inst.class == .take and inst.extras.loans.noloans) return out.items;
        for (inst.consumes) |c| {
            if (self.states[c] != .owned) continue;
            for (point.r.items) |held| if (held.name == c) try out.append(self.a, held);
        }
        return out.items;
    }

    /// Whether the instruction hands the loans of what it consumes on to an owned result.
    fn carries(inst: *const form.Inst) bool {
        return inst.result.state == .owned and !(inst.class == .take and inst.extras.loans.noloans);
    }

    /// Whether value `v` may be used at `point` (design §2).
    fn usable(self: *Checker, point: *const Point, v: u32) bool {
        return switch (self.states[v]) {
            .scalar, .immortal, .stack, .emptied => true,
            // An owned value that holds a loan is usable only while what it borrows is there.
            .owned => point.l.isSet(v) and loansAlive(point, v),
            .borrowed => point.d.isSet(v) and loansAlive(point, v),
            .none => false,
        };
    }

    /// Whether `v` is an `undef` of a managed type: the null owner (immortal), which a join, a store or a drop may take
    /// but no operation may read, since it points at nothing (FX12: a `match mut` binding lowered to one crashed a
    /// runtime helper that read it).
    fn nullOwner(self: *Checker, v: u32) bool {
        const def = self.defs[v] orelse return false;
        return def.op == .undef and self.states[v] == .immortal;
    }

    // ---- one instruction ---------------------------------------------------------------------------------

    fn instruction(self: *Checker, point: *Point, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        if (try self.shape(inst, b, k)) |failure| return failure;
        if (inst.class == .parameter) return null;
        for (inst.reads) |r| {
            if (!self.usable(point, r)) {
                const check: Check = if (self.states[r] == .borrowed) .j4 else .j3;
                return self.fail(check, b, k, "operand %{d} ({s}) is not usable here", .{ r, self.states[r].token() });
            }
            if (self.nullOwner(r)) return self.fail(.j3, b, k, "operand %{d} is an undef of a managed type (the null owner), which holds nothing to read", .{r});
        }
        for (inst.result.parents) |parent| switch (parent) {
            .caller => {},
            .value => |p| if (!self.laterSibling(inst, p) and !self.usable(point, p)) return self.fail(.j4, b, k, "the result borrows from %{d}, which is not usable here", .{p}),
        };
        for (inst.consumes) |c| {
            if (self.states[c] == .borrowed) return self.fail(.j5, b, k, "borrowed value %{d} is consumed", .{c});
        }
        for (inst.consumes) |c| switch (self.states[c]) {
            .owned => if (!point.l.isSet(c)) return self.fail(.j2, b, k, "consumed value %{d} is not live", .{c}),
            .emptied => return self.fail(.j8, b, k, "%{d} is an emptied aggregate and is never consumed", .{c}),
            // A unit value or an `undef` of the unit type: consuming it changes nothing.
            else => {},
        };
        const joins = inst.class == .call and inst.result.state == .none;
        for (inst.consumes) |c| {
            if (joins or self.states[c] != .owned) continue;
            if (point.isGroup(c)) return self.fail(.j2, b, k, "group %{d} is consumed by {s}, which does not end it (group-join)", .{ c, @tagName(inst.op) });
        }
        if (self.outlivesRoot(point, inst, b, k)) |failure| return failure;
        if (try self.stackRules(inst, b, k)) |failure| return failure;
        if (try self.disjoint(point, inst, b, k)) |failure| return failure;
        if (self.constructRead(point, inst, b, k)) |failure| return failure;
        if (try self.slots(point, inst, b, k)) |failure| return failure;
        if (inst.value) |value| {
            if (inst.result.state == .owned and point.l.isSet(value)) return self.fail(.j2, b, k, "%{d} is defined while it is still live", .{value});
            if (point.guardedOn(value)) return self.fail(.j8, b, k, "%{d} is defined while a take is guarded by a test on it (guard-redefined)", .{value});
        }
        try self.apply(point, inst);
        return null;
    }

    /// Whether `parent` is another projection of the result `inst` projects from: the final owner a call wrote back,
    /// taken right after the borrowed leaf is read. It is not defined yet; every later use of the leaf needs it alive.
    fn laterSibling(self: *Checker, inst: *const form.Inst, parent: u32) bool {
        if (inst.class != .project or inst.reads.len == 0) return false;
        const def = self.defs[parent] orelse return false;
        return def.class == .project and def.reads.len != 0 and def.reads[0] == inst.reads[0];
    }

    /// J1: the class, the result state and the parents agree with the operation's row (design §3).
    fn shape(self: *Checker, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        if (inst.class != ops.classOf(inst.op)) return self.fail(.j1, b, k, "{s} is stated {s}, the table says {s}", .{ @tagName(inst.op), inst.class.token(), ops.classOf(inst.op).token() });
        if (inst.extras.loans.lent) |group| if (self.lendFault(inst, group)) |why| return self.fail(.j1, b, k, "a lend {s}", .{why});
        if (viewsFault(inst)) |why| return self.fail(.j1, b, k, "views: {s}", .{why});
        if (inst.class == .call) if (try self.callFault(inst)) |why| return self.fail(.j1, b, k, "{s}", .{why});
        if (inst.class != .call and inst.extras.call.callee != null) return self.fail(.j1, b, k, "call-entry: only a call names a callee", .{});
        const result = inst.result;
        const state = result.state;
        if (inst.value == null and state != .none) return self.fail(.j1, b, k, "a line with no value has state {s}", .{state.token()});
        if (inst.value != null and state == .none and inst.class != .constant and inst.class != .call)
            return self.fail(.j1, b, k, "%{d} has state none", .{inst.value.?});
        // An owned update may list the borrowed values it stores (RB2: a collection of borrows lends its elements), as the
        // proven checker's `parentsOk` admits for any owned result; `parentsFault` keeps them among the operands it reads.
        const lends = inst.class == .construct or inst.class == .call or (inst.class == .update and state == .owned);
        if (result.parents.len != 0 and state != .borrowed and !lends)
            return self.fail(.j1, b, k, "a {s} value has parents", .{state.token()});
        if (self.parentsFault(inst)) |why| return self.fail(.j1, b, k, "parents: {s}", .{why});
        const first: ?u32 = if (inst.reads.len != 0) inst.reads[0] else null;
        const empty = inst.consumes.len == 0;
        const ok: bool = switch (inst.class) {
            .join, .forward, .jump, .branch, .@"return", .trap => false,
            // A parameter listed inside a block (a synthesized entry builds them there) is the one the signature names.
            .parameter => inst.value != null and self.isParam(inst.value.?) and empty and inst.reads.len == 0,
            // Only an `undef` (of the unit type) is a constant without a value; any other constant is a scalar or a static block.
            .constant => (state == .scalar or state == .immortal or (state == .none and inst.op == .undef)) and empty and inst.reads.len == 0,
            .pure, .inspect => state == .scalar and empty,
            .output, .trace => state == .none and empty,
            .fresh => (state == .owned or state == .stack) and empty,
            .copy => (state == .owned or state == .scalar) and empty,
            .character => (state == .owned or state == .immortal) and empty,
            .project => empty and self.projectionOk(inst, first),
            .view, .borrow => empty and (state == .scalar or (state == .borrowed and first != null and result.parents.len == 1 and std.meta.eql(result.parents[0], form.Parent{ .value = first.? }))),
            // A text frame frames the span it is given second, and lives as long as that span does.
            .text_frame => empty and (state == .scalar or (state == .borrowed and inst.reads.len == 2 and result.parents.len == 1 and std.meta.eql(result.parents[0], form.Parent{ .value = inst.reads[1] }))),
            .update => self.updateOk(inst),
            .construct => state == .owned or state == .emptied or state == .scalar or (state == .borrowed and self.consumesNothingOwned(inst)),
            .take => inst.consumes.len == 1 and (state == .owned or state == .scalar or state == .emptied),
            .drop => inst.consumes.len == 1 and inst.reads.len == 0 and inst.value == null,
            .call => self.callOk(inst),
        };
        if (!ok) return self.fail(.j1, b, k, "{s} ({s}) cannot have this shape: state {s}, {d} reads, {d} consumes", .{ @tagName(inst.op), inst.class.token(), state.token(), inst.reads.len, inst.consumes.len });
        if (state == .emptied and inst.extras.slots == null) return self.fail(.j1, b, k, "an emptied value must list its slots", .{});
        return null;
    }

    /// J1 for a lend (design §10.4): a `box_make` that reads its lender and its group and nothing else, consumes nothing and
    /// yields an owned box without parents; the group is another value and is owned. What is wrong with it, or null.
    fn lendFault(self: *Checker, inst: *const form.Inst, group: u32) ?[]const u8 {
        if (inst.op != .box_make) return "is stated on an instruction that is not a box_make";
        if (inst.reads.len != 2 or inst.reads[1] != group) return "reads exactly two values, the lender and its group";
        if (inst.consumes.len != 0) return "consumes nothing";
        if (inst.reads[0] == group) return "names its lender as its group";
        if (self.states[group] != .owned) return "lends to a value that is not an owned group";
        if (inst.result.state != .owned or inst.result.parents.len != 0) return "yields an owned box without parents";
        return null;
    }

    /// J1 `views` (format v2): only a constructor lists views, and each is an operand it reads. What is wrong, or null.
    fn viewsFault(inst: *const form.Inst) ?[]const u8 {
        const views = inst.extras.loans.views;
        if (views.len == 0) return null;
        if (inst.class != .construct) return "only a constructor lists views";
        for (views) |v| if (!listed(inst.reads, v)) return "a view that is not an operand the constructor reads";
        return null;
    }

    /// A projection is a scalar, a borrow of its container (or of what a call's result borrows), or a take.
    fn projectionOk(self: *Checker, inst: *const form.Inst, first: ?u32) bool {
        const result = inst.result;
        switch (result.state) {
            .scalar => return true,
            .owned, .emptied => return inst.extras.slot != null and first != null,
            .borrowed => {
                const head = first orelse return false;
                if (self.readsInPlace(inst, head)) return true;
                // Through a call's result: the parents are what the callee's `from` contract names.
                var at = head;
                var steps: usize = 0;
                while (steps <= self.n) : (steps += 1) {
                    const def = self.defs[at] orelse return false;
                    if (def.class == .call) {
                        const from = def.extras.call.from orelse return false;
                        for (result.parents) |parent| switch (parent) {
                            .caller => return false,
                            // The final owner a mutable parameter wrote back is another projection of the same call.
                            .value => |p| if (std.mem.indexOfScalar(u32, from, p) == null and !self.sameCall(p, def)) return false,
                        };
                        return result.parents.len != 0;
                    }
                    if (def.class != .project or def.reads.len == 0) return false;
                    at = def.reads[0];
                }
                return false;
            },
            else => return false,
        }
    }

    /// Whether every parent of the borrowed projection `inst` is the container `head` it reads or a take of the same
    /// container that follows (a forward take), and there is at least one.
    fn readsInPlace(self: *Checker, inst: *const form.Inst, head: u32) bool {
        if (inst.result.parents.len == 0) return false;
        for (inst.result.parents) |parent| switch (parent) {
            .caller => return false,
            .value => |p| if (p != head and !self.laterSibling(inst, p)) return false,
        };
        return true;
    }

    fn isParam(self: *Checker, value: u32) bool {
        for (self.f.params) |param| if (param.value == value) return true;
        return false;
    }

    /// A borrowed aggregate gives away nothing but scalars and static blocks.
    fn consumesNothingOwned(self: *Checker, inst: *const form.Inst) bool {
        for (inst.consumes) |c| switch (self.states[c]) {
            .scalar, .immortal => {},
            else => return false,
        };
        return true;
    }

    /// Whether value `v` is a projection, at any depth, of the result of `call`.
    fn sameCall(self: *Checker, v: u32, call: *const form.Inst) bool {
        var at = v;
        var steps: usize = 0;
        while (steps <= self.n) : (steps += 1) {
            const def = self.defs[at] orelse return false;
            if (def == call) return true;
            if (def.class != .project or def.reads.len == 0) return false;
            at = def.reads[0];
        }
        return false;
    }

    fn updateOk(self: *Checker, inst: *const form.Inst) bool {
        if (inst.consumes.len == 0) return false;
        const state = inst.result.state;
        return switch (self.states[inst.consumes[0]]) {
            .stack => state == .stack,
            .scalar => state == .scalar,
            else => state == .owned or state == .emptied or state == .scalar,
        };
    }

    /// J1 of the callee table (design §9, entry 57): the ids run 0, 1, 2, …; an indirect entry has no name and another has one; a
    /// `from` position is a parameter of the entry. The words themselves are the reader's.
    fn calleeTable(self: *Checker) Allocator.Error!?Failure {
        for (self.f.callees, 0..) |callee, i| {
            if (callee.id != i) return self.fail(.j1, null, null, "callee-table: the entry {d} is numbered {d}", .{ i, callee.id });
            if ((callee.kind == .indirect) != (callee.name.len == 0))
                return self.fail(.j1, null, null, "callee-table: entry {d} has a name exactly when it is not indirect", .{i});
            for (callee.from) |position| {
                if (position >= callee.params.len) return self.fail(.j1, null, null, "callee-table: entry {d} borrows from parameter {d} of {d}", .{ i, position, callee.params.len });
            }
        }
        return null;
    }

    /// J1 `parentsOk`, as the proven checker states it (`proofs/ownership/Checker.lean`): the parents of an instruction's value.
    /// A borrowed value borrows only from what `parentOperand` allows, and from nothing in its caller; an owned value lists
    /// only operands it reads (an owner it consumes is inherited with its loans, never a parent); any other value has none.
    /// Every class is judged the same, so a constructor or a call is no exception. Null when the parents are right.
    fn parentsFault(self: *Checker, inst: *const form.Inst) ?[]const u8 {
        if (inst.value == null) return null;
        switch (inst.result.state) {
            .borrowed => for (inst.result.parents) |parent| switch (parent) {
                .value => |n| if (!self.parentOperand(inst, n)) return "a borrowed value names a parent that is not an operand it reads, a loan of one, a later take of its container or a `from` value of its call",
                .caller => return "only a parameter borrows from its caller",
            },
            .owned => for (inst.result.parents) |parent| switch (parent) {
                .value => |n| if (!listed(inst.reads, n)) return "an owned value names a parent it does not read; an owner it consumes is inherited, not lent",
                .caller => return "only a parameter borrows from its caller",
            },
            else => if (inst.result.parents.len != 0) return "a value that is neither borrowed nor owned has parents",
        }
        return null;
    }

    /// Whether `n` may be a parent of the value `inst` defines (`parentOperand` of the proven checker): an operand it reads, a
    /// parent of a borrowed or owned operand it reads, a later owned take of the container it reads (`forwardTake`), or, for a
    /// projection, a `from` value of the call its container is a projection of.
    fn parentOperand(self: *Checker, inst: *const form.Inst, n: u32) bool {
        if (listed(inst.reads, n)) return true;
        for (inst.reads) |a| {
            if ((self.states[a] == .borrowed or self.states[a] == .owned) and parentsInclude(self.parents[a], n)) return true;
        }
        if (self.forwardTake(inst, n)) return true;
        return inst.class == .project and inst.reads.len != 0 and self.callFromOperand(inst.reads[0], n);
    }

    /// Whether the projection `inst` is a view written ahead of the owned take `n` of the container it reads (or of a view of
    /// it), `forwardTakeWith` of the proven checker: `n` is a slot take, it is owned, and it takes from that container.
    fn forwardTake(self: *Checker, inst: *const form.Inst, n: u32) bool {
        if (inst.class != .project) return false;
        const taken = self.defs[n] orelse return false;
        if (taken.class != .project or taken.extras.slot == null or self.states[n] != .owned or taken.reads.len == 0) return false;
        const container = taken.reads[0];
        if (inst.reads.len != 0 and inst.reads[0] == container) return true;
        for (inst.reads) |a| if (parentsInclude(self.parents[a], container)) return true;
        return false;
    }

    /// Whether `n` is one of the `from` values of the call that `start` is, or is projected from through projections
    /// (`callFromOperand` of the proven checker).
    fn callFromOperand(self: *Checker, start: u32, n: u32) bool {
        var at = start;
        var fuel = self.n + 1;
        while (fuel != 0) : (fuel -= 1) {
            const def = self.defs[at] orelse return false;
            if (def.class == .call) return if (def.extras.call.from) |from| listed(from, n) else false;
            if (def.class != .project or def.reads.len == 0) return false;
            at = def.reads[0];
        }
        return false;
    }

    /// J1 of a call against its callee table entry (design §9, entry 57): `call-entry`, `call-arity`, and for a program or indirect
    /// callee `call-scalar`, `call-result`, `call-from`. What is wrong, or null.
    fn callFault(self: *Checker, inst: *const form.Inst) Allocator.Error!?[]const u8 {
        const id = inst.extras.call.callee orelse return "call-entry: the call names no callee";
        if (id >= self.f.callees.len) return "call-entry: the callee is not in the table";
        const callee = self.f.callees[id];
        const indirect = inst.op == .call_indirect;
        if (indirect != (callee.kind == .indirect)) return "call-entry: an indirect entry belongs to an indirect call, and only to one";
        var taken: usize = 0;
        for (callee.params) |mode| taken += @intFromBool(mode.consumed());
        const skipped: usize = @intFromBool(indirect);
        if (inst.reads.len < skipped or inst.consumes.len != taken or inst.reads.len - skipped != callee.params.len - taken)
            return "call-arity: the operands are not the callee's parameters, taken and read";
        if (callee.kind != .program and callee.kind != .indirect) return null;
        const args = try self.a.alloc(u32, callee.params.len);
        var next_taken: usize = 0;
        var next_read: usize = skipped;
        for (callee.params, args) |mode, *arg| {
            if (mode.consumed()) {
                arg.* = inst.consumes[next_taken];
                next_taken += 1;
            } else {
                arg.* = inst.reads[next_read];
                next_read += 1;
            }
            if (mode.scalar()) switch (self.states[arg.*]) {
                .scalar, .immortal, .none => {},
                else => return "call-scalar: an unmanaged parameter receives a value that is not a scalar",
            };
        }
        const state = inst.result.state;
        const wanted: form.ResultKind = switch (state) {
            .owned, .emptied => .owned,
            .borrowed => .borrowed,
            else => .scalar,
        };
        if (state != .stack and callee.result != wanted) return "call-result: the state of the call's value is not what the callee returns";
        if (state == .borrowed) for (callee.from) |position| {
            if (callee.params[position].consumed()) return "call-from: the borrow contract names a parameter the callee takes";
            const arg = args[position];
            switch (self.states[arg]) {
                .scalar, .immortal, .none => continue,
                else => {},
            }
            if (!parentsInclude(inst.result.parents, arg)) return "call-from: the result does not borrow from an argument the callee's borrow contract names";
        };
        return null;
    }

    /// Whether `value` is among `parents`.
    fn parentsInclude(parents: []const form.Parent, value: u32) bool {
        for (parents) |parent| switch (parent) {
            .value => |v| if (v == value) return true,
            .caller => {},
        };
        return false;
    }

    fn callOk(self: *Checker, inst: *const form.Inst) bool {
        _ = self;
        const state = inst.result.state;
        if (inst.value == null or state == .none) return state == .none;
        if (state == .borrowed) {
            const from = inst.extras.call.from orelse return false;
            for (inst.result.parents) |parent| switch (parent) {
                .caller => return false,
                .value => |p| if (std.mem.indexOfScalar(u32, from, p) == null) return false,
            };
            return true;
        }
        return state == .scalar or state == .owned or state == .emptied;
    }

    /// Whether `inst` builds an owned aggregate that lists `view` among its loans.
    fn carriesLoan(inst: *const form.Inst, view: u32) bool {
        if (inst.class != .construct) return false;
        // A record built only to have its managed fields taken straight out (state emptied) keeps no parents.
        if (inst.result.state == .emptied) return true;
        if (inst.result.state != .owned) return false;
        for (inst.result.parents) |parent| switch (parent) {
            .value => |p| if (p == view) return true,
            .caller => {},
        };
        return false;
    }

    /// J7: a stack list is consumed only by a filling push, and holds nothing that needs destroying.
    fn stackRules(self: *Checker, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        var any_stack = false;
        for (inst.consumes, 0..) |c, position| {
            if (self.states[c] != .stack) continue;
            any_stack = true;
            if (inst.class != .update or position != 0 or inst.result.state != .stack)
                return self.fail(.j7, b, k, "stack value %{d} is consumed by a {s} instruction, which would let it escape", .{ c, inst.class.token() });
        }
        if (inst.class == .update and inst.result.state == .stack and !any_stack)
            return self.fail(.j7, b, k, "a stack result must come from a stack container", .{});
        if (any_stack) {
            for (inst.consumes[1..]) |stored| switch (self.states[stored]) {
                .owned, .emptied, .stack => return self.fail(.j7, b, k, "%{d} would be stored in a stack list, which destroys nothing", .{stored}),
                else => {},
            };
        }
        return null;
    }

    /// J6: nothing the instruction consumes is also read, consumed twice, or the root of another operand.
    fn disjoint(self: *Checker, point: *const Point, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        for (inst.consumes, 0..) |c, i| {
            if (self.states[c] != .owned) continue;
            for (inst.consumes[0..i]) |earlier| {
                if (earlier == c) return self.fail(.j6, b, k, "%{d} fills two consumed positions", .{c});
            }
            for (inst.reads) |r| {
                if (r == c) return self.fail(.j6, b, k, "%{d} is both read and consumed", .{c});
            }
            for ([_][]const u32{ inst.reads, inst.consumes }) |operands| {
                for (operands) |o| {
                    if (o == c) continue;
                    // An aggregate built from an owner and a view of it carries the loan itself.
                    if (self.livesIn(point, o, c) and !carriesLoan(inst, o))
                        return self.fail(.j6, b, k, "%{d} is consumed while operand %{d} borrows from it", .{ c, o });
                }
            }
        }
        return null;
    }

    /// Whether value `v` lives in owner `c` (or in a slot of it) at `point`.
    fn livesIn(self: *Checker, point: *const Point, v: u32, c: u32) bool {
        _ = self;
        for (point.r.items) |held| {
            if (held.name != v) continue;
            switch (held.root) {
                .value => |r| if (r == c) return true,
                .slot => |slot| if (slot.owner == c) return true,
                .caller => {},
            }
        }
        return false;
    }

    /// J8: the take protocol (design §3, slots).
    fn slots(self: *Checker, point: *Point, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        // An emptied aggregate is used only to take its parts and to read its scalars.
        for ([_][]const u32{ inst.reads, inst.consumes }) |operands| {
            for (operands) |o| {
                if (self.states[o] == .emptied and inst.class != .project)
                    return self.fail(.j8, b, k, "%{d} is an emptied aggregate and cannot be used as a whole", .{o});
            }
        }
        const closing = isClosing(inst);
        for (inst.consumes, 0..) |c, position| {
            if (self.states[c] != .owned or !point.pending(c)) continue;
            if (!(closing and position == 0))
                return self.fail(.j8, b, k, "%{d} is consumed by {s} while a take from it is open", .{ c, @tagName(inst.op) });
        }
        if (inst.class == .project and (inst.result.state == .owned or inst.result.state == .emptied)) return self.take(point, inst, b, k);
        if (inst.class == .project) {
            // A borrowed read of a slot an owned read took reads a pointer that is not the container's any more.
            if (inst.extras.slot) |key| if (inst.reads.len != 0 and self.states[inst.reads[0]] == .owned) {
                if (point.find(inst.reads[0], key, false) != null) return self.fail(.j8, b, k, "slot {s} of %{d} is read while an owned read has taken it", .{ key, inst.reads[0] });
            };
            return null;
        }
        if (closing) return self.store(point, inst, b, k);
        return null;
    }

    fn isClosing(inst: *const form.Inst) bool {
        return switch (inst.op) {
            .record_set, .array_set, .list_set, .list_set_field, .dict_set_value, .list_pop, .dict_remove => inst.class == .update,
            else => false,
        };
    }

    /// An owned read takes a slot: of an owned container (an open take), or of an emptied aggregate (an owed slot).
    fn take(self: *Checker, point: *Point, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        const key = inst.extras.slot orelse return self.fail(.j1, b, k, "an owned read names no slot", .{});
        if (inst.reads.len == 0) return self.fail(.j1, b, k, "an owned read names no container", .{});
        const container = inst.reads[0];
        switch (self.states[container]) {
            .emptied => {
                const owed = point.find(container, key, true) orelse return self.fail(.j8, b, k, "slot {s} of emptied %{d} is not owed (taken twice, or not one of its slots)", .{ key, container });
                _ = point.p.swapRemove(owed);
            },
            .owned => {
                if (point.find(container, key, false) != null) return self.fail(.j8, b, k, "slot {s} of %{d} is taken while an earlier take of it is open", .{ key, container });
                // A pop that left its element past the end is taken by the read at the new length.
                if (point.find(container, "tail", false)) |tail| if (self.atLength(key, container)) {
                    if (!point.p.items[tail].definite()) return self.fail(.j8, b, k, "the pop of %{d} is open only under a decision", .{container});
                    _ = point.p.swapRemove(tail);
                    return null;
                };
                try point.p.append(self.a, .{ .container = container, .key = key, .owed = false });
                if (try self.endLoans(point, container, key, b, k)) |failure| return failure;
            },
            else => return self.fail(.j8, b, k, "a take from %{d}, which is {s} and not an owned container", .{ container, self.states[container].token() }),
        }
        return null;
    }

    /// Whether `key` names the element at the length of `container`: the read `markPops` adds after a pop.
    fn atLength(self: *Checker, key: []const u8, container: u32) bool {
        if (key.len < 3 or key[0] != 'e' or key[1] != '%') return false;
        const index = std.fmt.parseInt(u32, key[2..], 10) catch return false;
        if (index >= self.n) return false;
        const def = self.defs[index] orelse return false;
        return def.op == .list_len and def.reads.len == 1 and def.reads[0] == container;
    }

    /// A store closes the take of its slot (or releases the old content when none is open), a pop closes the take of
    /// the element it removes, and a removal accounts for the parts it did not destroy.
    fn store(self: *Checker, point: *Point, inst: *const form.Inst, b: u32, k: u32) Allocator.Error!?Failure {
        const container = inst.consumes[0];
        if (self.states[container] != .owned) return null;
        const result = inst.value;
        switch (inst.op) {
            .dict_remove => {
                const key = inst.extras.slot orelse return null;
                const taken = inst.extras.taken orelse form.Parts{};
                const released = inst.extras.released orelse form.Parts{};
                inline for (.{ .{ "key", 'k' }, .{ "value", 'v' } }) |part| {
                    if (@field(released, part[0])) {
                        const part_key = try std.fmt.allocPrint(self.a, "{c}{s}", .{ part[1], key[1..] });
                        if (point.find(container, part_key, false) != null) return self.fail(.j8, b, k, "the removal releases the {s} of the entry, which an owned read has taken", .{part[0]});
                    }
                    if (@field(taken, part[0])) {
                        const part_key = try std.fmt.allocPrint(self.a, "{c}{s}", .{ part[1], key[1..] });
                        const at = point.find(container, part_key, false) orelse return self.fail(.j8, b, k, "the {s} of the removed entry is not released and no take of it is open", .{part[0]});
                        if (!point.p.items[at].definite()) return self.fail(.j8, b, k, "the take of the {s} of the removed entry is open only under a decision", .{part[0]});
                        _ = point.p.swapRemove(at);
                    }
                }
            },
            .list_pop => {
                const key = inst.extras.slot orelse return null;
                if (std.mem.eql(u8, key, "tail")) {
                    if (result) |r| point.rename(container, r);
                    if (result) |r| try point.p.append(self.a, .{ .container = r, .key = "tail", .owed = false });
                    return null;
                }
                const at = point.find(container, key, false) orelse return self.fail(.j8, b, k, "the pop removes slot {s} of %{d}, which no owned read has taken", .{ key, container });
                if (!point.p.items[at].definite()) return self.fail(.j8, b, k, "the take of slot {s} of %{d} is open only under a decision", .{ key, container });
                _ = point.p.swapRemove(at);
            },
            else => if (inst.extras.slot) |key| {
                const open = point.find(container, key, false);
                if (open) |at| if (!point.p.items[at].definite()) return self.fail(.j8, b, k, "the take of slot {s} of %{d} is open only under a decision the store cannot see", .{ key, container });
                const releases = if (inst.extras.released) |released| released.old else false;
                if (releases and open != null) return self.fail(.j8, b, k, "the store releases slot {s} of %{d}, which an owned read has taken", .{ key, container });
                if (!releases and open == null) return self.fail(.j8, b, k, "the store releases nothing of slot {s} of %{d}, which no owned read has taken", .{ key, container });
                if (open) |at| _ = point.p.swapRemove(at);
            },
        }
        if (result) |r| point.rename(container, r);
        return null;
    }

    /// Consumed values leave `L`, the defined value enters it, and a redefined owner takes its borrowers out of `D`. A
    /// borrowed result, or an owned call result that holds a loan, enters with the roots of its parents; a constructor
    /// takes over the owners it consumed and the loans their holders held.
    fn apply(self: *Checker, point: *Point, inst: *const form.Inst) Allocator.Error!void {
        for (inst.consumes) |c| {
            if (self.states[c] == .owned) {
                point.l.unset(c);
                point.unmarkGroup(c);
            }
        }
        if (inst.value) |value| try self.introduce(point, inst, value);
        for (inst.consumes) |c| {
            if (self.states[c] == .owned) self.kill(point, c);
        }
    }

    /// The instruction defines `value`.
    fn introduce(self: *Checker, point: *Point, inst: *const form.Inst, value: u32) Allocator.Error!void {
        point.forget(value);
        switch (inst.result.state) {
            .owned => {
                point.l.set(value);
                point.unmarkGroup(value);
                // The consumed holders are forgotten with the redefinition: what the result inherits is read first.
                const inherited = try self.inheritedLoans(point, inst);
                self.redefine(point, value);
                point.release(value);
                for (inherited) |held| try point.hold(self.a, value, held.root, held.forward);
                try self.holdParents(point, value, inst);
                if (inst.class == .construct) {
                    // The aggregate takes the owners it consumed: the roots that named them name it, and it holds no loan on itself.
                    self.absorb(point, inst, value);
                    point.dropSelf(value);
                }
                if (inst.extras.loans.lent) |group| try self.lendTo(point, inst, value, group);
            },
            .stack => self.redefine(point, value),
            .borrowed => {
                point.d.set(value);
                try self.lend(point, value, inst);
            },
            .emptied => {
                if (inst.extras.slots) |keys| for (keys) |key| {
                    try point.p.append(self.a, .{ .container = value, .key = key, .owed = true });
                };
            },
            else => {},
        }
    }

    /// Owner `c` was consumed and not handed on: the borrows that live in it can never be used again, so they leave `D` and
    /// `R`. (An unusable name and a dead root change no verdict and only make every later state larger.) A loan written
    /// ahead of a take (`forward`) is on an owner that is not defined yet and stays.
    fn kill(self: *Checker, point: *Point, c: u32) void {
        var any = false;
        for (point.r.items) |held| {
            // A consumed holder (a task group that was joined) keeps no loans.
            if (held.name == c) any = true;
            if (held.forward or self.states[held.name] != .borrowed) continue;
            const lives_in = switch (held.root) {
                .value => |v| v == c,
                .slot => |slot| slot.owner == c,
                .caller => false,
            };
            if (lives_in) {
                point.d.unset(held.name);
                any = true;
            }
        }
        if (any) point.prune();
    }

    /// A lend (design §10.3): the roots of the lender join the loans of the group, which holds them until it is consumed, and
    /// of the box the lend yields, which the environment built around it inherits. An owned lender is its own root, a borrowed
    /// one has the roots recorded for it, and an immortal or scalar lender has none.
    fn lendTo(self: *Checker, point: *Point, inst: *const form.Inst, box: u32, group: u32) Allocator.Error!void {
        const lender = inst.reads[0];
        try point.markGroup(self.a, group);
        switch (self.states[lender]) {
            .owned => for ([_]u32{ group, box }) |holder| try point.hold(self.a, holder, .{ .value = lender }, false),
            .borrowed => {
                const known = point.r.items.len;
                for (point.r.items[0..known]) |held| {
                    if (held.name != lender) continue;
                    for ([_]u32{ group, box }) |holder| try point.hold(self.a, holder, held.root, held.forward);
                }
            },
            else => {},
        }
    }

    /// A constructor takes over the owners it consumed (the storage moves into the aggregate): the loans on them name the
    /// aggregate. The loans their holders held it inherited with `inheritedLoans`.
    fn absorb(self: *Checker, point: *Point, inst: *const form.Inst, aggregate: u32) void {
        for (inst.consumes) |c| {
            if (self.states[c] == .owned) point.renameRoots(c, aggregate, true);
        }
    }

    /// Defining an owned or stack value takes the names that live in it out of `D`. A loan that was written ahead of the
    /// definition (a view of a slot that this take now takes) only comes alive.
    fn redefine(self: *Checker, point: *Point, owner: u32) void {
        for (point.r.items) |*held| {
            const lives_in = switch (held.root) {
                .value => |v| v == owner,
                .slot => |slot| slot.owner == owner,
                .caller => false,
            };
            if (!lives_in) continue;
            if (held.forward) {
                held.forward = false;
            } else if (self.states[held.name] == .borrowed) point.d.unset(held.name);
        }
        point.prune();
    }

    /// Taking slot `key` of `container` ends the loans on it: a borrowed view of the slot leaves `D`, and an owned value
    /// that holds such a loan outlives its root (J4).
    fn endLoans(self: *Checker, point: *Point, container: u32, key: []const u8, b: u32, k: u32) Allocator.Error!?Failure {
        for (point.r.items) |held| {
            if (!endsWithTake(held.root, container, key)) continue;
            if (self.states[held.name] == .owned and point.l.isSet(held.name))
                return self.fail(.j4, b, k, "slot {s} of %{d} is taken while %{d} still holds a loan on it (loan-outlives-root)", .{ key, container, held.name });
            point.d.unset(held.name);
        }
        point.prune();
        return null;
    }

    /// J6 `construct-read` (lane VAL, after lane FX6): a constructor whose result is owned or `emptied`, and that is not a lend,
    /// reads a borrowed operand only when every root recorded for it is an owner the constructor consumes, or a slot of one
    /// (the aggregate takes the owner over and reads a view of it, design entries 19 and 28), or when the result is owned and
    /// lists the operand among its parents and among its `views` (an aggregate that holds a view as a loan, design §3,
    /// Construct; a view is a value the aggregate's destruction does not destroy, format v2). Otherwise the
    /// aggregate would destroy, or an owned take out of it would hand out, storage it never received: the plan of FX6 took a
    /// dictionary's key out of an `emptied` record as an owner and freed it twice. A forward root, a caller's root and no root
    /// at all satisfy neither condition. The operand that breaks the rule, or null. The proof's copy is `constructReadOk`.
    fn constructReadFault(self: *const Checker, point: *const Point, inst: *const form.Inst) ?ConstructRead {
        if (inst.class != .construct or inst.extras.loans.lent != null) return null;
        const state = inst.result.state;
        if (state != .owned and state != .emptied) return null;
        for (inst.reads) |r| {
            if (self.states[r] != .borrowed) continue;
            // Condition 2: an owned aggregate may hold a borrowed operand as a loan only when it is a view (`views`), which
            // its destruction does not destroy; a listed borrowed `str`, list or record would be destroyed with it.
            const loan = state == .owned and listsParent(inst.result.parents, r);
            if (loan and listed(inst.extras.loans.views, r)) continue;
            const why = self.rootFault(point, inst, r) orelse continue;
            return .{ .operand = r, .why = if (loan) "which it lists as a loan but which is not a view (a value its destruction leaves alone)" else why };
        }
        return null;
    }

    /// Condition 1 of the construct-read rule for borrowed operand `r`: where it lives that `inst` does not take over (the
    /// caller, a take defined later, an owner it does not consume, nowhere recorded), or null when every root is an owner
    /// `inst` consumes or a slot of one.
    fn rootFault(self: *const Checker, point: *const Point, inst: *const form.Inst, r: u32) ?[]const u8 {
        var rooted = false;
        for (point.r.items) |held| {
            if (held.name != r) continue;
            rooted = true;
            const owner = switch (held.root) {
                .value => |v| v,
                .slot => |slot| slot.owner,
                .caller => return "which lives in the caller",
            };
            if (held.forward) return "which lives in a take defined later";
            if (self.states[owner] != .owned or !listed(inst.consumes, owner)) return "which lives in an owner it does not consume";
        }
        return if (rooted) null else "which has no recorded root";
    }

    /// The construct-read rule at `inst` in the mode the options name: the failure that refuses it, or null after counting it
    /// (in the recheck alone, so once per instruction) or when nothing is wrong.
    fn constructRead(self: *Checker, point: *const Point, inst: *const form.Inst, b: u32, k: u32) ?Failure {
        const fault = self.constructReadFault(point, inst) orelse return null;
        switch (self.options.construct_read) {
            .refuse => {
                const state = inst.result.state.token();
                return self.fail(.j6, b, k, "construct-read: the {s} constructor reads borrowed %{d}, {s}", .{ state, fault.operand, fault.why });
            },
            .count => if (self.rechecking) {
                if (self.options.counted) |counted| counted.* += 1;
            },
        }
        return null;
    }

    /// An owner is consumed while an owned value that holds a loan on it is still live (J4, loan-outlives-root). A constructor
    /// with an owned result takes the storage and its loans over; one with an `emptied` result destroys what it consumes, so
    /// it is not exempt (design §9, entry 41).
    fn outlivesRoot(self: *Checker, point: *const Point, inst: *const form.Inst, b: u32, k: u32) ?Failure {
        if (inst.class == .construct and inst.result.state != .emptied) return null;
        for (inst.consumes) |c| {
            if (self.states[c] != .owned) continue;
            for (point.r.items) |held| {
                const on_it = switch (held.root) {
                    .value => |v| v == c,
                    .slot => |slot| slot.owner == c,
                    .caller => false,
                };
                if (!on_it or held.name == c or self.states[held.name] != .owned) continue;
                // A holder consumed by the instruction is exempt only if its loans end with it: the result is not an owner, or
                // the instruction is a take that hands none on. One handed on to an owned result keeps them (entry 50).
                const dies_with_it = listed(inst.consumes, held.name) and !carries(inst);
                if (point.l.isSet(held.name) and !dies_with_it)
                    return self.fail(.j4, b, k, "%{d} is consumed while %{d} still holds a loan on it (loan-outlives-root)", .{ c, held.name });
            }
        }
        return null;
    }

    // ---- terminators and edges ---------------------------------------------------------------------------

    fn terminator(self: *Checker, point: *Point, block: form.Block) Allocator.Error!?Failure {
        const where: u32 = @intCast(block.insts.len);
        switch (block.term) {
            .jump, .unreachable_path => return null,
            .branch => |branch| {
                if (!self.usable(point, branch.condition)) return self.fail(if (self.states[branch.condition] == .borrowed) .j4 else .j3, block.id, where, "the branch condition %{d} is not usable", .{branch.condition});
                return null;
            },
            .ret => |value| return self.returns(point, block.id, where, value),
        }
    }

    fn returns(self: *Checker, point: *Point, b: u32, where: u32, value: ?u32) Allocator.Error!?Failure {
        if (point.p.items.len != 0) {
            const entry = point.p.items[0];
            return self.fail(.j8, b, where, "the function returns with {s} slot {s} of %{d}", .{ if (entry.owed) "an untaken" else "an open take of", entry.key, entry.container });
        }
        const live = point.l.count();
        const v = value orelse {
            if (live != 0) return self.fail(.j2, b, where, "{d} owned values are still live at the return", .{live});
            return null;
        };
        const state = self.states[v];
        if (state == .owned and point.isGroup(v)) return self.fail(.j2, b, where, "the returned value %{d} is a group that nothing ended (group-join)", .{v});
        switch (self.f.returns.kind) {
            .owned => {
                if (state == .stack) return self.fail(.j7, b, where, "the returned value %{d} is a stack list", .{v});
                if (state == .borrowed) return self.fail(.j5, b, where, "the returned value %{d} is borrowed in a function that returns an owner", .{v});
                if (state != .owned and state != .immortal) return self.fail(.j1, b, where, "the returned value %{d} is {s}", .{ v, state.token() });
                if (state == .owned) {
                    if (!point.l.isSet(v)) return self.fail(.j2, b, where, "the returned value %{d} is not live", .{v});
                    if (live != 1) return self.fail(.j2, b, where, "{d} owned values besides the returned one are still live", .{live - 1});
                } else if (live != 0) return self.fail(.j2, b, where, "{d} owned values are still live at the return", .{live});
            },
            .borrowed => {
                if (state == .stack) return self.fail(.j7, b, where, "the returned value %{d} is a stack list", .{v});
                if (state == .owned) return self.fail(.j5, b, where, "an owner is returned from a function that returns a borrow", .{});
                if (state != .borrowed and state != .immortal and state != .scalar) return self.fail(.j1, b, where, "the returned value %{d} is {s}", .{ v, state.token() });
                if (state == .borrowed) {
                    if (!self.usable(point, v)) return self.fail(.j4, b, where, "the returned borrow %{d} is not usable", .{v});
                    for (point.r.items) |held| {
                        if (held.name != v) continue;
                        switch (held.root) {
                            .caller => |i| if (std.mem.indexOfScalar(u32, self.f.returns.from, i) == null) return self.fail(.j5, b, where, "the returned borrow lives in parameter {d}, which the result's from does not name", .{i}),
                            .value => |r| return self.fail(.j5, b, where, "the returned borrow lives in %{d}, which this function owns", .{r}),
                            .slot => |slot| return self.fail(.j5, b, where, "the returned borrow lives in slot {s} of %{d}, which this function owns", .{ slot.key, slot.owner }),
                        }
                    }
                }
                if (live != 0) return self.fail(.j2, b, where, "{d} owned values are still live at the return", .{live});
            },
            .scalar => {
                if (state != .scalar and state != .immortal) return self.fail(.j1, b, where, "the returned value %{d} is {s}", .{ v, state.token() });
                if (live != 0) return self.fail(.j2, b, where, "{d} owned values are still live at the return", .{live});
            },
        }
        return null;
    }

    /// The state flowing into block position `target` along the edge out of block position `from`, or null for an
    /// edge that fails; `edgeFailure` says which check.
    fn edgeState(self: *Checker, from: u32, point: *const Point, target: u32) Allocator.Error!?Point {
        if (try self.edgeFailure(from, point, target) != null) return null;
        const block = self.f.blocks[target];
        const origin = self.f.blocks[from].id;
        var next = try point.clone(self.a);
        if (abandonedOn(block, origin)) |values| abandon(&next, values);
        var redefined: std.ArrayList(u32) = .empty;
        var moves: std.ArrayList(Move) = .empty;
        var fresh: std.ArrayList(Held) = .empty;
        for (block.phis) |phi| {
            if (phi.result.state == .none) continue;
            const operand = edgeOperand(phi, origin).?;
            switch (phi.result.state) {
                .owned => {
                    if (self.states[operand] == .owned) {
                        next.l.unset(operand);
                        try moves.append(self.a, .{ .from = operand, .to = phi.value });
                    }
                    try redefined.append(self.a, phi.value);
                },
                .stack => try redefined.append(self.a, phi.value),
                .borrowed => try self.operandRoots(point, phi.value, operand, &fresh),
                else => {},
            }
        }
        for (block.phis) |phi| switch (phi.result.state) {
            .owned => next.l.set(phi.value),
            else => {},
        };
        // A phi that consumes a holder holds what it held, and one that consumes a group must still end it.
        for (moves.items) |move| {
            next.renameHolder(move.from, move.to);
            next.moveGroup(move.from, move.to);
        }
        // The names that live in a redefined owner leave `D` by the roots they had before the edge.
        for (redefined.items) |owner| self.redefine(&next, owner);
        for (block.phis) |phi| if (phi.result.state == .borrowed) {
            next.d.unset(phi.value);
            next.prune();
        };
        for (fresh.items) |held| try next.hold(self.a, held.name, held.root, held.forward);
        for (moves.items) |move| next.renameRoots(move.from, move.to, false);
        for (block.phis) |phi| {
            if (phi.result.state == .borrowed) next.d.set(phi.value);
        }
        try self.assume(&next, from, target);
        for (block.phis) |phi| next.forget(phi.value);
        return next;
    }

    /// The roots `operand` has at `point`, as roots of the borrowed phi `name`.
    fn operandRoots(self: *Checker, point: *const Point, name: u32, operand: u32, out: *std.ArrayList(Held)) Allocator.Error!void {
        switch (self.states[operand]) {
            .owned => try out.append(self.a, .{ .name = name, .root = .{ .value = operand } }),
            .borrowed => for (point.r.items) |held| {
                if (held.name == operand) try out.append(self.a, .{ .name = name, .root = held.root, .forward = held.forward });
            },
            else => {},
        }
    }

    /// Whether crossing the edge decides a test the other way from a decision already known on the path: no execution
    /// takes the edge, and no state flows along it.
    fn infeasible(self: *Checker, point: *const Point, from: u32, target: u32) bool {
        const block = self.f.blocks[from];
        if (block.term != .branch) return false;
        const branch = block.term.branch;
        if (branch.then == branch.otherwise) return false;
        const when = self.f.blocks[target].id == branch.then;
        return point.holdsNot(.{ .cond = self.testOf(block, branch.condition), .when = when });
    }

    /// Crossing an edge out of a branch decides the test the branch looked at.
    fn assume(self: *Checker, next: *Point, from: u32, target: u32) Allocator.Error!void {
        const block = self.f.blocks[from];
        if (block.term != .branch) return;
        const branch = block.term.branch;
        if (branch.then == branch.otherwise) return;
        const when = self.f.blocks[target].id == branch.then;
        try next.decide(self.a, .{ .cond = self.testOf(block, branch.condition), .when = when });
    }

    /// The test a branch on `cond` decides: a comparison defined in `block` itself, so that its operands are the ones the
    /// branch sees, or else the condition value.
    fn testOf(self: *Checker, block: form.Block, cond: u32) Test {
        for (block.insts) |*inst| {
            if (inst.value != cond) continue;
            const compares = (inst.op == .cmp or inst.op == .fcmp) and inst.reads.len == 2;
            const predicate = inst.extras.imm orelse break;
            if (!compares) break;
            return .{ .compare = .{ .op = inst.op, .predicate = predicate, .lhs = self.compared(inst.reads[0]), .rhs = self.compared(inst.reads[1]) } };
        }
        return .{ .value = cond };
    }

    /// A constant compares by value; anything else by name.
    fn compared(self: *Checker, v: u32) Operand {
        const def = self.defs[v] orelse return .{ .value = v };
        if (def.op != .iconst) return .{ .value = v };
        const imm = def.extras.imm orelse return .{ .value = v };
        return .{ .constant = imm };
    }

    fn edgeOperand(phi: form.Phi, origin: u32) ?u32 {
        for (phi.edges) |edge| if (edge.block == origin) return edge.value;
        return null;
    }

    /// The failure, if any, of the phis of `target` on the edge out of `from`; the message is left in `note`.
    fn edgeFailure(self: *Checker, from: u32, edge_start: *const Point, target: u32) Allocator.Error!?Check {
        const block = self.f.blocks[target];
        const origin = self.f.blocks[from].id;
        if (try self.abandonFailure(edge_start, target, origin)) |check| return check;
        // What the phis find on the edge is what is left after the abandons.
        var left: Point = undefined;
        var point = edge_start;
        if (abandonedOn(block, origin)) |values| {
            left = try edge_start.clone(self.a);
            abandon(&left, values);
            point = &left;
        }
        // The branch's decision settles guarded takes before the phis consume anything.
        var decided = try point.clone(self.a);
        try self.assume(&decided, from, target);
        var consumed: std.ArrayList(u32) = .empty;
        for (block.phis) |phi| {
            const state = phi.result.state;
            if (state == .none) continue;
            if (decided.guardedOn(phi.value)) {
                self.note = try std.fmt.allocPrint(self.a, "phi %{d} is defined while a take is guarded by a test on it (guard-redefined)", .{phi.value});
                return .j8;
            }
            const operand = edgeOperand(phi, origin) orelse {
                self.note = try std.fmt.allocPrint(self.a, "phi %{d} has no operand for the edge from b{d}", .{ phi.value, origin });
                return .j1;
            };
            const have = self.states[operand];
            const fits = switch (state) {
                .scalar => have == .scalar,
                .immortal => have == .immortal,
                .owned => have == .owned or have == .immortal,
                .stack => have == .stack,
                .borrowed => have == .borrowed or have == .immortal or (have == .owned and parentNamed(phi, operand)),
                else => false,
            };
            if (!fits) {
                self.note = try std.fmt.allocPrint(self.a, "phi %{d} ({s}) takes %{d} ({s}) from b{d}", .{ phi.value, state.token(), operand, have.token(), origin });
                return .j1;
            }
            if (state != .borrowed and phi.result.parents.len != 0) {
                self.note = try std.fmt.allocPrint(self.a, "phi %{d} ({s}) has parents, and only a borrowed phi has any (phi-parents)", .{ phi.value, state.token() });
                return .j1;
            }
            if (state == .owned and have == .owned) {
                if (!point.l.isSet(operand)) {
                    self.note = try std.fmt.allocPrint(self.a, "phi %{d} consumes %{d}, which is not live on the edge from b{d}", .{ phi.value, operand, origin });
                    return .j2;
                }
                for (consumed.items) |earlier| {
                    if (earlier == operand) {
                        self.note = try std.fmt.allocPrint(self.a, "two phis consume %{d}", .{operand});
                        return .j2;
                    }
                }
                if (decided.pending(operand)) {
                    self.note = try std.fmt.allocPrint(self.a, "phi %{d} consumes %{d}, which has an open take", .{ phi.value, operand });
                    return .j8;
                }
                try consumed.append(self.a, operand);
            }
            if (state == .borrowed and !self.usable(point, operand)) {
                self.note = try std.fmt.allocPrint(self.a, "borrowed phi %{d} takes %{d}, which is not usable on the edge from b{d}", .{ phi.value, operand, origin });
                return .j4;
            }
        }
        for (block.phis) |phi| {
            if (phi.result.state == .owned and point.l.isSet(phi.value) and !listed(consumed.items, phi.value)) {
                self.note = try std.fmt.allocPrint(self.a, "phi %{d} defines a value that is already live", .{phi.value});
                return .j2;
            }
        }
        return null;
    }

    fn parentNamed(phi: form.Phi, operand: u32) bool {
        return parentHeld(phi.result.parents, .{ .value = operand });
    }

    fn parentHeld(parents: []const form.Parent, wanted: form.Parent) bool {
        for (parents) |parent| if (std.meta.eql(parent, wanted)) return true;
        return false;
    }

    fn listed(values: []const u32, value: u32) bool {
        return std.mem.indexOfScalar(u32, values, value) != null;
    }

    /// Whether `parents` names value `v`.
    fn listsParent(parents: []const form.Parent, v: u32) bool {
        for (parents) |parent| switch (parent) {
            .value => |p| if (p == v) return true,
            .caller => {},
        };
        return false;
    }
};

/// A borrowed operand a constructor reads against the construct-read rule, and where it lives.
const ConstructRead = struct { operand: u32, why: []const u8 };

test "a guarded take names a container that is live where the take is joined" {
    const a = std.testing.allocator;
    var known: Point = .{ .l = try Bits.initEmpty(a, 4), .d = try Bits.initEmpty(a, 4), .p = .empty, .path = .empty, .r = .empty };
    defer known.l.deinit(a);
    defer known.d.deinit(a);
    defer known.p.deinit(a);
    var edge = try known.clone(a);
    defer edge.l.deinit(a);
    defer edge.d.deinit(a);
    defer edge.p.deinit(a);
    defer edge.path.deinit(a);
    const guard: Guard = .{ .cond = .{ .value = 3 }, .when = true };
    try known.p.append(a, .{ .container = 1, .key = "f0", .owed = false, .guard = guard });
    try edge.path.append(a, .{ .cond = guard.cond, .when = false });
    try std.testing.expect(!compatible(&known, &edge));
    known.l.set(1);
    edge.l.set(1);
    try std.testing.expect(compatible(&known, &edge));
}

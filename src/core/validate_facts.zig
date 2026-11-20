//! The fact validator (docs/design/fact-certificates.md §6): F1–F7 over a module's certificate.
//!
//! It reads only the form of `fact_function.zig` and the operation names of `ir.zig`, so a bug of `facts.zig` cannot be
//! shared with it. A fact certificate states an interval for each value; the validator does not replay the fixed-point
//! iteration that produced them, it checks that they are an **inductive invariant**: every stated interval contains what
//! the transfer rule of its instruction derives from the other stated intervals as seen at the instruction's block (the
//! stated interval narrowed by the branch edges that dominate the block), a phi's contains the hull of its live operands,
//! and a `proven` check is implied by the intervals at its site.
const std = @import("std");
const ir = @import("ir.zig");
const form = @import("fact_function.zig");

const Allocator = std.mem.Allocator;
const Interval = form.Interval;
const Type = form.Type;
const M = form.max_list_length;
const none = std.math.maxInt(u32);

/// A debug compiler checks the certificate of every optimized function it builds, as it checks ownership.
pub const enabled = @import("builtin").mode == .debug;

/// The checks of design §6.
pub const Check = enum {
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,

    /// `F1` … `F7`.
    pub fn label(self: Check) []const u8 {
        return switch (self) {
            .f1 => "F1",
            .f2 => "F2",
            .f3 => "F3",
            .f4 => "F4",
            .f5 => "F5",
            .f6 => "F6",
            .f7 => "F7",
        };
    }

    /// The name of the check, for the report.
    pub fn rule(self: Check) []const u8 {
        return switch (self) {
            .f1 => "shape",
            .f2 => "transfer",
            .f3 => "phi",
            .f4 => "loop",
            .f5 => "reachability",
            .f6 => "inter-procedural",
            .f7 => "proven",
        };
    }
};

/// Why a `proven` check is reported unchecked rather than validated (design §6 F7, §8 A6). None is a rejection.
pub const Unchecked = enum {
    /// A list access justified by a length bound (`bound`).
    list_bound,
    /// A list access justified by a fill loop's length.
    list_fill,
    /// A list access justified by a dominating edge or an earlier access (`index_keys`).
    list_keys,
    /// A float conversion.
    float,
    /// A signed constant addition or subtraction on a phi (or a field read through a phi) of a block that dominates it, with the
    /// same checked operation on the path into every edge of that block: the unguarded form is justified by the earlier checks, which
    /// an interval cannot show (`overflow_edges.zig`).
    edge_checked,
    /// Any other operation the checker has no row for.
    other_op,

    /// The spelling in the report.
    pub fn token(self: Unchecked) []const u8 {
        return switch (self) {
            .list_bound => "list-bound",
            .list_fill => "list-fill",
            .list_keys => "list-keys",
            .float => "float",
            .edge_checked => "edge-checked",
            .other_op => "other-op",
        };
    }
};

/// How many reasons there are.
pub const unchecked_kinds = std.enums.values(Unchecked).len;

/// What a function's certificate rests on.
pub const Stats = struct {
    /// Stated intervals the checker derived (integers and lists).
    derived: u32 = 0,
    /// Stated intervals it accepted without a derivation (design §8, A6).
    assumed: u32 = 0,
    /// `proven` checks it validated.
    proven: u32 = 0,
    /// `proven` checks it could not validate, by reason.
    unchecked: [unchecked_kinds]u32 = @splat(0),
};

/// The first fault of a certificate.
pub const Failure = struct {
    check: Check,
    block: ?u32 = null,
    value: ?u32 = null,
    detail: []const u8 = "",
};

/// One function's verdict.
pub const Verdict = union(enum) {
    accepted: Stats,
    rejected: Failure,
};

/// `F2 (transfer): …` with the place, for an error line.
pub fn describe(a: Allocator, name: []const u8, failure: Failure) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "fact validation rejected {s}", .{name});
    if (failure.block) |b| try out.print(a, " at block b{d}", .{b});
    if (failure.value) |v| try out.print(a, ", value %{d}", .{v});
    try out.print(a, ": {s} ({s}): {s}", .{ failure.check.label(), failure.check.rule(), failure.detail });
    return out.items;
}

// ---- fault-injection support -------------------------------------------------------------------------------------------

/// The interval the checker derives for value `v` of function `index` (the tightest of the rules that apply to a phi), or
/// null when it derives none: an operation it accepts without a rule, a value in a dead block, a non-integer.
pub fn derivedOf(keep: Allocator, backing: Allocator, module: form.Module, index: usize, v: u32) Allocator.Error!?Interval {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    var checker: Checker = .{ .keep = keep, .a = scratch.allocator(), .module = module, .f = module.functions[index] };
    checker.prepare() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Fault => return null,
    };
    if (v >= checker.n) return null;
    const def = checker.defs[v];
    const limits = def.ty.range() orelse return null;
    if (def.kind == .phi) {
        if (!checker.reached[def.block]) return null;
        const line = def.phi.?;
        var candidates: [4]?Interval = .{ null, null, null, null };
        var joined: ?Interval = null;
        for (line.edges) |edge| {
            if (!checker.edgeLive(edge.block, def.block)) continue;
            const range = (try checker.operandRaw(edge.value, edge.block)) orelse limits;
            if (range.empty()) continue;
            joined = if (joined) |so_far| so_far.hull(range) else range;
        }
        candidates[0] = joined;
        candidates[1] = try checker.counterBound(line.*, def.block);
        candidates[2] = try checker.reduction(line.*, def.block);
        // The meet the phi rule accepts (`Checker.loopBound`) lies within each candidate it meets.
        if (joined) |hull| candidates[3] = try checker.loopBound(line.*, def.block, limits, hull);
        var best: ?Interval = null;
        for (candidates) |candidate| {
            const known = candidate orelse continue;
            if (best == null or known.hi - known.lo < best.?.hi - best.?.lo) best = known;
        }
        return best;
    }
    const inst = def.inst orelse return null;
    if (def.block != none and !checker.reached[def.block]) return null;
    if (staleAfterFacts(inst.op)) return null;
    const derived = try checker.derive(inst.*, limits, if (def.block == none) 0 else def.block);
    return if (derived.assumed) null else derived.range;
}

/// The interval value `v` has where block `at` of function `index` executes, as the checker derives it.
pub fn viewOf(keep: Allocator, backing: Allocator, module: form.Module, index: usize, v: u32, at: u32) Allocator.Error!?Interval {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    var checker: Checker = .{ .keep = keep, .a = scratch.allocator(), .module = module, .f = module.functions[index] };
    checker.prepare() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Fault => return null,
    };
    if (v >= checker.n or checker.defs[v].ty.range() == null) return null;
    const seen = try checker.operand(v, at);
    return seen;
}

// ---- the module --------------------------------------------------------------------------------------------------------

/// How often the checker accepted a stated interval on an operation it has no rule for, by operation (design §8, A6).
pub const Histogram = std.EnumArray(ir.Op, u32);

/// Check every function of `module`. `keep` holds the verdicts and failure text; `backing` the work of one function at a
/// time, returned when it is done. The result has one verdict per function, in module order. `assumed`, when given, counts
/// the intervals accepted without a rule, by operation.
pub fn validate(keep: Allocator, backing: Allocator, module: form.Module, assumed: ?*Histogram) Allocator.Error![]Verdict {
    const verdicts = try keep.alloc(Verdict, module.functions.len);
    for (module.functions, verdicts) |function, *slot| {
        var scratch = std.heap.ArenaAllocator.init(backing);
        defer scratch.deinit();
        var checker: Checker = .{ .keep = keep, .a = scratch.allocator(), .module = module, .f = function, .assumed = assumed };
        slot.* = try checker.run();
    }
    return verdicts;
}

// ---- one function ------------------------------------------------------------------------------------------------------

const Kind = enum { missing, pre, phi, inst };

/// What the checker knows of a value.
const Def = struct {
    kind: Kind = .missing,
    /// Position of the defining block in `f.blocks`; `none` for constants and parameters.
    block: u32 = none,
    ty: Type = .other,
    stated: ?Interval = null,
    inst: ?*const form.Inst = null,
    phi: ?*const form.Phi = null,
};

/// A fill cap (design §5.2): `value <= M` in every block `block` dominates.
const Cap = struct { block: u32, value: u32 };

const Fault = error{ Fault, OutOfMemory };

const Checker = struct {
    keep: Allocator,
    a: Allocator,
    module: form.Module,
    f: form.Function,
    assumed: ?*Histogram = null,
    n: usize = 0,
    defs: []Def = &.{},
    idom: []u32 = &.{},
    /// Entry and exit numbers of the blocks in a walk of the dominator tree: `a` dominates `b` when `a`'s span holds `b`'s.
    tin: []u32 = &.{},
    tout: []u32 = &.{},
    /// Per block position: some execution can reach it, by the branches the stated intervals leave open (design §5.1).
    reached: []bool = &.{},
    caps: []Cap = &.{},
    lists: []?*const form.ListFact = &.{},
    sites: []?*const form.Site = &.{},
    memo: std.AutoHashMapUnmanaged(u64, ?Interval) = .empty,
    /// Set when an operand the current rule read has an empty view: the instruction is never executed and what it states is vacuous.
    vacuous: bool = false,
    stats: Stats = .{},
    /// The first fault found.
    fault: ?Failure = null,

    fn fail(self: *Checker, check_: Check, block: ?u32, value: ?u32, comptime format: []const u8, arguments: anytype) Fault {
        const detail = std.fmt.allocPrint(self.keep, format, arguments) catch return error.OutOfMemory;
        self.fault = .{ .check = check_, .block = block, .value = value, .detail = detail };
        return error.Fault;
    }

    fn run(self: *Checker) Allocator.Error!Verdict {
        self.prepare() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Fault => return .{ .rejected = self.fault.? },
        };
        self.check() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Fault => return .{ .rejected = self.fault.? },
        };
        return .{ .accepted = self.stats };
    }

    fn prepare(self: *Checker) Fault!void {
        try self.shape();
        try self.dominators();
        try self.reach();
    }

    /// The blocks some execution can reach: from the entry along every edge a decided branch does not rule out. A block stated
    /// reachable that no such path reaches (one a later pass added on a dead edge) is unreached; it is not a claim.
    fn reach(self: *Checker) Fault!void {
        const count = self.f.blocks.len;
        self.reached = try self.a.alloc(bool, count);
        @memset(self.reached, false);
        if (count == 0) return;
        var work: std.ArrayList(u32) = .empty;
        self.reached[0] = true;
        try work.append(self.a, 0);
        while (work.pop()) |block| {
            for (successors(self.f.blocks[block].term).slice()) |next| {
                if (self.reached[next] or !self.edgeOpen(block, next)) continue;
                self.reached[next] = true;
                try work.append(self.a, next);
            }
        }
        // Checked, not trusted: no open edge leaves the reached blocks for an unreached one, so what is unreached no execution enters.
        for (self.f.blocks, 0..) |block, position| {
            if (!self.reached[position]) continue;
            for (successors(block.term).slice()) |next| {
                if (!self.reached[next] and self.edgeOpen(@intCast(position), next)) return self.fail(.f1, next, null, "b{d} is entered from the reached b{d} but is not reached", .{ next, position });
            }
        }
    }

    // ---- F1: shape ----------------------------------------------------------------------------------------------------

    fn define(self: *Checker, value: u32, def: Def) Fault!void {
        if (value >= self.n) return self.fail(.f1, null, value, "value %{d} is out of the function's range", .{value});
        if (self.defs[value].kind != .missing) return self.fail(.f1, null, value, "value %{d} is defined twice", .{value});
        if (def.stated) |range| {
            const limits = def.ty.range() orelse return self.fail(.f1, null, value, "a range on %{d}, which is not an integer or a boolean", .{value});
            // An empty interval says the value is never produced (an `exact` operation that always traps); it is checked like any other.
            if (!range.empty() and !range.within(limits)) return self.fail(.f1, null, value, "the range [{d}, {d}] of %{d} is outside its type", .{ range.lo, range.hi, value });
        }
        self.defs[value] = def;
    }

    /// The entry is also where an execution starts: with a predecessor, the refinement of a single incoming branch edge would hold
    /// for the first entry too, which no branch has taken; and a phi there would have no edge to read on the first entry.
    fn entryHasNoPredecessor(self: *Checker) Fault!void {
        if (self.f.blocks.len == 0) return;
        const entry = self.f.blocks[0];
        if (entry.preds.len != 0) return self.fail(.f1, 0, null, "the entry block b0 has {d} predecessors", .{entry.preds.len});
        if (entry.phis.len != 0) return self.fail(.f1, 0, entry.phis[0].value, "the entry block b0 has a phi", .{});
    }

    /// What the rules read of the leaves: the values defined outside every block take no operands, a parameter has the type its
    /// header gives, and a constant fits its type. The verifier (`verify_ir`) holds the compiled IR to the same.
    fn leaves(self: *Checker) Fault!void {
        for (self.f.pre) |inst| {
            if (inst.operands.a != null or inst.operands.b != null or inst.operands.x.len != 0) return self.fail(.f1, null, inst.value, "%{d} is defined outside every block and has operands", .{inst.value});
            try self.leaf(null, inst);
        }
        for (self.f.blocks, 0..) |block, position| for (block.insts) |inst| try self.leaf(@intCast(position), inst);
    }

    fn leaf(self: *Checker, block: ?u32, inst: form.Inst) Fault!void {
        switch (inst.op) {
            .param => {
                const k = inst.immediates.imm;
                if (k >= self.f.header.params.len or self.f.header.params[@intCast(k)] != inst.ty) return self.fail(.f1, block, inst.value, "parameter %{d} does not have the type the header gives parameter {d}", .{ inst.value, k });
            },
            .iconst => {
                // A capability is a constant of a type with no interval; there is nothing to fit it to.
                const limits = inst.ty.range() orelse return;
                const value: i128 = if (inst.ty == .bool) @intFromBool(inst.immediates.imm != 0) else if (inst.ty == .u64) inst.immediates.imm else @as(i64, @bitCast(inst.immediates.imm));
                if (value < limits.lo or value > limits.hi) return self.fail(.f1, block, inst.value, "the constant {d} does not fit the type of %{d}", .{ value, inst.value });
            },
            else => {},
        }
    }

    fn shape(self: *Checker) Fault!void {
        var max_value: usize = 0;
        for (self.f.pre) |inst| max_value = scanInst(max_value, inst);
        for (self.f.blocks) |block| {
            for (block.phis) |line| {
                max_value = @max(max_value, line.value);
                for (line.edges) |edge| max_value = @max(max_value, edge.value);
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
        for (self.f.aux.lists) |list| max_value = @max(max_value, list.value);
        self.n = max_value + 1;
        self.defs = try self.a.alloc(Def, self.n);
        @memset(self.defs, .{});
        self.lists = try self.a.alloc(?*const form.ListFact, self.n);
        @memset(self.lists, null);
        for (self.f.pre) |*inst| try self.define(inst.value, .{ .kind = .pre, .ty = inst.ty, .stated = inst.range, .inst = inst });
        const count = self.f.blocks.len;
        for (self.f.blocks, 0..) |block, position| {
            if (block.id != position) return self.fail(.f1, block.id, null, "blocks must be numbered 0, 1, … in order", .{});
        }
        try self.entryHasNoPredecessor();
        for (self.f.blocks, 0..) |block, position| {
            const here: u32 = @intCast(position);
            for (block.phis) |*phi_line| {
                if (phi_line.edges.len != block.preds.len) return self.fail(.f1, here, phi_line.value, "phi %{d} has {d} edges for {d} predecessors", .{ phi_line.value, phi_line.edges.len, block.preds.len });
                for (phi_line.edges, block.preds) |edge, pred| if (edge.block != pred) return self.fail(.f1, here, phi_line.value, "phi %{d} lists an edge from b{d} where the predecessor is b{d}", .{ phi_line.value, edge.block, pred });
                try self.define(phi_line.value, .{ .kind = .phi, .block = here, .ty = phi_line.ty, .stated = phi_line.range, .phi = phi_line });
            }
            for (block.insts) |*inst| try self.define(inst.value, .{ .kind = .inst, .block = here, .ty = inst.ty, .stated = inst.range, .inst = inst });
        }
        try self.edges();
        try self.leaves();
        for (self.f.aux.lists) |*list| {
            if (self.defs[list.value].kind == .missing) return self.fail(.f1, null, list.value, "a list fact names %{d}, which is not defined", .{list.value});
            if (self.lists[list.value] != null) return self.fail(.f1, null, list.value, "two list facts name %{d}", .{list.value});
            self.lists[list.value] = list;
        }
        if (count != 0 and self.f.blocks[0].dead) return self.fail(.f5, 0, null, "the entry block is stated dead", .{});
        try self.operands();
        var caps: std.ArrayList(Cap) = .empty;
        for (self.f.aux.loops) |loop| {
            if (loop.header >= count or loop.exit >= count) return self.fail(.f1, null, null, "a loop names a block that does not exist", .{});
            for (self.f.blocks[loop.header].phis) |phi| {
                const fact = self.lists[phi.value] orelse continue;
                if (fact.pattern and fact.length != null) try caps.append(self.a, .{ .block = loop.exit, .value = fact.length.? });
            }
        }
        self.caps = caps.items;
    }

    fn scanInst(max_value: usize, inst: form.Inst) usize {
        var out = @max(max_value, inst.value);
        if (inst.operands.a) |a| if (inst.op != .call) {
            out = @max(out, a);
        };
        if (inst.operands.b) |b| out = @max(out, b);
        for (inst.operands.x) |x| if (x != none) {
            out = @max(out, x);
        };
        return out;
    }

    /// Terminator targets exist, and the stated predecessors are exactly the blocks that jump here.
    fn edges(self: *Checker) Fault!void {
        const count = self.f.blocks.len;
        const seen = try self.a.alloc(std.ArrayList(u32), count);
        @memset(seen, .empty);
        for (self.f.blocks, 0..) |block, position| {
            const targets = successors(block.term);
            for (targets.slice()) |target| {
                if (target >= count) return self.fail(.f1, @intCast(position), null, "b{d} names a block that does not exist", .{block.id});
                try seen[target].append(self.a, @intCast(position));
            }
        }
        for (self.f.blocks, 0..) |block, position| {
            for (block.preds) |pred| {
                if (pred >= count) return self.fail(.f1, @intCast(position), null, "a predecessor of b{d} does not exist", .{block.id});
                if (std.mem.indexOfScalar(u32, seen[position].items, pred) == null) return self.fail(.f1, @intCast(position), null, "b{d} lists predecessor b{d}, which does not branch to it", .{ block.id, pred });
            }
            for (seen[position].items) |from| if (std.mem.indexOfScalar(u32, block.preds, from) == null) return self.fail(.f1, @intCast(position), null, "b{d} is reached from b{d}, which it does not list", .{ block.id, from });
        }
    }

    /// Every operand names a defined value, and an integer rule or a phi reads operands of its own type.
    fn operands(self: *Checker) Fault!void {
        for (self.f.blocks, 0..) |block, position| {
            const here: u32 = @intCast(position);
            for (block.phis) |line| for (line.edges) |edge| {
                if (self.defs[edge.value].kind == .missing) return self.fail(.f1, here, line.value, "phi %{d} reads %{d}, which is not defined", .{ line.value, edge.value });
                if (self.defs[edge.value].ty != line.ty) return self.fail(.f1, null, null, "phi %{d} reads %{d}, which has another type", .{ line.value, edge.value });
            };
            for (block.insts) |inst| {
                try self.sameTypes(inst);
                if (inst.operands.a) |a| if (inst.op != .call and self.defs[a].kind == .missing) return self.fail(.f1, here, inst.value, "%{d} reads %{d}, which is not defined", .{ inst.value, a });
                if (inst.operands.b) |b| if (self.defs[b].kind == .missing) return self.fail(.f1, here, inst.value, "%{d} reads %{d}, which is not defined", .{ inst.value, b });
                for (inst.operands.x) |x| if (x != none and self.defs[x].kind == .missing) return self.fail(.f1, here, inst.value, "%{d} reads %{d}, which is not defined", .{ inst.value, x });
            }
            switch (block.term) {
                .branch => |branch| if (self.defs[branch.condition].kind == .missing) return self.fail(.f1, here, null, "b{d} branches on %{d}, which is not defined", .{ block.id, branch.condition }),
                .ret => |value| if (value) |v| if (self.defs[v].kind == .missing) return self.fail(.f1, here, null, "b{d} returns %{d}, which is not defined", .{ block.id, v }),
                else => {},
            }
        }
    }

    /// The integer operations whose rules read operands of the result's own type: both operands of the arithmetic and bit
    /// operations, the left operand of a negation and of a shift (the count has a type of its own). Like the Lean checker's, the
    /// fault names neither a block nor a value.
    fn sameTypes(self: *Checker, inst: form.Inst) Fault!void {
        switch (inst.op) {
            .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .saturating_add, .neg, .shift_left, .shift_right, .bit_and, .bit_or, .bit_xor => {},
            else => return,
        }
        const wide = inst.op != .neg and inst.op != .shift_left and inst.op != .shift_right;
        const a = inst.operands.a orelse return;
        if (self.defs[a].kind != .missing and self.defs[a].ty != inst.ty) return self.fail(.f1, null, null, "%{d} reads %{d}, which does not have the type of the result", .{ inst.value, a });
        const b = inst.operands.b orelse return;
        if (wide and self.defs[b].kind != .missing and self.defs[b].ty != inst.ty) return self.fail(.f1, null, null, "%{d} reads %{d}, which does not have the type of the result", .{ inst.value, b });
    }

    // ---- the graph ------------------------------------------------------------------------------------------------------

    /// Immediate dominators (Cooper, Harvey and Kennedy), from the stated terminators; `none` for a block no path reaches.
    fn dominators(self: *Checker) Fault!void {
        const count = self.f.blocks.len;
        self.idom = try self.a.alloc(u32, count);
        @memset(self.idom, none);
        if (count == 0) return;
        const order = try self.a.alloc(u32, count);
        @memset(order, none);
        var post: std.ArrayList(u32) = .empty;
        const visited = try self.a.alloc(bool, count);
        @memset(visited, false);
        var stack: std.ArrayList(struct { block: u32, next: u8 }) = .empty;
        try stack.append(self.a, .{ .block = 0, .next = 0 });
        visited[0] = true;
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const targets = successors(self.f.blocks[top.block].term);
            if (top.next < targets.len) {
                const next = targets.buffer[top.next];
                top.next += 1;
                if (!visited[next]) {
                    visited[next] = true;
                    try stack.append(self.a, .{ .block = next, .next = 0 });
                }
            } else {
                try post.append(self.a, top.block);
                _ = stack.pop();
            }
        }
        std.mem.reverse(u32, post.items);
        for (post.items, 0..) |block, position| order[block] = @intCast(position);
        self.idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            for (post.items[1..]) |block| {
                var chosen: u32 = none;
                for (self.f.blocks[block].preds) |pred| {
                    if (self.idom[pred] == none) continue;
                    chosen = if (chosen == none) pred else self.meetOf(order, pred, chosen);
                }
                if (chosen != none and self.idom[block] != chosen) {
                    self.idom[block] = chosen;
                    changed = true;
                }
            }
        }
        try self.verifyDominators();
    }

    /// The immediate dominators are checked, not trusted: they form a tree rooted at the entry, and for every edge `p -> x` out of a
    /// block some path reaches, `x`'s dominator is `p` or one of its ancestors. Then every path from the entry to `x` passes through
    /// each ancestor of `x`: by induction on the path, the path to `p` passes through `p`'s ancestors, `x`'s are `x` and the ancestors of
    /// its dominator, which is one of them. The numbering this walk gives answers `dominates` in constant time.
    fn verifyDominators(self: *Checker) Fault!void {
        const count = self.f.blocks.len;
        self.tin = try self.a.alloc(u32, count);
        self.tout = try self.a.alloc(u32, count);
        @memset(self.tin, none);
        @memset(self.tout, none);
        const head = try self.a.alloc(u32, count);
        @memset(head, none);
        const sibling = try self.a.alloc(u32, count);
        for (self.idom[1..], 1..) |parent, child| {
            if (parent == none) continue;
            sibling[child] = head[parent];
            head[parent] = @intCast(child);
        }
        var clock: u32 = 0;
        var stack: std.ArrayList(u32) = .empty;
        self.tin[0] = clock;
        clock += 1;
        try stack.append(self.a, 0);
        var cursor = try self.a.dupe(u32, head);
        while (stack.items.len != 0) {
            const top = stack.items[stack.items.len - 1];
            const child = cursor[top];
            if (child == none) {
                self.tout[top] = clock;
                clock += 1;
                _ = stack.pop();
                continue;
            }
            cursor[top] = sibling[child];
            self.tin[child] = clock;
            clock += 1;
            try stack.append(self.a, child);
        }
        for (self.idom, 0..) |parent, block| {
            if (parent != none and self.tin[block] == none) return self.fail(.f1, @intCast(block), null, "the dominators of b{d} do not lead to the entry", .{block});
        }
        for (self.f.blocks, 0..) |block, position| {
            if (self.idom[position] == none) continue;
            for (successors(block.term).slice()) |next| {
                if (next == 0) continue;
                const parent = self.idom[next];
                if (parent == none) return self.fail(.f1, next, null, "b{d} is reached from b{d} but has no dominator", .{ next, position });
                if (!(self.tin[parent] <= self.tin[position] and self.tout[position] <= self.tout[parent])) return self.fail(.f1, next, null, "the dominator b{d} of b{d} does not dominate its predecessor b{d}", .{ parent, next, position });
            }
        }
    }

    fn meetOf(self: *Checker, order: []const u32, a: u32, b: u32) u32 {
        var x = a;
        var y = b;
        while (x != y) {
            while (order[x] > order[y]) x = self.idom[x];
            while (order[y] > order[x]) y = self.idom[y];
        }
        return x;
    }

    fn dominates(self: *const Checker, a: u32, b: u32) bool {
        if (a == b) return true;
        if (self.idom[a] == none or self.idom[b] == none) return false;
        return self.tin[a] <= self.tin[b] and self.tout[b] <= self.tout[a];
    }

    // ---- intervals ------------------------------------------------------------------------------------------------------

    /// The stated interval of a value as its own definition gives it (design §3, `base`); null when nothing is stated.
    fn base(self: *Checker, v: u32) ?Interval {
        const def = self.defs[v];
        const limits = def.ty.range() orelse return null;
        switch (def.kind) {
            .missing => return null,
            .phi => return def.stated,
            .pre, .inst => {
                const inst = def.inst.?;
                return switch (inst.op) {
                    .iconst => Interval.point(constant(def)),
                    .undef, .union_payload, .union_take, .record_take, .box_take => limits,
                    .param => self.paramInterval(inst.*) orelse limits,
                    .call => def.stated orelse limits,
                    else => def.stated,
                };
            },
        }
    }

    /// The interval of `v` where block `at` executes: its own, narrowed by the fill caps and the dominating branch edges.
    fn view(self: *Checker, v: u32, at: u32) Allocator.Error!?Interval {
        const key = (@as(u64, v) << 32) | at;
        if (self.memo.get(key)) |known| return known;
        var range = self.base(v) orelse {
            try self.memo.put(self.a, key, null);
            return null;
        };
        for (self.caps) |cap| {
            if (cap.value == v and self.dominates(cap.block, at)) range.hi = @min(range.hi, M);
        }
        var x = at;
        while (true) {
            if (self.refining(x)) |edge| range = try self.refine(range, v, edge);
            if (x == 0 or self.idom[x] == none) break;
            x = self.idom[x];
        }
        try self.memo.put(self.a, key, range);
        return range;
    }

    /// The view of an operand, else its type's range; null for a non-integer. An operand that is never produced has an empty view.
    fn operandRaw(self: *Checker, v: ?u32, at: u32) Allocator.Error!?Interval {
        const value = v orelse return null;
        if (value == none) return null;
        const limits = self.defs[value].ty.range() orelse return null;
        return (try self.view(value, at)) orelse limits;
    }

    /// The interval of an operand for a rule: its view, else its type's range; null for a non-integer. An operand that is never
    /// produced makes the instruction vacuous (`vacuous`) and reads as its type's range.
    fn operand(self: *Checker, v: ?u32, at: u32) Allocator.Error!?Interval {
        const seen = (try self.operandRaw(v, at)) orelse return null;
        if (!seen.empty()) return seen;
        self.vacuous = true;
        return self.defs[v.?].ty.range();
    }

    const Edge = struct { cmp: *const form.Inst, taken: bool, source: u32 };

    /// The refining edge into block `x` (design §5.2).
    fn refining(self: *Checker, x: u32) ?Edge {
        const preds = self.f.blocks[x].preds;
        if (preds.len != 1) return null;
        const branch = switch (self.f.blocks[preds[0]].term) {
            .branch => |b| b,
            else => return null,
        };
        if (branch.then == branch.otherwise) return null;
        const condition = self.defs[branch.condition];
        const inst = condition.inst orelse return null;
        if (condition.kind == .phi or inst.op != .cmp) return null;
        return .{ .cmp = inst, .taken = branch.then == x, .source = preds[0] };
    }

    fn refine(self: *Checker, range: Interval, v: u32, edge: Edge) Allocator.Error!Interval {
        const left = edge.cmp.operands.a orelse return range;
        const right = edge.cmp.operands.b orelse return range;
        if (left != v and right != v) return self.refineSquare(range, v, edge);
        var predicate = predicateOf(edge.cmp.immediates.imm) orelse return range;
        if (!edge.taken) predicate = negate(predicate);
        const other = if (left == v) right else left;
        if (left != v) predicate = mirror(predicate);
        const bound = (try self.operandRaw(other, edge.source)) orelse return range;
        if (bound.empty()) return range;
        var out = range;
        switch (predicate) {
            .lt => out.hi = @min(out.hi, bound.hi - 1),
            .le => out.hi = @min(out.hi, bound.hi),
            .gt => out.lo = @max(out.lo, bound.lo + 1),
            .ge => out.lo = @max(out.lo, bound.lo),
            .eq => out = out.meet(bound),
            .ne => {},
        }
        return out;
    }

    fn isSquareOf(self: *Checker, raw: ?u32, v: u32) bool {
        const value = raw orelse return false;
        const def = self.defs[value];
        const inst = def.inst orelse return false;
        return def.kind != .phi and inst.op == .mul and inst.check != .none and inst.operands.a == v and inst.operands.b == v;
    }

    fn refineSquare(self: *Checker, range: Interval, v: u32, edge: Edge) Allocator.Error!Interval {
        const on_left = self.isSquareOf(edge.cmp.operands.a, v);
        if (!on_left and !self.isSquareOf(edge.cmp.operands.b, v)) return range;
        var predicate = predicateOf(edge.cmp.immediates.imm) orelse return range;
        if (!edge.taken) predicate = negate(predicate);
        if (!on_left) predicate = mirror(predicate);
        const bound = (try self.operandRaw(if (on_left) edge.cmp.operands.b else edge.cmp.operands.a, edge.source)) orelse return range;
        if (bound.empty()) return range;
        const top: i128 = switch (predicate) {
            .lt => bound.hi - 1,
            .le, .eq => bound.hi,
            else => return range,
        };
        if (top < 0) return range;
        const root: i128 = std.math.sqrt(@as(u128, @intCast(top)));
        return range.meet(.{ .lo = -root, .hi = root });
    }

    // ---- reachability ---------------------------------------------------------------------------------------------------

    /// Whether the edge `from → to` can execute, by the stated reachability and the branch's decided condition.
    fn edgeLive(self: *Checker, from: u32, to: u32) bool {
        return self.reached[from] and self.edgeOpen(from, to);
    }

    /// Whether the branch at the end of `from` leaves the edge to `to` open: it is not decided against it.
    fn edgeOpen(self: *Checker, from: u32, to: u32) bool {
        const branch = switch (self.f.blocks[from].term) {
            .branch => |b| b,
            else => return true,
        };
        const condition = self.base(branch.condition) orelse return true;
        if (condition.lo == 1 and condition.hi == 1) return branch.then == to;
        if (condition.lo == 0 and condition.hi == 0) return branch.otherwise == to;
        return true;
    }

    // ---- the checks -----------------------------------------------------------------------------------------------------

    fn check(self: *Checker) Fault!void {
        try self.reachability();
        try self.intervals();
        try self.listFacts();
        try self.interprocedural();
        try self.proven();
    }

    fn reachability(self: *Checker) Fault!void {
        for (self.f.blocks, 0..) |block, position| {
            if (!block.dead) continue;
            if (self.reached[position]) return self.fail(.f5, @intCast(position), null, "b{d} is stated dead but an execution can reach it", .{block.id});
            for (block.preds) |pred| {
                if (self.edgeLive(pred, @intCast(position))) return self.fail(.f5, @intCast(position), null, "b{d} is stated dead but the edge from b{d} can execute", .{ block.id, pred });
            }
        }
    }

    /// F2, F3 and F4 over every instruction of every block not stated dead.
    fn intervals(self: *Checker) Fault!void {
        for (self.f.pre) |inst| try self.instruction(inst, 0);
        for (self.f.blocks, 0..) |block, position| {
            if (!self.reached[position]) continue;
            const here: u32 = @intCast(position);
            for (block.phis) |phi_line| try self.joinPhi(phi_line, here);
            for (block.insts) |inst| try self.instruction(inst, here);
        }
    }

    fn joinPhi(self: *Checker, phi_line: form.Phi, here: u32) Fault!void {
        const stated = phi_line.range orelse return;
        const limits = phi_line.ty.range() orelse return;
        var joined: ?Interval = null;
        for (phi_line.edges) |edge| {
            if (!self.edgeLive(edge.block, here)) continue;
            const range = (try self.operandRaw(edge.value, edge.block)) orelse limits;
            if (range.empty()) continue;
            joined = if (joined) |so_far| so_far.hull(range) else range;
        }
        const derived = joined orelse {
            self.stats.derived += 1;
            return;
        };
        if (derived.within(stated)) {
            self.stats.derived += 1;
            return;
        }
        if (try self.loopBound(phi_line, here, limits, derived)) |bound| {
            if (bound.within(stated)) {
                self.stats.derived += 1;
                return;
            }
        }
        return self.fail(.f3, here, phi_line.value, "phi %{d} states [{d}, {d}] but its live operands give [{d}, {d}]", .{ phi_line.value, stated.lo, stated.hi, derived.lo, derived.hi });
    }

    /// The tightest bound the loop rules give the phi `phi_line` of block `here`, met with `hull`, the hull of its live operands
    /// (design §5.5, F3): the counter bound when the phi is a counted loop's counter, the reduction bound when it is a reduction
    /// (a phi is never both). Each is a bound the checker derives itself and each holds on its own, so the values the phi takes
    /// lie in their meet. A counter bound is met with the hull only when it fits the type (`bound.hi <= limits.hi`, so the
    /// counter cannot wrap); otherwise it counts alone, as before the meet. Null when neither rule applies.
    fn loopBound(self: *Checker, phi_line: form.Phi, here: u32, limits: Interval, hull: Interval) Allocator.Error!?Interval {
        if (try self.counterBound(phi_line, here)) |bound| {
            if (bound.hi <= limits.hi) return hull.meet(bound);
            return bound;
        }
        if (try self.reduction(phi_line, here)) |bound| return hull.meet(bound);
        return null;
    }

    // ---- counted loops and reductions (design §5.5) ----------------------------------------------------------------------

    const Counted = struct { counter: u32, start: u32, bound: u32, latch_index: usize };

    /// The counted loop whose header is block `header`: two predecessors (the entry and the latch), a branch `counter < bound`
    /// into the body, and `counter = phi(start, counter + 1)`.
    fn countedAt(self: *Checker, header: u32) ?Counted {
        for (self.f.aux.loops) |loop| {
            if (loop.header != header) continue;
            const block = self.f.blocks[header];
            if (block.preds.len != 2) continue;
            const branch = switch (block.term) {
                .branch => |b| b,
                else => continue,
            };
            if (branch.then != loop.body) continue;
            // The guard `counter < bound` holds throughout the body only if the body is entered by that edge alone and every trip back
            // to the latch passes through it; otherwise the back edge is not guarded and the counter's bound is false.
            const guard = self.refining(loop.body) orelse continue;
            if (guard.source != header or !self.dominates(loop.body, loop.latch)) continue;
            const cond = self.defs[branch.condition];
            const cmp = cond.inst orelse continue;
            if (cond.kind == .phi or cmp.op != .cmp or predicateOf(cmp.immediates.imm) != Predicate.lt) continue;
            const counter = cmp.operands.a orelse continue;
            const bound = cmp.operands.b orelse continue;
            const counter_def = self.defs[counter];
            if (counter_def.kind != .phi or counter_def.block != header) continue;
            const latch_index: usize = if (block.preds[0] == loop.latch) 0 else 1;
            if (block.preds[latch_index] != loop.latch) continue;
            const line = counter_def.phi.?;
            const step_def = self.defs[line.edges[latch_index].value];
            const step = step_def.inst orelse continue;
            if (step_def.kind == .phi or step.op != .add or step.operands.a != counter) continue;
            const one = self.defs[step.operands.b orelse continue].inst orelse continue;
            if (one.op != .iconst or one.immediates.imm != 1) continue;
            return .{ .counter = counter, .start = line.edges[1 - latch_index].value, .bound = bound, .latch_index = latch_index };
        }
        return null;
    }

    /// The interval of a counted loop's counter at its header (design §5.5, Counter): from the entry value's lowest to the larger of
    /// its highest and the bound's highest. The counter is `s + j` at the `j`th visit of the header, and the visit exists only
    /// because the counter of the visit before was below the bound.
    fn counterBound(self: *Checker, phi_line: form.Phi, here: u32) Allocator.Error!?Interval {
        const counted = self.countedAt(here) orelse return null;
        if (counted.counter != phi_line.value) return null;
        const limits = phi_line.ty.range() orelse return null;
        const start = self.base(counted.start) orelse limits;
        const bound = (try self.operand(counted.bound, here)) orelse return null;
        return .{ .lo = start.lo, .hi = @max(start.hi, bound.hi) };
    }

    /// At most this many iterations of the counted loop at `header` complete (design §5.5, Trips).
    fn tripBound(self: *Checker, header: u32) Allocator.Error!?i128 {
        const counted = self.countedAt(header) orelse return null;
        const bound = (try self.operand(counted.bound, header)) orelse return null;
        const start = self.base(counted.start) orelse (self.defs[counted.start].ty.range() orelse return null);
        return @max(bound.hi - start.lo, 0);
    }

    /// The interval a reduction phi of a counted loop stays in: its entry value moved by at most `trips` steps (design §5.5).
    fn reduction(self: *Checker, phi_line: form.Phi, here: u32) Allocator.Error!?Interval {
        const counted = self.countedAt(here) orelse return null;
        if (counted.counter == phi_line.value or phi_line.edges.len != 2) return null;
        var budget: u32 = growth_budget;
        const step = (try self.growth(phi_line.value, phi_line.edges[counted.latch_index].value, &budget)) orelse return null;
        const entry = phi_line.edges[1 - counted.latch_index];
        const start = (try self.operand(entry.value, entry.block)) orelse return null;
        const trips = (try self.tripBound(here)) orelse return null;
        return grown(start, step, trips);
    }

    /// How far value `raw` lies from `acc` in the same iteration, as an interval of `raw - acc`, or null when `raw` is not `acc`
    /// moved by checked additions and subtractions, joins of such values, and inner counted loops that move it.
    fn growth(self: *Checker, acc: u32, raw: u32, budget: *u32) Allocator.Error!?Interval {
        if (budget.* == 0) return null;
        budget.* -= 1;
        if (raw == acc) return Interval.point(0);
        const def = self.defs[raw];
        const where = def.block;
        if (where == none) return null;
        if (def.kind == .phi) {
            for (self.f.aux.loops) |loop| {
                if (loop.header == where) return self.innerGrowth(acc, raw, where, budget);
            }
            var out: ?Interval = null;
            for (def.phi.?.edges) |edge| {
                if (!self.edgeLive(edge.block, where)) continue;
                const moved = (try self.growth(acc, edge.value, budget)) orelse return null;
                out = if (out) |so_far| so_far.hull(moved) else moved;
            }
            return out;
        }
        const inst = def.inst orelse return null;
        if (inst.op != .add and inst.op != .sub) return null;
        // A wrapping operation may wrap: only checked or proven ones move by their operand.
        if (inst.check == .none) return null;
        if (try self.growth(acc, inst.operands.a orelse return null, budget)) |x| {
            const y = (try self.operand(inst.operands.b, where)) orelse return null;
            if (inst.op == .add) return .{ .lo = x.lo +| y.lo, .hi = x.hi +| y.hi };
            return .{ .lo = x.lo -| y.hi, .hi = x.hi -| y.lo };
        }
        if (inst.op == .sub) return null;
        const y = (try self.growth(acc, inst.operands.b orelse return null, budget)) orelse return null;
        const x = (try self.operand(inst.operands.a, where)) orelse return null;
        return .{ .lo = x.lo +| y.lo, .hi = x.hi +| y.hi };
    }

    /// The growth of a phi in the header of an inner counted loop: its entry value's growth, plus at most the inner loop's trips of
    /// its own per-iteration growth.
    fn innerGrowth(self: *Checker, acc: u32, phi_value: u32, header: u32, budget: *u32) Allocator.Error!?Interval {
        const inner = self.countedAt(header) orelse return null;
        const line = self.defs[phi_value].phi.?;
        if (line.edges.len != 2) return null;
        const entry = (try self.growth(acc, line.edges[1 - inner.latch_index].value, budget)) orelse return null;
        const step = (try self.growth(phi_value, line.edges[inner.latch_index].value, budget)) orelse return null;
        const trips = (try self.tripBound(header)) orelse return null;
        return grown(entry, step, trips);
    }

    const Derived = struct { range: Interval, assumed: bool = false };

    fn instruction(self: *Checker, inst: form.Inst, here: u32) Fault!void {
        const limits = inst.ty.range() orelse return;
        const stated = inst.range orelse return;
        if (stated.lo == limits.lo and stated.hi == limits.hi) return;
        const derived = try self.derive(inst, limits, here);
        if (derived.assumed) {
            self.stats.assumed += 1;
            if (self.assumed) |histogram| histogram.getPtr(inst.op).* += 1;
            return;
        }
        if (derived.range.within(stated)) {
            self.stats.derived += 1;
            return;
        }
        if (staleAfterFacts(inst.op)) {
            // A pass that ran after the facts rewrote the list or the callee this result reads, and the final IR no longer shows
            // why the interval holds (design §8, A6). It is counted, not rejected.
            self.stats.assumed += 1;
            if (self.assumed) |histogram| histogram.getPtr(inst.op).* += 1;
            return;
        }
        const block: ?u32 = if (self.defs[inst.value].kind == .pre) null else here;
        const message = "{s} %{d} states [{d}, {d}] but its operands give [{d}, {d}]";
        return self.fail(.f2, block, inst.value, message, .{ @tagName(inst.op), inst.value, stated.lo, stated.hi, derived.range.lo, derived.range.hi });
    }

    /// What the transfer rule of `inst` gives; empty when an operand is never produced, since the instruction then never executes.
    fn derive(self: *Checker, inst: form.Inst, limits: Interval, here: u32) Allocator.Error!Derived {
        self.vacuous = false;
        const found = try self.deriveRule(inst, limits, here);
        if (self.vacuous) return .{ .range = .{ .lo = 1, .hi = 0 } };
        return found;
    }

    fn deriveRule(self: *Checker, inst: form.Inst, limits: Interval, here: u32) Allocator.Error!Derived {
        const full: Derived = .{ .range = limits };
        const unknown: Derived = .{ .range = limits, .assumed = true };
        switch (inst.op) {
            .iconst => return .{ .range = Interval.point(constant(self.defs[inst.value])) },
            .param => return .{ .range = self.paramInterval(inst) orelse limits },
            .add, .sub, .mul => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const y = (try self.operand(inst.operands.b, here)) orelse return full;
                const exact = arithmetic(inst.op, x, y);
                if (exact.within(limits)) return .{ .range = exact };
                return .{ .range = if (inst.check == .none) limits else exact.meet(limits) };
            },
            .saturating_add => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const y = (try self.operand(inst.operands.b, here)) orelse return full;
                return .{ .range = .{ .lo = std.math.clamp(x.lo + y.lo, limits.lo, limits.hi), .hi = std.math.clamp(x.hi + y.hi, limits.lo, limits.hi) } };
            },
            .shift_right => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const count = (try self.operand(inst.operands.b, here)) orelse return full;
                if (count.lo < 0 or count.hi >= inst.ty.bits()) return full;
                const lo: u7 = @intCast(count.lo);
                const hi: u7 = @intCast(count.hi);
                return .{ .range = .{ .lo = @min(x.lo >> lo, x.lo >> hi), .hi = @max(x.hi >> lo, x.hi >> hi) } };
            },
            .floor_div, .div => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const d = (try self.operand(inst.operands.b, here)) orelse return full;
                if (d.lo <= 0 or x.lo < 0) return full;
                return .{ .range = .{ .lo = @divFloor(x.lo, d.hi), .hi = @divFloor(x.hi, d.lo) } };
            },
            .floor_rem => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const d = (try self.operand(inst.operands.b, here)) orelse return full;
                if (d.lo <= 0) return full;
                if (x.lo >= 0 and x.hi < d.lo) return .{ .range = x };
                return .{ .range = .{ .lo = 0, .hi = d.hi - 1 } };
            },
            .rem => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const d = (try self.operand(inst.operands.b, here)) orelse return full;
                if (d.lo <= 0 or x.lo < 0) return full;
                return .{ .range = .{ .lo = 0, .hi = @min(x.hi, d.hi - 1) } };
            },
            .bit_xor => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                const y = (try self.operand(inst.operands.b, here)) orelse return full;
                if (x.lo < 0 or y.lo < 0) return full;
                const high: u128 = @intCast(@max(x.hi, y.hi));
                const bits: u8 = @intCast(128 - @clz(high));
                const bound: i128 = if (bits == 0) 0 else @intCast((@as(u128, 1) << @intCast(bits)) - 1);
                return .{ .range = (Interval{ .lo = 0, .hi = bound }).meet(limits) };
            },
            .convert => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                if (inst.check == .none and !x.within(limits)) return full;
                return .{ .range = x.meet(limits) };
            },
            .cmp => return .{ .range = try self.compare(inst, here) },
            .not => {
                const x = (try self.operand(inst.operands.a, here)) orelse return full;
                return .{ .range = .{ .lo = 1 - x.hi, .hi = 1 - x.lo } };
            },
            .list_len => {
                const len = if (inst.operands.a) |a| self.factOf(self.liveList(a)).len else null;
                return .{ .range = (len orelse Interval{ .lo = 0, .hi = M }).meet(.{ .lo = 0, .hi = M }) };
            },
            .str_len, .dict_entries => return .{ .range = .{ .lo = 0, .hi = M } },
            .list_get, .array_get => {
                const elements = if (inst.operands.a) |a| self.factOf(self.liveList(a)).elems else null;
                return .{ .range = elements orelse limits };
            },
            .call => {
                const callee = inst.operands.a orelse return full;
                if (callee >= self.module.functions.len) return full;
                const returned = self.module.functions[callee].boundary.returns orelse return full;
                return .{ .range = returned.meet(limits) };
            },
            // Stage 2 (design §8, A6): the facts of records, dictionaries and floats are stated and accepted.
            .record_get, .list_get_field, .dict_len, .dict_entry_key, .dict_entry_value, .float_to_int => return unknown,
            else => return unknown,
        }
    }

    fn compare(self: *Checker, inst: form.Inst, here: u32) Allocator.Error!Interval {
        const undecided: Interval = .{ .lo = 0, .hi = 1 };
        const x = (try self.operand(inst.operands.a, here)) orelse return undecided;
        const y = (try self.operand(inst.operands.b, here)) orelse return undecided;
        const predicate = predicateOf(inst.immediates.imm) orelse return undecided;
        const decided: ?bool = switch (predicate) {
            .lt => if (x.hi < y.lo) true else if (x.lo >= y.hi) false else null,
            .le => if (x.hi <= y.lo) true else if (x.lo > y.hi) false else null,
            .gt => if (x.lo > y.hi) true else if (x.hi <= y.lo) false else null,
            .ge => if (x.lo >= y.hi) true else if (x.hi < y.lo) false else null,
            .eq => if (x.lo == x.hi and y.lo == y.hi and x.lo == y.lo) true else if (x.hi < y.lo or y.hi < x.lo) false else null,
            .ne => if (x.hi < y.lo or y.hi < x.lo) true else if (x.lo == x.hi and y.lo == y.hi and x.lo == y.lo) false else null,
        };
        return if (decided) |value| Interval.point(@intFromBool(value)) else undecided;
    }

    // ---- lists ----------------------------------------------------------------------------------------------------------

    const ListView = struct { len: ?Interval = null, elems: ?Interval = null };

    /// The stated fact of list `v`.
    fn factOf(self: *Checker, v: u32) ListView {
        if (v >= self.n) return .{};
        const fact = self.lists[v] orelse return .{};
        return .{ .len = fact.len, .elems = fact.elems };
    }

    /// The value whose list fact a list operation reads: through views and borrows, and through a phi with one live operand.
    fn liveList(self: *Checker, v: u32) u32 {
        const def = self.defs[v];
        if (def.kind == .inst) {
            const inst = def.inst.?;
            if (inst.op == .list_view_of or inst.op == .borrow) return if (inst.operands.a) |a| self.liveList(a) else v;
        }
        if (def.kind == .phi) {
            const line = def.phi.?;
            var only: ?u32 = null;
            for (line.edges) |edge| {
                if (!self.edgeLive(edge.block, def.block)) continue;
                if (only != null and only.? != edge.value) return v;
                only = edge.value;
            }
            return only orelse v;
        }
        return v;
    }

    /// F2 over the list facts: each stated length and element interval contains what the list operation derives.
    fn listFacts(self: *Checker) Fault!void {
        for (self.f.aux.lists) |fact| {
            const def = self.defs[fact.value];
            if (def.block != none and !self.reached[def.block]) continue;
            const here = if (def.block == none) 0 else def.block;
            const derived = try self.deriveList(def, here);
            if (fact.len) |stated| {
                if (derived.known and derived.len != null) {
                    const found = derived.len.?;
                    const message = "the list length of %{d} states [{d}, {d}] but its operation gives [{d}, {d}]";
                    if (!found.within(stated)) return self.fail(.f2, def.block, fact.value, message, .{ fact.value, stated.lo, stated.hi, found.lo, found.hi });
                    self.stats.derived += 1;
                } else self.noteAssumed(def);
            }
            if (fact.elems) |stated| {
                if (derived.known and derived.elems != null) {
                    const found = derived.elems.?;
                    const message = "the list elements of %{d} state [{d}, {d}] but its operation gives [{d}, {d}]";
                    if (!found.within(stated)) return self.fail(.f2, def.block, fact.value, message, .{ fact.value, stated.lo, stated.hi, found.lo, found.hi });
                    self.stats.derived += 1;
                } else self.noteAssumed(def);
            }
        }
    }

    fn noteAssumed(self: *Checker, def: Def) void {
        self.stats.assumed += 1;
        if (self.assumed) |histogram| if (def.inst) |inst| {
            histogram.getPtr(inst.op).* += 1;
        };
    }

    const Derivation = struct { known: bool = false, len: ?Interval = null, elems: ?Interval = null };

    fn scalar(self: *Checker, v: ?u32, here: u32) Allocator.Error!?Interval {
        const value = v orelse return null;
        if (value == none or self.defs[value].ty.range() == null) return null;
        const seen = try self.operand(value, here);
        return seen;
    }

    /// The length and element intervals the operation defining a list value gives it (design §5.5, A6).
    fn deriveList(self: *Checker, def: Def, here: u32) Allocator.Error!Derivation {
        if (def.kind == .phi) return self.joinLists(def);
        const inst = def.inst orelse return .{};
        switch (inst.op) {
            .list_new => return .{ .known = true, .len = Interval.point(0) },
            .list_push => {
                const old = self.factOf(inst.operands.a orelse return .{});
                const value = try self.scalar(inst.operands.b, here);
                var out: Derivation = .{ .known = true };
                if (old.len) |len| out.len = .{ .lo = len.lo + 1, .hi = @min(len.hi + 1, M) };
                if (old.len) |len| {
                    if (len.lo == 0 and len.hi == 0) out.elems = value;
                }
                if (out.elems == null) out.elems = if (old.elems) |held| (if (value) |v| held.hull(v) else null) else null;
                return out;
            },
            .list_pop => {
                const old = self.factOf(inst.operands.a orelse return .{});
                var out: Derivation = .{ .known = true, .elems = old.elems };
                if (old.len) |len| out.len = .{ .lo = @max(len.lo - 1, 0), .hi = @max(len.hi - 1, 0) };
                return out;
            },
            .list_copy, .list_view_of, .borrow => {
                const old = self.factOf(inst.operands.a orelse return .{});
                return .{ .known = true, .len = old.len, .elems = old.elems };
            },
            .list_set, .array_set => {
                const old = self.factOf(inst.operands.a orelse return .{});
                const value = if (inst.operands.x.len != 0) try self.scalar(inst.operands.x[0], here) else null;
                return .{ .known = true, .len = old.len, .elems = if (old.elems) |held| (if (value) |v| held.hull(v) else null) else null };
            },
            .record_make => {
                if (inst.ty != .list) return .{};
                var hull: ?Interval = null;
                for (inst.operands.x, 0..) |operand_, k| {
                    const value = try self.scalar(operand_, here);
                    hull = if (k == 0) value else if (hull) |held| (if (value) |v| held.hull(v) else null) else null;
                }
                return .{ .known = true, .len = Interval.point(@intCast(inst.operands.x.len)), .elems = hull };
            },
            else => return .{},
        }
    }

    fn joinLists(self: *Checker, def: Def) Derivation {
        const line = def.phi.?;
        var len: ?Interval = null;
        var elems: ?Interval = null;
        var lengths_known = true;
        var elems_known = true;
        var seen = false;
        for (line.edges) |edge| {
            if (!self.edgeLive(edge.block, def.block)) continue;
            const fact = self.factOf(edge.value);
            if (fact.len) |l| len = if (len) |so_far| so_far.hull(l) else l else lengths_known = false;
            if (fact.elems) |e| elems = if (elems) |so_far| so_far.hull(e) else e else elems_known = false;
            seen = true;
        }
        if (!seen) return .{};
        return .{ .known = true, .len = if (lengths_known) len else null, .elems = if (elems_known) elems else null };
    }

    // ---- inter-procedural facts -----------------------------------------------------------------------------------------

    /// The interval the function states for parameter `inst`, when anyone outside the module cannot call it.
    fn paramInterval(self: *const Checker, inst: form.Inst) ?Interval {
        const k = inst.immediates.imm;
        if (!self.f.header.internal or self.f.header.address_taken or k >= self.f.boundary.params.len) return null;
        return self.f.boundary.params[k];
    }

    /// F6: every call in this function passes arguments inside the callee's stated parameter intervals, and every `ret` of it
    /// returns inside its stated return interval.
    fn interprocedural(self: *Checker) Fault!void {
        for (self.f.blocks, 0..) |block, position| {
            if (!self.reached[position]) continue;
            const here: u32 = @intCast(position);
            for (block.insts) |inst| {
                if (inst.op != .call) continue;
                const index = inst.operands.a orelse continue;
                if (index >= self.module.functions.len) continue;
                const callee = self.module.functions[index];
                if (!callee.header.internal or callee.header.address_taken) continue;
                for (inst.operands.x, 0..) |argument, k| {
                    if (k >= callee.boundary.params.len or argument == none) continue;
                    const claim = callee.boundary.params[k] orelse continue;
                    const seen = (try self.operandRaw(argument, here)) orelse continue;
                    if (seen.empty()) continue;
                    const passed = reinterpret(seen, self.defs[argument].ty, callee.header.params[k]);
                    const message = "the call of {s} passes %{d} in [{d}, {d}] where parameter {d} is stated [{d}, {d}]";
                    if (!passed.within(claim)) return self.fail(.f6, here, inst.value, message, .{ callee.header.name, argument, passed.lo, passed.hi, k, claim.lo, claim.hi });
                }
            }
            const returned = switch (block.term) {
                .ret => |value| value,
                else => null,
            };
            if (returned) |value| if (self.f.boundary.returns) |claim| {
                if (self.defs[value].ty.range() != null) {
                    const seen = (try self.operandRaw(value, here)) orelse continue;
                    if (!seen.empty() and !seen.within(claim)) return self.fail(.f6, here, value, "{s} returns %{d} in [{d}, {d}] where its return is stated [{d}, {d}]", .{ self.f.header.name, value, seen.lo, seen.hi, claim.lo, claim.hi });
                }
            };
        }
    }

    // ---- F7: proven checks ----------------------------------------------------------------------------------------------

    fn siteOf(self: *Checker, value: u32) ?*const form.Site {
        if (self.sites.len == 0) {
            self.sites = self.a.alloc(?*const form.Site, self.n) catch return null;
            @memset(self.sites, null);
            for (self.f.aux.sites) |*site| if (site.value < self.n) {
                self.sites[site.value] = site;
            };
        }
        return if (value < self.n) self.sites[value] else null;
    }

    fn proven(self: *Checker) Fault!void {
        for (self.f.blocks, 0..) |block, position| {
            if (!self.reached[position]) continue;
            for (block.insts) |inst| {
                if (inst.check != .proven) continue;
                try self.provenCheck(inst, @intCast(position));
            }
        }
    }

    /// The viewed intervals the check of `inst` reads, as the checker derives them (design §10, Sites).
    fn derivedParts(self: *Checker, inst: form.Inst, here: u32) Allocator.Error!Parts {
        var out: Parts = .{};
        switch (inst.op) {
            .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem => {
                out.set(0, try self.operand(inst.operands.a, here));
                out.set(1, try self.operand(inst.operands.b, here));
            },
            .neg, .convert => out.set(0, try self.operand(inst.operands.a, here)),
            .shift_left, .shift_right, .array_get, .array_set => out.set(0, try self.operand(inst.operands.b, here)),
            .list_get, .list_get_field, .list_set => {
                out.set(0, try self.operand(inst.operands.b, here));
                out.set(1, if (inst.operands.a) |a| self.factOf(self.liveList(a)).len else null);
            },
            .list_pop => out.set(0, if (inst.operands.a) |a| self.factOf(self.liveList(a)).len else null),
            else => {},
        }
        return out;
    }

    fn provenCheck(self: *Checker, inst: form.Inst, here: u32) Fault!void {
        if (!hasRow(inst.op)) return self.unchecked(inst);
        const site = self.siteOf(inst.value) orelse return self.noCheck(inst, here, "its site is missing: a proven check states the reason it cannot fail");
        self.vacuous = false;
        const derived = try self.derivedParts(inst, here);
        if (self.vacuous) {
            // An operand is never produced: the check never runs.
            self.stats.proven += 1;
            return;
        }
        var stated: Parts = .{};
        for (0..2) |k| {
            const claim: ?Interval = if (k < site.parts.len) site.parts[k] else null;
            stated.set(k, claim);
            const actual = derived.get(k);
            if (claim) |part| {
                const known = actual orelse return self.fail(.f7, here, inst.value, "the site of {s} %{d} states [{d}, {d}] for operand {d} that no fact backs", .{ @tagName(inst.op), inst.value, part.lo, part.hi, k });
                const message = "the site of {s} %{d} states [{d}, {d}] for operand {d} but the operands give [{d}, {d}]";
                if (!known.within(part)) return self.fail(.f7, here, inst.value, message, .{ @tagName(inst.op), inst.value, part.lo, part.hi, k, known.lo, known.hi });
            }
        }
        if (rowHolds(inst, &stated.values) orelse false) {
            self.stats.proven += 1;
            return;
        }
        switch (inst.op) {
            .list_get, .list_get_field, .list_set => return self.listUnchecked(inst),
            .add, .sub => {
                if (!self.edgeChecked(inst, here)) return self.noCheck(inst, here, "its site does not rule out the failure");
                self.stats.unchecked[@backingInt(Unchecked.edge_checked)] += 1;
            },
            else => return self.noCheck(inst, here, "its site does not rule out the failure"),
        }
    }

    /// Whether a `proven` signed constant addition or subtraction has the shape the edge induction of `overflow_edges.zig` proves: its
    /// left operand is a phi `P` (or the read of a field of a record phi) of a block `H` that dominates it, and on the path into each
    /// edge of `H` (the predecessor or one of its dominators) the same operation with the same constant is checked on the value `P`
    /// takes from that edge (or on the same field of the record it takes). Each such earlier operation ran before `P` took its value
    /// from that edge, so `P`, whichever edge it came from, passed it. It is counted, not validated: that two reads of a field are
    /// reads of the same field is the pass's alias analysis, not the certificate's.
    fn edgeChecked(self: *Checker, inst: form.Inst, here: u32) bool {
        if (inst.ty != .i64) return false;
        const right = self.defs[inst.operands.b orelse return false];
        if (right.kind == .missing or (right.inst orelse return false).op != .iconst) return false;
        const amount = constant(right);
        const left = self.defs[inst.operands.a orelse return false];
        const field: ?u64 = if (left.kind == .inst and left.inst.?.op == .record_get) left.inst.?.immediates.imm else null;
        const source = if (field != null) self.defs[left.inst.?.operands.a orelse return false] else left;
        if (source.kind != .phi) return false;
        const header = source.block;
        if (!self.dominates(header, here)) return false;
        const preds = self.f.blocks[header].preds;
        if (preds.len == 0) return false;
        for (source.phi.?.edges) |edge| {
            const wanted: Earlier = .{ .op = inst.op, .amount = amount, .base = edge.value, .field = field };
            if (!self.checkedBefore(edge.block, wanted, inst.value)) return false;
        }
        return true;
    }

    /// Whether two values are the same: one value, or two reads of the same field of the same record (a record is a value, so the
    /// reads cannot differ).
    fn sameValue(self: *Checker, x: u32, y: u32) bool {
        if (x == y) return true;
        const left = self.defs[x].inst orelse return false;
        const right = self.defs[y].inst orelse return false;
        if (left.op != .record_get or right.op != .record_get or left.immediates.imm != right.immediates.imm) return false;
        const record_x = left.operands.a orelse return false;
        const record_y = right.operands.a orelse return false;
        return record_x == record_y;
    }

    const Earlier = struct { op: ir.Op, amount: i128, base: u32, field: ?u64 };

    /// Whether block `from`, or a block that dominates it, holds a checked `wanted` other than `except`.
    fn checkedBefore(self: *Checker, from: u32, wanted: Earlier, except: u32) bool {
        var at = from;
        while (true) {
            for (self.f.blocks[at].insts) |earlier| {
                if (earlier.value == except or earlier.op != wanted.op or earlier.ty != .i64 or earlier.check == .none) continue;
                const other = self.defs[earlier.operands.b orelse continue];
                if (other.kind == .missing or (other.inst orelse continue).op != .iconst or constant(other) != wanted.amount) continue;
                const operand_a = earlier.operands.a orelse continue;
                if (wanted.field) |field| {
                    const read = self.defs[operand_a].inst orelse continue;
                    if (read.op == .record_get and read.immediates.imm == field and (read.operands.a orelse continue) == wanted.base) return true;
                } else if (self.sameValue(operand_a, wanted.base)) return true;
            }
            if (at == 0 or self.idom[at] == none or self.idom[at] == at) return false;
            at = self.idom[at];
        }
    }

    fn noCheck(self: *Checker, inst: form.Inst, here: u32, why: []const u8) Fault {
        return self.fail(.f7, here, inst.value, "{s} %{d} is proven but {s}", .{ @tagName(inst.op), inst.value, why });
    }

    fn unchecked(self: *Checker, inst: form.Inst) void {
        const reason: Unchecked = switch (inst.op) {
            .float_to_int => .float,
            else => .other_op,
        };
        self.stats.unchecked[@backingInt(reason)] += 1;
    }

    /// A list access `len` does not justify (design §6 F7): a length bound, a fill length, or a dominating edge or earlier access.
    fn listUnchecked(self: *Checker, inst: form.Inst) void {
        const list = self.liveList(inst.operands.a orelse return self.unchecked(inst));
        const reason: Unchecked = if (self.hasBound(list, inst.operands.b)) .list_bound else if (self.lengthOf(list) != null) .list_fill else .list_keys;
        self.stats.unchecked[@backingInt(reason)] += 1;
    }

    fn hasBound(self: *Checker, list: u32, index: ?u32) bool {
        const v = index orelse return false;
        for (self.f.aux.bounds) |bound| if (bound.value == v and bound.list == list) return true;
        return false;
    }

    fn lengthOf(self: *Checker, list: u32) ?u32 {
        if (list >= self.n) return null;
        const fact = self.lists[list] orelse return null;
        return fact.length;
    }

    /// The value of a constant, read at the type's signedness.
    fn constant(def: Def) i128 {
        const inst = def.inst.?;
        if (def.ty == .bool) return @intFromBool(inst.immediates.imm != 0);
        if (def.ty == .u64) return inst.immediates.imm;
        return @as(i64, @bitCast(inst.immediates.imm));
    }
};

/// The viewed operand intervals of a site, at most two (design §10).
const Parts = struct {
    values: [2]?Interval = .{ null, null },

    fn set(self: *Parts, k: usize, value: ?Interval) void {
        self.values[k] = value;
    }

    fn get(self: Parts, k: usize) ?Interval {
        return self.values[k];
    }
};

/// Whether the interval of this operation's result reads a list or a callee that passes after the facts rewrote (ownership
/// splits writes and copies lists; versioning and inlining move calls), so the final IR can lose what showed it.
pub fn staleAfterFacts(op: ir.Op) bool {
    return switch (op) {
        .list_get, .array_get, .call => true,
        else => false,
    };
}

/// Whether the operation has a row in the table of design §4 (a `proven` form the checker can validate).
pub fn hasRow(op: ir.Op) bool {
    return switch (op) {
        .add, .sub, .mul, .shift_left, .shift_right, .div, .floor_div, .rem, .floor_rem, .neg, .convert, .array_get, .array_set, .list_get, .list_get_field, .list_set, .list_pop => true,
        else => false,
    };
}

/// Whether the row of `inst`'s operation (design §4, last column) rules out its failure for the site `parts`; null for an
/// operation without a row. An interval the site does not state is the widest the row could be asked about, so it never holds.
pub fn rowHolds(inst: form.Inst, stated: []const ?Interval) ?bool {
    var parts: Parts = .{};
    for (stated[0..@min(stated.len, 2)], 0..) |value, k| parts.set(k, value);
    const limits = inst.ty.range() orelse Interval{ .lo = std.math.minInt(i64), .hi = std.math.maxInt(u64) };
    const wide: Interval = .{ .lo = -(@as(i128, 1) << 65), .hi = @as(i128, 1) << 65 };
    const first = parts.get(0) orelse wide;
    const second = parts.get(1) orelse wide;
    return switch (inst.op) {
        .add, .sub, .mul => arithmetic(inst.op, first, second).within(limits) and (limits.lo < 0 or (first.lo >= 0 and second.lo >= 0)),
        .shift_left, .shift_right => first.lo >= 0 and first.hi < inst.ty.bits(),
        .div, .floor_div, .rem, .floor_rem => first.lo >= 0 and second.lo > 0,
        .neg => if (limits.lo == 0) (first.lo == 0 and first.hi == 0) else first.lo > limits.lo,
        .convert => first.within(limits),
        .array_get, .array_set => first.lo >= 0 and first.hi < inst.immediates.aux,
        .list_get, .list_get_field, .list_set => parts.get(1) != null and first.lo >= 0 and first.hi < second.lo,
        .list_pop => parts.get(0) != null and first.lo >= 1,
        else => null,
    };
}

/// The interval a callee sees for an argument of type `from` passed to a parameter of type `to`: the same bits, read at the
/// parameter's signedness (the Core IR passes integers of one width as the same register).
fn reinterpret(range: Interval, from: Type, to: Type) Interval {
    const limits = to.range() orelse return range;
    if (range.within(limits)) return range;
    if (from.bits() != to.bits() or from.signed() == to.signed()) return limits;
    const span: i128 = @as(i128, 1) << @intCast(to.bits());
    if (to.signed()) {
        const half: i128 = span >> 1;
        if (range.lo >= half) return .{ .lo = range.lo - span, .hi = range.hi - span };
    } else if (range.hi < 0) return .{ .lo = range.lo + span, .hi = range.hi + span };
    return limits;
}

/// How many values one reduction may look through before it gives up.
const growth_budget: u32 = 64;

/// `start` after at most `trips` steps, each in `step`.
fn grown(start: Interval, step: Interval, trips: i128) Interval {
    return .{ .lo = start.lo +| @min(0, mulSat(trips, step.lo)), .hi = start.hi +| @max(0, mulSat(trips, step.hi)) };
}

fn arithmetic(op: ir.Op, x: Interval, y: Interval) Interval {
    return switch (op) {
        .add => .{ .lo = x.lo + y.lo, .hi = x.hi + y.hi },
        .sub => .{ .lo = x.lo - y.hi, .hi = x.hi - y.lo },
        else => blk: {
            const p = [4]i128{ mulSat(x.lo, y.lo), mulSat(x.lo, y.hi), mulSat(x.hi, y.lo), mulSat(x.hi, y.hi) };
            break :blk .{ .lo = @min(@min(p[0], p[1]), @min(p[2], p[3])), .hi = @max(@max(p[0], p[1]), @max(p[2], p[3])) };
        },
    };
}

fn mulSat(x: i128, y: i128) i128 {
    return std.math.mul(i128, x, y) catch if ((x < 0) == (y < 0)) std.math.maxInt(i128) else std.math.minInt(i128);
}

const Targets = struct {
    buffer: [2]u32 = .{ 0, 0 },
    len: u8 = 0,

    fn slice(self: *const Targets) []const u32 {
        return self.buffer[0..self.len];
    }
};

fn successors(term: form.Term) Targets {
    return switch (term) {
        .jump => |target| .{ .buffer = .{ target, 0 }, .len = 1 },
        .branch => |branch| .{ .buffer = .{ branch.then, branch.otherwise }, .len = 2 },
        else => .{},
    };
}

const Predicate = enum { eq, ne, lt, le, gt, ge };

fn predicateOf(imm: u64) ?Predicate {
    return std.enums.fromInt(Predicate, imm);
}

fn negate(p: Predicate) Predicate {
    return switch (p) {
        .eq => .ne,
        .ne => .eq,
        .lt => .ge,
        .le => .gt,
        .gt => .le,
        .ge => .lt,
    };
}

fn mirror(p: Predicate) Predicate {
    return switch (p) {
        .lt => .gt,
        .le => .ge,
        .gt => .lt,
        .ge => .le,
        else => p,
    };
}

test "a function that defines a value twice is a fault of shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const twice: form.Inst = .{ .value = 0, .op = .iconst, .ty = .i64, .check = .none };
    const function: form.Function = .{
        .header = .{ .name = "f", .internal = false, .address_taken = false, .params = &.{}, .ret = .i64 },
        .pre = &.{ twice, twice },
    };
    var checker: Checker = .{ .keep = arena.allocator(), .a = arena.allocator(), .module = .{ .functions = &.{function} }, .f = function };
    try std.testing.expectError(error.Fault, checker.prepare());
    try std.testing.expectEqual(Check.f1, checker.fault.?.check);
}

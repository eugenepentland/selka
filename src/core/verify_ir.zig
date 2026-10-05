//! The Core IR verifier (docs/design/new-core-s1.md §2): every block reachable from
//! the entry ends in exactly one terminator with its phis first, every phi has one
//! operand per predecessor, predecessor lists match the terminators, every operand
//! has the type its operation's signature asks for, and every use is dominated by
//! its definition (a phi operand by the end of its predecessor). Debug builds of
//! `mylang-core` run it after construction and after the release passes, and the
//! unit tests run it on every module they build. `verifyPlan` checks that a vector
//! plan reads nothing from inside its loop before the loop runs (the S0 splat bug).
const std = @import("std");
const ir = @import("ir.zig");
const vector = @import("vector.zig");

/// Verification only allocates, or finds the IR malformed.
pub const Error = error{ OutOfMemory, InvalidIr };

/// The first problem found: where, and what.
pub const Failure = struct {
    function: []const u8 = "",
    /// The block, or `none_index` for a function-level problem.
    block: u32 = none_index,
    /// The instruction, or `none_index`.
    inst: u32 = none_index,
    reason: []const u8 = "",

    /// Marks a missing block or instruction position.
    pub const none_index = std.math.maxInt(u32);

    /// One line: `function b3 %7: reason`.
    pub fn render(self: Failure, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.print(allocator, "invalid Core IR in {s}", .{self.function});
        if (self.block != none_index) try out.print(allocator, " b{d}", .{self.block});
        if (self.inst != none_index) try out.print(allocator, " %{d}", .{self.inst});
        try out.print(allocator, ": {s}", .{self.reason});
        return out.toOwnedSlice(allocator);
    }
};

/// Whether `mylang-core` verifies its IR on every build: in debug builds of the compiler.
pub const enabled = @import("builtin").mode == .debug;

/// Verify `module` and, per function, the vector plans the release passes made
/// (`plans` may be empty); a failure is rendered into `report`.
pub fn check(arena: std.mem.Allocator, module: *const ir.Module, plans: []const []const vector.Plan, report: *std.ArrayList(u8)) Error!void {
    var failure: Failure = .{};
    verifyModule(arena, module, &failure) catch |err| return reported(arena, err, failure, report);
    for (plans, module.functions.items[0..plans.len]) |function_plans, *f| {
        for (function_plans) |plan| verifyPlan(arena, module, f, plan, &failure) catch |err| return reported(arena, err, failure, report);
    }
}

fn reported(arena: std.mem.Allocator, err: Error, failure: Failure, report: *std.ArrayList(u8)) Error {
    if (err == error.InvalidIr) try report.print(arena, "internal error[E_CORE_INVALID_IR]: {s}\n", .{try failure.render(arena)});
    return err;
}

/// Verify every internal function of `module`.
pub fn verifyModule(arena: std.mem.Allocator, module: *const ir.Module, failure: *Failure) Error!void {
    for (module.functions.items) |*f| {
        if (f.signature.linkage != .internal) continue;
        try verifyFunction(arena, module, f, failure);
    }
}

/// Verify one function.
pub fn verifyFunction(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, failure: *Failure) Error!void {
    var v: Verifier = .{ .arena = arena, .module = module, .f = f, .failure = failure };
    failure.* = .{ .function = f.name };
    try v.run();
}

/// Verify that `plan`'s vector part, emitted on the edge from its preheader, reads
/// only values that exist there: every operand of a lane instruction that is not
/// itself a lane value, every select arm, and the loop's start, bound and initial
/// sum must be constants or dominate the preheader.
pub fn verifyPlan(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, plan: vector.Plan, failure: *Failure) Error!void {
    var v: Verifier = .{ .arena = arena, .module = module, .f = f, .failure = failure };
    failure.* = .{ .function = f.name };
    try v.structure();
    const carried = plan.carried;
    for ([_]ir.Ref{ carried.start, carried.bound, carried.acc_init }) |value| try v.beforeLoop(plan, value);
    for (plan.body) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .phi) continue;
        // A lane read indexes by the vector counter; only its list comes from outside.
        if (inst.op == .list_get) {
            try v.beforeLoop(plan, inst.a);
            continue;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| {
            if (std.mem.indexOfScalar(ir.Ref, plan.body, f.resolve(operands.get(i))) != null) continue;
            try v.beforeLoop(plan, operands.get(i));
        }
    }
    for (plan.selects) |select| {
        for ([_]ir.Ref{ select.condition, select.then_value, select.else_value }) |value| {
            if (std.mem.indexOfScalar(ir.Ref, plan.body, f.resolve(value)) != null) continue;
            try v.beforeLoop(plan, value);
        }
    }
}

/// One instruction with its operand types resolved, for the signature checks.
const Shape = struct { inst: ir.Inst, extra: []const ir.Ref, a: ir.Type, b: ir.Type };

/// Where an instruction sits.
const Position = struct { block: u32, index: u32 };

/// The control-flow facts the checks need.
const Graph = struct {
    reachable: []bool = &.{},
    /// Immediate dominators of reachable blocks (the entry's is itself).
    idom: []u32 = &.{},
    /// Reverse-postorder number of each reachable block.
    order: []u32 = &.{},
};

const Verifier = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    failure: *Failure,
    graph: Graph = .{},
    /// Where each instruction listed in a reachable block sits.
    position: []?Position = &.{},

    fn fail(self: *Verifier, block: ?usize, inst: ?ir.Ref, comptime format: []const u8, args: anytype) Error {
        self.failure.block = if (block) |b| @intCast(b) else Failure.none_index;
        self.failure.inst = if (inst) |i| @intCast(i.index()) else Failure.none_index;
        self.failure.reason = try std.fmt.allocPrint(self.arena, format, args);
        return error.InvalidIr;
    }

    fn run(self: *Verifier) Error!void {
        try self.structure();
        for (self.f.blocks.items, 0..) |block, b| {
            if (!self.graph.reachable[b]) continue;
            for (block.insts.items, 0..) |ref, at| {
                const inst = self.f.inst(ref);
                if (inst.op == .copy) continue;
                try self.signature(b, ref, inst);
                try self.dominance(b, @intCast(at), ref, inst);
            }
        }
    }

    // ---- structure ------------------------------------------------------------------

    /// Blocks, terminators, predecessor lists and phi arity; then reachability and dominators.
    fn structure(self: *Verifier) Error!void {
        const f = self.f;
        if (f.blocks.items.len == 0) return self.fail(null, null, "a function with a body has no blocks", .{});
        for (f.signature.params) |param| if (!self.module.valid(param)) return self.fail(null, null, "parameter type is not interned", .{});
        try self.reach();
        self.position = try self.arena.alloc(?Position, f.insts.items.len);
        @memset(self.position, null);
        for (f.blocks.items, 0..) |block, b| {
            if (!self.graph.reachable[b]) continue;
            const insts = block.insts.items;
            if (insts.len == 0) return self.fail(b, null, "empty block", .{});
            var phis_done = false;
            for (insts, 0..) |ref, at| {
                if (ref == .none or ref.index() >= f.insts.items.len) return self.fail(b, null, "block lists an instruction that does not exist", .{});
                if (self.position[ref.index()] != null) return self.fail(b, ref, "instruction listed in two places", .{});
                self.position[ref.index()] = .{ .block = @intCast(b), .index = @intCast(at) };
                const inst = f.inst(ref);
                const last = at + 1 == insts.len;
                if (inst.op.terminates() != last) return self.fail(b, ref, "{s}", .{if (last) "block does not end in a terminator" else "terminator before the end of its block"});
                if (inst.op == .copy) continue;
                if (inst.op == .phi) {
                    if (phis_done) return self.fail(b, ref, "phi after a non-phi instruction", .{});
                    const arity = ir.ExtraSlice.unpack(inst.data).len;
                    if (arity != block.preds.items.len) return self.fail(b, ref, "phi has {d} operands for {d} predecessors", .{ arity, block.preds.items.len });
                } else phis_done = true;
            }
            try self.edges(b);
        }
        try self.dominators();
    }

    fn successors(self: *Verifier, b: usize) [2]?u32 {
        const insts = self.f.blocks.items[b].insts.items;
        if (insts.len == 0) return .{ null, null };
        const last = self.f.inst(insts[insts.len - 1]);
        return switch (last.op) {
            .jump => .{ @truncate(last.data), null },
            .branch => blk: {
                const targets = ir.unpackTargets(last.data);
                break :blk .{ @backingInt(targets.then), @backingInt(targets.otherwise) };
            },
            else => .{ null, null },
        };
    }

    fn reach(self: *Verifier) Error!void {
        const count = self.f.blocks.items.len;
        self.graph.reachable = try self.arena.alloc(bool, count);
        @memset(self.graph.reachable, false);
        var stack: std.ArrayList(u32) = .empty;
        self.graph.reachable[0] = true;
        try stack.append(self.arena, 0);
        while (stack.pop()) |b| {
            for (self.successors(b)) |maybe| {
                const s = maybe orelse continue;
                if (s >= count) return self.fail(b, null, "branch to block b{d}, which does not exist", .{s});
                if (self.graph.reachable[s]) continue;
                self.graph.reachable[s] = true;
                try stack.append(self.arena, s);
            }
        }
    }

    /// Each edge `b -> s` appears in `s`'s predecessors as often as `b` targets `s`,
    /// and every predecessor of a reachable block targets it.
    fn edges(self: *Verifier, b: usize) Error!void {
        const out = self.successors(b);
        for (out, 0..) |maybe, i| {
            const s = maybe orelse continue;
            const both = out[0] != null and out[1] != null and out[0].? == out[1].?;
            if (i == 1 and both) continue;
            const wanted: usize = if (both) 2 else 1;
            const listed = std.mem.count(ir.BlockId, self.f.blocks.items[s].preds.items, &.{@fromBackingInt(@intCast(b))});
            if (listed != wanted) return self.fail(b, null, "edge to b{d} appears {d} times in its predecessors", .{ s, listed });
        }
        for (self.f.blocks.items[b].preds.items) |pred| {
            if (pred.index() >= self.f.blocks.items.len) return self.fail(b, null, "predecessor b{d} does not exist", .{pred.index()});
            if (!self.graph.reachable[pred.index()]) continue;
            const targets = self.successors(pred.index());
            const here: u32 = @intCast(b);
            if (targets[0] != here and targets[1] != here) return self.fail(b, null, "predecessor b{d} does not branch here", .{pred.index()});
        }
    }

    /// Cooper, Harvey and Kennedy's iterative dominators over reachable blocks.
    fn dominators(self: *Verifier) Error!void {
        const count = self.f.blocks.items.len;
        const undefined_order = std.math.maxInt(u32);
        self.graph.order = try self.arena.alloc(u32, count);
        @memset(self.graph.order, undefined_order);
        // Postorder by an explicit DFS.
        var post: std.ArrayList(u32) = .empty;
        const visited = try self.arena.alloc(bool, count);
        @memset(visited, false);
        var stack: std.ArrayList(struct { block: u32, next: u8 }) = .empty;
        try stack.append(self.arena, .{ .block = 0, .next = 0 });
        visited[0] = true;
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const out = self.successors(top.block);
            if (top.next < 2) {
                const which = top.next;
                top.next += 1;
                const s = out[which] orelse continue;
                if (visited[s]) continue;
                visited[s] = true;
                try stack.append(self.arena, .{ .block = s, .next = 0 });
                continue;
            }
            try post.append(self.arena, top.block);
            _ = stack.pop();
        }
        const rpo = post.items;
        std.mem.reverse(u32, rpo);
        for (rpo, 0..) |b, i| self.graph.order[b] = @intCast(i);
        self.graph.idom = try self.arena.alloc(u32, count);
        @memset(self.graph.idom, undefined_order);
        self.graph.idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            for (rpo[1..]) |b| {
                var chosen: u32 = undefined_order;
                for (self.f.blocks.items[b].preds.items) |pred_id| {
                    const pred: u32 = @intCast(pred_id.index());
                    if (!self.graph.reachable[pred] or self.graph.idom[pred] == undefined_order) continue;
                    chosen = if (chosen == undefined_order) pred else self.intersect(pred, chosen);
                }
                if (chosen != self.graph.idom[b]) {
                    self.graph.idom[b] = chosen;
                    changed = true;
                }
            }
        }
    }

    fn intersect(self: *Verifier, x: u32, y: u32) u32 {
        var a = x;
        var b = y;
        while (a != b) {
            while (self.graph.order[a] > self.graph.order[b]) a = self.graph.idom[a];
            while (self.graph.order[b] > self.graph.order[a]) b = self.graph.idom[b];
        }
        return a;
    }

    /// Whether block `a` dominates block `b` (both reachable).
    fn dominatesBlock(self: *Verifier, a: u32, b: u32) bool {
        var x = b;
        while (true) {
            if (x == a) return true;
            if (x == 0) return false;
            x = self.graph.idom[x];
        }
    }

    // ---- dominance --------------------------------------------------------------------

    fn dominance(self: *Verifier, b: usize, at: u32, ref: ir.Ref, inst: ir.Inst) Error!void {
        const f = self.f;
        if (inst.op == .phi) {
            for (f.operands(inst.data), f.blocks.items[b].preds.items) |operand, pred| {
                if (!self.graph.reachable[pred.index()]) continue;
                // A phi operand is read at the end of its predecessor.
                const end: u32 = @intCast(f.blocks.items[pred.index()].insts.items.len);
                try self.available(b, ref, operand, .{ .block = @intCast(pred.index()), .index = end });
            }
            return;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| try self.available(b, ref, operands.get(i), .{ .block = @intCast(b), .index = at });
    }

    /// Whether `operand` is defined before `use` on every path from the entry.
    fn available(self: *Verifier, b: usize, user: ir.Ref, raw: ir.Ref, use: Position) Error!void {
        if (raw == .none) return self.fail(b, user, "missing operand", .{});
        if (raw.index() >= self.f.insts.items.len) return self.fail(b, user, "operand %{d} does not exist", .{raw.index()});
        const operand = self.f.resolve(raw);
        if (operand == .none) return self.fail(b, user, "operand %{d} forwards to nothing", .{raw.index()});
        if (self.f.inst(operand).op.isConstant()) return;
        const def = self.position[operand.index()] orelse return self.fail(b, user, "operand %{d} is not defined in a reachable block", .{operand.index()});
        if (def.block == use.block) {
            if (def.index < use.index) return;
            return self.fail(b, user, "operand %{d} is used before its definition", .{operand.index()});
        }
        if (!self.dominatesBlock(def.block, use.block)) return self.fail(b, user, "operand %{d} (b{d}) does not dominate its use in b{d}", .{ operand.index(), def.block, use.block });
    }

    /// A vector plan's outside value must exist on the preheader's edge.
    fn beforeLoop(self: *Verifier, plan: vector.Plan, raw: ir.Ref) Error!void {
        const pre: u32 = @intCast(plan.preheader.index());
        const end: u32 = @intCast(self.f.blocks.items[pre].insts.items.len);
        if (!self.graph.reachable[pre]) return self.fail(pre, null, "vector plan preheader is unreachable", .{});
        try self.available(pre, raw, raw, .{ .block = pre, .index = end });
    }

    // ---- types ------------------------------------------------------------------------

    fn typeOf(self: *Verifier, raw: ir.Ref) ir.Type {
        return self.f.inst(self.f.resolve(raw)).ty;
    }

    fn isInteger(ty: ir.Type) bool {
        return ty.integer() != null;
    }

    /// The compound structure of `ty` when it is of kind `k`.
    fn compoundOf(self: *Verifier, ty: ir.Type, comptime k: std.meta.Tag(ir.Compound)) ?@FieldType(ir.Compound, @tagName(k)) {
        if (self.module.kind(ty) != k) return null;
        return @field(self.module.compound(ty), @tagName(k));
    }

    fn signature(self: *Verifier, b: usize, ref: ir.Ref, inst: ir.Inst) Error!void {
        const f = self.f;
        if (!self.module.valid(inst.ty)) return self.fail(b, ref, "result type is not interned", .{});
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| {
            const operand = operands.get(i);
            if (operand == .none or operand.index() >= f.insts.items.len) return self.fail(b, ref, "missing or out-of-range operand", .{});
        }
        const shape: Shape = .{
            .inst = inst,
            .extra = operands.extra,
            .a = if (inst.a != .none and inst.op != .call) self.typeOf(inst.a) else .void,
            .b = if (inst.b != .none) self.typeOf(inst.b) else .void,
        };
        const ok = self.scalarSignature(shape) orelse self.aggregateSignature(shape) orelse self.controlSignature(shape);
        if (!ok) return self.fail(b, ref, "{s} does not match its signature", .{@tagName(inst.op)});
    }

    /// Constants, arithmetic, comparisons and conversions; null for any other operation.
    fn scalarSignature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .param, .fconst, .undef, .str_const, .copy => true,
            .iconst => isInteger(inst.ty) or inst.ty == .bool,
            .phi => for (self.f.operands(inst.data)) |operand| {
                if (self.typeOf(operand) != inst.ty) break false;
            } else true,
            .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem => isInteger(inst.ty) and s.a == inst.ty and s.b == inst.ty,
            .neg => isInteger(inst.ty) and s.a == inst.ty,
            .bit_and, .bit_or, .bit_xor => (isInteger(inst.ty) or inst.ty == .bool) and s.a == inst.ty and s.b == inst.ty,
            .not => inst.ty == .bool and s.a == .bool,
            .cmp => inst.ty == .bool and s.a == s.b and (isInteger(s.a) or s.a == .bool) and inst.data < 6,
            .fadd, .fsub, .fmul, .fdiv => inst.ty == .f64 and s.a == .f64 and s.b == .f64,
            .fneg => inst.ty == .f64 and s.a == .f64,
            .fcmp => inst.ty == .bool and s.a == .f64 and s.b == .f64 and inst.data < 6,
            .int_to_float => inst.ty == .f64 and isInteger(s.a),
            .float_to_int => isInteger(inst.ty) and s.a == .f64,
            .convert => isInteger(inst.ty) and isInteger(s.a),
            .str_len => isInteger(inst.ty) and s.a == .str,
            .str_parse_int => s.a == .str and self.compoundOf(inst.ty, .@"union") != null,
            else => null,
        };
    }

    /// Lists, records, unions, boxes and counting; null for any other operation.
    fn aggregateSignature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .list_new => self.compoundOf(inst.ty, .list) != null and isInteger(s.a),
            .list_len => isInteger(inst.ty) and self.compoundOf(s.a, .list) != null,
            .list_get => if (self.compoundOf(s.a, .list)) |element| element == inst.ty and isInteger(s.b) else false,
            .list_push => if (self.compoundOf(s.a, .list)) |element| inst.ty == s.a and s.b == element else false,
            .list_copy, .list_pop => self.compoundOf(s.a, .list) != null and inst.ty == s.a,
            .list_set => if (self.compoundOf(s.a, .list)) |element| inst.ty == s.a and isInteger(s.b) and s.extra.len == 1 and self.typeOf(s.extra[0]) == element else false,
            .list_get_field => self.fieldSignature(s),
            .union_make, .union_tag, .union_payload => self.unionSignature(s),
            .record_make => if (self.compoundOf(inst.ty, .record)) |fields| self.typesMatch(s.extra, fields) else false,
            .record_get => if (self.compoundOf(s.a, .record)) |fields| inst.data < fields.len and fields[@intCast(inst.data)] == inst.ty else false,
            .record_set => if (self.compoundOf(s.a, .record)) |fields| inst.ty == s.a and inst.data < fields.len and fields[@intCast(inst.data)] == s.b else false,
            .box_make => if (self.compoundOf(inst.ty, .box)) |inner| s.a == inner else false,
            .box_get => if (self.compoundOf(s.a, .box)) |inner| inner == inst.ty else false,
            .retain, .release => inst.ty == .void and self.module.managed(s.a),
            .is_unique => inst.ty == .bool and self.module.isBlock(s.a),
            // Mode 3 (`converted`) names the case in a `str` operand; the others take none.
            .err_trace => inst.ty == .void and inst.data <= 4 and if (inst.data == 3) inst.a != .none and s.a == .str else inst.a == .none,
            else => null,
        };
    }

    /// Calls, printing and terminators.
    fn controlSignature(self: *Verifier, s: Shape) bool {
        const inst = s.inst;
        const m = self.module;
        return switch (inst.op) {
            .call => blk: {
                if (inst.a == .none or inst.a.index() >= m.functions.items.len) break :blk false;
                const callee = m.functions.items[inst.a.index()].signature;
                break :blk inst.ty == callee.ret and self.typesMatch(s.extra, callee.params);
            },
            .print => inst.ty == .void and s.extra.len != 0 and self.typeOf(s.extra[0]) == .cap,
            .jump => inst.data < self.f.blocks.items.len,
            .branch => s.a == .bool,
            .ret => if (self.f.signature.ret == .void) inst.a == .none else inst.a != .none and s.a == self.f.signature.ret,
            .@"unreachable" => true,
            else => false,
        };
    }

    /// Whether `values` have exactly the types `types`, in order.
    fn typesMatch(self: *Verifier, values: []const ir.Ref, types: []const ir.Type) bool {
        if (values.len != types.len) return false;
        for (values, types) |value, ty| if (self.typeOf(value) != ty) return false;
        return true;
    }

    fn fieldSignature(self: *Verifier, s: Shape) bool {
        const element = self.compoundOf(s.a, .list) orelse return false;
        const path = ir.FieldPath.unpack(s.inst.data);
        if (path.len == 0) return false;
        const target = self.module.pathTarget(element, path) orelse return false;
        return isInteger(s.b) and target.ty == s.inst.ty;
    }

    fn unionSignature(self: *Verifier, s: Shape) bool {
        const inst = s.inst;
        if (inst.op == .union_tag) return inst.ty == .u32 and self.compoundOf(s.a, .@"union") != null;
        const union_type = if (inst.op == .union_make) inst.ty else s.a;
        const cases = self.compoundOf(union_type, .@"union") orelse return false;
        if (inst.data >= cases.len) return false;
        const payload = cases[@intCast(inst.data)];
        if (inst.op == .union_payload) return payload != .void and payload == inst.ty;
        return if (payload == .void) inst.a == .none else inst.a != .none and s.a == payload;
    }
};

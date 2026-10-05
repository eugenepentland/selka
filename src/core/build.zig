//! Build Core IR from the checked tree (docs/design/new-core-ir.md §3).
//!
//! SSA comes from the on-the-fly construction of Braun et al. (2013): each
//! checked local is a variable, `read`/`write` look definitions up per block,
//! phis appear on demand and are completed when a block is sealed, and a
//! trivial phi becomes a forwarding `copy`. The checked tree is structured, so
//! a block is sealed as soon as the walk has created all its predecessors.
//! Only functions reachable from `main` are built; a node the builder does not
//! support stops the build with `error.Unsupported` and a `Refusal`.
const std = @import("std");
const typed = @import("mylang").typed;
const ir = @import("ir.zig");

/// Why building stopped.
pub const Error = error{ OutOfMemory, Unsupported };

/// The first unsupported construct: a short reason and its source offset.
pub const Refusal = struct { reason: []const u8 = "", span: u32 = 0 };

/// Build the module for `program`, reachable from its `main`. On
/// `error.Unsupported`, `refusal` names the construct.
pub fn buildModule(allocator: std.mem.Allocator, program: typed.Program, refusal: *Refusal) Error!ir.Module {
    return buildRoots(allocator, program, &.{program.main}, refusal);
}

/// Build the module reachable from several `roots` (the test runner's one executable
/// holds every test of a file). The roots take the first function indices in order
/// and `entry` is the first one; the caller replaces `entry` with its own dispatcher.
pub fn buildRoots(allocator: std.mem.Allocator, program: typed.Program, roots: []const typed.FunctionId, refusal: *Refusal) Error!ir.Module {
    var mb: ModuleBuilder = .{ .allocator = allocator, .program = program, .refusal = refusal };
    defer mb.ids.deinit(allocator);
    for (roots, 0..) |root, position| {
        const index = try mb.functionIndex(root);
        if (position == 0) mb.module.entry = index;
    }
    var next: usize = 0;
    while (next < mb.pending.items.len) : (next += 1) {
        const id = mb.pending.items[next];
        const index = mb.ids.get(@backingInt(id)).?;
        const function = program.functions[@backingInt(id)];
        if (mb.module.functions.items[index].signature.linkage == .internal) {
            // Building may declare callees and grow the table, so store afterwards.
            const built = try buildFunction(&mb, function, mb.module.functions.items[index]);
            mb.module.functions.items[index] = built;
        }
    }
    mb.pending.deinit(allocator);
    // Ownership (copies before shared updates, counting) is `own.zig`'s, after the release passes.
    return mb.module;
}

/// How one checked function fared: built (its Core IR), or the reason it was refused.
pub const Outcome = struct {
    name: []const u8,
    refusal: ?[]const u8,
    function: ?ir.Function = null,
    /// The types the built function uses (its own module's interned compounds).
    module: ?ir.Module = null,
};

/// Try to build every function of `program` on its own (the coverage sweep).
pub fn coverage(allocator: std.mem.Allocator, program: typed.Program) Error![]Outcome {
    const outcomes = try allocator.alloc(Outcome, program.functions.len);
    for (program.functions, outcomes) |function, *outcome| {
        outcome.* = .{ .name = function.name, .refusal = null };
        if (function.policy.c_abi or function.policy.host != null) {
            outcome.refusal = if (function.policy.c_abi) "extern" else "host function";
            continue;
        }
        var refusal: Refusal = .{};
        var mb: ModuleBuilder = .{ .allocator = allocator, .program = program, .refusal = &refusal };
        const index = mb.functionIndex(function.id) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => {
                outcome.refusal = refusal.reason;
                continue;
            },
        };
        outcome.function = buildFunction(&mb, function, mb.module.functions.items[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => blk: {
                outcome.refusal = refusal.reason;
                break :blk null;
            },
        };
        outcome.module = mb.module;
    }
    return outcomes;
}

const ModuleBuilder = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    refusal: *Refusal,
    module: ir.Module = .{},
    /// Checked function id → IR function index.
    ids: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    pending: std.ArrayList(typed.FunctionId) = .empty,

    fn refuse(self: *ModuleBuilder, reason: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span };
        return error.Unsupported;
    }

    /// The IR index of a checked function, declaring it on first use.
    fn functionIndex(self: *ModuleBuilder, id: typed.FunctionId) Error!u32 {
        if (self.ids.get(@backingInt(id))) |index| return index;
        const function = self.program.functions[@backingInt(id)];
        const params = try self.allocator.alloc(ir.Type, function.signature.parameter_count);
        for (params, function.scope.locals[0..params.len]) |*param, local| param.* = try self.mapType(local.ty, @intCast(local.declaration.start));
        const span: u32 = @intCast(function.declaration.start);
        // A `mut` parameter writes through to the caller's place; that is S1 (ownership).
        if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return self.refuse("mut parameter", span);
        const linkage: ir.Linkage = if (function.policy.c_abi) .extern_c else if (function.policy.host != null) return self.refuse("host function", span) else .internal;
        const ret = try self.mapType(function.signature.return_type, span);
        const index: u32 = @intCast(self.module.functions.items.len);
        try self.module.functions.append(self.allocator, .{ .name = function.name, .signature = .{ .params = params, .ret = ret, .linkage = linkage }, .span = span });
        try self.ids.put(self.allocator, @backingInt(id), index);
        try self.pending.append(self.allocator, id);
        return index;
    }

    /// The Core IR type of a checked type, or a refusal.
    fn mapType(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        return switch (ty) {
            .i64 => .i64,
            .bool => .bool,
            .i8 => .i8,
            .i16 => .i16,
            .i32 => .i32,
            .u8 => .u8,
            .u16 => .u16,
            .u32 => .u32,
            .u64 => .u64,
            .unit => .void,
            .host_cap, .stream_cap => .cap,
            else => self.mapAggregate(ty, span),
        };
    }

    fn mapAggregate(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        const records = self.program.records;
        if (!ty.isAggregate()) return self.refuse(if (ty.isFile()) "file handle type" else "capability type", span);
        if (ty.recordIndex() >= records.len) return self.refuse("type", span);
        const record = records[ty.recordIndex()];
        if (record.isCollection()) switch (record.collection.kind) {
            .string => return .str,
            .list => {
                const element = try self.mapType(record.shape.buffer.?, span);
                if (element == .void or element == .cap) return self.refuse("list element type", span);
                return self.module.intern(self.allocator, .{ .list = element });
            },
            .dictionary => return self.refuse(if (record.collection.set) "set type" else "dict type", span),
            .bytes => return self.refuse("bytes type", span),
        };
        if (record.shape.domain != null and std.mem.eql(u8, record.name, "float")) return .f64;
        if (record.shape.variants) |variants| {
            const option = variants.is_union and !variants.fallible and variants.cases.len == 2 and
                variants.cases[0].payload == null and variants.cases[1].payload != null and
                std.mem.startsWith(u8, record.name, "Option");
            if (option) return self.module.option(self.allocator, try self.mapType(variants.cases[1].payload.?, span));
            if (variants.fallible) return self.refuse("Result type", span);
            if (!variants.is_union) return self.refuse("enum type", span);
            return self.refuse(if (std.mem.startsWith(u8, record.name, "Option")) "Option of an aggregate" else "union type", span);
        }
        if (record.contract.callback != null) return self.refuse("function value type", span);
        if (record.shape.array != null) return self.refuse("fixed array type", span);
        if (record.shape.resource != null) return self.refuse("resource type", span);
        if (record.shape.domain != null) return self.refuse("domain type", span);
        if (record.isManagedRecord()) return self.refuse("class type", span);
        return self.refuse("record type", span);
    }
};

/// Per-block definitions, incomplete phis and sealed flags of the SSA construction.
const Ssa = struct {
    /// (block << 32 | variable) → value.
    defs: std.AutoHashMapUnmanaged(u64, ir.Ref) = .empty,
    /// Phis created in an unsealed block, with the variable each one joins.
    incomplete: std.AutoHashMapUnmanaged(u32, std.ArrayList(struct { variable: u32, phi: ir.Ref })) = .empty,
    sealed: std.ArrayList(bool) = .empty,
    /// The IR type of each variable: checked locals first, then synthetic joins.
    types: std.ArrayList(ir.Type) = .empty,
};

/// Where `break` and `continue` of one checked loop go.
const LoopTargets = struct { id: usize, latch: ir.BlockId, exit: ir.BlockId };

/// A checker-hidden local that names a list or string place (`root`) while a
/// loop iterates it or an index reads it.
const Alias = struct { hidden: u32, root: u32 };

const FnBuilder = struct {
    mb: *ModuleBuilder,
    function: ir.Function,
    /// The block instructions are appended to; null after a terminator.
    current: ?ir.BlockId = null,
    ssa: Ssa = .{},
    loops: std.ArrayList(LoopTargets) = .empty,
    checked: typed.Function,
    /// Active aliases, innermost last; a block statement drops the ones it opened.
    aliases: std.ArrayList(Alias) = .empty,

    fn allocator(self: *FnBuilder) std.mem.Allocator {
        return self.mb.allocator;
    }

    fn nodeOf(self: *FnBuilder, id: typed.NodeId) typed.Node {
        return self.mb.program.nodes[@backingInt(id)];
    }

    fn statementOf(self: *FnBuilder, id: typed.StatementId) typed.Statement {
        return self.mb.program.statements[@backingInt(id)];
    }

    // ---- instructions and blocks -------------------------------------------------

    fn newBlock(self: *FnBuilder) Error!ir.BlockId {
        const id: ir.BlockId = @fromBackingInt(@intCast(self.function.blocks.items.len));
        try self.function.blocks.append(self.allocator(), .{});
        try self.ssa.sealed.append(self.allocator(), false);
        return id;
    }

    /// Add an instruction that belongs to no block (constants, parameters, undef).
    fn detached(self: *FnBuilder, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.allocator(), inst);
        return ref;
    }

    /// Append an instruction to the current block.
    fn emit(self: *FnBuilder, inst: ir.Inst) Error!ir.Ref {
        const block = self.current orelse return self.mb.refuse("unreachable code", inst.span);
        const ref = try self.detached(inst);
        try self.function.blocks.items[block.index()].insts.append(self.allocator(), ref);
        return ref;
    }

    fn constant(self: *FnBuilder, ty: ir.Type, value: i128) Error!ir.Ref {
        const bits: u64 = @bitCast(@as(i64, @truncate(value)));
        return self.detached(.{ .op = .iconst, .ty = ty, .data = bits });
    }

    fn extraSlice(self: *FnBuilder, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.allocator(), refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }

    fn addPred(self: *FnBuilder, block: ir.BlockId, pred: ir.BlockId) Error!void {
        try self.function.blocks.items[block.index()].preds.append(self.allocator(), pred);
    }

    fn jump(self: *FnBuilder, target: ir.BlockId) Error!void {
        const from = self.current orelse return;
        _ = try self.emit(.{ .op = .jump, .ty = .void, .data = @backingInt(target) });
        try self.addPred(target, from);
        self.current = null;
    }

    fn branch(self: *FnBuilder, condition: ir.Ref, then: ir.BlockId, otherwise: ir.BlockId, span: u32) Error!void {
        const from = self.current orelse return;
        _ = try self.emit(.{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(then, otherwise), .span = span });
        try self.addPred(then, from);
        try self.addPred(otherwise, from);
        self.current = null;
    }

    fn hasPreds(self: *FnBuilder, block: ir.BlockId) bool {
        return self.function.blocks.items[block.index()].preds.items.len != 0;
    }

    /// Continue in `block` if anything reaches it.
    fn enter(self: *FnBuilder, block: ir.BlockId) void {
        self.current = if (self.hasPreds(block)) block else null;
    }

    // ---- SSA construction (Braun et al.) ----------------------------------------

    fn key(block: ir.BlockId, variable: u32) u64 {
        return (@as(u64, @backingInt(block)) << 32) | variable;
    }

    fn write(self: *FnBuilder, variable: u32, block: ir.BlockId, value: ir.Ref) Error!void {
        try self.ssa.defs.put(self.allocator(), key(block, variable), value);
    }

    fn read(self: *FnBuilder, variable: u32, block: ir.BlockId) Error!ir.Ref {
        if (self.ssa.defs.get(key(block, variable))) |value| return self.function.resolve(value);
        return self.readRecursive(variable, block);
    }

    fn readRecursive(self: *FnBuilder, variable: u32, block: ir.BlockId) Error!ir.Ref {
        const preds = self.function.blocks.items[block.index()].preds.items;
        var value: ir.Ref = undefined;
        if (!self.ssa.sealed.items[block.index()]) {
            value = try self.newPhi(block, variable);
            const entry = try self.ssa.incomplete.getOrPut(self.allocator(), @backingInt(block));
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(self.allocator(), .{ .variable = variable, .phi = value });
        } else if (preds.len == 0) {
            value = try self.detached(.{ .op = .undef, .ty = self.ssa.types.items[variable] });
        } else if (preds.len == 1) {
            value = try self.read(variable, preds[0]);
        } else {
            value = try self.newPhi(block, variable);
            try self.write(variable, block, value);
            value = try self.completePhi(variable, value, block);
        }
        try self.write(variable, block, value);
        return value;
    }

    fn newPhi(self: *FnBuilder, block: ir.BlockId, variable: u32) Error!ir.Ref {
        const ref = try self.detached(.{ .op = .phi, .ty = self.ssa.types.items[variable] });
        const list = &self.function.blocks.items[block.index()].insts;
        var at: usize = 0;
        while (at < list.items.len and self.function.insts.items[list.items[at].index()].op == .phi) at += 1;
        try list.insert(self.allocator(), at, ref);
        return ref;
    }

    fn completePhi(self: *FnBuilder, variable: u32, phi: ir.Ref, block: ir.BlockId) Error!ir.Ref {
        var operands: std.ArrayList(ir.Ref) = .empty;
        defer operands.deinit(self.allocator());
        const count = self.function.blocks.items[block.index()].preds.items.len;
        for (0..count) |i| {
            const pred = self.function.blocks.items[block.index()].preds.items[i];
            try operands.append(self.allocator(), try self.read(variable, pred));
        }
        self.function.insts.items[phi.index()].data = try self.extraSlice(operands.items);
        return self.removeTrivial(phi);
    }

    fn removeTrivial(self: *FnBuilder, phi: ir.Ref) Error!ir.Ref {
        var same: ir.Ref = .none;
        for (self.function.operands(self.function.insts.items[phi.index()].data)) |raw| {
            const operand = self.function.resolve(raw);
            if (operand == same or operand == phi) continue;
            if (same != .none) return phi;
            same = operand;
        }
        if (same == .none) same = try self.detached(.{ .op = .undef, .ty = self.function.insts.items[phi.index()].ty });
        self.function.insts.items[phi.index()].op = .copy;
        self.function.insts.items[phi.index()].a = same;
        return same;
    }

    fn seal(self: *FnBuilder, block: ir.BlockId) Error!void {
        if (self.ssa.incomplete.fetchRemove(@backingInt(block))) |entry| {
            var pending = entry.value;
            defer pending.deinit(self.allocator());
            for (pending.items) |item| _ = try self.completePhi(item.variable, item.phi, block);
        }
        self.ssa.sealed.items[block.index()] = true;
    }

    fn local(self: *FnBuilder, slot: typed.LocalId) u32 {
        _ = self;
        return @intCast(@backingInt(slot));
    }

    /// A fresh variable for a value joined across control flow (short-circuit operators).
    fn synthetic(self: *FnBuilder, ty: ir.Type) Error!u32 {
        try self.ssa.types.append(self.allocator(), ty);
        return @intCast(self.ssa.types.items.len - 1);
    }

    // ---- live places (D1) -----------------------------------------------------------

    /// Record `hidden = root` when the checker binds a hidden local to a list or string place.
    fn noteAlias(self: *FnBuilder, slot: typed.LocalId, value: typed.NodeId) Error!void {
        const name = self.checked.scope.locals[@backingInt(slot)].name;
        if (name.len == 0 or name[0] != '<') return;
        const root = switch (self.nodeOf(value).data) {
            .local => |source| self.local(source),
            else => return,
        };
        const ty = self.ssa.types.items[root];
        if (ty != .str and !(ty.isCompound() and self.mb.module.compound(ty) == .list)) return;
        try self.aliases.append(self.allocator(), .{ .hidden = self.local(slot), .root = root });
    }

    /// D1 (live-place iteration): a loop over a place sees the body's writes to it.
    /// The Core IR reads the alias, which equals the place only while nothing
    /// writes the place, so S0 refuses such a write instead of iterating a snapshot.
    fn guardPlace(self: *FnBuilder, variable: u32, span: u32) Error!void {
        for (self.aliases.items) |alias| {
            if (alias.root == variable or alias.hidden == variable) return self.mb.refuse("write to a list while it is iterated (live-place iteration)", span);
        }
    }

    // ---- statements ---------------------------------------------------------------

    fn statement(self: *FnBuilder, id: typed.StatementId) Error!void {
        if (self.current == null) return;
        const s = self.statementOf(id);
        const span: u32 = @intCast(s.span.start);
        switch (s.data) {
            .block => |items| {
                const open = self.aliases.items.len;
                for (items) |item| try self.statement(item);
                self.aliases.shrinkRetainingCapacity(@min(open, self.aliases.items.len));
            },
            .initialize, .assign => |store| {
                if (store.element) return self.mb.refuse("element store", span);
                try self.guardPlace(self.local(store.slot), span);
                const value = try self.expression(store.value);
                const block = self.current orelse return;
                try self.write(self.local(store.slot), block, value);
                try self.noteAlias(store.slot, store.value);
            },
            .discard => |value| _ = try self.expression(value),
            .ret => |value| {
                const result = try self.expression(value);
                if (self.current == null) return;
                _ = try self.emit(.{ .op = .ret, .ty = .void, .a = if (self.function.signature.ret == .void) .none else result, .span = span });
                self.current = null;
            },
            .branch => |b| try self.branchStatement(b.condition, b.then_body, b.else_body),
            .loop => |loop| try self.loopStatement(loop.id, loop.condition, loop.body, loop.step),
            .loop_exit => |exit| {
                for (self.loops.items) |targets| if (targets.id == exit.target) {
                    if (exit.arenas.len != 0) return self.mb.refuse("arena loop exit", span);
                    return self.jump(if (exit.continuing) targets.latch else targets.exit);
                };
                return self.mb.refuse("loop exit target", span);
            },
            .match => |m| try self.matchStatement(m.value, m.arms, span),
            .assertion => return self.mb.refuse("assertion", span),
            .with_scope => return self.mb.refuse("with scope", span),
        }
    }

    fn branchStatement(self: *FnBuilder, condition: typed.NodeId, then_body: typed.StatementId, else_body: ?typed.StatementId) Error!void {
        const cond = try self.expression(condition);
        if (self.current == null) return;
        const then_block = try self.newBlock();
        const join = try self.newBlock();
        const else_block = if (else_body != null) try self.newBlock() else join;
        try self.branch(cond, then_block, else_block, @intCast(self.nodeOf(condition).span.start));
        try self.seal(then_block);
        self.current = then_block;
        try self.statement(then_body);
        try self.jump(join);
        if (else_body) |other| {
            try self.seal(else_block);
            self.current = else_block;
            try self.statement(other);
            try self.jump(join);
        }
        try self.seal(join);
        self.enter(join);
    }

    fn loopStatement(self: *FnBuilder, id: usize, condition: typed.NodeId, body: typed.StatementId, step: ?typed.StatementId) Error!void {
        const header = try self.newBlock();
        try self.jump(header);
        self.current = header;
        const cond = try self.expression(condition);
        const body_block = try self.newBlock();
        const latch = try self.newBlock();
        const exit = try self.newBlock();
        try self.branch(cond, body_block, exit, @intCast(self.nodeOf(condition).span.start));
        try self.seal(body_block);
        try self.loops.append(self.allocator(), .{ .id = id, .latch = latch, .exit = exit });
        self.current = body_block;
        try self.statement(body);
        try self.jump(latch);
        try self.seal(latch);
        self.enter(latch);
        if (step) |s| try self.statement(s);
        try self.jump(header);
        _ = self.loops.pop();
        try self.seal(header);
        try self.seal(exit);
        try self.function.loops.append(self.allocator(), .{ .id = id, .header = header, .body = body_block, .latch = latch, .exit = exit });
        self.enter(exit);
    }

    fn matchStatement(self: *FnBuilder, value_node: typed.NodeId, arms: []const typed.MatchArm, span: u32) Error!void {
        const value = try self.expression(value_node);
        if (self.current == null) return;
        if (arms.len == 0) return self.mb.refuse("empty match", span);
        const union_type = self.function.inst(value).ty;
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
        const join = try self.newBlock();
        for (arms, 0..) |arm, i| {
            const arm_block = try self.newBlock();
            if (i + 1 < arms.len) {
                const expected = try self.constant(.u32, @intCast(arm.tag));
                const is_arm = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = expected, .data = @backingInt(ir.Predicate.eq), .span = span });
                const next = try self.newBlock();
                try self.branch(is_arm, arm_block, next, span);
                try self.seal(next);
                try self.seal(arm_block);
                const resume_at = next;
                self.current = arm_block;
                try self.armBody(arm, value, union_type, span);
                try self.jump(join);
                self.current = resume_at;
            } else {
                try self.jump(arm_block);
                try self.seal(arm_block);
                self.current = arm_block;
                try self.armBody(arm, value, union_type, span);
                try self.jump(join);
            }
        }
        try self.seal(join);
        self.enter(join);
    }

    fn armBody(self: *FnBuilder, arm: typed.MatchArm, value: ir.Ref, union_type: ir.Type, span: u32) Error!void {
        if (arm.slot) |slot| {
            const payload_type = switch (self.mb.module.compound(union_type)) {
                .@"union" => |cases| if (arm.tag < cases.len and cases[arm.tag] != .void) cases[arm.tag] else return self.mb.refuse("match payload", span),
                else => return self.mb.refuse("match payload", span),
            };
            const payload = try self.emit(.{ .op = .union_payload, .ty = payload_type, .a = value, .data = arm.tag, .span = span });
            try self.write(self.local(slot), self.current.?, payload);
        }
        try self.statement(arm.body);
    }

    // ---- expressions --------------------------------------------------------------

    fn typeOf(self: *FnBuilder, id: typed.NodeId) Error!ir.Type {
        const n = self.nodeOf(id);
        return self.mb.mapType(n.ty, @intCast(n.span.start));
    }

    fn expression(self: *FnBuilder, id: typed.NodeId) Error!ir.Ref {
        const n = self.nodeOf(id);
        const span: u32 = @intCast(n.span.start);
        if (self.current == null) return .none;
        switch (n.data) {
            .integer => |value| return self.constant(try self.typeOf(id), value),
            .boolean => |value| return self.constant(.bool, @intFromBool(value)),
            .unit => return .none,
            .local => |slot| return self.read(self.local(slot), self.current.?),
            .block_value => |block| {
                try self.statement(block.body);
                return self.expression(block.value);
            },
            .binary => |b| return self.binary(b.op, b.left, b.right, @intCast(b.op_span.start)),
            .unary => |u| return self.unary(u.op, u.operand, try self.typeOf(id), @intCast(u.op_span.start)),
            .cast => |operand| return self.cast(operand, try self.typeOf(id), span),
            .wrap => |operand| return self.wrap(operand, try self.typeOf(id), span),
            .unwrap => |operand| {
                const value = try self.expression(operand);
                if (value != .none and self.function.inst(value).ty == .f64) return value;
                return self.mb.refuse("unwrap", span);
            },
            .call => |c| return self.call(c.function, c.arguments, c.evaluation != null, span),
            .buffer_operation => |operation| return self.bufferOperation(operation.kind, operation.owner, operation.arguments, try self.typeOf(id), span),
            .acquire_buffer => |acquire| {
                const capacity = try self.expression(acquire.capacity);
                return self.emit(.{ .op = .list_new, .ty = try self.typeOf(id), .a = capacity, .span = span });
            },
            .variant => |variant| {
                const payload = if (variant.value) |value| try self.expression(value) else .none;
                return self.emit(.{ .op = .union_make, .ty = try self.typeOf(id), .a = payload, .data = variant.tag, .span = span });
            },
            .print => |print| return self.printNode(print, span),
            .array => |items| {
                if (try self.typeOf(id) != .str) return self.mb.refuse("array", span);
                return self.stringConstant(items, span);
            },
            else => return self.mb.refuse(@tagName(n.data), span),
        }
    }

    fn binary(self: *FnBuilder, op: typed.BinaryOp, left_node: typed.NodeId, right_node: typed.NodeId, span: u32) Error!ir.Ref {
        if (op == .logical_and or op == .logical_or) return self.shortCircuit(op == .logical_or, left_node, right_node, span);
        const left = try self.expression(left_node);
        const right = try self.expression(right_node);
        if (self.current == null) return .none;
        const ty = self.function.inst(left).ty;
        const is_float = ty == .f64;
        const Shape = struct { op: ir.Op, check: ir.Check = .none, predicate: ?ir.Predicate = null };
        const shape: Shape = switch (op) {
            .add => .{ .op = .add, .check = .exact },
            .sub => .{ .op = .sub, .check = .exact },
            .mul => .{ .op = .mul, .check = .exact },
            .div => .{ .op = .div, .check = .exact },
            .rem => .{ .op = .rem, .check = .exact },
            .floor_div => .{ .op = .floor_div, .check = .exact },
            .floor_rem => .{ .op = .floor_rem, .check = .exact },
            .wrapping_add => .{ .op = .add },
            .wrapping_sub => .{ .op = .sub },
            .wrapping_mul => .{ .op = .mul },
            .bit_and => .{ .op = .bit_and },
            .bit_or => .{ .op = .bit_or },
            .bit_xor => .{ .op = .bit_xor },
            .eq => .{ .op = if (is_float) .fcmp else .cmp, .predicate = .eq },
            .ne => .{ .op = if (is_float) .fcmp else .cmp, .predicate = .ne },
            .lt => .{ .op = .cmp, .predicate = .lt },
            .le => .{ .op = .cmp, .predicate = .le },
            .gt => .{ .op = .cmp, .predicate = .gt },
            .ge => .{ .op = .cmp, .predicate = .ge },
            .f64_add => .{ .op = .fadd },
            .f64_sub => .{ .op = .fsub },
            .f64_mul => .{ .op = .fmul },
            .f64_div => .{ .op = .fdiv },
            .f64_eq => .{ .op = .fcmp, .predicate = .eq },
            .f64_lt => .{ .op = .fcmp, .predicate = .lt },
            .f64_le => .{ .op = .fcmp, .predicate = .le },
            else => return self.mb.refuse(@tagName(op), span),
        };
        const is_compare = shape.predicate != null;
        const scalar = is_float or ty.integer() != null or ty == .bool;
        if (!is_compare and !scalar) return self.mb.refuse("binary operand type", span);
        return self.emit(.{
            .op = shape.op,
            .ty = if (is_compare) .bool else ty,
            .a = left,
            .b = right,
            .data = if (shape.predicate) |p| @backingInt(p) else 0,
            .check = shape.check,
            .span = span,
        });
    }

    /// `a or b` / `a and b`: the right operand runs only when it decides the result.
    fn shortCircuit(self: *FnBuilder, is_or: bool, left_node: typed.NodeId, right_node: typed.NodeId, span: u32) Error!ir.Ref {
        const variable = try self.synthetic(.bool);
        const left = try self.expression(left_node);
        const from = self.current orelse return .none;
        try self.write(variable, from, left);
        const right_block = try self.newBlock();
        const join = try self.newBlock();
        if (is_or) try self.branch(left, join, right_block, span) else try self.branch(left, right_block, join, span);
        try self.seal(right_block);
        self.current = right_block;
        const right = try self.expression(right_node);
        if (self.current) |end| try self.write(variable, end, right);
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        if (self.current == null) return .none;
        return self.read(variable, join);
    }

    fn unary(self: *FnBuilder, op: typed.UnaryOp, operand_node: typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        return switch (op) {
            .neg => self.emit(.{ .op = .neg, .ty = ty, .a = operand, .check = .exact, .span = span }),
            .not => self.emit(.{ .op = .not, .ty = .bool, .a = operand, .span = span }),
            .f64_neg => self.emit(.{ .op = .fneg, .ty = .f64, .a = operand, .span = span }),
            .f64_from_i64 => self.emit(.{ .op = .int_to_float, .ty = .f64, .a = operand, .span = span }),
            .f64_to_i64, .f64_to_i32, .f64_to_i16, .f64_to_i8, .f64_to_u8, .f64_to_u16, .f64_to_u32 => self.emit(.{ .op = .float_to_int, .ty = ty, .a = operand, .check = .exact, .span = span }),
            else => self.mb.refuse(@tagName(op), span),
        };
    }

    fn cast(self: *FnBuilder, operand_node: typed.NodeId, target: ir.Type, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        const source = self.function.inst(operand).ty;
        if (source == target) return operand;
        const from = source.integer() orelse return self.mb.refuse("cast source", span);
        const to = target.integer() orelse return self.mb.refuse("cast target", span);
        // A conversion every source value survives carries no check.
        const fits = (from.signed == to.signed and to.bits >= from.bits) or (!from.signed and to.signed and to.bits > from.bits);
        return self.emit(.{ .op = .convert, .ty = target, .a = operand, .check = if (fits) .none else .exact, .span = span });
    }

    /// `wrap` builds a domain value: for `float` from IEEE bits (a constant) or a float operation.
    fn wrap(self: *FnBuilder, operand_node: typed.NodeId, target: ir.Type, span: u32) Error!ir.Ref {
        if (target != .f64) return self.mb.refuse("domain wrap", span);
        const operand = self.nodeOf(operand_node);
        if (operand.data == .integer) {
            const bits: u64 = @truncate(@as(u128, @bitCast(operand.data.integer)));
            return self.detached(.{ .op = .fconst, .ty = .f64, .data = bits });
        }
        const value = try self.expression(operand_node);
        if (value == .none or self.function.inst(value).ty == .f64) return value;
        return self.mb.refuse("float bits", span);
    }

    fn call(self: *FnBuilder, callee: typed.FunctionId, argument_nodes: []const typed.NodeId, has_evaluation: bool, span: u32) Error!ir.Ref {
        if (has_evaluation) return self.mb.refuse("call evaluation body", span);
        const index = try self.mb.functionIndex(callee);
        var arguments: std.ArrayList(ir.Ref) = .empty;
        defer arguments.deinit(self.allocator());
        for (argument_nodes) |argument| try arguments.append(self.allocator(), try self.expression(argument));
        if (self.current == null) return .none;
        const ret = self.mb.module.functions.items[index].signature.ret;
        const data = try self.extraSlice(arguments.items);
        const ref = try self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(@intCast(index)), .data = data, .span = span });
        return if (ret == .void) .none else ref;
    }

    fn bufferOperation(self: *FnBuilder, kind: anytype, owner: typed.LocalId, argument_nodes: []const typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const receiver = try self.read(self.local(owner), self.current.?);
        const receiver_type = self.function.inst(receiver).ty;
        switch (kind) {
            .length => return self.emit(.{ .op = if (receiver_type == .str) .str_len else .list_len, .ty = .u64, .a = receiver, .span = span }),
            .read => {
                if (receiver_type == .str) return self.mb.refuse("string index", span);
                const index = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                return self.emit(.{ .op = .list_get, .ty = ty, .a = receiver, .b = index, .check = .exact, .span = span });
            },
            .append => {
                try self.guardPlace(self.local(owner), span);
                const value = try self.expression(argument_nodes[0]);
                const block = self.current orelse return .none;
                // The receiver is read again: the argument may not change it, but
                // the checker's owner local is the value the push consumes.
                const list = try self.read(self.local(owner), block);
                const pushed = try self.emit(.{ .op = .list_push, .ty = self.function.inst(list).ty, .a = list, .b = value, .span = span });
                try self.write(self.local(owner), self.current.?, pushed);
                return .none;
            },
            // The iterated place cannot change length here: every write to it while an
            // alias is active is refused (`guardPlace`), so the check cannot fail.
            .iteration_check => return .none,
            .parse_int => {
                if (receiver_type != .str) return self.mb.refuse("parse_int receiver", span);
                return self.emit(.{ .op = .str_parse_int, .ty = ty, .a = receiver, .span = span });
            },
            else => return self.mb.refuse(@tagName(kind), span),
        }
    }

    /// A string literal: the checker spells it as code points, stored here as UTF-8.
    fn stringConstant(self: *FnBuilder, items: []const typed.NodeId, span: u32) Error!ir.Ref {
        var bytes: std.ArrayList(u8) = .empty;
        for (items) |item| {
            const point = switch (self.nodeOf(item).data) {
                .integer => |value| value,
                else => return self.mb.refuse("string element", span),
            };
            var buffer: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(std.math.cast(u21, point) orelse return self.mb.refuse("code point", span), &buffer) catch return self.mb.refuse("code point", span);
            try bytes.appendSlice(self.allocator(), buffer[0..len]);
        }
        const index = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), try bytes.toOwnedSlice(self.allocator()));
        return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
    }

    fn printNode(self: *FnBuilder, print: typed.Print, span: u32) Error!ir.Ref {
        if (print.debug or print.separator != null or print.terminator != null) return self.mb.refuse("print options", span);
        var operands: std.ArrayList(ir.Ref) = .empty;
        defer operands.deinit(self.allocator());
        const stream = if (print.stream) |stream_node| try self.expression(stream_node) else try self.constant(.cap, if (print.sink == .stdout) 1 else 2);
        try operands.append(self.allocator(), stream);
        for (print.arguments) |argument| {
            const value = try self.expression(argument);
            const ty = self.function.inst(value).ty;
            if (ty.integer() == null and ty != .bool and ty != .str) return self.mb.refuse("print argument type", span);
            try operands.append(self.allocator(), value);
        }
        if (self.current == null) return .none;
        _ = try self.emit(.{ .op = .print, .ty = .void, .data = try self.extraSlice(operands.items), .span = span });
        return .none;
    }
};

fn buildFunction(mb: *ModuleBuilder, checked: typed.Function, declared: ir.Function) Error!ir.Function {
    var b: FnBuilder = .{ .mb = mb, .function = declared, .checked = checked };
    defer b.ssa.defs.deinit(mb.allocator);
    defer b.ssa.incomplete.deinit(mb.allocator);
    defer b.ssa.sealed.deinit(mb.allocator);
    defer b.ssa.types.deinit(mb.allocator);
    defer b.loops.deinit(mb.allocator);
    defer b.aliases.deinit(mb.allocator);
    for (checked.scope.locals) |local| {
        const ty = mb.mapType(local.ty, @intCast(local.declaration.start)) catch .void;
        try b.ssa.types.append(mb.allocator, ty);
    }
    const entry = try b.newBlock();
    try b.seal(entry);
    b.current = entry;
    for (declared.signature.params, 0..) |ty, i| {
        const param = try b.detached(.{ .op = .param, .ty = ty, .data = i });
        try b.write(@intCast(i), entry, param);
    }
    try b.statement(checked.scope.body);
    if (b.current != null) {
        if (declared.signature.ret != .void) return mb.refuse("missing return", declared.span);
        _ = try b.emit(.{ .op = .ret, .ty = .void });
    }
    return b.function;
}

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
const fuse = @import("fuse.zig");
const flags = @import("flags.zig");

/// Refusal reasons several constructs share.
const refuse_payload = "match payload";
const refuse_field_index = "field index";
const refuse_non_record = "field of a non-record value";
const refuse_equality = "aggregate equality";

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
    // Element reads that are only taken apart become field reads, before ownership sees their uses of the list.
    for (mb.module.functions.items) |*function| {
        if (function.signature.linkage == .internal) _ = try fuse.projections(allocator, function, &mb.module);
    }
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
    /// Checked record and union type → IR type. An entry is made before the type's fields
    /// are mapped, so a recursive type (through a boxed field) finds itself.
    types: std.AutoHashMapUnmanaged(typed.Type, ir.Type) = .empty,

    fn refuse(self: *ModuleBuilder, reason: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span };
        return error.Unsupported;
    }

    /// The IR index of a checked function, declaring it on first use.
    fn functionIndex(self: *ModuleBuilder, id: typed.FunctionId) Error!u32 {
        if (self.ids.get(@backingInt(id))) |index| return index;
        const function = self.program.functions[@backingInt(id)];
        const all = try self.allocator.alloc(ir.Type, function.signature.parameter_count);
        for (all, function.scope.locals[0..all.len]) |*param, local| param.* = try self.mapType(local.ty, @intCast(local.declaration.start));
        // A `unit` parameter carries nothing, so it is not passed.
        var passed: std.ArrayList(ir.Type) = .empty;
        for (all) |param| if (param != .void) try passed.append(self.allocator, param);
        const params = passed.items;
        const span: u32 = @intCast(function.declaration.start);
        const linkage: ir.Linkage = if (function.policy.c_abi) .extern_c else if (function.policy.host != null) return self.refuse("host function", span) else .internal;
        const declared = try self.mapType(function.signature.return_type, span);
        if (linkage == .extern_c and function.signature.declared_mutates.len != 0) return self.refuse("mut parameter of an extern function", span);
        const ret = try self.returnType(function, declared, all, span);
        const index: u32 = @intCast(self.module.functions.items.len);
        try self.module.functions.append(self.allocator, .{ .name = function.name, .signature = .{ .params = params, .ret = ret, .linkage = linkage }, .span = span });
        try self.ids.put(self.allocator, @backingInt(id), index);
        try self.pending.append(self.allocator, id);
        return index;
    }

    /// The IR return type of `function`: its declared type, or, when it has `mut` parameters,
    /// a record of that value (unless it is `unit`) followed by each `mut` parameter's final
    /// value in parameter order. The caller writes those values back into its places, which
    /// is the `inout` of a `mut` parameter done by value (docs/design/new-core-s1.md §7).
    fn returnType(self: *ModuleBuilder, function: typed.Function, declared: ir.Type, params: []const ir.Type, span: u32) Error!ir.Type {
        const mutated = function.signature.declared_mutates;
        if (mutated.len == 0) return declared;
        if (function.signature.mutates.len != mutated.len) return self.refuse("inferred mut parameter", span);
        var parts: std.ArrayList(ir.Type) = .empty;
        defer parts.deinit(self.allocator);
        if (declared != .void) try parts.append(self.allocator, declared);
        for (mutated) |position| try parts.append(self.allocator, params[position]);
        if (parts.items.len == 1) return parts.items[0];
        return self.module.intern(self.allocator, .{ .record = parts.items });
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
        if (record.shape.variants) |variants| return self.mapUnion(ty, variants, span);
        if (record.contract.callback != null) return self.refuse("function value type", span);
        if (record.shape.array != null) return self.refuse("fixed array type", span);
        if (record.shape.resource != null) return self.refuse("resource type", span);
        if (record.shape.domain != null) return self.refuse("domain type", span);
        if (record.isManagedRecord()) return self.refuse("class type", span);
        return self.mapRecord(ty, record, span);
    }

    /// Reserve the IR type of a checked record or union before its parts are mapped.
    fn reserve(self: *ModuleBuilder, ty: typed.Type) Error!ir.Type {
        const reserved: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + self.module.compounds.items.len));
        try self.module.compounds.append(self.allocator, .{ .record = &.{} });
        try self.types.put(self.allocator, ty, reserved);
        return reserved;
    }

    /// The type a field or payload is stored as: its own type, or a `box` of it when it closes a recursive type.
    fn stored(self: *ModuleBuilder, ty: typed.Type, boxed: bool, span: u32) Error!ir.Type {
        const mapped = try self.mapType(ty, span);
        if (mapped == .cap) return self.refuse("record field type", span);
        if (!boxed or mapped == .void) return mapped;
        return self.module.intern(self.allocator, .{ .box = mapped });
    }

    fn mapRecord(self: *ModuleBuilder, ty: typed.Type, record: typed.Record, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| return known;
        const reserved = try self.reserve(ty);
        const fields = try self.allocator.alloc(ir.Type, record.fields.len);
        for (record.fields, fields) |field, *out| {
            out.* = self.stored(field.ty, field.boxed, span) catch |err| return self.unreserve(ty, err);
            if (out.* == .void) return self.unreserve(ty, self.refuse("record field type", span));
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .record = fields };
        return reserved;
    }

    /// Mapping `ty` failed: forget its reservation, so a later use is refused again instead of finding an empty type.
    fn unreserve(self: *ModuleBuilder, ty: typed.Type, err: Error) Error {
        _ = self.types.remove(ty);
        return err;
    }

    /// A union, `Option`, `Result` or payload-free enum: one IR case per checked case, in the checker's order.
    fn mapUnion(self: *ModuleBuilder, ty: typed.Type, variants: typed.Variants, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| return known;
        const reserved = try self.reserve(ty);
        const cases = try self.allocator.alloc(ir.Type, variants.cases.len);
        for (variants.cases, cases) |case, *out| {
            out.* = if (case.payload) |payload| self.stored(payload, case.boxed, span) catch |err| return self.unreserve(ty, err) else .void;
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .@"union" = cases };
        return reserved;
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
/// loop iterates it or an index reads it. `iterating` is set once the loop's
/// `iteration_check` on the alias has been built: from then on a write to the root is refused.
const Alias = struct { hidden: u32, root: u32, iterating: bool = false };

/// One step from a value to a part of it: a record field, or a list element by index.
const Step = union(enum) { field: u32, element: ir.Ref };

/// Where a value lives: a local and a path of steps from it, and how many times the local had
/// been written when the place was named. A write to a hidden receiver (`s.items.append(v)`,
/// `xs[i][j] = v`) rebuilds the path and stores the new root back, unless the root was written
/// since (`receiverOf`).
const Place = struct { root: u32, steps: []const Step, root_version: u32 = 0 };

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
    /// The place each checker-hidden receiver local was initialized from.
    places: std.AutoHashMapUnmanaged(u32, Place) = .empty,
    /// How many times each local has been assigned so far (the builder's own count of writes).
    versions: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// The type the function declares it returns; `function.signature.ret` is a record
    /// of it and the `mut` parameters' final values when there are any.
    declared_ret: ir.Type = .void,
    /// The `mut` list parameters this path of the walk has rebound (`items = other`): a rebinding
    /// detaches the name from the caller's collection, so only the payload it had then is written
    /// back (COW-MUT-REBIND-1), which `connected` holds as a variable.
    rebound: std.ArrayList(u32) = .empty,
    /// Per `mut` list parameter, the synthetic variable of the value still tied to the caller.
    connected: std.AutoHashMapUnmanaged(u32, u32) = .empty,

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

    /// Record where a checker-hidden receiver came from: its `place` (so a write through it
    /// can be stored back), and, for a list or string, an alias of the place's root for D1.
    fn noteAlias(self: *FnBuilder, slot: typed.LocalId, place: ?Place) Error!void {
        const name = self.checked.scope.locals[@backingInt(slot)].name;
        if (name.len == 0 or name[0] != '<') return;
        const variable = self.local(slot);
        const found = place orelse {
            _ = self.places.remove(variable);
            return;
        };
        try self.places.put(self.allocator(), variable, found);
        const ty = self.ssa.types.items[variable];
        if (ty != .str and !(ty.isCompound() and self.mb.module.kind(ty).? == .list)) return;
        try self.aliases.append(self.allocator(), .{ .hidden = variable, .root = found.root });
    }

    /// D1 (live-place iteration): a loop over a place sees the body's writes to it.
    /// The Core IR reads the alias, which equals the place only while nothing writes
    /// the place, so the builder refuses such a write instead of iterating a snapshot.
    fn guardPlace(self: *FnBuilder, variable: u32, span: u32) Error!void {
        for (self.aliases.items) |alias| {
            if (alias.iterating and (alias.root == variable or alias.hidden == variable)) return self.mb.refuse("write to a list while it is iterated (live-place iteration)", span);
        }
    }

    /// The loop's `iteration_check` on `owner` has been reached: the alias is iterated from here on.
    fn markIterating(self: *FnBuilder, owner: typed.LocalId) void {
        const variable = self.local(owner);
        for (self.aliases.items) |*alias| {
            if (alias.hidden == variable) alias.iterating = true;
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
                var place: ?Place = null;
                const value = try self.expressionPlace(store.value, &place);
                const block = self.current orelse return;
                try self.detachParameter(self.local(store.slot), span);
                try self.write(self.local(store.slot), block, value);
                try self.assigned(self.local(store.slot));
                try self.noteAlias(store.slot, place);
            },
            .discard => |value| _ = try self.expression(value),
            .ret => |value| {
                const result = try self.expression(value);
                if (self.current == null) return;
                try self.traceReturned(value, result, span);
                try self.returnValue(result, span);
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
        const base = self.rebound.items.len;
        var paths: std.ArrayList([]const u32) = .empty;
        defer paths.deinit(self.allocator());
        self.current = then_block;
        try self.statement(then_body);
        try self.endPath(base, &paths);
        try self.jump(join);
        if (else_body) |other| {
            try self.seal(else_block);
            self.current = else_block;
            try self.statement(other);
            try self.endPath(base, &paths);
            try self.jump(join);
        } else try paths.append(self.allocator(), &.{});
        try self.joinPaths(paths.items, @intCast(self.nodeOf(condition).span.start));
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
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
        const join = try self.newBlock();
        const base = self.rebound.items.len;
        var paths: std.ArrayList([]const u32) = .empty;
        defer paths.deinit(self.allocator());
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
                try self.armBody(arm, value, span);
                try self.endPath(base, &paths);
                try self.jump(join);
                self.current = resume_at;
            } else {
                try self.jump(arm_block);
                try self.seal(arm_block);
                self.current = arm_block;
                try self.armBody(arm, value, span);
                try self.endPath(base, &paths);
                try self.jump(join);
            }
        }
        try self.joinPaths(paths.items, span);
        try self.seal(join);
        self.enter(join);
    }

    fn armBody(self: *FnBuilder, arm: typed.MatchArm, value: ir.Ref, span: u32) Error!void {
        if (arm.slot) |slot| {
            const payload = try self.payloadOf(value, arm.tag, span);
            try self.write(self.local(slot), self.current.?, payload);
        }
        try self.statement(arm.body);
    }

    /// The type of the value `ref` stands for.
    fn typeOfRef(self: *FnBuilder, ref: ir.Ref) ir.Type {
        return self.function.inst(self.function.resolve(ref)).ty;
    }

    /// The payload of case `tag` of union `value`, read out of its box when the case is boxed.
    fn payloadOf(self: *FnBuilder, value: ir.Ref, tag: usize, span: u32) Error!ir.Ref {
        const union_type = self.typeOfRef(value);
        const cases = switch (self.mb.module.kind(union_type) orelse return self.mb.refuse(refuse_payload, span)) {
            .@"union" => self.mb.module.compound(union_type).@"union",
            else => return self.mb.refuse(refuse_payload, span),
        };
        if (tag >= cases.len) return self.mb.refuse(refuse_payload, span);
        if (cases[tag] == .void) return .none;
        const payload = try self.emit(.{ .op = .union_payload, .ty = cases[tag], .a = value, .data = tag, .span = span });
        return self.unbox(payload, span);
    }

    /// The value inside `value` when it is a `box` (a recursive field or payload), else `value`.
    fn unbox(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(value);
        if (self.mb.module.kind(ty) != .box) return value;
        return self.emit(.{ .op = .box_get, .ty = self.mb.module.compound(ty).box, .a = value, .span = span });
    }

    /// `value` as stored in a slot of type `stored`: boxed when the slot is a `box`.
    fn boxFor(self: *FnBuilder, stored: ir.Type, value: ir.Ref, span: u32) Error!ir.Ref {
        if (self.mb.module.kind(stored) != .box) return value;
        return self.emit(.{ .op = .box_make, .ty = stored, .a = value, .span = span });
    }

    // ---- places ---------------------------------------------------------------------

    /// The place a checked local names: the one its hidden receiver was initialized from, else itself.
    fn placeOfLocal(self: *FnBuilder, slot: typed.LocalId) Error!Place {
        const variable = self.local(slot);
        if (self.places.get(variable)) |place| return place;
        return .{ .root = variable, .steps = &.{}, .root_version = self.version(variable) };
    }

    fn version(self: *FnBuilder, variable: u32) u32 {
        return self.versions.get(variable) orelse 0;
    }

    /// Note an assignment to `variable`.
    fn assigned(self: *FnBuilder, variable: u32) Error!void {
        try self.versions.put(self.allocator(), variable, self.version(variable) + 1);
    }

    /// `items = value` of a `mut` list parameter detaches the name from the caller's collection:
    /// from here on only the payload it had before is written back, and the new binding is an
    /// ordinary local (a write to it copies, COW-MUT-REBIND-1). Which paths rebound it is a fact of
    /// the walk, so a rebinding in a loop is refused, and paths that join must agree (`joinPaths`).
    fn detachParameter(self: *FnBuilder, variable: u32, span: u32) Error!void {
        const connected = self.connected.get(variable) orelse return;
        if (std.mem.indexOfScalar(u32, self.rebound.items, variable) != null) return;
        if (self.loops.items.len != 0) return self.mb.refuse("rebinding of a mut collection parameter in a loop", span);
        try self.write(connected, self.current.?, try self.read(variable, self.current.?));
        try self.rebound.append(self.allocator(), variable);
    }

    /// One path of a fork ended: what it rebound leaves `rebound` (back to the fork's state) and,
    /// when the path reaches the join, is kept in `paths`.
    fn endPath(self: *FnBuilder, base: usize, paths: *std.ArrayList([]const u32)) Error!void {
        const added = try self.allocator().dupe(u32, self.rebound.items[base..]);
        self.rebound.shrinkRetainingCapacity(base);
        if (self.current != null) try paths.append(self.allocator(), added);
    }

    /// The paths that reach a join must have rebound the same `mut` list parameters, which stay
    /// rebound after it; whether one was rebound cannot be a run-time fact.
    fn joinPaths(self: *FnBuilder, paths: []const []const u32, span: u32) Error!void {
        if (paths.len == 0) return;
        for (paths[1..]) |other| {
            var same = other.len == paths[0].len;
            if (same) for (other) |variable| {
                if (std.mem.indexOfScalar(u32, paths[0], variable) == null) same = false;
            };
            if (!same) return self.mb.refuse("conditional rebinding of a mut collection parameter", span);
        }
        try self.rebound.appendSlice(self.allocator(), paths[0]);
    }

    /// The value of receiver `owner`. A receiver the checker rooted at a place (`frame.code`,
    /// `xs`) is a reference to what the place held then; if evaluating the operation's arguments
    /// wrote that place (a `mut` call in an index), whether the write shows through depends on
    /// whether the callee changed the list in place or replaced it, which a value cannot tell,
    /// so the operation is refused.
    fn receiverOf(self: *FnBuilder, owner: typed.LocalId, span: u32) Error!ir.Ref {
        const variable = self.local(owner);
        const alias = try self.read(variable, self.current.?);
        const place = self.places.get(variable) orelse return alias;
        if (self.version(place.root) != place.root_version) return self.mb.refuse("write to a receiver's place while its arguments are evaluated", span);
        return alias;
    }

    fn extendPlace(self: *FnBuilder, place: Place, step: Step) Error!Place {
        const steps = try self.allocator().alloc(Step, place.steps.len + 1);
        @memcpy(steps[0..place.steps.len], place.steps);
        steps[place.steps.len] = step;
        return .{ .root = place.root, .steps = steps, .root_version = place.root_version };
    }

    /// Field `index` of record `base`, out of its box when the field is boxed.
    fn fieldGet(self: *FnBuilder, base: ir.Ref, index: usize, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(base);
        const fields = switch (self.mb.module.kind(record_type) orelse return self.mb.refuse(refuse_non_record, span)) {
            .record => self.mb.module.compound(record_type).record,
            else => return self.mb.refuse(refuse_non_record, span),
        };
        if (index >= fields.len) return self.mb.refuse(refuse_field_index, span);
        const got = try self.emit(.{ .op = .record_get, .ty = fields[index], .a = base, .data = index, .span = span });
        return self.unbox(got, span);
    }

    /// Record `base` with field `index` replaced by `value` (boxed again when the field is boxed).
    fn fieldSet(self: *FnBuilder, base: ir.Ref, index: usize, value: ir.Ref, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(base);
        const fields = switch (self.mb.module.kind(record_type) orelse return self.mb.refuse(refuse_non_record, span)) {
            .record => self.mb.module.compound(record_type).record,
            else => return self.mb.refuse(refuse_non_record, span),
        };
        if (index >= fields.len) return self.mb.refuse(refuse_field_index, span);
        const stored = try self.boxFor(fields[index], value, span);
        return self.emit(.{ .op = .record_set, .ty = record_type, .a = base, .b = stored, .data = index, .span = span });
    }

    /// The part of `base` that `step` reaches.
    fn stepGet(self: *FnBuilder, base: ir.Ref, step: Step, span: u32) Error!ir.Ref {
        switch (step) {
            .field => |index| return self.fieldGet(base, index, span),
            .element => |index| {
                const list_type = self.typeOfRef(base);
                if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element of a non-list value", span);
                return self.emit(.{ .op = .list_get, .ty = self.mb.module.compound(list_type).list, .a = base, .b = index, .check = .exact, .span = span });
            },
        }
    }

    /// `base` with the part `step` reaches replaced by `value`.
    fn stepSet(self: *FnBuilder, base: ir.Ref, step: Step, value: ir.Ref, span: u32) Error!ir.Ref {
        switch (step) {
            .field => |index| return self.fieldSet(base, index, value, span),
            .element => |index| return self.listSet(base, index, value, span),
        }
    }

    /// `list` with element `index` replaced by `value`; the index is checked, and ownership
    /// releases the element that is replaced.
    fn listSet(self: *FnBuilder, list: ir.Ref, index: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
        const list_type = self.typeOfRef(list);
        if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element write of a non-list", span);
        const data = try self.extraSlice(&.{value});
        return self.emit(.{ .op = .list_set, .ty = self.typeOfRef(list), .a = list, .b = index, .data = data, .check = .exact, .span = span });
    }

    fn storeInto(self: *FnBuilder, base: ir.Ref, steps: []const Step, value: ir.Ref, span: u32) Error!ir.Ref {
        if (steps.len == 0) return value;
        const inner = if (steps.len == 1) value else blk: {
            const child = try self.stepGet(base, steps[0], span);
            break :blk try self.storeInto(child, steps[1..], value, span);
        };
        return self.stepSet(base, steps[0], inner, span);
    }

    /// The value at `place` as its root stands now.
    fn readPlace(self: *FnBuilder, place: Place, span: u32) Error!ir.Ref {
        var value = try self.read(place.root, self.current.?);
        for (place.steps) |step| value = try self.stepGet(value, step, span);
        return value;
    }

    /// Store `value` at `place`: rebuild the path from the root's current value and write the root.
    fn storePlace(self: *FnBuilder, place: Place, value: ir.Ref, span: u32) Error!ir.Ref {
        try self.guardPlace(place.root, span);
        const block = self.current orelse return .none;
        const root = try self.read(place.root, block);
        const rebuilt = try self.storeInto(root, place.steps, value, span);
        try self.write(place.root, self.current.?, rebuilt);
        try self.assigned(place.root);
        return rebuilt;
    }

    /// A write through receiver `owner` produced `value`: bind it, and store it back where the receiver came from.
    fn writeOwner(self: *FnBuilder, owner: typed.LocalId, value: ir.Ref, span: u32) Error!void {
        try self.write(self.local(owner), self.current.?, value);
        try self.assigned(self.local(owner));
        if (self.places.getPtr(self.local(owner))) |place| {
            _ = try self.storePlace(place.*, value, span);
            place.root_version = self.version(place.root);
        }
    }

    // ---- expressions --------------------------------------------------------------

    fn typeOf(self: *FnBuilder, id: typed.NodeId) Error!ir.Type {
        const n = self.nodeOf(id);
        return self.mb.mapType(n.ty, @intCast(n.span.start));
    }

    fn expression(self: *FnBuilder, id: typed.NodeId) Error!ir.Ref {
        return self.expressionPlace(id, null);
    }

    /// Build expression `id`. When `out` is given and the expression names a place (a local,
    /// a field of a place, an element read of a place), `out` receives that place.
    fn expressionPlace(self: *FnBuilder, id: typed.NodeId, out: ?*?Place) Error!ir.Ref {
        const n = self.nodeOf(id);
        const span: u32 = @intCast(n.span.start);
        if (self.current == null) return .none;
        switch (n.data) {
            .integer => |value| return self.constant(try self.typeOf(id), value),
            .boolean => |value| return self.constant(.bool, @intFromBool(value)),
            .unit => return .none,
            .local => |slot| {
                if (out) |place| place.* = try self.placeOfLocal(slot);
                return self.read(self.local(slot), self.current.?);
            },
            .block_value => |block| {
                try self.statement(block.body);
                return self.expressionPlace(block.value, out);
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
            .buffer_operation => |operation| return self.bufferOperation(operation, try self.typeOf(id), span, out),
            .acquire_buffer => |acquire| {
                const capacity = try self.expression(acquire.capacity);
                return self.emit(.{ .op = .list_new, .ty = try self.typeOf(id), .a = capacity, .span = span });
            },
            .variant => |case| return self.variantMake(id, case.tag, case.value, span),
            .record => |fields| return self.recordMake(id, fields, span),
            .update => |update| return self.recordUpdate(update.base, update.fields, span),
            .field => |field| {
                var base_place: ?Place = null;
                const base = try self.expressionPlace(field.base, if (out != null) &base_place else null);
                if (self.current == null) return .none;
                const value = try self.fieldGet(base, field.index, span);
                if (out) |place| if (base_place) |found| {
                    place.* = try self.extendPlace(found, .{ .field = @intCast(field.index) });
                };
                return value;
            },
            .propagate => |try_value| return self.tryValue(try_value.value, try_value.output, span),
            .print => |print| return self.printNode(print, span),
            .array => |items| {
                if (try self.typeOf(id) != .str) return self.mb.refuse("array", span);
                return self.stringConstant(items, span);
            },
            else => return self.mb.refuse(@tagName(n.data), span),
        }
    }

    /// `Name(...)` or `Union.case(...)`: a union value, boxing a recursive payload. Building an
    /// `Err` starts an error trace at this site (ERROR-TRACE-1).
    fn variantMake(self: *FnBuilder, id: typed.NodeId, tag: usize, value_node: ?typed.NodeId, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        var payload: ir.Ref = .none;
        if (value_node) |value| {
            payload = try self.expression(value);
            if (self.current == null) return .none;
        }
        const cases = switch (self.mb.module.kind(ty) orelse return self.mb.refuse("variant type", span)) {
            .@"union" => self.mb.module.compound(ty).@"union",
            else => return self.mb.refuse("variant type", span),
        };
        if (tag >= cases.len) return self.mb.refuse("variant tag", span);
        if (payload != .none) payload = try self.boxFor(cases[tag], payload, span);
        const made = try self.emit(.{ .op = .union_make, .ty = ty, .a = payload, .data = tag, .span = span });
        if (typed.resultShape(self.nodeOf(id).ty, self.mb.program.records)) |shape| {
            if (shape.error_tag == tag) _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.origin), .span = span });
        }
        return made;
    }

    /// `Name(fields)`: the fields are evaluated in the order written and placed in declaration order.
    fn recordMake(self: *FnBuilder, id: typed.NodeId, fields: []const typed.FieldInit, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        const stored = switch (self.mb.module.kind(ty) orelse return self.mb.refuse("record type", span)) {
            .record => self.mb.module.compound(ty).record,
            else => return self.mb.refuse("record type", span),
        };
        const values = try self.allocator().alloc(ir.Ref, stored.len);
        @memset(values, .none);
        for (fields) |init| {
            if (init.index >= stored.len) return self.mb.refuse(refuse_field_index, span);
            const value = try self.expression(init.value);
            if (self.current == null) return .none;
            values[init.index] = try self.boxFor(stored[init.index], value, span);
        }
        for (values) |value| if (value == .none) return self.mb.refuse("record field without a value", span);
        return self.emit(.{ .op = .record_make, .ty = ty, .data = try self.extraSlice(values), .span = span });
    }

    /// `update`: the base with each listed field replaced.
    fn recordUpdate(self: *FnBuilder, base_node: typed.NodeId, fields: []const typed.FieldInit, span: u32) Error!ir.Ref {
        var base = try self.expression(base_node);
        if (self.current == null) return .none;
        for (fields) |init| {
            const value = try self.expression(init.value);
            if (self.current == null) return .none;
            base = try self.fieldSet(base, init.index, value, span);
        }
        return base;
    }

    /// `value?`: the payload on success; on failure `return` the failure in the function's own
    /// result type, converting the error into the case of the caller's error union that carries it.
    fn tryValue(self: *FnBuilder, value_node: typed.NodeId, output: typed.Type, span: u32) Error!ir.Ref {
        const input = try self.expression(value_node);
        if (self.current == null) return .none;
        const records = self.mb.program.records;
        const input_type = self.nodeOf(value_node).ty;
        const result = try self.mb.mapType(output, span);
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = input, .span = span });
        const failed = try self.newBlock();
        const succeeded = try self.newBlock();
        if (typed.resultShape(input_type, records)) |shape| {
            const wanted = typed.resultShape(output, records) orelse return self.mb.refuse("propagation into a non-result", span);
            const is_error = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(shape.error_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
            try self.branch(is_error, failed, succeeded, span);
            try self.seal(failed);
            try self.seal(succeeded);
            self.current = failed;
            // An error passed on unchanged appends its site; one wrapped into a case of the caller's
            // error union is `converted`, naming `Union.case` (design note §6.2).
            const converted = shape.error_type != wanted.error_type;
            const case = if (converted) typed.wrappingCase(records, wanted.error_type, shape.error_type) orelse return self.mb.refuse("error conversion", span) else 0;
            const naming: ir.Ref = if (converted) try self.caseName(wanted.error_type, case) else .none;
            _ = try self.emit(.{ .op = .err_trace, .ty = .void, .a = naming, .data = @backingInt(if (converted) ir.TraceMode.converted else ir.TraceMode.append), .span = span });
            var error_value = try self.payloadOf(input, shape.error_tag, span);
            if (converted) {
                const union_type = try self.mb.mapType(wanted.error_type, span);
                const stored = self.mb.module.compound(union_type).@"union"[case];
                error_value = try self.emit(.{ .op = .union_make, .ty = union_type, .a = try self.boxFor(stored, error_value, span), .data = case, .span = span });
            }
            const stored = self.mb.module.compound(result).@"union"[wanted.error_tag];
            const failure = try self.emit(.{ .op = .union_make, .ty = result, .a = try self.boxFor(stored, error_value, span), .data = wanted.error_tag, .span = span });
            try self.returnValue(failure, span);
            self.current = succeeded;
            return self.payloadOf(input, shape.ok_tag, span);
        }
        const none_tag = optionNoneTag(records, input_type) orelse return self.mb.refuse("propagation of a non-result", span);
        _ = optionNoneTag(records, output) orelse return self.mb.refuse("propagation into a non-option", span);
        const is_none = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(none_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
        try self.branch(is_none, failed, succeeded, span);
        try self.seal(failed);
        try self.seal(succeeded);
        self.current = failed;
        const none = try self.emit(.{ .op = .union_make, .ty = result, .data = none_tag, .span = span });
        try self.returnValue(none, span);
        self.current = succeeded;
        return self.payloadOf(input, 1 - none_tag, span);
    }

    /// A string constant `Union.case` naming case `case` of the union `ty`, as the old core spells it.
    fn caseName(self: *FnBuilder, ty: typed.Type, case: usize) Error!ir.Ref {
        const record = self.mb.program.records[ty.recordIndex()];
        const text = try std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ record.name, record.shape.variants.?.cases[case].name });
        const index = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), text);
        return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
    }

    /// `return value` in a function that returns a `Result`: when the statement did not build the
    /// value itself (a variable, a call, a conditional) and it is an `Err`, its site is appended.
    fn traceReturned(self: *FnBuilder, node: typed.NodeId, result: ir.Ref, span: u32) Error!void {
        const shape = typed.resultShape(self.checked.signature.return_type, self.mb.program.records) orelse return;
        if (result == .none or self.nodeOf(node).data == .variant) return;
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = result, .span = span });
        const is_error = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(shape.error_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
        const failed = try self.newBlock();
        const done = try self.newBlock();
        try self.branch(is_error, failed, done, span);
        try self.seal(failed);
        self.current = failed;
        _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.returned), .span = span });
        try self.jump(done);
        try self.seal(done);
        self.enter(done);
    }

    /// End the function with `result`. A function with `mut` parameters returns a record of its
    /// result (unless `unit`) and the final value of each `mut` parameter.
    fn returnValue(self: *FnBuilder, result: ir.Ref, span: u32) Error!void {
        const mutated = self.checked.signature.declared_mutates;
        var value = result;
        if (mutated.len != 0) {
            var parts: std.ArrayList(ir.Ref) = .empty;
            defer parts.deinit(self.allocator());
            if (self.declared_ret != .void) try parts.append(self.allocator(), result);
            for (mutated) |position| {
                // A rebound collection writes back the payload that was still the caller's.
                const rebound = std.mem.indexOfScalar(u32, self.rebound.items, position) != null;
                try parts.append(self.allocator(), try self.read(if (rebound) self.connected.get(position).? else position, self.current.?));
            }
            value = if (parts.items.len == 1) parts.items[0] else try self.emit(.{ .op = .record_make, .ty = self.function.signature.ret, .data = try self.extraSlice(parts.items), .span = span });
        }
        _ = try self.emit(.{ .op = .ret, .ty = .void, .a = if (self.function.signature.ret == .void) .none else value, .span = span });
        self.current = null;
    }

    fn binary(self: *FnBuilder, op: typed.BinaryOp, left_node: typed.NodeId, right_node: typed.NodeId, span: u32) Error!ir.Ref {
        if (op == .logical_and or op == .logical_or) return self.shortCircuit(op == .logical_or, left_node, right_node, span);
        var left = try self.expression(left_node);
        var right = try self.expression(right_node);
        if (self.current == null) return .none;
        // The checker may type the literal of `i16 + 1` as `i64`: it takes the other operand's type.
        if (op != .shift_left and op != .shift_right) {
            const left_type = self.typeOfRef(left);
            const right_type = self.typeOfRef(right);
            if (left_type != right_type) {
                if (self.nodeOf(right_node).data == .integer and self.nodeOf(left_node).data != .integer) right = try self.literalAs(right_node, left_type);
                if (self.nodeOf(left_node).data == .integer and self.nodeOf(right_node).data != .integer) left = try self.literalAs(left_node, right_type);
            }
        }
        const ty = self.typeOfRef(left);
        if (ty == .str or ty.isCompound()) return self.aggregateCompare(op, left, right, span);
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

    /// The integer literal `node` as a constant of integer type `ty`.
    fn literalAs(self: *FnBuilder, node: typed.NodeId, ty: ir.Type) Error!ir.Ref {
        if (ty.integer() == null) return self.expression(node);
        return self.constant(ty, self.nodeOf(node).data.integer);
    }

    /// `==` and `!=` of two records, unions (enums, `Option`, `Result`) or lists: structural,
    /// never a pointer comparison. A `str` (S2's text runtime) and a recursive value are refused.
    fn aggregateCompare(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        if (op != .eq and op != .ne) return self.mb.refuse(if (op == .add) "concatenation" else "operator on an aggregate value", span);
        const same = try self.equal(left, right, span);
        if (self.current == null or op == .eq) return same;
        return self.emit(.{ .op = .not, .ty = .bool, .a = same, .span = span });
    }

    /// Whether `ty` is recursive: it holds a `box`, or nests deeper than equality is expanded
    /// (a record that holds a list of itself).
    fn recursive(self: *FnBuilder, ty: ir.Type, depth: u32) bool {
        const m = self.mb.module;
        const kind = m.kind(ty) orelse return false;
        if (depth > 6) return true;
        switch (kind) {
            .box => return true,
            .list => return self.recursive(m.compound(ty).list, depth + 1),
            .record => for (m.compound(ty).record) |field| if (self.recursive(field, depth + 1)) return true,
            .@"union" => for (m.compound(ty).@"union") |case| if (self.recursive(case, depth + 1)) return true,
        }
        return false;
    }

    /// Whether two values of one type are equal: fields and payloads compare with the type's
    /// own equality (floats as IEEE numbers), and a union's payloads only when its tags are equal.
    fn equal(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const m = self.mb.module;
        const ty = self.typeOfRef(a);
        if (ty == .str) return self.mb.refuse("str equality", span);
        // A recursive value would need a function that calls itself, not an expansion in place.
        if (self.recursive(ty, 0)) return self.mb.refuse("equality of a recursive value", span);
        if (ty == .f64) return self.emit(.{ .op = .fcmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span });
        if (ty.integer() != null or ty == .bool) return self.emit(.{ .op = .cmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span });
        switch (m.kind(ty) orelse return self.mb.refuse(refuse_equality, span)) {
            .record => {
                var all = try self.constant(.bool, 1);
                for (m.compound(ty).record, 0..) |_, i| {
                    const here = try self.equal(try self.fieldGet(a, i, span), try self.fieldGet(b, i, span), span);
                    all = try self.emit(.{ .op = .bit_and, .ty = .bool, .a = all, .b = here, .span = span });
                }
                return all;
            },
            .@"union" => return self.unionEqual(a, b, span),
            .list => return self.listEqual(a, b, span),
            .box => return self.mb.refuse(refuse_equality, span),
        }
    }

    /// Two unions are equal when their tags are and the payloads of that case are.
    fn unionEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const cases = self.mb.module.compound(self.typeOfRef(a)).@"union";
        const tag_a = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = a, .span = span });
        const tag_b = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = b, .span = span });
        const tags = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = tag_b, .data = @backingInt(ir.Predicate.eq), .span = span });
        var payloads: std.ArrayList(u32) = .empty;
        defer payloads.deinit(self.allocator());
        for (cases, 0..) |case, k| if (case != .void) try payloads.append(self.allocator(), @intCast(k));
        if (payloads.items.len == 0) return tags;
        const result = try self.synthetic(.bool);
        try self.write(result, self.current.?, tags);
        const check = try self.newBlock();
        const join = try self.newBlock();
        try self.branch(tags, check, join, span);
        try self.seal(check);
        self.current = check;
        for (payloads.items) |case| {
            const arm = try self.newBlock();
            const next = try self.newBlock();
            const is_case = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = try self.constant(.u32, case), .data = @backingInt(ir.Predicate.eq), .span = span });
            try self.branch(is_case, arm, next, span);
            try self.seal(arm);
            try self.seal(next);
            self.current = arm;
            const same = try self.equal(try self.payloadOf(a, case, span), try self.payloadOf(b, case, span), span);
            try self.write(result, self.current.?, same);
            try self.jump(join);
            self.current = next;
        }
        // A tag that carries no payload: equal tags are equal values.
        try self.write(result, self.current.?, tags);
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        return self.read(result, join);
    }

    /// Two lists are equal when their lengths are and every element pair is.
    fn listEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const element = self.mb.module.compound(self.typeOfRef(a)).list;
        const length_a = try self.emit(.{ .op = .list_len, .ty = .u64, .a = a, .span = span });
        const length_b = try self.emit(.{ .op = .list_len, .ty = .u64, .a = b, .span = span });
        const lengths = try self.emit(.{ .op = .cmp, .ty = .bool, .a = length_a, .b = length_b, .data = @backingInt(ir.Predicate.eq), .span = span });
        const result = try self.synthetic(.bool);
        const index = try self.synthetic(.u64);
        try self.write(result, self.current.?, lengths);
        try self.write(index, self.current.?, try self.constant(.u64, 0));
        const header = try self.newBlock();
        const join = try self.newBlock();
        const start = try self.newBlock();
        try self.branch(lengths, start, join, span);
        try self.seal(start);
        self.current = start;
        try self.jump(header);
        self.current = header;
        const position = try self.read(index, header);
        const more = try self.emit(.{ .op = .cmp, .ty = .bool, .a = position, .b = length_a, .data = @backingInt(ir.Predicate.lt), .span = span });
        const body = try self.newBlock();
        const finished = try self.newBlock();
        try self.branch(more, body, finished, span);
        try self.seal(body);
        try self.seal(finished);
        self.current = body;
        // The lengths agree, so both reads are in range.
        const x = try self.emit(.{ .op = .list_get, .ty = element, .a = a, .b = position, .span = span });
        const y = try self.emit(.{ .op = .list_get, .ty = element, .a = b, .b = position, .span = span });
        const same = try self.equal(x, y, span);
        const latch = try self.newBlock();
        const differ = try self.newBlock();
        try self.branch(same, latch, differ, span);
        try self.seal(latch);
        try self.seal(differ);
        self.current = latch;
        try self.write(index, latch, try self.emit(.{ .op = .add, .ty = .u64, .a = position, .b = try self.constant(.u64, 1), .span = span }));
        try self.jump(header);
        try self.seal(header);
        self.current = differ;
        try self.write(result, differ, try self.constant(.bool, 0));
        try self.jump(join);
        self.current = finished;
        try self.write(result, finished, try self.constant(.bool, 1));
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        return self.read(result, join);
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
        const mutated = self.mb.program.functions[@backingInt(callee)].signature.declared_mutates;
        var arguments: std.ArrayList(ir.Ref) = .empty;
        defer arguments.deinit(self.allocator());
        // A `mut` argument is the place the callee's final value is written back to. The callee
        // writes the caller's tree when the call runs, not where the argument is evaluated, so the
        // place is only located while the arguments are evaluated and its value read after them.
        const places = try self.allocator().alloc(Place, mutated.len);
        const values = try self.allocator().alloc(ir.Ref, argument_nodes.len);
        for (argument_nodes, values, 0..) |argument, *value, position| {
            const slot = std.mem.indexOfScalar(u16, mutated, @intCast(position));
            var place: ?Place = null;
            value.* = try self.expressionPlace(argument, if (slot != null) &place else null);
            if (slot) |at| places[at] = place orelse return self.mb.refuse("mut argument that is not a place", span);
        }
        if (self.current == null) return .none;
        for (mutated, places) |position, place| values[position] = try self.readPlace(place, span);
        // A `unit` argument is evaluated for its effects and not passed.
        for (values) |value| if (value != .none and self.typeOfRef(value) != .void) try arguments.append(self.allocator(), value);
        const ret = self.mb.module.functions.items[index].signature.ret;
        const data = try self.extraSlice(arguments.items);
        const result = try self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(@intCast(index)), .data = data, .span = span });
        if (mutated.len == 0) return if (ret == .void) .none else result;
        const declared = try self.mb.mapType(self.mb.program.functions[@backingInt(callee)].signature.return_type, span);
        return self.writeBack(result, declared != .void, places, span);
    }

    /// A call to a function with `mut` parameters returned `result`: its own value (unless
    /// `unit`) and each `mut` parameter's final value. Store those into the caller's places.
    fn writeBack(self: *FnBuilder, result: ir.Ref, has_value: bool, places: []const Place, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(result);
        const parts: []const ir.Type = if (self.mb.module.kind(record_type) == .record) self.mb.module.compound(record_type).record else &.{};
        // One part alone is not wrapped in a record.
        const wrapped = has_value or places.len > 1;
        var value: ir.Ref = result;
        if (wrapped) value = if (has_value) try self.emit(.{ .op = .record_get, .ty = parts[0], .a = result, .data = 0, .span = span }) else .none;
        const first: usize = if (has_value) 1 else 0;
        for (places, 0..) |place, k| {
            const part = if (wrapped) try self.emit(.{ .op = .record_get, .ty = parts[first + k], .a = result, .data = first + k, .span = span }) else result;
            _ = try self.storePlace(place, part, span);
        }
        return if (has_value) value else .none;
    }

    fn bufferOperation(self: *FnBuilder, operation: anytype, ty: ir.Type, span: u32, out: ?*?Place) Error!ir.Ref {
        const kind = operation.kind;
        const owner = operation.owner;
        const argument_nodes = operation.arguments;
        const receiver_type = self.ssa.types.items[self.local(owner)];
        switch (kind) {
            .length => return self.emit(.{ .op = if (receiver_type == .str) .str_len else .list_len, .ty = .u64, .a = try self.receiverOf(owner, span), .span = span }),
            .read => {
                if (receiver_type == .str) return self.mb.refuse("string index", span);
                const index = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                const receiver = try self.receiverOf(owner, span);
                if (out) |place| place.* = try self.extendPlace(try self.placeOfLocal(owner), .{ .element = index });
                return self.emit(.{ .op = .list_get, .ty = ty, .a = receiver, .b = index, .check = .exact, .span = span });
            },
            .append => {
                try self.guardPlace(self.local(owner), span);
                const value = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                // The receiver is read after the argument, which may have written its place.
                const list = try self.receiverOf(owner, span);
                const pushed = try self.emit(.{ .op = .list_push, .ty = self.function.inst(list).ty, .a = list, .b = value, .span = span });
                try self.writeOwner(owner, pushed, span);
                return .none;
            },
            .write => {
                if (receiver_type == .str) return self.mb.refuse("string element write", span);
                try self.guardPlace(self.local(owner), span);
                const index = try self.expression(argument_nodes[0]);
                const value = try self.expression(argument_nodes[1]);
                if (self.current == null) return .none;
                const list = try self.receiverOf(owner, span);
                try self.writeOwner(owner, try self.listSet(list, index, value, span), span);
                return .none;
            },
            .pop => {
                if (!receiver_type.isCompound() or self.mb.module.kind(receiver_type) != .list) return self.mb.refuse("pop of a non-list", span);
                try self.guardPlace(self.local(owner), span);
                const list = try self.receiverOf(owner, span);
                // The last element is read first (index `len - 1`, wrapping to a failing index
                // when empty, which the read reports as the empty-list pop), then dropped.
                const length = try self.emit(.{ .op = .list_len, .ty = .u64, .a = list, .span = span });
                const last = try self.emit(.{ .op = .sub, .ty = .u64, .a = length, .b = try self.constant(.u64, 1), .span = span });
                const element = try self.emit(.{ .op = .list_get, .ty = ty, .a = list, .b = last, .data = flags.pop_read, .check = .exact, .span = span });
                const rest = try self.emit(.{ .op = .list_pop, .ty = receiver_type, .a = list, .check = .exact, .span = span });
                try self.writeOwner(owner, rest, span);
                return element;
            },
            // A write to an iterated place while the loop runs is refused (`guardPlace`), so the
            // length cannot change and the check cannot fail.
            .iteration_check => {
                self.markIterating(owner);
                return .none;
            },
            .parse_int => {
                if (receiver_type != .str) return self.mb.refuse("parse_int receiver", span);
                return self.emit(.{ .op = .str_parse_int, .ty = ty, .a = try self.receiverOf(owner, span), .span = span });
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
        const stream = if (print.stream) |stream_node| try self.expression(stream_node) else try self.constant(.cap, switch (print.sink) {
            .stdout => 1,
            .stderr => 2,
            .error_report => flags.error_stream,
        });
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

/// The tag of `None` when `ty` is an `Option` (a two-case union whose first case has no payload).
fn optionNoneTag(records: []const typed.Record, ty: typed.Type) ?usize {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const record = records[ty.recordIndex()];
    const variants = record.shape.variants orelse return null;
    if (!variants.is_union or variants.fallible or variants.cases.len != 2) return null;
    if (variants.cases[0].payload != null or variants.cases[1].payload == null) return null;
    if (!std.mem.startsWith(u8, record.name, "Option")) return null;
    return 0;
}

fn buildFunction(mb: *ModuleBuilder, checked: typed.Function, declared: ir.Function) Error!ir.Function {
    var b: FnBuilder = .{ .mb = mb, .function = declared, .checked = checked };
    b.declared_ret = try mb.mapType(checked.signature.return_type, declared.span);
    defer b.rebound.deinit(mb.allocator);
    defer b.connected.deinit(mb.allocator);
    defer b.places.deinit(mb.allocator);
    defer b.versions.deinit(mb.allocator);
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
    for (checked.signature.declared_mutates) |position| {
        const ty = b.ssa.types.items[position];
        if (mb.module.kind(ty) == .list) try b.connected.put(mb.allocator, position, try b.synthetic(ty));
    }
    const entry = try b.newBlock();
    try b.seal(entry);
    b.current = entry;
    var passed: u64 = 0;
    for (checked.scope.locals[0..checked.signature.parameter_count], 0..) |local, i| {
        const ty = try mb.mapType(local.ty, @intCast(local.declaration.start));
        if (ty == .void) {
            try b.write(@intCast(i), entry, try b.detached(.{ .op = .undef, .ty = .void }));
            continue;
        }
        const param = try b.detached(.{ .op = .param, .ty = ty, .data = passed });
        passed += 1;
        try b.write(@intCast(i), entry, param);
    }
    try b.statement(checked.scope.body);
    if (b.current != null) {
        if (b.declared_ret != .void) return mb.refuse("missing return", declared.span);
        try b.returnValue(.none, declared.span);
    }
    return b.function;
}

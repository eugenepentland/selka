//! Aggregate copies the ownership analysis proves unnecessary
//! (`QBE-MOVE-ELIDE-1`), on today's collector.
//!
//! A record is a value, so the backend copies one wherever two names could
//! otherwise see each other's writes. Three of those copies are never observed,
//! and the ownership analysis (`ownership.zig`) proves it from the liveness the
//! root planner already solves:
//!
//!  * *Aliases.* The front end spells `p.x = v` as `t = p; t = p; p =
//!    update(t, x=v)`: a compiler temporary filled only from `p`. When nothing
//!    writes `p` while `t` is live, `t` is a second name for `p`'s storage, so
//!    each `t = p` copies nothing and every read of `t` reads `p`'s slot (a
//!    borrow in the ownership analysis's sense).
//!  * *In-place updates.* `update(x, f=v)` copies `x` into scratch and writes
//!    the fields there. When the read of `x` is its last (a move) and nothing
//!    can write `x`'s slot before the result is consumed, the fields are written
//!    into `x`'s own slot, and a store of that result back into `x` copies
//!    nothing.
//!  * *Element write-back.* `xs[i].f = v` reads the element's address, updates
//!    a copy and writes the copy back over the element. When the write names
//!    the same list and index as the read, with nothing in between that can
//!    call, allocate or write either, the fields are written into the element
//!    where it lives and the write-back copies nothing.
//!
//! Every produced value, trap, trace and exit status is the one the copies
//! produced.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const arena_lower = @import("qbe_arena.zig");
const ownership = @import("ownership.zig");

/// Failures raised while planning.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// The absent index or pc.
pub const none = ownership.none;

/// How an `update_record` writes its result.
pub const Update = union(enum) {
    /// Into this pc's scratch, after copying the base there.
    copy,
    /// Into the named local's own slot, the base's storage.
    slot: u32,
    /// Into the list element whose address the named local holds.
    element: u32,
};

/// The copies one function skips.
pub const Plan = struct {
    /// Per local, the local whose slot holds its value, or `none`.
    aliases: []const u32 = &.{},
    /// Per instruction, how an update there writes its result.
    updates: []const Update = &.{},
    /// Per instruction, whether a store or element write there finds its
    /// value already in place.
    in_place: []const bool = &.{},

    /// The local whose slot holds local `index`'s value, or `index` itself.
    pub fn resolve(self: Plan, index: usize) usize {
        if (index >= self.aliases.len or self.aliases[index] == none) return index;
        return self.aliases[index];
    }
    /// Whether local `index` names another local's slot.
    pub fn aliased(self: Plan, index: usize) bool {
        return index < self.aliases.len and self.aliases[index] != none;
    }
    /// How the update at `pc` writes its result.
    pub fn update(self: Plan, pc: usize) Update {
        return if (pc < self.updates.len) self.updates[pc] else .copy;
    }
    /// Whether the store or element write at `pc` has nothing left to copy.
    pub fn placed(self: Plan, pc: usize) bool {
        return pc < self.in_place.len and self.in_place[pc];
    }
};

/// Bind the planner to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Plan the copies this function skips.
        pub fn plan(self: *E) Error!Plan {
            return planFunction(E, self);
        }
    };
}

fn planFunction(comptime E: type, self: *E) Error!Plan {
    const f = self.function;
    const analysis = self.ownership orelse return .{};
    if (arena_lower.opens(f)) return .{};
    const a = self.allocator;
    const aliases = try a.alloc(u32, f.scope.locals.len);
    @memset(aliases, none);
    const updates = try a.alloc(Update, f.scope.instructions.len);
    @memset(updates, .copy);
    const in_place = try a.alloc(bool, f.scope.instructions.len);
    @memset(in_place, false);
    var result: Plan = .{ .aliases = aliases, .updates = updates, .in_place = in_place };
    for (0..f.scope.locals.len) |index| {
        if (try aliasTarget(E, self, index)) |target| aliases[index] = @intCast(target);
    }
    // A local another alias names cannot itself name a third slot.
    for (aliases) |*target| if (target.* != none and aliases[target.*] != none) {
        target.* = none;
    };
    self.moves = result;
    for (f.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .update_record => |update| updates[pc] = try placeUpdate(E, self, .{ .analysis = analysis, .pc = pc, .ty = update.ty, .indices = update.indices, .in_place = in_place }),
        else => {},
    };
    result = .{ .aliases = aliases, .updates = updates, .in_place = in_place };
    return result;
}

/// Whether a value of `ty` is a copied aggregate this rule may name in place:
/// not one word, owning nothing, and of nonzero size.
fn plainAggregate(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    if (self.isScalar(ty)) return false;
    const value = try self.layout(ty);
    return !value.drop and value.size != 0;
}

/// Whether local `index` holds its own value in its own slot.
fn ownSlot(comptime E: type, self: *E, index: usize) bool {
    return !self.byReference(index) and !self.callerStorage(index);
}

/// The local whose slot can stand in for local `index`: a local every write of
/// `index` copies whole (`load_local s; store_local index`, reached by falling
/// through), and which nothing writes while `index` is live.
fn aliasTarget(comptime E: type, self: *E, index: usize) Error!?usize {
    const f = self.function;
    if (index < f.signature.parameter_count or !ownSlot(E, self, index)) return null;
    const ty = f.scope.locals[index].ty;
    if (!try plainAggregate(E, self, ty)) return null;
    const live = self.live orelse return null;
    var source: ?usize = null;
    const code = f.scope.instructions;
    for (code, 0..) |instruction, pc| {
        if (!writesLocal(f, pc, index)) continue;
        if (instruction.op != .store_local or pc == 0 or self.states[pc] == null or self.isBranchTarget(pc)) return null;
        const loaded = switch (code[pc - 1].op) {
            .load_local => |slot| @backingInt(slot),
            else => return null,
        };
        if (source) |known| if (known != loaded) return null;
        source = loaded;
    }
    const target = source orelse return null;
    if (target == index or f.scope.locals[target].ty != ty or !ownSlot(E, self, target)) return null;
    for (code, 0..) |_, pc| {
        if (self.states[pc] == null) continue;
        if (live.before(pc, index) and writesLocal(f, pc, target)) return null;
    }
    return target;
}

/// One update being placed: the analysis, its pc and shape, and the table of
/// instructions that find their value already in place.
const Candidate = struct {
    analysis: ownership.Analysis,
    pc: usize,
    ty: typed.Type,
    indices: []const usize,
    in_place: []bool,
};

/// Where the update at `candidate.pc` may write its result.
fn placeUpdate(comptime E: type, self: *E, candidate: Candidate) Error!Update {
    const f = self.function;
    const ty = candidate.ty;
    if (self.program.records[ty.recordIndex()].isManagedRecord()) return .copy;
    if (!try plainAggregate(E, self, ty)) return .copy;
    // Every written field is one word, so no field operand can name a region
    // of the base that an earlier field write in place already overwrote.
    for (candidate.indices) |field_index| if (!self.isScalar((try self.field(ty, field_index)).ty)) return .copy;
    const stack = if (candidate.pc < candidate.analysis.operands.len) candidate.analysis.operands[candidate.pc] orelse return .copy else return .copy;
    const at_base = stack.len - candidate.indices.len - 1;
    const base = stack[at_base];
    if (base.origin != .local or base.part != .whole or base.read == none) return .copy;
    if (f.scope.instructions[base.read].op != .load_local) return .copy;
    const loaded: usize = base.local;
    if (self.borrowsElement(loaded)) return writeBack(E, self, candidate, .{ .local = loaded, .load = base.read, .slot = at_base });
    const storage = self.moves.resolve(loaded);
    if (!ownSlot(E, self, storage) or f.scope.locals[storage].ty != ty) return .copy;
    if (!try self.borrowableAt(.{ .index = storage, .slot = at_base, .pc = base.read })) return .copy;
    if (!try deadStorage(E, self, storage, base.read)) return .copy;
    const consumer = try resultConsumer(E, self, candidate.pc, storage) orelse return .copy;
    if (consumer.stores) candidate.in_place[consumer.pc] = true;
    return .{ .slot = @intCast(storage) };
}

/// Whether no read of `storage`'s value — through the local itself or any
/// alias naming its slot — follows the load at `pc`.
fn deadStorage(comptime E: type, self: *E, storage: usize, pc: usize) Error!bool {
    const live = self.live orelse return false;
    for (0..self.function.scope.locals.len) |index| {
        if (index != storage and self.moves.resolve(index) != storage) continue;
        if (live.after(pc, index)) return false;
    }
    // A `mut` argument hands the slot's address to a callee that may still be
    // reading it; no such reference may exist anywhere in the frame.
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .ref_local => |slot| if (@backingInt(slot) == storage) return false,
        else => {},
    };
    return true;
}

/// The instruction that consumes an update's result, when control reaches it
/// by falling through and nothing before it writes `storage`.
const Consumer = struct { pc: usize, stores: bool };

fn resultConsumer(comptime E: type, self: *E, pc: usize, storage: usize) Error!?Consumer {
    const code = self.function.scope.instructions;
    const result_slot = (self.states[pc + 1] orelse return null).len - 1;
    var consumer = pc + 1;
    while (true) {
        if (consumer >= code.len or self.states[consumer] == null or self.isBranchTarget(consumer)) return null;
        const after = if (consumer + 1 < self.states.len) self.states[consumer + 1] else null;
        const height = if (after) |stack| stack.len else 0;
        if (height <= result_slot + 1) break;
        if (writesLocal(self.function, consumer, storage)) return null;
        consumer += 1;
    }
    const stores = switch (code[consumer].op) {
        .store_local => |slot| @backingInt(slot) == storage,
        else => false,
    };
    if (!stores and writesLocal(self.function, consumer, storage)) return null;
    return .{ .pc = consumer, .stores = stores };
}

/// The base of an update that names a list element: the local holding the
/// element's address, the load that read it, and its operand slot.
const Borrowed = struct { local: usize, load: usize, slot: usize };

/// Place an update whose base is a borrowed list element in that element, when
/// the next instruction writes the result back over the same element.
fn writeBack(comptime E: type, self: *E, candidate: Candidate, base: Borrowed) Error!Update {
    const f = self.function;
    const code = f.scope.instructions;
    const write_pc = candidate.pc + 1;
    const live = self.live orelse return .copy;
    if (live.after(base.load, base.local)) return .copy;
    if ((try self.layout(candidate.ty)).trace) return .copy;
    if (write_pc >= code.len or self.states[write_pc] == null or self.isBranchTarget(write_pc)) return .copy;
    const write = switch (code[write_pc].op) {
        .buffer_operation => |operation| operation,
        else => return .copy,
    };
    if (write.kind != .write) return .copy;
    const owner: usize = @backingInt(write.owner);
    const list = f.scope.locals[owner].ty;
    if (!list.isAggregate()) return .copy;
    const schema = self.program.records[list.recordIndex()];
    if (!schema.managed or schema.collection.kind != .list or schema.shape.buffer.? != candidate.ty) return .copy;
    const read = try elementRead(E, self, .{ .local = base.local, .before = base.load }) orelse return .copy;
    if (read.owner != owner) return .copy;
    const write_stack = candidate.analysis.operands[write_pc] orelse return .copy;
    const index = write_stack[write_stack.len - 2];
    if (index.origin != .local or index.part != .whole or index.local != read.index) return .copy;
    if (!try straightLine(E, self, .{ .from = read.pc, .to = write_pc, .owner = owner, .index = read.index, .element = base.local, .store = read.pc + 1 })) return .copy;
    candidate.in_place[write_pc] = true;
    return .{ .element = @intCast(base.local) };
}

/// The element read that last filled a borrowed element local before `before`:
/// its pc, its receiver and the local its index was loaded from.
const Read = struct { pc: usize, owner: usize, index: u32 };
/// Where to look for the element read: the borrowed local and the pc it is
/// read at.
const Lookup = struct { local: usize, before: usize };

fn elementRead(comptime E: type, self: *E, lookup: Lookup) Error!?Read {
    const code = self.function.scope.instructions;
    var at = lookup.before;
    while (at > 1) {
        at -= 1;
        if (!writesLocal(self.function, at, lookup.local)) continue;
        if (code[at].op != .store_local) return null;
        const read = switch (code[at - 1].op) {
            .buffer_operation => |operation| operation,
            else => return null,
        };
        if (read.kind != .read) return null;
        const stack = (self.ownership orelse return null).operands[at - 1] orelse return null;
        if (stack.len == 0) return null;
        const index = stack[stack.len - 1];
        if (index.origin != .local or index.part != .whole) return null;
        return .{ .pc = at - 1, .owner = @backingInt(read.owner), .index = index.local };
    }
    return null;
}

/// The window from an element read to the write that puts the element back.
const Window = struct { from: usize, to: usize, owner: usize, index: u32, element: usize, store: usize };

/// Whether the window runs straight through: no branch enters it, nothing in it
/// writes the list, the index or (but for the one store) the element local, and
/// every instruction between the read and the write only pushes, loads, reads
/// fields or computes scalars — nothing that can call, allocate, release or
/// write memory.
fn straightLine(comptime E: type, self: *E, window: Window) Error!bool {
    const code = self.function.scope.instructions;
    for (window.from + 1..window.to + 1) |pc| {
        if (self.states[pc] == null or self.isBranchTarget(pc)) return false;
        if (writesLocal(self.function, pc, window.owner) or writesLocal(self.function, pc, window.index)) return false;
        if (pc != window.store and writesLocal(self.function, pc, window.element)) return false;
        if (pc == window.to or pc == window.to - 1) continue;
        if (!inert(code[pc].op)) return false;
    }
    return true;
}

/// Instructions that neither call, allocate, release nor write memory, and
/// the element store itself.
fn inert(op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .load_local, .push_i64, .push_integer, .push_bool, .push_unit, .get_field, .wrap_domain, .unwrap_domain => true,
        .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .neg_i64_checked, .cmp_i64, .cmp_bool, .not_bool => true,
        .binary_integer => |operation| !operation.ty.isAggregate(),
        .store_local => true,
        .buffer_operation => |operation| operation.kind == .read or operation.kind == .length,
        else => false,
    };
}

/// Whether the instruction at `pc` writes local `index`: a whole-value store, a
/// move, an explicit drop, a match arm's payload binding into it, or a
/// `ref_local` handing its storage to a callee that writes through it.
pub fn writesLocal(f: bytecode.Function, pc: usize, index: usize) bool {
    return switch (f.scope.instructions[pc].op) {
        .store_local, .move_local, .drop_local, .ref_local => |target| @backingInt(target) == index,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |target| if (@backingInt(target) == index) break true;
        } else false,
        else => false,
    };
}

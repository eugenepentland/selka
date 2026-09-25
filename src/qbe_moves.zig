//! Aggregate copies the ownership analysis proves unnecessary
//! (`QBE-MOVE-ELIDE-1`), on today's collector.
//!
//! A record is a value, so the backend copies one wherever two names could
//! otherwise see each other's writes. Two of those copies are never observed,
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
};
// An update whose base is a borrowed list element written straight back
// (`xs[i].f = v`) keeps its copies. Writing the field into the element in
// place cut nbody's instructions to 0.68x on the QBE backend, but under the
// LLVM backend with full LTO it raised them to 1.06x (thin LTO 1.00x, no LTO
// 0.99x), an effect of the translator's memory classes on LLVM's optimizer
// rather than of the stores themselves, so it waits for that to be understood.

/// The copies one function skips.
pub const Plan = struct {
    /// Per local, the local whose slot holds its value, or `none`.
    aliases: []const u32 = &.{},
    /// Per instruction, how an update there writes its result.
    updates: []const Update = &.{},
    /// Per instruction, whether a store there finds its value already in
    /// place.
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
    /// Whether the store at `pc` has nothing left to copy.
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
    // A borrowed list element is not updated in place: see the note on
    // `Update` for why its write-back keeps the copy.
    if (self.borrowsElement(loaded)) return .copy;
    const storage = self.moves.resolve(loaded);
    if (!ownSlot(E, self, storage) or f.scope.locals[storage].ty != ty) return .copy;
    if (!try self.borrowableAt(.{ .index = storage, .slot = at_base, .pc = base.read })) return .copy;
    if (!try deadStorage(E, self, storage, base.read)) return .copy;
    if (namedBelow(self.moves, stack[0..at_base], storage)) return .copy;
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

/// Whether an operand still on the stack under the base may name `storage`: a
/// read of the local or of an alias of it, or an operand whose source a join
/// lost. `f(p, replace(p, x=2))` passes `p`'s slot as the first argument, so
/// writing the update into that slot would change the argument too.
fn namedBelow(plan: Plan, below: []const ownership.Source, storage: usize) bool {
    for (below) |operand| switch (operand.origin) {
        .fresh => {},
        .unknown => return true,
        .local => if (plan.resolve(operand.local) == storage) return true,
    };
    return false;
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

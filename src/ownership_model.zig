//! The shapes of the ownership analysis (`ownership.zig`,
//! `OWNERSHIP-ANALYSIS-1`) and the facts every step of it reads.
//!
//! Nothing here assumes a runtime. A value's *transfer* — an assignment, an
//! argument, a store into a field, element or dictionary value, a return, a
//! loop or match binding — is a move, a borrow or a copy in the sense value
//! semantics gives those words; a *copy-on-write site* is where a uniqueness
//! check would have to run before a managed payload is written in place.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const liveness = @import("qbe_liveness.zig");
const sources = @import("ownership_sources.zig");

/// The op union every step switches over.
pub const Op = sources.Op;
/// The absent index or pc.
pub const none = sources.none;
/// The failures an analysis step can meet.
pub const Error = sources.Error;
/// Where an operand came from.
pub const Source = sources.Source;

/// What one transfer costs under value semantics.
///
/// `move`: the source is never read again (or no local held it), so the
/// destination can take it as it stands. `borrow`: the source stays readable,
/// but neither side is written while both are, so the two may share it.
/// `copy`: one side may be written while the other is still read, so value
/// semantics needs its own copy (or a copy-on-write check that fires).
pub const Class = enum(u8) { move, borrow, copy };

/// Where a transferred value lands.
pub const Kind = enum(u8) {
    /// A store into an ordinary local.
    assign,
    /// A loop variable or a match arm's payload binding.
    binding,
    /// An argument to a parameter the callee only reads.
    argument,
    /// A list element, set member or dictionary key.
    element,
    /// A dictionary value.
    dict_value,
    /// A field an update writes.
    field,
    /// A field or payload of a value being constructed.
    construct,
    /// The record an update starts from.
    update,
    @"return",
};

/// What a local's slot means for ownership.
///
/// `owned`: it holds a value of its own. `param`: a parameter the body only
/// reads, owned by the caller. `mut_param`: a `mut` parameter, written in the
/// caller's value. `borrowed`: a local filled once from another local (or a
/// part of one) that stays readable and unwritten while it is live, so it is
/// a second name, not a second value. `path`: a compiler temporary filled
/// that way and written through, so its writes land in the other local's
/// value. `plain`: a scalar.
pub const Role = enum(u8) { plain, owned, param, mut_param, borrowed, path };

/// One transfer of a non-scalar value.
pub const Transfer = struct {
    pc: u32,
    kind: Kind,
    source: Source,
    /// The local stored into, for `assign` and `binding`.
    target: u32 = none,
    class: Class,
};

/// One place a managed payload is written in place, and so where value
/// semantics would check that no other name shares it.
pub const Cow = struct {
    /// The write itself, the load handing it to a `mut` parameter, or the
    /// element read that begins a write through a temporary.
    pc: u32,
    /// The local whose payload must be unique.
    local: u32,
    /// The local the instruction names (the root or a temporary aliasing it).
    via: u32,
    /// Whether the elements of `local` must be unique, not only the collection.
    elements: bool,
    /// False when the caller already guarantees uniqueness (a `mut` parameter).
    needed: bool,
    /// The loop header whose entry edges run the check instead, or `none`.
    hoisted: u32 = none,
};

/// The finished analysis of one function.
pub const Analysis = struct {
    roles: []const Role,
    /// Per local, the local a `borrowed` or `path` local aliases, else `none`.
    parents: []const u32,
    transfers: []const Transfer,
    cows: []const Cow,
    /// Per instruction, whether it is a load whose value moves out of its local.
    moves: []const bool,
    /// Per instruction, the sources of its operands on entry; null where
    /// unreachable.
    operands: []const ?[]const Source,
    /// Per instruction, whether a `value_copy` there must make a real copy
    /// (`VALUE-SEMANTICS-2`); empty when the function has none.
    copies: []const bool = &.{},

    /// The local at the end of `local`'s chain of aliases.
    pub fn rootOf(self: Analysis, local: u32) u32 {
        var at = local;
        var guard: usize = 0;
        while (guard <= self.roles.len) : (guard += 1) {
            if (at >= self.roles.len) return at;
            const role = self.roles[at];
            if (role != .borrowed and role != .path) return at;
            const parent = self.parents[at];
            if (parent == none) return at;
            at = parent;
        }
        return at;
    }
};

/// The function under analysis and its typed operand stacks.
pub const Code = struct {
    program: bytecode.Program,
    function: bytecode.Function,
    states: []const ?[]const typed.Type,
};

/// Per-local facts.
pub const Locals = struct {
    list: []const typed.Local,
    params: usize,
    /// Whether the local's type is a non-scalar value (a record, variant,
    /// array or managed collection).
    value: []bool,
    /// Whether the local's type holds a managed reference anywhere inside it.
    managed: []bool,
    roles: []Role,
    parents: []u32,
    /// Whether an alias names an element or field of its parent rather than
    /// the parent's own value.
    step: []bool,
};

/// How each local is written: its stores, the pc of its last store, and
/// whether its payload is written in place.
pub const Defs = struct {
    count: []u32,
    pc: []u32,
    mutated: []bool,
};

/// Per-instruction marks the copy-on-write placement reads and writes.
pub const Marks = struct {
    /// A load that must first make its local unique: a `mut` argument, the
    /// receiver operand of a write, or the root load of a write-through path.
    unique_load: []bool,
    /// An element read that fills a write-through temporary.
    path_read: []bool,
    /// A uniqueness check here moved to a loop entry.
    suppressed: []bool,
    /// A path read whose element uniqueness moved to a loop entry.
    plain_read: []bool,
};

/// Everything one analysis step reads.
pub const Context = struct {
    allocator: std.mem.Allocator,
    code: Code,
    live: liveness.Solution,
    flow: sources.Sources,
    locals: Locals,
    defs: Defs,
    marks: Marks,

    /// Release nothing: every table the context names lives in the arena the
    /// caller passed to `ownership.analyze`, and is freed with it.
    pub fn deinit(self: *Context) void {
        self.* = undefined;
    }
    /// The instructions of the function under analysis.
    pub fn instructions(self: *const Context) []const bytecode.Instruction {
        return self.code.function.scope.instructions;
    }
    /// Whether instruction `pc` runs.
    pub fn reachable(self: *const Context, pc: usize) bool {
        return pc < self.code.states.len and self.code.states[pc] != null;
    }
    /// The role of `local`.
    pub fn role(self: *const Context, local: u32) Role {
        return self.locals.roles[local];
    }
    /// Whether `local` is a second name for another local's value.
    pub fn alias(self: *const Context, local: u32) bool {
        const r = self.role(local);
        return r == .borrowed or r == .path;
    }
    /// The local at the end of `local`'s chain of aliases.
    pub fn rootOf(self: *const Context, local: u32) u32 {
        var at = local;
        var guard: usize = 0;
        while (guard <= self.locals.list.len) : (guard += 1) {
            if (!self.alias(at)) return at;
            const parent = self.locals.parents[at];
            if (parent == none) return at;
            at = parent;
        }
        return at;
    }
    /// Whether `local` is `ancestor` or aliases a value inside it.
    pub fn descends(self: *const Context, local: u32, ancestor: u32) bool {
        var at = local;
        var guard: usize = 0;
        while (guard <= self.locals.list.len) : (guard += 1) {
            if (at == ancestor) return true;
            if (!self.alias(at)) return false;
            at = self.locals.parents[at];
            if (at == none) return false;
        }
        return false;
    }
    /// Whether `local` names its root's own value, with no element step between.
    pub fn levelZero(self: *const Context, local: u32) bool {
        var at = local;
        var guard: usize = 0;
        while (guard <= self.locals.list.len) : (guard += 1) {
            if (!self.alias(at)) return true;
            if (self.locals.step[at]) return false;
            at = self.locals.parents[at];
            if (at == none) return true;
        }
        return false;
    }
    /// Whether local `index` is one the compiler made to name a place. A loop
    /// variable carries a hidden name too, but a write through it must not
    /// reach the collection.
    pub fn temporary(self: *const Context, index: usize) bool {
        if (index < self.locals.params) return false;
        const local = self.locals.list[index];
        if (local.origin == .iteration) return false;
        return local.name.len == 0 or local.name[0] == '<';
    }
    /// Whether a value of `ty` holds a managed reference anywhere inside it.
    pub fn managedType(self: *const Context, ty: typed.Type) bool {
        return holdsManaged(self.code.program, ty, 0);
    }
    /// The record schema of aggregate type `ty`.
    pub fn record(self: *const Context, ty: typed.Type) typed.Record {
        return self.code.program.records[ty.recordIndex()];
    }
    /// Whether instruction `pc` writes the tree rooted at `root`, other than
    /// through path local `through` and its descendants.
    pub fn writesTree(self: *const Context, pc: usize, root: u32, through: ?u32) bool {
        return switch (self.instructions()[pc].op) {
            .store_local, .drop_local, .move_local => |slot| li(slot) == root,
            .buffer_operation => |operation| self.bufferWritesTree(pc, .{ .owner = li(operation.owner), .writes = writesReceiver(operation.kind) }, root, through),
            .load_local => |slot| self.loadWritesTree(pc, li(slot), root, through),
            else => false,
        };
    }

    const Write = struct { owner: u32, writes: bool };

    fn bufferWritesTree(self: *const Context, pc: usize, write: Write, root: u32, through: ?u32) bool {
        const unique_read = self.marks.path_read[pc] and !self.marks.plain_read[pc];
        if (!write.writes and !unique_read) return false;
        if (!self.writeDescends(write.owner, root)) return false;
        const path = through orelse return true;
        return !(self.descends(write.owner, path) or self.feedsPath(pc, path));
    }

    fn loadWritesTree(self: *const Context, pc: usize, loaded: u32, root: u32, through: ?u32) bool {
        if (!self.marks.unique_load[pc] or self.marks.suppressed[pc]) return false;
        if (!self.writeDescends(loaded, root)) return false;
        const path = through orelse return true;
        return !self.feedsPath(pc, path);
    }

    // A field receiver can own its temporary value while COW writes it back
    // into its source record. Its owning role must not hide that mutation
    // from another local's borrow proof. Follow only compiler temporaries
    // with one known source; named homes and fresh results stop the walk.
    fn writeDescends(self: *const Context, local: u32, ancestor: u32) bool {
        var at = local;
        for (0..self.locals.list.len + 1) |_| {
            if (at == ancestor) return true;
            if (self.alias(at)) {
                at = self.locals.parents[at];
                if (at == none) return false;
                continue;
            }
            if (!self.temporary(at)) return false;
            if (self.defs.count[at] != 1) return true;
            const pc = self.defs.pc[at];
            if (pc == none) return true;
            const stack = self.flow.at[pc] orelse return true;
            if (stack.len == 0) return true;
            const source = stack[stack.len - 1];
            if (source.origin != .local) return source.origin != .fresh;
            at = source.local;
        }
        // An unresolved cycle cannot justify eliding a semantic copy.
        return true;
    }

    /// Whether the value instruction `pc` pushes is stored straight into a
    /// local descending from path local `path`.
    pub fn feedsPath(self: *const Context, pc: usize, path: u32) bool {
        const code = self.instructions();
        var at = pc + 1;
        while (at < code.len) : (at += 1) {
            switch (code[at].op) {
                .store_local => |slot| return self.descends(li(slot), path),
                .wrap_domain, .unwrap_domain => {},
                else => return false,
            }
        }
        return false;
    }
};

/// A local id as a 32-bit index.
pub fn li(slot: typed.LocalId) u32 {
    return @intCast(@backingInt(slot));
}

/// Whether a buffer operation changes the collection it is called on: its
/// elements, its length or its capacity, a set's members included.
pub fn writesReceiver(kind: @import("buffer_operations.zig").Kind) bool {
    return kind.writesReceiver() or kind == .set_add or kind == .set_discard;
}

/// Whether `function`'s body may write parameter `position` in place.
pub fn writesParameter(function: bytecode.Function, position: usize) bool {
    for (function.signature.declared_mutates) |p| if (p == position) return true;
    for (function.signature.mutates) |p| if (p == position) return true;
    return false;
}

/// A caller's uniqueness contract applies only while the parameter slot still
/// names the original mutable payload. Keep its borrowed role after rebinding,
/// but require ordinary copy-on-write checks for any replacement value.
pub fn uniqueParameter(function: bytecode.Function, position: usize) bool {
    if (position >= function.signature.parameter_count or !writesParameter(function, position)) return false;
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .move_local, .drop_local, .ref_local => |slot| if (li(slot) == position) return false,
        else => {},
    };
    return true;
}

/// Whether a value of `ty` holds a managed reference: a collection, a string,
/// a `class` or `Cell`, or an aggregate with one inside it.
pub fn holdsManaged(program: bytecode.Program, ty: typed.Type, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    if (depth > 32) return true;
    const schema = program.records[ty.recordIndex()];
    if (schema.managed) return true;
    if (schema.contract.callback != null) return false;
    if (schema.shape.domain) |backing| return holdsManaged(program, backing, depth + 1);
    if (schema.shape.array) |array| return holdsManaged(program, array.element, depth + 1);
    if (schema.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (holdsManaged(program, payload, depth + 1)) return true;
        return false;
    }
    for (schema.fields) |field| if (holdsManaged(program, field.ty, depth + 1)) return true;
    return false;
}

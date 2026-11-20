//! Writes that nothing reads (lane W7, step 1): in one checked function, a store to a local, to a field
//! or element of a local, or a writer call on a local, when no path from the write to the function's
//! end reads, moves, returns, passes or stores that local again. With value semantics and no aliases
//! such a write changes nothing: it is dead code, or a lost update made on a copy.
//!
//! The analysis is a backward liveness over the checked tree (`typed.zig`), which is structured: a
//! block, a branch, a match, a loop with its exits and returns. It runs before Core and decides
//! nothing: `selka lint`'s `dead-write` rule reports what it finds and is off unless asked for.
//!
//! What it never reports: a write to a `mut` parameter or to a place reached through one, a write
//! through a `match mut` binding (both reach caller storage), a write the compiler made (a hidden
//! temporary, a range loop's step), a writer call whose result is used (`pop`, a function that
//! returns a value), a call that also writes a live place or is handed a capability, a file or a
//! resource (it is needed for that effect), and a declaration's initializer. Liveness is per local, not per field: a later
//! read of `x.b` keeps a write to `x.a` alive, so a dead field write beside a live sibling is missed.
const std = @import("std");
const buffer_operations = @import("buffer_operations.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// What a reported write changes: the whole local (`x = ...`, `x += 1`), one field of it
/// (`x.f = ...`), one element of it (`x[i] = ...`, `x.f[i] = ...`), or a call that writes it
/// (`append(mut x, ...)`, `sets.add(mut x, ...)`, `helper(mut x)`).
pub const Kind = enum {
    whole,
    field,
    element,
    writer_call,

    /// The words the rule's message uses for a write of this kind.
    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .whole => "assignment",
            .field => "field write",
            .element => "element write",
            .writer_call => "call that writes it",
        };
    }
};

/// One write no later read can see: where it is, what it changes, the function it is in, the
/// local's source name, and whether that local is read anywhere in the function at all (a local
/// never read is the one `W_UNUSED_BINDING` already names when nothing writes it either).
pub const Hit = struct {
    span: source.Span,
    kind: Kind,
    function: typed.FunctionId,
    local: []const u8,
    never_read: bool,
};

/// Every write in `program` that no later read can see, one per source span, in function order.
/// A span that several checked bodies share (the instances of a generic function) is reported only
/// when it is dead in every one of them. `bytes` is the merged source the spans index.
pub fn find(allocator: std.mem.Allocator, program: typed.Program, bytes: []const u8) std.mem.Allocator.Error![]Hit {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sites: Sites = .{};
    for (program.functions, 0..) |function, index| {
        if (!function.scope.body_complete or function.policy.host != null) continue;
        if (compilerMade(function.name)) continue;
        var analysis = try Analysis.init(arena, program, @fromBackingInt(index), bytes);
        try analysis.run(&sites);
    }
    var hits: std.ArrayList(Hit) = .empty;
    errdefer hits.deinit(allocator);
    std.mem.sort(Key, sites.order.items, {}, keyBefore);
    for (sites.order.items) |key| {
        const site = sites.map.get(key).?;
        if (!site.dead) continue;
        try hits.append(allocator, .{
            .span = .{ .start = key.start, .end = key.end },
            .kind = site.kind,
            .function = site.function,
            .local = site.local,
            .never_read = site.never_read,
        });
    }
    return hits.toOwnedSlice(allocator);
}

/// A function the compiler wrote rather than the source: the entry wrapper and invariant checks.
fn compilerMade(name: []const u8) bool {
    return std.mem.eql(u8, name, "__selka_entry") or @import("invariant_callbacks.zig").isName(name);
}

const Key = struct { start: usize, end: usize };

fn keyBefore(_: void, left: Key, right: Key) bool {
    return left.start < right.start or (left.start == right.start and left.end < right.end);
}

/// One write site and whether every evaluation of it so far found it dead. Liveness only grows
/// while a loop's fixed point is computed, so a site dead in every evaluation is dead in the last.
const Site = struct { kind: Kind, dead: bool, function: typed.FunctionId, local: []const u8, root: usize, never_read: bool };

const Sites = struct {
    map: std.AutoHashMapUnmanaged(Key, Site) = .empty,
    order: std.ArrayList(Key) = .empty,
};

const Set = std.DynamicBitSetUnmanaged;

/// The live sets a loop exit continues with: a `continue` resumes at the step, a `break` after the loop.
const LoopTarget = struct { id: usize, continuing: Set, breaking: Set };

/// One function's liveness pass. `root` maps each hidden temporary that names a place of a local
/// to that local; every other local is its own root (or `none`).
const Analysis = struct {
    arena: std.mem.Allocator,
    program: typed.Program,
    id: typed.FunctionId,
    bytes: []const u8,
    root: []const ?usize,
    /// The locals read anywhere in the body; `run` sizes it.
    ever_read: Set = .{},
    loops: std.ArrayList(LoopTarget) = .empty,

    /// Every allocation is in `arena`, which the caller frees whole.
    fn init(arena: std.mem.Allocator, program: typed.Program, id: typed.FunctionId, bytes: []const u8) std.mem.Allocator.Error!Analysis {
        const roots = try placeRoots(arena, program, program.functions[@backingInt(id)]);
        return .{ .arena = arena, .program = program, .id = id, .bytes = bytes, .root = roots };
    }

    fn current(self: *const Analysis) typed.Function {
        return self.program.functions[@backingInt(self.id)];
    }

    fn run(self: *Analysis, sites: *Sites) std.mem.Allocator.Error!void {
        self.ever_read = try self.empty();
        var live = try self.empty();
        var pass: Pass = .{ .analysis = self, .sites = sites, .record = true };
        try pass.statement(self.current().scope.body, &live);
        // Whether a local is read anywhere is known only once the whole body has been seen.
        var iterator = sites.map.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.function != self.id) continue;
            entry.value_ptr.never_read = !self.ever_read.isSet(entry.value_ptr.root);
        }
    }

    fn empty(self: *const Analysis) std.mem.Allocator.Error!Set {
        return Set.initEmpty(self.arena, self.current().scope.locals.len);
    }

    fn copy(self: *const Analysis, set: Set) std.mem.Allocator.Error!Set {
        return set.clone(self.arena);
    }

    /// The local a write to or read of `slot` reaches, or null for a slot outside the table.
    fn rootOf(self: *const Analysis, slot: typed.LocalId) ?usize {
        const index = @backingInt(slot);
        if (index >= self.root.len) return null;
        return self.root[index];
    }

    /// Whether a write to local `index` is one this rule may report: a named local the function owns.
    fn reportable(self: *const Analysis, index: usize) bool {
        const function = self.current();
        const local = function.scope.locals[index];
        if (hidden(local) or !local.written()) return false;
        switch (local.origin) {
            .local, .collection_copy, .view, .parameter => {},
            // A `match mut` binding names the scrutinee's payload; the other origins are read-only.
            .iteration, .contract_old, .contract_value, .pattern => return false,
        }
        if (index < function.signature.parameter_count) {
            for (function.signature.mutates) |position| if (position == index) return false;
            for (function.signature.declared_mutates) |position| if (position == index) return false;
        }
        return true;
    }
};

/// A local the compiler made: a temporary whose name no source spells.
fn hidden(local: typed.Local) bool {
    return local.usage.temporary or local.name.len == 0 or local.name[0] == '<';
}

/// For each local, the local whose storage it names. A named local names itself. A hidden temporary
/// that is never assigned and whose every initializer is a place of one local (that local, a field
/// or element of it, or another such temporary) names that local's storage: a write through it is
/// a write of the local. Any other hidden temporary names nothing (null).
fn placeRoots(arena: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error![]const ?usize {
    const locals = function.scope.locals;
    const inits = try arena.alloc(std.ArrayList(typed.NodeId), locals.len);
    for (inits) |*list| list.* = .empty;
    const assigned = try arena.alloc(bool, locals.len);
    @memset(assigned, false);
    try collectInits(arena, program, function.scope.body, inits, assigned);
    const roots = try arena.alloc(?usize, locals.len);
    const state = try arena.alloc(u2, locals.len);
    @memset(state, 0);
    for (0..locals.len) |index| roots[index] = try resolveRoot(program, locals, .{ .inits = inits, .assigned = assigned, .roots = roots, .state = state }, index);
    return roots;
}

/// Record every initializer and every assignment of each local in `body`, unpacked match arms included.
fn collectInits(arena: std.mem.Allocator, program: typed.Program, body: typed.StatementId, inits: []std.ArrayList(typed.NodeId), assigned: []bool) std.mem.Allocator.Error!void {
    var walker = try @import("typed_walk.zig").Walker.init(arena, program, body);
    while (try walker.next()) |item| switch (item) {
        .expression => {},
        .statement => |id| switch (program.statements[@backingInt(id)].data) {
            .initialize => |store| if (@backingInt(store.slot) < inits.len) try inits[@backingInt(store.slot)].append(arena, store.value),
            .assign => |store| if (@backingInt(store.slot) < inits.len) {
                assigned[@backingInt(store.slot)] = true;
            },
            // The walker visits an arm's borrowing body, not the body that unpacks an owned payload.
            .match => |match| for (match.arms) |arm| if (arm.unpack) |unpack| try collectInits(arena, program, unpack.body, inits, assigned),
            else => {},
        },
    };
}

/// The tables `resolveRoot` reads and memoizes into; `state` is 0 unseen, 1 in progress, 2 done.
const RootTables = struct {
    inits: []const std.ArrayList(typed.NodeId),
    assigned: []const bool,
    roots: []?usize,
    state: []u2,
};

fn resolveRoot(program: typed.Program, locals: []const typed.Local, tables: RootTables, index: usize) std.mem.Allocator.Error!?usize {
    if (tables.state[index] == 2) return tables.roots[index];
    if (tables.state[index] == 1) return null;
    if (!hidden(locals[index])) {
        tables.state[index] = 2;
        tables.roots[index] = index;
        return index;
    }
    tables.state[index] = 1;
    var found: ?usize = null;
    var named = !tables.assigned[index] and tables.inits[index].items.len != 0;
    if (named) for (tables.inits[index].items) |value| {
        const base = placeBase(program, value) orelse {
            named = false;
            break;
        };
        const target = if (@backingInt(base) < locals.len) try resolveRoot(program, locals, tables, @backingInt(base)) else null;
        if (target == null or (found != null and found.? != target.?)) {
            named = false;
            break;
        }
        found = target;
    };
    tables.state[index] = 2;
    tables.roots[index] = if (named) found else null;
    return tables.roots[index];
}

/// The local a place expression starts from: a local, a field or element of a place, or an element
/// read of a collection local. Null for any other expression.
fn placeBase(program: typed.Program, id: typed.NodeId) ?typed.LocalId {
    var current = id;
    while (true) switch (program.nodes[@backingInt(current)].data) {
        .local => |slot| return slot,
        .field => |field| current = field.base,
        .index => |index| current = index.base,
        .buffer_operation => |op| return if (op.kind == .read) op.owner else null,
        else => return null,
    };
}

/// Whether a value of type `ty` holds an authority a callee can act through: a capability, an open
/// file, a task group or a resource, directly or in a field, element or case payload.
fn carriesAuthority(records: []const typed.Record, ty: typed.Type, depth: usize) bool {
    if (ty.capabilityIndex() != null or ty.isFile() or ty == .task_group or ty == .task_handle) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth == 16) return false;
    const record = records[ty.recordIndex()];
    if (record.shape.resource != null) return true;
    if (record.shape.buffer) |element| if (carriesAuthority(records, element, depth + 1)) return true;
    if (record.collection.key) |key| if (carriesAuthority(records, key, depth + 1)) return true;
    if (record.shape.array) |array| if (carriesAuthority(records, array.element, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (carriesAuthority(records, payload, depth + 1)) return true;
    };
    for (record.fields) |field| if (carriesAuthority(records, field.ty, depth + 1)) return true;
    return false;
}

/// One traversal of a function body from its end to its start, carrying the live set. `record`
/// is false inside a range loop's step, which the compiler writes.
const Pass = struct {
    analysis: *Analysis,
    sites: *Sites,
    record: bool,

    fn gen(self: *Pass, live: *Set, slot: typed.LocalId) void {
        const index = @backingInt(slot);
        const locals = self.analysis.current().scope.locals.len;
        if (index >= locals) return;
        live.set(index);
        self.analysis.ever_read.set(index);
        if (self.analysis.rootOf(slot)) |root| {
            live.set(root);
            self.analysis.ever_read.set(root);
        }
    }

    fn kill(live: *Set, slot: typed.LocalId) void {
        if (@backingInt(slot) < live.bit_length) live.unset(@backingInt(slot));
    }

    /// Note a write of local `root` at `span`, dead when `root` is not live after it.
    fn write(self: *Pass, root: ?usize, span: source.Span, kind: Kind, live: *const Set) std.mem.Allocator.Error!void {
        const index = root orelse return;
        if (index >= live.bit_length) return;
        return self.note(index, span, kind, !live.isSet(index));
    }

    /// Note one evaluation of the write of local `index` at `span`, dead or not. Every evaluation
    /// must be noted, live ones too: a site is dead only when every evaluation of it was.
    fn note(self: *Pass, index: usize, span: source.Span, kind: Kind, dead: bool) std.mem.Allocator.Error!void {
        if (!self.record) return;
        if (!self.analysis.reportable(index)) return;
        const key: Key = .{ .start = span.start, .end = span.end };
        const entry = try self.sites.map.getOrPut(self.analysis.arena, key);
        if (entry.found_existing) {
            entry.value_ptr.dead = entry.value_ptr.dead and dead;
            return;
        }
        entry.value_ptr.* = .{
            .kind = kind,
            .dead = dead,
            .function = self.analysis.id,
            .local = self.analysis.current().scope.locals[index].name,
            .root = index,
            .never_read = false,
        };
        try self.sites.order.append(self.analysis.arena, key);
    }

    fn statement(self: *Pass, id: typed.StatementId, live: *Set) std.mem.Allocator.Error!void {
        const program = self.analysis.program;
        const stmt = program.statements[@backingInt(id)];
        switch (stmt.data) {
            .block => |children| {
                var i = children.len;
                while (i != 0) {
                    i -= 1;
                    try self.statement(children[i], live);
                }
            },
            .ret => |value| {
                live.unsetAll();
                try self.expression(value, live, false);
            },
            .discard => |value| try self.expression(value, live, true),
            .assertion => |check| {
                if (check.message_value) |value| try self.expression(value, live, false);
                try self.expression(check.condition, live, false);
            },
            .loop_exit => |exit| {
                var i = self.analysis.loops.items.len;
                while (i != 0) {
                    i -= 1;
                    const target = self.analysis.loops.items[i];
                    if (target.id != exit.target) continue;
                    live.unsetAll();
                    live.setUnion(if (exit.continuing) target.continuing else target.breaking);
                    break;
                }
            },
            .initialize => |store| try self.initialize(store, live),
            .assign => |store| try self.assign(stmt.span, store, live),
            .branch => |branch| {
                var then_live = try self.analysis.copy(live.*);
                try self.statement(branch.then_body, &then_live);
                if (branch.else_body) |body| try self.statement(body, live);
                live.setUnion(then_live);
                try self.expression(branch.condition, live, false);
            },
            .match => |match| {
                const out = try self.analysis.copy(live.*);
                live.unsetAll();
                for (match.arms) |arm| {
                    var arm_live = try self.analysis.copy(out);
                    try self.statement(arm.body, &arm_live);
                    if (arm.slot) |slot| kill(&arm_live, slot);
                    live.setUnion(arm_live);
                    if (arm.unpack) |unpack| {
                        var unpack_live = try self.analysis.copy(out);
                        try self.statement(unpack.body, &unpack_live);
                        for (unpack.fields) |field| if (field) |slot| kill(&unpack_live, slot);
                        live.setUnion(unpack_live);
                    }
                }
                try self.expression(match.value, live, false);
            },
            .loop => |loop| try self.loopIn(loop, live),
            .range_loop => |range| {
                const plan = range.plan();
                try self.loopIn(plan.loop, live);
                var i = plan.setup.len;
                while (i != 0) {
                    i -= 1;
                    try self.statement(plan.setup[i], live);
                }
                kill(live, plan.end.slot);
                kill(live, plan.start.slot);
                try self.expression(plan.end.value, live, false);
                try self.expression(plan.start.value, live, false);
            },
            .with_scope => |scope| {
                // The scope's end closes its resource, which reads the binding.
                self.gen(live, scope.slot);
                try self.statement(scope.body, live);
                kill(live, scope.slot);
                if (scope.resource) |value| try self.expression(value, live, false);
            },
        }
    }

    /// A loop's live set at entry, from the live set after it: the least fixed point of
    /// head = condition's reads + (body then step then head) + after.
    fn loopIn(self: *Pass, loop: typed.Loop, live: *Set) std.mem.Allocator.Error!void {
        const after = try self.analysis.copy(live.*);
        var head = try self.analysis.copy(after);
        const recording = self.record;
        var round: usize = 0;
        while (true) : (round += 1) {
            var continuing = try self.analysis.copy(head);
            if (loop.step) |step| {
                // A range loop's step is the compiler's; a while loop has none.
                self.record = false;
                try self.statement(step, &continuing);
                self.record = recording;
            }
            try self.analysis.loops.append(self.analysis.arena, .{ .id = loop.id, .continuing = continuing, .breaking = after });
            var body = try self.analysis.copy(continuing);
            try self.statement(loop.body, &body);
            _ = self.analysis.loops.pop();
            var next = try self.analysis.copy(after);
            next.setUnion(body);
            try self.expression(loop.condition, &next, false);
            if (next.eql(head) or round > self.analysis.current().scope.locals.len + 2) {
                live.unsetAll();
                live.setUnion(next);
                return;
            }
            head = next;
        }
    }

    fn initialize(self: *Pass, store: typed.Store, live: *Set) std.mem.Allocator.Error!void {
        const slot = @backingInt(store.slot);
        const locals = self.analysis.current().scope.locals;
        if (slot < locals.len and hidden(locals[slot]) and self.analysis.root[slot] != null) {
            // A temporary that names a place of a local is not a read of it: its uses are.
            try self.placeOperands(store.value, live);
            return;
        }
        kill(live, store.slot);
        if (store.unpack) |slots| for (slots) |field| if (field) |target| kill(live, target);
        try self.expression(store.value, live, false);
    }

    fn assign(self: *Pass, span: source.Span, store: typed.Store, live: *Set) std.mem.Allocator.Error!void {
        const target = self.analysis.rootOf(store.slot);
        if (target) |root| if (self.spine(store.value, root)) |kind| {
            // `x.f = v` and `x[i] = v` rebuild the local from itself: a partial write, which kills nothing.
            try self.write(root, span, if (store.element) .element else kind, live);
            try self.spineOperands(store.value, root, live);
            return;
        };
        try self.write(target, span, .whole, live);
        kill(live, store.slot);
        try self.expression(store.value, live, false);
    }

    /// Whether `value` rebuilds local `root` from its own storage (`update` and `replace` over a place
    /// of it), and which part it changes. Null for any other value.
    fn spine(self: *Pass, value: typed.NodeId, root: usize) ?Kind {
        var kind: Kind = .field;
        var current = value;
        var depth: usize = 0;
        while (depth < 64) : (depth += 1) switch (self.analysis.program.nodes[@backingInt(current)].data) {
            .update => |update| current = update.base,
            .replace => |replace| {
                kind = .element;
                current = replace.base;
            },
            else => {
                if (depth == 0) return null;
                const base = placeBase(self.analysis.program, current) orelse return null;
                const reached = self.analysis.rootOf(base) orelse return null;
                return if (reached == root) kind else null;
            },
        };
        return null;
    }

    /// Visit what a rebuilding value reads besides the local it rebuilds: the new field values, the
    /// indexes, and, inside a nested update, the values of its own fields.
    fn spineOperands(self: *Pass, value: typed.NodeId, root: usize, live: *Set) std.mem.Allocator.Error!void {
        const node = self.analysis.program.nodes[@backingInt(value)];
        switch (node.data) {
            .update => |update| {
                var i = update.fields.len;
                while (i != 0) {
                    i -= 1;
                    try self.spineOperands(update.fields[i].value, root, live);
                }
                try self.spineOperands(update.base, root, live);
            },
            .replace => |replace| {
                try self.spineOperands(replace.value, root, live);
                try self.expression(replace.index, live, false);
                try self.spineOperands(replace.base, root, live);
            },
            else => {
                const base = placeBase(self.analysis.program, value);
                const reached = if (base) |slot| self.analysis.rootOf(slot) else null;
                if (reached != null and reached.? == root) return self.placeOperands(value, live);
                try self.expression(value, live, false);
            },
        }
    }

    /// Visit the indexes a place expression reads, not the place itself.
    fn placeOperands(self: *Pass, id: typed.NodeId, live: *Set) std.mem.Allocator.Error!void {
        var current = id;
        while (true) switch (self.analysis.program.nodes[@backingInt(current)].data) {
            .local => return,
            .field => |field| current = field.base,
            .index => |index| {
                try self.expression(index.index, live, false);
                current = index.base;
            },
            .buffer_operation => |op| {
                var i = op.arguments.len;
                while (i != 0) {
                    i -= 1;
                    try self.expression(op.arguments[i], live, false);
                }
                return;
            },
            else => return self.expression(current, live, false),
        };
    }

    fn expressions(self: *Pass, ids: []const typed.NodeId, live: *Set) std.mem.Allocator.Error!void {
        var i = ids.len;
        while (i != 0) {
            i -= 1;
            try self.expression(ids[i], live, false);
        }
    }

    fn ordered(self: *Pass, ids: []const typed.NodeId, order: []const usize, live: *Set) std.mem.Allocator.Error!void {
        if (order.len == 0) return self.expressions(ids, live);
        var i = order.len;
        while (i != 0) {
            i -= 1;
            try self.expression(ids[order[i]], live, false);
        }
    }

    /// Carry `live` from after expression `id` to before it. `discarded` is true when the
    /// expression's value is dropped (`_ = call()` or a bare statement).
    fn expression(self: *Pass, id: typed.NodeId, live: *Set, discarded: bool) std.mem.Allocator.Error!void {
        const program = self.analysis.program;
        const node = program.nodes[@backingInt(id)];
        switch (node.data) {
            .integer, .boolean, .unit, .function_value, .blob, .task_group_open, .hole => {},
            .local => |slot| self.gen(live, slot),
            .accept_resource, .task_result => |slot| self.gen(live, slot),
            .task_submit => |submit| {
                self.gen(live, submit.group);
                try self.expression(submit.call, live, false);
            },
            .file_method => |method| {
                if (method.argument) |value| try self.expression(value, live, false);
                self.gen(live, method.owner);
            },
            .resource_io => |io| {
                if (io.value) |value| try self.expression(value, live, false);
                self.gen(live, io.owner);
            },
            .buffer_operation => |op| try self.bufferOperation(node, op, live, discarded),
            .call => |direct| try self.call(node, direct, live, discarded),
            .invoke => |indirect| {
                try self.ordered(indirect.arguments, indirect.evaluation_order, live);
                try self.expression(indirect.callee, live, false);
            },
            .place_exchange => |exchange| {
                // `take(mut x.f)` moves the place out: a read of the local, never reported.
                if (exchange.value) |value| try self.expression(value, live, false);
                if (placeBase(program, exchange.place)) |slot| self.gen(live, slot);
                try self.placeOperands(exchange.place, live);
            },
            .block_value => |block| {
                try self.expression(block.value, live, discarded);
                try self.statement(block.body, live);
            },
            .restrict_resource => |restrict| try self.expression(restrict.value, live, false),
            .dir_resource => |dir| {
                try self.expression(dir.path, live, false);
                try self.expression(dir.capability, live, false);
            },
            .host_resource => |host| {
                try self.expression(host.name, live, false);
                try self.expression(host.capability, live, false);
            },
            .environment_get => |get| {
                try self.expression(get.name, live, false);
                try self.expression(get.capability, live, false);
            },
            .environment_only => |only| {
                try self.expression(only.names, live, false);
                try self.expression(only.capability, live, false);
            },
            .environment_names, .complete_resource, .arena_escape, .cast, .wrap, .unwrap, .length => |value| try self.expression(value, live, false),
            .acquire_resource => |acquire| {
                try self.expression(acquire.request, live, false);
                try self.expression(acquire.capability, live, false);
            },
            .external_read => |read| try self.expression(read.capability, live, false),
            .stand_in => |stand| {
                if (stand.second) |second| try self.expression(second, live, false);
                try self.expression(stand.first, live, false);
            },
            .acquire_buffer => |acquire| try self.expression(acquire.capacity, live, false),
            .file_access => |access| try self.expressions(access.arguments, live),
            .print => |output| {
                if (output.terminator) |value| try self.expression(value, live, false);
                if (output.separator) |value| try self.expression(value, live, false);
                try self.expressions(output.arguments, live);
                if (output.stream) |value| try self.expression(value, live, false);
            },
            .stream_write => |output| {
                try self.expression(output.text, live, false);
                try self.expression(output.stream, live, false);
            },
            .stream_flush => |flush| try self.expression(flush.stream, live, false),
            .format => |format| {
                var i = format.pieces.len;
                while (i != 0) {
                    i -= 1;
                    switch (format.pieces[i]) {
                        .literal => {},
                        .hole => |hole| try self.expression(hole.value, live, false),
                    }
                }
            },
            .propagate => |propagate| try self.expression(propagate.value, live, false),
            .borrow_selection => |selection| {
                try self.expression(selection.second, live, false);
                try self.expression(selection.first, live, false);
            },
            .variant => |variant| if (variant.value) |value| try self.expression(value, live, false),
            .array => |values| try self.expressions(values, live),
            .record => |fields| {
                var i = fields.len;
                while (i != 0) {
                    i -= 1;
                    try self.expression(fields[i].value, live, false);
                }
            },
            .update => |update| {
                var i = update.fields.len;
                while (i != 0) {
                    i -= 1;
                    try self.expression(update.fields[i].value, live, false);
                }
                try self.expression(update.base, live, false);
            },
            .replace => |replace| {
                try self.expression(replace.value, live, false);
                try self.expression(replace.index, live, false);
                try self.expression(replace.base, live, false);
            },
            .field => |field| try self.expression(field.base, live, false),
            .index => |index| {
                try self.expression(index.index, live, false);
                try self.expression(index.base, live, false);
            },
            .unary => |unary| try self.expression(unary.operand, live, false),
            .binary => |binary| {
                try self.expression(binary.right, live, false);
                try self.expression(binary.left, live, false);
            },
            .vector_binary => |vector| {
                try self.expression(vector.right, live, false);
                try self.expression(vector.left, live, false);
            },
            .vector_neg => |vector| try self.expression(vector.operand, live, false),
            .vector_sqrt => |vector| try self.expression(vector.operand, live, false),
            .vector_convert => |vector| try self.expression(vector.operand, live, false),
            .vector_select => |selection| {
                try self.expression(selection.b, live, false);
                try self.expression(selection.a, live, false);
                try self.expression(selection.mask, live, false);
            },
            .float_fma => |fused| {
                try self.expression(fused.c, live, false);
                try self.expression(fused.b, live, false);
                try self.expression(fused.a, live, false);
            },
            .byte_load => |load| {
                try self.expression(load.offset, live, false);
                try self.expression(load.bytes, live, false);
            },
        }
    }

    fn bufferOperation(self: *Pass, node: typed.Node, op: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation"), live: *Set, discarded: bool) std.mem.Allocator.Error!void {
        const root = self.analysis.rootOf(op.owner);
        if (op.kind.writesReceiver()) {
            if (node.ty == .unit or discarded) {
                try self.write(root, node.span, self.callOrElement(node.span), live);
            } else {
                // A writer that answers a value (`pop`, `take`) reads the collection it changes.
                self.gen(live, op.owner);
            }
            var i = op.arguments.len;
            while (i != 0) {
                i -= 1;
                // `xs[i].f = v` writes an element rebuilt from itself: that rebuild reads nothing.
                if (root) |target| if (self.spine(op.arguments[i], target) != null) {
                    try self.spineOperands(op.arguments[i], target, live);
                    continue;
                };
                try self.expression(op.arguments[i], live, false);
            }
            return;
        }
        self.gen(live, op.owner);
        try self.expressions(op.arguments, live);
    }

    fn call(self: *Pass, node: typed.Node, call_node: @FieldType(@FieldType(typed.Node, "data"), "call"), live: *Set, discarded: bool) std.mem.Allocator.Error!void {
        const program = self.analysis.program;
        const callee = program.functions[@backingInt(call_node.function)];
        // A call is a dead write only when its value is dropped and every `mut` argument is a local
        // nothing reads afterwards: a call that also writes a live place or caller storage is needed
        // for that write, whatever it does to the local beside it.
        var target: ?usize = null;
        var all_dead = node.ty == .unit or discarded;
        // A call handed a capability, a file or a resource may print, write or close something: it is
        // needed for that effect, whatever it does to a local beside it.
        for (call_node.arguments) |argument| {
            if (carriesAuthority(program.records, program.nodes[@backingInt(argument)].ty, 0)) all_dead = false;
        }
        for (callee.signature.mutates) |position| {
            if (position >= call_node.arguments.len) continue;
            const base = placeBase(program, call_node.arguments[position]) orelse {
                all_dead = false;
                continue;
            };
            const root = self.analysis.rootOf(base);
            if (root == null or !self.analysis.reportable(root.?)) {
                all_dead = false;
                continue;
            }
            if (target == null) target = root;
            if (live.isSet(root.?)) all_dead = false;
        }
        // A live evaluation is noted too, so a loop's later round can clear an earlier dead one.
        if (target) |index| try self.note(index, node.span, .writer_call, all_dead);
        // The callee may read a `mut` argument, so every argument is read at the call.
        try self.ordered(call_node.arguments, call_node.evaluation_order, live);
    }

    /// `xs[i] = v` and `d[k] = v` are element writes; `sets.add(mut s, v)` and every other writer
    /// spelled as a call are writer calls. The source text at the write tells them apart.
    fn callOrElement(self: *Pass, span: source.Span) Kind {
        const bytes = self.analysis.bytes;
        if (span.end > bytes.len or span.start >= span.end) return .writer_call;
        const text = bytes[span.start..span.end];
        for (text) |ch| switch (ch) {
            '[' => return .element,
            '(' => return .writer_call,
            else => {},
        };
        return .writer_call;
    }
};

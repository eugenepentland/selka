//! Field-level effect summaries (CE2-A, docs/audits/values-keys-trap-search-plan-2026-10-07.md
//! §4.5 "CE2").
//!
//! For every function and every parameter: the field paths inside that parameter the
//! function may *read* (its result, its other parameters' final values, its traps or its
//! output may depend on them) and, for a `mut` parameter, the field paths its final value
//! may *differ in* from the value passed (its *writes*). A path is a chain of record field
//! indices from the parameter; it covers that field and everything inside it, and the
//! empty path covers the whole value.
//!
//! The summaries are transitive over the call graph: a call contributes its callee's
//! summary, prefixed by where the argument lies inside the parameter. Recursion is a
//! least fixed point over the whole module (every set starts empty and only grows).
//! Indirect calls, `extern` and runtime calls read and write everything they are given.
//!
//! A function whose declared result is a `bool` also gets *conditional* writes: the
//! paths each `mut` parameter may differ in when the function returns `True`, and when it
//! returns `False`. A handler that reports an error and answers `False` (Lox's
//! `runtime_error`, which resets the frame count) then does not count against a caller
//! that only continues when the answer is `True`.
//!
//! **Writes** come from a walk back from each return's final value: a `record_set` adds
//! its field, a `mut` call adds its callee's writes, a phi joins its operands, and any
//! value not built from the parameter that way (a fresh construction, a list update of the
//! field) adds the whole path it stands for. **Reads** come from a walk forward from the
//! parameter over the values built from it: field reads narrow the path, updates and phis
//! carry it, putting a field back into the record it came from or returning the parameter
//! as its own final value reads nothing, a call reads its callee's reads, and any other
//! use reads the whole path. Count updates and uniqueness tests read nothing.
const std = @import("std");
const ir = @import("ir.zig");

/// The analysis only allocates.
pub const Error = std.mem.Allocator.Error;

/// The most paths one set keeps before it covers the whole value.
const max_items = 16;

/// A path from a value to a field inside it: record field indices, outermost first.
pub const Path = ir.FieldPath;

/// The empty path: the whole value.
pub const whole_path: Path = .{};

/// Whether `prefix` is a prefix of (or equal to) `path`.
pub fn isPrefix(prefix: Path, path: Path) bool {
    if (prefix.len > path.len) return false;
    return std.mem.eql(u12, prefix.steps[0..prefix.len], path.steps[0..prefix.len]);
}

/// Whether two paths name overlapping bytes: one is a prefix of the other.
pub fn overlap(a: Path, b: Path) bool {
    return isPrefix(a, b) or isPrefix(b, a);
}

/// `path` followed by `step`; past `Path.max_steps` the result stays at `path`, which
/// covers the longer one.
pub fn child(path: Path, step: u32) Path {
    if (path.len >= Path.max_steps or step > std.math.maxInt(u12)) return path;
    var out = path;
    out.steps[out.len] = @intCast(step);
    out.len += 1;
    return out;
}

/// `prefix` followed by every step of `tail`, cut at `Path.max_steps` (a cut path covers
/// the longer one).
pub fn join(prefix: Path, tail: Path) Path {
    var out = prefix;
    for (tail.slice()) |step| out = child(out, step);
    return out;
}

/// A set of paths: `whole` covers every byte of the value; otherwise each path covers its
/// field and everything inside it. No path is a prefix of another.
pub const Paths = struct {
    whole: bool = false,
    items: std.ArrayList(Path) = .empty,

    /// The set covering everything.
    pub fn all() Paths {
        return .{ .whole = true };
    }

    /// Whether some path of the set overlaps `path`.
    pub fn overlaps(self: *const Paths, path: Path) bool {
        if (self.whole) return true;
        for (self.items.items) |item| if (overlap(item, path)) return true;
        return false;
    }

    /// Whether the set covers all of `path`: some member is a prefix of it.
    pub fn covers(self: *const Paths, path: Path) bool {
        if (self.whole) return true;
        for (self.items.items) |item| if (isPrefix(item, path)) return true;
        return false;
    }

    /// Add `path`; returns whether the set grew.
    pub fn add(self: *Paths, arena: std.mem.Allocator, path: Path) Error!bool {
        if (self.whole) return false;
        if (path.len == 0) {
            self.whole = true;
            self.items = .empty;
            return true;
        }
        if (self.covers(path)) return false;
        var i: usize = 0;
        while (i < self.items.items.len) {
            if (isPrefix(path, self.items.items[i])) {
                _ = self.items.swapRemove(i);
            } else i += 1;
        }
        if (self.items.items.len >= max_items) {
            self.whole = true;
            self.items = .empty;
            return true;
        }
        try self.items.append(arena, path);
        return true;
    }

    /// Add every path of `other`, each behind `prefix`; returns whether the set grew.
    pub fn addUnder(self: *Paths, arena: std.mem.Allocator, prefix: Path, other: *const Paths) Error!bool {
        if (other.whole) return self.add(arena, prefix);
        var grew = false;
        for (other.items.items) |item| {
            if (try self.add(arena, join(prefix, item))) grew = true;
        }
        return grew;
    }

    /// An independent copy.
    pub fn clone(self: *const Paths, arena: std.mem.Allocator) Error!Paths {
        return .{ .whole = self.whole, .items = .fromOwnedSlice(try arena.dupe(Path, self.items.items)) };
    }

    /// Whether both sets hold the same paths.
    pub fn same(self: *const Paths, other: *const Paths) bool {
        if (self.whole != other.whole or self.items.items.len != other.items.items.len) return false;
        for (other.items.items) |item| {
            const found = for (self.items.items) |mine| {
                if (std.meta.eql(mine, item)) break true;
            } else false;
            if (!found) return false;
        }
        return true;
    }
};

/// What a function may do to one parameter.
pub const Effect = struct {
    /// Paths whose values the function's behaviour may depend on.
    reads: Paths = .{},
    /// For a `mut` parameter, paths its final value may differ in.
    writes: Paths = .{},
    /// For a `mut` parameter of a function whose declared result is a `bool`: the writes on
    /// the returns that may answer `True`, and on those that may answer `False`.
    when_true: Paths = .{},
    when_false: Paths = .{},
};

/// Where a `mut` parameter's final value sits in the result (build.zig `returnType`): the
/// result itself, or one field of the result record.
pub const Final = union(enum) {
    whole,
    field: u32,
};

/// Where the final value of parameter `param` sits in a result of `signature`, or null for
/// a parameter that is not `mut` or a result that does not follow the convention.
pub fn finalOf(module: *const ir.Module, signature: ir.Signature, param: usize) ?Final {
    const params = signature.params;
    if (param >= params.len or param >= 64 or params.len > 64) return null;
    if (signature.owned & (@as(u64, 1) << @intCast(param)) == 0) return null;
    const owned = if (params.len == 64) signature.owned else signature.owned & ((@as(u64, 1) << @intCast(params.len)) - 1);
    const muts: u32 = @popCount(owned);
    if (muts == 1 and signature.ret == params[param]) return .whole;
    if (module.kind(signature.ret) != .record) return null;
    const fields = module.compound(signature.ret).record;
    if (fields.len != muts and fields.len != muts + 1) return null;
    if (fields.len == muts and muts < 2) return null;
    const below: u32 = @popCount(owned & ((@as(u64, 1) << @intCast(param)) - 1));
    const field: u32 = @as(u32, @intCast(fields.len - muts)) + below;
    if (fields[field] != params[param]) return null;
    return .{ .field = field };
}

/// The field of a result of `signature` that holds the declared `bool` result, or null when
/// the declared result is not a `bool` beside `mut` final values.
pub fn declaredBool(module: *const ir.Module, signature: ir.Signature) ?u32 {
    const params = signature.params;
    if (params.len > 64) return null;
    const owned = if (params.len == 64) signature.owned else signature.owned & ((@as(u64, 1) << @intCast(params.len)) - 1);
    const muts: u32 = @popCount(owned);
    if (muts == 0 or module.kind(signature.ret) != .record) return null;
    const fields = module.compound(signature.ret).record;
    if (fields.len != muts + 1 or fields[0] != .bool) return null;
    return 0;
}

/// Every function's effects on every parameter.
pub const Summaries = struct {
    /// Per function, per parameter.
    params: []const []Effect,
    /// Per function: whether it may return `True` and whether it may return `False`
    /// (functions whose declared result is a `bool` beside `mut` final values).
    may: [][2]bool,

    /// What function `function` may do to its parameter `param`.
    pub fn of(self: *const Summaries, function: usize, param: usize) *const Effect {
        return &self.params[function][param];
    }

    /// The paths `function` may write in `param` on a return that answers `answer` (null:
    /// any return).
    pub fn writes(self: *const Summaries, function: usize, param: usize, answer: ?bool) *const Paths {
        const effect = self.of(function, param);
        const known = answer orelse return &effect.writes;
        return if (known) &effect.when_true else &effect.when_false;
    }
};

/// A walk's condition: on this path, call `call`'s declared `bool` result is `value`.
pub const Condition = struct { call: ir.Ref, value: bool };

/// A dependency-validated function's immutable transitive effects.
pub const Reused = struct { params: []Effect, may: [2]bool };

/// Copy sparse effects into the owning build arena.
pub fn retain(arena: std.mem.Allocator, value: Reused) Error!Reused {
    const params = try arena.dupe(Effect, value.params);
    for (params) |*effect| {
        inline for (.{ "reads", "writes", "when_true", "when_false" }) |field| {
            const paths = &@field(effect, field);
            paths.items = .{ .items = try arena.dupe(Path, paths.items.items), .capacity = paths.items.items.len };
        }
    }
    return .{ .params = params, .may = value.may };
}

/// Compute every function's summaries.
pub fn analyze(arena: std.mem.Allocator, module: *const ir.Module) Error!Summaries {
    return analyzeReused(arena, module, &.{});
}

/// Seed validated closed dependency regions without walking their raw bodies.
pub fn analyzeReused(arena: std.mem.Allocator, module: *const ir.Module, reused: []const ?Reused) Error!Summaries {
    const count = module.functions.items.len;
    const params = try arena.alloc([]Effect, count);
    const may = try arena.alloc([2]bool, count);
    const users = try arena.alloc(?[]const []const ir.Ref, count);
    @memset(users, null);
    for (module.functions.items, params, may, 0..) |*f, *slot, *answers, index| {
        if (index < reused.len) if (reused[index]) |old| {
            std.debug.assert(old.params.len == f.signature.params.len);
            slot.* = old.params;
            answers.* = old.may;
            continue;
        };
        slot.* = try arena.alloc(Effect, f.signature.params.len);
        const opaque_body = f.signature.linkage != .internal or f.blocks.items.len == 0;
        answers.* = .{ opaque_body, opaque_body };
        for (slot.*, 0..) |*effect, i| {
            effect.* = .{};
            if (!opaque_body) continue;
            effect.reads = .all();
            if (finalOf(module, f.signature, i) != null) {
                effect.writes = .all();
                effect.when_true = .all();
                effect.when_false = .all();
            }
        }
    }
    var summaries: Summaries = .{ .params = params, .may = may };
    // Callers of each function, to revisit them when its summary grows.
    const callers = try arena.alloc(std.ArrayList(u32), count);
    @memset(callers, .empty);
    for (module.functions.items, 0..) |*f, index| {
        if (f.signature.linkage != .internal or (index < reused.len and reused[index] != null)) continue;
        for (f.insts.items) |inst| {
            if (inst.op != .call or inst.a.index() >= count) continue;
            const callee = &callers[inst.a.index()];
            if (std.mem.indexOfScalar(u32, callee.items, @intCast(index)) == null) try callee.append(arena, @intCast(index));
        }
    }
    const queued = try arena.alloc(bool, count);
    var work: std.ArrayList(u32) = .empty;
    for (module.functions.items, 0..) |*f, index| {
        queued[index] = f.signature.linkage == .internal and f.blocks.items.len != 0 and !(index < reused.len and reused[index] != null);
        if (queued[index]) try work.append(arena, @intCast(index));
    }
    std.mem.reverse(u32, work.items);
    // Each recomputation's working sets live until the next one starts.
    var scratch = std.heap.ArenaAllocator.init(arena);
    defer scratch.deinit();
    while (work.pop()) |index| {
        queued[index] = false;
        const f = &module.functions.items[index];
        if (users[index] == null) users[index] = try usersOf(arena, f);
        _ = scratch.reset(.retain_capacity);
        const pass: FunctionPass = .{ .arena = arena, .scratch = scratch.allocator(), .module = module, .f = f, .users = users[index].?, .summaries = &summaries };
        if (!try pass.update(index)) continue;
        for (callers[index].items) |caller| {
            if (queued[caller]) continue;
            queued[caller] = true;
            try work.append(arena, caller);
        }
    }
    canonicalize(&summaries);
    return summaries;
}

// A fixed point is a set of paths. Eager and seeded worklists can discover that
// set in different orders; persistence and emission must see one representation.
fn canonicalize(summaries: *const Summaries) void {
    for (summaries.params) |params| for (params) |*effect| {
        inline for (.{ "reads", "writes", "when_true", "when_false" }) |field| {
            std.mem.sort(Path, @field(effect, field).items.items, {}, pathLess);
        }
    };
}

fn pathLess(_: void, left: Path, right: Path) bool {
    return left.pack() < right.pack();
}

/// Per instruction of `f`, the instructions of reachable blocks that read it (copies resolved).
pub fn usersOf(arena: std.mem.Allocator, f: *const ir.Function) Error![]const []const ir.Ref {
    const lists = try arena.alloc(std.ArrayList(ir.Ref), f.insts.items.len);
    @memset(lists, .empty);
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |k| {
                const used = f.resolve(operands.get(k));
                if (used == .none) continue;
                const list = &lists[used.index()];
                if (list.items.len == 0 or list.items[list.items.len - 1] != ref) try list.append(arena, ref);
            }
        }
    }
    const out = try arena.alloc([]const ir.Ref, lists.len);
    for (lists, out) |list, *slot| slot.* = list.items;
    return out;
}

/// Where a value built from a parameter lies inside it.
const Origin = struct { param: u32, path: Path };

/// One function's recomputation against the current summaries.
const FunctionPass = struct {
    arena: std.mem.Allocator,
    scratch: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    users: []const []const ir.Ref,
    summaries: *Summaries,

    /// Recompute the function's summaries; returns whether any grew.
    fn update(self: FunctionPass, index: usize) Error!bool {
        var grew = false;
        const effects = self.summaries.params[index];
        const reads = try self.scratch.alloc(Paths, effects.len);
        for (reads) |*set| set.* = .{};
        try self.readsOf(reads);
        for (effects, reads) |*effect, *set| {
            if (try effect.reads.addUnder(self.arena, whole_path, set)) grew = true;
        }
        const answered = try self.answers();
        const may = &self.summaries.may[index];
        const new_true = answered[0] and !may[0];
        const new_false = answered[1] and !may[1];
        if (new_true or new_false) grew = true;
        may.* = .{ may[0] or answered[0], may[1] or answered[1] };
        for (effects, 0..) |*effect, param| {
            const final = finalOf(self.module, self.f.signature, param) orelse continue;
            var walk: Walk = .{ .pass = self, .param = @intCast(param), .final = final };
            if (try walk.returns(&effect.writes, null)) grew = true;
            if (declaredBool(self.module, self.f.signature) == null) continue;
            if (try walk.returns(&effect.when_true, true)) grew = true;
            if (try walk.returns(&effect.when_false, false)) grew = true;
        }
        return grew;
    }

    /// Whether the function may answer `True` and whether it may answer `False`.
    fn answers(self: FunctionPass) Error![2]bool {
        const field = declaredBool(self.module, self.f.signature) orelse return .{ true, true };
        var out: [2]bool = .{ false, false };
        for (self.f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            const last = self.f.inst(block.insts.items[block.insts.items.len - 1]);
            if (last.op != .ret) continue;
            const answer = try self.answerOf(last.a, field);
            out[0] = out[0] or answer[0];
            out[1] = out[1] or answer[1];
        }
        return out;
    }

    /// Whether the declared result in `result` (field `field` of the result record) may be
    /// `True` and whether it may be `False`.
    fn answerOf(self: FunctionPass, result: ir.Ref, field: u32) Error![2]bool {
        const made = self.f.inst(self.f.resolve(result));
        // A call's whole result returned as this function's (`return f(mut rt, …)`) answers as it does.
        if (made.op == .call and declaredBool(self.module, self.module.functions.items[made.a.index()].signature) == field) return self.summaries.may[made.a.index()];
        if (made.op != .record_make) return .{ true, true };
        const value = self.f.resolve(self.f.operands(made.data)[field]);
        const inst = self.f.inst(value);
        if (inst.op == .iconst and inst.ty == .bool) return .{ inst.data != 0, inst.data == 0 };
        if (inst.op == .record_get and inst.data == 0) {
            const call = self.f.inst(self.f.resolve(inst.a));
            if (call.op == .call and declaredBool(self.module, self.module.functions.items[call.a.index()].signature) != null) {
                return self.summaries.may[call.a.index()];
            }
        }
        return .{ true, true };
    }

    /// The reads of every parameter: a walk forward over the values built from each.
    fn readsOf(self: FunctionPass, reads: []Paths) Error!void {
        const f = self.f;
        const origin = try self.scratch.alloc(?Origin, f.insts.items.len);
        @memset(origin, null);
        var work: std.ArrayList(ir.Ref) = .empty;
        for (f.insts.items, 0..) |inst, i| {
            if (inst.op != .param or inst.data >= reads.len) continue;
            origin[i] = .{ .param = @intCast(inst.data), .path = whole_path };
            try work.append(self.scratch, @fromBackingInt(@intCast(i)));
        }
        var flow: Flow = .{ .pass = self, .origin = origin, .reads = reads, .work = &work };
        while (work.pop()) |value| try flow.visit(value);
    }
};

/// The forward walk of `FunctionPass.readsOf`.
const Flow = struct {
    pass: FunctionPass,
    origin: []?Origin,
    reads: []Paths,
    work: *std.ArrayList(ir.Ref),

    fn read(self: *Flow, at: Origin) Error!void {
        _ = try self.reads[at.param].add(self.pass.scratch, at.path);
    }

    /// `value` is built from a parameter at `at` too: join, and revisit it if that changed.
    fn carry(self: *Flow, value: ir.Ref, at: Origin) Error!void {
        const slot = &self.origin[value.index()];
        if (slot.*) |known| {
            if (known.param == at.param and isPrefix(known.path, at.path)) return;
            if (known.param != at.param) {
                // Built from two parameters: each is read whole at its path, and the value
                // is no longer followed.
                try self.read(known);
                try self.read(at);
                slot.* = .{ .param = known.param, .path = whole_path };
                return;
            }
            var common: Path = .{};
            for (known.path.slice(), 0..) |step, k| {
                if (k >= at.path.len or at.path.steps[k] != step) break;
                common = child(common, step);
            }
            slot.* = .{ .param = at.param, .path = common };
        } else slot.* = at;
        try self.work.append(self.pass.scratch, value);
    }

    fn visit(self: *Flow, value: ir.Ref) Error!void {
        const at = self.origin[value.index()].?;
        const f = self.pass.f;
        for (self.pass.users[value.index()]) |user| {
            const inst = f.inst(user);
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |k| {
                if (f.resolve(operands.get(k)) != value) continue;
                try self.use(user, inst, k, at);
            }
        }
    }

    /// Operand `k` (in `valueOperands` order) of `inst`, defined at `user`, is a value built
    /// from a parameter at `at`.
    fn use(self: *Flow, user: ir.Ref, inst: ir.Inst, k: usize, at: Origin) Error!void {
        const f = self.pass.f;
        const m = self.pass.module;
        switch (inst.op) {
            .retain, .release, .is_unique => {},
            .record_get => try self.carry(user, .{ .param = at.param, .path = child(at.path, @intCast(inst.data)) }),
            .record_set => {
                if (k == 0) return self.carry(user, at);
                // A field put back into the record it was read from reads nothing.
                if (self.origin[f.resolve(inst.a).index()]) |base| {
                    if (base.param == at.param and std.meta.eql(child(base.path, @intCast(inst.data)), at.path) and at.path.len > base.path.len) return;
                }
                try self.read(at);
            },
            .list_set, .list_set_field, .list_push, .list_pop, .array_set, .dict_set_value, .dict_insert, .dict_remove, .dict_clear, .buffer_set, .buffer_push, .buffer_pop => {
                if (k == 0) return self.carry(user, at);
                try self.read(at);
            },
            .list_copy, .dict_copy, .buffer_copy, .phi => try self.carry(user, at),
            .call => try self.call(user, inst, k, at),
            .ret => {
                const final = finalOf(m, f.signature, at.param);
                if (at.path.len == 0 and final != null and final.? == .whole) return;
                try self.read(at);
            },
            .record_make => {
                if (at.path.len == 0 and self.finalField(user, k, at.param)) return;
                try self.read(at);
            },
            else => try self.read(at),
        }
    }

    /// Whether `record` is only returned and its field `k` is where parameter `param`'s final value goes.
    fn finalField(self: *Flow, record: ir.Ref, k: usize, param: u32) bool {
        const f = self.pass.f;
        const final = finalOf(self.pass.module, f.signature, param) orelse return false;
        if (final != .field or final.field != k) return false;
        const users = self.pass.users[record.index()];
        if (users.len == 0) return false;
        for (users) |user| if (f.inst(user).op != .ret) return false;
        return true;
    }

    fn call(self: *Flow, user: ir.Ref, inst: ir.Inst, k: usize, at: Origin) Error!void {
        const m = self.pass.module;
        const callee = inst.a.index();
        if (callee >= m.functions.items.len) return self.read(at);
        const signature = m.functions.items[callee].signature;
        _ = try self.reads[at.param].addUnder(self.pass.scratch, at.path, &self.pass.summaries.of(callee, k).reads);
        const final = finalOf(m, signature, k) orelse return;
        switch (final) {
            .whole => try self.carry(user, at),
            .field => |field| for (self.pass.users[user.index()]) |reader| {
                const got = self.pass.f.inst(reader);
                if (got.op == .record_get and got.data == field) {
                    try self.carry(reader, at);
                } else if (got.op != .record_get) {
                    // The result record is read whole: the final value goes with it.
                    try self.read(at);
                }
            },
        }
    }
};

/// The backward walk from a function's returns to where one `mut` parameter's final value
/// came from.
const Walk = struct {
    pass: FunctionPass,
    param: u32,
    final: Final,
    seen: std.AutoHashMapUnmanaged(Key, void) = .empty,

    const Key = struct { ref: u32, component: u32, path: u64 };

    /// Add to `into` the writes of every return that may answer `answer` (null: every
    /// return); returns whether `into` grew.
    fn returns(self: *Walk, into: *Paths, answer: ?bool) Error!bool {
        const f = self.pass.f;
        var found: Paths = .{};
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            const last = f.inst(block.insts.items[block.insts.items.len - 1]);
            if (last.op != .ret or last.a == .none) continue;
            var condition: ?Condition = null;
            if (answer) |wanted| {
                const field = declaredBool(self.pass.module, f.signature).?;
                const possible = try self.pass.answerOf(last.a, field);
                if (!possible[if (wanted) 0 else 1]) continue;
                condition = self.conditionOf(last.a, field, wanted);
            }
            self.seen = .empty;
            const component: ?u32 = switch (self.final) {
                .whole => null,
                .field => |field| field,
            };
            try self.walk(&found, .{ .ref = f.resolve(last.a), .component = component, .path = whole_path, .condition = condition });
        }
        return into.addUnder(self.pass.arena, whole_path, &found);
    }

    /// When the declared result of `result` is a call's declared result: that call answered `wanted`.
    fn conditionOf(self: *Walk, result: ir.Ref, field: u32, wanted: bool) ?Condition {
        const f = self.pass.f;
        const made = f.inst(f.resolve(result));
        if (made.op == .call) return .{ .call = f.resolve(result), .value = wanted };
        if (made.op != .record_make) return null;
        const value = f.inst(f.resolve(f.operands(made.data)[field]));
        if (value.op != .record_get or value.data != 0) return null;
        const call = f.resolve(value.a);
        if (f.inst(call).op != .call) return null;
        return .{ .call = call, .value = wanted };
    }

    /// One step: the bytes of `at.ref` (its field `at.component`, when set) should be the
    /// parameter's bytes at `at.path`; add the paths where they may not be.
    const At = struct { ref: ir.Ref, component: ?u32, path: Path, condition: ?Condition };

    fn walk(self: *Walk, out: *Paths, at: At) Error!void {
        const f = self.pass.f;
        const m = self.pass.module;
        const ref = f.resolve(at.ref);
        if (self.fromParam(ref, at.component, at.path)) return;
        const inst = f.inst(ref);
        if (inst.op == .phi) {
            const key: Key = .{ .ref = @backingInt(ref), .component = at.component orelse std.math.maxInt(u32), .path = at.path.pack() };
            if ((try self.seen.getOrPut(self.pass.scratch, key)).found_existing) return;
            for (f.operands(inst.data)) |operand| try self.walk(out, .{ .ref = operand, .component = at.component, .path = at.path, .condition = at.condition });
            return;
        }
        if (at.component) |component| switch (inst.op) {
            .record_make => return self.walk(out, .{ .ref = f.operands(inst.data)[component], .component = null, .path = at.path, .condition = at.condition }),
            .record_set => {
                if (inst.data == component) return self.walk(out, .{ .ref = inst.b, .component = null, .path = at.path, .condition = at.condition });
                return self.walk(out, .{ .ref = inst.a, .component = component, .path = at.path, .condition = at.condition });
            },
            .call => return self.callFinal(out, ref, inst, component, at),
            else => {
                _ = try out.add(self.pass.scratch, at.path);
                return;
            },
        };
        switch (inst.op) {
            .record_set => {
                try self.walk(out, .{ .ref = inst.a, .component = null, .path = at.path, .condition = at.condition });
                try self.walk(out, .{ .ref = inst.b, .component = null, .path = child(at.path, @intCast(inst.data)), .condition = at.condition });
            },
            .record_get => try self.walk(out, .{ .ref = inst.a, .component = @intCast(inst.data), .path = at.path, .condition = at.condition }),
            .call => {
                const signature = m.functions.items[inst.a.index()].signature;
                const owned = signature.owned & if (signature.params.len >= 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(signature.params.len)) - 1;
                if (@popCount(owned) != 1) {
                    _ = try out.add(self.pass.scratch, at.path);
                    return;
                }
                const param: u32 = @ctz(owned);
                const final = finalOf(m, signature, param) orelse {
                    _ = try out.add(self.pass.scratch, at.path);
                    return;
                };
                if (final != .whole) {
                    _ = try out.add(self.pass.scratch, at.path);
                    return;
                }
                try self.through(out, ref, inst, param, at);
            },
            .list_copy, .dict_copy, .buffer_copy => try self.walk(out, .{ .ref = inst.a, .component = null, .path = at.path, .condition = at.condition }),
            else => _ = try out.add(self.pass.scratch, at.path),
        }
    }

    /// Field `component` of a call's result: a `mut` parameter's final value, or anything else.
    fn callFinal(self: *Walk, out: *Paths, ref: ir.Ref, inst: ir.Inst, component: u32, at: At) Error!void {
        const m = self.pass.module;
        const signature = m.functions.items[inst.a.index()].signature;
        for (signature.params, 0..) |_, param| {
            const final = finalOf(m, signature, param) orelse continue;
            if (final == .field and final.field == component) return self.through(out, ref, inst, @intCast(param), at);
        }
        _ = try out.add(self.pass.scratch, at.path);
    }

    /// The final value of the call's `mut` parameter `param`: its argument, changed where the
    /// callee writes (only where it writes when it answers as the walk's condition says).
    fn through(self: *Walk, out: *Paths, ref: ir.Ref, inst: ir.Inst, param: u32, at: At) Error!void {
        const f = self.pass.f;
        const callee = inst.a.index();
        const answer: ?bool = if (at.condition) |condition| (if (condition.call == ref) condition.value else null) else null;
        const written = self.pass.summaries.writes(callee, param, if (declaredBool(self.pass.module, self.pass.module.functions.items[callee].signature) != null) answer else null);
        _ = try out.addUnder(self.pass.scratch, at.path, written);
        const argument = f.operands(inst.data)[param];
        try self.walk(out, .{ .ref = argument, .component = null, .path = at.path, .condition = at.condition });
    }

    /// Whether `ref` (its field `component`, when set) is the parameter's own value at `path`:
    /// the parameter, or a chain of field reads of it spelling `path`.
    fn fromParam(self: *Walk, ref: ir.Ref, component: ?u32, path: Path) bool {
        const f = self.pass.f;
        var steps: [Path.max_steps + 1]u32 = undefined;
        var depth: usize = 0;
        if (component) |field| {
            steps[0] = field;
            depth = 1;
        }
        var current = ref;
        while (true) {
            const inst = f.inst(current);
            if (inst.op == .param) {
                if (inst.data != self.param) return false;
                break;
            }
            if (inst.op != .record_get or depth > Path.max_steps) return false;
            steps[depth] = @intCast(inst.data);
            depth += 1;
            current = f.resolve(inst.a);
        }
        if (depth != path.len) return false;
        for (0..depth) |i| if (steps[depth - 1 - i] != path.steps[i]) return false;
        return true;
    }
};

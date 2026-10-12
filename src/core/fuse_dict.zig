//! Pure probes of identical dictionary/key SSA values share a dominating lookup.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// Persistent views require a fresh dictionary whose identity has not escaped.
pub const ViewIdentity = enum { safe, exposed, unknown };

fn freshOrigins(arena: std.mem.Allocator, f: *ir.Function, sources: []const ir.Ref, aliases: []bool) std.mem.Allocator.Error!bool {
    var pending: std.ArrayList(ir.Ref) = .empty;
    defer pending.deinit(arena);
    try pending.appendSlice(arena, sources);
    while (pending.pop()) |raw| {
        const ref = f.resolve(raw);
        if (aliases[ref.index()]) continue;
        aliases[ref.index()] = true;
        const inst = f.inst(ref);
        switch (inst.op) {
            .dict_new => {},
            .dict_insert, .dict_set_value, .dict_remove, .dict_clear, .dict_copy => try pending.append(arena, inst.a),
            .phi => try pending.appendSlice(arena, f.operands(inst.data)),
            else => return false,
        }
    }
    return true;
}

fn anyAlias(f: *ir.Function, inst: ir.Inst, aliases: []const bool) bool {
    const operands = f.valueOperands(inst);
    for (0..operands.len()) |at| if (aliases[f.resolve(operands.get(at)).index()]) return true;
    return false;
}

fn aliasResult(f: *ir.Function, inst: ir.Inst, wrapper: bool, aliases: []const bool) bool {
    return switch (inst.op) {
        .copy, .phi => anyAlias(f, inst, aliases),
        .record_make => wrapper and anyAlias(f, inst, aliases),
        .record_get => aliases[f.resolve(inst.a).index()],
        .dict_insert, .dict_set_value, .dict_remove, .dict_clear, .dict_copy => aliases[f.resolve(inst.a).index()],
        else => false,
    };
}

fn allowedUse(m: *const ir.Module, inst: ir.Inst, at: usize, wrapper: bool) bool {
    return switch (inst.op) {
        .copy, .phi => true,
        .record_make => wrapper,
        .record_get => true,
        .dict_find, .dict_len, .dict_entries, .dict_entry_key, .dict_entry_value, .dict_entry_live => at == 0,
        .dict_insert, .dict_set_value, .dict_remove, .dict_clear, .dict_copy => at == 0,
        .call => std.mem.eql(u8, m.functions.items[inst.a.index()].name, "myl_core_dict_ordinal"),
        else => false,
    };
}

/// Refuse ordinary aggregate, opaque-call or returned aliases of a persistent view's dictionary.
pub fn viewIdentity(arena: std.mem.Allocator, f: *ir.Function, m: *const ir.Module, sources: []const ir.Ref, view_wrappers: []const ir.Ref) std.mem.Allocator.Error!ViewIdentity {
    const aliases = try arena.alloc(bool, f.insts.items.len);
    defer arena.free(aliases);
    @memset(aliases, false);
    if (sources.len == 0 or !try freshOrigins(arena, f, sources, aliases)) return .unknown;
    const wrappers = try arena.alloc(bool, f.insts.items.len);
    defer arena.free(wrappers);
    @memset(wrappers, false);
    for (view_wrappers) |ref| wrappers[ref.index()] = true;
    var changed = true;
    while (changed) {
        changed = false;
        for (f.insts.items, 0..) |inst, index| {
            if (aliases[index] or !aliasResult(f, inst, wrappers[index], aliases)) continue;
            aliases[index] = true;
            changed = true;
        }
    }
    for (f.insts.items, 0..) |inst, index| {
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (aliases[f.resolve(operands.get(at)).index()] and !allowedUse(m, inst, at, wrappers[index])) return .exposed;
        }
    }
    return .safe;
}

/// Fold repeated probes through default-value branches and within single blocks.
pub fn probes(allocator: std.mem.Allocator, function: *ir.Function) std.mem.Allocator.Error!u32 {
    const graph = try facts.shape(allocator, function);
    var folded: u32 = 0;
    for (graph.rpo) |block_id| {
        const block = function.blocks.items[block_id.index()];
        for (block.insts.items, 0..) |ref, at| {
            const inst = function.inst(ref);
            if (inst.op != .dict_find) continue;
            var ancestor: ?ir.BlockId = block_id;
            search: while (ancestor) |candidate_block| {
                const available = function.blocks.items[candidate_block.index()].insts.items;
                const limit = if (candidate_block == block_id) at else available.len;
                for (available[0..limit]) |earlier| {
                    const candidate = function.inst(earlier);
                    if (candidate.op != .dict_find) continue;
                    if (function.resolve(candidate.a) != function.resolve(inst.a) or function.resolve(candidate.b) != function.resolve(inst.b)) continue;
                    function.insts.items[ref.index()] = .{ .op = .copy, .ty = .i64, .a = earlier, .span = inst.span };
                    folded += 1;
                    break :search;
                }
                if (candidate_block.index() == 0) break;
                ancestor = graph.idom[candidate_block.index()];
            }
        }
    }
    return folded;
}

/// Sink an independent text-key copy to the insertion edge of a local update.
/// Only allocation-free scalar work may separate the source read and update;
/// snapshots, calls, source mutations, escapes and cyclic regions retain copies.
pub fn updateCopies(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    if (!module.zero_rc) return 0;
    const original = f.insts.items.len;
    // Cap both the function size and candidates: conservative fallback is cheap.
    if (original > 4096 or f.blocks.items.len > 256) return 0;
    var candidates: u32 = 0;
    var changed: u32 = 0;
    for (0..original) |index| {
        const copied = f.insts.items[index];
        if (copied.op != .call or copied.ty != .str) continue;
        candidates += 1;
        if (candidates > 32) break;
        if (!trustedTextCopy(module, copied)) continue;
        const source = f.resolve(f.operands(copied.data)[0]);
        if (f.inst(source).op != .list_get or f.inst(source).data != 0) continue;
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        const insertion = updateInsertion(module, f, ref) orelse continue;
        var usable = true;
        const insert = f.inst(insertion);
        const probe = f.resolve(insert.b);
        if (f.inst(probe).op != .dict_find or f.resolve(f.inst(probe).b) != ref) continue;
        const graph = try facts.shape(arena, f);
        // Probes must occur before the final update probe on every path. This
        // excludes observing a key after one update edge but before another.
        for (f.insts.items, 0..) |inst, use_index| {
            if (inst.op == .dict_find and f.resolve(inst.b) == ref and
                !probePrecedes(f, graph, @fromBackingInt(@as(u32, @intCast(use_index))), probe)) usable = false;
        }
        if (!usable) continue;
        var start: ?ir.BlockId = null;
        var start_at: usize = 0;
        var insert_block: ?ir.BlockId = null;
        var insert_at: usize = 0;
        for (f.blocks.items, 0..) |block, block_index| for (block.insts.items, 0..) |inst_ref, at| {
            if (inst_ref == ref) {
                start = @fromBackingInt(@as(u32, @intCast(block_index)));
                start_at = at + 1;
            }
            if (inst_ref == insertion) {
                insert_block = @fromBackingInt(@as(u32, @intCast(block_index)));
                insert_at = at;
            }
        };
        if (start == null or insert_block == null) continue;
        const states = try arena.alloc(u8, f.blocks.items.len);
        defer arena.free(states);
        @memset(states, 0);
        const seen = try arena.alloc(bool, f.insts.items.len);
        defer arena.free(seen);
        @memset(seen, false);
        var region = UpdateRegion{ .f = f, .insert = insertion, .probe = probe, .states = states, .seen = seen };
        if (!region.scan(start.?, start_at, 0)) continue;
        // Every observing use must precede an endpoint on these checked paths.
        for (f.insts.items, 0..) |inst, use_index| {
            if (inst.op == .copy) continue;
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |at| if (f.resolve(operands.get(at)) == ref and !seen[use_index]) {
                usable = false;
            };
        }
        if (!usable) continue;
        const fresh: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
        try f.insts.append(arena, copied);
        const owned_probe: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
        // Preserve the verifier's exact key/probe provenance. Only misses need
        // this second lookup; both copies and probes stay before insertion.
        try f.insts.append(arena, .{ .op = .dict_find, .ty = .i64, .a = insert.a, .b = fresh, .span = insert.span });
        try f.blocks.items[insert_block.?.index()].insts.insertSlice(arena, insert_at, &.{ fresh, owned_probe });
        const extra: u32 = @intCast(f.extra.items.len);
        const old_args = f.operands(insert.data);
        const value = old_args[1];
        try f.extra.appendSlice(arena, &.{ fresh, value });
        f.insts.items[insertion.index()].data = (ir.ExtraSlice{ .start = extra, .len = 2 }).pack();
        f.insts.items[insertion.index()].b = owned_probe;
        f.insts.items[index] = .{ .op = .copy, .ty = .str, .a = source, .span = copied.span };
        changed += 1;
    }
    return changed;
}

const UpdateRegion = struct {
    f: *const ir.Function,
    insert: ir.Ref,
    probe: ir.Ref,
    states: []u8,
    seen: []bool,

    fn scan(self: *UpdateRegion, block: ir.BlockId, begin: usize, depth: usize) bool {
        if (depth > 64 or self.states[block.index()] == 1) return false;
        if (self.states[block.index()] == 2) return true;
        self.states[block.index()] = 1;
        for (self.f.blocks.items[block.index()].insts.items[begin..]) |ref| {
            self.seen[ref.index()] = true;
            const inst = self.f.inst(ref);
            if (ref == self.insert or (inst.op == .dict_set_value and
                self.f.resolve(inst.a) == self.f.resolve(self.f.inst(self.insert).a) and
                self.f.resolve(inst.b) == self.probe))
            {
                self.states[block.index()] = 2;
                return true;
            }
            switch (inst.op) {
                .iconst, .fconst, .undef, .copy, .phi, .cmp, .fcmp, .convert, .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .not, .bit_and, .bit_or, .bit_xor, .dict_find, .dict_entry_value => {},
                .jump => {
                    if (!self.scan(@fromBackingInt(@as(u32, @intCast(inst.data))), 0, depth + 1)) return false;
                    self.states[block.index()] = 2;
                    return true;
                },
                .branch => {
                    const targets = ir.unpackTargets(inst.data);
                    if (!self.scan(targets.then, 0, depth + 1) or !self.scan(targets.otherwise, 0, depth + 1)) return false;
                    self.states[block.index()] = 2;
                    return true;
                },
                else => return false,
            }
        }
        return false;
    }
};

fn probePrecedes(f: *const ir.Function, graph: facts.Shape, earlier: ir.Ref, later: ir.Ref) bool {
    const early_block = graph.block_of[earlier.index()] orelse return false;
    const late_block = graph.block_of[later.index()] orelse return false;
    if (early_block == late_block) {
        for (f.blocks.items[early_block.index()].insts.items) |ref| {
            if (ref == earlier) return true;
            if (ref == later) return false;
        }
        return false;
    }
    var block = late_block;
    while (graph.idom[block.index()]) |parent| {
        if (parent == early_block) return true;
        if (parent == block) break;
        block = parent;
    }
    return false;
}

fn trustedTextCopy(module: *const ir.Module, copied: ir.Inst) bool {
    const callee = module.functions.items[copied.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .str) return false;
    if ((signature.owned | signature.views | signature.consumes) != 0) return false;
    if (!std.mem.eql(ir.Type, signature.params, &.{.str})) return false;
    return std.mem.eql(u8, callee.name, "myl_core_owned_octets_copy");
}

fn updateInsertion(module: *const ir.Module, f: *const ir.Function, ref: ir.Ref) ?ir.Ref {
    var insertion: ?ir.Ref = null;
    for (f.insts.items, 0..) |inst, use_index| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != ref) continue;
            if (inst.op == .dict_find and at == 1) continue;
            if (inst.op != .dict_insert or at != 2) return null;
            if (insertion != null or module.managed(module.compound(inst.ty).dict.value)) return null;
            insertion = @fromBackingInt(@as(u32, @intCast(use_index)));
        }
    }
    return insertion;
}

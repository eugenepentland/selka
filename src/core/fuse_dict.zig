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

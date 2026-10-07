//! Bounded release bodies for LLVM optimization across source units.
const std = @import("std");
const ir = @import("ir.zig");

const instruction_limit = 512;
const block_limit = 32;
const loop_block_limit = 64;
const unit_limit = 2048;

const Selection = struct {
    functions: std.ArrayList(u32) = .empty,
    visited: []bool,
    instructions: usize = 0,
    entry: bool = false,
};

/// Import calls inside loops and bounded loop bodies called from outside a loop,
/// then their direct-call closure in first-use order. Large dispatch stays separate.
pub fn select(a: std.mem.Allocator, module: *const ir.Module, owner: []const ?u32, owned: []const u32, group: u32) std.mem.Allocator.Error![]const u32 {
    var selected: Selection = .{ .visited = try a.alloc(bool, owner.len) };
    @memset(selected.visited, false);
    for (owned) |index| {
        const function = &module.functions.items[index];
        const inside = if (function.loops.items.len != 0) try loopBlocks(a, function) else null;
        for (function.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = function.inst(ref);
                if (inst.op != .call) continue;
                const target: u32 = @intCast(inst.a.index());
                if ((inside != null and inside.?[b]) or hasLoop(&module.functions.items[target])) try admit(a, module, owner, group, &selected, target);
            }
        }
    }
    try closure(a, module, owner, group, &selected);
    return selected.functions.toOwnedSlice(a);
}

/// Expose only a bounded loop-bearing entry and its consumed bodies to C main.
/// Large dispatch entries remain a call; no entry arguments are specialized here.
/// Entry-only private-copy eligibility is evaluated separately without changing IR.
pub fn entry(a: std.mem.Allocator, module: *const ir.Module, owner: []const ?u32) std.mem.Allocator.Error![]const u32 {
    if (!hasLoop(&module.functions.items[module.entry])) return &.{};
    var selected: Selection = .{ .visited = try a.alloc(bool, owner.len), .entry = true };
    @memset(selected.visited, false);
    const group = std.math.maxInt(u32);
    try admit(a, module, owner, group, &selected, module.entry);
    try closure(a, module, owner, group, &selected);
    return selected.functions.toOwnedSlice(a);
}

fn closure(a: std.mem.Allocator, module: *const ir.Module, owner: []const ?u32, group: u32, selected: *Selection) !void {
    var cursor: usize = 0;
    while (cursor < selected.functions.items.len) : (cursor += 1) {
        const function = &module.functions.items[selected.functions.items[cursor]];
        for (function.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = function.inst(ref);
                if (inst.op == .call) try admit(a, module, owner, group, selected, @intCast(inst.a.index()));
            }
        }
    }
}

fn hasLoop(function: *const ir.Function) bool {
    for (function.loops.items) |loop| if (loop.body.index() == 0 or function.blocks.items[loop.body.index()].preds.items.len != 0) return true;
    return false;
}

fn admit(a: std.mem.Allocator, module: *const ir.Module, owner: []const ?u32, group: u32, selected: *Selection, index: u32) !void {
    if (selected.visited[index]) return;
    selected.visited[index] = true;
    const function = &module.functions.items[index];
    if (owner[index] == null or owner[index] == group or function.signature.linkage != .internal) return;
    if (index == module.entry and !selected.entry) return;
    var instructions: usize = 0;
    var blocks: usize = 0;
    for (function.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        blocks += 1;
        for (block.insts.items) |ref| if (function.inst(ref).op != .copy) {
            instructions += 1;
        };
    }
    // Small loop kernels can have broad CFGs; branch-heavy dispatch remains separate.
    const allowed_blocks: usize = if (hasLoop(function)) loop_block_limit else block_limit;
    if (blocks > allowed_blocks or instructions > instruction_limit or selected.instructions + instructions > unit_limit) return;
    try selected.functions.append(a, index);
    selected.instructions += instructions;
}

fn loopBlocks(a: std.mem.Allocator, function: *const ir.Function) ![]bool {
    const inside = try a.alloc(bool, function.blocks.items.len);
    @memset(inside, false);
    // Each loop needs its own traversal: an outer loop may have marked a nested
    // header before that nested loop's exit was visited.
    const visited = try a.alloc(bool, inside.len);
    var pending: std.ArrayList(ir.BlockId) = .empty;
    for (function.loops.items) |loop| {
        @memset(visited, false);
        visited[loop.header.index()] = true;
        inside[loop.header.index()] = true;
        pending.clearRetainingCapacity();
        try pending.append(a, loop.body);
        while (pending.pop()) |block| {
            if (visited[block.index()] or block == loop.exit) continue;
            visited[block.index()] = true;
            inside[block.index()] = true;
            const insts = function.blocks.items[block.index()].insts.items;
            if (insts.len == 0) continue;
            const last = function.inst(insts[insts.len - 1]);
            switch (last.op) {
                .jump => try pending.append(a, @fromBackingInt(@intCast(@as(u32, @intCast(last.data))))),
                .branch => {
                    const targets = ir.unpackTargets(last.data);
                    try pending.append(a, targets.then);
                    try pending.append(a, targets.otherwise);
                },
                else => {},
            }
        }
    }
    return inside;
}

//! Entry scalar allocation identities and conservative pointer renderings.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");

/// Each admitted name and its allocation's position in the entry block.
pub const Plan = std.StringHashMapUnmanaged(usize);

/// A single, constant eight-byte allocation that dominates all its uses.
pub fn find(a: std.mem.Allocator, function: *const il.Function, counts: *const std.StringHashMapUnmanaged(u32)) il.Error!Plan {
    var result = try candidates(a, function, counts);
    errdefer result.deinit(a);
    if (function.blocks.items.len == 0) return result;
    const entry = function.blocks.items[0];
    for (function.blocks.items) |block| for (block.instructions.items, 0..) |instruction, position| {
        for (instruction.args, 0..) |argument, index| {
            const supported = (instruction.opcode == .loadl and index == 0) or (instruction.opcode == .storel and index == 1);
            if (supported and argument == .temp) {
                const allocated = result.get(argument.temp.name) orelse continue;
                if (block != entry or position > allocated) continue;
            }
            exclude(&result, argument);
        }
        switch (instruction.extra) {
            .target => |target| excludeTarget(&result, target),
            .phi => |inputs| for (inputs) |input| exclude(&result, input.value),
            else => {},
        }
    };
    return result;
}

/// Direct addresses of entry allocations; integer values and escapes remain.
pub fn addresses(a: std.mem.Allocator, function: *const il.Function, counts: *const std.StringHashMapUnmanaged(u32)) il.Error!Plan {
    var result = try candidates(a, function, counts);
    errdefer result.deinit(a);
    if (function.blocks.items.len == 0) return result;
    for (function.blocks.items[0].instructions.items, 0..) |instruction, position| {
        const early: Early = .{ .plan = &result, .position = position };
        for (instruction.args) |argument| early.operand(argument);
        switch (instruction.extra) {
            .target => |target| early.target(target),
            .phi => |inputs| for (inputs) |input| early.operand(input.value),
            else => {},
        }
    }
    return result;
}

fn candidates(a: std.mem.Allocator, function: *const il.Function, counts: *const std.StringHashMapUnmanaged(u32)) il.Error!Plan {
    var result: Plan = .empty;
    errdefer result.deinit(a);
    if (function.blocks.items.len == 0) return result;
    const entry = function.blocks.items[0];
    if (reentered(function, entry.label)) return result;
    for (entry.instructions.items, 0..) |instruction, position| {
        if (terminal(instruction.opcode)) break;
        const name = instruction.dest orelse continue;
        if ((counts.get(name) orelse 0) != 1 or !scalarAllocation(instruction)) continue;
        try result.put(a, name, position);
    }
    return result;
}

/// Conservatively retain the old lowering if any entry use precedes allocation.
const Early = struct {
    plan: *Plan,
    position: usize,

    fn operand(self: Early, argument: il.Operand) void {
        switch (argument) {
            .temp => |reference| self.name(reference.name),
            .call => |call| {
                self.target(call.target);
                for (call.args) |nested| self.operand(nested);
            },
            else => {},
        }
    }

    fn target(self: Early, value: il.Target) void {
        if (value == .indirect) self.name(value.indirect);
    }

    fn name(self: Early, value: []const u8) void {
        const allocated = self.plan.get(value) orelse return;
        if (self.position <= allocated) _ = self.plan.remove(value);
    }
};

fn scalarAllocation(instruction: *const il.Instruction) bool {
    if (instruction.opcode != .alloc8 and instruction.opcode != .alloc16) return false;
    if (instruction.qbe_type == null or !std.mem.eql(u8, instruction.qbe_type.?, "l")) return false;
    if (instruction.args.len != 1 or instruction.args[0] != .constant) return false;
    const size = instruction.args[0].constant;
    if (size.qbe_type != null and std.mem.eql(u8, size.qbe_type.?, "extern")) return false;
    return il.pythonInt(size.text) == 8;
}

/// No allocation in a repeated or ambiguously named first block is admitted.
fn reentered(function: *const il.Function, label: []const u8) bool {
    for (function.blocks.items, 0..) |block, index| {
        if (index != 0 and std.mem.eql(u8, block.label, label)) return true;
        for (block.instructions.items) |instruction| switch (instruction.extra) {
            .label => |target| if (std.mem.eql(u8, target, label)) return true,
            .branch => |targets| for (targets) |target| if (std.mem.eql(u8, target, label)) return true,
            else => {},
        };
    }
    return false;
}

fn terminal(opcode: il.Opcode) bool {
    return opcode == .jmp or opcode == .jnz or opcode == .ret or opcode == .hlt;
}

/// Include nested call arguments and indirect targets in the escape check.
fn exclude(plan: *Plan, argument: il.Operand) void {
    switch (argument) {
        .temp => |reference| _ = plan.remove(reference.name),
        .call => |call| {
            excludeTarget(plan, call.target);
            for (call.args) |nested| exclude(plan, nested);
        },
        else => {},
    }
}

fn excludeTarget(plan: *Plan, target: il.Target) void {
    switch (target) {
        .indirect => |name| _ = plan.remove(name),
        else => {},
    }
}

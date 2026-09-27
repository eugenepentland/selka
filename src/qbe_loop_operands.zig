//! Optional word-storage isolation of an already accepted quiet loop copy.
const facts = @import("qbe_loop_facts.zig");
const sources = @import("ownership_sources.zig");
const typed = @import("typed.zig");
const reads = @import("qbe_rc_read_version.zig");
const byte_reads = @import("qbe_rc_byte_version.zig");
const text = @import("qbe_loop_operand_text.zig");
const runtime = @import("runtime_mode.zig");

/// Rewrite only complete certified regions, after all original uses are known.
pub fn finish(comptime E: type, self: *E, input: []u8) reads.Error![]u8 {
    if (!runtime.enabled() or self.heap_frame) return input;
    return text.rewrite(self.allocator, input);
}

/// Keep existing eligibility and guards; isolation is a separate refusal.
pub fn certify(comptime E: type, self: *E, loop: *const facts.Loop, proof: ?reads.Certificate, body: []const u8) bool {
    if (!runtime.enabled() or self.heap_frame) return false;
    if (self.loop_plan.loops.len > text.max_regions) return false;
    if (!reads.quietCopy(body)) return false;
    return closed(self.function.scope.instructions, self.states, loop, if (proof) |p| p.bytes else .{});
}

/// The validated stack is empty at every boundary of the isolated region.
pub fn closed(code: []const @import("bytecode.zig").Instruction, states: []const ?[]const typed.Type, loop: *const facts.Loop, bytes: byte_reads.Certificate) bool {
    if (code.len > 4096 or states.len != code.len or loop.back < loop.head or loop.back + 1 >= code.len) return false;
    if (loop.back - loop.head > facts.max_body or loop.actions.len != loop.back - loop.head + 1) return false;
    if (!empty(states, loop.head)) return false;
    if (!empty(states, loop.back) or !empty(states, loop.back + 1)) return false;
    if (code[loop.back].op != .jump or code[loop.back].op.jump != loop.head) return false;
    const context: Edges = .{ .states = states, .loop = loop };
    var budget: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (!byte_reads.charge(&budget, 1)) return false;
        const inside = pc >= loop.head and pc <= loop.back;
        if (inside) {
            const stack = states[pc] orelse return false;
            if (stack.len > text.max_words or !byte_reads.charge(&budget, stack.len)) return false;
            for (stack, 0..) |ty, index| if (!plain(ty) and !bytes.borrowed(pc, index)) return false;
            if (loop.actions[pc - loop.head].dead) continue;
        }
        if (instruction.op == .switch_variant and !byte_reads.charge(&budget, instruction.op.switch_variant.arms.len)) return false;
        if (!sources.targetsSatisfy(instruction.op, pc, context, edge)) return false;
        const taken = inside and loop.actions[pc - loop.head].effect == .taken;
        if (!taken and sources.fallsThrough(instruction.op) and pc + 1 < code.len) {
            if (!edge(pc, pc + 1, context)) return false;
        }
    }
    return true;
}

const Edges = struct { states: []const ?[]const typed.Type, loop: *const facts.Loop };
fn edge(from: usize, target: usize, context: Edges) bool {
    const loop = context.loop;
    const inside = from >= loop.head and from <= loop.back;
    if (!inside) return target <= loop.head or target > loop.back;
    if (target >= loop.head and target <= loop.back) return !loop.actions[target - loop.head].dead;
    return target == loop.back + 1 and empty(context.states, target);
}
fn empty(states: []const ?[]const typed.Type, pc: usize) bool {
    if (pc >= states.len) return false;
    const stack = states[pc] orelse return false;
    return stack.len == 0;
}
fn plain(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}

/// Delimit just the accepted body; guards and the original copy stay outside.
pub fn begin(comptime E: type, self: *E, loop: *const facts.Loop) reads.Error!void {
    try self.print(" # RC-LOOP-OPERANDS-BEGIN {d} {d}\n", .{ loop.head, loop.back });
}
/// End a complete isolated candidate before the original header is emitted.
pub fn end(comptime E: type, self: *E, loop: *const facts.Loop) reads.Error!void {
    try self.print(" # RC-LOOP-OPERANDS-END {d} {d}\n", .{ loop.head, loop.back });
}

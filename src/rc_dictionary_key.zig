//! Bounded CFG and explicit writer checks for one anchored dictionary key.
const bytecode = @import("bytecode.zig");
const tail = @import("rc_dictionary_tail.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// Recover the one list read and its one capture; no semantic role implies O.
pub fn discover(code: []const bytecode.Instruction, proof: tail.Certificate) ?tail.Key {
    const key_store = definition(code, proof.key) orelse return null;
    if (key_store == 0 or key_store >= proof.start) return null;
    const read = code[key_store - 1].op;
    if (read != .buffer_operation or read.buffer_operation.kind != .read) return null;
    const receiver = @backingInt(read.buffer_operation.owner);
    const capture = definition(code, receiver) orelse return null;
    if (capture == 0 or capture >= key_store - 1 or code[capture - 1].op != .load_local) return null;
    return .{ .anchor = .{ .storage = @fromBackingInt(@intCast(@backingInt(code[capture - 1].op.load_local))) }, .receiver = receiver, .capture = capture, .projection = key_store - 1 };
}

/// A unique static ordinary store is necessary, but not itself a lifetime proof.
pub fn definition(code: []const bytecode.Instruction, local: usize) ?usize {
    var result: ?usize = null;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == local) {
            if (result != null) return null;
            result = pc;
        },
        .move_local, .ref_local, .drop_local => |id| if (@backingInt(id) == local) return null,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == local) return null;
        },
        else => {},
    };
    return result;
}

/// Keep each raw local's complete use set inside the single closed interval.
pub fn uses(code: []const bytecode.Instruction, proof: tail.Certificate, key: tail.Key) bool {
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .load_local => |id| {
            const local = @backingInt(id);
            if (local == key.receiver) return false;
            if (local == proof.key and (pc <= key.projection + 1 or pc > proof.start + 4)) return false;
        },
        .buffer_operation => |operation| {
            const owner = @backingInt(operation.owner);
            if (owner == proof.key) return false;
            if (owner != key.receiver) continue;
            if (operation.kind == .read) {
                if (pc != key.projection) return false;
            } else if (operation.kind != .length or pc <= key.capture or pc >= key.projection) return false;
        },
        else => {},
    };
    return true;
}

/// Source publication dominates capture. Only forward index-normalization
/// branches may occur within the interval; no outside entry skips a producer.
pub fn flow(code: []const bytecode.Instruction, key: tail.Key, definition_pc: usize, end: usize) bool {
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .jump, .jump_if_false => |target| if (!edge(key, definition_pc, end, pc, target)) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (!edge(key, definition_pc, end, pc, arm.target)) return false;
        },
        .try_result => |propagate| if (!edge(key, definition_pc, end, pc, propagate.error_target)) return false,
        else => {},
    };
    return true;
}
fn edge(key: tail.Key, definition_pc: usize, end: usize, pc: usize, target: usize) bool {
    if (pc < definition_pc and target > definition_pc) return false;
    if (target <= definition_pc and definition_pc <= pc) return false;
    const start = key.capture - 1;
    if (pc >= start and pc <= end) return target > pc and target <= key.projection;
    return target <= start or target > end;
}

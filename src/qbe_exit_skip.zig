//! RC-EXIT-SKIP-1: which function's return is the last guest work a process does.
//!
//! An RC frame releases its owners one by one when it returns. For the program's
//! entry that is pure cost once the process is about to exit, so the entry's
//! frame asks the runtime (`myl_qbe_exit_skip`) whether to keep them. That is
//! only sound for a function that runs once, at the bottom of the guest stack,
//! and this file proves it from the instruction program.
const std = @import("std");
const bytecode = @import("bytecode_model.zig");
const entry_adapter = @import("entry_adapter.zig");

/// Whether `index` runs at most once and returns last: the program's entry when
/// no instruction calls it or takes it as a value, or the one function the
/// synthesized `<entry>` wrapper calls when only that call names it. A `main`
/// that calls itself, or is passed as a function value, is neither.
pub fn last(program: bytecode.Program, index: usize) bool {
    const main: usize = @backingInt(program.main);
    if (main >= program.functions.len or index >= program.functions.len) return false;
    if (index == main) return references(program, main) == 0;
    const wrapper = program.functions[main];
    if (!std.mem.eql(u8, wrapper.name, entry_adapter.wrapper_name)) return false;
    const callee = onlyCallee(wrapper) orelse return false;
    return callee == index and references(program, main) == 0 and references(program, index) == 1;
}

/// The function `wrapper` calls, when it makes exactly one call.
fn onlyCallee(wrapper: bytecode.Function) ?usize {
    var found: ?usize = null;
    for (wrapper.scope.instructions) |instruction| switch (instruction.op) {
        .call => |callee| {
            if (found != null) return null;
            found = @backingInt(callee);
        },
        else => {},
    };
    return found;
}

/// How many instructions of the program call `target` or make it a function value.
fn references(program: bytecode.Program, target: usize) usize {
    var total: usize = 0;
    for (program.functions) |function| for (function.scope.instructions) |instruction| switch (instruction.op) {
        .call => |callee| total += @intFromBool(@backingInt(callee) == target),
        .function_value => |value| total += @intFromBool(@backingInt(value.function) == target),
        else => {},
    };
    return total;
}

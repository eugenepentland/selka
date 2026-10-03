//! Resolve nested inline provenance without losing the original instruction.
const bytecode = @import("bytecode_model.zig");

/// The original instruction and the number of removed frames surrounding it.
pub const Site = struct { function: bytecode.Function, pc: usize, depth: usize };

/// Follow a bounded, acyclic inline chain. The leaf's instruction stream is
/// stable once it contains no calls, so its local PCs remain valid in callers.
pub fn resolve(program: bytecode.Program, function: bytecode.Function, pc: usize) error{InternalError}!Site {
    var site = Site{ .function = function, .pc = pc, .depth = 0 };
    while (true) {
        const code = site.function.scope.instructions;
        if (site.pc >= code.len or site.depth >= program.functions.len) return error.InternalError;
        const origin = code[site.pc].inline_origin orelse return site;
        const callee = @backingInt(origin.callee);
        if (callee >= program.functions.len) return error.InternalError;
        site = .{ .function = program.functions[callee], .pc = origin.callee_pc, .depth = site.depth + 1 };
    }
}

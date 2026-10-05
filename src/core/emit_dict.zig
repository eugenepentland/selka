//! Dictionary operation dispatch; S2-D fills these layout-independent stubs.
const ir = @import("ir.zig");

/// Allocation or an unsupported IR representation can stop operation emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Emit a valid placeholder that traps E_CORE_UNSUPPORTED when executed.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    try context.unsupported(out, name, inst);
}

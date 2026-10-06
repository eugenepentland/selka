//! S3 mutable-byte dispatch. Source admission waits for S3-T2's runtime and COW tests.
const ir = @import("ir.zig");

/// Emit valid LLVM that refuses a pending byte operation before its result is used.
pub fn instruction(context: anytype, out: anytype, name: []const u8, inst: ir.Inst) error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction }!void {
    return context.unsupported(out, name, inst);
}

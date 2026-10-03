//! Logical frame admission for call-free bodies spliced by the bytecode inliner.
const inline_site = @import("bytecode_inline_site.zig");

/// Native emission and malformed inline provenance failures.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Check a removed call only in builds retaining frame accounting. Inline
/// bodies contain no guest calls, so the physical counter stays unchanged;
/// nested markers include their statically known inline ancestors instead.
pub fn enter(comptime E: type, self: *E, pc: usize) Error!void {
    if (!self.frame_checks or !self.function.scope.instructions[pc].inline_entry) return;
    const extra = 1 + (try inline_site.resolve(self.program, self.function, pc)).depth;
    const frames_slot = self.temp();
    const frames = self.temp();
    const limit_slot = self.temp();
    const limit = self.temp();
    const room = self.temp();
    const full = self.temp();
    const label = self.temp();
    // Physical frame admission maintains frames <= limit. Subtracting first
    // avoids overflow even when the configured ceiling is UINT64_MAX.
    try self.print(" %v{d} =l add %ctx, 8\n %v{d} =l loadl %v{d}\n %v{d} =l add %ctx, 56\n %v{d} =l loadl %v{d}\n", .{ frames_slot, frames, frames_slot, limit_slot, limit, limit_slot });
    try self.print(" %v{d} =l sub %v{d}, %v{d}\n %v{d} =l cultl %v{d}, {d}\n", .{ room, limit, frames, full, room, extra });
    try self.print(" jnz %v{d}, @inlinefull{d}, @inlineadmit{d}\n@inlinefull{d}\n call $myl_qbe_fail_frame(l %ctx)\n jmp @failure\n@inlineadmit{d}\n", .{ full, label, label, label, label });
}

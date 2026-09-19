//! QBE lowering of managed arena scopes. The native heap owns the region depth,
//! so `begin_arena` and `end_arena` are context calls, `escape` is one deep copy
//! into the enclosing region, and the store barrier is a call emitted before any
//! reference store whose element type can hold a collected reference. A frame
//! records its entry depth and restores it on return and while unwinding, so a
//! trap, `?` propagation, `break`/`continue` or host allocation failure closes
//! exactly the scopes that frame opened.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Failures reported while emitting native arena instructions.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const escape_failure = "myl_qbe_fail_arena_escape";
const restore_region = " call $myl_qbe_region_restore(l %ctx, l %region_mark)\n";

/// Whether any function in the program opens an arena scope, so an arena-free
/// program pays neither the store barrier nor the per-frame depth bookkeeping.
pub fn present(program: bytecode.Program) bool {
    for (program.functions) |function| {
        for (function.scope.instructions) |instruction| if (instruction.op == .begin_arena) return true;
    }
    return false;
}

/// Bind arena lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Record the frame's entry arena depth for unwinding.
        pub fn mark(self: *E) Error!void {
            if (!self.arenas) return;
            try self.print(" %region_mark =l call $myl_qbe_region_mark(l %ctx)\n", .{});
        }
        /// Close every arena this frame opened, on return or while unwinding.
        pub fn restore(self: *E) Error!void {
            if (!self.arenas) return;
            try self.print(restore_region, .{});
        }
        /// Reject a managed reference store that would outlive its arena.
        pub fn barrier(self: *E, container: usize, ty: typed.Type, value: usize) Error!void {
            if (!self.arenas or !(try self.layout(ty)).trace) return;
            const ok = self.temp();
            try self.print(" %v{d} =w call $myl_qbe_region_check(l %ctx, l %v{d}, l extern ${s}, l %v{d})\n", .{ ok, container, try self.descriptor(ty), value });
            try self.require(ok, escape_failure);
        }
        /// Lower one arena scope boundary or `escape` copy.
        pub fn emit(self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
            switch (op) {
                .begin_arena => try self.print(" call $myl_qbe_region_begin(l %ctx)\n", .{}),
                .end_arena => |watermark| try emitEnd(E, self, @backingInt(watermark)),
                .arena_escape => |ty| try emitEscape(E, self, ty, stack),
                else => return error.InternalError,
            }
        }
    };
}

/// Scan the bindings declared before the block, release the ones declared inside
/// it, then free the whole depth without tracing the survivors.
fn emitEnd(comptime E: type, self: *E, watermark: usize) Error!void {
    const locals = self.function.scope.locals;
    const scanned = @min(watermark, locals.len);
    for (locals[0..scanned], 0..) |local, index| {
        if (!(try self.layout(local.ty)).trace) continue;
        const retained = self.temp();
        try self.print(" %v{d} =w call $myl_qbe_region_retains(l %ctx, l extern ${s}, l %l{d})\n", .{ retained, try self.descriptor(local.ty), index });
        const label = self.temp();
        try self.print(" jnz %v{d}, @outlives{d}, @kept{d}\n@outlives{d}\n call ${s}(l %ctx)\n jmp @failure\n@kept{d}\n", .{ retained, label, label, label, escape_failure, label });
    }
    // Bindings introduced inside the block die with it; clearing their slots keeps
    // a released arena object out of the next frame-root scan.
    var index = locals.len;
    while (index > scanned) {
        index -= 1;
        const value = try self.layout(locals[index].ty);
        if (value.trace) try self.zeroTracedLocal(index, locals[index].ty);
    }
    try self.print(" call $myl_qbe_region_end(l %ctx)\n", .{});
}

fn emitEscape(comptime E: type, self: *E, ty: typed.Type, stack: []const typed.Type) Error!void {
    const base = stack.len - 1;
    const source = self.temp();
    if (self.isScalar(ty)) try self.print(" %v{d} =l copy %s{d}\n", .{ source, base }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ source, base });
    const output = try self.aggregatePointer();
    const copied = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_region_escape(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ copied, try self.descriptor(ty), source, output });
    try self.checkFailure("failure");
    try self.store(base, try self.readValue(output, ty));
}

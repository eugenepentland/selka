//! QBE lowering of `value_copy` (`VALUE-SEMANTICS-2`): the one place a
//! value-semantics copy becomes code. The ownership analysis decided, per
//! instruction, whether the copy is real (`ownership_values.zig`); a move or a
//! borrow emits nothing. A real copy places the operand in this pc's aggregate
//! scratch through the single runtime entry `myl_qbe_cow_transfer`
//! (`qbe_cow_runtime.c`). It marks the value's directly held mutable
//! collection payloads shared, or the children of an already-fresh outer
//! collection. The operand becomes the scratch; moves and borrows do nothing.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

/// Failures the emitter reports: the same set as `qbe.GenerateError`.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Bind the copy lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Whether the `value_copy` at `pc` makes a real copy. Without an
        /// ownership answer for it, it does.
        pub fn copies(self: *const E, pc: usize) bool {
            const analysis = self.ownership orelse return true;
            return pc >= analysis.copies.len or analysis.copies[pc];
        }
        /// Lower one `value_copy` over the operand on top of `stack`.
        pub fn emit(self: *E, copy: bytecode.ValueCopy, stack: []const typed.Type) Error!void {
            if (!copies(self, self.pc)) return;
            const base = stack.len - 1;
            const source = self.temp();
            // A one-word value is its operand slot's own contents; any wider
            // aggregate sits behind the address the slot holds.
            if (self.isScalar(copy.ty)) try self.print(" %v{d} =l copy %s{d}\n", .{ source, base }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ source, base });
            const output = try self.aggregatePointer();
            const copied = self.temp();
            // extend, update and keyed sorted copy elements into a fresh destination.
            // Their source collection stays in place; share its children,
            // not its outer payload. Ordinary element stores share the outer
            // element instead.
            var children: u8 = @intFromBool(copy.site == .children);
            if (copy.site == .store) {
                const code = self.function.scope.instructions;
                if (self.pc + 1 < code.len) switch (code[self.pc + 1].op) {
                    .buffer_operation => |operation| if (operation.kind == .extend or operation.kind == .update) {
                        children = 2;
                    },
                    else => {},
                };
                if (self.pc + 3 < code.len and code[self.pc + 1].op == .load_local and code[self.pc + 2].op == .load_local) switch (code[self.pc + 3].op) {
                    .buffer_operation => |operation| if (operation.kind == .sort_keyed) {
                        children = 2;
                    },
                    else => {},
                };
            }
            try self.print(" %v{d} =w call $myl_qbe_cow_transfer(l %ctx, l extern ${s}, l %v{d}, l %v{d}, w {d})\n", .{ copied, try self.descriptor(copy.ty), source, output, children });
            try self.checkFailure("failure");
            try self.store(base, try self.readValue(output, copy.ty));
        }
    };
}

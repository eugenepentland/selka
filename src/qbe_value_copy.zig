//! QBE lowering of `value_copy` (`VALUE-SEMANTICS-2`): the one place a
//! value-semantics copy becomes code. The ownership analysis decided, per
//! instruction, whether the copy is real (`ownership_values.zig`); a move or a
//! borrow emits nothing. A real copy places the operand in this pc's aggregate
//! scratch and marks its directly held mutable collection payloads shared.
//! Fixed flat values mark up to eight leaves inline; pinned leaves, recursive
//! boxes, variants and fresh-children operations use the rooted entry
//! `myl_qbe_cow_transfer` (`qbe_cow_runtime.c`). The operand becomes the
//! scratch; moves and borrows do nothing.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const cow = @import("qbe_cow.zig");

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
            if (!try inlineTransfer(E, self, copy.ty, source, output, children)) {
                const copied = self.temp();
                try self.print(" %v{d} =w call $myl_qbe_cow_transfer(l %ctx, l extern ${s}, l %v{d}, l %v{d}, w {d})\n", .{ copied, try self.descriptor(copy.ty), source, output, children });
                try self.checkFailure("failure");
            }
            try self.store(base, try self.readValue(output, copy.ty));
        }
    };
}

/// A fixed record/array of at most eight collection pointers needs no
/// descriptor walk. Copy into private scratch, check every leaf before marking
/// any, then set SHARED inline. A pinned or immortal leaf takes the rooted
/// runtime path, which can replace pinned descendants in that private copy.
fn inlineTransfer(comptime E: type, self: *E, ty: typed.Type, source: usize, output: usize, children: u8) Error!bool {
    if (children != 0) return false;
    const leaves = try cow.valueLeaves(E, self, ty) orelse return false;
    try self.print(" blit %v{d}, %v{d}, {d}\n", .{ source, output, (try self.layout(ty)).size });
    if (leaves.len == 0) return true;
    const slow = self.temp();
    var headers: [8]usize = undefined;
    var words: [8]usize = undefined;
    for (leaves.offsets[0..leaves.len], 0..) |offset, index| {
        const address = try self.address(output, offset);
        const payload = try self.load("v", address);
        const present = self.temp();
        try self.print(" jnz %v{d}, @vcpresent{d}, @vcslow{d}\n@vcpresent{d}\n", .{ payload, present, slow, present });
        headers[index] = self.temp();
        words[index] = self.temp();
        const unsafe = self.temp();
        try self.print(" %v{d} =l sub %v{d}, 16\n %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, {d}\n", .{ headers[index], payload, words[index], headers[index], unsafe, words[index], cow.pinned_flag | 2 });
        const next = self.temp();
        try self.print(" jnz %v{d}, @vcslow{d}, @vcnext{d}\n@vcnext{d}\n", .{ unsafe, slow, next, next });
    }
    for (headers[0..leaves.len], words[0..leaves.len]) |header, word| {
        if (self.cow.?.counting) try self.print(" call $myl_native_cow_tally(w 0)\n", .{});
        const shared = self.temp();
        try self.print(" %v{d} =l or %v{d}, {d}\n storel %v{d}, %v{d}\n", .{ shared, word, cow.shared_flag, shared, header });
    }
    const done = self.temp();
    try self.print(" jmp @vcdone{d}\n@vcslow{d}\n", .{ done, slow });
    const copied = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_cow_transfer(l %ctx, l extern ${s}, l %v{d}, l %v{d}, w 0)\n", .{ copied, try self.descriptor(ty), source, output });
    try self.checkFailure("failure");
    try self.print("@vcdone{d}\n", .{done});
    return true;
}

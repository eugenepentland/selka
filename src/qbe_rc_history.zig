//! Semantic SHARE events use the same decision and event position as the GC lane.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const loans = @import("qbe_rc_loans.zig");
const slots = @import("qbe_rc_slots.zig");
/// Native emitter failures shared with transactional slot publication.
pub const Error = slots.Error;
/// A semantic event's physical source and owning-or-loaned journal token.
pub const Event = struct { ty: typed.Type, source: usize, journal: usize, mode: u8 };

/// Select direct, fresh-child, or source-child history exactly as value_copy does.
pub fn mode(comptime E: type, self: *E, copy: bytecode.ValueCopy) u8 {
    if (copy.site == .children) return 1;
    if (copy.site != .store) return 0;
    const code = self.function.scope.instructions;
    if (self.pc + 1 < code.len) switch (code[self.pc + 1].op) {
        .buffer_operation => |operation| if (operation.kind == .extend or operation.kind == .update) return 2,
        else => {},
    };
    if (self.pc + 3 < code.len and code[self.pc + 1].op == .load_local and code[self.pc + 2].op == .load_local)
        switch (code[self.pc + 3].op) {
            .buffer_operation => |operation| if (operation.kind == .sort_keyed) return 2,
            else => {},
        };
    return 0;
}

/// Commit history before releasing anchors or evaluating any later expression.
/// Private loans copy into O; only guarded ordinary owners may be consumed.
pub fn prepare(comptime E: type, self: *E, event: Event) Error!void {
    const take = try loans.owner(E, self, event.journal);
    const selected = self.temp();
    const mode_value = self.temp();
    const result = self.temp();
    const region = try frame.region(E, self);
    try self.print(" %v{d} =w mul %v{d}, 4\n %v{d} =w or %v{d}, {d}\n", .{ selected, take, mode_value, selected, event.mode });
    const glue = @import("qbe_rc_glue.zig");
    if (try glue.routed(E, self, event.ty)) {
        const work = self.temp();
        try self.print(" %v{d} =l copy %rcwork\n", .{work});
        try glue.publish(E, self, .{ .move = .{ .ty = event.ty, .destination = work, .source = event.source, .region = region }, .mode = mode_value });
    } else {
        try self.print(" %v{d} =w call $myl_rc_native_publish(l %heap, l extern ${s}, l %rcwork, l %v{d}, w %v{d}, w %v{d})\n", .{
            result, try self.descriptor(event.ty), event.source, region, mode_value,
        });
        try slots.requireSuccess(E, self, result);
    }
    const label = self.temp();
    try self.print(" jnz %v{d}, @rchtaken{d}, @rchcopied{d}\n@rchcopied{d}\n", .{ take, label, label, label });
    try frame.drop(E, self, event.journal);
    try self.print(" jmp @rchprepared{d}\n@rchtaken{d}\n", .{ label, label });
    try frame.initialized(E, self, event.journal, false);
    try self.print("@rchprepared{d}\n", .{label});
    try frame.stableEntry(E, self, frame.pending(E, self), event.ty);
    try frame.initialized(E, self, frame.pending(E, self), true);
}

//! Non-sharing RC holds for call arguments and pending receiver projections.
const unique = @import("qbe_rc_unique.zig");
/// Native emitter failures.
pub const Error = unique.Error;
/// Typed pending path; its stack request is reused only between synchronous calls.
pub const Place = struct { scope: usize, address: usize, container: ?usize, path: usize, count: usize, loan: ?usize = null };

/// Address the frame's single non-overlapping outgoing-call scope.
pub fn callAddress(comptime E: type, self: *E) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l copy %rccall\n", .{result});
    return result;
}
/// Address a pending receiver's dedicated scope, retained through its mutation.
pub fn receiverAddress(comptime E: type, self: *E, fill: usize) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l copy %cowscope{d}\n", .{ result, fill });
    return result;
}
/// Address a receiver loan's own lifetime scope, separate from path preparation.
pub fn borrowAddress(comptime E: type, self: *E, local: usize) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l copy %rcborrow{d}\n", .{ result, local });
    return result;
}
/// Link before the first fallible pin; frame unwind owns every partial journal.
pub fn begin(comptime E: type, self: *E, scope: usize) Error!void {
    try self.print(" call $myl_qbe_rc_scope_begin(l %ctx, l %v{d})\n", .{scope});
}
/// Restore prior pin bits before releasing this scope's lifetime holds.
pub fn end(comptime E: type, self: *E, scope: usize) Error!void {
    try self.print(" call $myl_qbe_rc_scope_end(l %ctx, l %v{d})\n", .{scope});
}
/// Keep the header and any captured collection backing alive without sharing it.
pub fn pin(comptime E: type, self: *E, scope: usize, payload: usize) Error!void {
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_rc_scope_pin(l %ctx, l %v{d}, l %v{d})\n", .{ done, scope, payload });
    try unique.success(E, self, done);
}
/// Detach the finite pending path and retain every selected candidate leaf.
pub fn prepare(comptime E: type, self: *E, place: Place) Error!void {
    const request = self.temp();
    try self.print(" %v{d} =l copy %rcplace\n storel %v{d}, %v{d}\n", .{ request, place.address, request });
    const container = try self.address(request, 8);
    if (place.container) |value| {
        try self.print(" storel %v{d}, %v{d}\n", .{ value, container });
    } else try self.print(" storel 0, %v{d}\n", .{container});
    try self.print(" storel %v{d}, %v{d}\n", .{ place.path, try self.address(request, 16) });
    try self.print(" storel {d}, %v{d}\n", .{ place.count, try self.address(request, 24) });
    const done = self.temp();
    if (place.loan) |loan| {
        try self.print(" jnz %v{d}, @rcscopeloan{d}, @rcscopeowner{d}\n@rcscopeloan{d}\n", .{ loan, done, done, done });
        try self.print(" %v{d} =w call $myl_qbe_rc_scope_prepare_loan(l %ctx, l %v{d}, l %v{d})\n", .{ done, place.scope, request });
        try self.print(" jmp @rcscopejoined{d}\n@rcscopeowner{d}\n", .{ done, done });
    }
    try self.print(" %v{d} =w call $myl_qbe_rc_scope_prepare(l %ctx, l %v{d}, l %v{d})\n", .{ done, place.scope, request });
    if (place.loan != null) try self.print("@rcscopejoined{d}\n", .{done});
    try unique.success(E, self, done);
}

//! Compiler-generated Option mutation projections keep the source owning edge.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
const unique = @import("qbe_rc_unique.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Native emitter failures shared with typed ownership publication.
pub const Error = frame.Error;

/// Borrow only the hidden defensive Option projection that reaches a mutation.
/// User-written match bindings retain the ordinary snapshot publication path.
pub fn bind(comptime E: type, self: *E, dispatch: @FieldType(Op, "switch_variant"), index: usize) Error!bool {
    const owner = sourceOwner(E, self, dispatch, index) orelse return false;
    const ty = self.function.scope.locals[index].ty;
    if (!cow.payloadType(self.program, ty) or !mutated(E, self, index)) return false;
    const source = self.temp();
    const storage: []const u8 = if (self.byReference(owner) or self.callerStorage(owner)) "loadl" else "copy";
    try self.print(" %v{d} =l {s} %l{d}\n", .{ source, storage, owner });
    const address = try self.address(source, (try self.layout(dispatch.ty)).payload_offset);
    const previous = try self.load("v", address);
    try unique.field(E, self, .{ .ty = ty, .address = address, .container = previous });
    try frame.drop(E, self, index);
    const value = try self.load("v", address);
    try self.print(" storel %v{d}, %l{d}\n", .{ value, index });
    return true;
}

fn sourceOwner(comptime E: type, self: *E, dispatch: @FieldType(Op, "switch_variant"), index: usize) ?usize {
    if (self.pc == 0 or index < self.function.signature.parameter_count) return null;
    const local = self.function.scope.locals[index];
    if (!std.mem.eql(u8, local.name, "<collection>") or local.origin != .local) return null;
    const shape = @import("prelude.zig").optionShape(dispatch.ty, self.program.records) orelse return null;
    if (dispatch.arms.len != 2 or dispatch.arms[shape.some].slot == null or
        @backingInt(dispatch.arms[shape.some].slot.?) != index or dispatch.arms[shape.none].slot != null) return null;
    const code = self.function.scope.instructions;
    const load = code[self.pc - 1].op;
    if (load != .load_local) return null;
    const some = dispatch.arms[shape.some].target;
    const none = dispatch.arms[shape.none].target;
    if (some >= code.len or none + 2 >= code.len) return null;
    if (code[some].op != .jump or code[none].op != .push_bool or code[none].op.push_bool) return null;
    if (code[none + 1].op != .assert_true or code[none + 2].op != .jump) return null;
    if (!std.mem.eql(u8, code[none + 1].op.assert_true.message, "invalidated Option narrowing") or
        code[some].op.jump != code[none + 2].op.jump) return null;
    return @backingInt(load.load_local);
}

fn mutated(comptime E: type, self: *E, index: usize) bool {
    const plan = self.cow.?.plan;
    for (self.function.scope.instructions[self.pc + 1 ..]) |instruction| {
        if (instruction.op != .buffer_operation) continue;
        const operation = instruction.op.buffer_operation;
        if (!operation.kind.writesReceiver() and operation.kind != .set_add and operation.kind != .set_discard) continue;
        var at = @backingInt(operation.owner);
        var remaining = plan.places.len;
        while (remaining != 0) : (remaining -= 1) {
            if (at == index) return true;
            if (plan.place(at)) |place| {
                at = place.parent;
            } else if (at < plan.aliases.len and plan.aliases[at] != cow.none) {
                at = plan.aliases[at];
            } else break;
        }
    }
    return false;
}

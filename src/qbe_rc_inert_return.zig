//! A closed inert prefix can return null edges before initializing its journal.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const limit = 32;
/// The one forward condition and the null constructor path it protects.
pub const Proof = struct { branch: usize, end: usize };
/// Native lowering failures; unsupported prefixes retain ordinary lowering.
pub const Error = frame.Error;

/// Closed instruction admission intentionally excludes SHARE, projections,
/// calls, loans and future opcodes. History lowering may veto this query too.
pub fn certify(comptime E: type, self: *E) Error!?Proof {
    const state = frame.get(E, self) orelse return null;
    if (self.entry or self.heap_frame or self.step_checks) return null;
    if (@import("qbe_rc_borrow.zig").active(E, self)) return null;
    const function = self.function;
    if (function.signature.parameter_count > limit) return null;
    if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return null;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index|
        if (!scalar(local.ty) or self.byReference(index)) return null;
    const output = state.catalog.get(function.signature.return_type) catch |err|
        return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (@import("qbe_wire.zig").scalar(function.signature.return_type, self.program.records)) return null;
    if (!output.counted or output.unique_drop or (try self.layout(function.signature.return_type)).size > 256) return null;
    const code = function.scope.instructions;
    const branch = condition(function) orelse return null;
    const end = code[branch].op.jump_if_false;
    if (end <= branch + 1 or end > limit or end >= code.len) return null;
    for (code[0..end], 0..) |instruction, pc| {
        if (instruction.inline_origin != null or self.branch_targets[pc]) return null;
        const capture = self.cow.?.captures[pc];
        const none = @import("cow_plan.zig").none;
        if (capture.begin != none or capture.active != none) return null;
    }
    if (!try zeroPath(E, self, branch + 1, end)) return null;
    return .{ .branch = branch, .end = end };
}

fn scalar(ty: typed.Type) bool {
    return ty == .i64 or ty == .bool;
}

fn condition(function: bytecode.Function) ?usize {
    var height: usize = 0;
    for (function.scope.instructions[0..@min(limit, function.scope.instructions.len)], 0..) |instruction, pc| {
        switch (instruction.op) {
            .load_local => |id| {
                if (@backingInt(id) >= function.signature.parameter_count) return null;
                height += 1;
            },
            .push_i64, .push_bool => height += 1,
            .cmp_i64, .cmp_bool => {
                if (height < 2) return null;
                height -= 1;
            },
            .not_bool => if (height == 0) return null,
            .jump_if_false => return if (height == 1) pc else null,
            else => return null,
        }
    }
    return null;
}

fn zeroPath(comptime E: type, self: *E, start: usize, end: usize) Error!bool {
    var height: usize = 0;
    for (self.function.scope.instructions[start..end], start..) |instruction, pc| {
        switch (instruction.op) {
            .make_variant => |variant| {
                const record = self.program.records[variant.ty.recordIndex()];
                // Result construction can record error provenance even when
                // its payload is empty; that event is observable on propagation.
                if (typed.resultShape(variant.ty, self.program.records) != null) return false;
                if (variant.tag != 0 or record.shape.variants.?.cases[variant.tag].payload != null) return false;
                if ((try self.layout(variant.ty)).drop) return false;
                height += 1;
            },
            .make_record => |record| {
                const layout = try self.layout(record.ty);
                if (layout.kind != .record or layout.drop or record.fields > height) return false;
                height = height - record.fields + 1;
            },
            .push_i64 => |value| {
                if (value != 0) return false;
                height += 1;
            },
            .push_bool => |value| {
                if (value) return false;
                height += 1;
            },
            .push_unit => height += 1,
            .ret => return pc + 1 == end and height == 1,
            else => return false,
        }
    }
    return false;
}

/// Called after native frame admission but before any ownership journal or
/// arena setup. A false condition resumes its original empty-stack successor
/// after normal journal initialization, without evaluating the pure test twice.
pub fn emit(comptime E: type, self: *E) Error!?usize {
    const proof = try certify(E, self) orelse return null;
    var stack: [limit]usize = undefined;
    var height: usize = 0;
    for (self.function.scope.instructions[0..proof.branch]) |instruction|
        try predicate(E, self, instruction.op, &stack, &height);
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcinertreturn{d}, @rcinertfallback{d}\n@rcinertreturn{d}\n", .{ stack[0], label, label, label });
    const ty = self.function.signature.return_type;
    const indirect = try self.largeResult(self.function);
    const bytes = (try self.layout(ty)).size;
    const pointer = self.temp();
    try self.print(" %v{d} =l copy %{s}\n", .{ pointer, if (indirect) "out" else "empty" });
    var offset: u64 = 0;
    while (offset < bytes) : (offset += 1) {
        const word = bytes - offset >= 8;
        try self.print(" store{s} 0, %v{d}\n", .{ if (word) "l" else "b", try self.address(pointer, offset) });
        if (word) offset += 7;
    }
    try self.leaveFrame();
    if (indirect) try self.print(" ret 0\n", .{}) else try self.print(" ret %v{d}\n", .{pointer});
    try self.print("@rcinertfallback{d}\n", .{label});
    return proof.end;
}

/// Retain the original block boundary even if label stripping removes i0.
pub fn enterBody(comptime E: type, self: *E, successor: ?usize) Error!void {
    try self.print(" jmp @i{d}\n", .{successor orelse 0});
    if (successor != null) try self.print("@rcinertoriginal\n", .{});
}

fn predicate(comptime E: type, self: *E, op: Op, stack: *[limit]usize, height: *usize) Error!void {
    const value = self.temp();
    switch (op) {
        .load_local => |id| try self.print(" %v{d} =l copy %a{d}\n", .{ value, @backingInt(id) }),
        .push_i64 => |literal| try self.print(" %v{d} =l copy {d}\n", .{ value, literal }),
        .push_bool => |literal| try self.print(" %v{d} =l copy {d}\n", .{ value, @intFromBool(literal) }),
        .cmp_i64, .cmp_bool => {
            const kind = if (op == .cmp_i64) switch (op.cmp_i64) {
                .eq => "ceql",
                .ne => "cnel",
                .lt => "csltl",
                .le => "cslel",
                .gt => "csgtl",
                .ge => "csgel",
            } else if (op.cmp_bool == .eq) "ceql" else "cnel";
            try self.print(" %v{d} =l {s} %v{d}, %v{d}\n", .{ value, kind, stack[height.* - 2], stack[height.* - 1] });
            height.* -= 2;
        },
        .not_bool => {
            height.* -= 1;
            try self.print(" %v{d} =l xor %v{d}, 1\n", .{ value, stack[height.*] });
        },
        else => return error.InternalError,
    }
    stack[height.*] = value;
    height.* += 1;
}

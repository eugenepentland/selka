//! Iterative lowering with symbolic labels preserves stack shape and source evaluation order.
/// Failures returned by lower; callers must handle these boundary errors.
pub const LowerError = error{
    InternalError,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode.zig");
const Span = @import("source.zig").Span;
const Label = enum(usize) { _ };
const Work = union(enum) {
    expression: typed.NodeId,
    statement: typed.StatementId,
    instruction: bc.Instruction,
    mark: Label,
    jump: struct { target: Label, conditional: bool = false, span: Span },
    propagate: struct { input: typed.Type, output: typed.Type, target: Label, span: Span },
    dispatch: struct { ty: typed.Type, targets: []const Label, slots: []const ?typed.LocalId, span: Span },
};
const Fixup = struct { instruction: usize, label: Label, arm: ?usize = null, propagation: bool = false };
const Emitter = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    loops: std.AutoHashMapUnmanaged(usize, struct { start: Label, end: Label }) = .empty,
    code: std.ArrayList(bc.Instruction) = .empty,
    work: std.ArrayList(Work) = .empty,
    labels: std.ArrayList(?usize) = .empty,
    fixups: std.ArrayList(Fixup) = .empty,

    fn push(self: *Emitter, task: Work) !void {
        try self.work.append(self.allocator, task);
    }
    fn label(self: *Emitter) !Label {
        const id: Label = @fromBackingInt(self.labels.items.len);
        try self.labels.append(self.allocator, null);
        return id;
    }
    fn instruction(self: *Emitter, span: Span, op: @FieldType(bc.Instruction, "op")) !void {
        try self.push(.{ .instruction = .{ .span = span, .op = op } });
    }
    fn emitCall(self: *Emitter, span: Span, call: @FieldType(@FieldType(typed.Node, "data"), "call")) !void {
        for (call.literals) |literal| {
            try self.instruction(span, .{ .drop_local = literal.owner });
            try self.instruction(span, .{ .end_borrow = literal.reference });
        }
        try self.instruction(span, if (call.references.len == 0) .{ .call = call.function } else .{ .call_refs = .{ .function = call.function, .references = call.references } });
        var n = call.literals.len;
        while (n > 0) {
            n -= 1;
            const literal = call.literals[n];
            try self.instruction(span, .{ .begin_slice = literal.reference });
            try self.instruction(span, .{ .push_i64 = @intCast(literal.length) });
            try self.instruction(span, .{ .push_i64 = 0 });
            try self.instruction(span, .{ .store_local = literal.owner });
            try self.push(.{ .expression = literal.value });
        }
        var i = call.arguments.len;
        while (i > 0) {
            i -= 1;
            try self.push(.{ .expression = call.arguments[i] });
        }
    }
    fn emitStatement(self: *Emitter, id: typed.StatementId) !void {
        const stmt = self.program.statements[@backingInt(id)];
        switch (stmt.data) {
            .arena_scope => |scope| {
                if (!self.program.statements[@backingInt(scope.body)].terminates) try self.instruction(stmt.span, .{ .end_region = scope.slot });
                try self.push(.{ .statement = scope.body });
                try self.instruction(stmt.span, .{ .begin_region = scope.slot });
                try self.push(.{ .expression = scope.parent });
            },
            .block => |children| {
                for (stmt.owned_cleanup) |slot| try self.instruction(stmt.span, .{ .drop_local = slot });
                var i = children.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .statement = children[i] });
                }
            },
            .ret_ref => |reference| {
                try self.instruction(stmt.span, .ret_ref);
                for (stmt.cleanup) |cleanup_id| try self.instruction(stmt.span, .{ .end_borrow = cleanup_id });
                try self.instruction(stmt.span, .{ .capture_ref = reference });
            },
            .borrow_call => |borrow| {
                if (!self.program.statements[@backingInt(borrow.body)].terminates) try self.instruction(stmt.span, .{ .end_borrow = borrow.reference });
                try self.push(.{ .statement = borrow.body });
                const call_node = self.program.nodes[@backingInt(borrow.call)];
                const call = call_node.data.call;
                try self.instruction(call_node.span, .{ .call_borrow = .{ .function = call.function, .references = call.references, .destination = borrow.reference } });
                var i = call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = call.arguments[i] });
                }
            },
            .acknowledge => |value| {
                try self.instruction(stmt.span, .{ .acknowledge = self.program.nodes[@backingInt(value)].ty });
                try self.push(.{ .expression = value });
            },
            .ret, .discard => |value| {
                try self.instruction(stmt.span, if (stmt.data == .ret) .ret else .pop);
                for (stmt.cleanup) |reference| try self.instruction(stmt.span, .{ .end_borrow = reference });
                try self.push(.{ .expression = value });
            },
            .borrow => |borrow| {
                if (!self.program.statements[@backingInt(borrow.body)].terminates) {
                    try self.instruction(stmt.span, .{ .end_borrow = borrow.reference });
                    if (borrow.split) |split| try self.instruction(stmt.span, .{ .end_borrow = split.right });
                }
                try self.push(.{ .statement = borrow.body });
                if (borrow.split) |split| {
                    try self.instruction(stmt.span, .{ .split_borrow = .{ .left = borrow.reference, .right = split.right } });
                    try self.push(.{ .expression = split.middle });
                } else {
                    try self.instruction(stmt.span, if (borrow.range != null) .{ .begin_slice = borrow.reference } else .{ .begin_borrow = borrow.reference });
                    if (borrow.range) |range| {
                        try self.push(.{ .expression = range.end });
                        try self.push(.{ .expression = range.start });
                    }
                }
            },
            .write_slice => |write| {
                try self.instruction(stmt.span, .{ .write_slice = write.reference });
                try self.push(.{ .expression = write.value });
                try self.push(.{ .expression = write.index });
            },
            .write_ref => |write| {
                try self.instruction(stmt.span, .{ .write_ref = write.reference });
                try self.push(.{ .expression = write.value });
            },
            .initialize, .assign => |store| {
                try self.instruction(stmt.span, .{ .store_local = store.slot });
                try self.push(.{ .expression = store.value });
            },
            .match => |match| {
                const end = try self.label();
                const targets = try self.allocator.alloc(Label, match.arms.len);
                const slots = try self.allocator.alloc(?typed.LocalId, match.arms.len);
                try self.push(.{ .mark = end });
                var i = match.arms.len;
                while (i > 0) {
                    i -= 1;
                    const arm = match.arms[i];
                    targets[arm.tag] = try self.label();
                    slots[arm.tag] = arm.slot;
                    if (!self.program.statements[@backingInt(arm.body)].terminates) try self.push(.{ .jump = .{ .target = end, .span = stmt.span } });
                    try self.push(.{ .statement = arm.body });
                    try self.push(.{ .mark = targets[arm.tag] });
                }
                try self.push(.{ .dispatch = .{ .ty = self.program.nodes[@backingInt(match.value)].ty, .targets = targets, .slots = slots, .span = stmt.span } });
                try self.push(.{ .expression = match.value });
            },
            .branch => |branch| {
                const otherwise = try self.label();
                const end = try self.label();
                try self.push(.{ .mark = end });
                if (branch.else_body) |body| try self.push(.{ .statement = body });
                try self.push(.{ .mark = otherwise });
                if (branch.else_body != null and !self.program.statements[@backingInt(branch.then_body)].terminates)
                    try self.push(.{ .jump = .{ .target = end, .span = stmt.span } });
                try self.push(.{ .statement = branch.then_body });
                try self.push(.{ .jump = .{ .target = otherwise, .conditional = true, .span = self.program.nodes[@backingInt(branch.condition)].span } });
                try self.push(.{ .expression = branch.condition });
            },
            .loop_exit => |exit| {
                const target = self.loops.get(exit.target) orelse return error.InternalError;
                try self.push(.{ .jump = .{ .target = if (exit.continuing) target.start else target.end, .span = stmt.span } });
                for (exit.regions) |slot| try self.instruction(stmt.span, .{ .end_region = slot });
                for (stmt.owned_cleanup) |slot| try self.instruction(stmt.span, .{ .drop_local = slot });
                for (stmt.cleanup) |reference| try self.instruction(stmt.span, .{ .end_borrow = reference });
            },
            .loop => |loop| {
                const start = try self.label();
                const end = try self.label();
                const next = if (loop.step != null) try self.label() else start;
                try self.loops.put(self.allocator, loop.id, .{ .start = next, .end = end });
                try self.push(.{ .mark = end });
                if (loop.step) |step| {
                    try self.push(.{ .jump = .{ .target = start, .span = stmt.span } });
                    try self.push(.{ .statement = step });
                    try self.push(.{ .mark = next });
                } else if (!self.program.statements[@backingInt(loop.body)].terminates)
                    try self.push(.{ .jump = .{ .target = start, .span = stmt.span } });
                try self.push(.{ .statement = loop.body });
                try self.push(.{ .jump = .{ .target = end, .conditional = true, .span = self.program.nodes[@backingInt(loop.condition)].span } });
                try self.push(.{ .expression = loop.condition });
                try self.push(.{ .mark = start });
            },
        }
    }
    fn emitExpression(self: *Emitter, id: typed.NodeId) !void {
        const node = self.program.nodes[@backingInt(id)];
        switch (node.data) {
            .block_value => |block| {
                try self.push(.{ .expression = block.value });
                try self.push(.{ .statement = block.body });
            },
            .propagate => |propagate| {
                const failure = try self.label();
                const success = try self.label();
                try self.push(.{ .mark = success });
                try self.instruction(node.span, .ret);
                for (propagate.cleanup) |reference| try self.instruction(node.span, .{ .end_borrow = reference });
                try self.push(.{ .mark = failure });
                try self.push(.{ .jump = .{ .target = success, .span = node.span } });
                try self.push(.{ .propagate = .{ .input = self.program.nodes[@backingInt(propagate.value)].ty, .output = propagate.output, .target = failure, .span = node.span } });
                try self.push(.{ .expression = propagate.value });
            },
            .variant => |variant| {
                try self.instruction(node.span, .{ .make_variant = .{ .ty = node.ty, .tag = variant.tag } });
                if (variant.value) |value| try self.push(.{ .expression = value });
            },
            .array => |values| {
                try self.instruction(node.span, .{ .make_record = .{ .ty = node.ty, .fields = values.len } });
                var i = values.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = values[i] });
                }
            },
            .index => |access| {
                try self.instruction(node.span, .{ .get_index = self.program.nodes[@backingInt(access.base)].ty });
                try self.push(.{ .expression = access.index });
                try self.push(.{ .expression = access.base });
            },
            .replace => |replace| {
                try self.instruction(node.span, .{ .replace_index = node.ty });
                try self.push(.{ .expression = replace.value });
                try self.push(.{ .expression = replace.index });
                try self.push(.{ .expression = replace.base });
            },
            .length => |base| {
                try self.instruction(node.span, .{ .array_length = self.program.nodes[@backingInt(base)].ty });
                try self.push(.{ .expression = base });
            },
            .record => |fields| {
                const order = try self.allocator.alloc(usize, fields.len);
                for (fields, order) |field, *index| index.* = field.index;
                try self.instruction(node.span, .{ .make_record = .{ .ty = node.ty, .fields = fields.len, .order = order } });
                try self.pushFields(fields);
            },
            .update => |update| {
                const indices = try self.allocator.alloc(usize, update.fields.len);
                for (update.fields, indices) |field, *index| index.* = field.index;
                try self.instruction(node.span, .{ .update_record = .{ .ty = node.ty, .indices = indices } });
                try self.pushFields(update.fields);
                try self.push(.{ .expression = update.base });
            },
            .field => |field| {
                try self.instruction(node.span, .{ .get_field = field.index });
                try self.push(.{ .expression = field.base });
            },
            .integer => |value| try self.instruction(node.span, if (node.ty == .i64) .{ .push_i64 = @intCast(value) } else .{ .push_integer = .{ .ty = node.ty, .value = value } }),
            .wrap => |value| {
                try self.instruction(node.span, .{ .wrap_domain = node.ty });
                try self.push(.{ .expression = value });
            },
            .unwrap => |value| {
                try self.instruction(node.span, .{ .unwrap_domain = self.program.nodes[@backingInt(value)].ty });
                try self.push(.{ .expression = value });
            },
            .cast => |value| {
                try self.instruction(node.span, .{ .cast_integer = node.ty });
                try self.push(.{ .expression = value });
            },
            .boolean => |value| try self.instruction(node.span, .{ .push_bool = value }),
            .read_slice => |read| {
                try self.instruction(node.span, .{ .read_slice = read.reference });
                try self.push(.{ .expression = read.index });
            },
            .len_slice => |reference| try self.instruction(node.span, .{ .len_slice = reference }),
            .read_ref => |reference| try self.instruction(node.span, .{ .read_ref = reference }),
            .pool_operation => |operation| {
                try self.instruction(node.span, .{ .pool_operation = .{ .reference = operation.reference, .kind = operation.kind, .owner = operation.owner, .output = node.ty } });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = operation.arguments[i] });
                }
            },
            .buffer_operation => |operation| {
                try self.instruction(node.span, .{ .buffer_operation = .{ .reference = operation.reference, .kind = operation.kind, .owner = operation.owner, .output = node.ty } });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = operation.arguments[i] });
                }
            },
            .take_field => |read| try self.instruction(node.span, .{ .take_field = .{ .owner = read.owner, .field = read.field, .output = node.ty } }),
            .read_field => |read| try self.instruction(node.span, .{ .read_field = .{ .reference = read.reference, .owner = read.owner, .field = read.field, .output = node.ty } }),
            .reset_arena => |value| {
                try self.instruction(node.span, .{ .reset_arena = node.ty });
                try self.push(.{ .expression = value });
            },
            .restrict_resource => |restrict| {
                try self.instruction(node.span, .{ .restrict_resource = .{ .permissions = restrict.permissions, .ty = node.ty } });
                try self.push(.{ .expression = restrict.value });
            },
            .resource_io => |io| {
                try self.instruction(node.span, .{ .resource_io = .{ .reference = io.reference, .kind = io.kind, .owner = io.owner, .output = node.ty, .input = if (io.value) |value| self.program.nodes[@backingInt(value)].ty else null } });
                if (io.value) |value| try self.push(.{ .expression = value });
            },
            .environment_get => |get| {
                try self.instruction(node.span, .{ .environment_get = .{ .output = node.ty, .name = self.program.nodes[@backingInt(get.name)].ty } });
                try self.push(.{ .expression = get.name });
                try self.push(.{ .expression = get.capability });
            },
            .complete_resource => |value| {
                try self.instruction(node.span, .{ .complete_resource = node.ty });
                try self.push(.{ .expression = value });
            },
            .acquire_resource => |acquire| {
                try self.instruction(node.span, .{ .acquire_resource = .{ .output = node.ty, .request = self.program.nodes[@backingInt(acquire.request)].ty } });
                try self.push(.{ .expression = acquire.request });
                try self.push(.{ .expression = acquire.capability });
            },
            .external_read => |read| {
                try self.instruction(node.span, .{ .external_read = .{ .kind = read.kind, .output = node.ty } });
                try self.push(.{ .expression = read.capability });
            },
            .json_codec => |codec| {
                try self.instruction(node.span, .{ .json_codec = .{ .document = codec.document, .decode = codec.decode, .input = self.program.nodes[@backingInt(codec.arguments[1])].ty, .output = node.ty } });
                var index: usize = 3;
                while (index > 0) {
                    index -= 1;
                    try self.push(.{ .expression = codec.arguments[index] });
                }
            },
            .acquire_buffer, .acquire_pool => |acquire| {
                try self.instruction(node.span, if (node.data == .acquire_pool) .{ .acquire_pool = node.ty } else .{ .acquire_buffer = node.ty });
                try self.push(.{ .expression = acquire.capacity });
                try self.push(.{ .expression = acquire.allocator });
            },
            .local => |slot| try self.instruction(node.span, if (typed.moveOnly(node.ty, self.program.records) or typed.requiresHandling(node.ty, self.program.records)) .{ .move_local = slot } else .{ .load_local = slot }),
            .call => |call| try self.emitCall(node.span, call),
            .unary => |u| {
                try self.instruction(u.op_span, if (u.op != .neg and u.op != .not) .{ .unary_float = u.op } else if (u.op == .not) .not_bool else if (node.ty == .i64) .neg_i64_checked else .{ .neg_integer = node.ty });
                try self.push(.{ .expression = u.operand });
            },
            .binary => |b| {
                if (b.op == .logical_and or b.op == .logical_or) {
                    const alternate = try self.label();
                    const end = try self.label();
                    try self.push(.{ .mark = end });
                    if (b.op == .logical_and) try self.instruction(b.op_span, .{ .push_bool = false }) else try self.push(.{ .expression = b.right });
                    try self.push(.{ .mark = alternate });
                    try self.push(.{ .jump = .{ .target = end, .span = b.op_span } });
                    if (b.op == .logical_and) try self.push(.{ .expression = b.right }) else try self.instruction(b.op_span, .{ .push_bool = true });
                    try self.push(.{ .jump = .{ .target = alternate, .conditional = true, .span = b.op_span } });
                    try self.push(.{ .expression = b.left });
                } else {
                    try self.push(.{ .instruction = binaryInstruction(b, self.program.nodes, self.program.records) });
                    try self.push(.{ .expression = b.right });
                    try self.push(.{ .expression = b.left });
                }
            },
        }
    }
    fn pushFields(self: *Emitter, fields: []const typed.FieldInit) !void {
        var i = fields.len;
        while (i > 0) {
            i -= 1;
            try self.push(.{ .expression = fields[i].value });
        }
    }
    fn finish(self: *Emitter, body: typed.StatementId) ![]const bc.Instruction {
        defer self.work.deinit(self.allocator);
        defer self.labels.deinit(self.allocator);
        defer self.fixups.deinit(self.allocator);
        try self.push(.{ .statement = body });
        while (self.work.pop()) |task| switch (task) {
            .instruction => |inst| try self.code.append(self.allocator, inst),
            .statement => |id| try self.emitStatement(id),
            .expression => |id| try self.emitExpression(id),
            .propagate => |propagate| {
                try self.fixups.append(self.allocator, .{ .instruction = self.code.items.len, .label = propagate.target, .propagation = true });
                try self.code.append(self.allocator, .{ .span = propagate.span, .op = .{ .try_result = .{ .input = propagate.input, .output = propagate.output, .error_target = 0 } } });
            },
            .dispatch => |dispatch| {
                const arms = try self.allocator.alloc(bc.SwitchArm, dispatch.targets.len);
                for (dispatch.targets, dispatch.slots, arms, 0..) |target, slot, *arm, i| {
                    arm.* = .{ .target = 0, .slot = slot };
                    try self.fixups.append(self.allocator, .{ .instruction = self.code.items.len, .label = target, .arm = i });
                }
                try self.code.append(self.allocator, .{ .span = dispatch.span, .op = .{ .switch_variant = .{ .ty = dispatch.ty, .arms = arms } } });
            },
            .mark => |id| self.labels.items[@backingInt(id)] = self.code.items.len,
            .jump => |jump| {
                try self.fixups.append(self.allocator, .{ .instruction = self.code.items.len, .label = jump.target });
                try self.code.append(self.allocator, .{ .span = jump.span, .op = if (jump.conditional) .{ .jump_if_false = 0 } else .{ .jump = 0 } });
            },
        };
        for (self.fixups.items) |fixup| {
            const target = self.labels.items[@backingInt(fixup.label)] orelse return error.InternalError;
            const inst = &self.code.items[fixup.instruction];
            // Dispatch arms were allocated by this emitter and are not shared yet.
            if (fixup.propagation) {
                inst.op.try_result.error_target = target;
            } else if (fixup.arm) |arm| {
                @constCast(inst.op.switch_variant.arms)[arm].target = target;
            } else if (inst.op == .jump) {
                inst.op.jump = target;
            } else {
                inst.op.jump_if_false = target;
            }
        }
        return self.code.toOwnedSlice(self.allocator);
    }
};
fn binaryInstruction(binary: anytype, nodes: []const typed.Node, records: []const typed.Record) bc.Instruction {
    const operand_type = nodes[@backingInt(binary.left)].ty;
    if (operand_type.isAggregate() and records[operand_type.recordIndex()].shape.handle_pool != null) return .{ .span = binary.op_span, .op = .{ .cmp_handle = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    if (operand_type.isAggregate() and records[operand_type.recordIndex()].shape.domain != null) return .{ .span = binary.op_span, .op = .{ .cmp_domain = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    if (operand_type.isAggregate()) return .{ .span = binary.op_span, .op = .{ .cmp_enum = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    if (operand_type.isInteger() and operand_type != .i64)
        return .{ .span = binary.op_span, .op = .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } } };
    return .{ .span = binary.op_span, .op = switch (binary.op) {
        .add => .add_i64_checked,
        .sub => .sub_i64_checked,
        .mul => .mul_i64_checked,
        .div => .div_i64_checked,
        .rem => .rem_i64_checked,
        .f64_add,
        .f64_sub,
        .f64_mul,
        .f64_div,
        .f64_eq,
        .f64_lt,
        .f64_le,
        .bit_and,
        .bit_or,
        .bit_xor,
        .shift_left,
        .shift_right,
        .wrapping_add,
        .wrapping_sub,
        .wrapping_mul,
        .saturating_add,
        .saturating_sub,
        .saturating_mul,
        => .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } },
        .eq, .ne => if (nodes[@backingInt(binary.left)].ty == .bool)
            .{ .cmp_bool = if (binary.op == .eq) .eq else .ne }
        else
            .{ .cmp_i64 = if (binary.op == .eq) .eq else .ne },
        .lt, .le, .gt, .ge => .{ .cmp_i64 = std.meta.stringToEnum(bc.Predicate, @tagName(binary.op)).? },
        .logical_and, .logical_or => unreachable,
    } };
}
/// Allocate and validate bytecode lowered from the checked typed program.
pub fn lower(allocator: std.mem.Allocator, program: typed.Program) LowerError!bc.Program {
    const functions = try allocator.alloc(bc.Function, program.functions.len);
    for (program.functions, functions) |function, *out| {
        var emitter: Emitter = .{ .allocator = allocator, .program = program };
        defer emitter.loops.deinit(allocator);
        out.* = .{
            .policy = .{
                .host = function.policy.host,
                .effect_bound = function.policy.effect_bound,
                .effects = function.policy.effects,
                .owner = function.policy.owner,
                .restricted = function.policy.restricted,
                .conversion = function.policy.conversion,
            },
            .signature = .{
                .return_reference = function.signature.return_reference,
                .parameter_count = function.signature.parameter_count,
                .return_type = function.signature.return_type,
            },
            .scope = .{
                .references = function.scope.references,
                .locals = function.scope.locals,
                .instructions = if (function.policy.host != null) &.{} else try emitter.finish(function.scope.body),
            },
            .id = function.id,
            .name = function.name,
        };
    }
    const result: bc.Program = .{ .functions = functions, .main = program.main, .records = program.records };
    try bc.validate(allocator, result);
    return result;
}

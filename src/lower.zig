//! Iterative lowering with symbolic labels preserves stack shape and source evaluation order.
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
    fn emitStatement(self: *Emitter, id: typed.StatementId) !void {
        const stmt = self.program.statements[@backingInt(id)];
        switch (stmt.data) {
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
                if (!self.program.statements[@backingInt(borrow.body)].terminates) try self.instruction(stmt.span, .{ .end_borrow = borrow.reference });
                try self.push(.{ .statement = borrow.body });
                try self.instruction(stmt.span, if (borrow.range != null) .{ .begin_slice = borrow.reference } else .{ .begin_borrow = borrow.reference });
                if (borrow.range) |range| {
                    try self.push(.{ .expression = range.end });
                    try self.push(.{ .expression = range.start });
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
            .loop => |loop| {
                const start = try self.label();
                const end = try self.label();
                try self.push(.{ .mark = end });
                if (!self.program.statements[@backingInt(loop.body)].terminates)
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
            .buffer_operation => |operation| {
                try self.instruction(node.span, .{ .buffer_operation = .{ .kind = operation.kind, .owner = operation.owner, .output = node.ty } });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = operation.arguments[i] });
                }
            },
            .acquire_buffer => |capacity| {
                try self.instruction(node.span, .{ .acquire_buffer = node.ty });
                try self.push(.{ .expression = capacity });
            },
            .local => |slot| try self.instruction(node.span, if (typed.moveOnly(node.ty, self.program.records) or typed.requiresHandling(node.ty, self.program.records)) .{ .move_local = slot } else .{ .load_local = slot }),
            .call => |call| {
                try self.instruction(node.span, if (call.references.len == 0) .{ .call = call.function } else .{ .call_refs = .{ .function = call.function, .references = call.references } });
                var i = call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = call.arguments[i] });
                }
            },
            .unary => |u| {
                try self.instruction(u.op_span, if (u.op == .not) .not_bool else if (node.ty == .i64) .neg_i64_checked else .{ .neg_integer = node.ty });
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
                    try self.push(.{ .instruction = binaryInstruction(b, self.program.nodes) });
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
            if (fixup.propagation) inst.op.try_result.error_target = target else if (fixup.arm) |arm| @constCast(inst.op.switch_variant.arms)[arm].target = target else if (inst.op == .jump) inst.op.jump = target else inst.op.jump_if_false = target;
        }
        return self.code.toOwnedSlice(self.allocator);
    }
};
fn binaryInstruction(binary: anytype, nodes: []const typed.Node) bc.Instruction {
    const operand_type = nodes[@backingInt(binary.left)].ty;
    if (operand_type.isAggregate()) return .{ .span = binary.op_span, .op = .{ .cmp_enum = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    if (operand_type.isInteger() and operand_type != .i64)
        return .{ .span = binary.op_span, .op = .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } } };
    return .{ .span = binary.op_span, .op = switch (binary.op) {
        .add => .add_i64_checked,
        .sub => .sub_i64_checked,
        .mul => .mul_i64_checked,
        .div => .div_i64_checked,
        .rem => .rem_i64_checked,
        .eq, .ne => if (nodes[@backingInt(binary.left)].ty == .bool)
            .{ .cmp_bool = if (binary.op == .eq) .eq else .ne }
        else
            .{ .cmp_i64 = if (binary.op == .eq) .eq else .ne },
        .lt, .le, .gt, .ge => .{ .cmp_i64 = std.meta.stringToEnum(bc.Predicate, @tagName(binary.op)).? },
        .logical_and, .logical_or => unreachable,
    } };
}
pub fn lower(allocator: std.mem.Allocator, program: typed.Program) !bc.Program {
    const functions = try allocator.alloc(bc.Function, program.functions.len);
    for (program.functions, functions) |function, *out| {
        var emitter: Emitter = .{ .allocator = allocator, .program = program };
        out.* = .{ .effect_bound = function.effect_bound, .effects = function.effects, .return_reference = function.return_reference, .references = function.references, .owner = function.owner, .restricted = function.restricted, .conversion = function.conversion, .id = function.id, .name = function.name, .locals = function.locals, .parameter_count = function.parameter_count, .return_type = function.return_type, .instructions = try emitter.finish(function.body) };
    }
    const result: bc.Program = .{ .functions = functions, .main = program.main, .records = program.records };
    try bc.validate(allocator, result);
    return result;
}

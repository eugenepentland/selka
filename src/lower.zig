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
    /// A `--mode ReleaseFast` build drops `debug` nodes in lowering; Debug builds
    /// and `run`/`test` keep them.
    drop_debug: bool = false,
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
        if (call.evaluation) |evaluation| for (evaluation.cleanup) |slot| try self.instruction(span, .{ .drop_local = slot });
        try self.instruction(span, .{ .call = call.function });
        const callee = self.program.functions[@backingInt(call.function)];
        var i = call.arguments.len;
        while (i > 0) {
            i -= 1;
            // A `mut` fixed array crosses as the caller's own variable, which
            // the checker proved the argument names.
            if (referencePosition(self.program, callee, i)) {
                const argument = self.program.nodes[@backingInt(call.arguments[i])];
                if (argument.data != .local) return error.InternalError;
                try self.instruction(argument.span, .{ .ref_local = argument.data.local });
            } else try self.push(.{ .expression = call.arguments[i] });
        }
        if (call.evaluation) |evaluation| try self.push(.{ .statement = evaluation.body });
    }
    /// Whether parameter `position` of `callee` is a `mut` fixed array, which
    /// receives the address of the caller's variable instead of a copy.
    fn referencePosition(program: typed.Program, callee: typed.Function, position: usize) bool {
        if (position >= callee.signature.parameter_count) return false;
        for (callee.signature.declared_mutates) |declared| if (declared == position)
            return typed.referenceArray(program.records, callee.scope.locals[position].ty);
        return false;
    }
    /// Values evaluate in source order, then `sep=` and finally `end=`. A stream
    /// receiver evaluates first and sits at the stack bottom. A dropped `debug`
    /// node emits nothing at all, so its arguments are not evaluated either.
    fn emitPrint(self: *Emitter, span: Span, output: @FieldType(@FieldType(typed.Node, "data"), "print")) !void {
        if (output.debug and self.drop_debug) {
            // The node still produces its unit value, but no operand is
            // evaluated and no byte reaches the stream.
            try self.instruction(span, .push_unit);
            return;
        }
        const types = try self.allocator.alloc(typed.Type, output.arguments.len);
        for (output.arguments, types) |argument, *ty| ty.* = self.program.nodes[@backingInt(argument)].ty;
        try self.instruction(span, .{ .print = .{
            .sink = output.sink,
            .types = types,
            .separator = output.separator != null,
            .terminator = output.terminator != null,
            .stream = output.stream != null,
            .debug = output.debug,
        } });
        if (output.terminator) |value| try self.push(.{ .expression = value });
        if (output.separator) |value| try self.push(.{ .expression = value });
        var index = output.arguments.len;
        while (index > 0) {
            index -= 1;
            try self.push(.{ .expression = output.arguments[index] });
        }
        if (output.stream) |stream| try self.push(.{ .expression = stream });
    }
    /// `stream.write(text)`: push the text, then the stream receiver above it.
    fn emitStreamWrite(self: *Emitter, span: Span, write: @FieldType(@FieldType(typed.Node, "data"), "stream_write")) !void {
        try self.instruction(span, .{ .stream_write = .{
            .stream = self.program.nodes[@backingInt(write.stream)].ty,
            .text = self.program.nodes[@backingInt(write.text)].ty,
        } });
        try self.push(.{ .expression = write.text });
        try self.push(.{ .expression = write.stream });
    }
    fn emitLoopExit(self: *Emitter, stmt: typed.Statement, exit: @FieldType(@FieldType(typed.Statement, "data"), "loop_exit")) !void {
        const target = self.loops.get(exit.target) orelse return error.InternalError;
        try self.push(.{ .jump = .{ .target = if (exit.continuing) target.start else target.end, .span = stmt.span } });
        for (exit.arenas) |slot| try self.instruction(stmt.span, .{ .end_arena = slot });
        for (stmt.owned_cleanup) |slot| try self.instruction(stmt.span, .{ .drop_local = slot });
    }
    /// One statement form, two resource kinds: a managed region or an open file.
    fn emitWithScope(self: *Emitter, span: Span, scope: @FieldType(@FieldType(typed.Statement, "data"), "with_scope")) !void {
        const terminates = self.program.statements[@backingInt(scope.body)].terminates;
        if (scope.resource) |value| {
            if (!terminates) try self.instruction(span, .{ .drop_local = scope.slot });
            try self.push(.{ .statement = scope.body });
            try self.instruction(span, .{ .store_local = scope.slot });
            try self.push(.{ .expression = value });
            return;
        }
        if (!terminates) try self.instruction(span, .{ .end_arena = scope.slot });
        try self.push(.{ .statement = scope.body });
        try self.instruction(span, .{ .begin_arena = scope.slot });
    }
    /// A valued assert renders its message to standard error only when the
    /// condition is false, then traps through the same `assert_true` op a
    /// static-message assert uses. The status message stays empty, so the trap
    /// record is the bare `R_ASSERT` and the printed line names the values.
    fn emitValuedAssert(self: *Emitter, span: Span, check: @FieldType(@FieldType(typed.Statement, "data"), "assertion"), message: typed.NodeId) !void {
        const condition_span = self.program.nodes[@backingInt(check.condition)].span;
        const fail = try self.label();
        const done = try self.label();
        const types = try self.allocator.alloc(typed.Type, 1);
        types[0] = self.program.nodes[@backingInt(message)].ty;
        try self.push(.{ .mark = done });
        try self.instruction(condition_span, .{ .assert_true = "" });
        try self.instruction(condition_span, .{ .push_bool = false });
        try self.instruction(span, .pop);
        try self.instruction(span, .{ .print = .{ .sink = .stderr, .types = types, .separator = false, .terminator = false, .stream = false, .debug = true } });
        try self.push(.{ .expression = message });
        try self.push(.{ .mark = fail });
        try self.push(.{ .jump = .{ .target = done, .span = span } });
        try self.push(.{ .jump = .{ .target = fail, .conditional = true, .span = condition_span } });
        try self.push(.{ .expression = check.condition });
    }
    fn emitStatement(self: *Emitter, id: typed.StatementId) !void {
        const stmt = self.program.statements[@backingInt(id)];
        switch (stmt.data) {
            .with_scope => |scope| try self.emitWithScope(stmt.span, scope),
            .block => |children| {
                for (stmt.owned_cleanup) |slot| try self.instruction(stmt.span, .{ .drop_local = slot });
                var i = children.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .statement = children[i] });
                }
            },
            .ret => |value| {
                try self.instruction(stmt.span, .ret);
                try self.push(.{ .expression = value });
            },
            .assertion => |check| {
                if (check.message_value) |message| {
                    try self.emitValuedAssert(stmt.span, check, message);
                    return;
                }
                try self.instruction(self.program.nodes[@backingInt(check.condition)].span, .{ .assert_true = check.message });
                try self.push(.{ .expression = check.condition });
            },
            // `_ = expr` releases a result-bearing value, which settles its obligation.
            .discard => |value| {
                const value_type = self.program.nodes[@backingInt(value)].ty;
                const handled = typed.requiresHandling(value_type, self.program.records);
                try self.instruction(stmt.span, if (handled) .{ .acknowledge = value_type } else .pop);
                try self.push(.{ .expression = value });
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
            .loop_exit => |exit| try self.emitLoopExit(stmt, exit),
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
                // A loop the checker proved never exits emits no conditional exit, so what
                // follows it stays unreachable instead of falling out of the function.
                if (!stmt.terminates) {
                    try self.push(.{ .jump = .{ .target = end, .conditional = true, .span = self.program.nodes[@backingInt(loop.condition)].span } });
                    try self.push(.{ .expression = loop.condition });
                }
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
            .unit => try self.instruction(node.span, .push_unit),
            .buffer_operation => |operation| {
                try self.instruction(node.span, .{ .buffer_operation = .{ .kind = operation.kind, .owner = operation.owner, .output = node.ty } });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = operation.arguments[i] });
                }
            },
            .arena_escape => |value| {
                try self.instruction(node.span, .{ .arena_escape = node.ty });
                try self.push(.{ .expression = value });
            },
            .restrict_resource => |restrict| {
                try self.instruction(node.span, .{ .restrict_resource = .{ .permissions = restrict.permissions, .ty = node.ty } });
                try self.push(.{ .expression = restrict.value });
            },
            .dir_resource => |dir| {
                try self.instruction(node.span, .{ .dir_resource = .{ .output = node.ty, .path = self.program.nodes[@backingInt(dir.path)].ty } });
                try self.push(.{ .expression = dir.path });
                try self.push(.{ .expression = dir.capability });
            },
            .host_resource => |host| {
                try self.instruction(node.span, .{ .host_resource = .{ .output = node.ty, .name = self.program.nodes[@backingInt(host.name)].ty } });
                try self.push(.{ .expression = host.name });
                try self.push(.{ .expression = host.capability });
            },
            .resource_io => |io| {
                try self.instruction(node.span, .{ .resource_io = .{ .kind = io.kind, .owner = io.owner, .output = node.ty, .input = if (io.value) |value| self.program.nodes[@backingInt(value)].ty else null } });
                if (io.value) |value| try self.push(.{ .expression = value });
            },
            .environment_get => |get| {
                try self.instruction(node.span, .{ .environment_get = .{ .output = node.ty, .name = self.program.nodes[@backingInt(get.name)].ty } });
                try self.push(.{ .expression = get.name });
                try self.push(.{ .expression = get.capability });
            },
            .environment_only => |only| {
                try self.instruction(node.span, .{ .environment_only = .{ .output = node.ty, .names = self.program.nodes[@backingInt(only.names)].ty } });
                try self.push(.{ .expression = only.names });
                try self.push(.{ .expression = only.capability });
            },
            .environment_names => |capability| {
                try self.instruction(node.span, .{ .environment_names = .{ .output = node.ty } });
                try self.push(.{ .expression = capability });
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
            .acquire_buffer => |acquire| {
                try self.instruction(node.span, .{ .acquire_buffer = node.ty });
                try self.push(.{ .expression = acquire.capacity });
            },
            .print => |output| try self.emitPrint(node.span, output),
            .stream_write => |write| try self.emitStreamWrite(node.span, write),
            .file_access => |call| {
                try self.instruction(node.span, .{ .file_access = .{
                    .kind = call.kind,
                    .mode = call.mode,
                    .text = call.text,
                    .operands = call.arguments.len,
                    .output = node.ty,
                    .shapes = call.shapes,
                } });
                var index = call.arguments.len;
                while (index > 0) {
                    index -= 1;
                    try self.push(.{ .expression = call.arguments[index] });
                }
            },
            .file_method => |call| {
                try self.instruction(node.span, .{ .file_method = .{
                    .kind = call.kind,
                    .owner = call.owner,
                    .text = call.text,
                    .argument = call.argument != null,
                    .output = node.ty,
                    .shapes = call.shapes,
                } });
                if (call.argument) |value| try self.push(.{ .expression = value });
            },
            .local => |slot| try self.instruction(node.span, if (typed.moveOnly(node.ty, self.program.records) or typed.requiresHandling(node.ty, self.program.records)) .{ .move_local = slot } else .{ .load_local = slot }),
            .function_value => |target| try self.instruction(node.span, .{ .function_value = .{ .ty = node.ty, .function = target } }),
            .invoke => |call| {
                try self.instruction(node.span, .{ .invoke = self.program.nodes[@backingInt(call.callee)].ty });
                var i = call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try self.push(.{ .expression = call.arguments[i] });
                }
                try self.push(.{ .expression = call.callee });
            },
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
    if (operand_type.isAggregate() and records[operand_type.recordIndex()].managed) return .{ .span = binary.op_span, .op = .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } } };
    if (operand_type.isAggregate() and records[operand_type.recordIndex()].shape.domain != null) return .{ .span = binary.op_span, .op = .{ .cmp_domain = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    // A payload-free enum compares its tag; a record, fixed array, union, Result or
    // Option compares structurally through the shared native equality runtime.
    if (operand_type.isAggregate() and records[operand_type.recordIndex()].isEnum()) return .{ .span = binary.op_span, .op = .{ .cmp_enum = .{ .ty = operand_type, .predicate = if (binary.op == .eq) .eq else .ne } } };
    if (operand_type.isAggregate()) return .{ .span = binary.op_span, .op = .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } } };
    if (operand_type.isInteger() and operand_type != .i64)
        return .{ .span = binary.op_span, .op = .{ .binary_integer = .{ .ty = operand_type, .op = binary.op } } };
    return .{ .span = binary.op_span, .op = switch (binary.op) {
        .add => .add_i64_checked,
        .sub => .sub_i64_checked,
        .mul => .mul_i64_checked,
        .div => .div_i64_checked,
        .rem => .rem_i64_checked,
        .floor_div,
        .floor_rem,
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
    return lowerWith(allocator, program, false);
}

/// Lower with an explicit `debug` policy: a ReleaseFast build drops the nodes.
pub fn lowerWith(allocator: std.mem.Allocator, program: typed.Program, drop_debug: bool) LowerError!bc.Program {
    const functions = try allocator.alloc(bc.Function, program.functions.len);
    for (program.functions, 0..) |function, index| functions[index] = try lowerFunction(allocator, program, function, true, drop_debug);
    const result: bc.Program = .{ .functions = functions, .main = program.main, .records = program.records };
    try bc.validate(allocator, result);
    return result;
}

/// Allocate a selective bytecode program. Selected functions carry lowered
/// instructions; every other entry keeps its checked policy, signature and
/// locals so callers can resolve callee ABIs without lowering that body. The
/// selection mask is caller-owned and must remain live through validation.
pub fn lowerSelected(allocator: std.mem.Allocator, program: typed.Program, selected: []const bool) LowerError!bc.Program {
    return lowerSelectedWith(allocator, program, selected, false);
}

/// Selective lowering with an explicit `debug` policy.
pub fn lowerSelectedWith(allocator: std.mem.Allocator, program: typed.Program, selected: []const bool, drop_debug: bool) LowerError!bc.Program {
    if (selected.len != program.functions.len) return error.InternalError;
    const functions = try allocator.alloc(bc.Function, program.functions.len);
    for (program.functions, 0..) |function, index| functions[index] = try lowerFunction(allocator, program, function, selected[index], drop_debug);
    const result: bc.Program = .{ .functions = functions, .main = program.main, .records = program.records };
    bc.validateSelected(allocator, result, selected) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    return result;
}

fn lowerFunction(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function, with_body: bool, drop_debug: bool) LowerError!bc.Function {
    var emitter: Emitter = .{ .allocator = allocator, .program = program, .drop_debug = drop_debug };
    defer emitter.loops.deinit(allocator);
    return .{
        .policy = .{
            .host = function.policy.host,
            .c_abi = function.policy.c_abi,
            .effect_bound = function.policy.effect_bound,
            .effects = function.policy.effects,
            .owner = function.policy.owner,
            .restricted = function.policy.restricted,
            .conversion = function.policy.conversion,
        },
        .signature = .{
            .parameter_count = function.signature.parameter_count,
            .return_type = function.signature.return_type,
            .mutates = function.signature.mutates,
            .return_origin = function.signature.return_origin,
            .declared_mutates = function.signature.declared_mutates,
            .mutation_facts = function.signature.mutation_facts,
        },
        .scope = .{
            .locals = function.scope.locals,
            .instructions = if (with_body and function.policy.host == null) try emitter.finish(function.scope.body) else &.{},
        },
        .id = function.id,
        .name = function.name,
    };
}

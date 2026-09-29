//! Backend-independent typed operand-stack control-flow analysis.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const prelude = @import("prelude.zig");
/// Invalid bytecode, unsupported lowering, or allocation failure.
pub const AnalyzeError = error{ InternalError, UnsupportedOperation, OutOfMemory };
/// Reachable instruction inputs and required operand storage.
pub const Function = struct { states: []?[]const typed.Type, stack_capacity: usize };
/// Analyze validated bytecode with allocations owned by the caller's arena.
pub fn analyze(allocator: std.mem.Allocator, program: bytecode.Program, function: bytecode.Function) AnalyzeError!Function {
    var analyzer = Analyzer{ .allocator = allocator, .program = program, .function = function };
    const capacity = try analyzer.analyze();
    return .{ .states = analyzer.states, .stack_capacity = capacity };
}
fn comparison(op: typed.BinaryOp) bool {
    return switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge, .f64_eq, .f64_lt, .f64_le => true,
        else => false,
    };
}
const Analyzer = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    function: bytecode.Function,
    states: []?[]const typed.Type = &.{},
    fn merge(self: *Analyzer, pc: usize, stack: []const typed.Type, queue: *std.ArrayList(usize)) AnalyzeError!void {
        if (pc >= self.states.len) return error.InternalError;
        if (self.states[pc]) |old| {
            if (!std.mem.eql(typed.Type, old, stack)) return error.InternalError;
        } else {
            self.states[pc] = try self.allocator.dupe(typed.Type, stack);
            try queue.append(self.allocator, pc);
        }
    }
    fn validateBinary(self: *Analyzer, ty: typed.Type, op: typed.BinaryOp) AnalyzeError!void {
        if (!ty.isInteger()) {
            if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return error.UnsupportedOperation;
            const record = self.program.records[ty.recordIndex()];
            const concatenation = record.managed and op == .add and (record.collection.kind == .string or record.collection.kind == .bytes);
            const sequence = record.collection.kind == .string or record.collection.kind == .bytes;
            const text_order = sequence and (op == .lt or op == .le or op == .gt or op == .ge);
            if (concatenation or text_order) return;
            if (op != .eq and op != .ne) return error.UnsupportedOperation;
        }
    }
    fn validateCast(self: *Analyzer, ty: typed.Type) AnalyzeError!void {
        if (!ty.isInteger()) {
            if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return error.UnsupportedOperation;
            const kind = self.program.records[ty.recordIndex()].collection.kind;
            if (kind != .string and kind != .bytes) return error.UnsupportedOperation;
        }
    }
    fn analyze(self: *Analyzer) AnalyzeError!usize {
        const code = self.function.scope.instructions;
        if (code.len == 0) return error.UnsupportedOperation;
        self.states = try self.allocator.alloc(?[]const typed.Type, code.len);
        @memset(self.states, null);
        var queue: std.ArrayList(usize) = .empty;
        try self.merge(0, &.{}, &queue);
        var cursor: usize = 0;
        var maximum: usize = 0;
        while (cursor < queue.items.len) : (cursor += 1) {
            const pc = queue.items[cursor];
            var stack: std.ArrayList(typed.Type) = .empty;
            try stack.appendSlice(self.allocator, self.states[pc].?);
            const op = code[pc].op;
            var pops: usize = 0;
            var result: ?typed.Type = null;
            switch (op) {
                .acquire_resource => |acquire| {
                    pops = 2;
                    result = acquire.output;
                },
                .complete_resource => |ty| {
                    pops = 1;
                    result = ty;
                },
                .restrict_resource => |restrict| {
                    pops = 1;
                    result = restrict.ty;
                },
                .dir_resource => |dir| {
                    pops = 2;
                    result = dir.output;
                },
                .host_resource => |host| {
                    pops = 2;
                    result = host.output;
                },
                .resource_io => |io| {
                    pops = if (io.kind == .write) 1 else 0;
                    result = io.output;
                },
                .external_read => |read| {
                    pops = 1;
                    result = read.output;
                },
                .stand_in => |kind| {
                    pops = kind.operands();
                    result = bytecode.standInOutput(kind);
                },
                .environment_get => |get| {
                    pops = 2;
                    result = get.output;
                },
                .environment_only => |only| {
                    pops = 2;
                    result = only.output;
                },
                .environment_names => |names| {
                    pops = 1;
                    result = names.output;
                },
                .print => |output| {
                    pops = output.types.len + @intFromBool(output.separator) + @intFromBool(output.terminator) + @intFromBool(output.stream);
                    result = .unit;
                },
                .stream_write => {
                    pops = 2;
                    result = .i64;
                },
                .file_access => |call| {
                    pops = call.operands;
                    result = call.output;
                },
                .file_method => |call| {
                    pops = @intFromBool(call.argument);
                    result = call.output;
                },
                .acquire_buffer => |ty| {
                    pops = 1;
                    result = ty;
                },
                .buffer_operation => |operation| {
                    pops = operation.kind.arity();
                    result = operation.output;
                },
                .try_result => |propagate| {
                    pops = 1;
                    result = if (typed.resultShape(propagate.input, self.program.records)) |shape| shape.ok_type else prelude.optionShape(propagate.input, self.program.records).?.element;
                },
                .function_value => |value| result = value.ty,
                .invoke => |callback_type| {
                    const signature = self.program.records[callback_type.recordIndex()].contract.callback.?;
                    pops = signature.valueCount() + 1;
                    result = signature.return_type;
                },
                .push_i64 => result = .i64,
                .push_integer => |v| result = v.ty,
                .push_bool => result = .bool,
                .push_unit => result = .unit,
                .load_local, .ref_local, .move_local => |slot| result = self.function.scope.locals[@backingInt(slot)].ty,
                .store_local, .pop, .acknowledge, .jump_if_false, .ret, .assert_true => pops = 1,
                .drop_local, .jump => {},
                .cast_integer => |ty| {
                    pops = 1;
                    result = ty;
                    try self.validateCast(ty);
                },
                .neg_integer => |ty| {
                    pops = 1;
                    result = ty;
                    if (!ty.isInteger()) return error.UnsupportedOperation;
                },
                .neg_i64_checked => {
                    pops = 1;
                    result = .i64;
                },
                .not_bool => {
                    pops = 1;
                    result = .bool;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked => {
                    pops = 2;
                    result = .i64;
                },
                .wrap_domain => |ty| {
                    pops = 1;
                    result = ty;
                },
                .value_copy => |copy| {
                    pops = 1;
                    result = copy.ty;
                },
                .unwrap_domain => |ty| {
                    pops = 1;
                    if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return error.InternalError;
                    result = self.program.records[ty.recordIndex()].shape.domain orelse return error.InternalError;
                },
                .make_record => |record| {
                    pops = record.fields;
                    result = record.ty;
                },
                .update_record => |update| {
                    pops = update.indices.len + 1;
                    result = update.ty;
                },
                .get_field => |index| {
                    if (stack.items.len == 0) return error.InternalError;
                    const owner = stack.items[stack.items.len - 1];
                    if (!owner.isAggregate() or owner.recordIndex() >= self.program.records.len) return error.InternalError;
                    const record = self.program.records[owner.recordIndex()];
                    if (index >= record.fields.len) return error.InternalError;
                    pops = 1;
                    result = record.fields[index].ty;
                },
                .get_index => |access| {
                    const ty = access.ty;
                    if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) return error.InternalError;
                    const record = self.program.records[ty.recordIndex()];
                    pops = 2;
                    result = if (record.managed) (if (record.collection.kind == .string) ty else record.shape.buffer orelse return error.InternalError) else (record.shape.array orelse return error.UnsupportedOperation).element;
                },
                .replace_index => |access| {
                    pops = 3;
                    result = access.ty;
                },
                .array_length => |ty| {
                    pops = 1;
                    result = if (ty.isAggregate() and self.program.records[ty.recordIndex()].managed) .i64 else .u64;
                },
                .make_variant => |variant| {
                    if (!variant.ty.isAggregate() or variant.ty.recordIndex() >= self.program.records.len) return error.InternalError;
                    const variants = self.program.records[variant.ty.recordIndex()].shape.variants orelse return error.InternalError;
                    if (variant.tag >= variants.cases.len) return error.InternalError;
                    pops = @intFromBool(variants.cases[variant.tag].payload != null);
                    result = variant.ty;
                },
                .switch_variant => pops = 1,
                .cmp_i64, .cmp_bool, .cmp_domain, .cmp_enum => {
                    pops = 2;
                    result = .bool;
                },
                .binary_integer => |operation| {
                    pops = 2;
                    result = if (comparison(operation.op)) .bool else operation.ty;
                    try self.validateBinary(operation.ty, operation.op);
                },
                .unary_float => |unary| {
                    pops = 1;
                    result = if (unary == .f64_to_i64) .i64 else .u64;
                },
                .begin_arena, .end_arena => {},
                .arena_escape => |ty| {
                    pops = 1;
                    result = ty;
                },
                .call => |target| {
                    const callee = self.program.functions[@backingInt(target)];
                    pops = callee.signature.parameter_count;
                    result = callee.signature.return_type;
                },
            }
            if (pops > stack.items.len) return error.InternalError;
            stack.shrinkRetainingCapacity(stack.items.len - pops);
            if (result) |ty| try stack.append(self.allocator, ty);
            maximum = @max(maximum, stack.items.len);
            switch (op) {
                .ret => {},
                .try_result => |propagate| {
                    try self.merge(pc + 1, stack.items, &queue);
                    try self.merge(propagate.error_target, &.{propagate.output}, &queue);
                },
                .switch_variant => |dispatch| {
                    for (dispatch.arms) |arm| try self.merge(arm.target, stack.items, &queue);
                },
                .jump => |target| try self.merge(target, stack.items, &queue),
                .jump_if_false => |target| {
                    try self.merge(target, stack.items, &queue);
                    try self.merge(pc + 1, stack.items, &queue);
                },
                else => try self.merge(pc + 1, stack.items, &queue),
            }
        }
        return maximum;
    }
};

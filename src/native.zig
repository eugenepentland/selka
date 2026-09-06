//! Scalar C emission: direct labels/branches, explicit frames, checked arithmetic.
const jump_format = "goto L{d};\n";
const unsupported_feature = "E_NATIVE_FEATURE";
const binary_format = "V b = pop(), a = pop(); push(a {s} b);\n";
/// Failures returned by generate; callers must handle these boundary errors.
pub const GenerateError = error{
    InternalError,
    OutOfMemory,
    SourceError,
    WriteFailed,
};

const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const diagnostic = @import("diagnostic.zig");
const native_layout = @import("native_layout.zig");
fn payload(w: *std.Io.Writer, layout: native_layout.Layout, owner: typed.Type, ty: typed.Type) !void {
    if (layout.width(owner) == 0) {
        try w.writeAll("field_value(variant, 0)");
    } else {
        const tag_bits = native_layout.tagBits(layout.records[owner.recordIndex()].shape.variants.?.cases.len);
        try w.print("(Slot){{variant_payload(variant.number, {d}, {d}, {d}), NULL}}", .{ tag_bits, layout.width(ty), @intFromBool(layout.signed(ty)) });
    }
}
fn variantTag(w: *std.Io.Writer, layout: native_layout.Layout, ty: typed.Type) !void {
    if (layout.width(ty) == 0) return w.writeAll("variant.object->tag");
    try w.print("(size_t)((U)variant.number & variant_mask({d}))", .{native_layout.tagBits(layout.records[ty.recordIndex()].shape.variants.?.cases.len)});
}
fn variantValue(w: *std.Io.Writer, layout: native_layout.Layout, ty: typed.Type, tag: usize, payload_type: ?typed.Type) !void {
    if (layout.width(ty) == 0) {
        try w.print("boxed_variant({d}, value, {d})", .{ tag, @intFromBool(payload_type != null) });
    } else if (payload_type) |value_type| {
        try w.print("(Slot){{variant_make(value.number, {d}, {d}, {d}), NULL}}", .{ native_layout.tagBits(layout.records[ty.recordIndex()].shape.variants.?.cases.len), layout.width(value_type), tag });
    } else try w.print("(Slot){{{d}, NULL}}", .{tag});
}
fn indices(w: *std.Io.Writer, values: []const usize) !void {
    if (values.len == 0) return w.writeAll("NULL");
    try w.writeAll("(const size_t[]){");
    for (values) |value| try w.print("{d},", .{value});
    try w.writeByte('}');
}
fn enter(w: *std.Io.Writer, function: bc.Function, target: usize) !void {
    try w.print("enter({d}, {d}, {d}, {d}, {d}, ", .{ @backingInt(function.id), function.scope.locals.len, bc.valueParameterCount(function), target, function.scope.references.len });
    if (bc.valueParameterCount(function) == 0) {
        try w.writeAll("NULL");
    } else {
        try w.writeAll("(const size_t[]){");
        for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
            if (local.parameter.reference_parameter == null) try w.print("{d},", .{index});
        }
        try w.writeByte('}');
    }
    try w.writeAll(");\n");
}
fn literal(w: *std.Io.Writer, value: i128) !void {
    try w.print("({s}(V)UINT64_C({d}))", .{ if (value < 0) "-" else "", @abs(value) });
}
fn string(w: *std.Io.Writer, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |byte| try w.print("\\{o:0>3}", .{byte});
    try w.writeByte('"');
}
fn limits(w: *std.Io.Writer, ty: typed.Type) !void {
    try literal(w, ty.min());
    try w.writeAll(", ");
    try literal(w, ty.max());
}
fn predicate(op: typed.BinaryOp) []const u8 {
    return switch (op) {
        .eq => "==",
        .ne => "!=",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        else => unreachable,
    };
}
/// Validate supported bytecode and allocate standalone C source; report unsupported features through the sink.
pub fn generate(allocator: std.mem.Allocator, program: bc.Program, src: Source, sink: *diagnostic.Sink) GenerateError![]u8 {
    return generateInner(allocator, program, src, sink) catch |err| switch (err) {
        error.WriteFailed => error.OutOfMemory,
        else => err,
    };
}
fn generateInner(allocator: std.mem.Allocator, program: bc.Program, src: Source, sink: *diagnostic.Sink) ![]u8 {
    try bc.validate(allocator, program);
    var layout = try native_layout.Layout.init(allocator, program.records);
    defer layout.deinit();
    const offsets = try allocator.alloc(usize, program.functions.len);
    defer allocator.free(offsets);
    var count: usize = 0;
    for (program.functions, offsets) |function, *offset| {
        offset.* = count;
        count += function.scope.instructions.len;
        try checkFunction(layout, function, sink);
    }
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const w = &output.writer;
    try w.print("#define MYLANG_GUEST_VALUE_BYTES {d}\n", .{@sizeOf(typed.Value)});
    try w.writeAll(@embedFile("native_runtime.c"));
    try w.writeAll("\nstatic const char *const names[] = {\n");
    for (program.functions) |function| {
        try string(w, function.name);
        try w.writeAll(",\n");
    }
    try w.writeAll("};\nstatic const size_t lines[] = {");
    for (program.functions) |function| for (function.scope.instructions) |ins| try w.print("{d},", .{src.locate(ins.span.start).line});
    try w.writeAll("};\nstatic const size_t columns[] = {");
    for (program.functions) |function| for (function.scope.instructions) |ins| try w.print("{d},", .{src.locate(ins.span.start).column});
    try w.writeAll("};\nstatic const char *const paths[] = {\n");
    for (program.functions) |function| for (function.scope.instructions) |ins| {
        try string(w, src.locate(ins.span.start).path);
        try w.writeAll(",\n");
    };
    try w.writeAll("};\nint main(int argc, char **argv) {\nsource_paths = paths; function_names = names; source_lines = lines; source_columns = columns;\noptions(argc, argv); size_t return_target = 0;\n");
    const main_index = @backingInt(program.main);
    for (program.functions[main_index].scope.locals[0..program.functions[main_index].signature.parameter_count]) |parameter| {
        if (parameter.ty != .allocator) return sink.fail(unsupported_feature, parameter.declaration, "native entry parameters require root allocator authority");
        try w.writeAll("push(1);\n");
    }
    try enter(w, program.functions[main_index], 0);
    try w.print(jump_format, .{offsets[main_index]});
    for (program.functions, offsets) |function, offset| {
        for (function.scope.instructions, 0..) |ins, pc| {
            const location = offset + pc;
            try w.print("L{d}: {{ tick({d});\n", .{ location, location });
            const falls_through = try writeOperation(.{
                .writer = w,
                .layout = layout,
                .program = program,
                .offsets = offsets,
                .function = function,
                .position = .{ .offset = offset, .location = location },
                .instruction = ins,
            });
            if (falls_through) {
                if (pc + 1 < function.scope.instructions.len) try w.print(jump_format, .{location + 1}) else try w.writeAll("host_failure(\"InternalError\");\n");
            }
            try w.writeAll("}\n");
        }
    }
    try w.writeAll("dispatch_return: switch (return_target) {\n");
    for (program.functions, offsets) |function, offset| for (function.scope.instructions, 0..) |ins, pc| if (ins.op == .call or ins.op == .call_refs or ins.op == .call_borrow) {
        try w.print("case {d}: goto L{d};\n", .{ offset + pc + 1, offset + pc + 1 });
    };
    try w.writeAll("default: host_failure(\"InternalError\"); } return 2;\n}\n");
    return output.toOwnedSlice();
}

fn checkFunction(layout: native_layout.Layout, function: bc.Function, sink: *diagnostic.Sink) !void {
    if (!layout.supports(function.signature.return_type)) return sink.fail(unsupported_feature, function.scope.instructions[0].span, "native execution does not yet support this signature");
    for (function.scope.locals) |local| if (!layout.supports(local.ty)) return sink.fail(unsupported_feature, local.declaration, "native execution requires supported value locals and parameters");
    for (function.scope.references) |reference| if (!layout.supports(reference.ty)) return sink.fail(unsupported_feature, reference.declaration, "native references require supported value types");
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .make_variant => |variant| {
            if (!layout.supports(variant.ty)) return sink.fail(unsupported_feature, instruction.span, "native variant representation requires supported payloads");
        },
        .switch_variant => |dispatch| {
            if (!layout.supports(dispatch.ty)) return sink.fail(unsupported_feature, instruction.span, "native matching requires a supported variant layout");
        },
        .try_result => |propagate| {
            if (!layout.supports(propagate.input) or !layout.supports(propagate.output)) return sink.fail(unsupported_feature, instruction.span, "native propagation requires supported result layouts");
        },
        .acknowledge => |ty| {
            if (!layout.supports(ty)) return sink.fail(unsupported_feature, instruction.span, "native acknowledgement requires a supported result layout");
        },
        .make_record => |record| {
            if (!layout.supports(record.ty)) return sink.fail(unsupported_feature, instruction.span, "native aggregate construction requires supported fields");
        },
        .update_record => |record| {
            if (!layout.supports(record.ty)) return sink.fail(unsupported_feature, instruction.span, "native record updates require supported fields");
        },
        .get_index, .replace_index, .array_length => |ty| {
            if (!layout.supports(ty)) return sink.fail(unsupported_feature, instruction.span, "native arrays require supported elements");
        },
        .get_field, .read_field, .take_field, .begin_borrow, .begin_slice, .end_borrow, .read_ref, .write_ref, .read_slice, .write_slice, .len_slice, .call_refs, .call_borrow, .capture_ref, .ret_ref => {},
        .cmp_enum,
        .wrap_domain,
        .unwrap_domain,
        .push_i64,
        .push_bool,
        .push_integer,
        .cast_integer,
        .neg_integer,
        .binary_integer,
        .drop_local,
        .move_local,
        .load_local,
        .acquire_buffer,
        .buffer_operation,
        .store_local,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .pop,
        .jump,
        .jump_if_false,
        .call,
        .ret,
        => {},
        else => return sink.fail(unsupported_feature, instruction.span, "this operation is not yet supported by native execution"),
    };
}

const InstructionOutput = struct {
    writer: *std.Io.Writer,
    layout: native_layout.Layout,
    program: bc.Program,
    offsets: []const usize,
    function: bc.Function,
    position: struct { offset: usize, location: usize },
    instruction: bc.Instruction,
};
fn writeOperation(context: InstructionOutput) !bool {
    const w = context.writer;
    const layout = context.layout;
    const program = context.program;
    const offsets = context.offsets;
    const function = context.function;
    const offset = context.position.offset;
    const location = context.position.location;
    const ins = context.instruction;
    var falls_through = true;
    switch (ins.op) {
        .push_i64 => |value| {
            try w.writeAll("push(");
            try literal(w, value);
            try w.writeAll(");\n");
        },
        .push_integer => |number| {
            try w.writeAll("push(");
            try literal(w, number.value);
            try w.writeAll(");\n");
        },
        // Nominal identity and representation access are checked before
        // emission. Domains carry their scalar backing without host boxes.
        // The surrounding instruction tick still counts wrap/unwrap steps.
        .wrap_domain, .unwrap_domain => {},
        .make_variant => |variant| {
            const payload_type = program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag].payload;
            try w.print("Slot value = {s}; push_value(", .{if (payload_type != null) "pop_value()" else "(Slot){0}"});
            try variantValue(w, layout, variant.ty, variant.tag, payload_type);
            try w.writeAll(");\n");
        },
        .cmp_enum => |comparison| try w.print(binary_format, .{if (comparison.predicate == .eq) "==" else "!="}),
        .switch_variant => |dispatch| {
            const variants = program.records[dispatch.ty.recordIndex()].shape.variants.?;
            try w.writeAll("Slot variant = pop_value(); switch (");
            try variantTag(w, layout, dispatch.ty);
            try w.writeAll(") {\n");
            for (dispatch.arms, 0..) |arm, tag| {
                try w.print("case {d}: ", .{tag});
                if (arm.slot) |slot| {
                    try w.print("store_local({d}, ", .{@backingInt(slot)});
                    try payload(w, layout, dispatch.ty, variants.cases[tag].payload.?);
                    try w.writeAll("); ");
                }
                try w.print("release_value(variant); goto L{d};\n", .{offset + arm.target});
            }
            try w.writeAll("default: host_failure(\"InternalError\");\n}\n");
            falls_through = false;
        },
        .try_result => |propagate| {
            const input = typed.resultShape(propagate.input, program.records).?;
            const result = typed.resultShape(propagate.output, program.records).?;
            try w.writeAll("Slot variant = pop_value(); size_t tag = ");
            try variantTag(w, layout, propagate.input);
            try w.print("; if (tag == {d}) {{ Slot value = ", .{input.ok_tag});
            try payload(w, layout, propagate.input, input.ok_type);
            try w.print("; release_value(variant); push_value(value); }} else if (tag == {d}) {{ Slot value = ", .{input.error_tag});
            try payload(w, layout, propagate.input, input.error_type);
            try w.writeAll("; release_value(variant); clear_values(frames[nf-1].base); push_value(");
            try variantValue(w, layout, propagate.output, result.error_tag, result.error_type);
            try w.print("); goto L{d}; }} else host_failure(\"InternalError\");\n", .{offset + propagate.error_target});
        },
        .begin_borrow, .begin_slice => |id| {
            const reference = function.scope.references[@backingInt(id)];
            try w.print("begin_reference({d}, {d}, ", .{ @backingInt(id), @backingInt(reference.owner) });
            if (reference.parent) |parent| try w.print("{d}", .{@backingInt(parent)}) else try w.writeAll("SIZE_MAX");
            try w.print(", {d}, {d}, {d});\n", .{ @intFromBool(reference.mutable), @intFromBool(reference.mode.slice), @intFromBool(ins.op == .begin_slice) });
        },
        .end_borrow => |id| try w.print("end_reference({d});\n", .{@backingInt(id)}),
        .read_ref => |id| try w.print("read_reference({d});\n", .{@backingInt(id)}),
        .write_ref => |id| try w.print("write_reference({d});\n", .{@backingInt(id)}),
        .read_slice => |id| try w.print("read_slice({d});\n", .{@backingInt(id)}),
        .write_slice => |id| try w.print("write_slice({d});\n", .{@backingInt(id)}),
        .len_slice => |id| try w.print("length_slice({d});\n", .{@backingInt(id)}),
        .capture_ref => |id| try w.print("capture_reference({d});\n", .{@backingInt(id)}),
        .make_record => |record| {
            try w.print("make_record({d}, ", .{record.fields});
            try indices(w, record.order);
            try w.writeAll(");\n");
        },
        .update_record => |update| {
            try w.print("update_record({d}, ", .{update.indices.len});
            try indices(w, update.indices);
            try w.writeAll(");\n");
        },
        .get_field => |index| try w.print("get_field({d});\n", .{index}),
        .get_index => try w.writeAll("get_index();\n"),
        .replace_index => try w.writeAll("replace_index();\n"),
        .array_length => try w.writeAll("array_length();\n"),
        .read_field => |read| try w.print("push_value(field_value(local_access({d}, 0)->value, {d}));\n", .{ @backingInt(read.owner), read.field }),
        .take_field => |take| try w.print("take_field({d}, {d});\n", .{ @backingInt(take.owner), take.field }),
        .acquire_buffer => |ty| {
            const shape = typed.resultShape(ty, program.records).?;
            try w.print("push_value(acquire_buffer({d}, {d}));\n", .{ shape.ok_tag, shape.error_tag });
        },
        .buffer_operation => |operation| {
            switch (operation.kind) {
                .length, .capacity => try w.print("push((V)buffer_{s}({d}));\n", .{ @tagName(operation.kind), @backingInt(operation.owner) }),
                .read => try w.print("push_value(buffer_read({d}));\n", .{@backingInt(operation.owner)}),
                else => {
                    try w.print("int status = buffer_{s}({d}); Slot value = (Slot){{status ? status : 1, NULL}};\n", .{ @tagName(operation.kind), @backingInt(operation.owner) });
                    const shape = typed.resultShape(operation.output, program.records).?;
                    try w.writeAll("if (status) { push_value(");
                    try variantValue(w, layout, operation.output, shape.error_tag, shape.error_type);
                    try w.writeAll("); } else { push_value(");
                    try variantValue(w, layout, operation.output, shape.ok_tag, shape.ok_type);
                    try w.writeAll("); }\n");
                },
            }
        },
        .acknowledge, .pop => try w.writeAll("release_value(pop_value());\n"),
        .move_local => |slot| try w.print("move_local({d});\n", .{@backingInt(slot)}),
        .push_bool => |value| try w.print("push({d});\n", .{@intFromBool(value)}),
        .drop_local => |slot| try w.print("store_local({d}, (Slot){{0}});\n", .{@backingInt(slot)}),
        .load_local => |slot| try w.print("load_local({d});\n", .{@backingInt(slot)}),
        .store_local => |slot| try w.print("store_local({d}, pop_value());\n", .{@backingInt(slot)}),
        .not_bool => try w.writeAll("push(!pop());\n"),
        .cmp_i64 => |op| try w.print(binary_format, .{predicate(std.meta.stringToEnum(typed.BinaryOp, @tagName(op)).?)}),
        .cmp_bool => |op| try w.print(binary_format, .{if (op == .eq) "==" else "!="}),
        .cast_integer, .neg_integer, .neg_i64_checked => {
            const ty = switch (ins.op) {
                .cast_integer, .neg_integer => |ty| ty,
                else => typed.Type.i64,
            };
            try w.print("push(checked({s}pop(), ", .{if (ins.op == .cast_integer) "" else "-"});
            try limits(w, ty);
            try w.writeAll("));\n");
        },
        .binary_integer, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked => {
            const ty = if (ins.op == .binary_integer) ins.op.binary_integer.ty else typed.Type.i64;
            const operation: typed.BinaryOp = switch (ins.op) {
                .binary_integer => |binary| binary.op,
                .add_i64_checked => .add,
                .sub_i64_checked => .sub,
                .mul_i64_checked => .mul,
                .div_i64_checked => .div,
                else => .rem,
            };
            try w.writeAll("V b = pop(), a = pop(); ");
            switch (operation) {
                .eq, .ne, .lt, .le, .gt, .ge => try w.print("push(a {s} b);\n", .{predicate(operation)}),
                else => {
                    const code: usize = switch (operation) {
                        .add => 0,
                        .sub => 1,
                        .mul => 2,
                        .div => 3,
                        .rem => 4,
                        else => unreachable,
                    };
                    try w.print("push(arithmetic({d}, a, b, ", .{code});
                    try limits(w, ty);
                    try w.writeAll("));\n");
                },
            }
        },
        .jump => |target| {
            try w.print(jump_format, .{offset + target});
            falls_through = false;
        },
        .jump_if_false => |target| try w.print("if (!pop()) goto L{d};\n", .{offset + target}),
        .call, .call_refs, .call_borrow => {
            const callee_id = switch (ins.op) {
                .call => |id| id,
                .call_refs => |call| call.function,
                .call_borrow => |call| call.function,
                else => unreachable,
            };
            const loans: []const typed.ReferenceId = switch (ins.op) {
                .call => &.{},
                .call_refs => |call| call.references,
                .call_borrow => |call| call.references,
                else => unreachable,
            };
            const callee = @backingInt(callee_id);
            const target = program.functions[callee];
            try enter(w, target, location + 1);
            try w.writeAll("binding_call = 1;\n");
            if (ins.op == .call_borrow) {
                const destination = ins.op.call_borrow.destination;
                const reference = function.scope.references[@backingInt(destination)];
                try w.print("prepare_reference_return({d}, {d}, {d});\n", .{ @backingInt(destination), @backingInt(reference.parent.?), @intFromBool(reference.mutable) });
            }
            var argument: usize = 0;
            for (target.scope.references, 0..) |reference, index| if (reference.mode.parameter) {
                try w.print("bind_reference({d}, {d}, {d});\n", .{ index, @backingInt(loans[argument]), @intFromBool(reference.mutable) });
                argument += 1;
            };
            try w.print("binding_call = 0; goto L{d};\n", .{offsets[callee]});
            falls_through = false;
        },
        .ret_ref => {
            try w.writeAll("return_target = leave_reference(); goto dispatch_return;\n");
            falls_through = false;
        },
        .ret => {
            try w.writeAll("Slot result = pop_value(); size_t target = leave(result); if (!nf) { printf(\"%\" PRId64 \"\\n\", (int64_t)result.number); cleanup(); return 0; }\nreturn_target = target; goto dispatch_return;\n");
            falls_through = false;
        },
        else => unreachable,
    }
    return falls_through;
}

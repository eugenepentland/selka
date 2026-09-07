//! Scalar C emission: direct labels/branches, explicit frames, checked arithmetic.
const native_host = @import("native_host.zig");
const callables = @import("callables.zig");
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
const native_wire = @import("native_wire.zig");
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
fn statusResult(w: *std.Io.Writer, layout: native_layout.Layout, ty: typed.Type) !void {
    const shape = typed.resultShape(ty, layout.records).?;
    try w.writeAll("if (status) { push_value(");
    try variantValue(w, layout, ty, shape.error_tag, shape.error_type);
    try w.writeAll("); } else { push_value(");
    try variantValue(w, layout, ty, shape.ok_tag, shape.ok_type);
    try w.writeAll("); }\n");
}
fn writeResourceIo(w: *std.Io.Writer, layout: native_layout.Layout, operation: @FieldType(@FieldType(bc.Instruction, "op"), "resource_io")) !void {
    try w.print("Slot value = (Slot){{0}}; int status = resource_{s}({d}, ", .{ @tagName(operation.kind), @backingInt(operation.owner) });
    if (operation.reference) |reference| try w.print("{d}", .{@backingInt(reference)}) else try w.writeAll("SIZE_MAX");
    if (operation.kind == .read) {
        if (operation.reference != null) {
            const shape = typed.resourceSliceReadShape(operation.output, layout.records).?;
            try w.print(", 0, 0, {d}, {d}", .{ shape.length_field, shape.eof_field });
        } else {
            const shape = typed.resourceReadShape(operation.output, layout.records).?;
            const capacity = layout.records[shape.bytes_type.recordIndex()].shape.array.?.length;
            try w.print(", {d}, {d}, {d}, {d}", .{ capacity, shape.bytes_field, shape.length_field, shape.flag_field });
        }
    }
    try w.writeAll(", &value); if (status) value = (Slot){status, NULL};\n");
    try statusResult(w, layout, operation.output);
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
    return generateWithInterface(allocator, program, src, sink, .{});
}
/// Checked public roots and optional canonical schema bytes from the same compilation.
pub const Interface = struct { roots: []const typed.FunctionId = &.{}, schema: ?[]const u8 = null };
/// Generate native C retaining the selected public roots and immutable schema identity.
pub fn generateWithInterface(allocator: std.mem.Allocator, program: bc.Program, src: Source, sink: *diagnostic.Sink, interface: Interface) GenerateError![]u8 {
    return generateInner(allocator, program, src, sink, interface) catch |err| switch (err) {
        error.WriteFailed => error.OutOfMemory,
        else => err,
    };
}
fn generateInner(allocator: std.mem.Allocator, program: bc.Program, src: Source, sink: *diagnostic.Sink, interface: Interface) ![]u8 {
    try bc.validate(allocator, program);
    var layout = try native_layout.Layout.init(allocator, program.records);
    defer layout.deinit();
    const wire_types = try native_wire.supported(allocator, program.records, false);
    defer allocator.free(wire_types);
    const codec_types = try native_wire.supported(allocator, program.records, true);
    defer allocator.free(codec_types);
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
    if (hasJsonSupport(program)) try writeJsonSupport(w);
    try w.print("#define MYLANG_GUEST_VALUE_BYTES {d}\n", .{@sizeOf(typed.Value)});
    try w.writeAll(@embedFile("native_host.h"));
    try w.writeAll(@embedFile("native_providers.h"));
    try w.writeAll(@embedFile("native_embed.h"));
    try w.writeAll(@embedFile("native_runtime.c"));
    try w.writeAll(@embedFile("native_resources.c"));
    if (hasFloatSupport(program)) try w.writeAll(@embedFile("native_math.c"));
    try native_host.emit(w, layout, program);
    if (hasJsonSupport(program)) {
        try @import("native_json_schema.zig").emit(w, program);
        try w.writeAll(@embedFile("native_json.c"));
    }
    try writeInterface(w, interface.schema);
    try native_wire.emit(w, layout, codec_types, program.functions);
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
    try w.writeAll("};\nstatic int execute_entry(const char *entry_name, const MylangScalar *arguments, size_t argument_count, size_t codec_entry) {\n" ++
        "source_paths = paths; function_names = names; source_lines = lines; source_columns = columns;\n" ++
        "validate_resource_providers(); size_t return_target = 0;\n");
    try writeCodecDispatch(allocator, w, program, offsets);
    try w.writeAll("host_begin();\n");
    try writeExports(w, program, offsets, interface.roots, wire_types, codec_types);
    const main_index = @backingInt(program.main);
    for (program.functions[main_index].scope.locals[0..program.functions[main_index].signature.parameter_count]) |parameter| {
        switch (parameter.ty) {
            .allocator => try w.writeAll("push(1);\n"),
            .clock_cap => try w.writeAll("grant_external(0);\n"),
            .random_cap => try w.writeAll("grant_external(1);\n"),
            .environment_cap => try w.writeAll("grant_external(2);\n"),
            .filesystem_cap => try w.writeAll("grant_resource(0);\n"),
            .network_cap => try w.writeAll("grant_resource(1);\n"),
            else => return sink.fail(unsupported_feature, parameter.declaration, "native entry capability is unsupported"),
        }
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
    for (program.functions, offsets) |function, offset| for (function.scope.instructions, 0..) |ins, pc| if (ins.op == .call or ins.op == .call_refs or ins.op == .call_borrow or ins.op == .invoke) {
        try w.print("case {d}: goto L{d};\n", .{ offset + pc + 1, offset + pc + 1 });
    };
    try w.writeAll("default: host_failure(\"InternalError\"); } return 2;\n}\n");
    if (hasJsonSupport(program)) try w.writeAll(@embedFile("native_json_call.c"));
    try w.writeAll("#ifndef MYLANG_EMBED\nint main(int argc,char **argv) { options(argc,argv);providers=mylang_native_providers();return execute_entry(NULL,NULL,0,SIZE_MAX); }\n#endif\n");
    try w.writeAll(@embedFile("native_embed.c"));
    return output.toOwnedSlice();
}

fn writeCodecDispatch(allocator: std.mem.Allocator, w: *std.Io.Writer, program: bc.Program, offsets: []const usize) !void {
    const selected = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(selected);
    @memset(selected, false);
    for (program.records) |record| if (record.contract.codec) |codec| {
        const decode = @backingInt(codec.decode);
        const encode = @backingInt(codec.encode);
        if (decode >= selected.len or encode >= selected.len) return error.InternalError;
        selected[decode] = true;
        selected[encode] = true;
    };
    try w.writeAll("const size_t return_depth = nf;\nif (codec_entry != SIZE_MAX) { switch (codec_entry) {\n");
    for (program.functions, offsets, selected) |function, offset, enabled| {
        if (!enabled) continue;
        try w.print("case {d}:\n", .{@backingInt(function.id)});
        try enter(w, function, 0);
        try w.print(jump_format, .{offset});
    }
    try w.writeAll("default: host_failure(\"InternalError\"); } }\n");
}

fn writeInterface(w: *std.Io.Writer, schema: ?[]const u8) !void {
    try w.writeAll("#ifdef MYLANG_EMBED\nconst char *mylang_native_schema_json_v1(void) { return ");
    if (schema) |bytes| try string(w, bytes) else try w.writeAll("NULL");
    try w.writeAll("; }\nconst char *mylang_native_schema_sha256_v1(void) { return ");
    if (schema) |bytes| {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        try string(w, &std.fmt.bytesToHex(digest, .lower));
    } else try w.writeAll("NULL");
    try w.writeAll("; }\n#endif\n");
}

fn scalarSignature(function: bc.Function) bool {
    if (function.signature.return_reference != null) return false;
    if (!scalarType(function.signature.return_type)) return false;
    for (function.scope.locals[0..function.signature.parameter_count]) |local| {
        if (local.parameter.reference_parameter != null or !scalarType(local.ty)) return false;
    }
    return true;
}
fn scalarType(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool;
}
fn writeExports(w: *std.Io.Writer, program: bc.Program, offsets: []const usize, roots: []const typed.FunctionId, wire_types: []const bool, codec_types: []const bool) !void {
    try w.writeAll("#ifdef MYLANG_EMBED\nif (entry_name) {\n");
    for (roots) |root| {
        const index = @backingInt(root);
        if (index >= program.functions.len) return error.InternalError;
        const function = program.functions[index];
        try w.writeAll("if (!strcmp(entry_name, ");
        try string(w, function.name);
        try w.writeAll(")) {\n");
        try w.writeAll("if (wire_call) {\n");
        if (native_wire.signature(function, codec_types)) {
            if (!native_wire.signature(function, wire_types)) try w.writeAll("if (!wire_call->codecs) host_failure(\"UnsupportedSignature\");\n");
            for (function.scope.locals[0..function.signature.parameter_count]) |local|
                try w.print("wire_read({d}, 0);\n", .{@backingInt(local.ty)});
            try w.writeAll("if (wire_call->cursor != wire_call->count) host_failure(\"InvalidArgument\");\n");
            try w.writeAll("wire_count_call();\n");
            try w.print("wire_call->return_type = {d};\n", .{@backingInt(function.signature.return_type)});
            try enter(w, function, 0);
            try w.print(jump_format, .{offsets[index]});
        } else try w.writeAll("host_failure(\"UnsupportedSignature\");\n");
        try w.writeAll("}\n");
        if (scalarSignature(function)) {
            try w.print("if (argument_count != {d}) host_failure(\"InvalidArgument\");\n", .{function.signature.parameter_count});
            for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, i| {
                try w.print("if (!arguments[{d}].type || strcmp(arguments[{d}].type, ", .{ i, i });
                try string(w, typed.typeName(local.ty, program.records));
                try w.writeAll(")) host_failure(\"InvalidArgument\");\n");
                try w.print("push(wire_scalar({d}, arguments[{d}].bits));\n", .{ @backingInt(local.ty), i });
            }
            try w.writeAll("native_type = ");
            try string(w, typed.typeName(function.signature.return_type, program.records));
            try w.writeAll(";\n");
            try enter(w, function, 0);
            try w.print(jump_format, .{offsets[index]});
        } else try w.writeAll("host_failure(\"UnsupportedSignature\");\n");
        try w.writeAll("}\n");
    }
    try w.writeAll("host_failure(\"UnknownFunction\");\n}\n#endif\n");
}

fn checkFunction(layout: native_layout.Layout, function: bc.Function, sink: *diagnostic.Sink) !void {
    if (!layout.supports(function.signature.return_type)) return sink.fail(unsupported_feature, function.scope.instructions[0].span, "native execution does not yet support this signature");
    for (function.scope.locals) |local| if (!layout.supports(local.ty)) return sink.fail(unsupported_feature, local.declaration, "native execution requires supported value locals and parameters");
    for (function.scope.references) |reference| if (!layout.supports(reference.ty)) return sink.fail(unsupported_feature, reference.declaration, "native references require supported value types");
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .cmp_domain, .json_codec => {},
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
        .function_value, .invoke => {},
        .get_field, .read_field, .take_field, .split_borrow, .begin_borrow, .begin_slice, .end_borrow, .read_ref, .write_ref, .read_slice, .write_slice, .len_slice, .call_refs, .call_borrow, .capture_ref, .ret_ref => {},
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
        .acquire_pool,
        .acquire_resource,
        .complete_resource,
        .restrict_resource,
        .resource_io,
        .external_read,
        .environment_get,
        .pool_operation,
        .cmp_handle,
        .begin_region,
        .end_region,
        .reset_arena,
        .buffer_operation,
        .store_local,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .unary_float,
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
fn writeIndirect(context: InstructionOutput, ty: typed.Type) !void {
    const w = context.writer;
    const program = context.program;
    const offsets = context.offsets;
    const location = context.position.location;
    const contract = callables.signature(ty, program.records).?;
    try w.print("switch (callback_target({d})) {{\n", .{contract.parameters.len});
    for (program.functions, 0..) |target, target_id| {
        if (!callables.accepts(contract, target)) continue;
        try w.print("case {d}: ", .{target_id});
        if (target.policy.host != null) {
            try w.print("host_invoke({d}); goto L{d};\n", .{ native_host.declarationIndex(program.functions, target_id), location + 1 });
        } else {
            try enter(w, target, location + 1);
            try w.print("goto L{d};\n", .{offsets[target_id]});
        }
    }
    try w.writeAll("default: host_failure(\"InternalError\");\n}\n");
}
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
        .cmp_domain => |comparison| try w.print(binary_format, .{if (comparison.predicate == .eq) "==" else "!="}),
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
            try w.writeAll("; release_value(variant); Slot propagated = ");
            try variantValue(w, layout, propagate.output, result.error_tag, result.error_type);
            try w.print("; clear_values(frames[nf-1].base); push_value(propagated); goto L{d}; }} else host_failure(\"InternalError\");\n", .{offset + propagate.error_target});
        },
        .split_borrow => |pair| {
            const parent = function.scope.references[@backingInt(pair.left)].parent.?;
            try w.print("split_reference({d}, {d}, {d});\n", .{ @backingInt(parent), @backingInt(pair.left), @backingInt(pair.right) });
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
        .read_field => |read| {
            try w.writeAll("push_value(field_value(");
            try operationOwner(w, read.owner, read.reference, false);
            try w.print("->value, {d}));\n", .{read.field});
        },
        .take_field => |take| try w.print("take_field({d}, {d});\n", .{ @backingInt(take.owner), take.field }),
        .environment_get => |operation| {
            const shape = typed.environmentShape(operation.output, program.records).?;
            const capacity = program.records[shape.bytes_type.recordIndex()].shape.array.?.length;
            try w.print("push_value(environment_lookup({d}, {d}, {d}, {d}, {d}, {d}));\n", .{
                capacity, shape.result.ok_tag, shape.result.error_tag, shape.bytes_field, shape.length_field, shape.flag_field,
            });
        },
        .external_read => |operation| {
            try w.print("Slot value = (Slot){{0}}; int status = external_read({d}, &value); if (status) value = (Slot){{status, NULL}};\n", .{@intFromBool(operation.kind == .random)});
            try statusResult(w, layout, operation.output);
        },
        .cmp_handle => |operation| try w.print("compare_handle({d});\n", .{@intFromBool(operation.predicate == .ne)}),
        .acquire_resource => |operation| {
            const shape = typed.resultShape(operation.output, program.records).?;
            const kind = typed.resourceKind(shape.ok_type, program.records).?;
            try w.print("push_value(acquire_resource({d}, {d}, {d}));\n", .{ @intFromBool(kind == .network), shape.ok_tag, shape.error_tag });
        },
        .complete_resource => |ty| {
            const shape = typed.completionShape(ty, program.records).?;
            try w.print("push_value(complete_resource({d}, {d}, {d}, {d}));\n", .{ shape.result.ok_tag, shape.result.error_tag, shape.resource_field, shape.code_field });
        },
        .resource_io => |operation| try writeResourceIo(w, layout, operation),
        .restrict_resource => |operation| try w.print("restrict_resource({d});\n", .{operation.permissions}),
        .acquire_pool => |ty| {
            const shape = typed.resultShape(ty, program.records).?;
            try w.print("push_value(acquire_pool({d}, {d}));\n", .{ shape.ok_tag, shape.error_tag });
        },
        .pool_operation => |operation| {
            try w.writeAll("Local *container = ");
            try operationOwner(w, operation.owner, operation.reference, operation.kind.mutates());
            try w.writeAll(";\n");
            if (operation.kind.fallible()) {
                try w.print("Slot value = (Slot){{0}}; int status = pool_{s}(container, &value); if (status) value = (Slot){{status, NULL}};\n", .{@tagName(operation.kind)});
                try statusResult(w, layout, operation.output);
            } else try w.print("push((V)pool_{s}(container));\n", .{@tagName(operation.kind)});
        },
        .begin_region => |slot| try w.print("begin_region({d});\n", .{@backingInt(slot)}),
        .end_region => |slot| try w.print("end_region({d});\n", .{@backingInt(slot)}),
        .reset_arena => |ty| {
            try w.writeAll("int status = reset_arena(); Slot value = (Slot){status ? status : 1, NULL};\n");
            try statusResult(w, layout, ty);
        },
        .json_codec => |operation| {
            const result = typed.resultShape(operation.output, program.records).?;
            if (operation.document) {
                try w.print("push_value(json_document({d}, {d}));\n", .{ result.ok_tag, result.error_tag });
            } else {
                const value_type = if (operation.decode) result.ok_type else operation.input;
                try w.print("NativeJsonResult converted=json_typed({d}, {d}); int status=converted.status; " ++
                    "Slot value=converted.value; if(status) value=(Slot){{status,NULL}};\n", .{ @backingInt(value_type), @intFromBool(operation.decode) });
                try statusResult(w, layout, operation.output);
            }
        },
        .acquire_buffer => |ty| {
            const shape = typed.resultShape(ty, program.records).?;
            try w.print("push_value(acquire_buffer({d}, {d}));\n", .{ shape.ok_tag, shape.error_tag });
        },
        .buffer_operation => |operation| {
            try w.writeAll("Local *container = ");
            try operationOwner(w, operation.owner, operation.reference, operation.kind.mutates());
            try w.writeAll(";\n");
            switch (operation.kind) {
                .length, .capacity => try w.print("push((V)buffer_{s}(container));\n", .{@tagName(operation.kind)}),
                .read => try w.writeAll("push_value(buffer_read(container));\n"),
                else => {
                    try w.print("int status = buffer_{s}(container); Slot value = (Slot){{status ? status : 1, NULL}};\n", .{@tagName(operation.kind)});
                    try statusResult(w, layout, operation.output);
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
        .unary_float => |op| {
            const code = floatUnaryCode(op);
            try w.print("push(float_unary({d}, (uint64_t)pop()));\n", .{code});
        },
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
                .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => {
                    const code = floatBinaryCode(operation);
                    try w.print("push(float_binary({d}, (uint64_t)a, (uint64_t)b));\n", .{code});
                },
                .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .wrapping_add, .wrapping_sub, .wrapping_mul, .saturating_add, .saturating_sub, .saturating_mul => {
                    const code: usize = switch (operation) {
                        .bit_and => 0,
                        .bit_or => 1,
                        .bit_xor => 2,
                        .shift_left => 3,
                        .shift_right => 4,
                        .wrapping_add => 5,
                        .wrapping_sub => 6,
                        .wrapping_mul => 7,
                        .saturating_add => 8,
                        .saturating_sub => 9,
                        .saturating_mul => 10,
                        else => unreachable,
                    };
                    const info = ty.integer().?;
                    try w.print("push(integer_extended({d}, a, b, {d}, {d}));\n", .{ code, info.bits, @intFromBool(info.signed) });
                },
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
        .function_value => |value| try w.print("push({d});\n", .{@backingInt(value.function)}),
        .invoke => |ty| {
            try writeIndirect(context, ty);
            falls_through = false;
        },
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
            if (target.policy.host != null) {
                try w.print("host_invoke({d});\n", .{native_host.declarationIndex(program.functions, callee)});
                return true;
            }
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
            try w.writeAll("Slot result = pop_value(); size_t target = leave(result);\n" ++
                "if (nf == return_depth && codec_entry != SIZE_MAX) return 0;\n#ifdef MYLANG_EMBED\nif (nf == return_depth) {\n" ++
                "wire_finish(result); native_value = (int64_t)result.number; native_bits = (uint64_t)(U)result.number; cleanup(); return 0; }\n" ++
                "#else\nif (!nf) { printf(\"%\" PRId64 \"\\n\", (int64_t)result.number); cleanup(); return 0; }\n#endif\n" ++
                "return_target = target; goto dispatch_return;\n");
            falls_through = false;
        },
    }
    return falls_through;
}

fn operationOwner(writer: *std.Io.Writer, owner: typed.LocalId, reference: ?typed.ReferenceId, mutable: bool) std.Io.Writer.Error!void {
    if (reference) |id| {
        try writer.print("reference_owner({d}, {d})", .{ @backingInt(id), @intFromBool(mutable) });
    } else try writer.print("local_access({d}, {d})", .{ @backingInt(owner), @intFromBool(mutable) });
}

fn hasJsonSupport(program: bc.Program) bool {
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (instruction.op == .json_codec) return true;
    };
    return false;
}

fn writeJsonSupport(w: *std.Io.Writer) error{WriteFailed}!void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    inline for (.{
        "native_json_bridge.zig",
        "native_json_abi.zig",
        "native_typed_json.zig",
        "native_json_calls.zig",
        "native_json_values.zig",
        "codec_execution.zig",
        "invocation_contract.zig",
        "json_document.zig",
        "typed_json.zig",
        "codec_memory.zig",
        "typed.zig",
        "runtime_values.zig",
    }) |path| {
        hash.update(path);
        hash.update("\x00");
        hash.update(@embedFile(path));
    }
    const digest = hash.finalResult();
    try w.print("#define MYLANG_NATIVE_JSON 1\n#define MYLANG_NATIVE_JSON_SUPPORT_SHA256 \"{s}\"\n", .{std.fmt.bytesToHex(digest, .lower)});
}

fn hasFloatSupport(program: bc.Program) bool {
    for (program.functions) |function| {
        for (function.scope.instructions) |instruction| {
            if (instruction.op == .unary_float) return true;
            if (instruction.op == .binary_integer and std.mem.startsWith(u8, @tagName(instruction.op.binary_integer.op), "f64_")) return true;
        }
    }
    return false;
}

fn floatUnaryCode(op: typed.UnaryOp) usize {
    return switch (op) {
        .f64_sqrt => 0,
        .f64_floor => 1,
        .f64_ceil => 2,
        .f64_trunc => 3,
        .f64_abs => 4,
        .f64_neg => 5,
        .f64_from_u64 => 6,
        .f64_to_u64 => 7,
        else => unreachable,
    };
}

fn floatBinaryCode(operation: typed.BinaryOp) usize {
    return switch (operation) {
        .f64_add => 0,
        .f64_sub => 1,
        .f64_mul => 2,
        .f64_div => 3,
        .f64_eq => 4,
        .f64_lt => 5,
        .f64_le => 6,
        else => unreachable,
    };
}

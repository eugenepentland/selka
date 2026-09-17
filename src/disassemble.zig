//! Deterministic instruction dumps show evaluation order and source locations.
const reference_format = " ref={d}";
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;

/// Render deterministic instructions, nominal schemas, and original source locations.
pub fn dump(allocator: std.mem.Allocator, program: bc.Program, src: Source) std.mem.Allocator.Error![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    // The allocating writer can fail only because its allocator failed.
    write(&text.writer, program, src) catch return error.OutOfMemory;
    return text.toOwnedSlice();
}

fn write(writer: *std.Io.Writer, program: bc.Program, src: Source) std.Io.Writer.Error!void {
    for (program.records) |record| try writeRecord(writer, program, record);
    for (program.functions) |function| try writeFunction(writer, program, src, function);
}

fn writeRecord(writer: *std.Io.Writer, program: bc.Program, record: typed.Record) std.Io.Writer.Error!void {
    try writer.print("{s} {s} type#{d}\n", .{ recordKind(record), record.name, @backingInt(record.id) });
    if (record.shape.variants) |v| for (v.cases, 0..) |variant, tag| {
        try writer.print("  variant {d}: {s}", .{ tag, variant.name });
        if (variant.payload) |ty| try writer.print(": {s}", .{typed.typeName(ty, program.records)});
        try writer.writeByte('\n');
    };
    if (record.shape.resource) |kind| try writer.print("  provider {s} (owned)\n", .{@tagName(kind)});
    if (record.shape.buffer) |element| try writer.print("  element {s} (managed)\n", .{typed.typeName(element, program.records)});
    if (record.shape.domain) |backing| try writer.print("  backing {s} (private)\n", .{typed.typeName(backing, program.records)});
    for (record.fields, 0..) |field, i| try writer.print("  field {d}: {s}: {s}\n", .{ i, field.name, typed.typeName(field.ty, program.records) });
}

fn writeFunction(writer: *std.Io.Writer, program: bc.Program, src: Source, function: bc.Function) std.Io.Writer.Error!void {
    if (function.policy.restricted) try writer.writeAll("private ");
    if (function.policy.conversion) try writer.writeAll("conversion ");
    try writer.print("function {s}(", .{function.name});
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |parameter, i| {
        if (i != 0) try writer.writeAll(", ");
        try writer.print("{s}: {s}", .{ parameter.name, typed.typeName(parameter.ty, program.records) });
    }
    try writer.print(") -> {s}\n", .{typed.typeName(function.signature.return_type, program.records)});
    if (function.policy.c_abi) try writer.print("  extern C symbol {s}\n", .{@import("c_abi.zig").symbol(function.name)}) else if (function.policy.host != null) try writer.writeAll("  host declaration\n");
    if (function.policy.effects != 0 or function.policy.effect_bound != null) {
        try writer.writeAll("  effects ");
        try @import("effect_set.zig").write(writer, function.policy.effects);
        if (function.policy.effect_bound) |bound| {
            try writer.writeAll(" allowed ");
            try @import("effect_set.zig").write(writer, bound.allowed);
        }
        try writer.writeByte('\n');
    }
    for (function.scope.instructions, 0..) |instruction, i| try writeInstruction(writer, program, src, instruction, i);
}

fn writeInstruction(writer: *std.Io.Writer, program: bc.Program, src: Source, instruction: bc.Instruction, i: usize) std.Io.Writer.Error!void {
    try writer.print("  {d:0>4}  ", .{i});
    switch (instruction.op) {
        .unary_float => |op| try writer.print("unary_float {s}", .{@tagName(op)}),
        .push_i64 => |value| try writer.print("PUSH_I64 {d}", .{value}),
        .make_record => |record| try writer.print("MAKE_RECORD type#{d} fields={d} order={any}", .{ @backingInt(record.ty), record.fields, record.order }),
        .update_record => |update| try writer.print("UPDATE_RECORD type#{d} fields={any}", .{ @backingInt(update.ty), update.indices }),
        .get_index => |ty| try writer.print("GET_INDEX {s}", .{typed.typeName(ty, program.records)}),
        .replace_index => |ty| try writer.print("REPLACE_INDEX {s}", .{typed.typeName(ty, program.records)}),
        .array_length => |ty| try writer.print("ARRAY_LENGTH {s}", .{typed.typeName(ty, program.records)}),
        .get_field => |index| try writer.print("GET_FIELD {d}", .{index}),
        .push_integer => |number| try writer.print("PUSH_INT {f} {d}", .{ number.ty, number.value }),
        .make_variant => |variant| try writer.print("MAKE_VARIANT {s}.{s}", .{
            typed.typeName(variant.ty, program.records),
            program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag].name,
        }),
        .switch_variant => |dispatch| {
            try writer.print("SWITCH_VARIANT {s}", .{typed.typeName(dispatch.ty, program.records)});
            for (dispatch.arms, program.records[dispatch.ty.recordIndex()].shape.variants.?.cases) |arm, variant| try writer.print(" {s}:target={d},slot={?d}", .{
                variant.name,
                arm.target,
                if (arm.slot) |slot| @as(?usize, @backingInt(slot)) else null,
            });
        },
        .cmp_domain => |comparison| try writer.print("CMP_DOMAIN {s} {s}", .{ typed.typeName(comparison.ty, program.records), @tagName(comparison.predicate) }),
        .cmp_enum => |comparison| try writer.print("CMP_ENUM {s} {s}", .{ typed.typeName(comparison.ty, program.records), @tagName(comparison.predicate) }),
        .begin_arena => |watermark| try writer.print("BEGIN_ARENA locals={d}", .{@backingInt(watermark)}),
        .end_arena => |watermark| try writer.print("END_ARENA locals={d}", .{@backingInt(watermark)}),
        .arena_escape => |ty| try writer.print("ARENA_ESCAPE {f}", .{ty}),
        .wrap_domain => |ty| try writer.print("WRAP_DOMAIN {s}", .{typed.typeName(ty, program.records)}),
        .unwrap_domain => |ty| try writer.print("UNWRAP_DOMAIN {s}", .{typed.typeName(ty, program.records)}),
        .cast_integer => |ty| try writer.print("CAST_INT {f}", .{ty}),
        .neg_integer => |ty| try writer.print("NEG_INT_CHECKED {f}", .{ty}),
        .binary_integer => |binary| try writer.print("INT_BINARY {f} {s}", .{ binary.ty, @tagName(binary.op) }),
        .push_unit => try writer.writeAll("PUSH_UNIT"),
        .push_bool => |value| try writer.print("PUSH_BOOL {}", .{value}),
        .buffer_operation => |operation| {
            try writer.print("BUFFER_{s} local={d} -> {s}", .{
                @tagName(operation.kind),
                @backingInt(operation.owner),
                typed.typeName(operation.output, program.records),
            });
        },
        .resource_io => |io| try writer.print("RESOURCE_{s} local={d} -> {s}", .{
            @tagName(io.kind),
            @backingInt(io.owner),
            typed.typeName(io.output, program.records),
        }),
        .restrict_resource => |restrict| try writer.print("RESTRICT_RESOURCE permissions={d} -> {s}", .{ restrict.permissions, typed.typeName(restrict.ty, program.records) }),
        .dir_resource => |dir| try writer.print("DIR_RESOURCE -> {s}", .{typed.typeName(dir.output, program.records)}),
        .environment_get => |get| try writer.print("ENVIRONMENT_GET -> {s}", .{typed.typeName(get.output, program.records)}),
        .environment_only => |only| try writer.print("ENVIRONMENT_ONLY names={s} -> {s}", .{ typed.typeName(only.names, program.records), typed.typeName(only.output, program.records) }),
        .environment_names => |names| try writer.print("ENVIRONMENT_NAMES -> {s}", .{typed.typeName(names.output, program.records)}),
        .complete_resource => |output| try writer.print("COMPLETE_RESOURCE -> {s}", .{typed.typeName(output, program.records)}),
        .acquire_resource => |acquire| try writer.print("ACQUIRE_RESOURCE -> {s}", .{typed.typeName(acquire.output, program.records)}),
        .external_read => |read| try writer.print("EXTERNAL_{s} -> {s}", .{ @tagName(read.kind), typed.typeName(read.output, program.records) }),
        .acquire_buffer => |ty| try writer.print("ACQUIRE_BUFFER {f}", .{ty}),
        .print => |output| try writer.print("PRINT {d} sep={} end={} stream={} debug={}", .{ output.types.len, output.separator, output.terminator, output.stream, output.debug }),
        .stream_write => try writer.writeAll("STREAM_WRITE"),
        .file_access => |call| try writer.print("FILE_{s} operands={d} -> {s}", .{ @tagName(call.kind), call.operands, typed.typeName(call.output, program.records) }),
        .file_method => |call| try writer.print("FILE_{s} local={d} -> {s}", .{ @tagName(call.kind), @backingInt(call.owner), typed.typeName(call.output, program.records) }),
        .move_local => |slot| try writer.print("MOVE_LOCAL {d}", .{@backingInt(slot)}),
        .drop_local => |slot| try writer.print("DROP_LOCAL {d}", .{@backingInt(slot)}),
        .load_local => |slot| try writer.print("LOAD_LOCAL {d}", .{@backingInt(slot)}),
        .store_local => |slot| try writer.print("STORE_LOCAL {d}", .{@backingInt(slot)}),
        .cmp_i64 => |predicate| try writer.print("CMP_I64 {s}", .{@tagName(predicate)}),
        .cmp_bool => |predicate| try writer.print("CMP_BOOL {s}", .{@tagName(predicate)}),
        .try_result => |propagate| try writer.print("TRY_RESULT {s} -> {s} error={d}", .{
            typed.typeName(propagate.input, program.records),
            typed.typeName(propagate.output, program.records),
            propagate.error_target,
        }),
        .acknowledge => |ty| try writer.print("ACKNOWLEDGE {s}", .{typed.typeName(ty, program.records)}),
        .pop => try writer.writeAll("POP"),
        .jump => |target| try writer.print("JUMP {d}", .{target}),
        .jump_if_false => |target| try writer.print("JUMP_IF_FALSE {d}", .{target}),
        .assert_true => |message| try writer.print("ASSERT_TRUE {s}", .{message}),
        .div_i64_checked => try writer.writeAll("DIV_I64_CHECKED"),
        .rem_i64_checked => try writer.writeAll("REM_I64_CHECKED"),
        .not_bool => try writer.writeAll("NOT_BOOL"),
        .neg_i64_checked => try writer.writeAll("NEG_I64_CHECKED"),
        .add_i64_checked => try writer.writeAll("ADD_I64_CHECKED"),
        .sub_i64_checked => try writer.writeAll("SUB_I64_CHECKED"),
        .mul_i64_checked => try writer.writeAll("MUL_I64_CHECKED"),
        .function_value => |value| try writer.print("FUNCTION_VALUE {d} type {d}", .{ @backingInt(value.function), @backingInt(value.ty) }),
        .invoke => |ty| try writer.print("INVOKE type {d}", .{@backingInt(ty)}),
        .call => |id| try writer.print("CALL {d} ({s})", .{ @backingInt(id), program.functions[@backingInt(id)].name }),
        .ret => try writer.writeAll("RET"),
    }
    const location = src.locate(instruction.span.start);
    if (src.origins.len != 0) try writer.print("  ; {s}:{d}:{d}\n", .{ location.path, location.line, location.column }) else try writer.print("  ; {d}:{d}\n", .{
        location.line,
        location.column,
    });
}

fn recordKind(record: typed.Record) []const u8 {
    if (record.shape.variants) |variants| {
        if (variants.fallible) return "result";
        return if (variants.is_union) "union" else "enum";
    }
    if (record.shape.resource != null) return "resource";
    if (record.shape.buffer != null) return "list";
    if (record.tableKey() != null) return "table";
    if (record.shape.array != null) return "array";
    if (record.shape.domain != null) return "domain";
    return "record";
}

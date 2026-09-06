//! Scalar C emission: direct labels/branches, explicit frames, checked arithmetic.
const std = @import("std");
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const diagnostic = @import("diagnostic.zig");
const native_layout = @import("native_layout.zig");
fn payload(w: *std.Io.Writer, layout: native_layout.Layout, ty: typed.Type, tag_bits: u8) !void {
    try w.print("variant_payload(packed, {d}, {d}, {d})", .{ tag_bits, layout.width(ty), @intFromBool(layout.signed(ty)) });
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
pub fn generate(allocator: std.mem.Allocator, program: bc.Program, src: Source, sink: *diagnostic.Sink) ![]u8 {
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
        count += function.instructions.len;
        if (layout.width(function.return_type) == 0 or function.references.len != 0 or function.return_reference != null) return sink.fail("E_NATIVE_FEATURE", function.instructions[0].span, "native scalar execution does not yet support this signature");
        for (function.locals) |local| if (layout.width(local.ty) == 0 or local.reference_parameter != null) return sink.fail("E_NATIVE_FEATURE", local.declaration, "native execution requires supported scalar or packed variant locals and parameters");
        for (function.instructions) |instruction| switch (instruction.op) {
            .make_variant => |variant| {
                if (layout.width(variant.ty) == 0) return sink.fail("E_NATIVE_FEATURE", instruction.span, "native variant representation requires supported payloads and at most 127 packed bits");
            },
            .switch_variant => |dispatch| {
                if (layout.width(dispatch.ty) == 0) return sink.fail("E_NATIVE_FEATURE", instruction.span, "native matching requires a supported packed variant layout");
            },
            .try_result => |propagate| {
                if (layout.width(propagate.input) == 0 or layout.width(propagate.output) == 0) return sink.fail("E_NATIVE_FEATURE", instruction.span, "native propagation requires supported packed result layouts");
            },
            .acknowledge => |ty| {
                if (layout.width(ty) == 0) return sink.fail("E_NATIVE_FEATURE", instruction.span, "native acknowledgement requires a supported result layout");
            },
            .cmp_enum, .wrap_domain, .unwrap_domain, .push_i64, .push_bool, .push_integer, .cast_integer, .neg_integer, .binary_integer, .drop_local, .move_local, .load_local, .store_local, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked, .cmp_i64, .cmp_bool, .not_bool, .pop, .jump, .jump_if_false, .call, .ret => {},
            else => return sink.fail("E_NATIVE_FEATURE", instruction.span, "this operation is not yet supported by native scalar execution"),
        };
    }
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const w = &output.writer;
    try w.writeAll(@embedFile("native_runtime.c"));
    try w.writeAll("\nstatic const char *const names[] = {\n");
    for (program.functions) |function| {
        try string(w, function.name);
        try w.writeAll(",\n");
    }
    try w.writeAll("};\nstatic const size_t lines[] = {");
    for (program.functions) |function| for (function.instructions) |ins| try w.print("{d},", .{src.locate(ins.span.start).line});
    try w.writeAll("};\nstatic const size_t columns[] = {");
    for (program.functions) |function| for (function.instructions) |ins| try w.print("{d},", .{src.locate(ins.span.start).column});
    try w.writeAll("};\nstatic const char *const paths[] = {\n");
    for (program.functions) |function| for (function.instructions) |ins| {
        try string(w, src.locate(ins.span.start).path);
        try w.writeAll(",\n");
    };
    try w.writeAll("};\nint main(int argc, char **argv) {\nsource_paths = paths; function_names = names; source_lines = lines; source_columns = columns;\noptions(argc, argv); size_t return_target = 0;\n");
    const main_index = @backingInt(program.main);
    try w.print("enter({d}, {d}, 0, 0); goto L{d};\n", .{ main_index, program.functions[main_index].locals.len, offsets[main_index] });
    for (program.functions, offsets) |function, offset| {
        for (function.instructions, 0..) |ins, pc| {
            const location = offset + pc;
            try w.print("L{d}: {{ tick({d});\n", .{ location, location });
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
                    const variants = program.records[variant.ty.recordIndex()].variants.?;
                    if (variants.cases[variant.tag].payload) |ty| {
                        try w.print("push(variant_make(pop(), {d}, {d}, {d}));\n", .{ native_layout.tagBits(variants.cases.len), layout.width(ty), variant.tag });
                    } else try w.print("push((V)UINT64_C({d}));\n", .{variant.tag});
                },
                .cmp_enum => |comparison| try w.print("V b = pop(), a = pop(); push(a {s} b);\n", .{if (comparison.predicate == .eq) "==" else "!="}),
                .switch_variant => |dispatch| {
                    const variants = program.records[dispatch.ty.recordIndex()].variants.?;
                    if (!variants.is_union) {
                        try w.writeAll("switch (pop()) {\n");
                    } else try w.print("V packed = pop(); switch ((size_t)((U)packed & variant_mask({d}))) {{\n", .{native_layout.tagBits(variants.cases.len)});
                    for (dispatch.arms, 0..) |arm, tag| {
                        try w.print("case {d}: ", .{tag});
                        if (arm.slot) |slot| {
                            try w.print("frames[nf-1].locals[{d}] = ", .{@backingInt(slot)});
                            try payload(w, layout, variants.cases[tag].payload.?, native_layout.tagBits(variants.cases.len));
                            try w.writeAll("; ");
                        }
                        try w.print("goto L{d};\n", .{offset + arm.target});
                    }
                    try w.writeAll("default: host_failure(\"InternalError\");\n}\n");
                    falls_through = false;
                },
                .try_result => |propagate| {
                    const input = typed.resultShape(propagate.input, program.records).?;
                    const result = typed.resultShape(propagate.output, program.records).?;
                    const input_bits = native_layout.tagBits(program.records[propagate.input.recordIndex()].variants.?.cases.len);
                    const output_bits = native_layout.tagBits(program.records[propagate.output.recordIndex()].variants.?.cases.len);
                    try w.print("V packed = pop(); size_t tag = (size_t)((U)packed & variant_mask({d})); if (tag == {d}) {{ push(", .{ input_bits, input.ok_tag });
                    try payload(w, layout, input.ok_type, input_bits);
                    try w.print("); }} else if (tag == {d}) {{ nv = frames[nf-1].base; push(variant_make(", .{input.error_tag});
                    try payload(w, layout, input.error_type, input_bits);
                    try w.print(", {d}, {d}, {d})); goto L{d}; }} else host_failure(\"InternalError\");\n", .{ output_bits, layout.width(result.error_type), result.error_tag, offset + propagate.error_target });
                },
                .acknowledge => try w.writeAll("(void)pop();\n"),
                .move_local => |slot| try w.print("push(frames[nf-1].locals[{d}]); frames[nf-1].locals[{d}] = 0;\n", .{ @backingInt(slot), @backingInt(slot) }),
                .push_bool => |value| try w.print("push({d});\n", .{@intFromBool(value)}),
                .drop_local => |slot| try w.print("frames[nf-1].locals[{d}] = 0;\n", .{@backingInt(slot)}),
                .load_local => |slot| try w.print("push(frames[nf-1].locals[{d}]);\n", .{@backingInt(slot)}),
                .store_local => |slot| try w.print("frames[nf-1].locals[{d}] = pop();\n", .{@backingInt(slot)}),
                .pop => try w.writeAll("(void)pop();\n"),
                .not_bool => try w.writeAll("push(!pop());\n"),
                .cmp_i64 => |op| try w.print("V b = pop(), a = pop(); push(a {s} b);\n", .{predicate(std.meta.stringToEnum(typed.BinaryOp, @tagName(op)).?)}),
                .cmp_bool => |op| try w.print("V b = pop(), a = pop(); push(a {s} b);\n", .{if (op == .eq) "==" else "!="}),
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
                    try w.print("goto L{d};\n", .{offset + target});
                    falls_through = false;
                },
                .jump_if_false => |target| try w.print("if (!pop()) goto L{d};\n", .{offset + target}),
                .call => |callee_id| {
                    const callee = @backingInt(callee_id);
                    const target = program.functions[callee];
                    try w.print("enter({d}, {d}, {d}, {d}); goto L{d};\n", .{ callee, target.locals.len, target.parameter_count, location + 1, offsets[callee] });
                    falls_through = false;
                },
                .ret => {
                    try w.writeAll("V result = pop(); size_t target = leave(result); if (!nf) { printf(\"%\" PRId64 \"\\n\", (int64_t)result); cleanup(); return 0; }\nreturn_target = target; goto dispatch_return;\n");
                    falls_through = false;
                },
                else => unreachable,
            }
            if (falls_through) {
                if (pc + 1 < function.instructions.len) try w.print("goto L{d};\n", .{location + 1}) else try w.writeAll("host_failure(\"InternalError\");\n");
            }
            try w.writeAll("}\n");
        }
    }
    try w.writeAll("dispatch_return: switch (return_target) {\n");
    for (program.functions, offsets) |function, offset| for (function.instructions, 0..) |ins, pc| if (ins.op == .call) {
        try w.print("case {d}: goto L{d};\n", .{ offset + pc + 1, offset + pc + 1 });
    };
    try w.writeAll("default: host_failure(\"InternalError\"); } return 2;\n}\n");
    return output.toOwnedSlice();
}

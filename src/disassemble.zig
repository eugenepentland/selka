//! Deterministic instruction dumps show evaluation order and source locations.
const std = @import("std");
const bc = @import("bytecode.zig");
const Source = @import("source.zig").Source;

pub fn dump(allocator: std.mem.Allocator, program: bc.Program, src: Source) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    // The allocating writer can fail only because its allocator failed.
    write(&text.writer, program, src) catch return error.OutOfMemory;
    return text.toOwnedSlice();
}

fn write(writer: *std.Io.Writer, program: bc.Program, src: Source) std.Io.Writer.Error!void {
    for (program.functions) |function| {
        try writer.print("function {s}() -> i64\n", .{function.name});
        for (function.instructions, 0..) |instruction, i| {
            try writer.print("  {d:0>4}  ", .{i});
            switch (instruction.op) {
                .push_i64 => |value| try writer.print("PUSH_I64 {d}", .{value}),
                .push_bool => |value| try writer.print("PUSH_BOOL {}", .{value}),
                .load_local => |slot| try writer.print("LOAD_LOCAL {d}", .{@backingInt(slot)}),
                .store_local => |slot| try writer.print("STORE_LOCAL {d}", .{@backingInt(slot)}),
                .cmp_i64 => |predicate| try writer.print("CMP_I64 {s}", .{@tagName(predicate)}),
                .cmp_bool => |predicate| try writer.print("CMP_BOOL {s}", .{@tagName(predicate)}),
                .not_bool => try writer.writeAll("NOT_BOOL"),
                .neg_i64_checked => try writer.writeAll("NEG_I64_CHECKED"),
                .add_i64_checked => try writer.writeAll("ADD_I64_CHECKED"),
                .sub_i64_checked => try writer.writeAll("SUB_I64_CHECKED"),
                .mul_i64_checked => try writer.writeAll("MUL_I64_CHECKED"),
                .ret => try writer.writeAll("RET"),
            }
            const location = src.locate(instruction.span.start);
            try writer.print("  ; {d}:{d}\n", .{ location.line, location.column });
        }
    }
}

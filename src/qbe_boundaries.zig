//! Native provider and codec boundaries preserve semantic result layouts.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const owned = @import("qbe_owned.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Emit external reads, environment snapshots, region reset, and typed JSON.
pub fn emit(self: anytype, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
    const h = stack.len;
    switch (op) {
        .external_read => |read| {
            const authority = try self.load("s", h - 1);
            const status = self.temp();
            try self.print(" %v{d} =w call $myl_qbe_external_read(l %ctx, l %v{d}, l {d}, l %scratch)\n", .{ status, authority, @backingInt(read.kind) });
            try self.checkFailure("failure");
            const value = self.temp();
            try self.print(" %v{d} =l loadl %scratch\n", .{value});
            try owned.Lower(@TypeOf(self.*)).result(self, .{ .ty = read.output, .status = status, .value = value, .slot = h - 1 });
        },
        .reset_arena => |ty| {
            const authority = try self.load("s", h - 1);
            const status = self.temp();
            const value = self.temp();
            try self.print(" %v{d} =w call $myl_qbe_region_reset(l %ctx, l %v{d})\n %v{d} =l copy 1\n", .{ status, authority, value });
            try owned.Lower(@TypeOf(self.*)).result(self, .{ .ty = ty, .status = status, .value = value, .slot = h - 1 });
        },
        .environment_get => |get| {
            const shape = typed.environmentShape(get.output, self.program.records).?;
            const authority = try self.load("s", h - 2);
            const key = try self.load("s", h - 1);
            const output = self.temp();
            try self.print(" %v{d} =l copy %aux{d}\n call $memset(l %v{d}, w 0, l {d})\n", .{ output, self.pc, output, (try self.layout(shape.result.ok_type)).size });
            const bytes = try self.field(shape.result.ok_type, shape.bytes_field);
            const length = try self.field(shape.result.ok_type, shape.length_field);
            const flag = try self.field(shape.result.ok_type, shape.flag_field);
            const bytes_ptr = try self.address(output, bytes.offset);
            const length_ptr = try self.address(output, length.offset);
            const status = self.temp();
            try self.print(
                " %v{d} =w call $myl_qbe_environment_get(l %ctx, l %v{d}, l %v{d}, l {d}, l %v{d}, l {d}, l %v{d}, l %scratch)\n",
                .{ status, authority, key, (try self.layout(get.name)).size, bytes_ptr, (try self.layout(shape.bytes_type)).size, length_ptr },
            );
            try self.checkFailure("failure");
            const present = self.temp();
            try self.print(" %v{d} =l loaduw %scratch\n", .{present});
            try self.writeValue(try self.address(output, flag.offset), present, .bool);
            try owned.Lower(@TypeOf(self.*)).result(self, .{ .ty = get.output, .status = status, .value = output, .slot = h - 2 });
        },
        .json_codec => |codec| {
            const shape = typed.resultShape(codec.output, self.program.records).?;
            const value_type = if (codec.decode) shape.ok_type else codec.input;
            const authority = try self.load("s", h - 3);
            const limit = try self.load("s", h - 1);
            const input = self.temp();
            if (codec.decode or !self.isScalar(codec.input)) try self.print(" %v{d} =l loadl %s{d}\n", .{ input, h - 2 }) else try self.print(" %v{d} =l copy %s{d}\n", .{ input, h - 2 });
            const status = self.temp();
            if (codec.document) {
                try self.print(" %v{d} =l call $myl_qbe_json_document(l %ctx, l %v{d}, l %v{d}, l %aux{d}, l %v{d})\n", .{ status, input, limit, self.pc, authority });
            } else try self.print(" %v{d} =l call ${s}_json_{s}(l %ctx, l %v{d}, l %v{d}, l %aux{d}, l %v{d})\n", .{ status, try self.descriptor(value_type), if (codec.decode) "decode" else "encode", input, limit, self.pc, authority });
            try self.checkFailure("failure");
            const pointer = self.temp();
            try self.print(" %v{d} =l copy %aux{d}\n", .{ pointer, self.pc });
            const value = try self.readValue(pointer, shape.ok_type);
            try owned.Lower(@TypeOf(self.*)).result(self, .{ .ty = codec.output, .status = status, .value = value, .slot = h - 3 });
        },
        else => return error.InternalError,
    }
}

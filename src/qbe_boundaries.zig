//! Native provider and codec boundaries preserve semantic result layouts.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const prelude = @import("prelude.zig");
const results = @import("qbe_results.zig");
/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const EnvironmentGet = @FieldType(@FieldType(bytecode.Instruction, "op"), "environment_get");
/// Emit external capability reads and environment snapshots.
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
            try results.Lower(@TypeOf(self.*)).result(self, .{ .ty = read.output, .status = status, .value = value, .slot = h - 1 });
        },
        .environment_get => |get| {
            if (typed.environmentShape(get.output, self.program.records)) |shape| return emitEnvironmentGet(self, get, shape, h);
            const option = prelude.optionShape(get.output, self.program.records) orelse return error.InternalError;
            const authority = try self.load("s", h - 2);
            const key = try self.load("s", h - 1);
            const present = self.temp();
            const text = self.temp();
            try self.print(
                " %v{d} =l call $myl_qbe_environment_text(l %ctx, l %v{d}, l %v{d}, l {d}, l %scratch)\n",
                .{ text, authority, key, (try self.layout(get.name)).size },
            );
            try self.checkFailure("failure");
            try self.print(" %v{d} =l loaduw %scratch\n", .{present});
            const pointer = try self.aggregatePointer();
            const slot = try self.address(pointer, (try self.layout(get.output)).payload_offset);
            const label = self.temp();
            try self.print(" jnz %v{d}, @environment_some{d}, @environment_none{d}\n@environment_some{d}\n", .{ present, label, label, label });
            try self.writeTag(get.output, option.some, pointer);
            try self.writeValue(slot, text, option.element);
            try self.print(" jmp @environment_done{d}\n@environment_none{d}\n", .{ label, label });
            try self.writeTag(get.output, option.none, pointer);
            try self.print(" jmp @environment_done{d}\n@environment_done{d}\n", .{ label, label });
            try self.store(h - 2, pointer);
        },
        .environment_only => |only| {
            const authority = try self.load("s", h - 2);
            const names = try self.load("s", h - 1);
            const result = self.temp();
            try self.print(
                " %v{d} =l call $myl_qbe_environment_only(l %ctx, l %v{d}, l %v{d}, l {d})\n",
                .{ result, authority, names, (try self.layout(only.names)).size },
            );
            try self.checkFailure("failure");
            try self.store(h - 2, result);
        },
        .environment_names => {
            const authority = try self.load("s", h - 1);
            const result = self.temp();
            try self.print(" %v{d} =l call $myl_qbe_environment_names(l %ctx, l %v{d})\n", .{ result, authority });
            try self.checkFailure("failure");
            try self.store(h - 1, result);
        },
        else => return error.InternalError,
    }
}

/// Emit one raw `environment_get` that fills a caller-declared result record.
fn emitEnvironmentGet(self: anytype, get: EnvironmentGet, shape: typed.ByteResultShape, h: usize) Error!void {
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
    try results.Lower(@TypeOf(self.*)).result(self, .{ .ty = get.output, .status = status, .value = output, .slot = h - 2 });
}

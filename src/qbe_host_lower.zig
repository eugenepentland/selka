//! Independent guest ABI wrappers around copied-value host calls.
const std = @import("std");
/// Allocation or semantic failure generating a host ABI wrapper.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Host calls use caller-owned native argument storage and a copied-node bridge.
pub fn emit(self: anytype, name: []const u8) Error![]u8 {
    const function = self.function;
    const large_result = try self.largeResult(function);
    const packed_parameters = try self.packedParameters(function);
    const output_size = @max(8, (try self.layout(function.signature.return_type)).size);
    const argument_bytes = std.math.mul(u64, function.signature.parameter_count, 8) catch return self.reject(0);
    var frame_bytes: u64 = if (large_result) 0 else output_size;
    frame_bytes = std.math.add(u64, frame_bytes, argument_bytes) catch return self.reject(0);
    for (function.scope.locals[0..function.signature.parameter_count]) |local| {
        if (self.isScalar(local.ty)) frame_bytes = std.math.add(u64, frame_bytes, 8) catch return self.reject(0);
    }
    const heap_arguments = frame_bytes > 32768;
    try self.typeDefinitions();
    try self.print("export function {s} ${s}(l %ctx", .{ try self.returnType(function), name });
    if (large_result) try self.print(", l %out", .{});
    const parameters = function.scope.locals[0..function.signature.parameter_count];
    if (packed_parameters) {
        try self.print(", l %packed", .{});
    } else {
        for (parameters, 0..) |local, i| try self.print(", {s} %a{d}", .{ try self.parameterType(local), i });
    }
    try self.print(") {{\n@entry\n", .{});
    if (large_result) try self.print(" %output =l copy %out\n", .{}) else try self.print(" %output =l alloc8 {d}\n", .{output_size});
    try self.print(" call $memset(l %output, w 0, l {d})\n", .{output_size});
    if (heap_arguments) {
        try self.print(" %args =l call $myl_qbe_frame_allocate(l %ctx, l {d})\n", .{frame_bytes});
        try self.print(" %failed =l call $myl_qbe_failed(l %ctx)\n jnz %failed, @done, @arguments\n@arguments\n", .{});
    } else try self.print(" %args =l alloc8 {d}\n", .{@max(8, argument_bytes)});
    var scalar_offset = argument_bytes;
    for (parameters, 0..) |local, i| {
        if (packed_parameters) {
            try self.print(" %packed_slot{d} =l add %packed, {d}\n %a{d} =l loadl %packed_slot{d}\n", .{ i, i * 8, i, i });
        }
        if (self.isScalar(local.ty)) {
            if (heap_arguments) {
                try self.print(" %arg{d} =l add %args, {d}\n", .{ i, scalar_offset });
                scalar_offset += 8;
            } else try self.print(" %arg{d} =l alloc8 8\n", .{i});
            try self.print(" storel %a{d}, %arg{d}\n", .{ i, i });
        } else try self.print(" %arg{d} =l copy %a{d}\n", .{ i, i });
        try self.print(" %slot{d} =l add %args, {d}\n storel %arg{d}, %slot{d}\n", .{ i, i * 8, i, i });
    }
    try self.print(" call ${s}_host(l %ctx, l %args, l %output)\n", .{name});
    if (heap_arguments) try self.print(" call $myl_qbe_frame_release(l %ctx, l %args)\n jmp @done\n@done\n", .{});
    if (large_result) {
        try self.print(" ret 0\n}}\n", .{});
    } else if (self.isScalar(function.signature.return_type)) {
        const output = self.temp();
        try self.print(" %v{d} =l copy %output\n", .{output});
        try self.print(" ret %v{d}\n}}\n", .{try self.readValue(output, function.signature.return_type)});
    } else try self.print(" ret %output\n}}\n", .{});
    return self.output.toOwnedSlice();
}

//! Copied fixed-size byte blocks with explicit EOF and short-write counts.
const std = @import("std");
const language = @import("mylang");
const host = language.host_functions;
/// Maximum useful byte payload in one copied host call.
pub const block_size = 256;
/// Bind the callbacks to a host context without importing its registration module.
pub fn Operations(comptime Context: type) type {
    return struct {
        /// Install optional bulk declarations after validating their exact structural ABI.
        pub fn install(state: *Context, registry: *language.vm_host.Registry) language.vm_host.Error!void {
            for ([_][]const u8{ "io::read_block", "io::write_block" }, 0..) |name, index| {
                const signature = registry.contract(name) catch |err| switch (err) {
                    error.HostUnknownFunction => continue,
                    else => return err,
                };
                if (signature.parameters.len != 1 or signature.effects != 1 << 6) return error.HostSignatureMismatch;
                const block = if (index == 0) signature.result.ty else signature.parameters[0].ty;
                if ((if (index == 0) signature.parameters[0].ty else signature.result.ty) != .i64) return error.HostSignatureMismatch;
                if (!block.isAggregate()) return error.HostSignatureMismatch;
                const record = registry.program.records[block.recordIndex()];
                if (!record.isRecord() or record.fields.len != 2) return error.HostSignatureMismatch;
                if (!std.mem.eql(u8, record.fields[0].name, "bytes") or !std.mem.eql(u8, record.fields[1].name, "count")) return error.HostSignatureMismatch;
                if (record.fields[1].ty != .i64) return error.HostSignatureMismatch;
                const array_type = record.fields[0].ty;
                if (!array_type.isAggregate()) return error.HostSignatureMismatch;
                const array = registry.program.records[array_type.recordIndex()].shape.array orelse return error.HostSignatureMismatch;
                if (array.length != block_size or array.element != .u8 or array.key != null) return error.HostSignatureMismatch;
                try registry.register(name, .{ .signature = signature, .context = state, .invoke = if (index == 0) read else write }, 1 << 6);
            }
        }
        fn context(call: *host.Call) *Context {
            return @ptrCast(@alignCast(call.context.?));
        }
        fn read(call: *host.Call) host.CallbackError!language.vm.Value {
            const input = context(call).input;
            const offset = call.arguments[0].i64;
            if (offset < 0 or offset > input.len) return error.HostFailure;
            const count = @min(block_size, input.len - @as(usize, @intCast(offset)));
            try call.consume(1 + count);
            var bytes: [block_size]language.vm.Value = undefined;
            for (&bytes, 0..) |*value, index| value.* = language.vm.Value.number(.u8, if (index < count) input[@as(usize, @intCast(offset)) + index] else 0);
            const array_type = call.records[call.result_type.recordIndex()].fields[0].ty;
            const payload = try language.vm.Value.create(call.allocator(), array_type, &bytes);
            defer payload.release(call.allocator());
            return language.vm.Value.create(call.allocator(), call.result_type, &.{ payload, .{ .i64 = @intCast(count) } });
        }
        fn write(call: *host.Call) host.CallbackError!language.vm.Value {
            const self = context(call);
            const block = call.arguments[0].aggregate.fields;
            const requested = block[1].i64;
            if (requested < 0 or requested > block_size) return error.HostFailure;
            const count = @min(@as(usize, @intCast(requested)), self.output_limit -| self.output.items.len);
            try call.consume(1 + count);
            var bytes: [block_size]u8 = undefined;
            for (bytes[0..count], block[0].aggregate.fields[0..count]) |*byte, value| byte.* = @intCast(value.integer.value);
            try self.output.appendSlice(self.allocator, bytes[0..count]);
            return .{ .i64 = @intCast(count) };
        }
    };
}

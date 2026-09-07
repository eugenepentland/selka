//! Trusted raw byte operations; all input interpretation belongs to the guest.
const std = @import("std");
const language = @import("mylang");
const host = language.host_functions;
/// Borrow raw input and own unpublished output for one guest invocation.
pub const Context = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    output: std.ArrayList(u8) = .empty,
    output_limit: usize = 128 * 1024 * 1024,
    /// Release buffered output after publication or a failed invocation.
    pub fn deinit(self: *Context) void {
        self.output.deinit(self.allocator);
    }
    /// Install scalar compatibility calls and optional validated copied-block I/O.
    pub fn install(self: *Context, registry: *language.vm_host.Registry) language.vm_host.Error!void {
        const scalar = host.Parameter{ .ty = .i64 };
        const octet = host.Parameter{ .ty = .u8 };
        try registry.register("io::length", .{ .signature = .{ .parameters = &.{}, .result = scalar, .effects = 1 << 6 }, .context = self, .invoke = length }, 1 << 6);
        try registry.register("io::byte", .{ .signature = .{ .parameters = &.{scalar}, .result = octet, .effects = 1 << 6 }, .context = self, .invoke = byte }, 1 << 6);
        try registry.register("io::put", .{ .signature = .{ .parameters = &.{octet}, .result = scalar, .effects = 1 << 6 }, .context = self, .invoke = put }, 1 << 6);
        try @import("bulk.zig").Operations(Context).install(self, registry);
    }
    fn context(call: *host.Call) *Context {
        return @ptrCast(@alignCast(call.context.?));
    }
    fn length(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        return .{ .i64 = @intCast(context(call).input.len) };
    }
    fn byte(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        const input = context(call).input;
        const index = call.arguments[0].i64;
        if (index < 0 or index >= input.len) return error.HostFailure;
        return language.vm.Value.number(.u8, input[@intCast(index)]);
    }
    fn put(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        const self = context(call);
        if (self.output.items.len >= self.output_limit) return error.HostWorkLimit;
        try self.output.append(self.allocator, @intCast(call.arguments[0].integer.value));
        return .{ .i64 = 0 };
    }
};

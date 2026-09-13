//! Bounded byte input/output only; parsing and schematic decisions belong to the guest.
const std = @import("std");
const language = @import("mylang");
const host = language.host_functions;
/// Located guest failure, separate from VM traps and host failures.
pub const Issue = struct { code: i64, file: i64, position: i64 };
/// Stable-address context borrowing documents and owning the unpublished output.
pub const Context = struct {
    allocator: std.mem.Allocator,
    documents: []const []const u8,
    output: std.ArrayList(u8) = .empty,
    issue: ?Issue = null,
    /// Release all unpublished or returned output storage.
    pub fn deinit(self: *Context) void {
        self.output.deinit(self.allocator);
    }
    /// Register declared byte operations and named input providers; older guests may omit providers.
    pub fn install(self: *Context, registry: *language.vm_host.Registry) language.vm_host.Error!void {
        const i64_type = language.host_functions.Parameter{ .ty = .i64 };
        const u8_type = language.host_functions.Parameter{ .ty = .u8 };
        const Rule = struct { name: []const u8, args: []const host.Parameter, result: host.Parameter, invoke: *const fn (*host.Call) host.CallbackError!language.vm.Value };
        for ([_]Rule{
            .{ .name = "io::circuit_input", .args = &.{}, .result = i64_type, .invoke = circuitInput },
            .{ .name = "io::pinout_input", .args = &.{}, .result = i64_type, .invoke = pinoutInput },
            .{ .name = "io::interface_input", .args = &.{}, .result = i64_type, .invoke = interfaceInput },
            .{ .name = "io::length", .args = &.{i64_type}, .result = i64_type, .invoke = length },
            .{ .name = "io::byte", .args = &.{ i64_type, i64_type }, .result = u8_type, .invoke = byte },
            .{ .name = "io::put", .args = &.{u8_type}, .result = i64_type, .invoke = put },
            .{ .name = "io::issue", .args = &.{ i64_type, i64_type, i64_type }, .result = i64_type, .invoke = reportIssue },
        }) |rule| {
            _ = registry.registry.resolve(rule.name) catch |err| switch (err) {
                error.HostUnknownFunction => continue,
                else => return err,
            };
            try registry.register(rule.name, .{ .signature = .{ .parameters = rule.args, .result = rule.result, .effects = 1 << 6 }, .context = self, .invoke = rule.invoke }, 1 << 6);
        }
    }
    fn context(call: *host.Call) *Context {
        return @ptrCast(@alignCast(call.context.?));
    }
    fn document(self: *Context, id: i64) host.CallbackError![]const u8 {
        if (id < 0 or id >= self.documents.len) return error.HostFailure;
        return self.documents[@intCast(id)];
    }
    fn input(call: *host.Call, index: i64) host.CallbackError!language.vm.Value {
        try call.consume(1);
        _ = try context(call).document(index);
        return .{ .i64 = index };
    }
    fn circuitInput(call: *host.Call) host.CallbackError!language.vm.Value {
        return input(call, 0);
    }
    fn pinoutInput(call: *host.Call) host.CallbackError!language.vm.Value {
        return input(call, 1);
    }
    fn interfaceInput(call: *host.Call) host.CallbackError!language.vm.Value {
        return input(call, 2);
    }
    fn length(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        return .{ .i64 = @intCast((try context(call).document(call.arguments[0].i64)).len) };
    }
    fn byte(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        const bytes = try context(call).document(call.arguments[0].i64);
        const index = call.arguments[1].i64;
        if (index < 0 or index >= bytes.len) return error.HostFailure;
        return language.vm.Value.number(.u8, bytes[@intCast(index)]);
    }
    fn put(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        const self = context(call);
        if (self.output.items.len == 4 * 1024 * 1024) return error.HostWorkLimit;
        try self.output.append(self.allocator, @intCast(call.arguments[0].integer.value));
        return .{ .i64 = 0 };
    }
    fn reportIssue(call: *host.Call) host.CallbackError!language.vm.Value {
        try call.consume(1);
        const self = context(call);
        if (self.issue == null) self.issue = .{ .code = call.arguments[0].i64, .file = call.arguments[1].i64, .position = call.arguments[2].i64 };
        return .{ .i64 = 0 };
    }
};

/// Reject invalid UTF-8 and characters XML 1.0 cannot represent before handing bytes to the guest.
pub fn validateDocuments(documents: []const []const u8) ?Issue {
    for (documents, 0..) |bytes, file| {
        if (bytes.len > 1024 * 1024) return .{ .code = 7, .file = @intCast(file), .position = 0 };
        var i: usize = 0;
        while (i < bytes.len) {
            const length = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            if (i + length > bytes.len) return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            const cp = std.unicode.utf8Decode(bytes[i..][0..length]) catch return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            const forbidden_control = cp < 32 and cp != 9 and cp != 10 and cp != 13;
            if (forbidden_control or cp == 0xfffe or cp == 0xffff) return .{ .code = 8, .file = @intCast(file), .position = @intCast(i) };
            i += length;
        }
    }
    return null;
}

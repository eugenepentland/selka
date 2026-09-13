//! Replay validates call order/arguments and never repeats provider effects.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const host = language.host_functions;
const Provider = struct {
    calls: usize = 0,
    fn invoke(call: *host.Call) host.CallbackError!language.vm.Value {
        const self: *Provider = @ptrCast(@alignCast(call.context.?));
        self.calls += 1;
        try call.consume(3);
        return .{ .i64 = call.arguments[0].i64 * 2 };
    }
};
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "replay.my",
        \\host def measure(n: i64) -> i64 effects(host)
        \\
        \\
        \\def main() -> i64:
        \\    return measure(1) + measure(2)
    );
    defer c.deinit();
    try c.emit();
    var provider: Provider = .{};
    var tape: language.host_replay.Transcript = .{ .allocator = allocator };
    defer tape.deinit();
    var registry = try language.vm_host.Registry.init(allocator, c.code.?);
    defer registry.deinit();
    const signature = try registry.contract("measure");
    const binding = try tape.wrap("measure", .{ .signature = signature, .context = &provider, .invoke = Provider.invoke });
    try registry.register("measure", binding, signature.effects);
    const first = try language.vm.runWithHost(allocator, c.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 6), first.value);
    try t.expectEqual(@as(usize, 2), provider.calls);
    try tape.finish();
    try tape.replay();
    try t.expectError(error.IncompleteTranscript, tape.finish());
    const second = try language.vm.runWithHost(allocator, c.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 6), second.value);
    try t.expectEqual(@as(usize, 2), provider.calls);
    try tape.finish();
    try tape.replay();
    const session = try registry.begin(allocator, c.code.?, .{});
    defer session.close() catch |failure| std.debug.panic("replay session cleanup: {s}", .{@errorName(failure)});
    const id = try registry.registry.resolve("measure");
    const result = session.call(id, &.{.{ .i64 = 2 }});
    if (result) |value| {
        value.release(allocator);
        return error.TestUnexpectedResult;
    } else |failure| {
        if (failure == error.OutOfMemory) return failure;
        try t.expectEqual(error.HostReplayMismatch, failure);
    }
    try t.expectError(error.IncompleteTranscript, tape.finish());
    try t.expectEqual(@as(usize, 2), provider.calls);
}
// spec: HOST-REPLAY-1
test "host transcript wrap detects IncompleteTranscript and HostReplayMismatch with allocation failure cleanup" {
    try scenario(t.allocator);
    // Arena growth must not depend on whether the backing allocator can resize in place.
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

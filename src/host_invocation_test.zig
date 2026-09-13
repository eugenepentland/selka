//! Typed application entry points preserve values, exports and host callback boundaries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const vm = language.vm;
const host = language.host_functions;
const typed = @import("typed.zig");
const source = "module app;export Point;export Checked;export evaluate;export transform;" ++
    "struct Point{x:i64,y:i64}struct Other{x:i64,y:i64}result Checked{ok:Point,err:i64}" ++
    "host fn transform(p:Point)->Checked effects(host);fn evaluate(p:Point)->Checked{return transform(p);}" ++
    "fn hidden()->i64{return 9;}fn byReference(p:&Point)->i64{return read_ref(p).x;}fn authority(heap:allocator)->i64{_ = heap;return 0;}fn main()->i64{return 0;}";
const Inputs = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "app.my")) return error.NotFound;
        if (source.len > limit) return error.TooLarge;
        return allocator.dupe(u8, source);
    }
};
const Callback = struct {
    calls: usize = 0,
    fn invoke(call: *host.Call) host.CallbackError!typed.Value {
        const self: *Callback = @ptrCast(@alignCast(call.context.?));
        self.calls += 1;
        const input = call.arguments[0];
        if (input.aggregate.fields[0].i64 < 0) return typed.Value.createVariant(call.allocator(), call.result_type, 1, .{ .i64 = -7 });
        return typed.Value.createVariant(call.allocator(), call.result_type, 0, input);
    }
};
fn find(code: language.bytecode.Program, name: []const u8) typed.FunctionId {
    for (code.functions) |function| if (std.mem.eql(u8, name, function.name)) return function.id;
    unreachable;
}
fn install(registry: *language.vm_host.Registry, callback: *Callback) !void {
    const name = "app::transform";
    const signature = try registry.contract(name);
    try registry.register(name, .{ .signature = signature, .context = callback, .invoke = Callback.invoke }, signature.effects);
}
fn scenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Inputs.read }, "app", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.emit();
    var registry = try language.vm_host.Registry.init(allocator, c.code.?);
    defer registry.deinit();
    var callback: Callback = .{};
    try install(&registry, &callback);
    const point = try c.publicValueType("app::Point");
    for ([_]i64{ 3, -1 }) |x| {
        const input = try typed.Value.create(allocator, point, &.{ .{ .i64 = x }, .{ .i64 = 4 } });
        defer input.release(allocator);
        var steps: u64 = 0;
        const outcome = try c.invokePublicWithHost(allocator, "app::evaluate", &.{input}, &registry, .{ .execution = .{ .steps_executed = &steps } });
        try t.expect(outcome == .value);
        defer outcome.value.release(allocator);
        try t.expect(steps > 0);
        try t.expectEqual(@as(usize, if (x < 0) 1 else 0), try outcome.value.variantTag());
        if (x < 0) try t.expectEqual(@as(i64, -7), outcome.value.aggregate.fields[0].i64) else {
            const result = outcome.value.aggregate.fields[0];
            try t.expect(result.aggregate != input.aggregate);
            try t.expectEqual(x, result.aggregate.fields[0].i64);
            try t.expectEqual(@as(i64, 4), result.aggregate.fields[1].i64);
        }
        try t.expectEqual(x, input.aggregate.fields[0].i64);
    }
    try t.expectEqual(@as(usize, 2), callback.calls);
}
// spec: HOST-INVOKE-1
test "host typed application invocation preserves nominal result ownership under allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "host typed invocation rejects hidden entries invalid arguments and absent registrations before callbacks" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Inputs.read }, "app", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.emit();
    var registry = try language.vm_host.Registry.init(t.allocator, c.code.?);
    defer registry.deinit();
    var callback: Callback = .{};
    const point = try c.publicValueType("app::Point");
    const input = try typed.Value.create(t.allocator, point, &.{ .{ .i64 = 3 }, .{ .i64 = 4 } });
    defer input.release(t.allocator);
    const args = &.{input};
    const name = "app::evaluate";
    var steps: u64 = 99;
    try t.expectError(error.UnknownPublicFunction, c.invokePublicWithHost(t.allocator, "app::hidden", &.{}, &registry, .{ .execution = .{ .steps_executed = &steps } }));
    try t.expectEqual(@as(u64, 0), steps);
    try t.expectError(error.HostMissingRegistration, c.invokePublicWithHost(t.allocator, name, args, &registry, .{}));
    try install(&registry, &callback);
    try t.expectError(error.InvocationArity, c.invokePublicWithHost(t.allocator, name, &.{}, &registry, .{}));
    try t.expectError(error.ValueTypeMismatch, c.invokePublicWithHost(t.allocator, name, &.{.{ .bool = true }}, &registry, .{}));
    try t.expectError(error.InvocationHostDeclaration, c.invokePublicWithHost(t.allocator, "app::transform", args, &registry, .{}));
    try t.expectError(error.InvocationEffects, c.invokePublic(t.allocator, name, args, .{}));
    try t.expectError(error.UnknownInvocationFunction, vm.invokeWithHost(t.allocator, c.code.?, @fromBackingInt(c.code.?.functions.len), args, &registry, .{}));
    try t.expectError(error.InvocationReference, vm.invokeWithHost(t.allocator, c.code.?, find(c.code.?, "app::byReference"), args, &registry, .{}));
    try t.expectError(error.NotDataType, vm.invokeWithHost(t.allocator, c.code.?, find(c.code.?, "app::authority"), &.{.{ .i64 = 1 }}, &registry, .{}));
    try t.expectEqual(@as(usize, 0), callback.calls);
    const result = try c.invokePublicWithHost(t.allocator, name, args, &registry, .{});
    defer result.value.release(t.allocator);
    try t.expectEqual(@as(usize, 1), callback.calls);
}

test "host typed invocation accounts steps and independent input and callback budgets" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Inputs.read }, "app", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    try c.emit();
    var registry = try language.vm_host.Registry.init(t.allocator, c.code.?);
    defer registry.deinit();
    var callback: Callback = .{};
    try install(&registry, &callback);
    const input = try typed.Value.create(t.allocator, try c.publicValueType("app::Point"), &.{ .{ .i64 = 3 }, .{ .i64 = 4 } });
    defer input.release(t.allocator);
    const args = &.{input};
    const name = "app::evaluate";
    var steps: u64 = 99;
    const stopped = try c.invokePublicWithHost(t.allocator, name, args, &registry, .{ .execution = .{ .max_steps = 1, .steps_executed = &steps } });
    try t.expectEqualStrings("R_STEP_LIMIT", stopped.trap.code);
    try t.expectEqual(@as(u64, 1), steps);
    try t.expectEqual(@as(usize, 0), callback.calls);
    try t.expectError(error.ValueCountLimit, c.invokePublicWithHost(t.allocator, name, args, &registry, .{ .execution = .{ .arguments = .{ .max_values = 2 } } }));
    try t.expectEqual(@as(usize, 0), callback.calls);
    const limited = try c.invokePublicWithHost(t.allocator, name, args, &registry, .{ .callbacks = .{ .values = .{ .max_values = 3 } } });
    try t.expectEqualStrings("R_HOST_LIMIT", limited.trap.code);
    try t.expectEqualStrings("transform(p)", c.src.text(limited.trap.span));
    try t.expectEqualStrings("app::evaluate", limited.trap.stack.frames[0].function);
    try t.expectEqual(@as(usize, 1), callback.calls);
    try t.expectEqual(@as(i64, 3), input.aggregate.fields[0].i64);
    const result = try c.invokePublicWithHost(t.allocator, name, args, &registry, .{});
    defer result.value.release(t.allocator);
    try t.expectEqual(@as(usize, 2), callback.calls);
}

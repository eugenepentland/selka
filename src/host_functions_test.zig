//! Host registration validates contracts and isolates owned values before callback execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const host = language.host_functions;
const typed = @import("typed.zig");
const effects = @import("effect_set.zig");
const scalar: host.Signature = .{ .parameters = &.{.{ .ty = .i64 }}, .result = .{ .ty = .i64 } };
const Counter = struct {
    calls: usize = 0,
    failure: bool = false,
    wrong_type: bool = false,
    work: u64 = 0,
    fn invoke(call: *host.Call) host.CallbackError!typed.Value {
        const self: *Counter = @ptrCast(@alignCast(call.context.?));
        self.calls += 1;
        try call.consume(self.work);
        if (self.failure) return error.HostFailure;
        if (self.wrong_type) return .{ .bool = true };
        return call.arguments[0]; // Scalar values have no owned storage.
    }
};
fn registry(allocator: std.mem.Allocator) !host.Registry {
    return host.Registry.init(allocator, &.{}, &.{.{ .name = "geometry::measure", .signature = scalar }});
}
// spec: HOST-REGISTRY-1
test "host registration rejects unknown duplicate mismatched and denied contracts before callbacks" {
    var r = try registry(t.allocator);
    defer r.deinit();
    var counter: Counter = .{};
    const binding: host.Binding = .{ .signature = scalar, .context = &counter, .invoke = Counter.invoke };
    try t.expectError(error.HostMissingRegistration, r.begin(t.allocator, .{}));
    try t.expectError(error.HostUnknownFunction, r.register("missing", binding, 0));
    var mismatch = binding;
    mismatch.signature.result.ty = .bool;
    try t.expectError(error.HostSignatureMismatch, r.register("geometry::measure", mismatch, 0));
    try t.expectError(error.HostInvalidEffects, r.register("geometry::measure", binding, 0x100));
    try r.register("geometry::measure", binding, 0);
    try t.expectError(error.HostDuplicateRegistration, r.register("geometry::measure", binding, 0));
    try t.expectEqual(@as(usize, 0), counter.calls);
    var effectful = scalar;
    effectful.effects = effects.bit(.filesystem);
    var denied = try host.Registry.init(t.allocator, &.{}, &.{.{ .name = "read", .signature = effectful }});
    defer denied.deinit();
    try t.expectError(error.HostCapabilityDenied, denied.register("read", .{ .signature = effectful, .invoke = Counter.invoke }, 0));
    try t.expectError(error.HostMissingRegistration, denied.begin(t.allocator, .{}));
    try denied.register("read", .{ .signature = effectful, .context = &counter, .invoke = Counter.invoke }, effectful.effects);
    const session = try denied.begin(t.allocator, .{});
    defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    try t.expectEqual(@as(i64, 7), (try session.call(try denied.resolve("read"), &.{.{ .i64 = 7 }})).i64);
}
test "host declarations reject duplicate names borrowed signatures authority and invalid effect masks" {
    try t.expectError(error.HostDuplicateFunction, host.Registry.init(t.allocator, &.{}, &.{ .{ .name = "f", .signature = scalar }, .{ .name = "f", .signature = scalar } }));
    try t.expectError(error.HostUnknownFunction, host.Registry.init(t.allocator, &.{}, &.{.{ .name = "", .signature = scalar }}));
    var signature = scalar;
    signature.result.passing = .shared;
    try t.expectError(error.HostBorrowUnsupported, host.Registry.init(t.allocator, &.{}, &.{.{ .name = "f", .signature = signature }}));
    signature = scalar;
    signature.parameters = &.{.{ .ty = .i64, .passing = .exclusive }};
    try t.expectError(error.HostBorrowUnsupported, host.Registry.init(t.allocator, &.{}, &.{.{ .name = "f", .signature = signature }}));
    signature = scalar;
    signature.result.ty = .clock_cap;
    try t.expectError(error.NotDataType, host.Registry.init(t.allocator, &.{}, &.{.{ .name = "f", .signature = signature }}));
    signature = scalar;
    signature.effects = 0x100;
    try t.expectError(error.HostInvalidEffects, host.Registry.init(t.allocator, &.{}, &.{.{ .name = "f", .signature = signature }}));
}
test "host sessions enforce argument result call and work budgets with recovery and stale tokens" {
    var r = try registry(t.allocator);
    defer r.deinit();
    var counter: Counter = .{};
    try r.register("geometry::measure", .{ .signature = scalar, .context = &counter, .invoke = Counter.invoke }, 0);
    try t.expectError(error.HostInvalidBudget, r.begin(t.allocator, .{ .max_calls = 0 }));
    const first = try r.begin(t.allocator, .{ .max_calls = 2 });
    const id = try r.resolve("geometry::measure");
    try t.expectError(error.HostReentrant, r.begin(t.allocator, .{}));
    try t.expectError(error.HostUnknownFunction, first.call(@fromBackingInt(1), &.{}));
    try t.expectError(error.HostArity, first.call(id, &.{}));
    try t.expectError(error.ValueTypeMismatch, first.call(id, &.{.{ .bool = true }}));
    try t.expectEqual(@as(usize, 0), counter.calls);
    counter.wrong_type = true;
    try t.expectError(error.ValueTypeMismatch, first.call(id, &.{.{ .i64 = 7 }}));
    counter.wrong_type = false;
    counter.failure = true;
    try t.expectError(error.HostFailure, first.call(id, &.{.{ .i64 = 7 }}));
    try t.expectError(error.HostCallLimit, first.call(id, &.{.{ .i64 = 7 }}));
    try first.close();
    const next = try r.begin(t.allocator, .{ .max_work = 2 });
    defer next.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    try t.expectError(error.HostSessionClosed, first.call(id, &.{.{ .i64 = 7 }}));
    try t.expectError(error.HostSessionClosed, first.close());
    counter.failure = false;
    counter.work = 2;
    try t.expectError(error.HostWorkLimit, next.call(id, &.{.{ .i64 = 7 }}));
    counter.work = 0;
    try t.expectError(error.HostWorkLimit, next.call(id, &.{.{ .i64 = 7 }}));
}
fn schema(allocator: std.mem.Allocator) !language.Compilation {
    var c = try language.Compilation.init(allocator, "host-schema.my", "struct Point{x:i64,y:i64}result Checked{ok:Point,err:i64}fn main()->i64{return 0;}");
    errdefer c.deinit();
    try c.check();
    return c;
}
fn named(records: []const typed.Record, name: []const u8) typed.Type {
    for (records, 0..) |record, index| if (std.mem.eql(u8, record.name, name)) return @fromBackingInt(typed.Type.record_base + index);
    unreachable;
}
fn translate(call: *host.Call) host.CallbackError!typed.Value {
    try call.consume(2);
    const point = call.arguments[0];
    const original: *const typed.Value = @ptrCast(@alignCast(call.context.?));
    if (point.aggregate == original.aggregate) return error.HostFailure;
    return typed.Value.create(call.allocator(), call.result_type, &.{ .{ .i64 = 9 }, point.aggregate.fields[1] });
}
const translate_name = "geometry::translate";
fn aggregateScenario(allocator: std.mem.Allocator) !void {
    var c = try schema(allocator);
    defer c.deinit();
    const records = c.program.?.records;
    const point = named(records, "Point");
    const signature: host.Signature = .{ .parameters = &.{.{ .ty = point }}, .result = .{ .ty = point } };
    var r = try host.Registry.init(allocator, records, &.{.{ .name = translate_name, .signature = signature }});
    defer r.deinit();
    var input = try typed.Value.create(allocator, point, &.{ .{ .i64 = 7 }, .{ .i64 = 8 } });
    defer input.release(allocator);
    try r.register(translate_name, .{ .signature = signature, .context = &input, .invoke = translate }, 0);
    const id = try r.resolve(translate_name);
    const session = try r.begin(allocator, .{});
    const result = session.call(id, &.{input}) catch |err| {
        try session.close();
        return err;
    };
    defer result.release(allocator);
    try session.close();
    try t.expect(result.aggregate != input.aggregate);
    try t.expectEqual(@as(i64, 7), input.aggregate.fields[0].i64);
    try t.expectEqual(@as(i64, 9), result.aggregate.fields[0].i64);
    try t.expectEqual(@as(i64, 8), result.aggregate.fields[1].i64);
}
test "host aggregate boundary owns independent snapshots and cleans every allocation failure" {
    try aggregateScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), aggregateScenario, .{});
}

test "host preflight covers unused missing registrations and never wraps session generations" {
    var r = try host.Registry.init(t.allocator, &.{}, &.{ .{ .name = "a", .signature = scalar }, .{ .name = "b", .signature = scalar } });
    defer r.deinit();
    var counter: Counter = .{};
    const binding: host.Binding = .{ .signature = scalar, .context = &counter, .invoke = Counter.invoke };
    try r.register("a", binding, 0);
    try t.expectError(error.HostMissingRegistration, r.begin(t.allocator, .{}));
    try t.expectEqual(@as(usize, 0), counter.calls);
    try r.register("b", binding, 0);
    r.state.epoch = std.math.maxInt(u64);
    try t.expectError(error.HostGenerationExhausted, r.begin(t.allocator, .{}));
    try t.expectEqual(std.math.maxInt(u64), r.state.epoch);
}
fn recursive(call: *host.Call) host.CallbackError!typed.Value {
    const r = call.session.registry;
    t.expectError(error.HostReentrant, r.begin(call.allocator(), .{})) catch return error.HostFailure;
    t.expectError(error.HostReentrant, call.session.call(@fromBackingInt(0), call.arguments)) catch return error.HostFailure;
    t.expectError(error.HostReentrant, call.session.close()) catch return error.HostFailure;
    t.expectError(error.HostReentrant, r.register("geometry::measure", .{ .signature = scalar, .invoke = recursive }, 0)) catch return error.HostFailure;
    return call.arguments[0];
}
fn ignoreWorkFailure(call: *host.Call) host.CallbackError!typed.Value {
    call.consume(100) catch |err| if (err != error.HostWorkLimit) return err;
    return call.arguments[0];
}
test "host callbacks cannot reenter close rebind or swallow an exceeded cooperative budget" {
    for ([_]bool{ false, true }) |ignore| {
        var r = try registry(t.allocator);
        defer r.deinit();
        try r.register("geometry::measure", .{ .signature = scalar, .invoke = if (ignore) ignoreWorkFailure else recursive }, 0);
        const session = try r.begin(t.allocator, .{ .max_work = 5 });
        defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
        const outcome = session.call(try r.resolve("geometry::measure"), &.{.{ .i64 = 7 }});
        if (ignore) try t.expectError(error.HostWorkLimit, outcome) else try t.expectEqual(@as(i64, 7), (try outcome).i64);
    }
}
fn checked(call: *host.Call) host.CallbackError!typed.Value {
    const value = call.arguments[0];
    if (value.aggregate.fields[0].i64 < 0) return typed.Value.createVariant(call.allocator(), call.result_type, 1, .{ .i64 = 7 });
    return typed.Value.createVariant(call.allocator(), call.result_type, 0, value);
}
const validate_name = "validate";
fn resultScenario(allocator: std.mem.Allocator) !void {
    var c = try schema(allocator);
    defer c.deinit();
    const records = c.program.?.records;
    const point = named(records, "Point");
    const signature: host.Signature = .{ .parameters = &.{.{ .ty = point }}, .result = .{ .ty = named(records, "Checked") } };
    var r = try host.Registry.init(allocator, records, &.{.{ .name = validate_name, .signature = signature }});
    defer r.deinit();
    try r.register(validate_name, .{ .signature = signature, .invoke = checked }, 0);
    const id = try r.resolve(validate_name);
    const session = try r.begin(allocator, .{});
    defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    for ([_]i64{ 1, -1 }) |x| {
        const input = try typed.Value.create(allocator, point, &.{ .{ .i64 = x }, .{ .i64 = 0 } });
        defer input.release(allocator);
        const result = try session.call(id, &.{input});
        defer result.release(allocator);
        try t.expectEqual(@as(usize, if (x < 0) 1 else 0), try result.variantTag());
        if (x < 0) try t.expectEqual(@as(i64, 7), result.aggregate.fields[0].i64) else {
            const payload = result.aggregate.fields[0];
            try t.expect(payload.aggregate != input.aggregate);
            try t.expectEqual(x, payload.aggregate.fields[0].i64);
        }
    }
}
test "host declared result failures and owned success payloads remain distinct under allocation failure" {
    try resultScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), resultScenario, .{});
}

test "host registration snapshots caller declaration storage and checks the complete signature" {
    var name = [_]u8{ 'c', 'a', 'l', 'l' };
    var parameters = [_]host.Parameter{.{ .ty = .i64 }};
    const signature: host.Signature = .{ .parameters = &parameters, .result = .{ .ty = .i64 } };
    var r = try host.Registry.init(t.allocator, &.{}, &.{.{ .name = &name, .signature = signature }});
    defer r.deinit();
    name[0] = 'b';
    parameters[0].ty = .bool;
    try t.expectError(error.HostUnknownFunction, r.resolve(&name));
    for ([_]host.Signature{
        .{ .parameters = &.{}, .result = scalar.result },
        .{ .parameters = &parameters, .result = scalar.result },
        .{ .parameters = &.{.{ .ty = .i64, .passing = .shared }}, .result = scalar.result },
        .{ .parameters = scalar.parameters, .result = .{ .ty = .i64, .passing = .exclusive } },
        .{ .parameters = scalar.parameters, .result = scalar.result, .effects = effects.bit(.clock) },
    }) |wrong| try t.expectError(error.HostSignatureMismatch, r.register("call", .{ .signature = wrong, .invoke = Counter.invoke }, effects.all));
    var counter: Counter = .{};
    try r.register("call", .{ .signature = scalar, .context = &counter, .invoke = Counter.invoke }, 0);
    const session = try r.begin(t.allocator, .{});
    defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    try t.expectEqual(@as(i64, 42), (try session.call(try r.resolve("call"), &.{.{ .i64 = 42 }})).i64);
}

fn echo(call: *host.Call) host.CallbackError!typed.Value {
    const counter: *Counter = @ptrCast(@alignCast(call.context.?));
    counter.calls += 1;
    return call.arguments[0].retain();
}
test "host copy budgets span inputs and outputs and reject oversized input before invoking" {
    var c = try schema(t.allocator);
    defer c.deinit();
    const records = c.program.?.records;
    const point = named(records, "Point");
    const signature: host.Signature = .{ .parameters = &.{.{ .ty = point }}, .result = .{ .ty = point } };
    var r = try host.Registry.init(t.allocator, records, &.{.{ .name = "echo", .signature = signature }});
    defer r.deinit();
    var counter: Counter = .{};
    try r.register("echo", .{ .signature = signature, .context = &counter, .invoke = echo }, 0);
    const id = try r.resolve("echo");
    const input = try typed.Value.create(t.allocator, point, &.{ .{ .i64 = 1 }, .{ .i64 = 2 } });
    defer input.release(t.allocator);
    for ([_]host.Limits{
        .{ .values = .{ .max_values = 2 } },
        .{ .values = .{ .max_depth = 1 } },
        .{ .values = .{ .max_values = 5 } },
        .{ .values = .{ .max_values = 6 } },
    }, 0..) |limits, index| {
        const session = try r.begin(t.allocator, limits);
        defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
        const outcome = session.call(id, &.{input});
        if (index == 3) {
            const output = try outcome;
            defer output.release(t.allocator);
            try t.expect(output.aggregate != input.aggregate);
            try t.expectEqual(@as(i64, 2), output.aggregate.fields[1].i64);
        } else try t.expectError(if (index == 1) error.ValueDepthLimit else error.ValueCountLimit, outcome);
        try t.expectEqual(@as(usize, if (index < 2) 0 else index - 1), counter.calls);
    }
}
test "scalar host calls cross the boundary without allocating" {
    var r = try registry(t.allocator);
    defer r.deinit();
    var counter: Counter = .{};
    try r.register("geometry::measure", .{ .signature = scalar, .context = &counter, .invoke = Counter.invoke }, 0);
    var counting: std.testing.FailingAllocator = .init(t.allocator, .{});
    const session = try r.begin(counting.allocator(), .{});
    defer session.close() catch |err| std.debug.panic("host session cleanup failed: {s}", .{@errorName(err)});
    const id = try r.resolve("geometry::measure");
    for (0..64) |_| try t.expectEqual(@as(i64, 3), (try session.call(id, &.{.{ .i64 = 3 }})).i64);
    try t.expectEqual(@as(usize, 64), counter.calls);
    // A raw byte transport calls a scalar host function once per transported
    // byte. Argument and result copies must stay in the caller's frame, and the
    // declared types are already validated, so no call may reach the allocator.
    try t.expectEqual(@as(usize, 0), counting.allocations);
}

//! Guest host declarations execute through checked program-bound registrations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const vm = @import("vm.zig");
const typed = @import("typed.zig");
const host = language.host_functions;
const Registry = language.vm_host.Registry;
const effects = @import("effect_set.zig");
const scalar_source = "host fn measure(x:i64)->i64 effects(host);fn main()->i64{return measure(6)+measure(7);}";
const Counter = struct {
    calls: usize = 0,
    mode: enum { success, failure, wrong_type, work } = .success,
    fn invoke(call: *host.Call) host.CallbackError!typed.Value {
        const self: *Counter = @ptrCast(@alignCast(call.context.?));
        self.calls += 1;
        switch (self.mode) {
            .failure => return error.HostFailure,
            .wrong_type => return .{ .bool = true },
            .work => try call.consume(100),
            .success => {},
        }
        return .{ .i64 = call.arguments[0].i64 * 2 };
    }
};
fn bind(registry: *Registry, name: []const u8, counter: *Counter) !void {
    const signature = try registry.contract(name);
    try registry.register(name, .{ .signature = signature, .context = counter, .invoke = Counter.invoke }, signature.effects);
}
fn scalarScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "host.my", scalar_source);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(usize, 0), c.diagnostics.items.len);
    var registry = try Registry.init(allocator, c.code.?);
    defer registry.deinit();
    var counter: Counter = .{};
    try bind(&registry, "measure", &counter);
    const result = try vm.runWithHost(allocator, c.code.?, .{}, &registry, .{});
    try t.expectEqual(@as(i64, 26), result.value);
    try t.expectEqual(@as(usize, 2), counter.calls);
    try t.expectEqual(effects.bit(.host), c.program.?.functions[1].policy.effects);
}
// spec: HOST-VM-1
test "VM host declarations execute source calls and clean every allocation failure" {
    try scalarScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scalarScenario, .{});
}
test "VM host registration preflights all bindings and pins the compiled program" {
    var c = try language.Compilation.init(t.allocator, "host.my", scalar_source);
    defer c.deinit();
    try c.emit();
    var registry = try Registry.init(t.allocator, c.code.?);
    defer registry.deinit();
    var counter: Counter = .{};
    try t.expectError(error.HostMissingRegistration, vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{}));
    const signature = try registry.contract("measure");
    try t.expectError(error.HostCapabilityDenied, registry.register("measure", .{ .signature = signature, .invoke = Counter.invoke }, 0));
    try t.expectError(error.HostUnknownFunction, registry.register("main", .{ .signature = signature, .invoke = Counter.invoke }, effects.all));
    try bind(&registry, "measure", &counter);
    var other = try language.Compilation.init(t.allocator, "host.my", scalar_source);
    defer other.deinit();
    try other.emit();
    try t.expectError(error.HostProgramMismatch, vm.runWithHost(t.allocator, other.code.?, .{}, &registry, .{}));
    try t.expectEqual(@as(usize, 0), counter.calls);
    const missing = try c.execute(t.allocator);
    try t.expectEqualStrings("R_HOST_REGISTRATION", missing.trap.code);
    try t.expectEqualStrings("host", c.src.text(missing.trap.span));
    try t.expectEqual(@as(i64, 26), (try vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{})).value);
}
test "VM host failures and quotas locate the guest call and leave reusable sessions" {
    var c = try language.Compilation.init(t.allocator, "host.my", scalar_source);
    defer c.deinit();
    try c.emit();
    var registry = try Registry.init(t.allocator, c.code.?);
    defer registry.deinit();
    var counter: Counter = .{};
    try bind(&registry, "measure", &counter);
    for ([_]@TypeOf(counter.mode){ .failure, .wrong_type, .work }, [_][]const u8{ "R_HOST_FAILURE", "R_HOST_CONTRACT", "R_HOST_LIMIT" }) |mode, code| {
        counter.mode = mode;
        const result = try vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{ .max_work = 5 });
        try t.expectEqualStrings(code, result.trap.code);
        try t.expectEqualStrings("measure(6)", c.src.text(result.trap.span));
        try t.expectEqualStrings("main", result.trap.stack.frames[0].function);
    }
    counter.mode = .success;
    const limited = try vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{ .max_calls = 1 });
    try t.expectEqualStrings("R_HOST_LIMIT", limited.trap.code);
    try t.expectEqualStrings("measure(7)", c.src.text(limited.trap.span));
    const steps = try vm.runWithHost(t.allocator, c.code.?, .{ .max_steps = 1 }, &registry, .{});
    try t.expectEqualStrings("R_STEP_LIMIT", steps.trap.code);
    const frames = try vm.runWithHost(t.allocator, c.code.?, .{ .max_frames = 1 }, &registry, .{});
    try t.expectEqualStrings("R_FRAME_LIMIT", frames.trap.code);
    try t.expectEqual(@as(i64, 26), (try vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{})).value);
}

const geometry_source = "module geometry;export Point;export Checked;export validate;" ++
    "struct Point{x:i64,y:i64}result Checked{ok:Point,err:i64}" ++
    "host fn validate(point:Point)->Checked effects(host);";
const entry_prefix = "module main;import geometry as g;fn relay<T:copy>(p:g::Point,tag:T)->g::Checked effects(host){_ = tag;return g::validate(p);}" ++
    "fn main()->i64{let r=relay::<bool>(new g::Point{x:";
const entry_suffix = ",y:4},true);match r{g::Checked.ok(p)=>{return p.x+p.y;},g::Checked.err(e)=>{return e;}}}";
const Inputs = struct {
    negative: bool,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Inputs = @ptrCast(@alignCast(context.?));
        const bytes = if (std.mem.eql(u8, path, "geometry.my")) geometry_source else if (std.mem.eql(u8, path, "main.my"))
            (if (self.negative) entry_prefix ++ "-3" ++ entry_suffix else entry_prefix ++ "3" ++ entry_suffix)
        else
            return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};
fn validatePoint(call: *host.Call) host.CallbackError!typed.Value {
    try call.consume(2);
    const point = call.arguments[0];
    if (point.aggregate.fields[0].i64 < 0) return typed.Value.createVariant(call.allocator(), call.result_type, 1, .{ .i64 = -17 });
    return typed.Value.createVariant(call.allocator(), call.result_type, 0, point);
}
fn projectScenario(allocator: std.mem.Allocator) !void {
    for ([_]bool{ false, true }) |negative| {
        var inputs: Inputs = .{ .negative = negative };
        var project = language.project.Project.init(allocator);
        defer project.deinit();
        try project.load(.{ .context = &inputs, .read = Inputs.read }, "main", .{});
        var index = try language.interfaces.build(&project);
        var compilation = try language.project_compile.Compilation.init(&index);
        try compilation.emit();
        var registry = try Registry.init(allocator, compilation.code.?);
        defer registry.deinit();
        const name = "geometry::validate";
        const signature = try registry.contract(name);
        try registry.register(name, .{ .signature = signature, .invoke = validatePoint }, signature.effects);
        try t.expectError(error.HostUnknownFunction, registry.contract("g::validate"));
        const result = try vm.runWithHost(allocator, compilation.code.?, .{}, &registry, .{});
        try t.expectEqual(@as(i64, if (negative) -17 else 7), result.value);
        const limited = try vm.runWithHost(allocator, compilation.code.?, .{}, &registry, .{ .max_work = 2 });
        try t.expectEqualStrings("R_HOST_LIMIT", limited.trap.code);
        const site = compilation.src.locate(limited.trap.span.start);
        try t.expectEqualStrings("main.my", site.path);
        try t.expectEqualStrings("g::validate(p)", compilation.src.text(limited.trap.span));
    }
}
test "VM host imports preserve nominal aggregate results generic calls and allocation cleanup" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "VM host preflight requires unused declarations before any callback and rejects invalid budgets" {
    var c = try language.Compilation.init(t.allocator, "host.my", scalar_source ++ "host fn unused()->i64 effects(host);");
    defer c.deinit();
    try c.emit();
    var registry = try Registry.init(t.allocator, c.code.?);
    defer registry.deinit();
    var counter: Counter = .{};
    try bind(&registry, "measure", &counter);
    try t.expectError(error.HostMissingRegistration, vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{}));
    try t.expectEqual(@as(usize, 0), counter.calls);
    try bind(&registry, "unused", &counter);
    try t.expectError(error.InvalidBudget, vm.runWithHost(t.allocator, c.code.?, .{ .max_steps = 0 }, &registry, .{}));
    try t.expectError(error.HostInvalidBudget, vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{ .max_calls = 0 }));
    try t.expectEqual(@as(usize, 0), counter.calls);
    try t.expectEqual(@as(i64, 26), (try vm.runWithHost(t.allocator, c.code.?, .{}, &registry, .{})).value);
}

fn cleanupScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\host def measure(x: int) -> int effects(host)
        \\
        \\def main() -> int:
        \\    values: list[int] = []
        \\    values.append(1)
        \\    values.append(2)
        \\    n = measure(6)
        \\    _ = values
        \\    return n
        \\
    ;
    var c = try language.Compilation.init(allocator, "host-cleanup.my", source);
    defer c.deinit();
    try c.emit();
    var registry = try Registry.init(allocator, c.code.?);
    defer registry.deinit();
    var counter: Counter = .{};
    try bind(&registry, "measure", &counter);
    for ([_]bool{ false, true }) |failure| {
        counter.mode = if (failure) .failure else .success;
        const result = try vm.runWithHost(allocator, c.code.?, .{}, &registry, .{});
        if (failure) try t.expectEqualStrings("R_HOST_FAILURE", result.trap.code) else try t.expectEqual(@as(i64, 12), result.value);
    }
}
test "VM host traps release guest managed storage and all partial allocations exactly once" {
    try cleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), cleanupScenario, .{});
}

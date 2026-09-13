const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const vm = @import("vm.zig");
fn find(program: language.bytecode.Program, name: []const u8) typed.FunctionId {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.id;
    unreachable;
}
const domain_source =
    \\result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\
    \\domain Positive: i64:
    \\    private def raw(x: i64) -> Positive:
    \\        return wrap[Positive](x)
    \\
    \\    def decode(x: i64) -> Decoded:
    \\        if x <= 0:
    \\            return Err(-1)
    \\        return Ok(Positive.raw(x))
    \\
    \\    def encode(x: Positive) -> i64:
    \\        return unwrap(x)
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "invoke.my", domain_source ++
        \\def main() -> i64:
        \\    return 5
    );
    defer c.deinit();
    try c.emit();
    const code = c.code.?;
    for ([_]i64{ 7, 0, -10 }) |number| {
        const output = try vm.invoke(allocator, code, find(code, "Positive.decode"), &.{.{ .i64 = number }}, .{});
        try t.expect(output == .value);
        defer output.value.release(allocator);
        if (number > 0) {
            try t.expectEqual(@as(usize, 0), try output.value.variantTag());
            const domain = output.value.aggregate.fields[0];
            const encoded = try vm.invoke(allocator, code, find(code, "Positive.encode"), &.{domain}, .{});
            defer encoded.value.release(allocator);
            try t.expectEqual(number, encoded.value.i64);
        } else {
            try t.expectEqual(@as(usize, 1), try output.value.variantTag());
            try t.expectEqual(@as(i64, -1), output.value.aggregate.fields[0].i64);
        }
    }
    try t.expectEqual(@as(i64, 5), (try vm.run(allocator, code)).value);
}
test "typed invocation runs domain factories and keeps integer entry execution unchanged under every allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "typed invocation reports exact execution budgets and bounds argument traversal" {
    var c = try language.Compilation.init(t.allocator, "limits.my",
        \\class R:
        \\    x: i64
        \\
        \\
        \\def pair(a: R, b: R) -> i64:
        \\    return a.x + b.x
        \\
        \\
        \\def loop(x: i64) -> i64:
        \\    return loop(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    const code = c.code.?;
    const pair = find(code, "pair");
    const ty = code.functions[@backingInt(pair)].scope.locals[0].ty;
    const input = try typed.Value.create(t.allocator, ty, &.{.{ .i64 = 7 }});
    defer input.release(t.allocator);
    try t.expectError(error.ValueCountLimit, vm.invoke(t.allocator, code, pair, &.{ input, input }, .{ .arguments = .{ .max_values = 3 } }));
    try t.expectError(error.ValueDepthLimit, vm.invoke(t.allocator, code, pair, &.{ input, input }, .{ .arguments = .{ .max_depth = 1 } }));
    var finished = false;
    for (1..40) |budget| {
        var steps: u64 = 999;
        const output = try vm.invoke(t.allocator, code, pair, &.{ input, input }, .{ .max_steps = budget, .steps_executed = &steps });
        switch (output) {
            .trap => |trap| {
                try t.expectEqualStrings("R_STEP_LIMIT", trap.code);
                try t.expectEqual(budget, steps);
            },
            .value => |value| {
                defer value.release(t.allocator);
                try t.expectEqual(@as(i64, 14), value.i64);
                try t.expectEqual(budget, steps);
                finished = true;
                break;
            },
        }
    }
    try t.expect(finished);
    const failed = try vm.invoke(t.allocator, code, find(code, "loop"), &.{.{ .i64 = 1 }}, .{ .max_frames = 2 });
    try t.expectEqualStrings("R_FRAME_LIMIT", failed.trap.code);
    try t.expectEqual(@as(usize, 2), failed.trap.stack.len);
    try t.expectEqualStrings("loop", failed.trap.stack.frames[0].function);
    try t.expectError(error.InvalidBudget, vm.invoke(t.allocator, code, pair, &.{ input, input }, .{ .max_steps = 0 }));
    try t.expectError(error.InvalidValueLimits, vm.invoke(t.allocator, code, find(code, "main"), &.{}, .{ .arguments = .{ .max_depth = 0 } }));
}
const ProjectSource = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import data
            \\
            \\
            \\def main() -> i64:
            \\    return 0
        );
        if (std.mem.eql(u8, path, "data.my")) return allocator.dupe(u8, "module data;export Positive;export Decoded;" ++ domain_source ++
            \\def hidden() -> i64:
            \\    return 7
        );
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = ProjectSource.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    const output = try c.invokePublic(allocator, "data::Positive.decode", &.{.{ .i64 = 9 }}, .{});
    defer output.value.release(allocator);
    try t.expectEqual(@as(usize, 0), try output.value.variantTag());
    var steps: u64 = 999;
    try t.expectError(error.UnknownPublicFunction, c.invokePublic(allocator, "data::hidden", &.{}, .{ .steps_executed = &steps }));
    try t.expectEqual(@as(u64, 0), steps);
    try t.expectError(error.UnknownPublicFunction, c.invokePublic(allocator, "data::Positive.raw", &.{.{ .i64 = 1 }}, .{}));
    const encoded = try c.invokePublic(allocator, "data::Positive.encode", &.{output.value.aggregate.fields[0]}, .{});
    defer encoded.value.release(allocator);
    try t.expectEqual(@as(i64, 9), encoded.value.i64);
}
test "project typed invocation selects exports and public domain methods under allocation failures" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}

fn aggregateCopyScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "copy-failure.my",
        \\class R:
        \\    a: [2]i64
        \\    b: [2]i64
        \\
        \\
        \\def pass(x: R) -> R:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    const id = find(c.code.?, "pass");
    const ty = c.code.?.functions[@backingInt(id)].signature.return_type;
    const array_ty = c.code.?.records[ty.recordIndex()].fields[0].ty;
    const array = try typed.Value.create(t.allocator, array_ty, &.{ .{ .i64 = 7 }, .{ .i64 = 8 } });
    defer array.release(t.allocator);
    const input = try typed.Value.create(t.allocator, ty, &.{ array, array });
    defer input.release(t.allocator);
    const output = try vm.invoke(allocator, c.code.?, id, &.{input}, .{});
    defer output.value.release(allocator);
    try t.expect(output.value.aggregate != input.aggregate);
    try t.expectEqual(@as(i64, 8), output.value.aggregate.fields[1].aggregate.fields[1].i64);
    try t.expectEqual(@as(i64, 7), input.aggregate.fields[0].aggregate.fields[0].i64);
}
test "typed invocation partial aggregate argument copies clean every allocation failure" {
    try aggregateCopyScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), aggregateCopyScenario, .{});
}

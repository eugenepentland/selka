//! Concrete generics preserve universal contracts while using ordinary checked backends.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const text = "fn id<T:copy>(x:T)->T{return x;}" ++
    "fn sum<T:integer>(x:T)->T{if x==cast<T>(0){return x;}return x+sum::<T>(x-cast<T>(1));}" ++
    "fn forward<U:integer>(x:U)->U{return id::<U>(sum::<U>(x));}" ++
    "fn main()->i64{let small=forward::<u8>(4u8);let wide=forward::<i64>(5);" ++
    "if id::<bool>(true){return cast<i64>(small)+wide+sum::<i64>(2);}return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "specialized.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try compilation.execute(allocator)).value);
    // main plus two forward, two sum, and three id specializations.
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-EXECUTION-1
test "generic execution specializes widths forwarding recursion and shared instances" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic execution preserves nominal values through copy contracts" {
    var compilation = try language.Compilation.init(t.allocator, "nominal.my", "struct A{x:i64}struct B{x:i64}fn id<T:copy>(x:T)->T{return x;}" ++
        "fn main()->i64{let a=id::<A>(new A{x:3});let b=id::<B>(new B{x:4});return a.x+b.x;}");
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 7), (try compilation.execute(t.allocator)).value);
    try t.expectEqual(@as(usize, 3), compilation.program.?.functions.len);
    try t.expectEqualStrings("id::<A>", compilation.program.?.functions[1].name);
    try t.expectEqualStrings("id::<B>", compilation.program.?.functions[2].name);
}

fn limited(count: usize) !void {
    var text_buffer: std.Io.Writer.Allocating = .init(t.allocator);
    defer text_buffer.deinit();
    for (0..count) |index| try text_buffer.writer.print("fn g{d}<T:copy>()->i64{{return 0;}}", .{index});
    try text_buffer.writer.writeAll("fn main()->i64{");
    for (0..count) |index| try text_buffer.writer.print("_ = g{d}::<i64>();", .{index});
    try text_buffer.writer.writeAll("return g0::<i64>();}");
    var compilation = try language.Compilation.init(t.allocator, "limit.my", text_buffer.written());
    defer compilation.deinit();
    if (count == 4096) {
        try compilation.check();
        try t.expectEqual(@as(usize, 4097), compilation.program.?.functions.len);
    } else {
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    }
}
test "generic execution bounds actual discovery and reuses instances at capacity" {
    try limited(4096);
    try limited(4097);
}

// spec: GENERIC-DIAGNOSTIC-1
test "generic diagnostics name concrete types independently of discovery order" {
    const cases = [_][]const u8{
        "fn id<T:copy>(x:T)->T{return x;}fn main()->i64{return id::<i64>(2);}",
        "fn id<T:copy>(x:T)->T{return x;}fn extra()->bool{return id::<bool>(true);}fn main()->i64{return id::<i64>(2);}",
    };
    for (cases) |source_text| {
        var compilation = try language.Compilation.init(t.allocator, "names.my", source_text);
        defer compilation.deinit();
        try compilation.check();
        var found = false;
        for (compilation.program.?.functions) |function| {
            if (!std.mem.eql(u8, function.name, "id::<i64>")) continue;
            found = true;
            try t.expectEqualSlices(@import("typed.zig").Type, &.{.i64}, function.type_arguments);
        }
        try t.expect(found);
        const dump = try compilation.dump(t.allocator);
        defer t.allocator.free(dump);
        try t.expect(std.mem.indexOf(u8, dump, "id::<i64>") != null);
    }
}
test "generic diagnostics retain instantiated names in runtime traces" {
    var compilation = try language.Compilation.init(t.allocator, "trace.my", "fn divide<T:integer>(x:T)->T{return x/cast<T>(0);}fn forward<U:integer>(x:U)->U{return divide::<U>(x);}" ++
        "fn main()->i64{return cast<i64>(forward::<u8>(1u8));}");
    defer compilation.deinit();
    const result = try compilation.execute(t.allocator);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", result.trap.code);
    try t.expectEqual(@as(usize, 3), result.trap.stack.len);
    try t.expectEqualStrings("divide::<u8>", result.trap.stack.frames[0].function);
    try t.expectEqualStrings("forward::<u8>", result.trap.stack.frames[1].function);
}

test "generic execution rejects concrete requirement and arity violations" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source = "fn f<T:integer>(x:T)->T{return x;}fn main()->i64{_ = f::<bool>(true);return 0;}", .code = "E_GENERIC_ARGUMENT" },
        .{ .source = "fn f<T:copy,U:copy>(x:T)->T{return x;}fn main()->i64{return f(1);}", .code = "E_GENERIC_INFERENCE" },
        .{ .source = "fn f<T:copy>(x:T)->T{return x;}fn main()->i64{return f::<i64>(true);}", .code = "E_TYPE" },
        .{ .source = "fn main<T:copy>()->i64{return 0;}", .code = "E_MAIN" },
        .{ .source = "fn bad<T:copy>(x:T)->T{return x+x;}fn main()->i64{return bad::<i64>(2);}", .code = "E_GENERIC_OPERATION" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "rejected.my", case.source);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

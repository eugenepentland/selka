//! Differential acceptance for fused execution against original instruction dispatch.
const std = @import("std");
const language = @import("compiler.zig");
const t = std.testing;
fn same(left: language.vm.Result, right: language.vm.Result) !void {
    try t.expectEqual(std.meta.activeTag(left), std.meta.activeTag(right));
    switch (left) {
        .value => |value| try t.expectEqual(value, right.value),
        .trap => |failure| {
            const other = right.trap;
            try t.expectEqualStrings(failure.code, other.code);
            try t.expectEqualStrings(failure.message, other.message);
            try t.expectEqual(failure.span, other.span);
            try t.expectEqual(failure.stack.len, other.stack.len);
            try t.expectEqual(failure.stack.omitted, other.stack.omitted);
            for (failure.stack.frames[0..failure.stack.len], other.stack.frames[0..other.stack.len]) |a, b| {
                try t.expectEqualStrings(a.function, b.function);
                try t.expectEqual(a.span, b.span);
            }
        },
    }
}
fn compareBudgets(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "fusion.my", source);
    defer c.deinit();
    try c.emit();
    for ([_]u64{ 1, 3, 12 }) |frames| for (1..220) |steps| {
        const expected = try c.executeWithOptions(t.allocator, .{ .max_steps = steps, .max_frames = frames, .memory = .{ .optimize_dispatch = false } });
        const actual = try c.executeWithOptions(t.allocator, .{ .max_steps = steps, .max_frames = frames });
        try same(expected, actual);
    };
}
// spec: VM-FUSION-1
test "fused arithmetic branches calls and reads preserve every budget cutoff" {
    const sources = [_][]const u8{
        "fn f(x:i64,y:i64)->i64{return x/y+x%y;}fn main()->i64{return f(4294967295,65537);}",
        "fn f(x:i64,y:i64)->i64{return x/y+x%y;}fn main()->i64{return f(4294967296,65537);}",
        "fn f(x:i64,y:i64)->i64{return x/y+x%y;}fn main()->i64{return f(-4294967295,65537);}",
        "fn main()->i64{let mut a=3;let mut b=7;let mut n=0;while n<3{a=b;b=a;n+=1;}return a*10+b;}",
        "fn main()->i64{let mut a=false;let mut b=true;a=b;b=a;if b{return 1;}return 0;}",
        "fn main()->i64{let mut n=2;while n*n<=100{if n%3==0{n+=2;}else{n+=1;}}return n;}",
        "fn f(x:i64,y:i64)->i64{if x*y>5{return 1;}return 0;}fn main()->i64{return f(9223372036854775807,2);}",
        "fn main()->i64{let mut i=0;let mut t=1;while i<4{t=t*3+i;i+=1;}return t;}",
        "fn f(n:i64)->i64{if n<2{return n;}return f(n-1)+f(n-2);}fn main()->i64{return f(5);}",
        "fn f(x:i64,y:i64)->i64{return x/y;}fn main()->i64{return f(-9223372036854775808,-1);}",
        "fn f(x:i64,y:i64)->i64{return x%y;}fn main()->i64{return f(7,0);}",
        "fn f(x:i64,y:i64)->i64{return x+y;}fn main()->i64{return f(9223372036854775807,1);}",
        "fn main()->i64{let a=new [3]i64 [2,4,6];let mut i=0;let mut t=0;while i<4{t+=a[i];i+=1;}return t;}",
        "fn main()->i64{let a=new [3]i64 [2,4,6];let i=7;let d=0;return a[i%d];}",
        "fn f(n:i64)->bool{if n<1{return false;}return true;}fn main()->i64{let b=f(2);if b{return 3;}return 4;}",
    };
    for (sources) |source| try compareBudgets(source);
}
// spec: VM-FUSION-2
test "fused execution preserves borrowed scalar owners" {
    try compareBudgets("fn bump(x:&mut i64)->i64{write_ref(x,read_ref(x)+1);return read_ref(x);}" ++
        "fn main()->i64{let mut n=3;borrow mut n as p{discard bump(p);}n+=2;return n;}");
}
// spec: VM-FUSION-3
test "requested instruction trace is identical under both dispatch settings" {
    var c = try language.Compilation.init(t.allocator, "trace.my", "fn main()->i64{let mut n=0;while n<3{n+=1;}return n;}");
    defer c.deinit();
    var events_a: [128]language.vm_trace.Event = undefined;
    var events_b: [128]language.vm_trace.Event = undefined;
    var a: language.vm_trace.Trace = .{ .events = &events_a };
    var b: language.vm_trace.Trace = .{ .events = &events_b };
    try same(try c.executeWithOptions(t.allocator, .{ .memory = .{ .trace = &a } }), try c.executeWithOptions(t.allocator, .{ .memory = .{ .trace = &b, .optimize_dispatch = false } }));
    try t.expectEqual(a.count, b.count);
    for (events_a[0..a.count], events_b[0..b.count]) |left, right| {
        try t.expectEqual(left.function, right.function);
        try t.expectEqual(left.pc, right.pc);
        try t.expectEqual(left.step, right.step);
        try t.expectEqualStrings(left.operation, right.operation);
        try t.expectEqual(left.span, right.span);
        try t.expectEqualDeep(left.top, right.top);
    }
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "allocation.my", "fn f(n:i64)->i64{if n<1{return n;}return f(n-1)+1;}" ++
        "fn main()->i64{let a=new [2]i64 [3,7];let n=f(6);return a[n%2];}");
    defer c.deinit();
    try t.expectEqual(@as(i64, 3), (try c.execute(allocator)).value);
}
// spec: VM-FUSION-4
test "quickening metadata and execution clean every injected allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

// spec: VM-FUSION-5
test "fusion cache collisions and scalar frame growth preserve results" {
    const increments = comptime blk: {
        var text: []const u8 = "";
        for (0..140) |_| text = text ++ "n+=1;";
        break :blk text;
    };
    const sources = [_][]const u8{
        "fn main()->i64{let mut n=0;let mut i=0;while i<3{" ++ increments ++ "i+=1;}return n;}",
        "fn f(n:i64)->i64{if n<1{return n;}return f(n-1)+1;}fn main()->i64{return f(80);}",
    };
    for (sources, [_]i64{ 420, 80 }) |source, expected| {
        var c = try language.Compilation.init(t.allocator, "collision.my", source);
        defer c.deinit();
        const generic = try c.executeWithOptions(t.allocator, .{ .memory = .{ .optimize_dispatch = false } });
        const optimized = try c.execute(t.allocator);
        try t.expectEqual(expected, generic.value);
        try same(generic, optimized);
    }
}

// spec: VM-FUSION-6
test "invocation normalizes scalar bindings before optimized local access" {
    var c = try language.Compilation.init(t.allocator, "bindings.my", "fn increment(x:i64)->i64{let y=x+1;return y;}fn main()->i64{return 0;}");
    defer c.deinit();
    try c.emit();
    for (c.code.?.functions, 0..) |function, index| {
        if (!std.mem.eql(u8, function.name, "increment")) continue;
        const id: @import("typed.zig").FunctionId = @fromBackingInt(index);
        const result = try language.vm.invoke(t.allocator, c.code.?, id, &.{.{ .integer = .{ .ty = .i64, .value = 41 } }}, .{});
        try t.expectEqual(@as(i64, 42), result.value.i64);
        try t.expectError(error.ValueTypeMismatch, language.vm.invoke(t.allocator, c.code.?, id, &.{.{ .bool = true }}, .{}));
        return;
    }
    return error.TestExpectedEqual;
}

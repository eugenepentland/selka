const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "native.my", "fn twice(x: i64) -> i64 { return x * 2; } fn main() -> i64 { return 1 + twice(3); }");
    defer c.deinit();
    const first = try c.emitC(allocator);
    defer allocator.free(first);
    const second = try c.emitC(allocator);
    defer allocator.free(second);
    try t.expectEqualStrings(first, second);
    try t.expect(std.mem.indexOf(u8, first, "goto L") != null);
    try t.expect(std.mem.indexOf(u8, first, "__builtin_mul_overflow") != null);
}
test "native scalar emission is deterministic and cleans every failed allocation" {
    try scenario(t.allocator);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "native emission rejects unsupported operations and uncalled unsupported signatures" {
    for ([_][]const u8{
        "fn main() -> i64 { let a = new [1]i64 [7]; return a[0]; }",
        "fn unsupported(heap: allocator) -> i64 { return 0; } fn main() -> i64 { return 7; }",
        "fn main() -> i64 { let x = 7; borrow x as r { return read_ref(r); } }",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "native.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expectEqualStrings("E_NATIVE_FEATURE", c.diagnostics.items[c.diagnostics.items.len - 1].code);
    }
}

fn domainScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "domain.my", "domain D:i64 { fn make(x:i64)->D{return wrap<D>(x);} fn value(x:D)->i64{return unwrap(x);} } fn forward(x:D)->D{return x;} fn main()->i64{return D.value(forward(D.make(37)));}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expectEqual(@as(i64, 37), (try c.execute(allocator)).value);
}
test "native nominal scalar domains preserve checked construction and allocation failure cleanup" {
    try domainScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), domainScenario, .{});
}
test "native domain representation elision does not bypass nominal or private checks" {
    for ([_][]const u8{
        "domain D:i64 {} fn main()->i64{discard wrap<D>(1);return 0;}",
        "domain D:i64 { private fn raw(x:i64)->D{return wrap<D>(x);} } fn main()->i64{discard D.raw(1);return 0;}",
        "domain A:i64 {fn make(x:i64)->A{return wrap<A>(x);}} domain B:i64 {} fn take(x:B)->i64{return 0;} fn main()->i64{return take(A.make(1));}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[0].code, "E_NATIVE_FEATURE"));
    }
}

fn enumScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "enum.my", "enum Color{red,green,blue} fn score(x:Color)->i64{match x{Color.blue=>{return 3;},Color.red=>{return 1;},Color.green=>{return 2;}}} fn main()->i64{return score(new Color.red)*100+score(new Color.green)*10+score(new Color.blue);}");
    defer c.deinit();
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "switch (pop())") != null);
    try t.expectEqual(@as(i64, 123), (try c.execute(allocator)).value);
}
test "native closed enum dispatch and VM tag identity survive allocation failures" {
    try enumScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), enumScenario, .{});
}
test "native enum support retains exhaustive nominal checks and rejects unions" {
    for ([_][]const u8{
        "enum E{a,b} fn main()->i64{match new E.a { E.a=>{return 1;} }}",
        "enum A{x} enum B{x} fn main()->i64{if new A.x==new B.x{return 1;}return 0;}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expect(!std.mem.eql(u8, c.diagnostics.items[0].code, "E_NATIVE_FEATURE"));
    }
    for ([_][]const u8{
        "union U{empty} fn main()->i64{discard new U.empty;return 0;}",
        "union U{value:i64} fn main()->i64{match new U.value(7){U.value(x)=>{return x;}}}",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "unsupported.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.emitC(t.allocator));
        try t.expectEqualStrings("E_NATIVE_FEATURE", c.diagnostics.items[0].code);
    }
}

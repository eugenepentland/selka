//! Transparent aliases retain target identity, ownership and module privacy.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
fn scenario(allocator: std.mem.Allocator) !void {
    const text = "type Count=i64;type Counts=[2]Count;type Chosen=Pair<Count>;type Other=Chosen;" ++
        "struct Pair<T:copy>{left:T,right:T}const ANSWER:Count=42;" ++
        "fn identity<T:copy>(value:T)->T{return value;}fn read_value(value:Chosen)->Count{return value.left;}" ++
        "fn main()->i64{let pair=new Other{left:ANSWER,right:0};let values=new Counts[read_value(pair),1];" ++
        "return identity::<Count>(values[0])+values[1];}";
    var compilation = try language.Compilation.init(allocator, "aliases.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 43), (try compilation.execute(allocator)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 43), (try again.execute(allocator)).value);
}
// spec: TYPE-ALIAS-1
test "transparent aliases compose scalar arrays nominal applications constants and generic functions under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "aliases preserve nominal domains and owned result obligations and reject cycles" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "type A=B;type B=A;fn main()->i64{return 0;}", .code = "E_ALIAS_CYCLE" },
        .{ .text = "type A=i64;type A=bool;fn main()->i64{return 0;}", .code = "E_DUPLICATE_TYPE" },
        .{ .text = "struct A{}type A=i64;fn main()->i64{return 0;}", .code = "E_DUPLICATE_TYPE" },
        .{ .text = "domain D:i64{}type Alias=D;fn main()->i64{let value:Alias=1;return 0;}", .code = "E_TYPE" },
        .{ .text = "result R{ok:i64,err:i64}type Alias=R;fn main()->i64{let value=new Alias.ok(1);return 0;}", .code = "E_RESULT_UNHANDLED" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
fn provider(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const hidden = context != null;
    const text = if (std.mem.eql(u8, path, "main.my"))
        "module main;import shapes;fn main()->i64{let value:shapes::Count=42;return value;}"
    else if (std.mem.eql(u8, path, "shapes.my"))
        if (hidden) "module shapes;type Count=i64;" else "module shapes;export Count;type Count=i64;"
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}
test "module aliases export canonical types while private aliases remain inaccessible" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
    var hidden: language.embedded_project.Program = undefined;
    var marker: u8 = 0;
    try t.expectError(error.SourceError, hidden.init(t.allocator, .{ .context = &marker, .read = provider }));
}

test "owned aliases do not permit copying or reuse after a move" {
    var compilation = try language.Compilation.init(t.allocator, "owner.my", "buffer B:i64;type Owner=B;result Open{ok:Owner,err:i64}fn main(heap:allocator)->i64{" ++
        "match acquire_buffer<Open>(heap,0){Open.ok(b)=>{let moved=b;discard b;discard moved;return 0;},Open.err(e)=>{return e;}}}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_OWNED_CONSUMED", compilation.diagnostics.items[0].code);
}
fn privateTarget(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "module main;export Public;struct Secret{value:i64}type Public=Secret;fn main()->i64{return 0;}");
}
test "exported aliases cannot expose private nominal types" {
    var program: language.embedded_project.Program = undefined;
    try t.expectError(error.SourceError, program.init(t.allocator, .{ .context = null, .read = privateTarget }));
}

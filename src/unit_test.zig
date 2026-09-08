//! Unit procedures preserve effectful calls without dummy values or implicit result loss.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const program =
    "fn set(x:&mut i64)->unit{write_ref(x,42);}" ++
    "fn skip<T:copy>(x:T)->unit{discard x;}" ++
    "fn noop()->unit{return;}" ++
    "fn main()->i64{let mut x=0;borrow mut x as edit{set(edit);}skip::<i64>(x);noop();return x;}";

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "unit.my", program);
    defer c.deinit();
    for ([_]bool{ false, true }) |optimized| {
        const result = try c.executeWithOptions(allocator, .{ .memory = .{ .optimize_dispatch = optimized } });
        try t.expectEqual(@as(i64, 42), result.value);
    }
    const generated = try c.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "unit: zero-payload token") != null);
}
// spec: UNIT-1
test "unit calls bare returns generic fallthrough and mutable loans preserve results with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

// spec: UNIT-2
test "unit remains distinct and implicit discard cannot lose ordinary or fallible values" {
    const invalid = [_][]const u8{
        "fn main()->unit{}",
        "result Done{ok:unit,err:i64}fn leak(x:Done)->unit{}fn main()->i64{return 0;}",
        "result Done{ok:unit,err:i64}fn leak<T:copy>(x:Done)->unit{}fn main()->i64{return 0;}",
        "fn f(x:&unit)->&unit from x{}fn main()->i64{return 0;}",
        "fn f<T:copy>(x:&unit)->&unit from x{}fn main()->i64{return 0;}",
        "fn main()->i64{return;}",
        "fn f()->unit{return 0;}fn main()->i64{return 0;}",
        "fn f()->i64{return 7;}fn main()->i64{f();return 0;}",
        "fn f<T:copy>(x:T)->unit{x;}fn main()->i64{return 0;}",
        "fn f()->unit{}fn main()->i64{return f();}",
        "fn f()->unit{}fn main()->i64{if f(){return 1;}return 0;}",
        "fn f()->unit{}fn main()->i64{return f()+1;}",
    };
    for (invalid) |text| {
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}

// spec: UNIT-3
test "unit data and host boundaries reject unsupported ABI values explicitly" {
    const typed = @import("typed.zig");
    try t.expectEqual(typed.Type.unit, @as(typed.Value, .unit).typeOf());
    try t.expect(!typed.Type.unit.isAggregate());
    try t.expect(!typed.Type.unit.isInteger());
    try t.expectEqual(@as(?u3, null), typed.Type.unit.capabilityIndex());
    try t.expectError(error.NotDataType, @import("data_type.zig").check(t.allocator, &.{}, .unit, true));
    var c = try language.Compilation.init(t.allocator, "host.my", "host fn f()->unit effects(host);fn main()->i64{return 0;}");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_HOST_SIGNATURE", c.diagnostics.items[0].code);
}

// spec: UNIT-4
test "unit fallthrough and early return release owned parameters without losing result obligations" {
    const text = "buffer Numbers:i64;result A{ok:Numbers,err:i64}" ++
        "fn consume(values:Numbers,early:bool)->unit{discard len_buffer(values);if early{return;}}" ++
        "fn main(heap:allocator)->i64{let mut i=0;while i<2{match acquire_buffer<A>(heap,2){" ++
        "A.ok(values)=>{consume(values,i==0);},A.err(code)=>{return code;}}i+=1;}return 42;}";
    var c = try language.Compilation.init(t.allocator, "cleanup.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try c.execute(t.allocator)).value);
    const generated = try c.emitC(t.allocator);
    defer t.allocator.free(generated);
}

// spec: UNIT-5
test "unit result payloads still require handling and try only drops successful unit" {
    const header = "result Done{ok:unit,err:i64}fn noop()->unit{}fn done()->Done{return new Done.ok(noop());}";
    var valid = try language.Compilation.init(t.allocator, "result.my", header ++
        "fn chained()->Done{try done();return done();}" ++
        "fn main()->i64{match chained(){Done.ok(discard)=>{return 42;},Done.err(code)=>{return code;}}}");
    defer valid.deinit();
    try t.expectEqual(@as(i64, 42), (try valid.execute(t.allocator)).value);
    for ([_][]const u8{ "done();", "discard done();", "let pending=done();" }) |statement| {
        const text = try std.fmt.allocPrint(t.allocator, "{s}fn main()->i64{{{s}return 0;}}", .{ header, statement });
        defer t.allocator.free(text);
        var invalid = try language.Compilation.init(t.allocator, "unhandled.my", text);
        defer invalid.deinit();
        try t.expectError(error.SourceError, invalid.check());
    }
}

fn publicUnit(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "module main;export finish;fn finish()->unit{}fn main()->i64{finish();return 42;}");
}
// spec: UNIT-6
test "public unit schemas describe a distinct type while unsupported copied ABIs reject invocation" {
    var guest: language.embedded_project.Program = undefined;
    try guest.init(t.allocator, .{ .context = null, .read = publicUnit });
    defer guest.deinit();
    const schema = try language.schema.render(t.allocator, &guest.compilation);
    defer t.allocator.free(schema);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, schema, .{});
    defer parsed.deinit();
    try t.expect(std.mem.indexOf(u8, schema, "\"kind\":\"unit\"") != null);
    try t.expectError(error.NotDataType, guest.compilation.invokePublic(t.allocator, "main::finish", &.{}, .{}));
    const generated = try guest.compilation.emitC(t.allocator);
    defer t.allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, "UnsupportedSignature") != null);
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, guest.compilation.code.?)).value);
}

//! Abstract contracts are checked without sampling a concrete type or executing templates.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const bodies = @import("generic_bodies.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const pure = "fn identity<T:copy>(x:T)->T{return x;}" ++
    "fn equal<T:equality>(x:T,y:T)->bool{return x==y;}" ++
    "fn arithmetic<T:integer>(x:T,y:T)->T noalloc{let mut value=x;value+=y;" ++
    "while value<cast<T>(10){value=value+cast<T>(1);}if value==y{return -value;}else{return value;}}" ++
    "fn minimum<T:copy>(x:T)->i8{_ = x;return -128i8;}fn main()->i64{return 0;}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.my", pure);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try compilation.check();
}
// spec: GENERIC-BODY-1
test "generic body contracts check pure control flow without concrete representative types" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
test "generic body contracts preserve original module source locations" {
    var compilation = try language.Compilation.init(t.allocator, "mapped.my", "");
    defer compilation.deinit();
    const allocator = compilation.arena.allocator();
    compilation.src = try source.Source.initMapped(allocator, &.{
        try source.Source.init(allocator, "main.my", "fn main()->i64{return 0;}"),
        try source.Source.init(allocator, "library.my", "fn bad<T:copy>(x:T,y:T)->T{return x+y;}"),
    });
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_GENERIC_OPERATION", failure.code);
    try t.expectEqualStrings("library.my", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("+", compilation.src.text(failure.span));
}

fn checkBound(text: []const u8, failure: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "bounded.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    if (failure) {
        try t.expectError(error.SourceError, bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink));
        try t.expectEqualStrings("E_GENERIC_BODY_LIMIT", sink.items.items[0].code);
    } else try bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink);
}
test "generic body contracts bound left-deep expression checking" {
    for ([_]usize{ 100, 300 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("fn f<T:integer>(x:T)->T{return x");
        for (0..length) |_| try text.writer.writeAll("+x");
        try text.writer.writeAll(";}");
        try checkBound(text.written(), length == 300);
    }
}
test "generic body contracts reject top-level and type-parameter shadowing" {
    try reject("fn f<T:copy>(x:T)->T{let main=x;return main;}fn main()->i64{return 0;}", "E_SHADOWING");
    try reject("struct T{}fn f<T:copy>(x:T)->T{return x;}", "E_SHADOWING");
    try reject("fn f<T:copy>(x:T)->T{let T=x;return T;}", "E_SHADOWING");
}

test "generic body contracts reject undeclared operations mismatches and invalid control flow" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T:copy>(x:T,y:T)->T{return x+y;}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:copy>(x:T,y:T)->bool{return x==y;}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:equality>(x:T,y:T)->bool{return x<y;}", .code = "E_GENERIC_OPERATION" },
        .{ .text = "fn f<T:integer,U:integer>(x:T,y:U)->T{return x+y;}", .code = "E_GENERIC_TYPE" },
        .{ .text = "fn f<T:copy>(x:T)->T{return 1;}", .code = "E_GENERIC_TYPE" },
        .{ .text = "fn f<T:integer>(x:T)->T{return x+1;}", .code = "E_GENERIC_TYPE" },
        .{ .text = "fn f<T:copy>(x:T)->T{x=x;return x;}", .code = "E_IMMUTABLE" },
        .{ .text = "fn f<T:copy>(x:T)->T{if true{let y=x;}return y;}", .code = "E_UNKNOWN_NAME" },
        .{ .text = "fn f<T:copy>(x:T)->T{let x=x;return x;}", .code = "E_SHADOWING" },
        .{ .text = "fn f<T:copy>(x:T)->T{if true{return x;}}", .code = "E_MISSING_RETURN" },
        .{ .text = "fn f<T:copy>(x:T)->T{while true{return x;}}", .code = "E_MISSING_RETURN" },
        .{ .text = "fn f<T:copy>(x:T)->T{return x;_ = x;}", .code = "E_UNREACHABLE" },
        .{ .text = "fn f<T:copy>(x:T)->i8{_ = x;return 128i8;}", .code = "E_INTEGER_RANGE" },
        .{ .text = "fn f<T:copy>(x:T)->T{return other::<T>(x);}", .code = "E_UNKNOWN_FUNCTION" },
    };
    for (cases) |case| try reject(case.text, case.code);
}

test "generic body contracts bound wide statement work without host execution" {
    for ([_]usize{ 49998, 49999 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("fn f<T:copy>(x:T)->T{");
        for (0..length) |_| try text.writer.writeAll("_ = x;");
        try text.writer.writeAll("{}return x;}");
        try checkBound(text.written(), length == 49999);
    }
}

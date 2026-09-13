//! Requirement semantics use concrete language operations and preserve obligations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
fn contract(requirement: requirements.Requirement) requirements.Set {
    var result: requirements.Set = .{};
    result.include(requirement);
    return result;
}
test "generic requirements imply prerequisites and match builtin scalar operations" {
    const copy = contract(.copy);
    const equality = contract(.equality);
    const integer = contract(.integer);
    try t.expect(integer.implies(equality) and equality.implies(copy));
    try t.expect(!copy.implies(equality) and !equality.implies(integer));
    for ([_]typed.Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 }) |ty| try t.expect(integer.accepts(ty, &.{}));
    try t.expect(equality.accepts(.bool, &.{}) and !integer.accepts(.bool, &.{}));
    try t.expect(copy.accepts(.clock_cap, &.{}) and !equality.accepts(.clock_cap, &.{}));
}
fn namedType(records: []const typed.Record, name: []const u8) ?typed.Type {
    for (records) |record| if (std.mem.eql(u8, record.name, name)) return record.id;
    return null;
}
fn resolution(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "resolve.my", "fn f<T:copy+integer,U:equality>(a:T,b:U)->T{return a;}fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.parse();
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = compilation.arena.allocator() };
    const resolved = try requirements.resolve(allocator, compilation.src, compilation.syntax.?.functions[0].signature.type_parameters, &sink);
    defer allocator.free(resolved);
    try t.expectEqual(@as(usize, 2), resolved.len);
    try t.expect(resolved[0].requirements.implies(contract(.integer)));
    try t.expect(resolved[1].requirements.implies(contract(.copy)));
    try t.expect(!resolved[1].requirements.implies(contract(.integer)));
}
test "generic requirement resolution owns normalized contracts across allocation failures" {
    try resolution(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), resolution, .{});
}
test "generic requirements diagnose unknown names and builtin shadowing before unsupported specialization" {
    const cases = [_]struct { text: []const u8, code: []const u8, token: []const u8 }{
        .{ .text = "fn f<T:unknown>(x:T)->T{return x;}fn main()->i64{return 0;}", .code = "E_GENERIC_REQUIREMENT", .token = "unknown" },
        .{ .text = "fn f<i64:copy>(x:i64)->i64{return x;}fn main()->i64{return 0;}", .code = "E_SYNTAX", .token = "i64" },
        .{ .text = "fn f<T:copy>(x:T)->T{return x;}fn g<U:bad>(x:U)->U{return x;}fn main()->i64{return 0;}", .code = "E_GENERIC_REQUIREMENT", .token = "bad" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "bad.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
        try t.expectEqualStrings(case.token, compilation.src.text(compilation.diagnostics.items[0].span));
    }
}

test "generic requirement resolution frees partial results for malformed caller supplied syntax" {
    var compilation = try language.Compilation.init(t.allocator, "constructed.my", "T copy i64");
    defer compilation.deinit();
    const Span = @import("source.zig").Span;
    const name: Span = .{ .start = 0, .end = 1 };
    const copy_name: Span = .{ .start = 2, .end = 6 };
    const builtin: Span = .{ .start = 7, .end = 10 };
    const Parameter = @import("ast.zig").TypeParameter;
    const cases = [_]struct { parameters: []const Parameter, code: []const u8 }{
        .{ .parameters = &.{.{ .name = name, .requirements = &.{} }}, .code = "E_GENERIC_REQUIREMENT" },
        .{ .parameters = &.{.{ .name = name, .requirements = &.{ copy_name, copy_name } }}, .code = "E_GENERIC_REQUIREMENT" },
        .{ .parameters = &.{.{ .name = builtin, .requirements = &.{copy_name} }}, .code = "E_GENERIC_PARAMETER" },
        .{ .parameters = &.{ .{ .name = name, .requirements = &.{copy_name} }, .{ .name = name, .requirements = &.{copy_name} } }, .code = "E_GENERIC_PARAMETER" },
    };
    for (cases) |case| {
        var sink: @import("diagnostic.zig").Sink = .{ .allocator = compilation.arena.allocator() };
        try t.expectError(error.SourceError, requirements.resolve(t.allocator, compilation.src, case.parameters, &sink));
        try t.expectEqualStrings(case.code, sink.items.items[0].code);
    }
}

// spec: GENERIC-REQUIREMENTS-1
test "generic requirements preserve nominal identity and ownership obligations" {
    var compilation = try language.Compilation.init(t.allocator, "requirements.my", "domain Distance:i64{}enum Color{red,blue}struct Point{x:i64}resource File:filesystem;" ++
        "result Answer{ok:i64,err:i64}struct Pending{answer:Answer}struct Owned{file:File}" ++
        "fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    const cases = [_]struct { name: []const u8, copy: bool = false, equality: bool = false }{
        .{ .name = "Distance", .copy = true, .equality = true },
        .{ .name = "Point", .copy = true },
        .{ .name = "Color", .copy = true, .equality = true },
        .{ .name = "File" },
        .{ .name = "Answer" },
        .{ .name = "Pending" },
        .{ .name = "Owned" },
    };
    for (cases) |case| {
        const found = namedType(records, case.name);
        try t.expect(found != null);
        const ty = found.?;
        try t.expectEqual(case.copy, contract(.copy).accepts(ty, records));
        try t.expectEqual(case.equality, contract(.equality).accepts(ty, records));
        try t.expect(!contract(.integer).accepts(ty, records));
    }
}

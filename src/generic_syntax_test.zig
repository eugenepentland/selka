//! Generic syntax retains source contract metadata through executable specialization.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const copy = @import("ast_copy.zig");
const source = @import("source.zig");
const fixture = "fn choose<T: copy + equality,U: integer>(x:T,y:U)->T{return x;}fn main()->i64{return choose::<i64,u8>(1,2u8);}";
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.my", fixture);
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const parameters = syntax.functions[0].signature.type_parameters;
    try t.expectEqual(@as(usize, 2), parameters.len);
    try t.expectEqual(@as(usize, 2), parameters[0].requirements.len);
    try t.expectEqualStrings("equality", compilation.src.text(parameters[0].requirements[1]));
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const cloned = try copy.clone(arena.allocator(), syntax);
    try t.expect(cloned.functions[0].signature.type_parameters.ptr != parameters.ptr);
    try t.expect(cloned.functions[0].signature.type_parameters[0].requirements.ptr != parameters[0].requirements.ptr);
    const mapped = try source.Source.initMapped(arena.allocator(), &.{ try source.Source.init(arena.allocator(), "prefix.my", "// prefix\n"), compilation.src });
    const mapper: copy.Mapper = .{ .src = mapped, .module = 1, .node_count = syntax.nodes.items.len, .statement_count = syntax.statements.items.len };
    const moved = try mapper.value(arena.allocator(), ast.Function, cloned.functions[0]);
    try t.expectEqualStrings("copy", mapped.text(moved.signature.type_parameters[0].requirements[0]));
    var seen = false;
    for (syntax.nodes.items) |node| if (node.data == .call) {
        seen = true;
        const moved_call = try mapper.value(arena.allocator(), ast.Node, node);
        try t.expectEqual(@as(usize, 2), moved_call.data.call.type_arguments.len);
        try t.expectEqualStrings("u8", mapped.text(moved_call.data.call.type_arguments[1]));
    };
    try t.expect(seen);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var roundtrip = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer roundtrip.deinit();
    try roundtrip.parse();
    try t.expectEqual(@as(usize, 2), roundtrip.syntax.?.functions[0].signature.type_parameters.len);
    try compilation.check();
}
// spec: GENERIC-SYNTAX-1
test "generic syntax retains requirements type arguments and relocated owned metadata" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic syntax rejects incomplete duplicate and uncallable annotations" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn f<T>(x:T)->T{return x;}", .code = "E_SYNTAX" },
        .{ .text = "fn f<>(x:i64)->i64{return x;}", .code = "E_SYNTAX" },
        .{ .text = "fn f<T:copy,T:integer>(x:T)->T{return x;}", .code = "E_GENERIC_PARAMETER" },
        .{ .text = "fn f<T:copy+copy>(x:T)->T{return x;}", .code = "E_GENERIC_REQUIREMENT" },
        .{ .text = "fn main()->i64{return f::<i64>;}", .code = "E_GENERIC_CALL" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "bad.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.parse());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
    var compilation = try language.Compilation.init(t.allocator, "bad-call.my", "fn f(x:i64)->i64{return x;}fn main()->i64{return f::<i64>(1);}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_ARITY", compilation.diagnostics.items[0].code);
}

test "generic syntax list limits accept sixteen and reject seventeen entries" {
    for ([_][]const u8{ "parameters", "requirements", "arguments" }) |kind| {
        for ([_]usize{ 16, 17 }) |count| {
            var text: std.Io.Writer.Allocating = .init(t.allocator);
            defer text.deinit();
            const arguments = std.mem.eql(u8, kind, "arguments");
            const parameters = std.mem.eql(u8, kind, "parameters");
            try text.writer.writeAll(if (arguments) "fn main()->i64{return f::<" else if (parameters) "fn f<" else "fn f<T:");
            for (0..count) |i| {
                if (i != 0) try text.writer.writeAll(if (parameters or arguments) "," else "+");
                if (arguments) try text.writer.writeAll("i64") else if (parameters) try text.writer.print("T{d}:copy", .{i}) else try text.writer.print("R{d}", .{i});
            }
            try text.writer.writeAll(if (arguments) ">(1);}" else ">(x:i64)->i64{return x;}");
            var compilation = try language.Compilation.init(t.allocator, "limits.my", text.written());
            defer compilation.deinit();
            if (count == 16) try compilation.parse() else {
                try t.expectError(error.SourceError, compilation.parse());
                try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
            }
        }
    }
}

test "generic syntax preserves reference call and domain method forms" {
    const texts = [_][]const u8{
        "fn main()->i64{let x=1;borrow x as r{borrow echo::<i64>(r) as s{return read_ref(s);}}}",
        "domain D:i64{fn make<T:copy>(x:T)->T{return x;}}fn main()->i64{return D.make::<i64>(1);}",
    };
    for (texts) |text| {
        var compilation = try language.Compilation.init(t.allocator, "forms.my", text);
        defer compilation.deinit();
        try compilation.parse();
        const formatted = try compilation.format(t.allocator);
        defer t.allocator.free(formatted);
        var again = try language.Compilation.init(t.allocator, "forms.my", formatted);
        defer again.deinit();
        try again.parse();
    }
}

test "generic syntax preserves qualified module type arguments when formatting" {
    const text = "module main;import api;fn main()->i64{return api::identity::<api::Number>(1);}";
    var compilation = try language.Compilation.init(t.allocator, "main.my", text);
    defer compilation.deinit();
    const first = try compilation.formatModule(t.allocator);
    defer t.allocator.free(first);
    var again = try language.Compilation.init(t.allocator, "main.my", first);
    defer again.deinit();
    const second = try again.formatModule(t.allocator);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
}

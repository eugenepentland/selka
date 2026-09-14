//! Nominal template syntax survives copying, relocation and interface checks without unsafe lowering.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const ast = @import("ast.zig");
const copy = @import("ast_copy.zig");
const fixture =
    \\class Pair[T, U: equality]:
    \\    first: T
    \\    second: U
    \\
    \\
    \\union Slot[T]:
    \\    none,
    \\    some: T
    \\
    \\
    \\result Outcome[T, E]:
    \\    ok: T,
    \\    err: E
    \\
    \\
    \\enum Tag[T]:
    \\    left,
    \\    right
    \\
    \\
    \\def sample[T](x: T) -> Pair[T, bool]:
    \\    p: Pair[T, bool] = Pair[T, bool](first=x, second=True)
    \\    slots: [1]Slot[Pair[T, bool]] = [Slot.some(p)]
    \\    match slots[0]:
    \\        case Slot.none:
    \\            return p
    \\        case Slot.some(value):
    \\            return value
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
fn parseScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "nominal.my", fixture);
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    try t.expectEqual(@as(usize, 2), syntax.types.records[0].type_parameters.len);
    try t.expectEqual(@as(usize, 3), syntax.types.variants.len);
    try t.expectEqualStrings("equality", compilation.src.text(syntax.types.records[0].type_parameters[1].requirements[0]));
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const cloned = try copy.clone(arena.allocator(), syntax);
    try t.expect(cloned.types.records[0].type_parameters.ptr != syntax.types.records[0].type_parameters.ptr);
    const application = syntax.types.expressions.applications[0];
    try t.expectEqualStrings("Pair[T, bool]", compilation.src.text(application.span));
    try t.expectEqualStrings("Pair", compilation.src.text(application.name));
    try t.expect(cloned.types.expressions.applications[0].arguments.ptr != application.arguments.ptr);
    const mapped = try language.source.Source.initMapped(arena.allocator(), &.{ try language.source.Source.init(arena.allocator(), "prefix.my", "// prefix\n"), compilation.src });
    const mapper: copy.Mapper = .{ .src = mapped, .module = 1, .node_count = syntax.nodes.items.len, .statement_count = syntax.statements.items.len };
    const moved = try mapper.value(arena.allocator(), ast.TypeApplication, application);
    try t.expectEqualStrings("Pair[T, bool]", mapped.text(moved.span));
    try t.expectEqualStrings("bool", mapped.text(moved.arguments[1]));
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "p: Pair[T, bool] = Pair[T, bool](first=x, second=True)") != null);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try again.parse();
    try t.expectEqual(syntax.types.expressions.applications.len, again.syntax.?.types.expressions.applications.len);
    const stable = try again.format(allocator);
    defer allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
}
// spec: NOMINAL-TYPE-SYNTAX-1
test "nominalHeads and splitTypeClosures preserve template metadata through every allocation failure" {
    try parseScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), parseScenario, .{});
}
fn parseReject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
test "nominal templates reject malformed declarations and application lists" {
    try parseReject(
        \\class Box[T, T]:
        \\    value: T
    , "E_GENERIC_PARAMETER");
    try parseReject(
        \\union Slot[T: copy + copy]:
        \\    none,
        \\    some: T
    , "E_GENERIC_REQUIREMENT");
    try parseReject(
        \\def f(x: Box[]) -> i64:
        \\    return 0
    , "E_TYPE");
    try parseReject(
        \\def f(x: Box[i64,]) -> i64:
        \\    return 0
    , "E_TYPE");
    try parseReject(
        \\def f(x: Box[i64) -> i64:
        \\    return 0
    , "E_SYNTAX");
}
fn listSource(allocator: std.mem.Allocator, count: usize, nested: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("def f(x: ");
    if (nested) {
        for (0..count) |_| try out.writer.writeAll("Box[");
        try out.writer.writeAll("i64");
        for (0..count) |_| try out.writer.writeByte(']');
    } else {
        try out.writer.writeAll("Box[");
        for (0..count) |index| {
            if (index != 0) try out.writer.writeAll(", ");
            try out.writer.writeAll("i64");
        }
        try out.writer.writeByte(']');
    }
    try out.writer.writeAll(") -> i64:\n    return 0\n");
    return out.toOwnedSlice();
}
test "nominal application list and nesting bounds reject excessive syntax" {
    const allowed = try listSource(t.allocator, 16, false);
    defer t.allocator.free(allowed);
    var compilation = try language.Compilation.init(t.allocator, "allowed.my", allowed);
    defer compilation.deinit();
    try compilation.parse();
    try t.expectEqual(@as(usize, 16), compilation.syntax.?.types.expressions.applications[0].arguments.len);
    const excessive = try listSource(t.allocator, 17, false);
    defer t.allocator.free(excessive);
    try parseReject(excessive, "E_GENERIC_LIMIT");
    const nested = try listSource(t.allocator, 257, true);
    defer t.allocator.free(nested);
    try parseReject(nested, "E_NESTING_LIMIT");
}

test "unused nominal templates do not become empty executable record schemas" {
    const cases = [_][]const u8{
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        ,
        \\union Slot[T]:
        \\    none,
        \\    some: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        ,
        \\result R[T]:
        \\    ok: T,
        \\    err: i64
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        ,
        \\enum Tag[T]:
        \\    first,
        \\    second
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        ,
    };
    for (cases) |text| {
        var compilation = try language.Compilation.init(t.allocator, "deferred.my", text);
        defer compilation.deinit();
        try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
        try t.expectEqual(@as(usize, 0), compilation.program.?.records.len);
    }
    var invalid = try language.Compilation.init(t.allocator, "requirements.my",
        \\class Box[T: missing]:
        \\    value: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.check());
    try t.expectEqualStrings("E_GENERIC_REQUIREMENT", invalid.diagnostics.items[0].code);
}

const Modules = struct {
    main: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Modules = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, self.main);
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\export Slot
            \\export Id
            \\
            \\
            \\union Slot[T]:
            \\    none,
            \\    some: T
            \\
            \\
            \\class Hidden[T]:
            \\    value: T
            \\
            \\
            \\domain Id: i64:
            \\    pass
        );
        return error.NotFound;
    }
    fn provider(self: *Modules) language.project.Provider {
        return .{ .context = self, .read = read };
    }
};
const public_module =
    \\module main
    \\import model as m
    \\export Box
    \\export echo
    \\
    \\
    \\class Box[T]:
    \\    value: m.Slot[[2]T]
    \\
    \\
    \\def echo[T](x: Box[T]) -> Box[T]:
    \\    return x
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var files: Modules = .{ .main = public_module };
    var cache = @import("syntax_cache.zig").Cache.init(allocator, .{});
    defer cache.deinit();
    for (0..2) |iteration| {
        var project = language.project.Project.init(allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try language.interfaces.buildWithCache(&project, &cache, null);
        const merged = try @import("project_syntax.zig").build(&index);
        try t.expectEqual(@as(usize, 3), merged.syntax.types.expressions.applications.len);
        const application = merged.syntax.types.expressions.applications[0];
        try t.expectEqualStrings("m.Slot", merged.src.text(application.name));
        try t.expectEqualStrings("[2]T", merged.src.text(application.arguments[0]));
        try t.expectEqual(@as(usize, iteration * 2), cache.statistics.hits);
        var compilation = try language.project_compile.Compilation.init(&index);
        try compilation.emit();
        try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
    }
}
test "public nominal templates survive cached syntax and project relocation with requirements intact" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}
fn interfaceReject(text: []const u8, code: []const u8) !void {
    var files: Modules = .{ .main = text };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    try t.expectError(error.SourceError, language.interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
}
test "nominal template interfaces enforce privacy arity kind and parameter scope" {
    try interfaceReject(
        \\module main
        \\import model as m
        \\export Outer
        \\
        \\
        \\class Outer:
        \\    slot: m.Hidden[i64]
    , "E_PRIVATE_SYMBOL");
    try interfaceReject(
        \\module main
        \\import model as m
        \\export Outer
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\class Outer:
        \\    slot: m.Slot[Secret]
    , "E_PRIVATE_INTERFACE");
    try interfaceReject(
        \\module main
        \\import model as m
        \\export Outer
        \\
        \\
        \\class Outer:
        \\    slot: m.Slot[i64, bool]
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\module main
        \\import model as m
        \\export Outer
        \\
        \\
        \\class Outer:
        \\    slot: m.Slot
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\module main
        \\export Plain
        \\export Outer
        \\
        \\
        \\class Plain:
        \\    pass
        \\
        \\
        \\class Outer:
        \\    value: Plain[i64]
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\module main
        \\export Outer
        \\
        \\
        \\class Outer[T]:
        \\    value: T[i64]
    , "E_TYPE_APPLICATION");
    try interfaceReject(
        \\module main
        \\export Outer
        \\
        \\
        \\class Outer[T]:
        \\    value: Missing[T]
    , "E_UNKNOWN_SYMBOL");
    try interfaceReject(
        \\module main
        \\export helper
        \\export Outer
        \\
        \\
        \\def helper() -> i64:
        \\    return 0
        \\
        \\
        \\class Outer:
        \\    value: helper[i64]
    , "E_SYMBOL_KIND");
    try interfaceReject(
        \\module main
        \\
        \\
        \\class T:
        \\    pass
        \\
        \\
        \\class Outer[T]:
        \\    value: T
    , "E_SHADOWING");
    try interfaceReject(
        \\module main
        \\import model as m
        \\
        \\
        \\class Outer[m]:
        \\    value: m
    , "E_SHADOWING");
    try interfaceReject(
        \\module main
        \\
        \\
        \\class Outer[T: bad]:
        \\    value: T
    , "E_GENERIC_REQUIREMENT");
}

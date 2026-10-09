//! Nominal template syntax survives copying, relocation and interface checks without unsafe lowering.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const ast = @import("ast.zig");
const copy = @import("ast_copy.zig");
const fixture =
    \\record Pair[T, U: equality]:
    \\    first: T
    \\    second: U
    \\
    \\
    \\enum Slot[T]:
    \\    none
    \\    some(value: T)
    \\
    \\
    \\result Outcome[T, E]:
    \\    ok: T,
    \\    err: E
    \\
    \\
    \\enum Tag[T]:
    \\    left
    \\    right
    \\
    \\
    \\func sample[T](x: T) -> Pair[T, bool]:
    \\    mut p: Pair[T, bool] = Pair[T, bool](first=x, second=True)
    \\    mut slots: FixedArray[Slot[Pair[T, bool]], 1] = FixedArray[Slot[Pair[T, bool]], 1]([Slot.some(value=p)])
    \\    match slots[0]:
    \\        case Slot.none:
    \\            return p
    \\        case Slot.some(value=value):
    \\            return value
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn parseScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "nominal.selka", fixture);
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
    const mapped = try language.source.Source.initMapped(arena.allocator(), &.{ try language.source.Source.init(arena.allocator(), "prefix.selka", "// prefix\n"), compilation.src });
    const mapper: copy.Mapper = .{ .src = mapped, .module = 1, .node_count = syntax.nodes.items.len, .statement_count = syntax.statements.items.len };
    const moved = try mapper.value(arena.allocator(), ast.TypeApplication, application);
    try t.expectEqualStrings("Pair[T, bool]", mapped.text(moved.span));
    try t.expectEqualStrings("bool", mapped.text(moved.arguments[1]));
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "p: Pair[T, bool] = Pair[T, bool](first=x, second=True)") != null);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
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
    var compilation = try language.Compilation.init(t.allocator, "bad.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
test "nominal templates reject malformed declarations and application lists" {
    try parseReject(
        \\record Box[T, T]:
        \\    value: T
    , "E_GENERIC_PARAMETER");
    try parseReject(
        \\union Slot[T: copy + copy]:
        \\    none,
        \\    some: T
    , "E_GENERIC_REQUIREMENT");
    try parseReject(
        \\func f(x: Box[,]) -> i64:
        \\    return 0
    , "E_TYPE");
    try parseReject(
        \\func f(x: Box[i64,]) -> i64:
        \\    return 0
    , "E_TYPE");
    try parseReject(
        \\func f(x: Box[i64) -> i64:
        \\    return 0
    , "E_SYNTAX");
}
fn listSource(allocator: std.mem.Allocator, count: usize, nested: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("func f(x: ");
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
    var compilation = try language.Compilation.init(t.allocator, "allowed.selka", allowed);
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

// spec: PRELUDE-TYPES-CATALOG-1
test "unused nominal templates retain only unconditional concrete prelude schemas" {
    const cases = [_][]const u8{
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\enum Slot[T]:
        \\    none
        \\    some(value: T)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\result R[T]:
        \\    ok: T,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
        \\enum Tag[T]:
        \\    first
        \\    second
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        ,
    };
    for (cases) |text| {
        var compilation = try language.Compilation.init(t.allocator, "deferred.selka", text);
        defer compilation.deinit();
        try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
        try t.expectEqual(@as(usize, 3), compilation.program.?.records.len);
    }
    var invalid = try language.Compilation.init(t.allocator, "requirements.selka",
        \\record Box[T: missing]:
        \\    value: T
        \\
        \\
        \\func main() -> i64:
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
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8, self.main);
        if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8,
            \\
            \\
            \\public enum Slot[T]:
            \\    none
            \\    some(value: T)
            \\
            \\
            \\record Hidden[T]:
            \\    value: T
            \\
            \\
            \\public domain Id: i64:
            \\    pass
        );
        return error.NotFound;
    }
    fn provider(self: *Modules) language.project.Provider {
        return .{ .context = self, .read = read };
    }
};
const public_module =
    \\import model as m
    \\
    \\
    \\public record Box[T]:
    \\    value: m.Slot[FixedArray[T, 2]]
    \\
    \\
    \\public func echo[T](x: Box[T]) -> Box[T] effects():
    \\    return x
    \\
    \\
    \\func main() -> i64:
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
        try t.expectEqual(@as(usize, 4), merged.syntax.types.expressions.applications.len);
        const application = find: {
            for (merged.syntax.types.expressions.applications) |candidate| {
                if (std.mem.eql(u8, merged.src.text(candidate.name), "m.Slot")) break :find candidate;
            }
            return error.TestUnexpectedResult;
        };
        try t.expectEqualStrings("m.Slot", merged.src.text(application.name));
        try t.expectEqualStrings("FixedArray[T, 2]", merged.src.text(application.arguments[0]));
        try t.expectEqual(@as(usize, iteration * 2), cache.statistics.hits);
        var compilation = try language.project_compile.Compilation.init(&index);
        try compilation.check();
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
        \\import model as m
        \\
        \\
        \\public record Outer:
        \\    slot: m.Hidden[i64]
    , "E_PRIVATE_SYMBOL");
    try interfaceReject(
        \\import model as m
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public record Outer:
        \\    slot: m.Slot[Secret]
    , "E_PRIVATE_INTERFACE");
    try interfaceReject(
        \\import model as m
        \\
        \\
        \\public record Outer:
        \\    slot: m.Slot[i64, bool]
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\import model as m
        \\
        \\
        \\public record Outer:
        \\    slot: m.Slot
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\
        \\
        \\public record Plain:
        \\    pass
        \\
        \\
        \\public record Outer:
        \\    value: Plain[i64]
    , "E_GENERIC_ARITY");
    try interfaceReject(
        \\
        \\
        \\public record Outer[T]:
        \\    value: T[i64]
    , "E_TYPE_APPLICATION");
    try interfaceReject(
        \\
        \\
        \\public record Outer[T]:
        \\    value: Missing[T]
    , "E_UNKNOWN_SYMBOL");
    try interfaceReject(
        \\
        \\
        \\public func helper() -> i64:
        \\    return 0
        \\
        \\
        \\public record Outer:
        \\    value: helper[i64]
    , "E_SYMBOL_KIND");
    try interfaceReject(
        \\
        \\
        \\record T:
        \\    pass
        \\
        \\
        \\record Outer[T]:
        \\    value: T
    , "E_SHADOWING");
    try interfaceReject(
        \\import model as m
        \\
        \\
        \\record Outer[m]:
        \\    value: m
    , "E_SHADOWING");
    try interfaceReject(
        \\
        \\
        \\record Outer[T: bad]:
        \\    value: T
    , "E_GENERIC_REQUIREMENT");
}

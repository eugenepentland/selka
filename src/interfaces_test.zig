//! Module interface and export privacy tests covering qualified names, semantic checking, execution, and allocation failures.
const project_compile_module = @import("project_compile.zig");
const units_path = "units.my";
/// Local name a facade publishes and resolves through in these scenarios.
const distance_name = "Distance";
const contracts_module = "contracts.my";
const duplicates_module = @import("duplicates.zig");
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const module_names = @import("module_names.zig");
const project_syntax = @import("project_syntax.zig");
const diagnostic_module = @import("diagnostic.zig");
const native = @import("native_execute.zig");
const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| if (std.mem.eql(u8, file.path, path)) {
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        };
        return error.NotFound;
    }
    fn provider(self: *Files) graph.Provider {
        return .{ .context = self, .read = read };
    }
};
const units =
    \\module units
    \\
    \\
    \\public domain Distance: i64:
    \\    private def raw(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\    def make(x: i64) -> Distance effects():
    \\        return Distance.raw(x)
    \\
    \\
    \\def hidden() -> i64:
    \\    return 9
;
const entry =
    \\module main
    \\import units
    \\
    \\
    \\public class Sample:
    \\    distance: units.Distance
    \\
    \\
    \\public def echo(x: [2]units.Distance) -> [2]units.Distance effects():
    \\    return x
    \\
    \\
    \\def main() -> i64:
    \\    x = units.Distance.make(2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    const distance = try index.resolve(.{ .from = 0, .alias = "units", .name = distance_name, .kind = .type, .owner = null, .span = span });
    try t.expectEqual(@as(usize, 1), distance.module);
    _ = try index.resolve(.{ .from = 0, .alias = "units", .name = "Distance.make", .kind = .function, .owner = null, .span = span });
    _ = try index.resolve(.{ .from = 1, .alias = null, .name = "Distance.raw", .kind = .function, .owner = distance_name, .span = span });
    _ = try index.resolve(.{ .from = 1, .alias = null, .name = "hidden", .kind = .function, .owner = null, .span = span });
    const text = try index.render(allocator);
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function Distance.make") != null);
    try t.expect(std.mem.indexOf(u8, text, "Distance.raw") == null);
    try t.expect(std.mem.indexOf(u8, text, "hidden") == null);
    try t.expect(std.mem.indexOf(u8, text, "bodies not type checked") != null);
    const syntax = index.units[0].syntax;
    var call_seen = false;
    for (syntax.nodes.items) |node| if (node.data == .call) {
        call_seen = true;
        try t.expectEqualStrings("units.Distance", project.modules.items[0].src.text(node.data.call.owner.?));
    };
    try t.expect(call_seen);
}
test "module interfaces resolve nominal identities and exported domain methods with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

// spec: INTERFACE-SIGNATURE-1
test "default interface listing renders the whole signature with Python capability spellings" {
    const body =
        \\module main
        \\
        \\
        \\public def main(fs: Filesystem, clock: Clock) -> int:
        \\    return 0
        \\
        \\
        \\public def bump(values: list[int]) -> int effects(mutation) mutates(values):
        \\    values[0] = values[0] + 1
        \\    return values[0]
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "def(fs:Filesystem,clock:Clock)->i64") != null);
    try t.expect(std.mem.indexOf(u8, text, "filesystem_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "clock_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "effects()") != null);
    try t.expect(std.mem.indexOf(u8, text, "mutates(values)") != null);
    try t.expect(std.mem.indexOf(u8, text, "ceiling(mutation)") != null);
}

fn reject(body: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = body }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
}
// spec-case: DOC-1
test "list-interfaces prints a declaration's first docstring line" {
    const body =
        \\module main
        \\
        \\
        \\public record Point:
        \\    """A point in the plane."""
        \\    x: int
        \\
        \\
        \\public def area(width: int, height: int) -> int:
        \\    """The rectangle's area.
        \\
        \\    Long detail that the listing drops.
        \\    """
        \\    return width * height
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export type Point # A point in the plane.") != null);
    try t.expect(std.mem.indexOf(u8, text, "# The rectangle's area.") != null);
    try t.expect(std.mem.indexOf(u8, text, "Long detail") == null);
}
// spec: PROJ-3
test "module interfaces reject duplicate exports missing symbols and private type leaks" {
    try reject(
        \\module main
        \\export Missing
    , "E_EXPORT_REMOVED");
    try reject(
        \\module main
        \\import units
        \\export units.Missing
        \\export units.Missing
    , "E_DUPLICATE_EXPORT");
    try reject(
        \\module main
        \\import units
        \\
        \\
        \\class units:
        \\    pass
    , "E_IMPORT_ALIAS");
    try reject(
        \\module main
        \\
        \\
        \\class X:
        \\    pass
        \\
        \\
        \\def X() -> i64:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public def f(x: Secret) -> i64:
        \\    return 0
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public class Box:
        \\    value: [2]Secret
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public union Box:
        \\    value: Secret
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\public def f(x: Missing) -> i64:
        \\    return 0
    , "E_UNKNOWN_SYMBOL");
    try reject(
        \\module main
        \\def broken(
    , "E_SYNTAX");
}
// spec-case: DIAG-ORACLE-1
test "module interfaces suggest close function names for unknown symbols" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def twice(x: i64) -> i64:
        \\    return x + x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = null, .name = "twic", .kind = .function, .owner = null, .span = span }));
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
    try t.expect(std.mem.indexOf(u8, message, "did you mean `twice`?") != null);
}
test "module privacy rejects direct private access wrong kinds and transitive import names" {
    const cases = [_]struct { alias: ?[]const u8, name: []const u8, kind: interfaces.Kind, code: []const u8, from: usize = 0 }{
        .{ .alias = "units", .name = "hidden", .kind = .function, .code = "E_PRIVATE_SYMBOL" },
        .{ .alias = "units", .name = "Distance.raw", .kind = .function, .code = "E_PRIVATE_SYMBOL" },
        .{ .alias = "units", .name = "Distance", .kind = .function, .code = "E_SYMBOL_KIND" },
        .{ .alias = "other", .name = "Distance", .kind = .type, .code = "E_UNKNOWN_IMPORT" },
        .{ .alias = null, .name = "Distance", .kind = .type, .code = "E_UNKNOWN_SYMBOL" },
        .{ .alias = null, .name = "Distance.raw", .kind = .function, .code = "E_PRIVATE_FUNCTION", .from = 1 },
    };
    for (cases) |case| {
        var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = units_path, .bytes = units } } };
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.build(&project);
        try t.expectError(error.SourceError, index.resolve(.{ .from = case.from, .alias = case.alias, .name = case.name, .kind = case.kind, .owner = null, .span = project.modules.items[case.from].header.declaration }));
        try t.expectEqualStrings(case.code, project.problem.?.code);
        const message = try project.renderProblem(t.allocator);
        defer t.allocator.free(message);
        if (std.mem.eql(u8, case.code, "E_PRIVATE_SYMBOL")) try t.expect(std.mem.indexOf(u8, message, "units.my:") != null);
    }
}

test "module grammar parses qualified variant match constructors and free calls" {
    const text =
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    x = units.Choice.a
        \\    y = units.helper()
        \\    match x:
        \\        case units.Choice.a:
        \\            return y
    ;
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = text },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public enum Choice:
        \\    a
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 1
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const index = try interfaces.build(&project);
    const src = project.modules.items[0].src;
    try expectQualifiedSyntax(index.units[0].syntax, src);
}

fn mergedScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    try t.expectEqual(index.units[0].syntax.functions.len + index.units[1].syntax.functions.len, merged.syntax.functions.len);
    for (merged.syntax.functions, merged.function_modules) |function, module| {
        const at = merged.src.locate(function.name.start);
        try t.expectEqualStrings(project.modules.items[module].src.path, at.path);
        const range = merged.modules[module];
        try t.expect(@backingInt(function.body) >= range.statement_start and @backingInt(function.body) < range.statement_end);
    }
    for (merged.modules, index.units, 0..) |range, unit, module| {
        for (merged.syntax.nodes.items[range.node_start..range.node_end], unit.syntax.nodes.items) |node, original| {
            try t.expectEqualStrings(project.modules.items[module].src.text(original.span), merged.src.text(node.span));
            if (node.data == .call) for (node.data.call.arguments) |argument| try t.expect(@backingInt(argument) >= range.node_start and @backingInt(argument) < range.node_end);
        }
    }
    try t.expectEqualStrings("units.Distance", merged.src.text(merged.syntax.types.records[0].fields[0].ty));
    const original_span = index.units[1].syntax.functions[0].name;
    try t.expectEqualStrings("raw", project.modules.items[1].src.text(original_span));
    try t.expect(original_span.start < merged.syntax.functions[2].name.start);
}
test "module AST relocation retains source spelling namespace ownership and node references under allocation failure" {
    try mergedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), mergedScenario, .{});
}

fn checkedScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    x = units.Distance.make(12)
        \\    return units.Distance.number(x)
        },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public domain Distance: i64:
        \\    private def raw(x: i64) -> Distance:
        \\        return wrap[Distance](x)
        \\
        \\    def make(x: i64) -> Distance effects():
        \\        return Distance.raw(x)
        \\
        \\    def number(x: Distance) -> i64 effects():
        \\        return unwrap(x)
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 12), result.value);
}
test "cross module domain factories type check and execute with allocation failure cleanup" {
    try checkedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), checkedScenario, .{});
}

fn rejectChecked(main: []const u8, dependency: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items.items[0].code);
    const rendered = try compilation.diagnostics.items.items[0].render(t.allocator, compilation.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, ".my:") != null);
}
test "shared record types cross module boundaries and hidden names do not shadow caller locals" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    hidden = 7
        \\    x = units.make(hidden)
        \\    return units.value(x)
        },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public record X:
        \\    number: i64
        \\
        \\
        \\def hidden() -> i64:
        \\    return 99
        \\
        \\
        \\public def make(n: i64) -> X effects():
        \\    return X(number=n)
        \\
        \\
        \\public def value(x: X) -> i64 effects():
        \\    return x.number
        \\
        \\
        \\def main() -> i64:
        \\    return 88
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 7), result.value);
}

fn grouped(analysis: duplicates_module.Analysis, program: @import("typed.zig").Program, left: []const u8, right: []const u8) bool {
    for (analysis.groups) |group| {
        var found_left = false;
        var found_right = false;
        for (group.members) |id| {
            const name = program.functions[@backingInt(id)].name;
            found_left = found_left or std.mem.eql(u8, name, left);
            found_right = found_right or std.mem.eql(u8, name, right);
        }
        if (found_left and found_right) return true;
    }
    return false;
}
fn discoveryScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import left
        \\import right
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
        .{ .path = "left.my", .bytes =
        \\module left
        \\import shared as s
        \\
        \\
        \\class Box:
        \\    n: i64
        \\
        \\
        \\def pure(x: i64) -> i64:
        \\    return x * 2 + 3
        \\
        \\
        \\def nominal(x: Box) -> Box:
        \\    return x
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def wrapper(x: i64) -> i64:
        \\    return helper(x)
        \\
        \\
        \\def shared_use(x: s.Box) -> i64:
        \\    return s.number(x)
        },
        .{ .path = "right.my", .bytes =
        \\module right
        \\import shared as q
        \\
        \\
        \\class Box:
        \\    n: i64
        \\
        \\
        \\def pure(value: i64) -> i64:
        \\    return value * 2 + 3
        \\
        \\
        \\def nominal(value: Box) -> Box:
        \\    return value
        \\
        \\
        \\def helper(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\def wrapper(value: i64) -> i64:
        \\    return helper(value)
        \\
        \\
        \\def shared_use(value: q.Box) -> i64:
        \\    return q.number(value)
        },
        .{ .path = "shared.my", .bytes =
        \\module shared
        \\
        \\
        \\public class Box:
        \\    n: i64
        \\
        \\
        \\public def number(x: Box) -> i64 effects():
        \\    return x.n
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    var analysis = try duplicates_module.discover(allocator, compilation.program.?, .{ .min_nodes = 1, .approximate = true, .near_options = .{ .max_work = 10000 } });
    defer analysis.deinit();
    try t.expect(grouped(analysis, compilation.program.?, "left::pure", "right::pure"));
    try t.expect(grouped(analysis, compilation.program.?, "left::shared_use", "right::shared_use"));
    try t.expect(!grouped(analysis, compilation.program.?, "left::nominal", "right::nominal"));
    try t.expect(!grouped(analysis, compilation.program.?, "left::wrapper", "right::wrapper"));
    const text = try duplicates_module.render(allocator, analysis, compilation.program.?, compilation.src);
    defer allocator.free(text);
    for ([_][]const u8{ "left.my:9:", "right.my:9:", "left::pure", "right::pure", "approximate near-v3" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module duplicate discovery preserves nominal types and callees while normalizing shared import aliases" {
    try discoveryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), discoveryScenario, .{});
}

fn qualityScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import api
        \\
        \\
        \\def main() -> i64:
        \\    return api.used()
        },
        .{ .path = "api.my", .bytes =
        \\module api
        \\
        \\
        \\public def used() -> i64 effects():
        \\    return 7
        \\
        \\
        \\public def unused() -> i64 effects():
        \\    return helper()
        \\
        \\
        \\def helper() -> i64:
        \\    return 2
        \\
        \\
        \\def isolated() -> i64:
        \\    return 3
        \\
        \\
        \\def cycle_a() -> i64:
        \\    return cycle_b()
        \\
        \\
        \\def cycle_b() -> i64:
        \\    return cycle_a()
        \\
        \\
        \\public domain D: i64:
        \\    private def raw(x: i64) -> D:
        \\        return wrap[D](x)
        \\
        \\    def make(x: i64) -> D effects():
        \\        return D.raw(x)
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    try t.expectEqual(@as(usize, 3), roots.len);
    const quality = @import("quality.zig");
    var analysis = try quality.analyzeWithExports(allocator, compilation.program.?, compilation.src, .{}, roots);
    defer analysis.deinit();
    for (compilation.program.?.functions, analysis.functions) |function, metrics| {
        const expected_main = std.mem.eql(u8, function.name, "main::main") or std.mem.eql(u8, function.name, "api::used");
        const expected_export = std.mem.eql(u8, function.name, "api::used") or std.mem.eql(u8, function.name, "api::unused") or std.mem.eql(u8, function.name, "api::D.make");
        const expected_api = expected_export or std.mem.eql(u8, function.name, "api::helper") or std.mem.eql(u8, function.name, "api::D.raw");
        try t.expectEqual(expected_main, metrics.reachable);
        try t.expectEqual(expected_export, metrics.exported);
        try t.expectEqual(expected_api, metrics.reachable_from_exports);
    }
    const text = try quality.render(allocator, analysis, compilation.program.?, compilation.src);
    defer allocator.free(text);
    for ([_][]const u8{
        "quality-modules-v1",
        "module-exported=true reachable-from-exports=true",
        "module-exported=false reachable-from-exports=true domain-private=true",
        "no call path from main or exported interfaces",
        "calls api::used at main.my:",
        "not evidence of external callers",
    }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module quality reports distinguish main export and private helper reachability under allocation failure" {
    try qualityScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), qualityScenario, .{});
}

fn nativeModuleScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import helper
        \\
        \\
        \\def main() -> i64:
        \\    return helper.twice(7)
        },
        .{ .path = "helper.my", .bytes =
        \\module helper
        \\
        \\
        \\public def twice(x: i64) -> i64 effects():
        \\    return x * 2
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const first = try compilation.emitQbe(allocator);
    defer allocator.free(first);
    const second = try compilation.emitQbe(allocator);
    defer allocator.free(second);
    try t.expectEqualStrings(first, second);
    try t.expect(std.mem.indexOf(u8, first, "helper") != null);
}
test "module native emission is deterministic and cleans all failed allocations" {
    try nativeModuleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), nativeModuleScenario, .{});
}

fn expectQualifiedSyntax(syntax: @import("ast.zig").Program, src: @import("source.zig").Source) !void {
    var calls: usize = 0;
    var variants: usize = 0;
    var matches: usize = 0;
    for (syntax.nodes.items) |node| switch (node.data) {
        .call => |call| {
            try t.expectEqualStrings("units.helper", src.text(call.name));
            calls += 1;
        },
        // A payload-free case reads as a field of its qualified enum until the checker rewrites it.
        .field => |field| {
            try t.expectEqualStrings("units.Choice", src.text(syntax.nodes.items[@backingInt(field.base)].data.name));
            try t.expectEqualStrings("a", src.text(field.name));
            variants += 1;
        },
        else => {},
    };
    for (syntax.statements.items) |statement| if (statement.data == .match) {
        try t.expectEqualStrings("units.Choice", src.text(statement.data.match.arms[0].ty));
        matches += 1;
    };
    try t.expectEqual(@as(usize, 1), calls);
    try t.expectEqual(@as(usize, 1), variants);
    try t.expectEqual(@as(usize, 1), matches);
}

test "AST relocation rejects dangling expression and statement identities" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const statements = index.units[0].syntax.statements.items;
    const saved = statements[0];
    statements[0].data = .{ .ret = @fromBackingInt(index.units[0].syntax.nodes.items.len) };
    try t.expectError(error.InvalidNodeId, project_syntax.build(&index));
    statements[0] = saved;
    @constCast(index.units[0].syntax.functions)[0].body = @fromBackingInt(statements.len);
    try t.expectError(error.InvalidStatementId, project_syntax.build(&index));
}
test "public type selection rejects private and unknown nominal types" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\class Hidden:
        \\    n: i64
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Hidden"));
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Missing"));
}

test "schema rendering rejects an exported declaration missing its checked type" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\public class Visible:
        \\    n: i64
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    compilation.program.?.records = &.{};
    try t.expectError(error.InvalidCheckedType, @import("schema.zig").render(t.allocator, &compilation));
}

test "public schema renders normalized mutates metadata and callback contracts" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\public def touch(values: list[int]) -> None effects(mutation) mutates(values):
        \\    values[0] = 1
        \\
        \\
        \\public def apply(f: def(values: list[int]) -> None effects(mutation) mutates(values)) -> None effects():
        \\    _ = f
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const schema = try @import("schema.zig").render(t.allocator, &compilation);
    defer t.allocator.free(schema);
    try t.expect(std.mem.indexOf(u8, schema, "\"name\":\"main::touch\"") != null);
    try t.expect(std.mem.indexOf(u8, schema, "\"mutates\":[0]") != null);
    try t.expect(std.mem.indexOf(u8, schema, "\"return_origin\":\"unknown\"") != null);
}

test "generic syntax module interfaces retain scoped type names without hiding private concrete types" {
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public def f[T](x: T, y: [2]Secret) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    const text =
        \\module main
        \\
        \\
        \\public def echo[T: copy](x: [2]T) -> [2]T effects():
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = text }} };
    var cache = @import("syntax_cache.zig").Cache.init(t.allocator, .{});
    defer cache.deinit();
    for (0..2) |_| {
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.buildWithCache(&project, &cache, null);
        const merged = try project_syntax.build(&index);
        const parameters = merged.syntax.functions[0].signature.type_parameters;
        try t.expectEqual(@as(usize, 1), parameters.len);
        try t.expectEqualStrings("copy", merged.src.text(parameters[0].requirements[0]));
    }
    try t.expectEqual(@as(usize, 1), cache.statistics.hits);
}

test "generic requirements checkGenericRequirements validates exported and uncalled private templates" {
    try reject(
        \\module main
        \\
        \\
        \\public def f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\module main
        \\
        \\
        \\def private_template[T: unknown](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

fn namedConstraintIndexScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\module main
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\public def total[P: Prices](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal)
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = text }} };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const syntax = index.units[0].syntax;
    try t.expectEqual(@as(usize, 1), syntax.types.constraints.len);
    const constraint = syntax.types.constraints[0];
    const id = try index.resolve(.{ .from = 0, .alias = null, .name = "Prices", .kind = .constraint, .owner = null, .span = constraint.name });
    try t.expectEqual(interfaces.Kind.constraint, index.units[id.module].symbols.items[id.symbol].kind);
    const rendered = try index.render(allocator);
    defer allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "export constraint Prices") != null);
    const merged = try project_syntax.build(&index);
    try t.expectEqual(@as(usize, 1), merged.syntax.types.constraints.len);
    var sink: diagnostic_module.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    var names: module_names.Names = .{ .index = &index, .src = merged.src };
    const resolved = try names.constraintIdentity(.{ .alias = null, .name = merged.syntax.types.constraints[0].name }, &sink);
    try t.expectEqual(@as(usize, 0), resolved.module);
}

fn namedConstraintImportScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import contracts
        \\
        \\
        \\public def total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal)
        },
        .{ .path = contracts_module, .bytes =
        \\module contracts
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const bound = index.units[0].syntax.functions[0].signature.type_parameters[0].named_requirements[0];
    const identity = try index.resolve(.{ .from = 0, .alias = "contracts", .name = "Prices", .kind = .constraint, .owner = null, .span = bound.name });
    try t.expectEqual(@as(usize, 1), identity.module);
    const rendered = try index.render(allocator);
    defer allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "export constraint Prices") != null);
}

// spec: NAMED-CONSTRAINT-MODULE-7
test "named constraints resolve imported exported constraints" {
    try namedConstraintImportScenario(t.allocator);
}

// spec: NAMED-CONSTRAINT-MODULE-1
test "named constraints index export render and accept function bounds" {
    try namedConstraintIndexScenario(t.allocator);
}

// spec: NAMED-CONSTRAINT-MODULE-2
test "named constraints reject nominal bounds and wrong kinds" {
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public class Box[T: Prices]:
        \\    pass
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public union Box[T: Prices]:
        \\    item: T
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public def f(x: Prices) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public def f(x: Prices[int]) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
}

// spec: NAMED-CONSTRAINT-MODULE-3
test "named constraints enforce private interface exposure and unknown names" {
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public def f[T: Prices](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\public def f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, secret: Secret) -> int effects())
    , "E_PRIVATE_INTERFACE");
}

// spec: NAMED-CONSTRAINT-MODULE-4
test "named constraints participate in duplicate declaration checks" {
    try reject(
        \\module main
        \\
        \\
        \\class Prices:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-MODULE-6
test "named constraints reject subject shadowing declarations imports and builtins" {
    try reject(
        \\module main
        \\
        \\
        \\class P:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public def f(x: i64) -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\module main
        \\import units
        \\
        \\
        \\constraint Prices[units] = copy
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[int] = copy
    , "E_GENERIC_PARAMETER");
}

// spec: NAMED-CONSTRAINT-MODULE-5
test "named constraints constraintIdentity reports unmapped sources as internal errors" {
    const text =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = text }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var sink: diagnostic_module.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    var names: module_names.Names = .{ .index = &index, .src = project.modules.items[0].src };
    const bound: ast.BoundReference = .{ .alias = null, .name = project.modules.items[0].header.declaration };
    try t.expectError(error.InternalError, names.constraintIdentity(bound, &sink));
}

fn expectNamedConstraintLocatedErrors() !void {
    try reject(
        \\module main
        \\
        \\
        \\public def f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\module main
        \\
        \\
        \\constraint Prices[P] = field(tag: P)
    , "E_GENERIC_REQUIREMENT");
}

test "named constraints resolveConstraint and checkConstraint report located errors" {
    try expectNamedConstraintLocatedErrors();
}

fn acceptNamedConstraintModule(main: []const u8, contracts: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = contracts_module, .bytes = contracts } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try compilation.emit();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

fn rejectNamedConstraintModule(main: []const u8, contracts: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = contracts_module, .bytes = contracts } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
}

// spec-case: NAMED-CONSTRAINT-MODULE-7
test "named constraints accept an imported exported bound when the defining module has more declarations" {
    try acceptNamedConstraintModule(
        \\module main
        \\import contracts
        \\
        \\
        \\public def f[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\public def g[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module contracts
        \\
        \\
        \\record One:
        \\    a: int
        \\
        \\
        \\record Two:
        \\    a: int
        \\
        \\
        \\record Three:
        \\    a: int
        \\
        \\
        \\public constraint C[T] = copy
    );
}

// spec-case: NAMED-CONSTRAINT-MODULE-7
test "named constraints accept an imported exported bound when the defining module is smaller" {
    try acceptNamedConstraintModule(
        \\module main
        \\import contracts
        \\
        \\
        \\public def f[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module contracts
        \\
        \\
        \\record One:
        \\    a: int
        \\
        \\
        \\public constraint C[T] = copy
    );
}

// spec-case: NAMED-CONSTRAINT-MODULE-3
test "named constraints reject an unexported constraint imported from another module" {
    try rejectNamedConstraintModule(
        \\module main
        \\import contracts
        \\
        \\
        \\public def f[T: contracts.C](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module contracts
        \\
        \\
        \\constraint C[T] = copy
    , "E_PRIVATE_SYMBOL");
}

// spec-case: NAMED-CONSTRAINT-MODULE-3
test "named constraints reject a same-module unexported constraint exposed by an exported generic" {
    try reject(
        \\module main
        \\
        \\
        \\constraint C[T] = copy
        \\
        \\
        \\public def f[T: C](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-1
test "named constraints supply copy from an imported constraint to a structural field bound" {
    try acceptNamedConstraintModule(
        \\module main
        \\import contracts
        \\
        \\
        \\def value[T: contracts.C + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module contracts
        \\
        \\
        \\public constraint C[T] = copy
    );
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-5
test "named constraints accept implied copy from equality with a structural field" {
    try acceptChecked(
        \\module main
        \\
        \\
        \\def value[T: equality + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "module units\n");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject a structural field bound without copy" {
    try reject(
        \\module main
        \\
        \\
        \\def value[T: field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "generic body contracts respect module-local declaration and import scopes" {
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def f[T](x: T) -> T:
        \\    units = x
        \\    return units
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "module units\n", "E_SHADOWING");
    try acceptChecked(
        \\module main
        \\import units
        \\
        \\
        \\def f[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\class T:
        \\    pass
    );
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\def bad[T](x: T, y: T) -> T:
        \\    return x + y
    , "E_GENERIC_OPERATION");
}

test "generic calls preserve imported declaration identity and private boundaries" {
    const main =
        \\module main
        \\import units
        \\
        \\
        \\def identity[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\def forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const dependency =
        \\module units
        \\
        \\
        \\public def identity[U](x: U) -> U effects():
        \\    return x
    ;
    try acceptChecked(main, dependency);
    // A domain member names its type arguments through its owner: `m.D.make[T](x)`.
    const domain_main =
        \\module main
        \\import units
        \\
        \\
        \\def forward[T](x: T) -> T:
        \\    return units.D.make[T](x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const domain_dependency =
        \\module units
        \\
        \\
        \\public domain D: i64:
        \\    private def hidden[T](x: T) -> T:
        \\        return x
        \\
        \\    def make[U](x: U) -> U effects():
        \\        return D.hidden[U](x)
    ;
    try acceptChecked(domain_main, domain_dependency);
    try rejectChecked(main,
        \\module units
        \\
        \\
        \\def identity[U](x: U) -> U:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    try rejectChecked(main,
        \\module units
        \\
        \\
        \\public def identity[U: integer](x: U) -> U effects():
        \\    return x
    , "E_GENERIC_ARGUMENT");
}

fn genericCallsScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import units
        \\
        \\
        \\def forward[T: integer](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public def identity[U](x: U) -> U effects():
        \\    _ = helper(1)
        \\    return x
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x + 1
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    var names: @import("module_names.zig").Names = .{ .index = &index, .src = merged.src };
    var sink: diagnostic_module.Sink = .{ .allocator = project.arena.allocator() };
    try @import("generic_bodies.zig").checkWithNames(allocator, merged.src, merged.syntax, &sink, &names);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
test "generic calls module resolution and signature substitution release allocation failures" {
    try genericCallsScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericCallsScenario, .{});
}

test "generic calls requirement diagnostics link caller and imported declaration locations" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import units
        \\
        \\
        \\def forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public def identity[U: integer](x: U) -> U effects():
        \\    return x
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items.items[0];
    try t.expectEqualStrings("E_GENERIC_ARGUMENT", failure.code);
    try t.expectEqualStrings("main.my", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("T", compilation.src.text(failure.span));
    try t.expect(failure.related != null);
    try t.expectEqualStrings(units_path, compilation.src.locate(failure.related.?.span.start).path);
    try t.expectEqualStrings("U", compilation.src.text(failure.related.?.span));
}

fn acceptChecked(main: []const u8, dependency: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try compilation.emit();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

fn genericExecutionScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import units
        \\
        \\
        \\def id[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    _ = units.id[units.Box](units.Box(value=1))
        \\    x = 0
        \\    x = units.set[i64](x, 2)
        \\    values: [1]i64 = [x]
        \\    return units.run() + id[i64](units.head[i64](values))
        },
        .{ .path = units_path, .bytes =
        \\module units
        \\
        \\
        \\public class Box:
        \\    value: i64
        \\
        \\
        \\public def view[T](v: [1]T) -> [1]T effects():
        \\    return v
        \\
        \\
        \\public def head[T](v: [1]T) -> T effects():
        \\    seen = view[T](v)
        \\    return seen[0]
        \\
        \\
        \\public def set[T](x: T, y: T) -> T effects():
        \\    _ = x
        \\    return y
        \\
        \\
        \\public def id[T](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\public def run() -> i64 effects():
        \\    if id[bool](True):
        \\        return id[i64](5)
        \\    return 0
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    var nominal_instance = false;
    for (compilation.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "units::id[units::Box]")) continue;
        nominal_instance = true;
        try t.expectEqual(@as(usize, 1), function.type_arguments.len);
        try t.expectEqualStrings("units::Box", @import("typed.zig").typeName(function.type_arguments[0], compilation.program.?.records));
    }
    try t.expect(nominal_instance);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    try t.expectEqual(@as(usize, 1), roots.len);
    const schema = try @import("schema.zig").render(allocator, &compilation);
    defer allocator.free(schema);
    try t.expect(std.mem.indexOf(u8, schema, "units::id[") == null);
}
test "generic execution retains module identities and ordinary public schema roots" {
    try genericExecutionScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericExecutionScenario, .{});
}

// spec: EXPORT-PLACEMENT-1
test "exports after declarations retain interface validation and scope boundaries" {
    try acceptChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return units.value() - 42
    ,
        \\module units
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 42
        \\
        \\
    );
    try reject(
        \\module main
        \\export Missing
    , "E_EXPORT_REMOVED");
    try reject(
        \\module main
        \\import units
        \\export units.value
        \\export units.value
    , "E_DUPLICATE_EXPORT");
    try reject(
        \\module main
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public def value(x: Secret) -> i64:
        \\    return 0
        \\
        \\
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\def value() -> i64:
        \\    export value
        \\    return 0
    , "E_SYNTAX");
    try reject(
        \\module main
        \\
        \\
        \\class Value:
        \\    export Value
    , "E_SYNTAX");
    try reject(
        \\module main
        \\
        \\
        \\def value() -> i64:
        \\    return 0
        \\
        \\
        \\import units
    , "E_SYNTAX");
}

fn scatteredExports(allocator: std.mem.Allocator) !void {
    const body =
        \\module main
        \\
        \\
        \\public class Value:
        \\    n: i64
        \\
        \\
        \\
        \\
        \\public def value() -> i64 effects():
        \\    export = 42
        \\    return export
        \\
        \\
        \\public type Number = i64
        \\
        \\
        \\
        \\
        \\public const answer: Number = 42
        \\
        \\
        \\
        \\
        \\public def main() -> i64 effects():
        \\    return value() - answer
        \\
        \\
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const names = [_][]const u8{ "Value", "value", "Number", "answer", "main" };
    var index = try interfaces.build(&project);
    const unit = index.units[0];
    try t.expectEqual(names.len, unit.syntax.types.public_declarations.len);
    for (unit.syntax.types.public_declarations, names) |span, name| {
        try t.expectEqualStrings(name, project.modules.items[0].src.text(span));
    }
    var last: usize = 0;
    for (names) |name| {
        const id = unit.names.get(name).?;
        try t.expect(unit.symbols.items[id].exported);
        try t.expect(unit.symbols.items[id].span.start > last);
        last = unit.symbols.items[id].span.start;
    }
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

test "scattered exports preserve source order and spans through compilation and allocation failures" {
    try scatteredExports(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scatteredExports, .{});
}

test "late duplicate re-export diagnostics locate both original directives" {
    const body =
        \\module main
        \\import units
        \\export units.value
        \\
        \\
        \\export units.value
    ;
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = body }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    const failure = project.problem.?;
    try t.expectEqualStrings("E_DUPLICATE_EXPORT", failure.code);
    try t.expectEqual(std.mem.lastIndexOf(u8, body, "units.value").?, failure.site.span.start);
    try t.expectEqual(std.mem.indexOf(u8, body, "units.value").?, failure.related.?.span.start);
}

const facade_units =
    \\module shared.units
    \\
    \\
    \\public record Distance:
    \\    value: i64
    \\
    \\
    \\public def make(value: i64) -> Distance effects():
    \\    return Distance(value=value)
    \\
    \\
    \\public def metres(distance: Distance) -> i64 effects():
    \\    return distance.value
    \\
    \\
    \\def secret() -> i64 effects():
    \\    return 1
;
const facade_module =
    \\module facade
    \\import shared.units
    \\export shared.units.Distance
    \\export shared.units.make
    \\export shared.units.metres
;
const facade_entry =
    \\module main
    \\import facade
    \\
    \\
    \\def main() -> i64:
    \\    distance: facade.Distance = facade.make(42)
    \\    return facade.metres(distance)
;
/// A facade module publishes imported declarations under its own local names,
/// and a third module names, constructs and calls them through the facade.
fn facadeScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = facade_entry },
        .{ .path = "facade.my", .bytes = facade_module },
        .{ .path = "shared/units.my", .bytes = facade_units },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const units_id = project.names.get("shared.units").?;
    const facade_id = project.names.get("facade").?;
    const main_id = project.names.get("main").?;
    const site = project.modules.items[facade_id].header.declaration;
    const distance = try index.resolve(.{ .from = main_id, .alias = "facade", .name = distance_name, .kind = .type, .owner = null, .span = site });
    try t.expectEqual(units_id, distance.module);
    try t.expectEqualStrings(distance_name, index.units[distance.module].symbols.items[distance.symbol].name);
    const make = try index.resolve(.{ .from = main_id, .alias = "facade", .name = "make", .kind = .function, .owner = null, .span = site });
    try t.expectEqual(units_id, make.module);
    const text = try index.render(allocator);
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "module facade\n  export type Distance\n") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export function make def(value:i64)->shared.units::Distance") != null);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: REEXPORT-1
test "re-export facade publishes an imported declaration and a third module resolves through it" {
    try facadeScenario(t.allocator);
}
// spec: REEXPORT-2
test "re-export rejects an unimported qualifier an unknown target and a private declaration" {
    try reject(
        \\module main
        \\import units
        \\export missing.Distance
    , "E_UNKNOWN_EXPORT");
    try reject(
        \\module main
        \\import units
        \\export units.Missing
    , "E_UNKNOWN_EXPORT");
    try reject(
        \\module main
        \\import units
        \\export units.hidden
    , "E_PRIVATE_SYMBOL");
}

test "cross module bodies enforce private functions private types nominal identity and local shadowing" {
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return units.hidden()
    , units, "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    _ = units.Distance.raw(1)
        \\    return 0
    , units, "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    x = units.Hidden()
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\class Hidden:
        \\    pass
    , "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\class X:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return units.take(X())
    ,
        \\module units
        \\
        \\
        \\public class X:
        \\    pass
        \\
        \\
        \\public def take(x: X) -> i64 effects():
        \\    return 0
    , "E_TYPE");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    units = 1
        \\    return units
    , units, "E_SHADOWING");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return hidden()
    , units, "E_UNKNOWN_SYMBOL");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\def bad() -> i64:
        \\    return True
    , "E_TYPE");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\record Recursive:
        \\    next: Recursive
    , "E_RECURSIVE_RECORD");
}

test "generic calls concrete helpers retain imported identity and private domain boundaries" {
    const caller =
        \\module main
        \\import units
        \\
        \\
        \\def helper(x: i64) -> bool:
        \\    return x == 0
        \\
        \\
        \\def f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.helper(1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    try acceptChecked(caller,
        \\module units
        \\
        \\
        \\public def helper(x: i64) -> i64 effects():
        \\    return leaf(x)
        \\
        \\
        \\def leaf(x: i64) -> i64:
        \\    return x + 1
    );
    try rejectChecked(caller,
        \\module units
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    const domain_caller =
        \\module main
        \\import units
        \\
        \\
        \\def f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.D.helper(1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    try acceptChecked(domain_caller,
        \\module units
        \\
        \\
        \\public domain D: i64:
        \\    def helper(x: i64) -> i64 effects():
        \\        return D.leaf(x)
        \\
        \\    private def leaf(x: i64) -> i64:
        \\        return x + 1
    );
    try rejectChecked(domain_caller,
        \\module units
        \\
        \\
        \\public domain D: i64:
        \\    def helper(x: i64) -> i64:
        \\        return E.leaf(x)
        \\
        \\
        \\domain E: i64:
        \\    private def leaf(x: i64) -> i64:
        \\        return x
    , "E_PRIVATE_FUNCTION");
}

test "interface closure includes domain backing and enum table keys" {
    try reject(
        \\module main
        \\
        \\
        \\domain Hidden: i64:
        \\    pass
        \\
        \\
        \\public domain D: Hidden:
        \\    pass
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\
        \\
        \\enum Key:
        \\    a,
        \\    b
        \\
        \\
        \\public class Table:
        \\    values: [Key]i64
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\module main
        \\export units
        \\import units
    , "E_EXPORT_REMOVED");
}

// spec: ERGONOMIC-INTEGRATION-1
test "cross module effect and recoverable result obligations are enforced" {
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64 noalloc:
        \\    return units.allocate()
    ,
        \\module units
        \\
        \\
        \\public def allocate() -> i64 effects(managed_allocation):
        \\    values: list[i64] = []
        \\    values.append(1)
        \\    return values[0u64]
    , "E_EFFECT_BOUND");
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    pending = units.fallible()
        \\    return 0
    ,
        \\module units
        \\
        \\
        \\public result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\public def fallible() -> R effects():
        \\    return Ok(7)
    , "E_RESULT_UNHANDLED");
}

/// Build, interface-check, and fully check one single-module entry project.
/// The caller owns `project`/`index`/`compilation` order; this helper returns the
/// first diagnostic with `code` after a rejected check, or null after success.
fn projectDiagnostic(index: *interfaces.Index, code: []const u8) !?diagnostic_module.Diagnostic {
    var compilation = try project_compile_module.Compilation.init(index);
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        for (compilation.diagnostics.items.items) |item| {
            if (std.mem.eql(u8, item.code, code)) return item;
        }
        return null;
    };
    return null;
}

// spec: EFFECT-CEILING-INFERRED-1
test "exported functions publish their inferred ceiling while explicit ceilings stay upper bounds" {
    // A pure export checks without an author ceiling and publishes effects=.
    const pure =
        \\module main
        \\
        \\
        \\public def value(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    return value(41)
    ;
    var files_pure: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = pure }} };
    var project_pure = graph.Project.init(t.allocator);
    defer project_pure.deinit();
    try project_pure.load(files_pure.provider(), "main", .{});
    var index_pure = try interfaces.build(&project_pure);
    var compilation_pure = try project_compile_module.Compilation.init(&index_pure);
    try compilation_pure.check();
    index_pure.program = compilation_pure.program.?;
    const pure_contracts = try index_pure.renderContracts(t.allocator);
    defer t.allocator.free(pure_contracts);
    try t.expect(std.mem.indexOf(u8, pure_contracts, "\"name\":\"value\"") != null);
    try t.expect(std.mem.indexOf(u8, pure_contracts, "\"permissions\":\"effects=;mutates=;origin=unknown\"") != null);

    // An allocating export publishes the derived managed_allocation ceiling.
    const allocating =
        \\module main
        \\
        \\
        \\public def value() -> i64:
        \\    items: list[i64] = []
        \\    items.append(7)
        \\    return items[0]
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    var files_alloc: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = allocating }} };
    var project_alloc = graph.Project.init(t.allocator);
    defer project_alloc.deinit();
    try project_alloc.load(files_alloc.provider(), "main", .{});
    var index_alloc = try interfaces.build(&project_alloc);
    var compilation_alloc = try project_compile_module.Compilation.init(&index_alloc);
    try compilation_alloc.check();
    index_alloc.program = compilation_alloc.program.?;
    const alloc_contracts = try index_alloc.renderContracts(t.allocator);
    defer t.allocator.free(alloc_contracts);
    try t.expect(std.mem.indexOf(u8, alloc_contracts, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);
    try t.expect(std.mem.indexOf(u8, alloc_contracts, "effects=managed_allocation,output") == null);

    // An exported generic template and a public domain operation also check and publish.
    const generic =
        \\module main
        \\
        \\
        \\public def identity[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](41)
    ;
    var files_generic: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = generic }} };
    var project_generic = graph.Project.init(t.allocator);
    defer project_generic.deinit();
    try project_generic.load(files_generic.provider(), "main", .{});
    var index_generic = try interfaces.build(&project_generic);
    var compilation_generic = try project_compile_module.Compilation.init(&index_generic);
    try compilation_generic.check();
    index_generic.program = compilation_generic.program.?;
    const generic_contracts = try index_generic.renderContracts(t.allocator);
    defer t.allocator.free(generic_contracts);
    try t.expect(std.mem.indexOf(u8, generic_contracts, "\"name\":\"identity\"") != null);
    try t.expect(std.mem.indexOf(u8, generic_contracts, "\"permissions\":\"effects=;mutates=;origin=unknown\"") != null);

    const domain =
        \\module main
        \\
        \\
        \\public domain Distance: i64:
        \\    private def raw(x: i64) -> Distance:
        \\        return wrap[Distance](x)
        \\
        \\    def make(x: i64) -> Distance:
        \\        return Distance.raw(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var files_domain: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = domain }} };
    var project_domain = graph.Project.init(t.allocator);
    defer project_domain.deinit();
    try project_domain.load(files_domain.provider(), "main", .{});
    var index_domain = try interfaces.build(&project_domain);
    var compilation_domain = try project_compile_module.Compilation.init(&index_domain);
    try compilation_domain.check();
    index_domain.program = compilation_domain.program.?;
    const domain_contracts = try index_domain.renderContracts(t.allocator);
    defer t.allocator.free(domain_contracts);
    try t.expect(std.mem.indexOf(u8, domain_contracts, "\"name\":\"Distance.make\"") != null);
    try t.expect(std.mem.indexOf(u8, domain_contracts, "\"permissions\":\"effects=;mutates=;origin=unknown\"") != null);

    // An explicit ceiling is still an opt-in narrowing and still rejects excess.
    const narrowed =
        \\module main
        \\
        \\
        \\public def value() -> i64 noalloc:
        \\    items: list[i64] = []
        \\    items.append(7)
        \\    return items[0]
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    var files_narrow: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = narrowed }} };
    var project_narrow = graph.Project.init(t.allocator);
    defer project_narrow.deinit();
    try project_narrow.load(files_narrow.provider(), "main", .{});
    var index_narrow = try interfaces.build(&project_narrow);
    try t.expect((try projectDiagnostic(&index_narrow, "E_EFFECT_BOUND")) != null);
}

/// Whether the named contract declaration carries the `@test` discovery marker.
fn contractTestMarker(allocator: std.mem.Allocator, contracts: []const u8, name: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, contracts, .{});
    defer parsed.deinit();
    for (parsed.value.object.get("modules").?.array.items) |module| {
        for (module.object.get("declarations").?.array.items) |declaration| {
            if (!std.mem.eql(u8, declaration.object.get("name").?.string, name)) continue;
            const marker = declaration.object.get("test") orelse return false;
            return marker == .bool and marker.bool;
        }
    }
    return false;
}

// spec: ATTR-2
test "@test declarations publish a discovery marker in the contract manifest" {
    const body =
        \\module main
        \\
        \\
        \\public def helper(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\@test
        \\def takes_param(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\@test
        \\def checks() -> bool effects():
        \\    return True
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const contracts = try index.renderContracts(t.allocator);
    defer t.allocator.free(contracts);
    try t.expect(try contractTestMarker(t.allocator, contracts, "checks"));
    try t.expect(try contractTestMarker(t.allocator, contracts, "takes_param"));
    try t.expect(!try contractTestMarker(t.allocator, contracts, "helper"));
}

// spec: PUBLIC-DECL-1
test "a public declaration crosses the module boundary while an unmarked one stays private" {
    const dependency =
        \\module units
        \\
        \\
        \\public def answer() -> i64:
        \\    return 42
        \\
        \\
        \\public record Reading:
        \\    value: i64
        \\
        \\
        \\def hidden() -> i64:
        \\    return 7
    ;
    const main =
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    reading: units.Reading = units.Reading(value=units.answer())
        \\    return reading.value
    ;
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try rejectChecked(
        \\module main
        \\import units
        \\
        \\
        \\def main() -> i64:
        \\    return units.hidden()
    , dependency, "E_PRIVATE_SYMBOL");
}

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
const fact_status = @import("fact_status.zig");
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
    \\
    \\
    \\public domain Distance: i64:
    \\    private func raw(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\    func make(x: i64) -> Distance effects():
    \\        return Distance.raw(x)
    \\
    \\
    \\func hidden() -> i64:
    \\    return 9
;
const entry =
    \\import units
    \\
    \\
    \\public record Sample:
    \\    distance: units.Distance
    \\
    \\
    \\public func echo(x: FixedArray[units.Distance, 2]) -> FixedArray[units.Distance, 2] effects():
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    mut x = units.Distance.make(2)
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
        \\
        \\
        \\public func main(fs: Filesystem, clock: Clock) -> int:
        \\    _ = fs
        \\    _ = clock
        \\    return 0
        \\
        \\
        \\public func bump(mut values: int[]) -> int effects(mutation):
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
    try t.expect(std.mem.indexOf(u8, text, "func(fs:Filesystem,clock:Clock)->i64") != null);
    try t.expect(std.mem.indexOf(u8, text, "filesystem_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "clock_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "effects()") != null);
    try t.expect(std.mem.indexOf(u8, text, "func(mut values:i64[])->i64") != null);
    try t.expect(std.mem.indexOf(u8, text, "ceiling(mutation)") != null);
}

// spec: KEYWORD-ONLY-3
test "an interface signature prints individual named parameter markers" {
    const body =
        \\
        \\
        \\public func issue(host: int, named code: int, named file: int = 0) -> int effects():
        \\    return host + code + file
        \\
        \\
        \\public func main() -> int:
        \\    return 0
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
    try t.expect(std.mem.indexOf(u8, text, "func(host:i64,named code:i64,named file:i64=0)->i64") != null);
}

// spec-case: TUPLE-7
test "list-interfaces spells a tuple signature back in source form" {
    const body =
        \\
        \\
        \\public func split(text: str, sep: str) -> tuple[str, str]:
        \\    return text, sep
        \\
        \\
        \\public func main() -> int:
        \\    const head, rest = split("key=value", "=")
        \\    return len(head) + len(rest)
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
    const surface = try @import("typed.zig").surfaceTypeText(t.allocator, text);
    defer t.allocator.free(surface);
    try t.expect(std.mem.indexOf(u8, surface, "tuple[str, str]") != null);
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
        \\
        \\
        \\public record Point:
        \\    """A point in the plane."""
        \\    x: int
        \\
        \\
        \\public func area(width: int, height: int) -> int:
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
        \\export Missing
    , "E_EXPORT_REMOVED");
    try reject(
        \\import units
        \\export units.Missing
        \\export units.Missing
    , "E_DUPLICATE_EXPORT");
    try reject(
        \\import units
        \\
        \\
        \\record units:
        \\    pass
    , "E_IMPORT_ALIAS");
    try reject(
        \\
        \\
        \\record X:
        \\    pass
        \\
        \\
        \\func X() -> i64:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func f(x: Secret) -> i64:
        \\    return 0
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public record Box:
        \\    value: FixedArray[Secret, 2]
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public enum Box:
        \\    value(value: Secret)
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\public func f(x: Missing) -> i64:
        \\    return 0
    , "E_UNKNOWN_SYMBOL");
    try reject(
        \\func broken(
    , "E_SYNTAX");
}
// spec-case: DIAG-ORACLE-1
test "module interfaces suggest close function names for unknown symbols" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\
        \\
        \\func twice(x: i64) -> i64:
        \\    return x + x
        \\
        \\
        \\func main() -> i64:
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

const scanner_module = "\n\nfunc helper() -> int:\n    return 7\n\n\npublic func scan() -> int:\n    return helper()\n";
/// Resolve `scanner.helper` from the entry module `entry` whose source is
/// `text`, beside `scanner.my`, and answer the privacy problem code or null.
fn privateHelperProblem(module: []const u8, text: []const u8, extra: ?File) !?[]const u8 {
    const path = try std.fmt.allocPrint(t.allocator, "{s}.my", .{module});
    defer t.allocator.free(path);
    const all = [_]File{ .{ .path = path, .bytes = text }, .{ .path = "scanner.my", .bytes = scanner_module }, extra orelse .{ .path = "unused.my", .bytes = "" } };
    var files: Files = .{ .entries = if (extra == null) all[0..2] else all[0..3] };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), module, .{});
    var index = try interfaces.build(&project);
    const from = project.names.get(if (extra == null) module else "scanner_test").?;
    _ = index.resolve(.{ .from = from, .alias = "scanner", .name = "helper", .kind = .function, .owner = null, .span = project.modules.items[from].header.declaration }) catch |err| {
        if (err != error.SourceError) return err;
        return project.problem.?.code;
    };
    return null;
}

// spec: TEST-PRIVATE-ACCESS-1
test "a module's test file resolves its private declarations and nothing else does" {
    const tester = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == 7\n";
    try t.expectEqual(@as(?[]const u8, null), try privateHelperProblem("scanner_test", tester, null));
    const other = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == 7\n";
    try t.expectEqualStrings("E_PRIVATE_SYMBOL", (try privateHelperProblem("parser_test", other, null)).?);
    // A `scanner_test` another module imports is a library, not a test file,
    // so it could hand the private helper on: it sees only the public surface.
    const importer = "import scanner_test\n\n\nfunc main() -> int:\n    return 0\n";
    try t.expectEqualStrings("E_PRIVATE_SYMBOL", (try privateHelperProblem("main", importer, .{ .path = "scanner_test.my", .bytes = tester })).?);
}

test "module grammar parses qualified variant match constructors and free calls" {
    const text =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.Choice.a
        \\    mut y = units.helper()
        \\    match x:
        \\        case units.Choice.a:
        \\            return y
    ;
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = text },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public enum Choice:
        \\    a
        \\
        \\
        \\public func helper() -> i64 effects():
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
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.Distance.make(12)
        \\    return units.Distance.number(x)
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public domain Distance: i64:
        \\    private func raw(x: i64) -> Distance:
        \\        return wrap[Distance](x)
        \\
        \\    func make(x: i64) -> Distance effects():
        \\        return Distance.raw(x)
        \\
        \\    func number(x: Distance) -> i64 effects():
        \\        return unwrap(x)
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
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
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut hidden = 7
        \\    mut x = units.make(hidden)
        \\    return units.value(x)
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public record X:
        \\    number: i64
        \\
        \\
        \\func hidden() -> i64:
        \\    return 99
        \\
        \\
        \\public func make(n: i64) -> X effects():
        \\    return X(number=n)
        \\
        \\
        \\public func value(x: X) -> i64 effects():
        \\    return x.number
        \\
        \\
        \\func main() -> i64:
        \\    return 88
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
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
        \\import left
        \\import right
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "left.my", .bytes =
        \\import shared as s
        \\
        \\
        \\record Box:
        \\    n: i64
        \\
        \\
        \\func pure(x: i64) -> i64:
        \\    return x * 2 + 3
        \\
        \\
        \\func nominal(x: Box) -> Box:
        \\    return x
        \\
        \\
        \\func helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\func wrapper(x: i64) -> i64:
        \\    return helper(x)
        \\
        \\
        \\func shared_use(x: s.Box) -> i64:
        \\    return s.number(x)
        },
        .{ .path = "right.my", .bytes =
        \\import shared as q
        \\
        \\
        \\record Box:
        \\    n: i64
        \\
        \\
        \\func pure(value: i64) -> i64:
        \\    return value * 2 + 3
        \\
        \\
        \\func nominal(value: Box) -> Box:
        \\    return value
        \\
        \\
        \\func helper(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\func wrapper(value: i64) -> i64:
        \\    return helper(value)
        \\
        \\
        \\func shared_use(value: q.Box) -> i64:
        \\    return q.number(value)
        },
        .{ .path = "shared.my", .bytes =
        \\
        \\
        \\public record Box:
        \\    n: i64
        \\
        \\
        \\public func number(x: Box) -> i64 effects():
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
    for ([_][]const u8{ "left.my:8:", "right.my:8:", "left::pure", "right::pure", "approximate near-v3" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module duplicate discovery preserves nominal types and callees while normalizing shared import aliases" {
    try discoveryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), discoveryScenario, .{});
}

fn qualityScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\import api
        \\
        \\
        \\func main() -> i64:
        \\    return api.used()
        },
        .{ .path = "api.my", .bytes =
        \\
        \\
        \\public func used() -> i64 effects():
        \\    return 7
        \\
        \\
        \\public func unused() -> i64 effects():
        \\    return helper()
        \\
        \\
        \\func helper() -> i64:
        \\    return 2
        \\
        \\
        \\func isolated() -> i64:
        \\    return 3
        \\
        \\
        \\func cycle_a() -> i64:
        \\    return cycle_b()
        \\
        \\
        \\func cycle_b() -> i64:
        \\    return cycle_a()
        \\
        \\
        \\public domain D: i64:
        \\    private func raw(x: i64) -> D:
        \\        return wrap[D](x)
        \\
        \\    func make(x: i64) -> D effects():
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
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\record Hidden:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public record Visible:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public func touch(mut values: int[]) -> Unit effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\public func apply(f: func(mut values: int[]) -> Unit effects(mutation)) -> Unit effects():
        \\    _ = f
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func f[T](x: T, y: FixedArray[Secret, 2]) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    const text =
        \\
        \\
        \\public func echo[T: copy](x: FixedArray[T, 2]) -> FixedArray[T, 2] effects():
        \\    return x
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\func private_template[T: unknown](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

fn namedConstraintIndexScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\public func total[P: Prices](policy: P, subtotal: int) -> int effects():
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
        \\import contracts
        \\
        \\
        \\public func total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal)
        },
        .{ .path = contracts_module, .bytes =
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
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public record Box[T: Prices]:
        \\    pass
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public enum Box[T: Prices]:
        \\    item(value: T)
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: Prices) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: Prices[int]) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
}

// spec: NAMED-CONSTRAINT-MODULE-3
test "named constraints enforce private interface exposure and unknown names" {
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f[T: Prices](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, secret: Secret) -> int effects())
    , "E_PRIVATE_INTERFACE");
}

// spec: NAMED-CONSTRAINT-MODULE-4
test "named constraints participate in duplicate declaration checks" {
    try reject(
        \\
        \\
        \\record Prices:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-MODULE-6
test "named constraints reject subject shadowing declarations imports and builtins" {
    try reject(
        \\
        \\
        \\record P:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: i64) -> int:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\import units
        \\
        \\
        \\constraint Prices[units] = copy
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\
        \\
        \\constraint Prices[int] = copy
    , "E_GENERIC_PARAMETER");
}

// spec: NAMED-CONSTRAINT-MODULE-5
test "named constraints constraintIdentity reports unmapped sources as internal errors" {
    const text =
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
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
        \\import contracts
        \\
        \\
        \\public func f[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\public func g[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
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
        \\import contracts
        \\
        \\
        \\public func f[T: contracts.C](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
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
        \\import contracts
        \\
        \\
        \\public func f[T: contracts.C](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\constraint C[T] = copy
    , "E_PRIVATE_SYMBOL");
}

// spec-case: NAMED-CONSTRAINT-MODULE-3
test "named constraints reject a same-module unexported constraint exposed by an exported generic" {
    try reject(
        \\
        \\
        \\constraint C[T] = copy
        \\
        \\
        \\public func f[T: C](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-1
test "named constraints supply copy from an imported constraint to a structural field bound" {
    try acceptNamedConstraintModule(
        \\import contracts
        \\
        \\
        \\func value[T: contracts.C + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\public constraint C[T] = copy
    );
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-5
test "named constraints accept implied copy from equality with a structural field" {
    try acceptChecked(
        \\
        \\
        \\func value[T: equality + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject a structural field bound without copy" {
    try reject(
        \\
        \\
        \\func value[T: field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "generic body contracts respect module-local declaration and import scopes" {
    try rejectChecked(
        \\import units
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    mut units = x
        \\    return units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "", "E_SHADOWING");
    try acceptChecked(
        \\import units
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record T:
        \\    pass
    );
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\func bad[T](x: T, y: T) -> T:
        \\    return x + y
    , "E_GENERIC_OPERATION");
}

test "generic calls preserve imported declaration identity and private boundaries" {
    const main =
        \\import units
        \\
        \\
        \\func identity[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    const dependency =
        \\
        \\
        \\public func identity[U](x: U) -> U effects():
        \\    return x
    ;
    try acceptChecked(main, dependency);
    // A domain member names its type arguments through its owner: `m.D.make[T](x)`.
    const domain_main =
        \\import units
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.D.make[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    const domain_dependency =
        \\
        \\
        \\public domain D: i64:
        \\    private func hidden[T](x: T) -> T:
        \\        return x
        \\
        \\    func make[U](x: U) -> U effects():
        \\        return D.hidden[U](x)
    ;
    try acceptChecked(domain_main, domain_dependency);
    try rejectChecked(main,
        \\
        \\
        \\func identity[U](x: U) -> U:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    try rejectChecked(main,
        \\
        \\
        \\public func identity[U: integer](x: U) -> U effects():
        \\    return x
    , "E_GENERIC_ARGUMENT");
}

fn genericCallsScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\import units
        \\
        \\
        \\func forward[T: integer](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public func identity[U](x: U) -> U effects():
        \\    _ = helper(1)
        \\    return x
        \\
        \\
        \\func helper(x: i64) -> i64:
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
        \\import units
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public func identity[U: integer](x: U) -> U effects():
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
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

fn genericExecutionScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\import units
        \\
        \\
        \\func id[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    _ = units.id[units.Box](units.Box(value=1))
        \\    mut x = 0
        \\    x = units.set[i64](x, 2)
        \\    mut values: FixedArray[i64, 1] = FixedArray[i64, 1]([x])
        \\    return units.run() + id[i64](units.head[i64](values))
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public record Box:
        \\    value: i64
        \\
        \\
        \\public func view[T](v: FixedArray[T, 1]) -> FixedArray[T, 1] effects():
        \\    return v
        \\
        \\
        \\public func head[T](v: FixedArray[T, 1]) -> T effects():
        \\    mut seen = view[T](v)
        \\    return seen[0]
        \\
        \\
        \\public func set[T](x: T, y: T) -> T effects():
        \\    _ = x
        \\    return y
        \\
        \\
        \\public func id[T](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\public func run() -> i64 effects():
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
    try compilation.check();
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
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.value() - 42
    ,
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 42
        \\
        \\
    );
    try reject(
        \\export Missing
    , "E_EXPORT_REMOVED");
    try reject(
        \\import units
        \\export units.value
        \\export units.value
    , "E_DUPLICATE_EXPORT");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func value(x: Secret) -> i64:
        \\    return 0
        \\
        \\
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\func value() -> i64:
        \\    export value
        \\    return 0
    , "E_SYNTAX");
    try reject(
        \\
        \\
        \\record Value:
        \\    export Value
    , "E_SYNTAX");
    try reject(
        \\
        \\
        \\func value() -> i64:
        \\    return 0
        \\
        \\
        \\import units
    , "E_SYNTAX");
}

fn scatteredExports(allocator: std.mem.Allocator) !void {
    const body =
        \\
        \\
        \\public record Value:
        \\    n: i64
        \\
        \\
        \\
        \\
        \\public func value() -> i64 effects():
        \\    mut export = 42
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
        \\public func main() -> i64 effects():
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
    try compilation.check();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

test "scattered exports preserve source order and spans through compilation and allocation failures" {
    try scatteredExports(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scatteredExports, .{});
}

test "late duplicate re-export diagnostics locate both original directives" {
    const body =
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
    \\
    \\
    \\public record Distance:
    \\    value: i64
    \\
    \\
    \\public func make(value: i64) -> Distance effects():
    \\    return Distance(value=value)
    \\
    \\
    \\public func metres(distance: Distance) -> i64 effects():
    \\    return distance.value
    \\
    \\
    \\func secret() -> i64 effects():
    \\    return 1
;
const facade_module =
    \\import shared.units
    \\export shared.units.Distance
    \\export shared.units.make
    \\export shared.units.metres
;
const facade_entry =
    \\import facade
    \\
    \\
    \\func main() -> i64:
    \\    mut distance: facade.Distance = facade.make(42)
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
    try t.expect(std.mem.indexOf(u8, text, "  export function make func(value:i64)->shared.units::Distance") != null);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
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
        \\import units
        \\export missing.Distance
    , "E_UNKNOWN_EXPORT");
    try reject(
        \\import units
        \\export units.Missing
    , "E_UNKNOWN_EXPORT");
    try reject(
        \\import units
        \\export units.hidden
    , "E_PRIVATE_SYMBOL");
}

test "cross module bodies enforce private functions private types nominal identity and local shadowing" {
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.hidden()
    , units, "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    _ = units.Distance.raw(1)
        \\    return 0
    , units, "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.Hidden()
        \\    return 0
    ,
        \\
        \\
        \\record Hidden:
        \\    pass
    , "E_PRIVATE_SYMBOL");
    try rejectChecked(
        \\import units
        \\
        \\
        \\record X:
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return units.take(X())
    ,
        \\
        \\
        \\public record X:
        \\    pass
        \\
        \\
        \\public func take(x: X) -> i64 effects():
        \\    return 0
    , "E_TYPE");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut units = 1
        \\    return units
    , units, "E_SHADOWING");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return hidden()
    , units, "E_UNKNOWN_SYMBOL");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\func bad() -> i64:
        \\    return True
    , "E_TYPE");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record Recursive:
        \\    next: Recursive
    , "E_RECURSIVE_RECORD");
}

test "generic calls concrete helpers retain imported identity and private domain boundaries" {
    const caller =
        \\import units
        \\
        \\
        \\func helper(x: i64) -> bool:
        \\    return x == 0
        \\
        \\
        \\func f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.helper(1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    try acceptChecked(caller,
        \\
        \\
        \\public func helper(x: i64) -> i64 effects():
        \\    return leaf(x)
        \\
        \\
        \\func leaf(x: i64) -> i64:
        \\    return x + 1
    );
    try rejectChecked(caller,
        \\
        \\
        \\func helper(x: i64) -> i64:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    const domain_caller =
        \\import units
        \\
        \\
        \\func f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.D.helper(1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    try acceptChecked(domain_caller,
        \\
        \\
        \\public domain D: i64:
        \\    func helper(x: i64) -> i64 effects():
        \\        return D.leaf(x)
        \\
        \\    private func leaf(x: i64) -> i64:
        \\        return x + 1
    );
    try rejectChecked(domain_caller,
        \\
        \\
        \\public domain D: i64:
        \\    func helper(x: i64) -> i64:
        \\        return E.leaf(x)
        \\
        \\
        \\domain E: i64:
        \\    private func leaf(x: i64) -> i64:
        \\        return x
    , "E_PRIVATE_FUNCTION");
}

test "interface closure includes domain backing and enum table keys" {
    try reject(
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
        \\
        \\
        \\enum Key:
        \\    a
        \\    b
        \\
        \\
        \\public record Table:
        \\    values: [Key]i64
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\export units
        \\import units
    , "E_EXPORT_REMOVED");
}

// spec: ERGONOMIC-INTEGRATION-1
test "cross module effect and recoverable result obligations are enforced" {
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64 effects():
        \\    return units.allocate()
    ,
        \\
        \\
        \\public func allocate() -> i64 effects(managed_allocation):
        \\    mut values: i64[] = []
        \\    values.append(1)
        \\    return values[0u64]
    , "E_EFFECT_BOUND");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut pending = units.fallible()
        \\    return 0
    ,
        \\
        \\
        \\public result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\public func fallible() -> R effects():
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
        \\
        \\
        \\public func value(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\func main() -> i64:
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
    try t.expect(std.mem.indexOf(u8, pure_contracts, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);

    // An allocating export publishes the derived managed_allocation ceiling.
    const allocating =
        \\
        \\
        \\public func value() -> i64:
        \\    mut items: i64[] = []
        \\    items.append(7)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public func identity[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
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
    try t.expect(std.mem.indexOf(u8, generic_contracts, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);

    const domain =
        \\
        \\
        \\public domain Distance: i64:
        \\    private func raw(x: i64) -> Distance:
        \\        return wrap[Distance](x)
        \\
        \\    func make(x: i64) -> Distance:
        \\        return Distance.raw(x)
        \\
        \\
        \\func main() -> i64:
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
    try t.expect(std.mem.indexOf(u8, domain_contracts, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);

    // An explicit ceiling is still an opt-in narrowing and still rejects excess.
    const narrowed =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    mut items: i64[] = []
        \\    items.append(7)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\public func helper(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\@test
        \\func takes_param(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\@test
        \\func checks() -> bool effects():
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
        \\
        \\
        \\public func answer() -> i64:
        \\    return 42
        \\
        \\
        \\public record Reading:
        \\    value: i64
        \\
        \\
        \\func hidden() -> i64:
        \\    return 7
    ;
    const main =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut reading: units.Reading = units.Reading(value=units.answer())
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
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.hidden()
    , dependency, "E_PRIVATE_SYMBOL");
}

/// The plan's incomplete-interface fixture: one complete declaration with a
/// declared ceiling and one whose body is still a typed hole. The hole makes the
/// body check fail, which is the state `mylang list-interfaces` renders after it
/// ignores the body diagnostic.
const checked_ceiling_fixture =
    \\
    \\
    \\public func double(x: i64) -> i64 effects(managed_allocation):
    \\    return x * 2
    \\
    \\
    \\public func pure(x: i64) -> i64:
    \\    return x + 1
    \\
    \\
    \\func main() -> i64:
    \\    return double(2)
;
const hole_fixture =
    \\
    \\
    \\public func double(x: i64) -> i64 effects(managed_allocation):
    \\    return x * 2
    \\
    \\
    \\public func unfinished(x: i64) -> i64:
    \\    return todo[i64]()
    \\
    \\
    \\func main() -> i64:
    \\    return double(2)
;

// spec: INTERFACE-FACTS-1
test "an unchecked listing reports an unavailable inferred set and keeps a declared ceiling" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = hole_fixture }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    // Body checking fails on the hole, which is what leaves the summary
    // unavailable; the interface gate restores the pre-check problem and lists
    // declarations anyway, exactly as `mylang list-interfaces` does.
    const saved_problem = project.problem;
    try t.expectError(error.SourceError, compilation.check());
    project.problem = saved_problem;
    try t.expect(compilation.program == null);
    index.program = compilation.program;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function double func(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)") != null);
    try t.expect(std.mem.indexOf(u8, text, "export function unfinished func(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)") != null);
    // The internal conservative mask is a bound, never a published inference.
    try t.expect(std.mem.indexOf(u8, text, "filesystem") == null);
}
// spec-case: INTERFACE-FACTS-1
test "a checked listing publishes the inferred set with no analysis clause" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = checked_ceiling_fixture }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function double func(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)") != null);
    try t.expect(std.mem.indexOf(u8, text, "export function pure func(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)") != null);
    try t.expect(std.mem.indexOf(u8, text, "analysis(") == null);
    try t.expect(std.mem.indexOf(u8, text, "unavailable") == null);
}

// spec: INTERFACE-FACTS-2
test "an uninstantiated generic publishes an unavailable template summary" {
    const body =
        \\
        \\
        \\public func build[T](x: T) -> i64:
        \\    mut items: i64[] = []
        \\    items.append(1)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    // The program checks; it simply holds no instantiation of the template, so
    // the checker's conservative mask is not an inferred fact for it.
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function build func(x:$0)->i64 effects(unavailable) analysis(template)") != null);
    try t.expect(std.mem.indexOf(u8, text, "filesystem") == null);
    // The reachability index exists here, so no tests column is published and
    // none is claimed unavailable.
    try t.expect(std.mem.indexOf(u8, text, "tests(unavailable)") == null);
}

// spec: INTERFACE-CONTRACT-STATUS-1
test "the contract manifest states whether a checked program supplied inferred effects" {
    var files_unchecked: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = hole_fixture }} };
    var project_unchecked = graph.Project.init(t.allocator);
    defer project_unchecked.deinit();
    try project_unchecked.load(files_unchecked.provider(), "main", .{});
    var index_unchecked = try interfaces.build(&project_unchecked);
    const unchecked = try index_unchecked.renderContracts(t.allocator);
    defer t.allocator.free(unchecked);
    // The permissions value is the ceiling the signature implies, which follows
    // from the declaration whether or not a body was checked; the conservative
    // mask the checker keeps internally is never published as a fact, so nothing
    // here names `filesystem`.
    try t.expect(std.mem.indexOf(u8, unchecked, "\"analysis\":\"declaration-only\"") != null);
    try t.expect(std.mem.indexOf(u8, unchecked, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);
    try t.expect(std.mem.indexOf(u8, unchecked, "filesystem") == null);

    var files_checked: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = checked_ceiling_fixture }} };
    var project_checked = graph.Project.init(t.allocator);
    defer project_checked.deinit();
    try project_checked.load(files_checked.provider(), "main", .{});
    var index_checked = try interfaces.build(&project_checked);
    var compilation_checked = try project_compile_module.Compilation.init(&index_checked);
    try compilation_checked.check();
    index_checked.program = compilation_checked.program.?;
    const checked = try index_checked.renderContracts(t.allocator);
    defer t.allocator.free(checked);
    // A checked manifest keeps the same shape: the status field is omitted rather
    // than written as `checked`, and the derived ceiling is the `permissions`
    // value.
    try t.expect(std.mem.indexOf(u8, checked, "\"analysis\"") == null);
    try t.expect(std.mem.indexOf(u8, checked, "\"permissions\":\"effects=managed_allocation;mutates=;origin=unknown\"") != null);
}

// spec: FACT-STATUS-1
test "the shared fact-status vocabulary spells the statuses the reference publishes" {
    try t.expectEqualStrings("checked", fact_status.name(.checked));
    try t.expectEqualStrings("template", fact_status.name(.template));
    try t.expectEqualStrings("declaration-only", fact_status.name(.declaration_only));
    try t.expectEqualStrings("declared", fact_status.name(.declared));
    try t.expectEqualStrings("lexical-only", fact_status.name(.lexical_only));
}

// spec-case: DERIVED-EFFECTS-4
test "a Filesystem, Clock or Environment parameter reaches the published ceiling" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\
        \\public func stamp(fs: Filesystem, clock: Clock, env: Environment, net: Network, random: Entropy) -> int:
        \\    return 0
        \\
        \\func main() -> int:
        \\    return 0
        \\
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const listing = try index.render(t.allocator);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "ceiling(filesystem,network,clock,random,environment,managed_allocation)") != null);
}

// spec-case: NUM-LITERAL-4
test "constant hints inspect declaration policy without recording project problems" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes =
        \\public const VALUE: int = 42
        \\func ordinary() -> int:
        \\    return 1
        \\func main() -> int:
        \\    return VALUE
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    const names: module_names.Names = .{ .index = &index, .src = merged.src };
    try t.expect(try names.isConstant(merged.syntax.functions[0].name));
    try t.expect(!try names.isConstant(merged.syntax.functions[1].name));
    try t.expect(!try names.isConstant(merged.syntax.functions[2].name));
    try t.expect(project.problem == null);
}

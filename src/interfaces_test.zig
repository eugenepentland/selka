//! Module interface and export privacy tests covering qualified names, semantic checking, execution, and allocation failures.
const project_compile_module = @import("project_compile.zig");
const units_path = "units.my";
const duplicates_module = @import("duplicates.zig");
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
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
const units = "module units; export Distance; domain Distance: i64 { private fn raw(x: i64) -> Distance { return wrap<Distance>(x); } fn make(x: i64) -> Distance { return Distance.raw(x); } } fn hidden() -> i64 { return 9; }";
const entry = "module main; import units; export Sample; export echo; struct Sample { distance: " ++
    "units::Distance } fn echo(x: [2]units :: Distance) -> [2]units::Distance { return x; " ++
    "} fn main() -> i64 { let x = units::Distance.make(2); return 0; }";
fn scenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    const distance = try index.resolve(.{ .from = 0, .alias = "units", .name = "Distance", .kind = .type, .owner = null, .span = span });
    try t.expectEqual(@as(usize, 1), distance.module);
    _ = try index.resolve(.{ .from = 0, .alias = "units", .name = "Distance.make", .kind = .function, .owner = null, .span = span });
    _ = try index.resolve(.{ .from = 1, .alias = null, .name = "Distance.raw", .kind = .function, .owner = "Distance", .span = span });
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
        try t.expectEqualStrings("units::Distance", project.modules.items[0].src.text(node.data.call.owner.?));
    };
    try t.expect(call_seen);
}
test "module interfaces resolve nominal identities and exported domain methods with allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
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
// spec: PROJ-3
test "module interfaces reject duplicate exports missing symbols and private type leaks" {
    try reject("module main; export Missing;", "E_UNKNOWN_EXPORT");
    try reject("module main; export X; export X; struct X {}", "E_DUPLICATE_EXPORT");
    try reject("module main; import units; struct units {}", "E_IMPORT_ALIAS");
    try reject("module main; struct X {} fn X() -> i64 { return 0; }", "E_DUPLICATE_SYMBOL");
    try reject("module main; export f; struct Secret {} fn f(x: Secret) -> i64 { return 0; }", "E_PRIVATE_INTERFACE");
    try reject("module main; export Box; struct Secret {} struct Box { value: [2]Secret }", "E_PRIVATE_INTERFACE");
    try reject("module main; export Box; struct Secret {} union Box { value: Secret }", "E_PRIVATE_INTERFACE");
    try reject("module main; export f; fn f(x: absent::Thing) -> i64 { return 0; }", "E_UNKNOWN_IMPORT");
    try reject("module main; export f; fn f(x: Missing) -> i64 { return 0; }", "E_UNKNOWN_SYMBOL");
    try reject("module main; fn broken( ;", "E_SYNTAX");
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
        if (std.mem.eql(u8, case.code, "E_PRIVATE_SYMBOL")) try t.expect(std.mem.indexOf(u8, message, "units.my:1:") != null);
    }
}

test "interface closure includes buffers pools domain backing and enum table keys" {
    try reject("module main; export Store; struct Secret {} buffer Store: Secret;", "E_PRIVATE_INTERFACE");
    try reject("module main; export Store; struct Secret {} pool Store(Id): Secret;", "E_PRIVATE_INTERFACE");
    try reject("module main; export D; domain Hidden: i64 {} domain D: Hidden {}", "E_PRIVATE_INTERFACE");
    try reject("module main; export Table; enum Key { a, b } struct Table { values: [Key]i64 }", "E_PRIVATE_INTERFACE");
    try reject("module main; export units; import units;", "E_SYNTAX");
}

test "module grammar parses qualified variant match constructors and free calls" {
    const text = "module main; import units; fn main() -> i64 { let x = new units::Choice.a; let y = units::helper(); match x { units::Choice.a => { return y; } } }";
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = text }, .{ .path = units_path, .bytes = "module units; export Choice; export helper; enum Choice { a } fn helper() -> i64 { return 1; }" } } };
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
    const merged = try @import("project_syntax.zig").build(&index);
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
    try t.expectEqualStrings("units::Distance", merged.src.text(merged.syntax.types.records[0].fields[0].ty));
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
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = "module main; import units; fn main() -> i64 { let x = units::Distance.make(12); " ++
        "return units::Distance.number(x); }" }, .{ .path = units_path, .bytes = "module units; export Distance; domain Distance: i64 { private fn raw(x: i64) -> " ++
        "Distance { return wrap<Distance>(x); } fn make(x: i64) -> Distance { return " ++
        "Distance.raw(x); } fn number(x: Distance) -> i64 { return unwrap(x); } }" } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try @import("vm.zig").runWithOptions(allocator, compilation.code.?, .{});
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
test "cross module bodies enforce private functions private types nominal identity and local shadowing" {
    try rejectChecked("module main; import units; fn main() -> i64 { return units::hidden(); }", units, "E_PRIVATE_SYMBOL");
    try rejectChecked("module main; import units; fn main() -> i64 { discard units::Distance.raw(1); return 0; }", units, "E_PRIVATE_SYMBOL");
    try rejectChecked("module main; import units; fn main() -> i64 { let x = new units::Hidden {}; return 0; }", "module units; struct Hidden {}", "E_PRIVATE_SYMBOL");
    try rejectChecked("module main; import units; struct X {} fn main() -> i64 { return units::take(new X {}); }", "module units; export X; export take; struct X {} fn take(x: X) -> i64 { return 0; }", "E_TYPE");
    try rejectChecked("module main; import units; fn main() -> i64 { let units = 1; return units; }", units, "E_SHADOWING");
    try rejectChecked("module main; import units; fn main() -> i64 { return hidden(); }", units, "E_UNKNOWN_SYMBOL");
    try rejectChecked("module main; import units; fn main() -> i64 { return 0; }", "module units; fn bad() -> i64 { return true; }", "E_TYPE");
    try rejectChecked("module main; import units; fn main() -> i64 { return 0; }", "module units; struct Recursive { next: Recursive }", "E_RECURSIVE_RECORD");
}

test "shared record types cross module boundaries and hidden names do not shadow caller locals" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main; import units; fn main() -> i64 { let hidden = 7; let x = units::make(hidden); return units::value(x); }" },
        .{ .path = units_path, .bytes = "module units; export X; export make; export value; struct X { number: i64 } fn " ++
            "hidden() -> i64 { return 99; } fn make(n: i64) -> X { return new X { number: n }; } " ++
            "fn value(x: X) -> i64 { return x.number; } fn main() -> i64 { return 88; }" },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try @import("vm.zig").runWithOptions(t.allocator, compilation.code.?, .{});
    try t.expectEqual(@as(i64, 7), result.value);
}

test "cross module effect and recoverable result obligations are enforced" {
    try rejectChecked("module main; import units; fn main(a: allocator) -> i64 noalloc { return " ++
        "units::allocate(a); }", "module units; export allocate; buffer B: i64; result R { ok: B, err: i64 } fn " ++
        "allocate(a: allocator) -> i64 { acknowledge acquire_buffer<R>(a, 1); return 0; }", "E_EFFECT_BOUND");
    try rejectChecked("module main; import units; fn main() -> i64 { discard units::fallible(); return 0; }", "module units; export R; export fallible; result R { ok: i64, err: i64 } fn " ++
        "fallible() -> R { return new R.ok(7); }", "E_RESULT_DISCARD");
}

test "cross module returned slice references preserve caller mutation and snapshots" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main; import units; fn main() -> i64 { let mut values = new [3]i64 [1, 2, 3]; " ++
            "let old = values; borrow mut values[0..3] as all { borrow mut units::middle(all) as " ++
            "selected { write_slice(selected, 0, 9); } } return old[1] + values[1]; }" },
        .{ .path = units_path, .bytes = "module units; export middle; fn middle(values: &mut []i64) -> &mut []i64 from values { borrow mut values[1..2] as selected { return selected; } }" },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    const result = try @import("vm.zig").runWithOptions(t.allocator, compilation.code.?, .{});
    try t.expectEqual(@as(i64, 11), result.value);
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
        .{ .path = "main.my", .bytes = "module main; import left; import right; fn main() -> i64 { return 0; }" },
        .{ .path = "left.my", .bytes = "module left; import shared as s; struct Box { n: i64 } fn pure(x: i64) -> i64 { " ++
            "return x * 2 + 3; } fn nominal(x: Box) -> Box { return x; } fn helper(x: i64) -> i64 " ++
            "{ return x + 1; } fn wrapper(x: i64) -> i64 { return helper(x); } fn shared_use(x: " ++
            "s::Box) -> i64 { return s::number(x); }" },
        .{ .path = "right.my", .bytes = "module right; import shared as q; struct Box { n: i64 } fn pure(value: i64) -> i64 { " ++
            "return value * 2 + 3; } fn nominal(value: Box) -> Box { return value; } fn " ++
            "helper(value: i64) -> i64 { return value + 1; } fn wrapper(value: i64) -> i64 { " ++
            "return helper(value); } fn shared_use(value: q::Box) -> i64 { return " ++
            "q::number(value); }" },
        .{ .path = "shared.my", .bytes = "module shared; export Box; export number; struct Box { n: i64 } fn number(x: Box) -> i64 { return x.n; }" },
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
    for ([_][]const u8{ "left.my:1:", "right.my:1:", "left::pure", "right::pure", "approximate near-v3" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module duplicate discovery preserves nominal types and callees while normalizing shared import aliases" {
    try discoveryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), discoveryScenario, .{});
}

fn qualityScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main; import api; fn main() -> i64 { return api::used(); }" },
        .{ .path = "api.my", .bytes = "module api; export used; export unused; export D; fn used() -> i64 { return 7; } fn " ++
            "unused() -> i64 { return helper(); } fn helper() -> i64 { return 2; } fn isolated() " ++
            "-> i64 { return 3; } fn cycle_a() -> i64 { return cycle_b(); } fn cycle_b() -> i64 { " ++
            "return cycle_a(); } domain D: i64 { private fn raw(x: i64) -> D { return wrap<D>(x); " ++
            "} fn make(x: i64) -> D { return D.raw(x); } }" },
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
        .{ .path = "main.my", .bytes = "module main; import helper; fn main() -> i64 { return helper::twice(7); }" },
        .{ .path = "helper.my", .bytes = "module helper; export twice; fn twice(x: i64) -> i64 { return x * 2; }" },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const first = try compilation.emitC(allocator);
    defer allocator.free(first);
    const second = try compilation.emitC(allocator);
    defer allocator.free(second);
    try t.expectEqualStrings(first, second);
    try t.expect(std.mem.indexOf(u8, first, "source_paths = paths") != null);
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
            try t.expectEqualStrings("units::helper", src.text(call.name));
            calls += 1;
        },
        .variant => |variant| {
            try t.expectEqualStrings("units::Choice", src.text(variant.ty));
            variants += 1;
        },
        else => {},
    };
    for (syntax.statements.items) |statement| if (statement.data == .match) {
        try t.expectEqualStrings("units::Choice", src.text(statement.data.match.arms[0].ty));
        matches += 1;
    };
    try t.expectEqual(@as(usize, 1), calls);
    try t.expectEqual(@as(usize, 1), variants);
    try t.expectEqual(@as(usize, 1), matches);
}

test "AST relocation rejects dangling expression and statement identities" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "module main;fn main()->i64{return 0;}" }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const statements = index.units[0].syntax.statements.items;
    const saved = statements[0];
    statements[0].data = .{ .ret = @fromBackingInt(index.units[0].syntax.nodes.items.len) };
    try t.expectError(error.InvalidNodeId, @import("project_syntax.zig").build(&index));
    statements[0] = saved;
    @constCast(index.units[0].syntax.functions)[0].body = @fromBackingInt(statements.len);
    try t.expectError(error.InvalidStatementId, @import("project_syntax.zig").build(&index));
}
test "public type selection rejects private and unknown nominal types" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "module main;struct Hidden{n:i64}fn main()->i64{return 0;}" }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Hidden"));
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Missing"));
}

test "schema rendering rejects an exported declaration missing its checked type" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "module main;export Visible;struct Visible{n:i64}fn main()->i64{return 0;}" }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    compilation.program.?.records = &.{};
    try t.expectError(error.InvalidCheckedType, @import("schema.zig").render(t.allocator, &compilation));
}

test "generic syntax module interfaces retain scoped type names without hiding private concrete types" {
    try reject("module main;export f;struct Secret{}fn f<T:copy>(x:T,y:[2]Secret)->T{return x;}", "E_PRIVATE_INTERFACE");
    const text = "module main;export echo;fn echo<T:copy>(x:[2]T)->[2]T{return x;}fn main()->i64{return 0;}";
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = text }} };
    var cache = @import("syntax_cache.zig").Cache.init(t.allocator, .{});
    defer cache.deinit();
    for (0..2) |_| {
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.buildWithCache(&project, &cache);
        const merged = try @import("project_syntax.zig").build(&index);
        const parameters = merged.syntax.functions[0].signature.type_parameters;
        try t.expectEqual(@as(usize, 1), parameters.len);
        try t.expectEqualStrings("copy", merged.src.text(parameters[0].requirements[0]));
    }
    try t.expectEqual(@as(usize, 1), cache.statistics.hits);
}

test "generic requirements checkGenericRequirements validates exported and uncalled private templates" {
    try reject("module main;export f;fn f<T:unknown>(x:T)->T{return x;}", "E_GENERIC_REQUIREMENT");
    try reject("module main;fn private_template<T:unknown>(x:T)->T{return x;}fn main()->i64{return 0;}", "E_GENERIC_REQUIREMENT");
}

test "generic body contracts respect module-local declaration and import scopes" {
    try rejectChecked("module main;import units;fn f<T:copy>(x:T)->T{let units=x;return units;}fn main()->i64{return 0;}", "module units;", "E_SHADOWING");
    try acceptChecked("module main;import units;fn f<T:copy>(x:T)->T{return x;}fn main()->i64{return 0;}", "module units;struct T{}");
    try rejectChecked("module main;import units;fn main()->i64{return 0;}", "module units;fn bad<T:copy>(x:T,y:T)->T{return x+y;}", "E_GENERIC_OPERATION");
}

test "generic calls preserve imported declaration identity and private boundaries" {
    const main = "module main;import units;fn identity<T:integer>(x:T)->T{return x;}fn forward<T:copy>(x:T)->T{return units::identity::<T>(x);}fn main()->i64{return 0;}";
    const dependency = "module units;export identity;fn identity<U:copy>(x:U)->U{return x;}";
    try acceptChecked(main, dependency);
    const domain_main = "module main;import units;fn forward<T:copy>(x:T)->T{return units::D.make::<T>(x);}fn main()->i64{return 0;}";
    const domain_dependency = "module units;export D;domain D:i64{private fn hidden<T:copy>(x:T)->T{return x;}fn make<U:copy>(x:U)->U{return D.hidden::<U>(x);}}";
    try acceptChecked(domain_main, domain_dependency);
    try rejectChecked(main, "module units;fn identity<U:copy>(x:U)->U{return x;}", "E_PRIVATE_SYMBOL");
    try rejectChecked(main, "module units;export identity;fn identity<U:integer>(x:U)->U{return x;}", "E_GENERIC_ARGUMENT");
}

fn genericCallsScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main;import units;fn forward<T:integer>(x:T)->T{return units::identity::<T>(x);}fn main()->i64{return 0;}" },
        .{ .path = units_path, .bytes = "module units;export identity;fn identity<U:copy>(x:U)->U{discard helper(1);return x;}fn helper(x:i64)->i64{return x+1;}" },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try @import("project_syntax.zig").build(&index);
    var names: @import("module_names.zig").Names = .{ .index = &index, .src = merged.src };
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = project.arena.allocator() };
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
        .{ .path = "main.my", .bytes = "module main;import units;fn forward<T:copy>(x:T)->T{return units::identity::<T>(x);}fn main()->i64{return 0;}" },
        .{ .path = units_path, .bytes = "module units;export identity;fn identity<U:integer>(x:U)->U{return x;}" },
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

test "generic calls concrete helpers retain imported identity and private domain boundaries" {
    const caller = "module main;import units;fn helper(x:i64)->bool{return x==0;}fn f<T:copy>(x:T)->i64{discard x;return units::helper(1);}fn main()->i64{return 0;}";
    try acceptChecked(caller, "module units;export helper;fn helper(x:i64)->i64{return leaf(x);}fn leaf(x:i64)->i64{return x+1;}");
    try rejectChecked(caller, "module units;fn helper(x:i64)->i64{return x;}", "E_PRIVATE_SYMBOL");
    const domain_caller = "module main;import units;fn f<T:copy>(x:T)->i64{discard x;return units::D.helper(1);}fn main()->i64{return 0;}";
    try acceptChecked(domain_caller, "module units;export D;domain D:i64{fn helper(x:i64)->i64{return D.leaf(x);}private fn leaf(x:i64)->i64{return x+1;}}");
    try rejectChecked(domain_caller, "module units;export D;domain D:i64{fn helper(x:i64)->i64{return E.leaf(x);}}domain E:i64{private fn leaf(x:i64)->i64{return x;}}", "E_PRIVATE_FUNCTION");
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
    try t.expectEqual(@as(i64, 0), (try @import("vm.zig").runWithOptions(t.allocator, compilation.code.?, .{})).value);
}

fn genericExecutionScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main;import units;fn id<T:integer>(x:T)->T{return x;}" ++
            "fn main()->i64{let mut x=0;borrow mut x as r{discard units::set::<i64>(r,2);}return units::run()+id::<i64>(x);}" },
        .{ .path = units_path, .bytes = "module units;export run;export id;export set;" ++
            "fn set<T:copy>(x:&mut T,y:T)->T{write_ref(x,y);return read_ref(x);}fn id<T:copy>(x:T)->T{return x;}fn run()->i64{if id::<bool>(true){return id::<i64>(5);}return 0;}" },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 7), (try @import("vm.zig").runWithOptions(allocator, compilation.code.?, .{})).value);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    try t.expectEqual(@as(usize, 1), roots.len);
    const schema = try @import("schema.zig").render(allocator, &compilation);
    defer allocator.free(schema);
    try t.expect(std.mem.indexOfScalar(u8, schema, '$') == null);
    const generated = try compilation.emitC(allocator);
    defer allocator.free(generated);
    try t.expect(generated.len > 0);
}
test "generic execution retains module identities and ordinary public schema roots" {
    try genericExecutionScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericExecutionScenario, .{});
}

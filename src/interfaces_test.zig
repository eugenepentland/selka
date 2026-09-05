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
const entry = "module main; import units; export Sample; export echo; struct Sample { distance: units::Distance } fn echo(x: [2]units :: Distance) -> [2]units::Distance { return x; } fn main() -> i64 { let x = units::Distance.make(2); return 0; }";
fn scenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = "units.my", .bytes = units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].declaration;
    const distance = try index.resolve(0, "units", "Distance", .type, null, span);
    try t.expectEqual(@as(usize, 1), distance.module);
    _ = try index.resolve(0, "units", "Distance.make", .function, null, span);
    _ = try index.resolve(1, null, "Distance.raw", .function, "Distance", span);
    _ = try index.resolve(1, null, "hidden", .function, null, span);
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
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = body }, .{ .path = "units.my", .bytes = units } } };
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
        var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = "units.my", .bytes = units } } };
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.build(&project);
        try t.expectError(error.SourceError, index.resolve(case.from, case.alias, case.name, case.kind, null, project.modules.items[case.from].declaration));
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
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = text }, .{ .path = "units.my", .bytes = "module units; export Choice; export helper; enum Choice { a } fn helper() -> i64 { return 1; }" } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const index = try interfaces.build(&project);
    const src = project.modules.items[0].src;
    var calls: usize = 0;
    var variants: usize = 0;
    var matches: usize = 0;
    for (index.units[0].syntax.nodes.items) |node| switch (node.data) {
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
    for (index.units[0].syntax.statements.items) |statement| if (statement.data == .match) {
        try t.expectEqualStrings("units::Choice", src.text(statement.data.match.arms[0].ty));
        matches += 1;
    };
    try t.expectEqual(@as(usize, 1), calls);
    try t.expectEqual(@as(usize, 1), variants);
    try t.expectEqual(@as(usize, 1), matches);
}

fn mergedScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = entry }, .{ .path = "units.my", .bytes = units } } };
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
    try t.expectEqualStrings("units::Distance", merged.src.text(merged.syntax.records[0].fields[0].ty));
    const original_span = index.units[1].syntax.functions[0].name;
    try t.expectEqualStrings("raw", project.modules.items[1].src.text(original_span));
    try t.expect(original_span.start < merged.syntax.functions[2].name.start);
}
test "module AST relocation retains source spelling namespace ownership and node references under allocation failure" {
    try mergedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), mergedScenario, .{});
}

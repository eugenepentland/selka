//! Finite symbolic storage graphs distinguish nested and phantom arguments from recursive values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const templates = @import("nominal_templates.zig");
const layouts = @import("nominal_layouts.zig");
const fixture = "struct Empty<T:copy>{}struct Box<T:copy>{value:T}" ++
    "struct Pair<A:copy,B:copy>{first:A,second:B}struct Other<A:copy,B:copy>{first:A,second:B}" ++
    "struct Model<T:copy>{a:Pair<i64,bool>,b:Pair<i64,bool>,c:Pair<bool,i64>,d:Other<i64,bool>,nested:Box<Box<T>>}" ++
    "struct Grow<T:copy>{marker:Empty<Grow<[1]T>>}" ++
    "struct Left<T:copy>{box:Box<T>}struct Right<T:copy>{box:Box<T>}" ++
    "enum Key<T:copy>{a,b}struct Table{data:[Key<i64>]Box<i64>}";
fn root(graph: layouts.Graph, index: templates.Index, name: []const u8) !layouts.Node {
    const id = index.names.get(name);
    try t.expect(id != null);
    // Declaration roots precede any types discovered from field expansion.
    for (graph.nodes.items) |node| if (node.key.base == .named and node.key.base.named == id.?) return node;
    return error.TestUnexpectedResult;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "layouts.my", fixture);
    defer compilation.deinit();
    try compilation.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try templates.collect(compilation.arena.allocator(), compilation.src, compilation.syntax.?, &sink, null);
    var graph = try layouts.collect(allocator, &index, &sink);
    defer graph.deinit();
    const model = try root(graph, index, "Model");
    try t.expectEqual(model.edges[0].target, model.edges[1].target);
    try t.expect(model.edges[0].target != model.edges[2].target);
    try t.expect(model.edges[0].target != model.edges[3].target);
    const nested = graph.nodes.items[@backingInt(model.edges[4].target)];
    const inner = graph.nodes.items[@backingInt(nested.edges[0].target)];
    try t.expectEqual(nested.key.base.named, inner.key.base.named);
    try t.expect(nested.key.arguments[0] != inner.key.arguments[0]);
    const left = try root(graph, index, "Left");
    const right = try root(graph, index, "Right");
    try t.expect(left.edges[0].target != right.edges[0].target);
    const grow = try root(graph, index, "Grow");
    try t.expectEqual(@as(usize, 0), graph.nodes.items[@backingInt(grow.edges[0].target)].edges.len);
    const table = try root(graph, index, "Table");
    try t.expectEqual(@as(usize, 2), graph.nodes.items[@backingInt(table.edges[0].target)].key.base.array.length);
}
// spec: NOMINAL-LAYOUT-1
test "nominal layout collect preserves identity finite nesting and phantom arguments across allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn finite(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "finite.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try templates.collect(compilation.arena.allocator(), compilation.src, compilation.syntax.?, &sink, null);
    var graph = try layouts.collect(t.allocator, &index, &sink);
    defer graph.deinit();
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
fn reject(text: []const u8, code: []const u8, detail: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "recursive.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.emit());
    const problem = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, problem.code);
    try t.expect(std.mem.indexOf(u8, problem.message, detail) != null);
    try t.expect(compilation.program == null and compilation.code == null);
}
test "nominal layout expansion bounds argument growth without host stack recursion" {
    try reject("struct Grow<T:copy>{next:Grow<[1]T>}", "E_GENERIC_LIMIT", "4096 type instances");
    try reject("struct Box<T:copy>{value:T}struct Grow<T:copy>{next:Grow<Box<T>>}", "E_GENERIC_LIMIT", "4096 type instances");
}
fn identitySource(allocator: std.mem.Allocator, count: usize, wrap: bool) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("struct Tag<T:copy>{}struct Values<T:copy>{");
    for (0..count) |i| {
        try text.writer.print("{s}f{d}:", .{ if (i == 0) "" else ",", i });
        if (wrap) try text.writer.writeAll("Tag<");
        try text.writer.print("[{d}]T", .{i + 1});
        if (wrap) try text.writer.writeByte('>');
    }
    try text.writer.writeAll("}");
    return text.toOwnedSlice();
}
test "nominal layout expansion bounds distinct array identities" {
    const accepted = try identitySource(t.allocator, 4096, false);
    defer t.allocator.free(accepted);
    try finite(accepted);
    const excessive = try identitySource(t.allocator, 4097, false);
    defer t.allocator.free(excessive);
    try reject(excessive, "E_GENERIC_LIMIT", "4096 array shapes");
    // Tag and Values contribute two symbolic roots before the field applications.
    const nominal = try identitySource(t.allocator, 4094, true);
    defer t.allocator.free(nominal);
    try finite(nominal);
    const nominal_excess = try identitySource(t.allocator, 4095, true);
    defer t.allocator.free(nominal_excess);
    try reject(nominal_excess, "E_GENERIC_LIMIT", "4096 type instances");
}
fn workSource(allocator: std.mem.Allocator) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("struct Big<T:copy>{");
    for (0..512) |i| try text.writer.print("{s}f{d}:T", .{ if (i == 0) "" else ",", i });
    try text.writer.writeAll("}struct Uses<U:copy>{");
    for (0..256) |i| try text.writer.print("{s}f{d}:Big<[{d}]U>", .{ if (i == 0) "" else ",", i, i + 1 });
    try text.writer.writeAll("}");
    return text.toOwnedSlice();
}
test "nominal layout expansion bounds repeated field work independently of identity growth" {
    const text = try workSource(t.allocator);
    defer t.allocator.free(text);
    try reject(text, "E_GENERIC_LIMIT", "100000 checking operations");
}
fn longSource(allocator: std.mem.Allocator) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("struct Marker<T:copy>{}");
    for (0..1200) |i| try text.writer.print("struct Link{d}{{next:Link{d}}}", .{ i, i + 1 });
    try text.writer.writeAll("struct Link1200{value:i64}");
    return text.toOwnedSlice();
}
test "nominal layout checking handles long finite declaration chains iteratively" {
    const text = try longSource(t.allocator);
    defer t.allocator.free(text);
    try finite(text);
}
fn cycleScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "cycle.my", "struct Box<T:copy>{value:T}struct Loop<U:copy>{box:Box<Loop<U>>}");
    defer compilation.deinit();
    try compilation.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = allocator };
    defer sink.items.deinit(allocator);
    const index = try templates.collect(compilation.arena.allocator(), compilation.src, compilation.syntax.?, &sink, null);
    var graph = layouts.collect(allocator, &index, &sink) catch |err| {
        if (err != error.SourceError) return err;
        const problem = sink.items.items[0];
        try t.expectEqualStrings("E_RECURSIVE_RECORD", problem.code);
        try t.expectEqualStrings("value", compilation.src.text(problem.span));
        try t.expectEqualStrings("Loop", compilation.src.text(problem.related.?.span));
        return;
    };
    defer graph.deinit();
    return error.TestUnexpectedResult;
}
test "nominal layout cycle diagnostics preserve closing fields and clean up allocation failures" {
    try cycleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), cycleScenario, .{});
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import model as m;fn main()->i64{return 0;}");
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model;struct Box<T:copy>{value:T}struct Loop<U:copy>{box:Box<Loop<U>>}");
        return error.NotFound;
    }
};
test "nominal layout cycles in unused private imported templates retain original locations" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const problem = compilation.diagnostics.items.items[0];
    try t.expectEqualStrings("E_RECURSIVE_RECORD", problem.code);
    const original = try compilation.src.originalSpan(problem.span);
    const related = try compilation.src.originalSpan(problem.related.?.span);
    try t.expectEqualStrings("model", project.modules.items[original.input].name);
    try t.expectEqualStrings("model", project.modules.items[related.input].name);
    try t.expectEqualStrings("value", compilation.src.text(problem.span));
    try t.expectEqualStrings("Loop", compilation.src.text(problem.related.?.span));
}

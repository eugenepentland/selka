//! Semantic template metadata checks names and requirements before executable specialization.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const templates = @import("nominal_templates.zig");
const fixture = "struct Pair<T:copy,U:copy>{first:T,second:U}" ++
    "union Slot<T:copy>{none,some:T}struct Row<T:equality>{pair:Pair<T,bool>,slots:[2]Slot<T>}" ++
    "resource File:filesystem;struct Owned<T:copy>{file:File,value:T}" ++
    "result Answer<T:copy>{ok:T,err:i64}struct Pending{answer:Answer<i64>}" ++
    "enum Tag<T:copy>{left,right}domain Id:i64{}" ++
    "struct Empty{zero:[0]File}fn main()->i64{return 0;}";
fn collect(compilation: *language.Compilation, sink: *language.diagnostic.Sink) !templates.Index {
    try compilation.parse();
    return templates.collect(compilation.arena.allocator(), compilation.src, compilation.syntax.?, sink, null);
}
fn named(index: templates.Index, name: []const u8) !templates.Declaration {
    const id = index.names.get(name);
    try t.expect(id != null);
    return index.declarations.items[id.?];
}
fn metadataScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "templates.my", fixture);
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try collect(&compilation, &sink);
    const row = try named(index, "Row");
    const pair = row.fields[0].ty.?.application;
    try t.expectEqual(index.names.get("Pair").?, pair.declaration);
    try t.expectEqual(@as(usize, 0), pair.arguments[0].parameter);
    try t.expectEqual(@import("typed.zig").Type.bool, pair.arguments[1].builtin);
    const slots = row.fields[1].ty.?.array;
    try t.expectEqual(@as(?usize, 2), slots.length);
    try t.expectEqual(index.names.get("Slot").?, slots.element.application.declaration);
    try t.expectEqual(@as(usize, 0), slots.element.application.arguments[0].parameter);
    try t.expect(row.guarantees.contains(.copy));
    try t.expect(!row.guarantees.contains(.equality));
    for ([_][]const u8{ "File", "Owned", "Answer", "Pending" }) |name| try t.expect(!(try named(index, name)).guarantees.contains(.copy));
    for ([_][]const u8{ "Tag", "Id" }) |name| {
        const declaration = try named(index, name);
        try t.expect(declaration.guarantees.contains(.equality));
        try t.expect(!declaration.guarantees.contains(.integer));
    }
    try t.expect((try named(index, "Empty")).guarantees.contains(.copy));
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "invalid.my", "struct Box<T:copy>{value:T}resource File:filesystem;struct Bad{value:Box<File>}");
    defer compilation.deinit();
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        try t.expectEqualStrings("E_GENERIC_REQUIREMENT", compilation.diagnostics.items[0].code);
        try t.expect(compilation.program == null and compilation.code == null);
        return;
    };
    return error.TestUnexpectedResult;
}
fn separateSinkScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "allocators.my", "struct Box<T:copy>{value:T}");
    defer compilation.deinit();
    try compilation.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = allocator };
    defer sink.items.deinit(allocator);
    const catalog = try @import("records.zig").collectWithNames(compilation.arena.allocator(), compilation.src, compilation.syntax.?, &sink, null);
    try t.expectEqual(@as(usize, 0), catalog.records.len);
    try t.expect(catalog.templates.names.contains("Box"));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: NOMINAL-TEMPLATE-CHECK-1
test "nominal template collect and expression preserve identity and guarantees across allocation failures" {
    try metadataScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), metadataScenario, .{});
    try rejectionScenario(t.allocator);
    try t.checkAllAllocationFailures(stable.allocator(), rejectionScenario, .{});
    try separateSinkScenario(t.allocator);
    try t.checkAllAllocationFailures(stable.allocator(), separateSinkScenario, .{});
}
fn reject(text: []const u8, code: []const u8, token: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-template.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, diagnostic.code);
    try t.expectEqualStrings(token, compilation.src.text(diagnostic.span));
    try t.expect(compilation.program == null and compilation.code == null);
}
test "unused nominal template fields reject unknown names duplicate members and invalid result schemas" {
    try reject("struct Box<T:copy>{value:Missing}", "E_UNKNOWN_TYPE", "Missing");
    try reject("struct Box<T:copy>{value:T,value:i64}", "E_DUPLICATE_FIELD", "value");
    try reject("union Slot<T:copy>{some:T,some:i64}", "E_DUPLICATE_VARIANT", "some");
    try reject("union Slot<T:copy>{}", "E_EMPTY_VARIANTS", "Slot");
    try reject("result Answer<T:copy>{yes:T,no:i64}", "E_RESULT_SCHEMA", "Answer");
    try reject("result Answer<T:copy>{ok:T,err}", "E_RESULT_SCHEMA", "err");
    try reject("struct Box<T:copy>{value:T}domain Box:i64{}", "E_DUPLICATE_TYPE", "Box");
}
test "nominal template applications check arity and constructor kinds inside unused declarations" {
    try reject("struct Pair<T:copy,U:copy>{a:T,b:U}struct Bad<V:copy>{x:Pair<V>}", "E_GENERIC_ARITY", "Pair<V>");
    try reject("struct Box<T:copy>{value:T}struct Bad{value:Box}", "E_GENERIC_ARITY", "Box");
    try reject("struct Plain{}struct Bad<T:copy>{value:Plain<T>}", "E_GENERIC_ARITY", "Plain<T>");
    try reject("struct Bad<T:copy>{value:T<i64>}", "E_TYPE_APPLICATION", "T");
    try reject("struct Bad<T:copy>{value:[2]Missing<T>}", "E_UNKNOWN_TYPE", "Missing");
}
test "nominal template requirements reject insufficient symbolic promises and concrete operations" {
    const prefix = "struct Key<T:equality>{value:T}struct Number<T:integer>{value:T}";
    try reject(prefix ++ "struct Bad<T:copy>{value:Key<T>}", "E_GENERIC_REQUIREMENT", "T");
    try reject(prefix ++ "struct Bad<T:equality>{value:Number<T>}", "E_GENERIC_REQUIREMENT", "T");
    try reject(prefix ++ "struct Bad<T:copy>{value:Number<bool>}", "E_GENERIC_REQUIREMENT", "bool");
    try reject(prefix ++ "domain Id:i64{}struct Bad<T:copy>{value:Number<Id>}", "E_GENERIC_REQUIREMENT", "Id");
    try reject(prefix ++ "struct Bad<T:copy>{value:Key<[0]T>}", "E_GENERIC_REQUIREMENT", "[0]T");
    try reject(prefix ++ "struct Bad<T:copy>{value:Key<Key<i64>>}", "E_GENERIC_REQUIREMENT", "Key<i64>");
    var repaired = try language.Compilation.init(t.allocator, "repaired.my", prefix ++ "struct Good<T:integer>{key:Key<T>,number:Number<T>,flag:Key<bool>}");
    defer repaired.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = repaired.arena.allocator() };
    const index = try collect(&repaired, &sink);
    try t.expect((try named(index, "Good")).guarantees.contains(.copy));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
test "nominal template requirements preserve transitive owner and pending result obligations" {
    const prefix = "struct Box<T:copy>{value:T}resource File:filesystem;";
    try reject(prefix ++ "struct Bad{value:Box<File>}", "E_GENERIC_REQUIREMENT", "File");
    try reject(prefix ++ "struct Bad{value:Box<Outer>}struct Outer{inner:Inner}struct Inner{file:File}", "E_GENERIC_REQUIREMENT", "Outer");
    try reject(prefix ++ "result Answer{ok:i64,err:i64}struct Pending{answer:Answer}struct Bad{value:Box<[1]Pending>}", "E_GENERIC_REQUIREMENT", "[1]Pending");
    try reject(prefix ++ "struct Owner<T:copy>{file:File,value:T}struct Bad{value:Box<Owner<i64>>}", "E_GENERIC_REQUIREMENT", "Owner<i64>");
    try reject(prefix ++ "struct Bad{value:Box<Box<File>>}", "E_GENERIC_REQUIREMENT", "File");
}
test "nominal template arrays validate lengths keys and symbolic enum table boundaries" {
    try reject("struct Box<T:copy>{value:[2u8]T}", "E_ARRAY_LENGTH", "2u8");
    try reject("enum Key{one,two}struct Box<T:copy>{value:[Key]T}", "E_GENERIC_ARRAY_KEY", "[Key]T");
    try reject("struct Key{}struct Box<T:copy>{value:[Key]i64}", "E_TABLE_KEY", "Key");
    try reject("enum Key<T:integer>{one,two}struct Box<T:copy>{value:[Key<bool>]i64}", "E_GENERIC_REQUIREMENT", "bool");
    var compilation = try language.Compilation.init(t.allocator, "valid.my", "struct Box<T:copy>{value:T}resource File:filesystem;enum Key{one,two}enum Tag<T:copy>{first,second}" ++
        "struct Valid<U:integer>{empty:Box<[0]File>,table:[Key]Box<i64>,tags:[Tag<i64>]bool,pair:Box<[2]U>}");
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try collect(&compilation, &sink);
    try t.expect((try named(index, "Valid")).guarantees.contains(.copy));
}
test "nominal guarantee propagation handles long reverse ordered declaration chains" {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    try text.writer.writeAll("struct Box<T:copy>{value:T}resource File:filesystem;");
    for (0..1200) |i| try text.writer.print("struct Link{d}{{next:Link{d}}}", .{ i, i + 1 });
    try text.writer.writeAll("struct Link1200{file:File}struct Bad{value:Box<Link0>}");
    try reject(text.written(), "E_GENERIC_REQUIREMENT", "Link0");
}

test "nominal expression checking enforces the work budget without issuing executable type IDs" {
    var compilation = try language.Compilation.init(t.allocator, "budget.my", "struct Box<T:copy>{value:T}");
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    var index = try collect(&compilation, &sink);
    const declaration = try named(index, "Box");
    const span = compilation.syntax.?.types.records[0].fields[0].ty;
    // Collection already visited the one field. The remaining visits reach the exact limit.
    for (0..99999) |_| try t.expectEqual(@as(usize, 0), (try index.expression(span, declaration.parameters)).parameter);
    try t.expectError(error.SourceError, index.expression(span, declaration.parameters));
    try t.expectEqualStrings("E_GENERIC_LIMIT", sink.items.items[0].code);
}
const Modules = struct {
    strict: bool = false,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Modules = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "module main;import left as l;import right as r;" ++
            "struct Holder<T:copy>{a:l::Box<T>,b:r::Box<T>,c:l::Box<T>}fn main()->i64{return 0;}");
        if (std.mem.eql(u8, path, "left.my")) return allocator.dupe(u8, if (self.strict) "module left;export Box;struct Box<U:equality>{value:U}" else "module left;export Box;struct Box<U:copy>{value:U}");
        if (std.mem.eql(u8, path, "right.my")) return allocator.dupe(u8, "module right;export Box;struct Box<U:copy>{value:U}");
        return error.NotFound;
    }
};
test "nominal metadata preserves distinct imported template identities and related requirement sites" {
    for ([_]bool{ false, true }) |strict| {
        var files: Modules = .{ .strict = strict };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &files, .read = Modules.read }, "main", .{});
        var interfaces = try language.interfaces.build(&project);
        const merged = try @import("project_syntax.zig").build(&interfaces);
        var names: @import("module_names.zig").Names = .{ .index = &interfaces, .src = merged.src };
        var sink: language.diagnostic.Sink = .{ .allocator = project.arena.allocator() };
        const result = templates.collect(project.arena.allocator(), merged.src, merged.syntax, &sink, &names);
        if (strict) {
            try t.expectError(error.SourceError, result);
            const problem = sink.items.items[0];
            try t.expectEqualStrings("E_GENERIC_REQUIREMENT", problem.code);
            const primary = try merged.src.originalSpan(problem.span);
            const related = try merged.src.originalSpan(problem.related.?.span);
            try t.expectEqualStrings("main", project.modules.items[primary.input].name);
            try t.expectEqualStrings("left", project.modules.items[related.input].name);
        } else {
            const index = try result;
            const holder = try named(index, "main::Holder");
            const left = holder.fields[0].ty.?.application.declaration;
            const right = holder.fields[1].ty.?.application.declaration;
            try t.expect(left != right);
            try t.expectEqual(left, holder.fields[2].ty.?.application.declaration);
            try t.expectEqual(index.names.get("left::Box").?, left);
            try t.expectEqual(index.names.get("right::Box").?, right);
        }
    }
}

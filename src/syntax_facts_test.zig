//! The facts a merged program records agree with the scans they replace, and the passes that used to scan every node read only the module
//! they ask about.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const records = @import("records.zig");
const diagnostic = @import("diagnostic.zig");
const literals_fact = @import("ast_literals.zig");
const dictionary_views = @import("dictionary_views.zig");
const Names = @import("module_names.zig").Names;
const File = language.embedded_project.File;

const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

const entries = [_]File{
    .{ .path = "main.selka", .bytes = "import text\nimport blank\n\n\nfunc main() -> int:\n    const raw = b\"ab\"\n    const name = \"main\"\n    return text.size() + len(raw) + len(name)\n" },
    .{ .path = "text.selka", .bytes = "public func size() -> int:\n    const word = \"hello\"\n    const other = \"world\"\n    return len(word) + len(other)\n" },
    .{ .path = "blank.selka", .bytes = "# nothing but a comment\n" },
};

/// A merged project of three modules, the last of which has no syntax, kept alive for a test.
const Merged = struct {
    provider: Files,
    project: language.project.Project,
    index: language.interfaces.Index,
    compilation: language.project_compile.Compilation,

    fn open(self: *Merged) !void {
        self.provider = .{ .entries = &entries };
        self.project = language.project.Project.init(t.allocator);
        errdefer self.project.deinit();
        try self.project.load(.{ .context = &self.provider, .read = Files.read }, "main", .{});
        self.index = try language.interfaces.build(&self.project);
        self.compilation = try language.project_compile.Compilation.init(&self.index);
    }

    fn close(self: *Merged) void {
        self.project.deinit();
    }
};

/// The extents tile the node and statement tables in module order, a module with no syntax holding an empty run.
fn expectTiling(program: ast.Program) !void {
    var nodes: usize = 0;
    var statements: usize = 0;
    for (program.facts.extents) |extent| {
        try t.expectEqual(nodes, extent.node_start);
        try t.expectEqual(statements, extent.statement_start);
        nodes = extent.node_end;
        statements = extent.statement_end;
    }
    try t.expectEqual(program.nodes.items.len, nodes);
    try t.expectEqual(program.statements.items.len, statements);
}

/// Every node is found in the module whose source holds its span.
fn expectEveryNodeFound(program: ast.Program) !void {
    const extents = program.facts.extents;
    for (program.nodes.items, 0..) |node, id| {
        const position = ast.extentIndexOfNode(program, @fromBackingInt(id)).?;
        try t.expect(extents[position].node_start <= id and id < extents[position].node_end);
        try t.expectEqual(position, ast.extentIndexAt(program, node.span.start).?);
    }
}

fn hasEmptyModule(extents: []const ast.Extent) bool {
    for (extents) |extent| if (extent.node_start == extent.node_end) return true;
    return false;
}

test "a merged program records the extents of its modules and finds the module of a node or an offset" {
    var merged: Merged = undefined;
    try merged.open();
    defer merged.close();
    const program = merged.compilation.syntax;
    const extents = program.facts.extents;
    try t.expectEqual(merged.project.modules.items.len, extents.len);
    try expectTiling(program);
    try t.expect(hasEmptyModule(extents));
    try expectEveryNodeFound(program);
    try t.expect(ast.nodesAt(program, extents[1].source_start).len == extents[1].node_end - extents[1].node_start);
    try t.expect(ast.extentIndexOfNode(program, @fromBackingInt(program.nodes.items.len)) == null);
}

test "the literals a merge records are the literals a scan of the merged nodes finds" {
    var merged: Merged = undefined;
    try merged.open();
    defer merged.close();
    const program = merged.compilation.syntax;
    const scanned = try literals_fact.scan(t.allocator, merged.compilation.src, program);
    defer t.allocator.free(scanned);
    try t.expect(scanned.len >= 3);
    try t.expect(literals_fact.same(scanned, program.facts.literals.?));
    // A managed bytes literal needs no array schema; one that is not spelled `b"..."` has the shape of its length.
    const spelled = "x\"ab\"";
    var probe_arena = std.heap.ArenaAllocator.init(t.allocator);
    defer probe_arena.deinit();
    const src = try source.Source.init(probe_arena.allocator(), "probe.selka", spelled);
    const text_node: ast.Node = .{ .span = .{ .start = 0, .end = spelled.len }, .data = .{ .bytes = "ab" } };
    try t.expectEqual(@as(?usize, 2), literals_fact.of(src, text_node).?.bytes);
    const managed = try source.Source.init(probe_arena.allocator(), "probe.selka", "b\"ab\"");
    try t.expect(literals_fact.of(managed, text_node) == null);
}

test "the catalog registers the same types from the recorded literals as from a scan" {
    var merged: Merged = undefined;
    try merged.open();
    defer merged.close();
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var names: Names = .{ .index = &merged.index, .src = merged.compilation.src };
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const program = merged.compilation.syntax;
    const recorded = try records.collectWithNames(arena, merged.compilation.src, program, &sink, &names);
    var unrecorded_program = program;
    unrecorded_program.facts.literals = null;
    const scanned = try records.collectWithNames(arena, merged.compilation.src, unrecorded_program, &sink, &names);
    try expectSameCatalogs(scanned, recorded);
}

/// Two catalogs hold the same records in the same order and resolve the same spans to the same types.
fn expectSameCatalogs(scanned: records.Catalog, recorded: records.Catalog) !void {
    try t.expectEqual(scanned.records.len, recorded.records.len);
    for (scanned.records, recorded.records) |left, right| try t.expectEqualStrings(left.name, right.name);
    try t.expect(recorded.arrays.resolved.count() >= 3);
    try t.expectEqual(scanned.arrays.resolved.count(), recorded.arrays.resolved.count());
    var iterator = scanned.arrays.resolved.iterator();
    while (iterator.next()) |entry| try t.expectEqual(entry.value_ptr.*, recorded.arrays.resolved.get(entry.key_ptr.*).?);
}

test "the consumer index of a module is built when one of its expressions is asked about, and only then" {
    var merged: Merged = undefined;
    try merged.open();
    defer merged.close();
    const program = merged.compilation.syntax;
    const consumers = try dictionary_views.Consumers.init(t.allocator, merged.compilation.src, program);
    defer consumers.deinit(t.allocator);
    try t.expectEqual(@as(usize, 0), consumers.built());
    const text = program.facts.extents[1];
    _ = try consumers.use(@fromBackingInt(text.node_start));
    try t.expectEqual(@as(usize, 1), consumers.built());
    _ = try consumers.use(@fromBackingInt(text.node_end - 1));
    try t.expectEqual(@as(usize, 1), consumers.built());
    _ = try consumers.use(@fromBackingInt(program.facts.extents[0].node_start));
    try t.expectEqual(@as(usize, 2), consumers.built());
}

//! Combine already-parsed module tables while preserving declaration ownership.
//! This is not name resolution: consumers must retain the module context below.
/// Failures returned by build; callers must handle these boundary errors.
pub const BuildError = error{
    EmptySourceMap,
    IncompleteProject,
    InvalidNodeId,
    InvalidSourceIndex,
    InvalidSourceSpan,
    InvalidStatementId,
    NestedSourceMap,
    OutOfMemory,
    Overflow,
};

const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
/// Half-open expression and statement ranges originating in one merged module.
pub const Range = struct { node_start: usize, node_end: usize, statement_start: usize, statement_end: usize };
/// Merged project syntax, mapped source, and entry identity backed by the project arena.
pub const Merged = struct {
    src: source.Source,
    syntax: ast.Program,
    modules: []const Range,
    function_modules: []const usize,
};
const Remap = @import("ast_copy.zig").Mapper;
/// All output storage belongs to index.project.arena; the original AST is unchanged.
pub fn build(index: *interfaces.Index) BuildError!Merged {
    const project = index.project;
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    const inputs = try allocator.alloc(source.Source, project.modules.items.len);
    for (inputs, project.modules.items) |*input, module| input.* = module.src;
    const src = try source.Source.initMapped(allocator, inputs);
    const ranges = try allocator.alloc(Range, inputs.len);
    var merged: ast.Program = .{ .nodes = .empty, .statements = .empty, .functions = &.{} };
    var function_modules: std.ArrayList(usize) = .empty;
    for (index.units, 0..) |unit, module| {
        const map: Remap = .{
            .src = src,
            .module = module,
            .nodes = merged.nodes.items.len,
            .statements = merged.statements.items.len,
            .node_count = unit.syntax.nodes.items.len,
            .statement_count = unit.syntax.statements.items.len,
        };
        for (unit.syntax.nodes.items) |node| try merged.nodes.append(allocator, try map.value(allocator, ast.Node, node));
        for (unit.syntax.statements.items) |statement| try merged.statements.append(allocator, try map.value(allocator, ast.Statement, statement));
        ranges[module] = .{ .node_start = map.nodes, .node_end = merged.nodes.items.len, .statement_start = map.statements, .statement_end = merged.statements.items.len };
        for (unit.syntax.functions) |_| try function_modules.append(allocator, module);
    }
    // Append each declaration category once, avoiding quadratic slice copying.
    inline for (.{ "functions", "records", "domains", "variants", "arrays", "applications", "buffers", "resources", "pools" }) |field| {
        const is_function = comptime std.mem.eql(u8, field, "functions");
        const is_expression = comptime std.mem.eql(u8, field, "arrays") or std.mem.eql(u8, field, "applications");
        const Collection = if (is_function) ast.Program else if (is_expression) ast.TypeExpressions else ast.TypeDeclarations;
        const Slice = @FieldType(Collection, field);
        const Item = @typeInfo(Slice).pointer.child;
        var declarations: std.ArrayList(Item) = .empty;
        for (index.units, ranges, 0..) |unit, range, module| {
            const map: Remap = .{
                .src = src,
                .module = module,
                .nodes = range.node_start,
                .statements = range.statement_start,
                .node_count = unit.syntax.nodes.items.len,
                .statement_count = unit.syntax.statements.items.len,
            };
            for (@field(if (is_function) unit.syntax else if (is_expression) unit.syntax.types.expressions else unit.syntax.types, field)) |item| try declarations.append(allocator, try map.value(allocator, Item, item));
        }
        if (is_function) {
            merged.functions = try declarations.toOwnedSlice(allocator);
        } else {
            @field(if (is_expression) merged.types.expressions else merged.types, field) = try declarations.toOwnedSlice(allocator);
        }
    }
    return .{ .src = src, .syntax = merged, .modules = ranges, .function_modules = try function_modules.toOwnedSlice(allocator) };
}

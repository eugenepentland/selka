//! Combine already-parsed module tables while preserving declaration ownership.
//! This is not name resolution: consumers must retain the module context below.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
pub const Range = struct { node_start: usize, node_end: usize, statement_start: usize, statement_end: usize };
pub const Merged = struct {
    src: source.Source,
    syntax: ast.Program,
    modules: []const Range,
    function_modules: []const usize,
};
const Remap = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    module: usize,
    nodes: usize,
    statements: usize,
    node_count: usize,
    statement_count: usize,
    fn value(self: Remap, comptime T: type, input: T) error{ OutOfMemory, InvalidSourceIndex, InvalidSourceSpan, InvalidNodeId, InvalidStatementId }!T {
        if (T == source.Span) return self.src.mappedSpan(self.module, input);
        if (T == ast.NodeId) {
            if (@backingInt(input) >= self.node_count) return error.InvalidNodeId;
            return @fromBackingInt(@backingInt(input) + self.nodes);
        }
        if (T == ast.StatementId) {
            if (@backingInt(input) >= self.statement_count) return error.InvalidStatementId;
            return @fromBackingInt(@backingInt(input) + self.statements);
        }
        return switch (@typeInfo(T)) {
            .@"struct" => result: {
                var output: T = undefined;
                inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| @field(output, name) = try self.value(Field, @field(input, name));
                break :result output;
            },
            .@"union" => result: {
                inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                    if (std.meta.activeTag(input) == @field(std.meta.Tag(T), name)) break :result @unionInit(T, name, try self.value(Field, @field(input, name)));
                }
                unreachable;
            },
            .optional => |optional| if (input) |present| try self.value(optional.child, present) else null,
            .pointer => |pointer| result: {
                if (pointer.size != .slice) @compileError("AST remapping requires owned slices, not pointers");
                const output = try self.allocator.alloc(pointer.child, input.len);
                for (input, output) |item, *out| out.* = try self.value(pointer.child, item);
                break :result output;
            },
            .@"enum", .int, .bool, .void => input,
            else => @compileError("AST field needs an explicit relocation rule: " ++ @typeName(T)),
        };
    }
};
/// All output storage belongs to index.project.arena; the original AST is unchanged.
pub fn build(index: *interfaces.Index) !Merged {
    const project = index.project;
    if (!project.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    const inputs = try allocator.alloc(source.Source, project.modules.items.len);
    for (inputs, project.modules.items) |*input, module| input.* = module.src;
    const src = try source.Source.initMapped(allocator, inputs);
    const ranges = try allocator.alloc(Range, inputs.len);
    var merged: ast.Program = .{ .nodes = .empty, .statements = .empty, .functions = &.{}, .records = &.{} };
    var function_modules: std.ArrayList(usize) = .empty;
    for (index.units, 0..) |unit, module| {
        const map: Remap = .{ .allocator = allocator, .src = src, .module = module, .nodes = merged.nodes.items.len, .statements = merged.statements.items.len, .node_count = unit.syntax.nodes.items.len, .statement_count = unit.syntax.statements.items.len };
        for (unit.syntax.nodes.items) |node| try merged.nodes.append(allocator, try map.value(ast.Node, node));
        for (unit.syntax.statements.items) |statement| try merged.statements.append(allocator, try map.value(ast.Statement, statement));
        ranges[module] = .{ .node_start = map.nodes, .node_end = merged.nodes.items.len, .statement_start = map.statements, .statement_end = merged.statements.items.len };
        for (unit.syntax.functions) |_| try function_modules.append(allocator, module);
    }
    // Append each declaration category once, avoiding quadratic slice copying.
    inline for (.{ "functions", "records", "domains", "variants", "array_types", "buffers", "resources", "pools" }) |field| {
        const Slice = @FieldType(ast.Program, field);
        const Item = @typeInfo(Slice).pointer.child;
        var declarations: std.ArrayList(Item) = .empty;
        for (index.units, ranges, 0..) |unit, range, module| {
            const map: Remap = .{ .allocator = allocator, .src = src, .module = module, .nodes = range.node_start, .statements = range.statement_start, .node_count = unit.syntax.nodes.items.len, .statement_count = unit.syntax.statements.items.len };
            for (@field(unit.syntax, field)) |item| try declarations.append(allocator, try map.value(Item, item));
        }
        @field(merged, field) = try declarations.toOwnedSlice(allocator);
    }
    return .{ .src = src, .syntax = merged, .modules = ranges, .function_modules = try function_modules.toOwnedSlice(allocator) };
}

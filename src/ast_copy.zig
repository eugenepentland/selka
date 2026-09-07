//! Deep-copy syntax storage with optional source and identity relocation.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
/// Copies syntax tables and optionally relocates spans and local table identities.
pub const Mapper = struct {
    src: ?source.Source = null,
    module: usize = 0,
    nodes: usize = 0,
    statements: usize = 0,
    node_count: usize = 0,
    statement_count: usize = 0,
    /// Deep-copy a syntax field; mapped copies validate source and table references.
    pub fn value(self: Mapper, allocator: std.mem.Allocator, comptime T: type, input: T) error{ OutOfMemory, InvalidSourceIndex, InvalidSourceSpan, InvalidNodeId, InvalidStatementId }!T {
        if (T == source.Span) return if (self.src) |src| src.mappedSpan(self.module, input) else input;
        if (T == ast.NodeId) {
            if (self.src == null) return input;
            if (@backingInt(input) >= self.node_count) return error.InvalidNodeId;
            return @fromBackingInt(@backingInt(input) + self.nodes);
        }
        if (T == ast.StatementId) {
            if (self.src == null) return input;
            if (@backingInt(input) >= self.statement_count) return error.InvalidStatementId;
            return @fromBackingInt(@backingInt(input) + self.statements);
        }
        return switch (@typeInfo(T)) {
            .@"struct" => result: {
                var output: T = undefined;
                inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| @field(output, name) = try self.value(allocator, Field, @field(input, name));
                break :result output;
            },
            .@"union" => result: {
                inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                    if (std.meta.activeTag(input) == @field(std.meta.Tag(T), name)) break :result @unionInit(T, name, try self.value(allocator, Field, @field(input, name)));
                }
                unreachable;
            },
            .optional => |optional| if (input) |present| try self.value(allocator, optional.child, present) else null,
            .pointer => |pointer| result: {
                if (pointer.size != .slice) @compileError("AST remapping requires owned slices, not pointers");
                const output = try allocator.alloc(pointer.child, input.len);
                for (input, output) |item, *out| out.* = try self.value(allocator, pointer.child, item);
                break :result output;
            },
            .array => |array| result: {
                var output: T = undefined;
                for (input, &output) |item, *out| out.* = try self.value(allocator, array.child, item);
                break :result output;
            },
            .@"enum", .int, .float, .bool, .void => input,
            else => @compileError("AST field needs an explicit relocation rule: " ++ @typeName(T)),
        };
    }
};
/// Copy a parsed program into a caller-owned arena without retaining original storage.
pub fn clone(allocator: std.mem.Allocator, input: ast.Program) error{ OutOfMemory, InternalError }!ast.Program {
    const map: Mapper = .{};
    return cloneInner(map, allocator, input) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InternalError,
    };
}
fn cloneInner(map: Mapper, allocator: std.mem.Allocator, input: ast.Program) !ast.Program {
    return .{
        .nodes = .fromOwnedSlice(try map.value(allocator, []ast.Node, input.nodes.items)),
        .statements = .fromOwnedSlice(try map.value(allocator, []ast.Statement, input.statements.items)),
        .functions = try map.value(allocator, []const ast.Function, input.functions),
        .types = try map.value(allocator, ast.TypeDeclarations, input.types),
    };
}

//! A deep copy of one statement subtree, appended to the syntax tables under fresh identities.
//!
//! The checker memoizes an expression by its node identity, so one body checked for two arms would reuse the first
//! arm's typed nodes (and the first arm's bindings) for the second. The arms of a `case a(x) | b(x):` list therefore
//! each get a copy of the body. The copies keep the original spans, so a diagnostic points at the one body the
//! source has.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");

/// The syntax tables a copy appends to, and the allocator that owns their storage (a parser grows them with a
/// different allocator from the one its slices use).
pub const Tables = struct { nodes: *std.ArrayList(ast.Node), statements: *std.ArrayList(ast.Statement), growth: std.mem.Allocator };

/// Copy statement `id` and everything below it; the copy shares no node or statement with the original.
pub fn cloneStatement(allocator: std.mem.Allocator, tables: Tables, id: ast.StatementId) std.mem.Allocator.Error!ast.StatementId {
    const cloner: Cloner = .{ .allocator = allocator, .tables = tables };
    return cloner.statement(id);
}

const Cloner = struct {
    allocator: std.mem.Allocator,
    tables: Tables,

    fn statement(self: Cloner, id: ast.StatementId) std.mem.Allocator.Error!ast.StatementId {
        const original = self.tables.statements.items[@backingInt(id)];
        const copy = try self.value(ast.Statement, original);
        try self.tables.statements.append(self.tables.growth, copy);
        return @fromBackingInt(self.tables.statements.items.len - 1);
    }

    fn node(self: Cloner, id: ast.NodeId) std.mem.Allocator.Error!ast.NodeId {
        const original = self.tables.nodes.items[@backingInt(id)];
        const copy = try self.value(ast.Node, original);
        try self.tables.nodes.append(self.tables.growth, copy);
        return @fromBackingInt(self.tables.nodes.items.len - 1);
    }

    fn value(self: Cloner, comptime T: type, input: T) std.mem.Allocator.Error!T {
        if (T == ast.NodeId) return self.node(input);
        if (T == ast.StatementId) return self.statement(input);
        if (T == source.Span) return input;
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
                if (pointer.size != .slice) @compileError("AST copying needs owned slices, not pointers");
                const output = try self.allocator.alloc(pointer.child, input.len);
                for (input, output) |item, *out| out.* = try self.value(pointer.child, item);
                break :result output;
            },
            .array => |array| result: {
                var output: T = undefined;
                for (input, &output) |item, *out| out.* = try self.value(array.child, item);
                break :result output;
            },
            .@"enum", .int, .float, .bool, .void => input,
            else => @compileError("AST field needs an explicit copy rule: " ++ @typeName(T)),
        };
    }
};

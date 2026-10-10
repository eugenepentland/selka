//! Validate source ranges and the mixed expression/statement reference graph.
const std = @import("std");
const ast = @import("ast.zig");
const Span = @import("source.zig").Span;
/// Malformed syntax graphs or allocator exhaustion.
pub const Error = error{ ComponentProtocol, OutOfMemory };

const Validator = struct {
    program: ast.Program,
    source_len: usize,
    colors: []u8,
    visits: usize = 4194304,

    fn vertex(self: *Validator, id: usize, depth: usize) Error!void {
        if (id >= self.colors.len or depth > 256) return error.ComponentProtocol;
        if (self.colors[id] == 1) return error.ComponentProtocol;
        if (self.colors[id] == 2) return;
        self.colors[id] = 1;
        if (id < self.program.nodes.items.len) {
            try self.walk(ast.Node, self.program.nodes.items[id], depth + 1);
        } else {
            try self.walk(ast.Statement, self.program.statements.items[id - self.program.nodes.items.len], depth + 1);
        }
        self.colors[id] = 2;
    }
    fn walk(self: *Validator, comptime T: type, value: T, depth: usize) Error!void {
        if (self.visits == 0 or depth > 256) return error.ComponentProtocol;
        self.visits -= 1;
        if (T == Span) {
            if (value.start > value.end or value.end > self.source_len) return error.ComponentProtocol;
            return;
        }
        if (T == ast.NodeId) {
            const id = @backingInt(value);
            if (id >= self.program.nodes.items.len) return error.ComponentProtocol;
            return self.vertex(id, depth + 1);
        }
        if (T == ast.StatementId) {
            const id = @backingInt(value);
            if (id >= self.program.statements.items.len) return error.ComponentProtocol;
            return self.vertex(self.program.nodes.items.len + id, depth + 1);
        }
        switch (@typeInfo(T)) {
            .void, .int, .bool, .@"enum" => {},
            .optional => |info| if (value) |present| try self.walk(info.child, present, depth + 1),
            .pointer => |info| {
                if (info.child != u8) for (value) |item| try self.walk(info.child, item, depth + 1);
            },
            .array => |info| for (value) |item| try self.walk(info.child, item, depth + 1),
            .@"struct" => |info| inline for (info.field_names, info.field_types) |field_name, Field| try self.walk(Field, @field(value, field_name), depth + 1),
            .@"union" => |info| inline for (info.field_names, info.field_types) |field_name, Field| {
                if (std.mem.eql(u8, @tagName(value), field_name)) try self.walk(Field, @field(value, field_name), depth + 1);
            },
            else => @compileError("unexpected syntax shape " ++ @typeName(T)),
        }
    }
};

/// Reject invalid AST ranges and references, including mixed graph cycles.
pub fn validate(allocator: std.mem.Allocator, program: ast.Program, source_len: usize) Error!void {
    @setEvalBranchQuota(200000);
    if (program.nodes.items.len > 262144 or program.statements.items.len > 262144) return error.ComponentProtocol;
    const colors = try allocator.alloc(u8, program.nodes.items.len + program.statements.items.len);
    defer allocator.free(colors);
    @memset(colors, 0);
    var validator: Validator = .{ .program = program, .source_len = source_len, .colors = colors };
    for (0..colors.len) |id| try validator.vertex(id, 0);
    try validator.walk(ast.TypeDeclarations, program.types, 0);
    try validator.walk(@TypeOf(program.functions), program.functions, 0);
    try validator.walk(@TypeOf(program.lambdas), program.lambdas, 0);
    try validator.walk(@TypeOf(program.attributes), program.attributes, 0);
    try validator.walk(@TypeOf(program.docstrings), program.docstrings, 0);
}

/// Validate source ranges in a plain value tree without expression references.
pub fn ranges(comptime T: type, value: T, source_len: usize) Error!void {
    var validator: Validator = .{ .program = .{ .nodes = .empty, .statements = .empty, .functions = &.{} }, .source_len = source_len, .colors = &.{} };
    try validator.walk(T, value, 0);
}

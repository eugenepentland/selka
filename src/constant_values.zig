//! Bounded scalar constant evaluation with checked arithmetic and acyclic dependencies.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const integers = @import("integers.zig");
const eLimit = "E_CONSTANT_LIMIT";
const eType = "E_CONSTANT_TYPE";
/// Source context for immutable scalar declarations; no guest authority is available.
pub const Context = struct {
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    /// Resolve a visible constant or leave an ordinary local/function name unchanged.
    pub fn lookup(self: Context, name: source.Span) Error!?usize {
        var any_constants = false;
        for (self.program.functions) |function| if (function.policy.constant) {
            any_constants = true;
            break;
        };
        if (!any_constants) return null;
        const target = if (self.names) |names| resolved: {
            if (!try names.topLevel(name) and std.mem.indexOf(u8, self.src.text(name), "::") == null) return null;
            break :resolved try names.reference(name, .function, null, null, self.sink);
        } else self.src.text(name);
        for (self.program.functions, 0..) |function, index| {
            if (!function.policy.constant) continue;
            const identity = if (self.names) |names| try names.functionDeclaration(null, function.name) else self.src.text(function.name);
            if (std.mem.eql(u8, identity, target)) return index;
        }
        return null;
    }
    /// Evaluate one constant including forward references within a bounded dependency graph.
    pub fn evaluate(self: Context, index: usize) Error!typed.Value {
        const allocator = self.sink.allocator;
        const values = try allocator.alloc(?typed.Value, self.program.functions.len);
        defer allocator.free(values);
        @memset(values, null);
        const visiting = try allocator.alloc(bool, self.program.functions.len);
        defer allocator.free(visiting);
        @memset(visiting, false);
        var evaluator: Evaluator = .{ .context = self, .values = values, .visiting = visiting };
        try evaluator.validateDeclaration(index, 0);
        return evaluator.declaration(index, 0);
    }
};
const Evaluator = struct {
    context: Context,
    values: []?typed.Value,
    visiting: []bool,
    work: usize = 0,
    fn validateDeclaration(self: *Evaluator, index: usize, depth: usize) Error!void {
        const function = self.context.program.functions[index];
        if (depth >= 256) return self.context.sink.fail(eLimit, function.name, "constant dependency nesting exceeds 256");
        if (self.visiting[index]) return self.context.sink.fail("E_CONSTANT_CYCLE", function.name, "constant initializers must have acyclic dependencies");
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const body = self.context.program.statements.items[@backingInt(function.body)].data.block[0];
        try self.validateExpression(self.context.program.statements.items[@backingInt(body)].data.ret, depth + 1);
    }
    fn validateExpression(self: *Evaluator, id: ast.NodeId, depth: usize) Error!void {
        const node = self.context.program.nodes.items[@backingInt(id)];
        self.work += 1;
        if (depth >= 256 or self.work > 65536) return self.context.sink.fail(eLimit, node.span, "constant evaluation exceeds nesting or work budget");
        switch (node.data) {
            .integer, .boolean => {},
            .name => |name| {
                const index = try self.context.lookup(name) orelse return self.context.sink.fail("E_CONSTANT_NAME", name, "constant initializers may refer only to other constants");
                try self.validateDeclaration(index, depth + 1);
            },
            .unary => |unary| try self.validateExpression(unary.operand, depth + 1),
            .cast => |cast| try self.validateExpression(cast.value, depth + 1),
            .binary => |binary| {
                try self.validateExpression(binary.left, depth + 1);
                try self.validateExpression(binary.right, depth + 1);
            },
            else => return self.context.sink.fail("E_CONSTANT_EXPRESSION", node.span, "constant initializers support scalar literals, constants, casts and operators; calls and allocation are excluded"),
        }
    }
    fn declaration(self: *Evaluator, index: usize, depth: usize) Error!typed.Value {
        const function = self.context.program.functions[index];
        if (depth >= 256) return self.context.sink.fail(eLimit, function.name, "constant dependency nesting exceeds 256");
        if (self.values[index]) |value| return value;
        if (self.visiting[index]) return self.context.sink.fail("E_CONSTANT_CYCLE", function.name, "constant initializers must have acyclic dependencies");
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const result_type = typed.Type.fromName(self.context.src.text(function.signature.return_type)) orelse
            return self.context.sink.fail(eType, function.signature.return_type, "constant types currently require builtin integers or bool");
        if (!result_type.isInteger() and result_type != .bool) return self.context.sink.fail(eType, function.signature.return_type, "constant types currently require builtin integers or bool");
        const body = self.context.program.statements.items[@backingInt(function.body)].data.block[0];
        const initializer = self.context.program.statements.items[@backingInt(body)].data.ret;
        const value = try self.expression(initializer, depth + 1);
        if (value.typeOf() != result_type) return self.context.sink.fail("E_TYPE", function.signature.return_type, "constant initializer type differs from its declared type");
        self.values[index] = value;
        return value;
    }
    fn failure(self: *Evaluator, span: source.Span, err: integers.Error) Error {
        return self.context.sink.fail("E_CONSTANT_ARITHMETIC", span, switch (err) {
            error.Overflow => "constant arithmetic overflows its integer type",
            error.DivisionByZero => "constant arithmetic divides by zero",
            error.InternalError => "constant operation requires matching scalar operand types",
        });
    }
    fn expression(self: *Evaluator, id: ast.NodeId, depth: usize) Error!typed.Value {
        const node = self.context.program.nodes.items[@backingInt(id)];
        self.work += 1;
        if (depth >= 256 or self.work > 65536) return self.context.sink.fail(eLimit, node.span, "constant evaluation exceeds nesting or work budget");
        switch (node.data) {
            .integer => |span| {
                const literal = try @import("integer_literal.zig").parse(self.context.src, span, false, self.context.sink);
                return typed.Value.number(literal.ty, literal.value);
            },
            .boolean => |value| return .{ .bool = value },
            .name => |name| {
                const index = try self.context.lookup(name) orelse return self.context.sink.fail("E_CONSTANT_NAME", name, "constant initializers may refer only to other constants");
                return self.declaration(index, depth + 1);
            },
            .cast => |cast| {
                const ty = typed.Type.fromName(self.context.src.text(cast.ty)) orelse return self.context.sink.fail(eType, cast.ty, "constant cast requires a builtin integer type");
                const value = try self.expression(cast.value, depth + 1);
                if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", node.span, "constant cast requires an integer");
                return integers.cast(ty, integer(value)) catch |err| return self.failure(node.span, err);
            },
            .unary => |unary| {
                const operand = self.context.program.nodes.items[@backingInt(unary.operand)];
                if (unary.op == .neg and operand.data == .integer) {
                    const literal = try @import("integer_literal.zig").parse(self.context.src, operand.data.integer, true, self.context.sink);
                    return integers.cast(literal.ty, -literal.value) catch |err| return self.failure(node.span, err);
                }
                const value = try self.expression(unary.operand, depth + 1);
                if (unary.op == .not and value.typeOf() == .bool) return .{ .bool = !value.bool };
                if (unary.op == .neg and value.typeOf().isInteger()) return integers.cast(value.typeOf(), -integer(value)) catch |err| return self.failure(node.span, err);
                return self.context.sink.fail("E_TYPE", node.span, "invalid constant unary operand");
            },
            .binary => |binary| {
                const left = try self.expression(binary.left, depth + 1);
                if (left.typeOf() == .bool) {
                    if (binary.op == .logical_and and !left.bool) return left;
                    if (binary.op == .logical_or and left.bool) return left;
                }
                const right = try self.expression(binary.right, depth + 1);
                if (left.typeOf() != right.typeOf()) return self.context.sink.fail("E_TYPE", node.span, "constant binary operands must have the same type");
                if (left.typeOf() == .bool) return switch (binary.op) {
                    .logical_and => .{ .bool = left.bool and right.bool },
                    .logical_or => .{ .bool = left.bool or right.bool },
                    .eq => .{ .bool = left.bool == right.bool },
                    .ne => .{ .bool = left.bool != right.bool },
                    else => self.context.sink.fail("E_TYPE", node.span, "invalid constant boolean operation"),
                };
                return integers.binary(left.typeOf(), std.meta.stringToEnum(typed.BinaryOp, @tagName(binary.op)).?, integer(left), integer(right)) catch |err| return self.failure(node.span, err);
            },
            else => return self.context.sink.fail("E_CONSTANT_EXPRESSION", node.span, "constant initializers support scalar literals, constants, casts and operators; calls and allocation are excluded"),
        }
    }
};
fn integer(value: typed.Value) i128 {
    return if (value == .i64) value.i64 else value.integer.value;
}

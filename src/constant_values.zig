//! Literal-only managed constants and bounded scalar evaluation with checked dependencies.
const call_arguments = @import("call_arguments.zig");
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const integers = @import("integers.zig");
const integer_literal = @import("integer_literal.zig");
const eLimit = "E_CONSTANT_LIMIT";
const eType = "E_CONSTANT_TYPE";
const eEffect = "E_CONSTANT_EFFECT";
const eExpression = "E_CONSTANT_EXPRESSION";
const eName = "E_CONSTANT_NAME";
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const Assignment = @FieldType(@FieldType(ast.Statement, "data"), "assignment");
const Range = @FieldType(@FieldType(ast.Statement, "data"), "for_range");
/// Source context for immutable declarations; no guest authority is available.
pub const Context = struct {
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    sink: *diagnostic.Sink,
    catalog: ?@import("type_catalog.zig").Catalog = null,
    fn resolveType(self: Context, span: source.Span) Error!typed.Type {
        if (self.catalog) |catalog| return catalog.resolve(self.src, span, self.sink);
        return typed.Type.fromName(self.src.text(span)) orelse self.sink.fail(eType, span, "constant type requires a known scalar type");
    }
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
    /// The declared type of the constant at `index`, resolved without evaluating it.
    pub fn declaredType(self: Context, index: usize) Error!typed.Type {
        return self.resolveType(self.program.functions[index].signature.return_type);
    }
    /// Validate a str/bytes literal getter, leaving scalar declarations to evaluation.
    pub fn literalType(self: Context, index: usize) Error!?typed.Type {
        const function = self.program.functions[index];
        const ty = try self.resolveType(function.signature.return_type);
        const catalog = self.catalog orelse return null;
        if (!ty.isAggregate()) return null;
        const kind = catalog.records[ty.recordIndex()].collection.kind;
        if (kind != .string and kind != .bytes) return null;
        const body = self.program.statements.items[@backingInt(function.body)].data.block[0];
        const initializer = self.program.statements.items[@backingInt(body)].data.ret;
        const node = self.program.nodes.items[@backingInt(initializer)];
        if (node.data != .text and node.data != .bytes)
            return self.sink.fail(eExpression, node.span, "str and bytes constants require a literal initializer; calls, operators, casts and dependencies are excluded");
        if ((kind == .string) != (node.data == .text))
            return self.sink.fail("E_TYPE", node.span, "constant literal type differs from its declared str or bytes type");
        return ty;
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
        defer evaluator.frame.locals.deinit(allocator);
        try evaluator.validateDeclaration(index, 0);
        return evaluator.declaration(index, 0);
    }
};
const Evaluator = struct {
    context: Context,
    values: []?typed.Value,
    visiting: []bool,
    work: usize = 0,
    frame: struct { locals: std.ArrayList(Local) = .empty, base: usize = 0, result: ?typed.Type = null } = .{},
    const Local = struct { name: source.Span, value: ?typed.Value, mutable: bool };
    const Flow = union(enum) { next, returned: typed.Value, break_loop, continue_loop };
    fn take(self: *Evaluator, span: source.Span, depth: usize) Error!void {
        self.work += 1;
        if (depth >= 256 or self.work > 65536) return self.context.sink.fail(eLimit, span, "constant evaluation exceeds nesting or work budget");
    }
    fn local(self: *Evaluator, name: source.Span) Error!?usize {
        var index = self.frame.locals.items.len;
        while (index > self.frame.base) {
            index -= 1;
            try self.take(name, 0);
            if (std.mem.eql(u8, self.context.src.text(name), self.context.src.text(self.frame.locals.items[index].name))) return index;
        }
        return null;
    }
    fn bind(self: *Evaluator, name: source.Span, value: ?typed.Value, mutable: bool) Error!void {
        try self.frame.locals.append(self.context.sink.allocator, .{ .name = name, .value = value, .mutable = mutable });
    }
    fn scalar(self: *Evaluator, span: source.Span) Error!typed.Type {
        const ty = try self.context.resolveType(span);
        if (!ty.isInteger() and ty != .bool) return self.context.sink.fail(eType, span, "compile-time function values require scalar integer or bool types");
        return ty;
    }
    fn callIndex(self: *Evaluator, call: Call, span: source.Span) Error!usize {
        if (call.owner != null or call.type_arguments.len != 0) return self.context.sink.fail(eExpression, span, "compile-time calls require nongeneric free functions");
        const target = if (self.context.names) |names| try names.reference(call.name, .function, null, null, self.context.sink) else self.context.src.text(call.name);
        for (self.context.program.functions, 0..) |function, index| {
            try self.take(span, 0);
            if (function.policy.owner != null) continue;
            const name = if (self.context.names) |names| try names.functionDeclaration(null, function.name) else self.context.src.text(function.name);
            if (!std.mem.eql(u8, name, target)) continue;
            if (function.policy.host != null or function.signature.type_parameters.len != 0)
                return self.context.sink.fail(eEffect, span, "compile-time calls cannot use host functions or generics");
            const bound = try call_arguments.bind(self.context.sink.allocator, self.context.src, self.context.program.nodes.items, call, function.signature, self.context.sink);
            call_arguments.release(self.context.sink.allocator, call, bound);
            _ = try self.scalar(function.signature.return_type);
            for (function.signature.parameters) |parameter| {
                _ = try self.scalar(parameter.ty);
            }
            return index;
        }
        return self.context.sink.fail(eName, call.name, "compile-time call requires a visible source function");
    }
    fn validateCall(self: *Evaluator, call: Call, span: source.Span, depth: usize) Error!void {
        for (call.arguments) |argument| try self.validateExpression(argument, depth + 1);
        const index = try self.callIndex(call, span);
        if (self.visiting[index]) return;
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        self.frame.base = before;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
        }
        const function = self.context.program.functions[index];
        for (function.signature.parameters) |parameter| try self.bind(parameter.name, null, false);
        try self.validateStatement(function.body, depth + 1);
    }
    fn validateStatement(self: *Evaluator, id: ast.StatementId, depth: usize) Error!void {
        const stmt = self.context.program.statements.items[@backingInt(id)];
        try self.take(stmt.span, depth);
        switch (stmt.data) {
            .ret, .discard => |value| try self.validateExpression(value, depth + 1),
            .loop_exit => {},
            .block => |children| {
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                for (children) |child| try self.validateStatement(child, depth + 1);
            },
            .binding => |binding| {
                try self.validateExpression(binding.value, depth + 1);
                if (binding.annotation) |annotation| _ = try self.scalar(annotation);
                try self.bind(binding.name, null, binding.mutable);
            },
            .assignment => |assignment| {
                try self.validateExpression(assignment.value, depth + 1);
                if (assignment.op == .set and try self.local(assignment.name) == null) try self.bind(assignment.name, null, true);
            },
            .branch => |branch| {
                try self.validateExpression(branch.condition, depth + 1);
                try self.validateStatement(branch.then_body, depth + 1);
                if (branch.else_body) |body| try self.validateStatement(body, depth + 1);
            },
            .loop => |loop| {
                try self.validateExpression(loop.condition, depth + 1);
                try self.validateStatement(loop.body, depth + 1);
            },
            .for_range => |range| {
                if (self.context.program.nodes.items[@backingInt(range.start)].data != .unit) try self.validateExpression(range.start, depth + 1);
                try self.validateExpression(range.end, depth + 1);
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                try self.bind(range.name, null, true);
                try self.validateStatement(range.body, depth + 1);
            },
            else => return self.context.sink.fail(eEffect, stmt.span, "compile-time function bodies permit scalar locals, branches and loops; runtime memory and effects are excluded"),
        }
    }
    fn executeCall(self: *Evaluator, input: Call, span: source.Span, depth: usize) Error!typed.Value {
        const index = try self.callIndex(input, span);
        const function = self.context.program.functions[index];
        const invocation = try call_arguments.bind(self.context.sink.allocator, self.context.src, self.context.program.nodes.items, input, function.signature, self.context.sink);
        defer call_arguments.release(self.context.sink.allocator, input, invocation);
        const arguments = try self.context.sink.allocator.alloc(typed.Value, invocation.arguments.len);
        defer self.context.sink.allocator.free(arguments);
        for (0..invocation.arguments.len) |source_index| {
            const position = call_arguments.parameterPosition(invocation, source_index);
            const argument = invocation.arguments[position];
            const parameter = function.signature.parameters[position];
            const value = &arguments[position];
            const parameter_type = try self.scalar(parameter.ty);
            value.* = try self.expressionAs(argument, parameter_type, depth + 1);
            if (value.typeOf() != parameter_type) return self.context.sink.fail("E_TYPE", parameter.ty, "compile-time argument type differs from parameter");
        }
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        const outer_result = self.frame.result;
        self.frame.base = before;
        self.frame.result = try self.scalar(function.signature.return_type);
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
            self.frame.result = outer_result;
        }
        for (function.signature.parameters, arguments) |parameter, value| try self.bind(parameter.name, value, false);
        const result = try self.statement(function.body, depth + 1);
        if (result != .returned) return self.context.sink.fail("E_CONSTANT_RETURN", span, "compile-time function must return a scalar value");
        if (result.returned.typeOf() != try self.scalar(function.signature.return_type)) return self.context.sink.fail("E_TYPE", function.signature.return_type, "compile-time return type differs from signature");
        return result.returned;
    }
    fn condition(self: *Evaluator, id: ast.NodeId, depth: usize) Error!bool {
        const value = try self.expression(id, depth + 1);
        if (value != .bool) return self.context.sink.fail("E_TYPE", self.context.program.nodes.items[@backingInt(id)].span, "compile-time condition requires bool");
        return value.bool;
    }
    fn statement(self: *Evaluator, id: ast.StatementId, depth: usize) Error!Flow {
        const stmt = self.context.program.statements.items[@backingInt(id)];
        try self.take(stmt.span, depth);
        switch (stmt.data) {
            .ret => |value| return .{ .returned = try self.expressionAs(value, self.frame.result, depth + 1) },
            .discard => |value| {
                _ = try self.expression(value, depth + 1);
            },
            .loop_exit => |is_continue| return if (is_continue) .continue_loop else .break_loop,
            .block => |children| {
                const before = self.frame.locals.items.len;
                defer self.frame.locals.shrinkRetainingCapacity(before);
                for (children) |child| {
                    const flow = try self.statement(child, depth + 1);
                    if (flow != .next) return flow;
                }
            },
            .binding => |binding| {
                const declared: ?typed.Type = if (binding.annotation) |annotation| try self.scalar(annotation) else null;
                const value = try self.expressionAs(binding.value, declared, depth + 1);
                if (binding.annotation) |annotation| {
                    if (value.typeOf() != declared.?) return self.context.sink.fail("E_TYPE", annotation, "compile-time binding annotation differs from initializer");
                }
                try self.bind(binding.name, value, binding.mutable);
            },
            .assignment => |assignment| try self.assign(assignment, depth + 1),
            .branch => |branch| {
                if (try self.condition(branch.condition, depth + 1)) return self.statement(branch.then_body, depth + 1);
                if (branch.else_body) |body| return self.statement(body, depth + 1);
            },
            .loop => |loop| {
                while (try self.condition(loop.condition, depth + 1)) {
                    const flow = try self.statement(loop.body, depth + 1);
                    if (flow == .returned) return flow;
                    if (flow == .break_loop) break;
                }
            },
            .for_range => |range| return self.rangeLoop(range, depth + 1),
            else => return self.context.sink.fail(eEffect, stmt.span, "unsupported compile-time statement"),
        }
        return .next;
    }
    fn assign(self: *Evaluator, assignment: Assignment, depth: usize) Error!void {
        const existing = try self.local(assignment.name);
        if (existing == null and assignment.op == .set) {
            const bound = try self.expression(assignment.value, depth + 1);
            return self.bind(assignment.name, bound, true);
        }
        const index = existing orelse return self.context.sink.fail(eName, assignment.name, "compile-time compound assignment requires an existing local");
        const previous = self.frame.locals.items[index];
        var value = try self.expressionAs(assignment.value, previous.value.?.typeOf(), depth + 1);
        if (value.typeOf() != previous.value.?.typeOf()) return self.context.sink.fail("E_TYPE", assignment.op_span, "compile-time assignment types differ");
        if (assignment.op != .set) {
            if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", assignment.op_span, "compound assignment requires integers");
            value = integers.binary(value.typeOf(), if (assignment.op == .add) .add else .sub, integer(previous.value.?), integer(value)) catch |err| return self.failure(assignment.op_span, err);
        }
        self.frame.locals.items[index].value = value;
    }
    fn rangeLoop(self: *Evaluator, range: Range, depth: usize) Error!Flow {
        var start: typed.Value = if (self.context.program.nodes.items[@backingInt(range.start)].data == .unit) .{ .i64 = 0 } else try self.expression(range.start, depth + 1);
        const end = try self.expression(range.end, depth + 1);
        if (!start.typeOf().isInteger() or start.typeOf() != end.typeOf()) return self.context.sink.fail("E_TYPE", range.name, "compile-time range requires matching integers");
        const before = self.frame.locals.items.len;
        defer self.frame.locals.shrinkRetainingCapacity(before);
        try self.bind(range.name, start, true);
        while (integer(start) < integer(end)) {
            self.frame.locals.items[before].value = start;
            const flow = try self.statement(range.body, depth + 1);
            if (flow == .returned) return flow;
            if (flow == .break_loop) break;
            start = integers.cast(start.typeOf(), integer(start) + 1) catch |err| return self.failure(range.name, err);
        }
        return .next;
    }

    fn validateDeclaration(self: *Evaluator, index: usize, depth: usize) Error!void {
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        self.frame.base = before;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
        }
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
        try self.take(node.span, depth);
        switch (node.data) {
            .unit, .integer, .boolean => {},
            .call => |invocation| try self.validateCall(invocation, node.span, depth + 1),
            .name => |name| {
                if (try self.local(name) != null) return;
                self.work += self.context.program.functions.len;
                try self.take(name, depth);
                const index = try self.context.lookup(name) orelse return self.context.sink.fail(eName, name, "constant initializers may refer only to other constants");
                try self.validateDeclaration(index, depth + 1);
            },
            .unary => |unary| try self.validateExpression(unary.operand, depth + 1),
            .cast => |cast| try self.validateExpression(cast.value, depth + 1),
            .binary => |binary| {
                try self.validateExpression(binary.left, depth + 1);
                try self.validateExpression(binary.right, depth + 1);
            },
            else => return self.context.sink.fail(eExpression, node.span, "constant evaluation permits scalar expressions and source functions; allocation and external effects are excluded"),
        }
    }
    fn declaration(self: *Evaluator, index: usize, depth: usize) Error!typed.Value {
        const before = self.frame.locals.items.len;
        const base = self.frame.base;
        self.frame.base = before;
        defer {
            self.frame.locals.shrinkRetainingCapacity(before);
            self.frame.base = base;
        }
        const function = self.context.program.functions[index];
        if (depth >= 256) return self.context.sink.fail(eLimit, function.name, "constant dependency nesting exceeds 256");
        if (self.values[index]) |value| return value;
        if (self.visiting[index]) return self.context.sink.fail("E_CONSTANT_CYCLE", function.name, "constant initializers must have acyclic dependencies");
        self.visiting[index] = true;
        defer self.visiting[index] = false;
        const result_type = try self.context.resolveType(function.signature.return_type);
        if (!result_type.isInteger() and result_type != .bool) return self.context.sink.fail(eType, function.signature.return_type, "constant types currently require builtin integers or bool");
        const body = self.context.program.statements.items[@backingInt(function.body)].data.block[0];
        const initializer = self.context.program.statements.items[@backingInt(body)].data.ret;
        const value = try self.expressionAs(initializer, result_type, depth + 1);
        if (value.typeOf() != result_type) return self.context.sink.fail("E_TYPE", function.signature.return_type, "constant initializer type differs from its declared type");
        self.values[index] = value;
        return value;
    }
    fn failure(self: *Evaluator, span: source.Span, err: integers.Error) Error {
        return self.context.sink.fail("E_CONSTANT_ARITHMETIC", span, switch (err) {
            error.Overflow => "constant arithmetic overflows its integer type",
            error.DivisionByZero => "constant arithmetic divides by zero",
            error.FloatConversion => "constant floating conversion is outside the integer range",
            error.InvalidShift => "constant shift count is outside its integer width",
            error.InternalError => "constant operation requires matching scalar operand types",
        });
    }
    fn expression(self: *Evaluator, id: ast.NodeId, depth: usize) Error!typed.Value {
        return self.expressionAs(id, null, depth);
    }
    /// Whether the node is an unsuffixed integer literal, possibly negated: the one
    /// expression whose type comes from its context rather than from its spelling.
    fn adoptsType(self: *Evaluator, id: ast.NodeId) bool {
        var node = self.context.program.nodes.items[@backingInt(id)];
        if (node.data == .unary and node.data.unary.op == .neg) node = self.context.program.nodes.items[@backingInt(node.data.unary.operand)];
        if (node.data != .integer) return false;
        return integer_literal.unsuffixed(self.context.src.text(node.data.integer));
    }
    /// Evaluate with an expected integer type, so an unsuffixed literal (and the operands
    /// of arithmetic around one) takes the declared type, as it does in checked code.
    fn expressionAs(self: *Evaluator, id: ast.NodeId, expected: ?typed.Type, depth: usize) Error!typed.Value {
        const node = self.context.program.nodes.items[@backingInt(id)];
        try self.take(node.span, depth);
        switch (node.data) {
            .integer => |span| {
                const literal = try integer_literal.parseExpected(self.context.src, span, false, expected, self.context.sink);
                return typed.Value.number(literal.ty, literal.value);
            },
            .boolean => |value| return .{ .bool = value },
            .call => |invocation| return self.executeCall(invocation, node.span, depth + 1),
            .name => |name| {
                if (try self.local(name)) |index| return self.frame.locals.items[index].value orelse error.InternalError;
                self.work += self.context.program.functions.len;
                try self.take(name, depth);
                const index = try self.context.lookup(name) orelse return self.context.sink.fail(eName, name, "constant initializers may refer only to other constants");
                return self.declaration(index, depth + 1);
            },
            .cast => |cast| {
                const ty = try self.context.resolveType(cast.ty);
                const value = try self.expression(cast.value, depth + 1);
                if (!value.typeOf().isInteger()) return self.context.sink.fail("E_TYPE", node.span, "constant cast requires an integer");
                return integers.cast(ty, integer(value)) catch |err| return self.failure(node.span, err);
            },
            .unary => |unary| {
                if (unary.op == .is_none) return self.context.sink.fail("E_OPTION_TEST", node.span, "is None requires an Option value");
                const operand = self.context.program.nodes.items[@backingInt(unary.operand)];
                if (unary.op == .neg and operand.data == .integer) {
                    const literal = try integer_literal.parseExpected(self.context.src, operand.data.integer, true, expected, self.context.sink);
                    return integers.cast(literal.ty, -literal.value) catch |err| return self.failure(node.span, err);
                }
                const value = try self.expressionAs(unary.operand, if (unary.op == .neg) expected else null, depth + 1);
                if (unary.op != .neg and unary.op != .not) {
                    if (value.typeOf() != .u64) return self.context.sink.fail("E_TYPE", node.span, "floating representation requires u64");
                    const converted = @import("floats.zig").unary(std.meta.stringToEnum(typed.UnaryOp, @tagName(unary.op)).?, @intCast(integer(value))) catch |err| return self.failure(node.span, err);
                    return typed.Value.number(.u64, converted);
                }
                if (unary.op == .not and value.typeOf() == .bool) return .{ .bool = !value.bool };
                if (unary.op == .neg and value.typeOf().isInteger()) return integers.cast(value.typeOf(), -integer(value)) catch |err| return self.failure(node.span, err);
                return self.context.sink.fail("E_TYPE", node.span, "invalid constant unary operand");
            },
            .binary => |binary| {
                const inherited = if (typesResult(binary.op)) expected else null;
                // A literal operand takes its sibling's type, so the typed side goes first.
                const literal_first = self.adoptsType(binary.left) and !self.adoptsType(binary.right);
                var left: typed.Value = undefined;
                var right: typed.Value = undefined;
                if (literal_first) {
                    right = try self.expressionAs(binary.right, inherited, depth + 1);
                    left = try self.expressionAs(binary.left, siblingType(right, inherited), depth + 1);
                } else {
                    left = try self.expressionAs(binary.left, inherited, depth + 1);
                    if (left.typeOf() == .bool) {
                        if (binary.op == .logical_and and !left.bool) return left;
                        if (binary.op == .logical_or and left.bool) return left;
                    }
                    right = try self.expressionAs(binary.right, siblingType(left, inherited), depth + 1);
                }
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
            else => return self.context.sink.fail(eExpression, node.span, "constant evaluation permits scalar expressions and source functions; allocation and external effects are excluded"),
        }
    }
};
/// Whether a binary operator's result has its operands' type, so the expected type
/// flows into them; comparisons and logical operators produce `bool` instead.
fn typesResult(op: ast.BinaryOp) bool {
    return switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge, .logical_and, .logical_or => false,
        else => true,
    };
}
/// The type a literal takes from its already evaluated sibling operand, or the
/// inherited expectation when that operand is not an integer.
fn siblingType(sibling: typed.Value, inherited: ?typed.Type) ?typed.Type {
    return if (sibling.typeOf().isInteger()) sibling.typeOf() else inherited;
}
fn integer(value: typed.Value) i128 {
    return if (value == .i64) value.i64 else value.integer.value;
}

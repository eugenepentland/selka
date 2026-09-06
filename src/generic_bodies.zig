//! Symbolic checking of pure template bodies; no representative concrete type is substituted.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;
const eShadowing = diagnostic.shadowing;
const eUnsupported = "E_GENERIC_BODY_UNSUPPORTED";
const Symbolic = union(enum) { builtin: typed.Type, parameter: usize };
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const FunctionMap = std.StringHashMapUnmanaged(usize);
const Local = struct { name: source.Span, ty: Symbolic, mutable: bool };
const Checker = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    parameters: []const requirements.Parameter,
    result: Symbolic,
    functions: *const FunctionMap,
    pending: *std.ArrayList(usize),
    scheduled: []bool,
    owner: ?source.Span = null,
    module_names: ?*Names = null,
    locals: std.ArrayList(Local) = .empty,
    active: std.StringHashMapUnmanaged(usize) = .empty,
    depth: usize = 0,
    work: usize = 0,
    fn enter(self: *Checker, span: source.Span) Error!void {
        if (self.depth == 256 or self.work == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic body exceeds checking depth/work budget");
        self.depth += 1;
        self.work += 1;
    }
    fn ty(self: *Checker, span: source.Span) Error!Symbolic {
        const text = self.src.text(span);
        for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return .{ .parameter = index };
        if (typed.Type.fromName(text)) |builtin| return .{ .builtin = builtin };
        return self.sink.fail(eUnsupported, span, "generic body checking does not yet support concrete nominal or composite signature types");
    }
    fn same(self: *Checker, actual: Symbolic, expected: Symbolic, span: source.Span) Error!void {
        if (!std.meta.eql(actual, expected)) return self.sink.fail("E_GENERIC_TYPE", span, "types differ; distinct type parameters remain distinct even with identical requirements");
    }
    fn supports(self: *Checker, ty_value: Symbolic, requirement: requirements.Requirement, span: source.Span) Error!void {
        const supported = switch (ty_value) {
            .parameter => |index| self.parameters[index].requirements.contains(requirement),
            .builtin => |builtin| result: {
                var required: requirements.Set = .{};
                required.include(requirement);
                break :result required.accepts(builtin, &.{});
            },
        };
        if (!supported) {
            const message = try std.fmt.allocPrint(self.sink.allocator, "operation requires declared {s} support", .{@tagName(requirement)});
            return self.sink.fail("E_GENERIC_OPERATION", span, message);
        }
    }
    fn local(self: *Checker, span: source.Span) Error!*Local {
        const index = self.active.get(self.src.text(span)) orelse return self.sink.fail("E_UNKNOWN_NAME", span, "name is not defined in this template scope");
        return &self.locals.items[index];
    }
    fn topLevel(self: *Checker, span: source.Span) Error!bool {
        if (self.module_names) |names| return names.topLevel(span);
        const name = self.src.text(span);
        if (self.functions.contains(name)) return true;
        inline for (.{ "records", "domains", "variants", "buffers", "resources", "pools" }) |field| {
            for (@field(self.program.types, field)) |declaration| if (std.mem.eql(u8, name, self.src.text(declaration.name))) return true;
        }
        for (self.program.types.pools) |pool| if (std.mem.eql(u8, name, self.src.text(pool.handle))) return true;
        return false;
    }
    fn bind(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        const text = self.src.text(name);
        if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows a top-level declaration or import");
        if (self.active.contains(text)) return self.sink.fail(eShadowing, name, "binding shadows an active template binding");
        for (self.parameters) |parameter| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return self.sink.fail(eShadowing, name, "binding shadows a template type parameter");
        try self.active.put(self.allocator, text, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .ty = ty_value, .mutable = mutable });
    }
    fn callTarget(self: *Checker, invocation: Call) Error!ast.Function {
        const key = if (self.module_names) |names|
            try names.reference(invocation.owner orelse invocation.name, .function, if (invocation.owner != null) invocation.name else null, if (self.owner) |owner| self.src.text(owner) else null, self.sink)
        else
            try @import("function_identity.zig").localName(self.sink.allocator, self.src, invocation.owner, invocation.name);
        const index = self.functions.get(key) orelse return self.sink.fail("E_UNKNOWN_FUNCTION", invocation.name, "no function has this qualified name");
        const function = self.program.functions[index];
        if (self.module_names == null and function.policy.restricted) {
            const allowed = if (self.owner) |owner| std.mem.eql(u8, self.src.text(owner), self.src.text(function.policy.owner.?)) else false;
            if (!allowed) return self.sink.failRelated("E_PRIVATE_FUNCTION", invocation.name, "private generic method requires the same declaring domain", .{ .span = function.name, .message = "private function declared here" });
        }
        if (!self.scheduled[index]) {
            self.pending.appendAssumeCapacity(index);
            self.scheduled[index] = true;
        }
        return function;
    }
    fn substituted(self: *Checker, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!Symbolic {
        const text = self.src.text(span);
        for (parameters, arguments) |parameter, argument| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return argument;
        if (typed.Type.fromName(text)) |builtin| return .{ .builtin = builtin };
        return self.sink.fail(eUnsupported, span, "generic call signature still needs nominal/composite substitution");
    }
    fn call(self: *Checker, invocation: Call, span: source.Span) Error!Symbolic {
        const function = try self.callTarget(invocation);
        const signature = function.signature;
        if (signature.return_reference != null or function.policy.conversion) return self.sink.fail(eUnsupported, span, "generic reference-result and conversion calls still need abstract checking");
        if (invocation.type_arguments.len != signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (invocation.arguments.len != signature.parameters.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        const required = try requirements.resolve(self.allocator, self.src, signature.type_parameters, self.sink);
        defer self.allocator.free(required);
        const arguments = try self.allocator.alloc(Symbolic, required.len);
        defer self.allocator.free(arguments);
        for (invocation.type_arguments, required, arguments) |argument_span, parameter, *argument| {
            argument.* = try self.ty(argument_span);
            const satisfies = switch (argument.*) {
                .parameter => |index| self.parameters[index].requirements.implies(parameter.requirements),
                .builtin => |builtin| parameter.requirements.accepts(builtin, &.{}),
            };
            if (!satisfies) return self.sink.failRelated(
                "E_GENERIC_ARGUMENT",
                argument_span,
                "type argument does not satisfy the callee's declared requirements",
                .{ .span = parameter.name, .message = "required type parameter declared here" },
            );
        }
        for (invocation.arguments, signature.parameters) |value, parameter| {
            if (parameter.reference != null) return self.sink.fail(eUnsupported, parameter.name, "generic reference arguments still need abstract checking");
            const expected = try self.substituted(parameter.ty, signature.type_parameters, arguments);
            try self.same(try self.expression(value), expected, self.program.nodes.items[@backingInt(value)].span);
        }
        return self.substituted(signature.return_type, signature.type_parameters, arguments);
    }
    fn expression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const node = self.program.nodes.items[@backingInt(id)];
        try self.enter(node.span);
        defer self.depth -= 1;
        return switch (node.data) {
            .name => |name| (try self.local(name)).ty,
            .call => |invocation| try self.call(invocation, node.span),
            .boolean => .{ .builtin = .bool },
            .integer => |span| .{ .builtin = (try @import("integer_literal.zig").parse(self.src, span, false, self.sink)).ty },
            .unary => |unary| result: {
                const child = self.program.nodes.items[@backingInt(unary.operand)];
                const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
                    .{ .builtin = (try @import("integer_literal.zig").parse(self.src, child.data.integer, true, self.sink)).ty }
                else
                    try self.expression(unary.operand);
                if (unary.op == .neg) try self.supports(operand, .integer, unary.op_span) else try self.same(operand, .{ .builtin = .bool }, unary.op_span);
                break :result operand;
            },
            .binary => |operation| try self.binary(operation),
            .cast => |cast| result: {
                const operand = try self.expression(cast.value);
                const target = try self.ty(cast.ty);
                try self.supports(operand, .integer, node.span);
                try self.supports(target, .integer, cast.ty);
                break :result target;
            },
            else => self.sink.fail(eUnsupported, node.span, "this operation still needs abstract generic body checking"),
        };
    }
    fn binary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!Symbolic {
        const left = try self.expression(operation.left);
        const right = try self.expression(operation.right);
        try self.same(right, left, operation.op_span);
        switch (operation.op) {
            .logical_and, .logical_or => try self.same(left, .{ .builtin = .bool }, operation.op_span),
            .eq, .ne => try self.supports(left, .equality, operation.op_span),
            else => try self.supports(left, .integer, operation.op_span),
        }
        return switch (operation.op) {
            .add, .sub, .mul, .div, .rem => left,
            else => .{ .builtin = .bool },
        };
    }
    fn block(self: *Checker, statements: []const ast.StatementId) Error!bool {
        const before = self.locals.items.len;
        defer {
            for (self.locals.items[before..]) |item| _ = self.active.remove(self.src.text(item.name));
            self.locals.shrinkRetainingCapacity(before);
        }
        var terminated = false;
        for (statements) |id| {
            if (terminated) return self.sink.fail("E_UNREACHABLE", self.program.statements.items[@backingInt(id)].span, "statement follows an unconditional return");
            terminated = try self.statement(id);
        }
        return terminated;
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!bool {
        const statement_value = self.program.statements.items[@backingInt(id)];
        try self.enter(statement_value.span);
        defer self.depth -= 1;
        switch (statement_value.data) {
            .block => |statements| return self.block(statements),
            .ret => |value| {
                try self.same(try self.expression(value), self.result, statement_value.span);
                return true;
            },
            .binding => |binding| {
                const value = try self.expression(binding.value);
                if (binding.annotation) |annotation| try self.same(value, try self.ty(annotation), annotation);
                try self.bind(binding.name, value, binding.mutable);
            },
            .assignment => |assignment| {
                const target = try self.local(assignment.name);
                if (!target.mutable) return self.sink.fail("E_IMMUTABLE", assignment.name, "assignment requires a mutable binding");
                const value = try self.expression(assignment.value);
                try self.same(value, target.ty, assignment.op_span);
                if (assignment.op != .set) try self.supports(target.ty, .integer, assignment.op_span);
            },
            .discard => |value| try self.supports(try self.expression(value), .copy, statement_value.span),
            .branch => |branch| {
                try self.same(try self.expression(branch.condition), .{ .builtin = .bool }, statement_value.span);
                const left = try self.statement(branch.then_body);
                const right = if (branch.else_body) |other| try self.statement(other) else false;
                return left and right;
            },
            .loop => |loop| {
                try self.same(try self.expression(loop.condition), .{ .builtin = .bool }, statement_value.span);
                _ = try self.statement(loop.body);
            },
            else => return self.sink.fail(eUnsupported, statement_value.span, "this statement still needs abstract generic body checking"),
        }
        return false;
    }
};
/// Validate supported template bodies symbolically; unsupported forms remain explicit errors.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!void {
    return checkWithNames(allocator, src, program, sink, null);
}
/// Validate bodies while preserving the declaring module's names and import aliases.
pub fn checkWithNames(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!void {
    var has_generic = false;
    for (program.functions) |function| if (function.signature.type_parameters.len != 0) {
        has_generic = true;
        break;
    };
    if (!has_generic) return;
    var functions: FunctionMap = .empty;
    defer functions.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        const key = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try @import("function_identity.zig").localName(sink.allocator, src, function.policy.owner, function.name);
        const entry = try functions.getOrPut(allocator, key);
        if (entry.found_existing) return sink.fail("E_DUPLICATE_FUNCTION", function.name, "duplicate function declaration");
        entry.value_ptr.* = index;
    }
    const scheduled = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(scheduled);
    @memset(scheduled, false);
    var pending = try std.ArrayList(usize).initCapacity(allocator, program.functions.len);
    defer pending.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        if (function.signature.type_parameters.len == 0) continue;
        scheduled[index] = true;
        pending.appendAssumeCapacity(index);
    }
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const function = program.functions[pending.items[cursor]];
        const parameters = try requirements.resolve(allocator, src, function.signature.type_parameters, sink);
        defer allocator.free(parameters);
        var checker: Checker = .{
            .allocator = allocator,
            .src = src,
            .program = program,
            .sink = sink,
            .parameters = parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
            .pending = &pending,
            .scheduled = scheduled,
            .owner = function.policy.owner,
        };
        defer checker.locals.deinit(allocator);
        defer checker.active.deinit(allocator);
        if (function.signature.return_reference != null or function.policy.conversion) return sink.fail(eUnsupported, function.name, "generic reference results and conversions still need abstract checking");
        for (parameters) |parameter| if (try checker.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "type parameter shadows a top-level declaration or import");
        checker.result = try checker.ty(function.signature.return_type);
        for (function.signature.parameters) |parameter| {
            if (parameter.reference != null) return sink.fail(eUnsupported, parameter.name, "generic reference parameters still need abstract checking");
            try checker.bind(parameter.name, try checker.ty(parameter.ty), false);
        }
        if (!try checker.statement(function.body)) return sink.fail("E_MISSING_RETURN", function.name, "template may fall through without returning its declared type");
    }
}

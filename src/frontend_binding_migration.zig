//! Scope-aware declaration repairs for the previous implicit-binding syntax.
//! A binding whose uses escape its new block needs a control-flow rewrite;
//! diagnostics leave that case to a person instead of moving initialization.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Span = source.Span;

/// Publish declaration insertions only where the binding's uses fit its block.
pub fn publish(src: source.Source, program: ast.Program, sink: *diagnostic.Sink) diagnostic.Error!bool {
    var pass: Pass = .{ .src = src, .program = program, .sink = sink };
    defer pass.bindings.active.deinit(sink.allocator);
    defer pass.bindings.declarations.deinit(sink.allocator);
    for (program.functions) |function| {
        pass.bindings.active.clearRetainingCapacity();
        pass.bindings.declarations.clearRetainingCapacity();
        pass.function = program.statements.items[@backingInt(function.body)].span;
        for (function.signature.parameters) |parameter| try pass.declare(parameter.name, pass.function, pass.function.start, false);
        try pass.walk(function.body, pass.function);
        try pass.expressionBindings();
        for (pass.bindings.declarations.items) |binding| if (binding.implicit) try pass.repair(binding);
    }
    return pass.changed;
}

const Declaration = struct {
    name: Span,
    scope: Span,
    available: usize,
    implicit: bool,
};

const Pass = struct {
    src: source.Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    bindings: struct {
        active: std.ArrayList(Span) = .empty,
        declarations: std.ArrayList(Declaration) = .empty,
    } = .{},
    function: Span = .{ .start = 0, .end = 0 },
    changed: bool = false,

    fn declare(self: *Pass, name: Span, scope: Span, available: usize, implicit: bool) diagnostic.Error!void {
        try self.bindings.active.append(self.sink.allocator, name);
        try self.bindings.declarations.append(self.sink.allocator, .{ .name = name, .scope = scope, .available = available, .implicit = implicit });
    }

    fn declared(self: *const Pass, name: Span) bool {
        for (self.bindings.active.items) |other| if (std.mem.eql(u8, self.src.text(name), self.src.text(other))) return true;
        return false;
    }

    fn walk(self: *Pass, id: ast.StatementId, scope: Span) diagnostic.Error!void {
        const statement = self.program.statements.items[@backingInt(id)];
        switch (statement.data) {
            .block => |children| {
                const count = self.bindings.active.items.len;
                defer self.bindings.active.shrinkRetainingCapacity(count);
                for (children) |child| try self.walk(child, statement.span);
            },
            .binding => |binding| try self.declare(binding.name, scope, statement.span.end, false),
            .discard => |expression| {
                const value = self.program.nodes.items[@backingInt(expression)].data;
                if (value == .field_assignment and value.field_assignment.declaration != null)
                    try self.tupleBindings(value.field_assignment.target, scope, statement.span.end);
            },
            .assignment => |assigned| try self.assignment(assigned, scope, statement.span.end),
            .for_each => |each| {
                const count = self.bindings.active.items.len;
                defer self.bindings.active.shrinkRetainingCapacity(count);
                const body = self.program.statements.items[@backingInt(each.body)].span;
                try self.declare(each.name, body, body.start, false);
                if (each.index_name) |name| try self.declare(name, body, body.start, false);
                try self.walk(each.body, scope);
            },
            .for_range => |range| try self.boundBody(range.name, range.body, scope),
            .with_scope => |with| try self.boundBody(with.name, with.body, scope),
            .match => |match| for (match.arms) |case| try self.arm(case),
            .branch => |branch| {
                try self.walk(branch.then_body, scope);
                if (branch.else_body) |other| try self.walk(other, scope);
            },
            .loop => |loop| try self.walk(loop.body, scope),
            else => {},
        }
    }

    fn boundBody(self: *Pass, name: ?Span, body: ast.StatementId, scope: Span) diagnostic.Error!void {
        const count = self.bindings.active.items.len;
        defer self.bindings.active.shrinkRetainingCapacity(count);
        const body_scope = self.program.statements.items[@backingInt(body)].span;
        if (name) |binding| try self.declare(binding, body_scope, body_scope.start, false);
        try self.walk(body, scope);
    }

    fn tupleBindings(self: *Pass, id: ast.NodeId, scope: Span, available: usize) diagnostic.Error!void {
        switch (self.program.nodes.items[@backingInt(id)].data) {
            .name => |name| try self.declare(name, scope, available, false),
            .tuple => |items| for (items) |item| try self.tupleBindings(item, scope, available),
            else => {},
        }
    }

    fn arm(self: *Pass, match: ast.MatchArm) diagnostic.Error!void {
        const count = self.bindings.active.items.len;
        defer self.bindings.active.shrinkRetainingCapacity(count);
        const scope = self.program.statements.items[@backingInt(match.body)].span;
        for (match.bindings) |binding| if (binding) |name| try self.declare(name, scope, scope.start, false);
        for (match.payload_patterns) |field| try self.pattern(field.pattern, scope);
        try self.walk(match.body, scope);
    }

    fn pattern(self: *Pass, value: ast.Pattern, scope: Span) diagnostic.Error!void {
        switch (value.data) {
            .binding => |binding| if (binding) |name| try self.declare(name, scope, scope.start, false),
            .variant => |variant| for (variant.fields) |field| try self.pattern(field.pattern, scope),
        }
    }

    fn assignment(self: *Pass, value: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), scope: Span, available: usize) diagnostic.Error!void {
        if (self.declared(value.name) or std.mem.eql(u8, self.src.text(value.name), "_")) return;
        if (value.op != .set) return;
        try self.declare(value.name, scope, available, true);
    }

    // Comprehension and callback binders have expression scopes, not source
    // blocks. Register only their output/filter/body regions: their own source
    // expressions are evaluated before those binders exist.
    fn expressionBindings(self: *Pass) diagnostic.Error!void {
        for (self.program.nodes.items) |node| {
            if (node.span.start < self.function.start or node.span.end > self.function.end) continue;
            switch (node.data) {
                .comprehension => |each| {
                    try self.expressionBinding(each.name, each.output);
                    if (each.filter) |filter| try self.expressionBinding(each.name, filter);
                },
                .gather => |gather| try self.gatherBindings(gather.loop),
                else => {},
            }
        }
        for (self.program.lambdas) |lambda| {
            if (lambda.span.start < self.function.start or lambda.span.end > self.function.end) continue;
            for (lambda.parameters) |name| try self.expressionBinding(name, lambda.body);
        }
    }

    fn expressionBinding(self: *Pass, name: Span, id: ast.NodeId) diagnostic.Error!void {
        const scope = self.program.nodes.items[@backingInt(id)].span;
        try self.bindings.declarations.append(self.sink.allocator, .{ .name = name, .scope = scope, .available = scope.start, .implicit = false });
    }

    fn gatherBindings(self: *Pass, id: ast.StatementId) diagnostic.Error!void {
        const statement = self.program.statements.items[@backingInt(id)];
        switch (statement.data) {
            .for_each => |each| {
                try self.gatherBody(each.name, each.body);
                if (each.index_name) |name| try self.gatherBody(name, each.body);
                try self.gatherBindings(each.body);
            },
            .for_range => |range| {
                try self.gatherBody(range.name, range.body);
                try self.gatherBindings(range.body);
            },
            .branch => |branch| {
                try self.gatherBindings(branch.then_body);
                if (branch.else_body) |body| try self.gatherBindings(body);
            },
            else => {},
        }
    }

    // An outer gather binder is visible in later clauses' inputs and filters,
    // including legacy comprehensions whose output precedes its binder in text.
    fn gatherBody(self: *Pass, name: Span, id: ast.StatementId) diagnostic.Error!void {
        const statement = self.program.statements.items[@backingInt(id)];
        switch (statement.data) {
            .for_each => |each| {
                try self.expressionBinding(name, each.iterable);
                try self.gatherBody(name, each.body);
            },
            .for_range => |range| {
                try self.expressionBinding(name, range.start);
                try self.expressionBinding(name, range.end);
                if (range.step) |step| try self.expressionBinding(name, step);
                try self.gatherBody(name, range.body);
            },
            .branch => |branch| {
                try self.expressionBinding(name, branch.condition);
                try self.gatherBody(name, branch.then_body);
                if (branch.else_body) |body| try self.gatherBody(name, body);
            },
            .gather_step => |step| {
                try self.expressionBinding(name, step.value);
                if (step.key) |key| try self.expressionBinding(name, key);
            },
            else => {},
        }
    }

    fn repair(self: *Pass, binding: Declaration) diagnostic.Error!void {
        self.changed = true;
        if (self.escapes(binding)) {
            try self.sink.items.append(self.sink.allocator, .{
                .code = "E_BINDING_SCOPE_MIGRATION",
                .span = binding.name,
                .message = "this implicit local is used outside its block; declare the state in the enclosing block or rewrite the branches as a value expression",
            });
            return;
        }
        try self.sink.appendFix(.{
            .code = "E_BINDING_DECLARATION",
            .span = binding.name,
            .message = "declare this writable local with 'mut'",
        }, .{ .span = .{ .start = binding.name.start, .end = binding.name.start }, .text = "mut " });
    }

    // Resolve each use against declarations that dominate it in its lexical
    // block. A sibling's binding is a different identity, while a read before
    // initialization or after leaving every defining block remains unresolved.
    fn escapes(self: *const Pass, binding: Declaration) bool {
        for (self.program.nodes.items) |node| {
            if (node.span.start < self.function.start or node.span.end > self.function.end) continue;
            if (node.data != .name or !std.mem.eql(u8, self.src.text(node.data.name), self.src.text(binding.name))) continue;
            var resolved: ?Declaration = null;
            for (self.bindings.declarations.items) |other| {
                if (!std.mem.eql(u8, self.src.text(other.name), self.src.text(binding.name))) continue;
                if (node.span.start < other.available or node.span.start < other.scope.start or node.span.end > other.scope.end) continue;
                if (resolved == null or other.scope.end - other.scope.start < resolved.?.scope.end - resolved.?.scope.start) resolved = other;
            }
            if (resolved == null) return true;
        }
        return false;
    }
};

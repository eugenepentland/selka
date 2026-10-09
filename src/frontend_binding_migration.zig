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
    defer pass.names.deinit(sink.allocator);
    for (program.functions) |function| {
        pass.names.clearRetainingCapacity();
        for (function.signature.parameters) |parameter| try pass.names.append(sink.allocator, parameter.name);
        pass.function = program.statements.items[@backingInt(function.body)].span;
        try pass.walk(function.body, pass.function);
    }
    return pass.changed;
}

const Pass = struct {
    src: source.Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    names: std.ArrayList(Span) = .empty,
    function: Span = .{ .start = 0, .end = 0 },
    changed: bool = false,

    fn declared(self: *const Pass, name: Span) bool {
        for (self.names.items) |other| if (std.mem.eql(u8, self.src.text(name), self.src.text(other))) return true;
        return false;
    }

    fn walk(self: *Pass, id: ast.StatementId, scope: Span) diagnostic.Error!void {
        const statement = self.program.statements.items[@backingInt(id)];
        switch (statement.data) {
            .block => |children| {
                const count = self.names.items.len;
                defer self.names.shrinkRetainingCapacity(count);
                for (children) |child| try self.walk(child, statement.span);
            },
            .binding => |binding| try self.names.append(self.sink.allocator, binding.name),
            .discard => |expression| {
                const value = self.program.nodes.items[@backingInt(expression)].data;
                if (value == .field_assignment and value.field_assignment.declaration != null)
                    try self.tupleBindings(value.field_assignment.target);
            },
            .assignment => |assigned| try self.assignment(assigned, scope),
            .for_each => |each| {
                const count = self.names.items.len;
                defer self.names.shrinkRetainingCapacity(count);
                try self.names.append(self.sink.allocator, each.name);
                if (each.index_name) |name| try self.names.append(self.sink.allocator, name);
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
        const count = self.names.items.len;
        defer self.names.shrinkRetainingCapacity(count);
        if (name) |binding| try self.names.append(self.sink.allocator, binding);
        try self.walk(body, scope);
    }

    fn tupleBindings(self: *Pass, id: ast.NodeId) diagnostic.Error!void {
        switch (self.program.nodes.items[@backingInt(id)].data) {
            .name => |name| try self.names.append(self.sink.allocator, name),
            .tuple => |items| for (items) |item| try self.tupleBindings(item),
            else => {},
        }
    }

    fn arm(self: *Pass, match: ast.MatchArm) diagnostic.Error!void {
        const count = self.names.items.len;
        defer self.names.shrinkRetainingCapacity(count);
        for (match.bindings) |binding| if (binding) |name| try self.names.append(self.sink.allocator, name);
        for (match.payload_patterns) |field| try self.pattern(field.pattern);
        try self.walk(match.body, self.program.statements.items[@backingInt(match.body)].span);
    }

    fn pattern(self: *Pass, value: ast.Pattern) diagnostic.Error!void {
        switch (value.data) {
            .binding => |binding| if (binding) |name| try self.names.append(self.sink.allocator, name),
            .variant => |variant| for (variant.fields) |field| try self.pattern(field.pattern),
        }
    }

    fn assignment(self: *Pass, value: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), scope: Span) diagnostic.Error!void {
        if (self.declared(value.name) or std.mem.eql(u8, self.src.text(value.name), "_")) return;
        if (value.op != .set) return;
        try self.names.append(self.sink.allocator, value.name);
        self.changed = true;
        if (self.escapes(value.name, scope)) {
            try self.sink.items.append(self.sink.allocator, .{
                .code = "E_BINDING_SCOPE_MIGRATION",
                .span = value.name,
                .message = "this implicit local is used outside its block; declare the state in the enclosing block or rewrite the branches as a value expression",
            });
            return;
        }
        try self.sink.appendFix(.{
            .code = "E_BINDING_DECLARATION",
            .span = value.name,
            .message = "declare this writable local with 'mut'",
        }, .{ .span = .{ .start = value.name.start, .end = value.name.start }, .text = "mut " });
    }

    fn escapes(self: *const Pass, name: Span, scope: Span) bool {
        for (self.program.nodes.items) |node| {
            if (node.span.start < self.function.start or node.span.end > self.function.end) continue;
            if (node.span.start >= scope.start and node.span.end <= scope.end) continue;
            if (node.data == .name and std.mem.eql(u8, self.src.text(node.data.name), self.src.text(name))) return true;
        }
        return false;
    }
};

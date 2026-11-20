//! A local binding that is named like the root of an imported module path wins over the path.
//!
//! `import eval.deprecations` makes `eval.deprecations` a spelling of that module, so the parser joins
//! `eval.deprecations.items` into one qualified name. It reads the module path whether or not the function has a
//! local `eval`, because it knows no scopes. A function that does (`mut eval = ...`, or a parameter `eval: Evaluator`)
//! means the field chain `eval` `.deprecations` `.items`: the language's scoping rule is that the innermost binding of a
//! name is the one in force, and an import's path root is not a name the import binds (an alias is, and a local cannot
//! take an alias's name: `E_SHADOWING`).
//!
//! This pass runs once the whole module is parsed, when every function body is a tree and each block's bindings can be
//! followed exactly: a parameter lives for the function, a `const`, `mut` or typed declaration for the rest of its block,
//! a `for` variable, a `with ... as` name or a `match` payload for the body that follows. A qualified name whose first
//! segment is such a binding is rewritten to the tree the parser builds for an ordinary field access or method call on
//! it, so the checker and every other reader of the syntax see no difference. A qualified name with no such binding in
//! force is left as the parser built it, which is what keeps every program that works today working.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const subtree = @import("ast_subtree.zig");

/// Where the rewrite appends the nodes of a field chain, and what it needs to tell a path root from an alias.
pub const Request = struct {
    src: source.Source,
    tables: subtree.Tables,
    /// The module's import aliases and full dotted paths, as the parser registered them.
    aliases: *const std.StringHashMapUnmanaged(void),
};

/// Rewrite, in every function of `functions`, each qualified name or call whose first segment is a binding in force there.
pub fn resolve(allocator: std.mem.Allocator, request: Request, functions: []const ast.Function) std.mem.Allocator.Error!void {
    if (!hasCandidate(request)) return;
    var walker: Walker = .{ .allocator = allocator, .request = request };
    defer walker.scope.deinit(allocator);
    for (functions) |function| {
        walker.scope.clearRetainingCapacity();
        for (function.signature.parameters) |parameter| try walker.scope.append(allocator, request.src.text(parameter.name));
        try walker.statement(function.body);
    }
}

/// Whether some name or call spells a dotted path that starts at a path root: the only spellings the pass can change.
fn hasCandidate(request: Request) bool {
    for (request.tables.nodes.items) |node| {
        const text = switch (node.data) {
            .name => |span| request.src.text(span),
            .call => |call| request.src.text(call.owner orelse call.name),
            else => continue,
        };
        if (pathRoot(request, text) != null) return true;
    }
    return false;
}

/// The first segment of dotted `text` when it only begins an imported path: it is not itself an alias or a full path.
fn pathRoot(request: Request, text: []const u8) ?[]const u8 {
    const dot = std.mem.indexOfScalar(u8, text, '.') orelse return null;
    const first = text[0..dot];
    if (first.len == 0 or request.aliases.contains(first)) return null;
    return first;
}

const Walker = struct {
    allocator: std.mem.Allocator,
    request: Request,
    /// The names bound where the walk is, innermost last.
    scope: std.ArrayList([]const u8) = .empty,

    fn bound(self: *const Walker, name: []const u8) bool {
        var index = self.scope.items.len;
        while (index > 0) {
            index -= 1;
            if (std.mem.eql(u8, self.scope.items[index], name)) return true;
        }
        return false;
    }

    fn bind(self: *Walker, name: ?source.Span) std.mem.Allocator.Error!void {
        const span = name orelse return;
        const text = self.request.src.text(span);
        if (!std.mem.eql(u8, text, "_")) try self.scope.append(self.allocator, text);
    }

    /// Visit a statement. A `binding` adds its name to the scope it is in, for the statements after it; every other form
    /// leaves the scope as it found it, and the forms that bind for a body (`for`, `with`) end the name with the body.
    fn statement(self: *Walker, id: ast.StatementId) std.mem.Allocator.Error!void {
        switch (self.request.tables.statements.items[@backingInt(id)].data) {
            .block => |members| {
                const mark = self.scope.items.len;
                defer self.scope.shrinkRetainingCapacity(mark);
                for (members) |member| try self.statement(member);
            },
            .binding => |binding| {
                try self.expression(binding.value);
                try self.bind(binding.name);
            },
            .for_each => |each| {
                try self.expression(each.iterable);
                const mark = self.scope.items.len;
                defer self.scope.shrinkRetainingCapacity(mark);
                try self.bind(each.name);
                try self.bind(each.index_name);
                try self.statement(each.body);
            },
            .for_range => |range| {
                try self.expression(range.start);
                try self.expression(range.end);
                if (range.step) |step| try self.expression(step);
                const mark = self.scope.items.len;
                defer self.scope.shrinkRetainingCapacity(mark);
                try self.bind(range.name);
                try self.statement(range.body);
            },
            .with_scope => |scope| {
                if (scope.resource) |resource| try self.expression(resource);
                const mark = self.scope.items.len;
                defer self.scope.shrinkRetainingCapacity(mark);
                try self.bind(scope.name);
                try self.statement(scope.body);
            },
            .branch => |branch| {
                try self.expression(branch.condition);
                try self.scoped(branch.then_body);
                if (branch.else_body) |other| try self.scoped(other);
            },
            .loop => |loop| {
                try self.expression(loop.condition);
                try self.scoped(loop.body);
            },
            .match => |match| {
                try self.expression(match.value);
                try self.arms(match.arms);
            },
            .assertion => |assertion| {
                try self.expression(assertion.condition);
                if (assertion.value) |message| try self.expression(message);
            },
            .ret, .fail, .yield_value, .discard => |value| try self.expression(value),
            .assignment => |assignment| try self.expression(assignment.value),
            .gather_step => |step| {
                try self.expression(step.value);
                if (step.key) |key| try self.expression(key);
            },
            .loop_exit => {},
        }
    }

    /// Visit a statement that is a body of its own, so a binding it makes ends with it.
    fn scoped(self: *Walker, id: ast.StatementId) std.mem.Allocator.Error!void {
        const mark = self.scope.items.len;
        defer self.scope.shrinkRetainingCapacity(mark);
        try self.statement(id);
    }

    fn arms(self: *Walker, list: []const ast.MatchArm) std.mem.Allocator.Error!void {
        for (list) |arm| {
            const mark = self.scope.items.len;
            defer self.scope.shrinkRetainingCapacity(mark);
            for (arm.payload_patterns) |field| try self.patternNames(field.pattern);
            for (arm.literals) |literal| try self.expression(literal);
            try self.statement(arm.body);
            // The copies of a bare-name arm's body each see the arm's scope too; `group` is another arm's own body.
            for (arm.alternatives.name_bodies) |copy| try self.statement(copy);
        }
    }

    fn patternNames(self: *Walker, pattern: ast.Pattern) std.mem.Allocator.Error!void {
        switch (pattern.data) {
            .binding => |name| try self.bind(name),
            .variant => |variant| for (variant.fields) |field| try self.patternNames(field.pattern),
        }
    }

    fn expression(self: *Walker, id: ast.NodeId) std.mem.Allocator.Error!void {
        const index = @backingInt(id);
        const node = self.request.tables.nodes.items[index];
        switch (node.data) {
            .name => try self.qualifiedName(id),
            .call => |call| {
                try self.qualifiedCall(id);
                // The rewrite may have replaced the node; its argument expressions are the same either way.
                for (call.arguments) |argument| try self.expression(argument);
            },
            .match_expression => |match| {
                try self.expression(match.value);
                try self.arms(match.arms);
            },
            .variant_test => |test_node| {
                try self.expression(test_node.value);
                try self.statement(test_node.check);
            },
            .gather => |gather| try self.statement(gather.loop),
            .comprehension => |comprehension| {
                const mark = self.scope.items.len;
                defer self.scope.shrinkRetainingCapacity(mark);
                switch (comprehension.source) {
                    .iterable => |iterable| try self.expression(iterable),
                    .range => |bounds| {
                        try self.expression(bounds.start);
                        try self.expression(bounds.end);
                        if (bounds.step) |step| try self.expression(step);
                    },
                }
                try self.bind(comprehension.name);
                try self.expression(comprehension.output);
                if (comprehension.filter) |filter| try self.expression(filter);
            },
            else => try self.children(ast.Node, node),
        }
    }

    /// Visit every expression and statement a value of type `T` holds, in the order they are written.
    fn children(self: *Walker, comptime T: type, value: T) std.mem.Allocator.Error!void {
        if (T == ast.NodeId) return self.expression(value);
        if (T == ast.StatementId) return self.statement(value);
        if (T == source.Span) return;
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| try self.children(Field, @field(value, name)),
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), name)) try self.children(Field, @field(value, name));
            },
            .optional => |optional| if (value) |present| try self.children(optional.child, present),
            .pointer => |pointer| if (pointer.size == .slice and pointer.child != u8) for (value) |item| try self.children(pointer.child, item),
            .array => |array| for (value) |item| try self.children(array.child, item),
            else => {},
        }
    }

    /// `eval.deprecations.items` with a local `eval`: the field chain `eval` `.deprecations` `.items`.
    fn qualifiedName(self: *Walker, id: ast.NodeId) std.mem.Allocator.Error!void {
        const span = self.request.tables.nodes.items[@backingInt(id)].data.name;
        const text = self.request.src.text(span);
        const first = pathRoot(self.request, text) orelse return;
        if (!self.bound(first) or !plainSegments(text)) return;
        const last = std.mem.lastIndexOfScalar(u8, text, '.').?;
        const base = try self.chain(span.start, text[0..last]);
        const member: source.Span = .{ .start = span.start + last + 1, .end = span.end };
        self.request.tables.nodes.items[@backingInt(id)].data = .{ .field = .{ .base = base, .name = member } };
    }

    /// A call spelled with a qualified name or owner: `eval.deprecations.note(x)` and `eval.deprecations.items.append(x)`
    /// with a local `eval` call a method on the field chain, the tree the parser builds for any other receiver.
    fn qualifiedCall(self: *Walker, id: ast.NodeId) std.mem.Allocator.Error!void {
        const call = self.request.tables.nodes.items[@backingInt(id)].data.call;
        if (call.type_arguments.len != 0) return;
        const spelled = call.owner orelse call.name;
        const text = self.request.src.text(spelled);
        const first = pathRoot(self.request, text) orelse return;
        if (!self.bound(first) or !plainSegments(text)) return;
        // The receiver is the owner, or, for a qualified name, everything before the last segment; one segment left is a
        // plain local, which the parser spells as an owner and a method name.
        const receiver_end = if (call.owner != null) text.len else std.mem.lastIndexOfScalar(u8, text, '.').?;
        const method: source.Span = if (call.owner != null) call.name else .{ .start = spelled.start + receiver_end + 1, .end = spelled.end };
        const receiver = text[0..receiver_end];
        if (std.mem.indexOfScalar(u8, receiver, '.') == null) {
            self.request.tables.nodes.items[@backingInt(id)].data = .{ .call = .{
                .argument_names = call.argument_names,
                .evaluation_order = call.evaluation_order,
                .owner = .{ .start = spelled.start, .end = spelled.start + receiver_end },
                .name = method,
                .arguments = call.arguments,
            } };
            return;
        }
        const base = try self.chain(spelled.start, receiver);
        self.request.tables.nodes.items[@backingInt(id)].data = .{ .method_call = .{
            .base = base,
            .name = method,
            .arguments = call.arguments,
            .argument_names = call.argument_names,
        } };
    }

    /// Append the nodes of the access `a.b.c` whose text starts at `start`, and return the last one.
    fn chain(self: *Walker, start: usize, text: []const u8) std.mem.Allocator.Error!ast.NodeId {
        const tables = self.request.tables;
        var segments = std.mem.splitScalar(u8, text, '.');
        const head = segments.next().?;
        var end = start + head.len;
        try tables.nodes.append(tables.growth, .{ .span = .{ .start = start, .end = end }, .data = .{ .name = .{ .start = start, .end = end } } });
        var previous: ast.NodeId = @fromBackingInt(tables.nodes.items.len - 1);
        while (segments.next()) |segment| {
            const member: source.Span = .{ .start = end + 1, .end = end + 1 + segment.len };
            end = member.end;
            try tables.nodes.append(tables.growth, .{ .span = .{ .start = start, .end = end }, .data = .{ .field = .{ .base = previous, .name = member } } });
            previous = @fromBackingInt(tables.nodes.items.len - 1);
        }
        return previous;
    }
};

/// Whether every segment of dotted `text` is a plain name: no space, no empty segment.
fn plainSegments(text: []const u8) bool {
    var segments = std.mem.splitScalar(u8, text, '.');
    while (segments.next()) |segment| {
        if (segment.len == 0) return false;
        for (segment) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

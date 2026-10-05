//! Whether a counting `for` loop's body can rebind its loop variable
//! (`PY-FOR-REBIND-1`).
//!
//! Python rebinds a loop variable from the iterator at the top of every
//! iteration, so a body assignment to it never changes which iteration comes
//! next. A `range` induction variable or an `enumerate` position that the body
//! never assigns *is* the loop's counter: it is immutable, the backend keeps
//! it as the one induction value, and `PY-ARRAY-NEGATIVE-1` may rely on it
//! never being negative. When the body can assign it, the checker counts on a
//! hidden local instead and copies it into the visible variable at the top of
//! each iteration. The decision is made from the syntax before the body is
//! checked, because the variable's mutability has to be fixed first.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");

/// The syntax a scan reads: the parsed program and the text its spans name.
pub const Syntax = struct { program: ast.Program, src: source.Source };

/// Whether any statement of `body`, at any nesting depth, can assign `name`:
/// a plain or augmented assignment, an annotated binding, or a destructuring
/// target list naming it. Place writes (`name[i] = v`, `name.f = v`) count too,
/// so the answer never misses a write to a scalar or array loop variable. A
/// nested loop, `with` block or `match` arm cannot rebind an active name
/// (`E_SHADOWING`), so every write found here is a write to the loop's own
/// variable.
pub fn assigns(allocator: std.mem.Allocator, syntax: Syntax, body: ast.StatementId, name: []const u8) std.mem.Allocator.Error!bool {
    var work: std.ArrayList(ast.StatementId) = .empty;
    defer work.deinit(allocator);
    try work.append(allocator, body);
    while (work.pop()) |id| {
        const statement = syntax.program.statements.items[@backingInt(id)];
        const written = switch (statement.data) {
            .assignment => |assignment| named(syntax, assignment.name, name),
            .binding => |binding| named(syntax, binding.name, name),
            .discard => |value| writesNode(syntax, value, name),
            else => false,
        };
        if (written) return true;
        try ast.appendNested(allocator, &work, statement);
    }
    return false;
}

/// Whether an expression statement is an assignment whose target, or one of
/// whose destructuring targets, is rooted at `name`.
fn writesNode(syntax: Syntax, id: ast.NodeId, name: []const u8) bool {
    const node = syntax.program.nodes.items[@backingInt(id)];
    const target = switch (node.data) {
        .field_assignment => |assignment| assignment.target,
        .index_assignment => |assignment| assignment.target,
        .list_operation => |operation| if (operation.kind == .write) operation.base else return false,
        else => return false,
    };
    const target_node = syntax.program.nodes.items[@backingInt(target)];
    if (target_node.data == .tuple) {
        for (target_node.data.tuple) |element| if (rootedAt(syntax, element, name)) return true;
        return false;
    }
    return rootedAt(syntax, target, name);
}

/// Whether a place starts at the named root, including fields and indices.
pub fn rootedAt(syntax: Syntax, id: ast.NodeId, name: []const u8) bool {
    var at = id;
    for (0..64) |_| switch (syntax.program.nodes.items[@backingInt(at)].data) {
        .name => |span| return named(syntax, span, name),
        .field => |field| at = field.base,
        .index => |index| at = index.base,
        else => return false,
    };
    return true;
}

/// Whether the body replaces the root binding itself; writes below it stay live.
pub fn rebinds(allocator: std.mem.Allocator, syntax: Syntax, body: ast.StatementId, name: []const u8) std.mem.Allocator.Error!bool {
    var work: std.ArrayList(ast.StatementId) = .empty;
    defer work.deinit(allocator);
    try work.append(allocator, body);
    while (work.pop()) |id| {
        const statement = syntax.program.statements.items[@backingInt(id)];
        const replaced = switch (statement.data) {
            .assignment => |assignment| assignment.op == .set and named(syntax, assignment.name, name),
            .binding => |binding| named(syntax, binding.name, name),
            .discard => |value| destructures(syntax, value, name),
            else => false,
        };
        if (replaced) return true;
        try ast.appendNested(allocator, &work, statement);
    }
    return false;
}

fn destructures(syntax: Syntax, id: ast.NodeId, name: []const u8) bool {
    const node = syntax.program.nodes.items[@backingInt(id)];
    if (node.data != .field_assignment) return false;
    const target = syntax.program.nodes.items[@backingInt(node.data.field_assignment.target)];
    if (target.data != .tuple) return false;
    for (target.data.tuple) |part| {
        const item = syntax.program.nodes.items[@backingInt(part)];
        if (item.data == .name and named(syntax, item.data.name, name)) return true;
    }
    return false;
}

fn named(syntax: Syntax, span: source.Span, name: []const u8) bool {
    return std.mem.eql(u8, syntax.src.text(span), name);
}

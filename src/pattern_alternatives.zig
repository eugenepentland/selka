//! The alternatives of a `case`: `case leaf | blank:` and `case text(value) | code(value):`.
//!
//! The parser makes one arm per alternative, each with a copy of the body, and marks the arms of one list with
//! `group`. Exhaustiveness, duplicate arms and code generation then see ordinary arms. What the list adds is its own
//! contract: every alternative binds the same names, so the one body can read them whichever alternative matched.
//! A list of bare names reaches here as a literal arm (it is a list of constants when the matched value is an
//! integer, a string or a bool), and `splitNames` turns it into one arm per case when the value is an enum or a union.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The code of a `|` list whose alternatives bind different names or different types.
pub const code = "E_ALTERNATIVE_BINDINGS";

const Error = diagnostic.Error;

/// A literal arm that lists only bare names, as the cases of an enum or a union they name: one payload-free arm for
/// each name, the first with the arm's body and the rest with the copies the parser made. Arms that are not such a
/// list are returned as they are, and `arms` itself when there is none.
pub fn splitNames(allocator: std.mem.Allocator, nodes: []const ast.Node, arms: []const ast.MatchArm) std.mem.Allocator.Error![]const ast.MatchArm {
    var any = false;
    for (arms) |arm| any = any or isNameList(nodes, arm);
    if (!any) return arms;
    var out: std.ArrayList(ast.MatchArm) = .empty;
    for (arms) |arm| {
        if (!isNameList(nodes, arm)) {
            try out.append(allocator, arm);
            continue;
        }
        for (arm.literals, 0..) |literal, position| {
            const name = nodes[@backingInt(literal)].data.name;
            try out.append(allocator, .{
                .ty = .{ .start = name.start, .end = name.start },
                .name = name,
                .body = if (position == 0) arm.body else arm.alternatives.name_bodies[position - 1],
                .alternatives = .{ .group = arm.body },
            });
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Whether an arm is a literal arm of two or more bare names whose copies of the body the parser made.
fn isNameList(nodes: []const ast.Node, arm: ast.MatchArm) bool {
    if (arm.literals.len < 2 or arm.alternatives.name_bodies.len + 1 != arm.literals.len) return false;
    for (arm.literals) |literal| if (nodes[@backingInt(literal)].data != .name) return false;
    return true;
}

/// Refuse a `|` list whose alternatives do not bind the same names. Under `match mut` the alternatives must bind the
/// same fields too, because each binding writes into its own alternative's payload: a name bound to a different field
/// would be a write to a place the other alternatives do not have.
pub fn requireSameBindings(allocator: std.mem.Allocator, sink: *diagnostic.Sink, src: source.Source, arms: []const ast.MatchArm, exclusive: bool) Error!void {
    for (arms, 0..) |arm, position| {
        const group = arm.alternatives.group orelse continue;
        const first = firstOf(arms, position, group) orelse continue;
        if (first == position) continue;
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(allocator);
        var earlier: std.ArrayList([]const u8) = .empty;
        defer earlier.deinit(allocator);
        try bound(allocator, src, arm.payload_patterns, &names, exclusive, 0);
        try bound(allocator, src, arms[first].payload_patterns, &earlier, exclusive, 0);
        if (sameNames(names.items, earlier.items)) continue;
        const message = if (exclusive)
            "every alternative of a `match mut` arm binds the same fields under the same names: each binding writes into its own alternative's payload"
        else
            "every alternative of a `|` arm binds the same names, so the body can read them whichever alternative matched";
        return sink.failRelated(code, arm.name, message, .{ .span = arms[first].name, .message = "the first alternative binds these names" });
    }
}

/// The position of the first arm of the list `group` names, searching up to `at`.
fn firstOf(arms: []const ast.MatchArm, at: usize, group: ast.StatementId) ?usize {
    for (arms[0 .. at + 1], 0..) |arm, position| {
        if (arm.alternatives.group) |other| if (other == group) return position;
    }
    return null;
}

/// Append the names a pattern list binds. Under `match mut` a name is joined to its field label, so the comparison
/// sees which field each name writes.
fn bound(allocator: std.mem.Allocator, src: source.Source, fields: []const ast.PatternField, out: *std.ArrayList([]const u8), with_labels: bool, depth: usize) std.mem.Allocator.Error!void {
    if (depth > 32) return;
    for (fields) |field| switch (field.pattern.data) {
        .binding => |binding| {
            const name = binding orelse continue;
            if (!with_labels) {
                try out.append(allocator, src.text(name));
                continue;
            }
            const label = if (field.name) |given| src.text(given) else src.text(name);
            try out.append(allocator, try std.fmt.allocPrint(allocator, "{s}={s}", .{ label, src.text(name) }));
        },
        .variant => |nested| try bound(allocator, src, nested.fields, out, with_labels, depth + 1),
    };
}

/// Whether two lists hold the same names, in any order.
fn sameNames(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left) |name| {
        var found = false;
        for (right) |other| found = found or std.mem.eql(u8, name, other);
        if (!found) return false;
    }
    return true;
}

/// Whether an arm's pattern, or a pattern nested in it, ends with the rest marker `..`.
pub fn spellsRest(arm: ast.MatchArm) bool {
    return arm.alternatives.rest or nestedSpellsRest(arm.payload_patterns, 0);
}

/// Whether a pattern nested in a payload ends with the rest marker.
pub fn nestedSpellsRest(fields: []const ast.PatternField, depth: usize) bool {
    if (depth > 32) return false;
    for (fields) |field| switch (field.pattern.data) {
        .variant => |nested| if (nested.rest or nestedSpellsRest(nested.fields, depth + 1)) return true,
        .binding => {},
    };
    return false;
}

/// `items` and one more pattern field, in a fresh slice.
pub fn appendField(allocator: std.mem.Allocator, items: []const ast.PatternField, extra: ast.PatternField) std.mem.Allocator.Error![]ast.PatternField {
    const grown = try allocator.alloc(ast.PatternField, items.len + 1);
    @memcpy(grown[0..items.len], items);
    grown[items.len] = extra;
    return grown;
}

/// `items` and one more optional span, in a fresh slice.
pub fn appendSpan(allocator: std.mem.Allocator, items: []const ?source.Span, extra: ?source.Span) std.mem.Allocator.Error![]?source.Span {
    const grown = try allocator.alloc(?source.Span, items.len + 1);
    @memcpy(grown[0..items.len], items);
    grown[items.len] = extra;
    return grown;
}

/// A discard of a declared field: the pattern field the rest marker stands for, labelled with the declaration's name.
pub fn discardOf(declaration: source.Span) ast.PatternField {
    return .{ .name = declaration, .pattern = .{ .span = declaration, .data = .{ .binding = null } } };
}

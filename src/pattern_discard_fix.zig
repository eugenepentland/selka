//! The repair of a `match` pattern's binding that nothing reads (lane FR45). A pattern binds names by position or by field, and the
//! language ignores a payload in one way for each: `_` for the payload of an `Option`, a `Result` or a `result` declaration's case,
//! `field=_` for a field of an enum case (a bare `_` there is `E_FRONTEND_VARIANT`). The edit is offered where the written pattern says
//! which of the two it is, and a shape that is not certain keeps the plain message and gets no edit.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// How deep a nested pattern is followed: a pattern the parser accepts is far shallower.
const depth_limit = 64;

/// One binding a written pattern introduces: the case whose payload it names, and whether the source gave it a label.
const Site = struct { case: source.Span, labelled: bool };

/// How a case's payload is spelled in a pattern, over every type that declares a case of the name.
const Shape = enum { positional, fielded, unknown };

/// What the edit writes: `_` for a single payload, `_` for a field the pattern labels, `name=_` for a field it names bare.
const Spelling = enum { payload, field, named };

/// The message and the one edit that ignore an unread pattern binding.
pub const Repair = struct { message: []const u8, edit: diagnostic.Edit };

/// The repair of `local`, an unread binding, or null when it is not the binding of a written pattern, its type must be handled
/// (`_` there is `E_RESULT_DISCARD`), a `match mut` arm writes it, or the pattern does not say how its payload is ignored. The pattern
/// is found in the body that holds the binding (`ast.scanAt` fills it, a body being read only when asked for, `lazy_readers.zig`). A
/// bind-or-else's success arm (`const x = f() else ...`) names its declaration, not a pattern, and an arm of a `case a(x) | b(x):`
/// list is left alone: one edit there without the others would make the alternatives bind different names (`E_ALTERNATIVE_BINDINGS`).
pub fn repair(allocator: std.mem.Allocator, src: source.Source, syntax: ast.Program, records: []const typed.Record, local: typed.Local) std.mem.Allocator.Error!?Repair {
    if (local.usage.writes != 0 or typed.requiresHandling(local.ty, records)) return null;
    if (!std.mem.eql(u8, src.text(local.declaration), local.name)) return null;
    const site = try siteOf(syntax, local.declaration.start) orelse return null;
    const spelling: Spelling = if (site.labelled) .field else switch (shape(src.text(site.case), records)) {
        .positional => .payload,
        .fielded => .named,
        .unknown => return null,
    };
    const text = if (spelling == .named) try std.fmt.allocPrint(allocator, "{s}=_", .{local.name}) else "_";
    const advice = switch (spelling) {
        .payload => "write `_` in its place to ignore the payload",
        .field => "write `_` in its place to ignore this field",
        .named => try std.fmt.allocPrint(allocator, "write `{s}` in its place to ignore this field", .{text}),
    };
    const message = try std.fmt.allocPrint(allocator, "binding `{s}` is never read; {s}", .{ local.name, advice });
    return .{ .message = message, .edit = .{ .span = local.declaration, .text = text } };
}

/// The pattern field that binds the name starting at offset `start`, found among the arms of the `match` statements and expressions of
/// the body that holds it.
fn siteOf(syntax: ast.Program, start: usize) std.mem.Allocator.Error!?Site {
    const scan = try ast.scanAt(syntax, start);
    for (syntax.statements.items[scan.statement_start..scan.statement_end]) |statement| {
        if (statement.data == .match) if (inArms(statement.data.match.arms, start)) |site| return site;
    }
    for (syntax.nodes.items[scan.node_start..scan.node_end]) |node| {
        if (node.data == .match_expression) if (inArms(node.data.match_expression.arms, start)) |site| return site;
    }
    return null;
}

fn inArms(arms: []const ast.MatchArm, start: usize) ?Site {
    for (arms) |arm| {
        if (arm.alternatives.role == .success or arm.alternatives.group != null or arm.internal.wildcard) continue;
        if (inFields(arm.name, arm.payload_patterns, start, 0)) |site| return site;
    }
    return null;
}

fn inFields(case: source.Span, patterns: []const ast.PatternField, start: usize, depth: usize) ?Site {
    if (depth > depth_limit) return null;
    for (patterns) |field| switch (field.pattern.data) {
        .binding => |binding| {
            const span = binding orelse continue;
            if (span.start == start) return .{ .case = case, .labelled = field.name != null };
        },
        .variant => |nested| if (inFields(nested.name, nested.fields, start, depth + 1)) |site| return site,
    };
    return null;
}

/// How a pattern spells the payload of the case called `name`: by position when every type with such a case declares one payload
/// (`Some`, `Ok`, `Err` always are), by field when every one declares named fields, and unknown when they disagree or none is known.
fn shape(name: []const u8, records: []const typed.Record) Shape {
    var positional = std.mem.eql(u8, name, "Some") or std.mem.eql(u8, name, "Ok") or std.mem.eql(u8, name, "Err");
    var fielded = false;
    for (records) |record| {
        const variants = record.shape.variants orelse continue;
        for (variants.cases) |case| {
            if (case.payload == null or !std.mem.eql(u8, case.name, name)) continue;
            if (case.fielded) fielded = true else positional = true;
        }
    }
    if (positional == fielded) return .unknown;
    return if (positional) .positional else .fielded;
}

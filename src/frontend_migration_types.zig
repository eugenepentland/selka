//! Shared canonical type rendering for structured frontend migrations.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const Span = source.Span;

fn same(left: Span, right: Span) bool {
    return left.start == right.start and left.end == right.end;
}

/// Render one parsed type with canonical collection suffixes. Type identities,
/// argument order and optional nesting are preserved; only spelling changes.
pub fn renderType(allocator: std.mem.Allocator, src: source.Source, expressions: ast.TypeExpressions, span: Span) std.mem.Allocator.Error![]const u8 {
    const original = src.text(span);
    if (std.mem.eql(u8, original, "None")) return "Unit";
    for (expressions.suffixes) |suffix| {
        if (!same(suffix.span, span)) continue;
        const base = try renderType(allocator, src, expressions, suffix.base);
        if (std.mem.eql(u8, base, src.text(suffix.base))) return original;
        return std.mem.concat(allocator, u8, &.{ base, if (suffix.kind == .growable) "[]" else "?" });
    }
    for (expressions.arrays) |array| {
        if (!same(array.span, span)) continue;
        const length = switch (array.index) {
            .length => |length| length,
            .enum_type => return original,
        };
        const element = try renderType(allocator, src, expressions, array.element);
        if (original.len > 0 and original[0] != '[' and std.mem.eql(u8, element, src.text(array.element))) return original;
        return std.fmt.allocPrint(allocator, "FixedArray[{s}, {s}]", .{ element, src.text(length) });
    }
    for (expressions.applications) |application| {
        if (!same(application.span, span)) continue;
        const name = src.text(application.name);
        if (application.arguments.len == 1 and (std.mem.eql(u8, name, "list") or std.mem.eql(u8, name, "Option"))) {
            const element = try renderType(allocator, src, expressions, application.arguments[0]);
            return std.mem.concat(allocator, u8, &.{ element, if (std.mem.eql(u8, name, "list")) "[]" else "?" });
        }
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        var changed = false;
        try out.appendSlice(allocator, name);
        try out.append(allocator, '[');
        for (application.arguments, 0..) |argument, index| {
            if (index != 0) try out.appendSlice(allocator, ", ");
            const rendered = try renderType(allocator, src, expressions, argument);
            changed = changed or !std.mem.eql(u8, rendered, src.text(argument));
            try out.appendSlice(allocator, rendered);
        }
        try out.append(allocator, ']');
        if (!changed) {
            out.deinit(allocator);
            return original;
        }
        return out.toOwnedSlice(allocator);
    }
    return original;
}

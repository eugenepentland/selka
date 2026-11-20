//! Source spellings for abstract control-expression migration results.
const std = @import("std");
const source = @import("source.zig");
/// Render abstract types before any specialization so repairs remain root-independent.
pub fn symbolicSpelling(
    allocator: std.mem.Allocator,
    src: source.Source,
    span: source.Span,
    value: @import("symbolic_types.zig").Value,
    parameters: []const @import("generic_requirements.zig").Parameter,
    catalog: @import("type_catalog.zig").Catalog,
) std.mem.Allocator.Error!?[]const u8 {
    return switch (value) {
        .concrete => |ty| try typedSpelling(allocator, src, span, ty, catalog),
        .parameter => |index| src.text(parameters[index].name),
        .nominal => |nominal| blk: {
            const name = src.text(catalog.templates.store.?.index.declarations.items[nominal.declaration].name);
            var text: std.ArrayList(u8) = .empty;
            try text.appendSlice(allocator, name);
            try text.append(allocator, '[');
            for (nominal.arguments, 0..) |argument, index| {
                if (index > 0) try text.appendSlice(allocator, ", ");
                try text.appendSlice(allocator, try symbolicSpelling(allocator, src, span, argument, parameters, catalog) orelse return null);
            }
            try text.append(allocator, ']');
            break :blk try text.toOwnedSlice(allocator);
        },
        .array => |array| blk: {
            const element = try symbolicSpelling(allocator, src, span, array.element, parameters, catalog) orelse return null;
            const length = if (array.length_parameter) |index| src.text(parameters[index].name) else try std.fmt.allocPrint(allocator, "{d}", .{array.length});
            if (array.key != null) break :blk null;
            break :blk try std.fmt.allocPrint(allocator, "FixedArray[{s}, {s}]", .{ element, length });
        },
        .length => |length| try std.fmt.allocPrint(allocator, "{d}", .{length}),
        .length_parameter => |index| src.text(parameters[index].name),
        else => null,
    };
}

/// Render a checked type in the owning original module's source namespace.
pub fn typedSpelling(
    allocator: std.mem.Allocator,
    src: source.Source,
    span: source.Span,
    ty: @import("typed.zig").Type,
    catalog: @import("type_catalog.zig").Catalog,
) std.mem.Allocator.Error!?[]const u8 {
    const rendered = try @import("typed.zig").surfaceTypeName(allocator, ty, catalog.records);
    const names = catalog.module_names orelse return rendered;
    const origin = src.originalSpan(span) catch return null;
    const module = names.index.project.modules.items[origin.input].name;
    const prefix = try std.fmt.allocPrint(allocator, "{s}.", .{module});
    const spelling = try @import("migration_support.zig").localTypeText(allocator, rendered, prefix);
    return spelling;
}

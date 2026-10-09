//! Compilation-arena nominal identities shared by symbolic checking and late specialization.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const templates = @import("nominal_templates.zig");
const layouts = @import("nominal_layouts.zig");
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const Context = struct { allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names };
const Identity = struct { ty: ?typed.Type = null, name: ?[]const u8 = null, visible: bool = false };
const Identities = struct {
    items: std.ArrayList(Identity) = .empty,
    by_type: std.AutoHashMapUnmanaged(typed.Type, layouts.Id) = .empty,
    name_bytes: usize = 0,
};
/// Compilation-arena state retained through function specialization; source, names and sink are borrowed.
pub const Store = struct {
    context: Context,
    index: *templates.Index,
    graph: *layouts.Graph,
    identities: Identities = .{},
    /// Look up the semantic identity of an already materialized runtime type.
    pub fn semantic(self: Store, ty: typed.Type) ?layouts.Id {
        return self.identities.by_type.get(ty);
    }
    /// Look up a materialized runtime type without inventing storage for phantom arguments.
    pub fn runtime(self: Store, id: layouts.Id) ?typed.Type {
        return if (@backingInt(id) < self.identities.items.items.len) self.identities.items.items[@backingInt(id)].ty else null;
    }
    /// The runtime type of `id` when it already has one and the graph gained no node
    /// since the last catalog completion, so completing again would change nothing.
    pub fn settled(self: Store, id: layouts.Id) ?typed.Type {
        if (self.graph.nodes.items.len != self.identities.items.items.len) return null;
        return self.runtime(id);
    }
    /// Intern a runtime argument, including numeric arrays created by function specialization.
    pub fn typeArgument(self: *Store, records: []const typed.Record, ty: typed.Type, span: source.Span, depth: usize) Error!layouts.Id {
        if (self.semantic(ty)) |id| return id;
        if (depth == 256) return self.context.sink.fail(diagnostic.generic_limit, span, "nominal argument shape exceeds 256 levels");
        const id = if (!ty.isAggregate()) try self.graph.materialize(.{ .builtin = ty }, span) else array: {
            if (records[ty.recordIndex()].contract.callback) |contract| {
                var arguments: [17]layouts.Id = undefined;
                for (contract.parameters, 0..) |parameter, i| arguments[i] = try self.typeArgument(records, parameter, span, depth + 1);
                arguments[contract.parameters.len] = try self.typeArgument(records, contract.return_type, span, depth + 1);
                break :array try self.graph.materializeKey(.{ .base = .{ .callback = .{
                    .effects = contract.effects,
                    .labels = contract.labels,
                    .mutates = contract.mutates,
                    .return_origin = contract.return_origin,
                } }, .arguments = arguments[0 .. contract.parameters.len + 1] }, span);
            }
            if (records[ty.recordIndex()].shape.tuple) {
                const fields = records[ty.recordIndex()].fields;
                var arguments: [8]layouts.Id = undefined;
                for (fields, 0..) |field, i| arguments[i] = try self.typeArgument(records, field.ty, span, depth + 1);
                break :array try self.graph.materializeKey(.{ .base = .{ .tuple = {} }, .arguments = arguments[0..fields.len] }, span);
            }
            const shape = records[ty.recordIndex()].shape.array orelse return error.InternalError;
            const element = try self.typeArgument(records, shape.element, span, depth + 1);
            const key = if (shape.key) |key_type| try self.typeArgument(records, key_type, span, depth + 1) else null;
            break :array try self.graph.materializeKey(.{ .base = .{ .array = .{ .length = shape.length, .key = key } }, .arguments = &.{element} }, span);
        };
        try self.identities.by_type.put(self.context.allocator, ty, id);
        return id;
    }
};

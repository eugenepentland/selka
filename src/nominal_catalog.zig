//! Materialize complete concrete runtime schemas without turning phantom identities into records.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const templates = @import("nominal_templates.zig");
const layouts = @import("nominal_layouts.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const Context = struct { allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names };
const Identities = struct { types: []?typed.Type, names: []?[]const u8, visible: []bool, name_bytes: usize = 0 };
const Builder = struct {
    context: Context,
    index: *const templates.Index,
    graph: *const layouts.Graph,
    catalog: *Catalog,
    identities: Identities,

    fn declarationName(self: Builder, span: source.Span) Error![]const u8 {
        return if (self.context.names) |names| names.declaration(span) else self.context.src.text(span);
    }
    fn appendName(self: *Builder, id: usize) Error!void {
        const node = self.graph.nodes.items[id];
        const allocator = self.context.allocator;
        var base: []const u8 = undefined;
        var array_prefix: ?[]u8 = null;
        defer if (array_prefix) |prefix| allocator.free(prefix);
        switch (node.key.base) {
            .parameter => return,
            .builtin => |ty| {
                self.identities.names[id] = @tagName(ty);
                self.identities.types[id] = ty;
                return;
            },
            .named => |declaration| base = try self.declarationName(self.index.declarations.items[declaration].name),
            .array => |array| {
                if (array.key) |key| {
                    const key_name = self.identities.names[@backingInt(key)] orelse return;
                    array_prefix = try std.fmt.allocPrint(allocator, "[{s}]", .{key_name});
                } else array_prefix = try std.fmt.allocPrint(allocator, "[{d}]", .{array.length});
                base = array_prefix.?;
            },
        }
        var size = base.len;
        for (node.key.arguments) |argument| {
            const name = self.identities.names[@backingInt(argument)] orelse return;
            if (name.len > 1048576 - @min(size, 1048576)) return self.nameLimit(node.site);
            size += name.len;
        }
        const punctuation = if (node.key.base == .named and node.key.arguments.len != 0) node.key.arguments.len + 1 else 0;
        if (size > 1048576 - @min(punctuation + self.identities.name_bytes, 1048576)) return self.nameLimit(node.site);
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        output.writer.writeAll(base) catch return error.OutOfMemory;
        if (node.key.base == .named and node.key.arguments.len != 0) output.writer.writeByte('<') catch return error.OutOfMemory;
        for (node.key.arguments, 0..) |argument, i| {
            if (i != 0) output.writer.writeByte(',') catch return error.OutOfMemory;
            output.writer.writeAll(self.identities.names[@backingInt(argument)].?) catch return error.OutOfMemory;
        }
        if (node.key.base == .named and node.key.arguments.len != 0) output.writer.writeByte('>') catch return error.OutOfMemory;
        self.identities.names[id] = try output.toOwnedSlice();
        self.identities.name_bytes += size + punctuation;
    }
    fn nameLimit(self: Builder, span: source.Span) Error {
        return self.context.sink.fail(diagnostic.generic_limit, span, "nominal type display names exceed the 1 MiB compilation budget");
    }
    fn publicBase(self: Builder, id: usize) Error!bool {
        const names = self.context.names orelse return true;
        const declaration = self.index.declarations.items[id];
        const original = self.context.src.originalSpan(declaration.name) catch return error.InternalError;
        const unit = names.index.units[original.input];
        const symbol = unit.names.get(self.context.src.text(declaration.name)) orelse return error.InternalError;
        return unit.symbols.items[symbol].exported;
    }
    fn publicArguments(self: Builder, node: layouts.Node) bool {
        for (node.key.arguments) |argument| if (!self.identities.visible[@backingInt(argument)]) return false;
        if (node.key.base == .array) if (node.key.base.array.key) |key| return self.identities.visible[@backingInt(key)];
        return true;
    }
    fn identify(self: *Builder) Error!void {
        var count: usize = 0;
        for (self.graph.nodes.items, 0..) |node, i| {
            try self.appendName(i);
            const base_visible = switch (node.key.base) {
                .parameter => false,
                .named => |id| try self.publicBase(id),
                else => true,
            };
            self.identities.visible[i] = base_visible and self.publicArguments(node);
            if (self.identities.names[i] == null or node.key.base == .builtin or node.state != .complete) continue;
            self.identities.types[i] = @fromBackingInt(typed.Type.record_base + count);
            count += 1;
        }
        const allocator = self.context.allocator;
        self.catalog.records = try allocator.alloc(typed.Record, count);
        self.catalog.record_capacity = count;
        self.catalog.field_names = try allocator.alloc(std.StringHashMapUnmanaged(usize), count);
        @memset(self.catalog.field_names, .empty);
        for (self.graph.nodes.items, 0..) |node, i| {
            const ty = self.identities.types[i] orelse continue;
            if (!ty.isAggregate()) continue;
            self.catalog.records[ty.recordIndex()] = .{ .id = ty, .name = self.identities.names[i].?, .declaration = node.site, .fields = &.{}, .contract = .{ .public_arguments = self.publicArguments(node) } };
            if (node.key.base == .named and node.key.arguments.len == 0) try self.catalog.names.put(allocator, self.identities.names[i].?, ty);
        }
        for (self.index.declarations.items) |declaration| {
            if (declaration.parameters.len != 0) try self.catalog.template_names.put(allocator, try self.declarationName(declaration.name), declaration.name);
        }
    }
    fn runtimeType(self: Builder, id: layouts.Id) Error!typed.Type {
        return self.identities.types[@backingInt(id)] orelse error.InternalError;
    }
    fn named(self: Builder, declaration: usize) Error!typed.Type {
        const id = self.graph.index.get(.{ .base = .{ .named = declaration }, .arguments = &.{} }) orelse return error.InternalError;
        return self.runtimeType(id);
    }
    fn fields(self: Builder, node: layouts.Node, schema: *typed.Record, declaration: templates.Declaration) Error!void {
        const allocator = self.context.allocator;
        const fields_out = try allocator.alloc(typed.Field, declaration.fields.len);
        for (declaration.fields, fields_out, node.edges, 0..) |field, *out, edge, i| {
            const name = self.context.src.text(field.name);
            out.* = .{ .name = name, .declaration = field.name, .ty = try self.runtimeType(edge.target) };
            try self.catalog.field_names[schema.id.recordIndex()].put(allocator, name, i);
        }
        schema.fields = fields_out;
    }
    fn variants(self: Builder, node: layouts.Node, schema: *typed.Record, declaration: templates.Declaration) Error!void {
        const allocator = self.context.allocator;
        const cases = try allocator.alloc(typed.Variant, declaration.fields.len);
        var edge: usize = 0;
        for (declaration.fields, cases, 0..) |field, *out, i| {
            const name = self.context.src.text(field.name);
            out.* = .{ .name = name, .declaration = field.name, .payload = null };
            if (field.ty != null) {
                out.payload = try self.runtimeType(node.edges[edge].target);
                edge += 1;
            }
            try self.catalog.field_names[schema.id.recordIndex()].put(allocator, name, i);
        }
        schema.shape.variants = .{ .fallible = declaration.kind == .result, .is_union = declaration.kind != .enumeration, .cases = cases };
    }
    fn fillArray(self: Builder, node: layouts.Node, schema: *typed.Record) Error!void {
        const shape = node.key.base.array;
        const key = if (shape.key) |id| try self.runtimeType(id) else null;
        const element = try self.runtimeType(node.key.arguments[0]);
        schema.shape.array = .{ .length = shape.length, .element = element, .key = key };
        if (shape.key) |key_id| {
            const declaration = self.index.declarations.items[self.graph.nodes.items[@backingInt(key_id)].key.base.named];
            const fields_out = try self.context.allocator.alloc(typed.Field, declaration.fields.len);
            for (declaration.fields, fields_out) |field, *out| out.* = .{ .name = self.context.src.text(field.name), .declaration = field.name, .ty = element };
            schema.fields = fields_out;
        }
        try self.catalog.arrays.shapes.put(self.context.allocator, schema.shape.array.?, schema.id);
    }
    fn special(self: Builder, declaration: templates.Declaration, schema: *typed.Record) Error!void {
        switch (declaration.kind) {
            .domain => {
                for (self.context.program.types.domains) |domain| if (domain.name.start == declaration.name.start) {
                    const backing = try self.catalog.resolve(self.context.src, domain.backing, self.context.sink);
                    if (!backing.isInteger() and backing != .bool) return self.context.sink.fail("E_DOMAIN_BASE", domain.backing, "domain backing must be a built-in integer or bool");
                    schema.shape.domain = backing;
                    return;
                };
            },
            .resource => {
                for (self.context.program.types.resources) |resource| if (resource.name.start == declaration.name.start) {
                    schema.shape.resource = std.meta.stringToEnum(@import("external_resources.zig").Kind, self.context.src.text(resource.backing)) orelse return self.context.sink.fail(
                        "E_RESOURCE_KIND",
                        resource.backing,
                        "resource kind must be filesystem or network",
                    );
                    return;
                };
            },
            else => {},
        }
        return error.InternalError;
    }
    fn fill(self: *Builder) Error!void {
        for (self.graph.nodes.items, 0..) |node, i| {
            const ty = self.identities.types[i] orelse continue;
            if (!ty.isAggregate()) continue;
            const schema = &self.catalog.records[ty.recordIndex()];
            if (node.key.base == .array) {
                try self.fillArray(node, schema);
                continue;
            }
            const id = node.key.base.named;
            const declaration = self.index.declarations.items[id];
            schema.declaration = declaration.name;
            switch (declaration.kind) {
                .record => try self.fields(node, schema, declaration),
                .variants, .result, .enumeration => try self.variants(node, schema, declaration),
                .buffer => schema.shape.buffer = try self.runtimeType(node.edges[0].target),
                .pool => schema.shape.pool = .{ .element = try self.runtimeType(node.edges[0].target), .handle = try self.named(id + 1) },
                .handle => schema.shape.handle_pool = try self.named(id - 1),
                .domain, .resource => try self.special(declaration, schema),
            }
        }
    }
};
/// Build complete concrete schemas using the same ownership/layout validator as ordinary declarations.
pub fn collect(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names) Error!Catalog {
    var index = try templates.collect(allocator, src, program, sink, names);
    var graph = try layouts.collect(allocator, &index, sink);
    defer graph.deinit();
    var catalog: Catalog = .{ .module_names = names, .records = &.{}, .names = .empty, .field_names = &.{} };
    const sources = try @import("nominal_sources.zig").collect(allocator, src, program, &index, &graph, sink);
    catalog.arrays.templates = sources.array_templates;
    const ids = try allocator.alloc(?typed.Type, graph.nodes.items.len);
    @memset(ids, null);
    const type_names = try allocator.alloc(?[]const u8, graph.nodes.items.len);
    @memset(type_names, null);
    const visible = try allocator.alloc(bool, graph.nodes.items.len);
    @memset(visible, false);
    var builder: Builder = .{
        .context = .{ .allocator = allocator, .src = src, .program = program, .sink = sink, .names = names },
        .index = &index,
        .graph = &graph,
        .catalog = &catalog,
        .identities = .{ .types = ids, .names = type_names, .visible = visible },
    };
    try builder.identify();
    var resolved = sources.resolved.iterator();
    while (resolved.next()) |entry| try catalog.arrays.resolved.put(allocator, entry.key_ptr.*, try builder.runtimeType(entry.value_ptr.*));
    try builder.fill();
    try @import("record_layouts.zig").validate(allocator, catalog.records, sink);
    return catalog;
}

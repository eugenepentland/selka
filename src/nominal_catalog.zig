//! Materialize complete concrete runtime schemas without turning phantom identities into records.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const templates = @import("nominal_templates.zig");
const byte_buffer_name = templates.byte_buffer_name;
const layouts = @import("nominal_layouts.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const Names = @import("module_names.zig").Names;
const Error = diagnostic.Error;
const Store = @import("nominal_state.zig").Store;
const callables = @import("callables.zig");
const Context = @FieldType(Store, "context");
const Identities = @FieldType(Store, "identities");
const Builder = struct {
    context: Context,
    index: *const templates.Index,
    graph: *const layouts.Graph,
    catalog: *Catalog,
    identities: *Identities,

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
            .callback => {
                try self.appendCallbackName(id, node);
                return;
            },
            .parameter => return,
            .length => |value| {
                self.identities.items.items[id].name = try std.fmt.allocPrint(allocator, "{d}", .{value});
                return;
            },
            .builtin => |ty| {
                self.identities.items.items[id].name = @tagName(ty);
                self.identities.items.items[id].ty = ty;
                return;
            },
            .named => |declaration| base = self.index.declarations.items[declaration].builtin_name orelse try self.declarationName(self.index.declarations.items[declaration].name),
            .array => |array| {
                if (array.length_parameter != null) return;
                if (array.key) |key| {
                    const key_name = self.identities.items.items[@backingInt(key)].name orelse return;
                    array_prefix = try std.fmt.allocPrint(allocator, "[{s}]", .{key_name});
                } else array_prefix = try std.fmt.allocPrint(allocator, "[{d}]", .{array.length});
                base = array_prefix.?;
            },
        }
        var size = base.len;
        for (node.key.arguments) |argument| {
            const name = self.identities.items.items[@backingInt(argument)].name orelse return;
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
            output.writer.writeAll(self.identities.items.items[@backingInt(argument)].name.?) catch return error.OutOfMemory;
        }
        if (node.key.base == .named and node.key.arguments.len != 0) output.writer.writeByte('>') catch return error.OutOfMemory;
        self.identities.items.items[id].name = try output.toOwnedSlice();
        self.identities.name_bytes += size + punctuation;
    }
    /// Render a callback schema in the same canonical source form used by diagnostics.
    fn appendCallbackName(self: *Builder, id: usize, node: layouts.Node) Error!void {
        const allocator = self.context.allocator;
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        output.writer.writeAll("def(") catch return error.OutOfMemory;
        const parameter_count = node.key.arguments.len - 1;
        for (node.key.arguments[0..parameter_count], 0..) |argument, index| {
            if (index != 0) output.writer.writeAll(", ") catch return error.OutOfMemory;
            const parameter_name = self.identities.items.items[@backingInt(argument)].name orelse return;
            output.writer.writeAll(parameter_name) catch return error.OutOfMemory;
        }
        output.writer.writeAll(") -> ") catch return error.OutOfMemory;
        const result_name = self.identities.items.items[@backingInt(node.key.arguments[parameter_count])].name orelse return;
        output.writer.writeAll(result_name) catch return error.OutOfMemory;
        output.writer.writeAll(" effects(") catch return error.OutOfMemory;
        callables.writeEffects(&output.writer, node.key.base.callback.effects) catch return error.OutOfMemory;
        output.writer.writeByte(')') catch return error.OutOfMemory;
        callables.writeMutates(&output.writer, node.key.base.callback.mutates) catch return error.OutOfMemory;
        const name = try output.toOwnedSlice();
        if (name.len > 1024 * 1024) return self.nameLimit(node.site);
        self.identities.items.items[id].name = name;
        self.identities.name_bytes += name.len;
    }
    fn nameLimit(self: Builder, span: source.Span) Error {
        return self.context.sink.fail(diagnostic.generic_limit, span, "nominal type display names exceed the 1 MiB compilation budget");
    }
    fn publicBase(self: Builder, id: usize) Error!bool {
        const declaration = self.index.declarations.items[id];
        if (declaration.builtin_name != null) return true;
        const names = self.context.names orelse return true;
        const original = self.context.src.originalSpan(declaration.name) catch return error.InternalError;
        const unit = names.index.units[original.input];
        const symbol = unit.names.get(self.context.src.text(declaration.name)) orelse return error.InternalError;
        return unit.symbols.items[symbol].exported;
    }
    fn publicArguments(self: Builder, node: layouts.Node) bool {
        for (node.key.arguments) |argument| if (!self.identities.items.items[@backingInt(argument)].visible) return false;
        if (node.key.base == .array) if (node.key.base.array.key) |key| return self.identities.items.items[@backingInt(key)].visible;
        return true;
    }
    fn identify(self: *Builder) Error!void {
        const allocator = self.context.allocator;
        const old = self.identities.items.items.len;
        try self.identities.items.resize(allocator, self.graph.nodes.items.len);
        @memset(self.identities.items.items[old..], .{});
        for (self.graph.nodes.items[old..], old..) |node, i| {
            try self.appendName(i);
            const base_visible = switch (node.key.base) {
                .parameter => false,
                .named => |id| try self.publicBase(id),
                else => true,
            };
            self.identities.items.items[i].visible = base_visible and self.publicArguments(node);
        }
        var storage: std.ArrayList(typed.Record) = .{ .items = self.catalog.records, .capacity = self.catalog.record_capacity };
        defer {
            self.catalog.records = storage.items;
            self.catalog.record_capacity = storage.capacity;
        }
        for (self.graph.nodes.items, 0..) |node, i| {
            const identity = &self.identities.items.items[i];
            if (node.key.base == .length) continue;
            if (identity.ty != null or identity.name == null or node.state != .complete) continue;
            if (node.key.base == .array) {
                const array = node.key.base.array;
                const shape: typed.Array = .{
                    .length = array.length,
                    .element = try self.runtimeType(node.key.arguments[0]),
                    .key = if (array.key) |key| try self.runtimeType(key) else null,
                };
                if (self.catalog.arrays.shapes.get(shape)) |found| {
                    identity.ty = found;
                    continue;
                }
            }
            if (node.key.base == .callback) {
                var parameters: [16]typed.Type = undefined;
                for (node.key.arguments[0 .. node.key.arguments.len - 1], 0..) |argument, argument_index| parameters[argument_index] = try self.runtimeType(argument);
                const contract: typed.Callable = .{
                    .parameters = parameters[0 .. node.key.arguments.len - 1],
                    .return_type = try self.runtimeType(node.key.arguments[node.key.arguments.len - 1]),
                    .effects = node.key.base.callback.effects,
                    .mutates = node.key.base.callback.mutates,
                    .return_origin = node.key.base.callback.return_origin,
                };
                for (storage.items) |record| if (record.contract.callback) |existing| {
                    if (callables.equal(existing, contract)) {
                        identity.ty = record.id;
                        break;
                    }
                };
                if (identity.ty != null) continue;
            }
            const ty: typed.Type = @fromBackingInt(typed.Type.record_base + storage.items.len);
            try storage.append(allocator, .{
                .id = ty,
                .name = identity.name.?,
                .declaration = node.site,
                .fields = &.{},
                .contract = .{ .public_arguments = self.publicArguments(node) },
            });
            identity.ty = ty;
            if (node.key.base == .named and node.key.arguments.len == 0 and !self.index.isSynthetic(node.key.base.named)) try self.catalog.names.put(allocator, identity.name.?, ty);
        }
        const indexed = self.catalog.field_names.items.len;
        try self.catalog.field_names.resize(allocator, storage.items.len);
        @memset(self.catalog.field_names.items[indexed..], .empty);
        for (self.identities.items.items, 0..) |identity, i| if (identity.ty) |ty| try self.identities.by_type.put(allocator, ty, @fromBackingInt(i));
    }
    fn complete(self: *Builder) Error!void {
        const first = self.catalog.records.len;
        try self.identify();
        try self.fill(first);
        try @import("record_layouts.zig").validate(self.context.allocator, self.catalog.records, self.context.sink);
    }
    fn runtimeType(self: Builder, id: layouts.Id) Error!typed.Type {
        return self.identities.items.items[@backingInt(id)].ty orelse error.InternalError;
    }
    fn named(self: Builder, declaration: usize, arguments: []const layouts.Id) Error!typed.Type {
        const id = self.graph.index.get(.{ .base = .{ .named = declaration }, .arguments = arguments }) orelse return error.InternalError;
        return self.runtimeType(id);
    }
    fn fields(self: Builder, node: layouts.Node, schema: *typed.Record, declaration: templates.Declaration) Error!void {
        const allocator = self.context.allocator;
        const fields_out = try allocator.alloc(typed.Field, declaration.fields.len);
        for (declaration.fields, fields_out, node.edges, 0..) |field, *out, edge, i| {
            const name = field.builtin_name orelse self.context.src.text(field.name);
            out.* = .{ .name = name, .declaration = field.name, .ty = try self.runtimeType(edge.target), .default_value = field.default_value };
            try self.catalog.field_names.items[schema.id.recordIndex()].put(allocator, name, i);
        }
        schema.fields = fields_out;
    }
    fn variants(self: Builder, node: layouts.Node, schema: *typed.Record, declaration: templates.Declaration) Error!void {
        const allocator = self.context.allocator;
        const cases = try allocator.alloc(typed.Variant, declaration.fields.len);
        var edge: usize = 0;
        for (declaration.fields, cases, 0..) |field, *out, i| {
            const name = field.builtin_name orelse self.context.src.text(field.name);
            out.* = .{ .name = name, .declaration = field.name, .payload = null, .fielded = field.ty != null and field.ty.? == .named and self.index.isSynthetic(field.ty.?.named) };
            if (field.ty != null) {
                out.payload = try self.runtimeType(node.edges[edge].target);
                edge += 1;
            }
            try self.catalog.field_names.items[schema.id.recordIndex()].put(allocator, name, i);
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
            for (declaration.fields, fields_out) |field, *out| out.* = .{ .name = self.context.src.text(field.name), .declaration = field.name, .ty = element, .default_value = field.default_value };
            schema.fields = fields_out;
        }
        try self.catalog.arrays.shapes.put(self.context.allocator, schema.shape.array.?, schema.id);
    }
    fn special(self: Builder, declaration: templates.Declaration, schema: *typed.Record) Error!void {
        switch (declaration.kind) {
            .domain => {
                if (declaration.builtin_name) |name| if (std.mem.eql(u8, name, "float")) {
                    schema.shape.domain = .u64;
                    return;
                };
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
    fn fill(self: *Builder, first: usize) Error!void {
        for (self.graph.nodes.items, 0..) |node, i| {
            const ty = self.identities.items.items[i].ty orelse continue;
            if (!ty.isAggregate() or ty.recordIndex() < first) continue;
            const schema = &self.catalog.records[ty.recordIndex()];
            if (node.key.base == .callback) {
                const parameters = try self.context.allocator.alloc(typed.Type, node.key.arguments.len - 1);
                for (node.key.arguments[0..parameters.len], parameters) |id, *out| out.* = try self.runtimeType(id);
                schema.shape.domain = .u64;
                schema.contract.callback = .{
                    .parameters = parameters,
                    .return_type = try self.runtimeType(node.key.arguments[parameters.len]),
                    .effects = node.key.base.callback.effects,
                    .mutates = node.key.base.callback.mutates,
                    .return_origin = node.key.base.callback.return_origin,
                };
                continue;
            }
            if (node.key.base == .array) {
                try self.fillArray(node, schema);
                continue;
            }
            const id = node.key.base.named;
            const declaration = self.index.declarations.items[id];
            schema.declaration = declaration.name;
            switch (declaration.kind) {
                .record => {
                    try self.fields(node, schema, declaration);
                    schema.managed = declaration.managed;
                    // A synthesized case-payload record borrows `builtin_name` for
                    // its display name but is an ordinary record, not the builtin Cell.
                    schema.shape.builtin_cell = if (declaration.builtin_name) |name| std.mem.eql(u8, name, "Cell") and !self.index.isSynthetic(id) else false;
                },
                .variants, .result, .enumeration => try self.variants(node, schema, declaration),
                .buffer => {
                    schema.shape.buffer = try self.runtimeType(node.edges[0].target);
                    schema.managed = declaration.managed;
                    if (declaration.builtin_name) |name| {
                        if (std.mem.eql(u8, name, "str")) schema.collection.kind = .string;
                        if (std.mem.eql(u8, name, "bytes")) schema.collection.kind = .bytes;
                        // The mutable octet buffer is a byte-kind buffer too: it
                        // shares the one-byte element descriptor and every read
                        // path, and only the method table separates it from the
                        // immutable byte string.
                        if (std.mem.eql(u8, name, "byte_buffer")) schema.collection.kind = .bytes;
                        if (std.mem.eql(u8, name, "dict")) {
                            schema.collection = .{ .kind = .dictionary, .key = schema.shape.buffer };
                            schema.shape.buffer = try self.runtimeType(node.edges[1].target);
                        }
                    }
                },
                .domain, .resource => try self.special(declaration, schema),
            }
        }
    }
};
/// Build complete concrete schemas using the same ownership/layout validator as ordinary declarations.
pub fn collect(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names) Error!Catalog {
    const index = try allocator.create(templates.Index);
    index.* = try templates.collect(allocator, src, program, sink, names);
    const graph = try allocator.create(layouts.Graph);
    graph.* = try layouts.collect(allocator, index, sink);
    _ = try graph.materialize(.{ .named = index.names.get("str").? }, .{ .start = 0, .end = 0 });
    if (index.names.get("bytes")) |declaration| {
        const builtin = index.declarations.items[declaration].builtin_name;
        if (builtin != null and std.mem.eql(u8, builtin.?, "bytes")) _ = try graph.materialize(.{ .named = declaration }, .{ .start = 0, .end = 0 });
    }
    _ = try graph.materialize(.{ .named = index.names.get("float").? }, .{ .start = 0, .end = 0 });
    const store = try allocator.create(Store);
    store.* = .{ .context = .{ .allocator = allocator, .src = src, .program = program, .sink = sink, .names = names }, .index = index, .graph = graph };
    var catalog: Catalog = .{ .module_names = names, .records = &.{}, .names = .empty, .field_names = .empty };
    catalog.templates.store = store;
    const sources = try @import("nominal_sources.zig").collect(allocator, src, program, index, graph, sink);
    catalog.arrays.templates = sources.array_templates;
    catalog.templates.applications = sources.nominal_templates;
    for (index.declarations.items, 0..) |declaration, id| {
        if (index.isSynthetic(id)) continue;
        const name = declaration.builtin_name orelse if (names) |module| try module.declaration(declaration.name) else src.text(declaration.name);
        if (declaration.parameters.len != 0) try catalog.templates.names.put(allocator, name, declaration.name);
    }
    const alias_ids = try allocator.alloc(layouts.Id, program.types.expressions.aliases.len);
    defer allocator.free(alias_ids);
    for (program.types.expressions.aliases, alias_ids) |alias, *id| id.* = try graph.materialize(try index.expression(alias.name, &.{}), alias.name);
    var builder: Builder = .{ .context = store.context, .index = index, .graph = graph, .catalog = &catalog, .identities = &store.identities };
    try builder.identify();
    for (program.types.expressions.aliases, alias_ids) |alias, id| {
        const name = if (names) |module| try module.declaration(alias.name) else src.text(alias.name);
        try catalog.names.put(allocator, name, try builder.runtimeType(id));
    }
    var resolved = sources.resolved.iterator();
    while (resolved.next()) |entry| try catalog.arrays.resolved.put(allocator, entry.key_ptr.*, try builder.runtimeType(entry.value_ptr.*));
    try builder.fill(0);
    try @import("record_layouts.zig").validate(allocator, catalog.records, sink);
    return catalog;
}

/// Materialize ordered type identities and their optional constant length values.
pub fn instantiateLengths(catalog: *Catalog, declaration: usize, arguments: []const typed.Type, lengths: []const ?usize, span: source.Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    if (arguments.len != state.index.declarations.items[declaration].parameters.len) return error.InternalError;
    var ids: [16]layouts.Id = undefined;
    for (arguments, 0..) |argument, i| {
        if (lengths.len != 0 and lengths[i] != null) {
            ids[i] = try state.graph.materialize(.{ .length = lengths[i].? }, span);
        } else ids[i] = try state.typeArgument(catalog.records, argument, span, 0);
    }
    const id = try state.graph.materializeKey(.{ .base = .{ .named = declaration }, .arguments = ids[0..arguments.len] }, span);
    var builder: Builder = .{ .context = state.context, .index = state.index, .graph = state.graph, .catalog = catalog, .identities = &state.identities };
    try builder.complete();
    return builder.runtimeType(id);
}

/// Materialize a parameterless builtin prelude type on its first mention. The
/// mutable octet buffer is declared with the other prelude types so a module may
/// name it without an import, but a program that never names one keeps the
/// minimal unconditional type table, so its schema is built here rather than in
/// `collect`. Answers null for a name that is not such a builtin.
pub fn materializePrelude(catalog: *Catalog, name: []const u8, span: source.Span) Error!?typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    if (std.mem.eql(u8, name, byte_buffer_name) and !state.index.names.contains(byte_buffer_name)) try state.index.addByteBuffer();
    const declaration = state.index.names.get(name) orelse return null;
    const builtin = state.index.declarations.items[declaration].builtin_name orelse return null;
    if (!std.mem.eql(u8, builtin, name)) return null;
    const resolved = try instantiateLengths(catalog, declaration, &.{}, &.{}, span);
    return resolved;
}

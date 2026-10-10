//! Structural and provenance checks for the project-wide interface boundary.
const std = @import("std");
const value = @import("type_interface_value.zig");
const declaration = @import("declaration_value.zig");
const Span = @import("source.zig").Span;
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
/// Wire admission never converts malformed values into source diagnostics.
pub const Error = error{ OutOfMemory, ComponentProtocol };
const rows_limit = 65536;
const strings_limit = 8388608;
fn require(ok: bool) Error!void {
    if (!ok) return error.ComponentProtocol;
}
fn add(total: *usize, amount: usize, limit: usize) Error!void {
    try require(amount <= limit - total.*);
    total.* += amount;
}
fn span(at: Span, size: usize) Error!void {
    try require(at.start <= at.end and at.end <= size);
}
fn namedSpan(at: Span, size: usize) Error!void {
    try span(at, size);
    try require(at.start < at.end);
}
fn optionalSpan(at: ?Span, size: usize) Error!void {
    if (at) |location| try span(location, size);
}
fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
const Storage = struct { sources: usize = 0, strings: usize = 0 };
const Budget = struct {
    storage: Storage = .{},
    symbols: usize = 0,
    imports: usize = 0,
    declarations: usize = 0,
    types: usize = 0,
    nested: usize = 0,
};
/// Admit complete raw module/syntax facts without deciding semantic validity.
pub fn input(a: std.mem.Allocator, in: value.Input) Error!void {
    try require(in.modules.len <= 4096 and in.order.len == in.modules.len);
    const seen = try a.alloc(bool, in.modules.len);
    defer a.free(seen);
    @memset(seen, false);
    for (in.order) |id| {
        try require(id < seen.len);
        try require(!seen[id]);
        seen[id] = true;
    }
    const imported = try a.alloc(bool, in.modules.len);
    defer a.free(imported);
    @memset(imported, false);
    var import_count: usize = 0;
    for (in.modules) |module| {
        try require(module.imports.len <= 4096);
        try add(&import_count, module.imports.len, rows_limit);
        for (module.imports) |item| {
            try require(item.target < imported.len);
            imported[item.target] = true;
        }
    }
    var budget: Budget = .{};
    for (in.modules, 0..) |module, id| {
        try require(module.context.module == id and module.context.source.len <= 1048576);
        try require(module.context.name.len != 0);
        try require(module.context.path.len <= 16384 and module.context.is_imported == imported[id]);
        try add(&budget.storage.sources, module.context.source.len, strings_limit);
        try add(&budget.storage.strings, module.context.name.len, strings_limit);
        try add(&budget.storage.strings, module.context.path.len, strings_limit);
        try moduleFacts(a, in, module, &budget);
        try catalog(a, module, &budget);
    }
}
fn moduleFacts(a: std.mem.Allocator, in: value.Input, module: value.Module, budget: *Budget) Error!void {
    try require(module.imports.len <= 4096 and module.import_used.len == module.imports.len);
    try add(&budget.imports, module.imports.len, rows_limit);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(a);
    var aliases: std.StringHashMapUnmanaged(void) = .empty;
    defer aliases.deinit(a);
    for (module.imports) |item| {
        try require(item.target < in.modules.len);
        try span(item.span, module.context.source.len);
        try add(&budget.storage.strings, item.name.len, strings_limit);
        try add(&budget.storage.strings, item.alias.len, strings_limit);
        const name = try names.getOrPut(a, item.name);
        const alias = try aliases.getOrPut(a, item.alias);
        try require(!name.found_existing and !alias.found_existing);
    }
    names.clearRetainingCapacity();
    try add(&budget.symbols, module.symbols.len, rows_limit);
    for (module.symbols, 0..) |symbol, symbol_id| {
        try namedSpan(symbol.span, module.context.source.len);
        try require(symbol.name.len != 0);
        try add(&budget.storage.strings, symbol.name.len, strings_limit);
        if (symbol.owner) |owner| try add(&budget.storage.strings, owner.len, strings_limit);
        const found = try names.getOrPut(a, symbol.name);
        try require(!found.found_existing);
        if (symbol.re_export) |origin| {
            try require(origin.module < in.modules.len);
            try require(origin.symbol < in.modules[origin.module].symbols.len);
            const target = in.modules[origin.module].symbols[origin.symbol];
            try require(target.kind == symbol.kind and target.re_export == null);
            try require(origin.module != module.context.module or origin.symbol != symbol_id);
            try require(same(symbol.name, target.name) and symbol.owner == null and !symbol.restricted);
            try require(symbol.exported);
        } else {
            try symbolSource(module, symbol);
        }
    }
}
fn symbolSource(module: value.Module, symbol: declaration.Symbol) Error!void {
    const leaf = module.context.source[symbol.span.start..symbol.span.end];
    if (symbol.owner) |owner| {
        try require(symbol.kind == .function and symbol.name.len == owner.len + 1 + leaf.len);
        try require(std.mem.startsWith(u8, symbol.name, owner));
        try require(symbol.name[owner.len] == '.' and same(symbol.name[owner.len + 1 ..], leaf));
    } else try require(same(symbol.name, leaf));
}
fn spans(items: []const Span, size: usize, budget: *Budget) Error!void {
    try add(&budget.nested, items.len, rows_limit);
    for (items) |at| try span(at, size);
}
fn fields(items: []const value.Field, size: usize, budget: *Budget) Error!void {
    try add(&budget.nested, items.len, rows_limit);
    for (items) |item| {
        try namedSpan(item.name, size);
        try span(item.ty, size);
    }
}
fn generics(items: []const value.Generic, size: usize, budget: *Budget) Error!void {
    try add(&budget.nested, items.len, rows_limit);
    for (items) |item| try generic(item, size, budget);
}
fn generic(item: value.Generic, size: usize, budget: *Budget) Error!void {
    // Empty constraint subjects survive admission so Selka can report the native diagnostic.
    try span(item.name, size);
    try spans(item.requirements, size, budget);
    try fields(item.fields, size, budget);
    try add(&budget.nested, item.operations.len, rows_limit);
    for (item.operations) |operation| {
        try namedSpan(operation.name, size);
        try fields(operation.parameters, size, budget);
        try span(operation.return_type, size);
    }
    try add(&budget.nested, item.named.len, rows_limit);
    for (item.named) |reference| {
        try optionalSpan(reference.alias, size);
        try namedSpan(reference.name, size);
    }
}
fn catalog(a: std.mem.Allocator, module: value.Module, budget: *Budget) Error!void {
    const size = module.context.source.len;
    const items = module.syntax.declarations;
    inline for (.{ "records", "variants", "aliases", "domains", "constraints", "functions" }) |field| {
        const rows = @field(items, field);
        try add(&budget.declarations, rows.len, rows_limit);
        for (rows) |row| try namedSpan(row.name, size);
    }
    for (items.records) |item| {
        try generics(item.parameters, size, budget);
        try spans(item.fields, size, budget);
    }
    for (items.variants) |item| {
        try generics(item.parameters, size, budget);
        try add(&budget.nested, item.cases.len, rows_limit);
        for (item.cases) |case| {
            try optionalSpan(case.payload, size);
            try spans(case.fields, size, budget);
        }
    }
    inline for (.{ "aliases", "domains" }) |field| for (@field(items, field)) |item| try span(item.target, size);
    for (items.constraints) |item| {
        try add(&budget.nested, 1, rows_limit);
        try span(item.span, size);
        try generic(item.subject, size, budget);
    }
    for (items.functions) |item| {
        try optionalSpan(item.owner, size);
        try generics(item.parameters, size, budget);
        try spans(item.inputs, size, budget);
        try span(item.return_type, size);
        try optionalSpan(item.failure_type, size);
    }
    try typeCatalog(a, module, budget);
}
const Shape = struct { at: Span, children: []const Span, constructor_leaf: bool, kind: u8 };
fn inside(child: Span, parent: Span) bool {
    return child.start >= parent.start and child.end <= parent.end;
}
fn shapes(a: std.mem.Allocator, module: value.Module, budget: *Budget) Error![]Shape {
    const types = module.syntax.types;
    var rows: std.ArrayList(Shape) = .empty;
    errdefer {
        for (rows.items) |row| a.free(row.children);
        rows.deinit(a);
    }
    inline for (.{ "suffixes", "callbacks", "arrays", "applications", "tuples" }, 0..) |field, kind| {
        const items = @field(types, field);
        try add(&budget.types, items.len, rows_limit);
        for (items) |item| {
            try namedSpan(item.span, module.context.source.len);
            try add(&budget.nested, childCount(@TypeOf(item), item), rows_limit);
            const children = try childrenOf(a, item);
            errdefer a.free(children);
            for (children) |child| {
                try span(child, module.context.source.len);
                try require(inside(child, item.span));
                try require(!std.meta.eql(child, item.span));
            }
            if (@TypeOf(item) == value.Application) {
                try namedSpan(item.name, module.context.source.len);
                try require(inside(item.name, item.span) and !std.meta.eql(item.name, item.span));
            }
            try rows.append(a, .{ .at = item.span, .children = children, .constructor_leaf = @TypeOf(item) == value.Application, .kind = kind });
        }
    }
    return rows.toOwnedSlice(a);
}
fn childCount(comptime T: type, item: T) usize {
    if (T == value.Suffix) return 1;
    if (T == value.Callback) return item.parameters.len + 1 + @intFromBool(item.failure_type != null);
    if (T == value.Array) return 1 + @intFromBool(item.enum_index != null);
    if (T == value.Application) return item.arguments.len + 1;
    return item.elements.len;
}
fn childrenOf(a: std.mem.Allocator, item: anytype) Error![]Span {
    const T = @TypeOf(item);
    var children: std.ArrayList(Span) = .empty;
    errdefer children.deinit(a);
    if (T == value.Suffix) {
        try children.append(a, item.base);
    } else if (T == value.Callback) {
        try children.appendSlice(a, item.parameters);
        try children.append(a, item.return_type);
        if (item.failure_type) |at| try children.append(a, at);
    } else if (T == value.Array) {
        if (item.enum_index) |at| try children.append(a, at);
        try children.append(a, item.element);
    } else if (T == value.Application) {
        try children.appendSlice(a, item.arguments);
    } else {
        try children.appendSlice(a, item.elements);
    }
    return children.toOwnedSlice(a);
}
fn typeCatalog(a: std.mem.Allocator, module: value.Module, budget: *Budget) Error!void {
    const rows = try shapes(a, module, budget);
    defer {
        for (rows) |row| a.free(row.children);
        a.free(rows);
    }
    const Key = struct { kind: u8, span: Span };
    var keys: std.AutoHashMapUnmanaged(Key, void) = .empty;
    defer keys.deinit(a);
    var by_span: std.AutoHashMapUnmanaged(Span, usize) = .empty;
    defer by_span.deinit(a);
    for (rows, 0..) |row, id| {
        const key = try keys.getOrPut(a, .{ .kind = row.kind, .span = row.at });
        try require(!key.found_existing);
        const entry = try by_span.getOrPut(a, row.at);
        if (!entry.found_existing) entry.value_ptr.* = id;
    }
    const depths = try a.alloc(usize, rows.len);
    defer a.free(depths);
    @memset(depths, 0);
    for (rows, 0..) |_, id| _ = try depth(rows, by_span, depths, id, 1);
}
fn depth(rows: []const Shape, by_span: std.AutoHashMapUnmanaged(Span, usize), depths: []usize, id: usize, level: usize) Error!usize {
    try require(level <= 256);
    if (depths[id] != 0) return depths[id];
    var result: usize = if (rows[id].constructor_leaf) 2 else 1;
    for (rows[id].children) |at| {
        const child_depth = if (by_span.get(at)) |child| try depth(rows, by_span, depths, child, level + 1) else 1;
        result = @max(result, 1 + child_depth);
    }
    try require(result <= 256);
    depths[id] = result;
    return result;
}
const Queries = struct {
    types: std.AutoHashMapUnmanaged(Span, void) = .empty,
    references: std.AutoHashMapUnmanaged(Span, ?Span) = .empty,
    fn deinit(self: *Queries, a: std.mem.Allocator) void {
        self.types.deinit(a);
        self.references.deinit(a);
    }
    fn at(self: *Queries, a: std.mem.Allocator, location: Span) Error!void {
        try self.types.put(a, location, {});
    }
    fn optional(self: *Queries, a: std.mem.Allocator, location: ?Span) Error!void {
        if (location) |at_| try self.at(a, at_);
    }
    fn list(self: *Queries, a: std.mem.Allocator, locations: []const Span) Error!void {
        for (locations) |location| try self.at(a, location);
    }
    fn generic(self: *Queries, a: std.mem.Allocator, item: value.Generic) Error!void {
        for (item.fields) |field| try self.at(a, field.ty);
        for (item.operations) |operation| {
            for (operation.parameters) |field| try self.at(a, field.ty);
            try self.at(a, operation.return_type);
        }
        for (item.named) |reference| try self.references.put(a, reference.name, reference.alias);
    }
    fn generics(self: *Queries, a: std.mem.Allocator, items: []const value.Generic) Error!void {
        for (items) |item| try self.generic(a, item);
    }
    fn init(a: std.mem.Allocator, module: value.Module) Error!Queries {
        var result: Queries = .{};
        errdefer result.deinit(a);
        const declarations = module.syntax.declarations;
        for (declarations.records) |item| {
            try result.generics(a, item.parameters);
            try result.list(a, item.fields);
        }
        for (declarations.variants) |item| {
            try result.generics(a, item.parameters);
            for (item.cases) |case| {
                try result.optional(a, case.payload);
                try result.list(a, case.fields);
            }
        }
        inline for (.{ "aliases", "domains" }) |field| for (@field(declarations, field)) |item| try result.at(a, item.target);
        for (declarations.constraints) |item| try result.generic(a, item.subject);
        for (declarations.functions) |item| {
            try result.generics(a, item.parameters);
            try result.list(a, item.inputs);
            try result.at(a, item.return_type);
            try result.optional(a, item.failure_type);
        }
        const types = module.syntax.types;
        for (types.suffixes) |item| try result.at(a, item.base);
        for (types.callbacks) |item| {
            try result.list(a, item.parameters);
            try result.at(a, item.return_type);
            try result.optional(a, item.failure_type);
        }
        for (types.arrays) |item| {
            try result.optional(a, item.enum_index);
            try result.at(a, item.element);
        }
        for (types.applications) |item| {
            try result.at(a, item.name);
            try result.list(a, item.arguments);
        }
        for (types.tuples) |item| try result.list(a, item.elements);
        return result;
    }
};
const Namespace = struct {
    imports: std.StringHashMapUnmanaged(usize) = .empty,
    symbols: std.StringHashMapUnmanaged(usize) = .empty,
    queries: Queries,
    normalized: std.AutoHashMapUnmanaged(Span, lexer.Qualified) = .empty,
    fn init(a: std.mem.Allocator, module: value.Module) Error!Namespace {
        var result: Namespace = .{ .queries = try Queries.init(a, module) };
        errdefer result.deinit(a);
        for (module.imports, 0..) |item, id| {
            const alias = try result.imports.getOrPut(a, item.alias);
            if (!alias.found_existing) alias.value_ptr.* = id;
            const name = try result.imports.getOrPut(a, item.name);
            if (!name.found_existing) name.value_ptr.* = id;
        }
        for (module.symbols, 0..) |item, id| try result.symbols.put(a, item.name, id);
        return result;
    }
    fn deinit(self: *Namespace, a: std.mem.Allocator) void {
        self.imports.deinit(a);
        self.symbols.deinit(a);
        self.queries.deinit(a);
        self.normalized.deinit(a);
    }
};
/// Validate completed acknowledgements, successful provenance and exact diagnostic vocabulary.
pub fn outcome(a: std.mem.Allocator, in: value.Input, result: value.Outcome) Error!void {
    switch (result) {
        .failure => |problem| try failure(a, in, problem),
        .success => |output| try success(a, in, output),
    }
}
fn success(a: std.mem.Allocator, in: value.Input, output: value.Output) Error!void {
    try require(std.mem.eql(usize, output.order, in.order));
    try require(output.import_used.len == in.modules.len and output.resolutions.len <= rows_limit);
    const spaces = try a.alloc(Namespace, in.modules.len);
    defer a.free(spaces);
    var initialized: usize = 0;
    defer for (spaces[0..initialized]) |*space| space.deinit(a);
    const used = try a.alloc([]bool, in.modules.len);
    defer a.free(used);
    var copied: usize = 0;
    defer for (used[0..copied]) |flags| a.free(flags);
    for (in.modules, output.import_used, 0..) |module, flags, id| {
        try require(flags.len == module.imports.len);
        spaces[id] = try Namespace.init(a, module);
        initialized += 1;
        used[id] = try a.dupe(bool, module.import_used);
        copied += 1;
    }
    var strings: usize = 0;
    for (output.resolutions) |resolution| {
        try add(&strings, resolution.name.len, strings_limit);
        if (resolution.alias) |alias| try add(&strings, alias.len, strings_limit);
        try receipt(a, in, spaces, used, resolution);
    }
    for (used, output.import_used) |expected, actual| try require(std.mem.eql(bool, expected, actual));
}
fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if ((left == null) != (right == null)) return false;
    return if (left) |bytes| same(bytes, right.?) else true;
}
fn qualified(a: std.mem.Allocator, raw: []const u8) Error!lexer.Qualified {
    return switch (lexer.quickQualifiedName(raw)) {
        .name => |name| name,
        .none => error.ComponentProtocol,
        .slow => slow: {
            var arena = std.heap.ArenaAllocator.init(a);
            defer arena.deinit();
            var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
            const tokens = lexer.lex(arena.allocator(), raw, &sink) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.ComponentProtocol,
            };
            break :slow lexer.qualifiedName(raw, tokens) orelse return error.ComponentProtocol;
        },
    };
}
fn receipt(a: std.mem.Allocator, in: value.Input, spaces: []Namespace, used: [][]bool, item: value.Resolution) Error!void {
    try require(item.from < in.modules.len);
    const module = in.modules[item.from];
    try span(item.span, module.context.source.len);
    const raw = module.context.source[item.span.start..item.span.end];
    if (item.kind == .constraint) {
        const alias = spaces[item.from].queries.references.get(item.span) orelse return error.ComponentProtocol;
        const expected: ?[]const u8 = if (alias) |at| module.context.source[at.start..at.end] else null;
        try require(optionalBytesEqual(item.alias, expected) and same(item.name, raw));
    } else {
        try require(item.kind == .type and spaces[item.from].queries.types.contains(item.span));
        const normalized = try spaces[item.from].normalized.getOrPut(a, item.span);
        if (!normalized.found_existing) normalized.value_ptr.* = try qualified(a, raw);
        const name = normalized.value_ptr.*;
        try require(optionalBytesEqual(item.alias, name.alias) and same(item.name, name.name));
    }
    var target = item.from;
    if (item.alias) |alias| {
        const import_id = spaces[item.from].imports.get(alias) orelse return error.ComponentProtocol;
        target = module.imports[import_id].target;
        used[item.from][import_id] = true;
    }
    const id = spaces[target].symbols.get(item.name) orelse return error.ComponentProtocol;
    const symbol = in.modules[target].symbols[id];
    try require(symbol.kind == item.kind);
    const expected = symbol.re_export orelse declaration.Identity{ .module = target, .symbol = id };
    try require(std.meta.eql(item.identity, expected));
}
fn site(in: value.Input, at: declaration.Site) Error!void {
    try require(at.module < in.modules.len);
    try span(at.span, in.modules[at.module].context.source.len);
}
const Diagnostic = struct { code: []const u8, message: []const u8 };
const e_arity = "E_GENERIC_ARITY";
const e_requirement = "E_GENERIC_REQUIREMENT";
const diagnostics = [_]Diagnostic{
    .{ .code = "E_UNKNOWN_IMPORT", .message = "name does not identify a direct import alias" },
    .{ .code = "E_UNKNOWN_SYMBOL", .message = "declaration is not present in the resolved module" },
    .{ .code = "E_PRIVATE_SYMBOL", .message = "declaration is private to its module" },
    .{ .code = "E_PRIVATE_FUNCTION", .message = "private domain function requires the same declaring domain" },
    .{ .code = "E_SYMBOL_KIND", .message = "declaration has the wrong kind for this reference" },
    .{ .code = "E_PRIVATE_INTERFACE", .message = "exported interface exposes an unexported type" },
    .{ .code = "E_PRIVATE_INTERFACE", .message = "exported generic function exposes an unexported constraint" },
    .{ .code = e_arity, .message = "nominal type template requires explicit type arguments" },
    .{ .code = e_arity, .message = "type application argument count does not match its declaration" },
    .{ .code = e_arity, .message = "FixedArray requires an element type and length" },
    .{ .code = e_arity, .message = "builtin type argument count does not match" },
    .{ .code = "E_TYPE_APPLICATION", .message = "type parameters cannot be used as type constructors" },
    .{ .code = "E_GENERIC_PARAMETER", .message = "type parameter cannot shadow a builtin type" },
    .{ .code = "E_GENERIC_PARAMETER", .message = "duplicate type parameter" },
    .{ .code = "E_SHADOWING", .message = "type parameter shadows a module declaration" },
    .{ .code = "E_SHADOWING", .message = "type parameter shadows an import alias" },
    .{ .code = "E_GENERIC_LIMIT", .message = "at most 16 type parameters are permitted" },
    .{ .code = e_requirement, .message = "constant-length parameters cannot declare requirements" },
    .{ .code = e_requirement, .message = "unknown requirement; expected copy, equality, integer, codec, or storable" },
    .{ .code = e_requirement, .message = "unknown requirement; expected copy, equality, integer, codec, storable, or a declared constraint" },
    .{ .code = e_requirement, .message = "duplicate type requirement" },
    .{ .code = e_requirement, .message = "duplicate named constraint requirement" },
    .{ .code = e_requirement, .message = "nested named constraints are not supported in this version" },
    .{ .code = e_requirement, .message = "type parameter requires an explicit requirement" },
    .{ .code = e_requirement, .message = "named constraints may only bound function type parameters" },
    .{ .code = e_requirement, .message = "constraint requires exactly one subject binder" },
    .{ .code = e_requirement, .message = "a constraint right-hand side may not reference another named constraint" },
    .{ .code = e_requirement, .message = "structural field contracts require copy to exclude hidden ownership and result obligations" },
    .{ .code = e_requirement, .message = "duplicate structural field requirement" },
    .{ .code = e_requirement, .message = "duplicate structural operation requirement" },
    .{ .code = e_requirement, .message = "duplicate structural operation parameter" },
};
fn failure(a: std.mem.Allocator, in: value.Input, problem: declaration.Problem) Error!void {
    try site(in, problem.site);
    if (problem.related) |related| try site(in, related);
    var known = false;
    for (diagnostics) |item| if (same(item.code, problem.code) and same(item.message, problem.message)) {
        known = true;
    };
    try require(known);
    try associatedSite(a, in, problem.site);
    if (problem.related) |related| try associatedSite(a, in, related);
}
fn associatedSite(a: std.mem.Allocator, in: value.Input, location: declaration.Site) Error!void {
    const module = in.modules[location.module];
    var sites: std.AutoHashMapUnmanaged(Span, void) = .empty;
    defer sites.deinit(a);
    try collectSpans(a, &sites, module.syntax);
    for (module.symbols) |symbol| try sites.put(a, symbol.span, {});
    for (module.imports) |item| try sites.put(a, item.span, {});
    try require(sites.contains(location.span));
}
fn collectSpans(a: std.mem.Allocator, sites: *std.AutoHashMapUnmanaged(Span, void), item: anytype) Error!void {
    const T = @TypeOf(item);
    if (T == Span) {
        try sites.put(a, item, {});
    } else switch (@typeInfo(T)) {
        .@"struct" => {
            if (T == value.Reference) if (item.alias) |alias| try sites.put(a, .{ .start = alias.start, .end = item.name.end }, {});
            inline for (@typeInfo(T).@"struct".field_names) |field| try collectSpans(a, sites, @field(item, field));
        },
        .pointer => |pointer| {
            if (pointer.size == .slice) for (item) |child| try collectSpans(a, sites, child);
        },
        .optional => if (item) |child| try collectSpans(a, sites, child),
        else => {},
    }
}

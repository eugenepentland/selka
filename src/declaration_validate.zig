//! Structural admission for declaration values; declaration decisions remain in the producer.
const std = @import("std");
const value = @import("declaration_value.zig");
const Span = @import("source.zig").Span;
/// Invalid transport values are host failures, never source diagnostics.
pub const Error = error{ OutOfMemory, ComponentProtocol };
const source_limit = 1048576;
const row_limit = 65536;
const graph_limit = 4096;
fn require(ok: bool) Error!void {
    if (!ok) return error.ComponentProtocol;
}
fn span(at: Span, size: usize) Error!void {
    try require(at.start <= at.end and at.end <= size);
}
fn nameSpan(at: Span, size: usize) Error!void {
    try span(at, size);
    try require(at.start < at.end);
}
fn add(total: *usize, size: usize) Error!void {
    try require(size <= source_limit - total.*);
    total.* += size;
}
fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn sameSpan(a: Span, b: Span) bool {
    return std.meta.eql(a, b);
}
fn text(in: value.Input, at: Span) []const u8 {
    return in.context.source[at.start..at.end];
}
fn kind(category: value.Category) value.Kind {
    return switch (category) {
        .function => .function,
        .constraint => .constraint,
        else => .type,
    };
}
fn key(a: std.mem.Allocator, in: value.Input, item: value.Declaration) Error![]const u8 {
    return if (item.owner) |owner| try std.fmt.allocPrint(a, "{s}.{s}", .{ text(in, owner), text(in, item.span) }) else text(in, item.span);
}
/// Check complete profile counts, source ranges and direct-dependency identities before encoding.
pub fn input(a: std.mem.Allocator, in: value.Input) Error!void {
    try require(in.context.source.len <= source_limit and in.context.path.len <= 16384);
    try require(in.context.module <= std.math.maxInt(u32));
    try require(in.declarations.len <= row_limit and in.exports.len <= row_limit and in.public.len <= row_limit);
    try require(in.imports.len <= graph_limit and in.dependencies.len <= graph_limit);
    var total: usize = 0;
    try add(&total, in.context.name.len);
    var facades: usize = 0;
    for (in.declarations) |item| {
        try nameSpan(item.span, in.context.source.len);
        try require(item.category == .function or (item.owner == null and !item.restricted));
        if (item.owner) |owner| try nameSpan(owner, in.context.source.len);
        const size = item.span.end - item.span.start;
        try add(&total, size);
        if (item.owner) |owner| try add(&total, owner.end - owner.start + 1);
    }
    var modules: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer modules.deinit(a);
    var rows: usize = 0;
    for (in.dependencies) |dep| {
        try require(dep.module != in.context.module and dep.module <= std.math.maxInt(u32) and dep.source_len <= source_limit);
        const entry = try modules.getOrPut(a, dep.module);
        try require(!entry.found_existing);
        try add(&total, dep.name.len);
        try require(dep.symbols.len <= row_limit - rows);
        rows += dep.symbols.len;
        var names: std.StringHashMapUnmanaged(void) = .empty;
        defer names.deinit(a);
        for (dep.symbols) |symbol| {
            try nameSpan(symbol.span, dep.source_len);
            try require(symbol.name.len != 0);
            const found = try names.getOrPut(a, symbol.name);
            try require(!found.found_existing);
            try add(&total, symbol.name.len);
            if (symbol.owner) |owner| try add(&total, owner.len);
            if (symbol.re_export) |origin| try require(origin.module <= std.math.maxInt(u32) and origin.symbol < row_limit);
        }
    }
    var import_names: std.StringHashMapUnmanaged(void) = .empty;
    defer import_names.deinit(a);
    var import_aliases: std.StringHashMapUnmanaged(void) = .empty;
    defer import_aliases.deinit(a);
    for (in.imports) |item| {
        const name = try import_names.getOrPut(a, item.name);
        const alias = try import_aliases.getOrPut(a, item.alias);
        try require(!name.found_existing and !alias.found_existing);
        try span(item.span, in.context.source.len);
        try require(modules.contains(item.target));
        try add(&total, item.name.len);
        try add(&total, item.alias.len);
    }
    for (in.exports) |item| {
        try span(item.span, in.context.source.len);
        try add(&total, item.name.len);
        if (item.alias) |alias| {
            facades += 1;
            try add(&total, alias.len);
            try add(&total, item.name.len);
        }
    }
    try require(facades <= row_limit - in.declarations.len);
    for (in.public) |at| try nameSpan(at, in.context.source.len);
}
const Target = struct { symbol: value.Symbol, origin: value.Identity, import_id: usize };
const Catalog = struct {
    imports: std.StringHashMapUnmanaged(usize) = .empty,
    modules: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    symbols: []std.StringHashMapUnmanaged(usize),
    fn init(a: std.mem.Allocator, in: value.Input) Error!Catalog {
        var result: Catalog = .{ .symbols = try a.alloc(std.StringHashMapUnmanaged(usize), in.dependencies.len) };
        @memset(result.symbols, .empty);
        errdefer result.deinit(a);
        for (in.imports, 0..) |item, id| {
            const alias = try result.imports.getOrPut(a, item.alias);
            if (!alias.found_existing) alias.value_ptr.* = id;
            const name = try result.imports.getOrPut(a, item.name);
            if (!name.found_existing) name.value_ptr.* = id;
        }
        for (in.dependencies, 0..) |dep, id| {
            try result.modules.put(a, dep.module, id);
            for (dep.symbols, 0..) |symbol, symbol_id| try result.symbols[id].put(a, symbol.name, symbol_id);
        }
        return result;
    }
    fn deinit(self: *Catalog, a: std.mem.Allocator) void {
        self.imports.deinit(a);
        self.modules.deinit(a);
        for (self.symbols) |*table| table.deinit(a);
        a.free(self.symbols);
    }
    fn target(self: Catalog, in: value.Input, directive: value.Export) Error!Target {
        const import_id = self.imports.get(directive.alias orelse return error.ComponentProtocol) orelse return error.ComponentProtocol;
        const dep_id = self.modules.get(in.imports[import_id].target) orelse return error.ComponentProtocol;
        const dep = in.dependencies[dep_id];
        const id = self.symbols[dep_id].get(directive.name) orelse return error.ComponentProtocol;
        const symbol = dep.symbols[id];
        return .{ .symbol = symbol, .origin = symbol.re_export orelse .{ .module = dep.module, .symbol = id }, .import_id = import_id };
    }
};
/// Admit complete symbol tables and diagnostics with exact source/owner/origin correspondence.
pub fn outcome(a: std.mem.Allocator, in: value.Input, result: value.Outcome) Error!void {
    switch (result) {
        .failure => |problem| try failure(a, in, problem),
        .success => |output| try success(a, in, output),
    }
}
fn success(a: std.mem.Allocator, in: value.Input, output: value.Output) Error!void {
    try require(output.import_used.len == in.imports.len);
    var facades: usize = 0;
    for (in.exports) |item| if (item.alias != null) {
        facades += 1;
    };
    try require(output.symbols.len == in.declarations.len + facades);
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(a);
    for (output.symbols, 0..) |symbol, id| {
        const entry = try names.getOrPut(a, symbol.name);
        try require(!entry.found_existing);
        entry.value_ptr.* = id;
    }
    var position: usize = 0;
    inline for (std.meta.tags(value.Category)) |category| {
        for (in.declarations) |item| {
            if (item.category != category) continue;
            const symbol = output.symbols[position];
            position += 1;
            const expected = try key(a, in, item);
            defer if (item.owner != null) a.free(expected);
            try require(same(symbol.name, expected) and symbol.kind == kind(category));
            try require(sameSpan(symbol.span, item.span) and symbol.re_export == null and symbol.restricted == item.restricted);
            try require((symbol.owner == null) == (item.owner == null));
            if (item.owner) |owner| try require(same(symbol.owner.?, text(in, owner)));
        }
    }
    var catalog = try Catalog.init(a, in);
    defer catalog.deinit(a);
    const used = try a.alloc(bool, in.imports.len);
    defer a.free(used);
    @memset(used, false);
    for (in.exports) |item| {
        if (item.alias == null) continue;
        const resolved = try catalog.target(in, item);
        used[resolved.import_id] = true;
        const symbol = output.symbols[position];
        position += 1;
        try require(same(symbol.name, item.name) and sameSpan(symbol.span, item.span));
        try require(symbol.kind == resolved.symbol.kind and symbol.owner == null and !symbol.restricted and symbol.exported);
        try require(std.meta.eql(symbol.re_export, @as(?value.Identity, resolved.origin)));
    }
    try require(std.mem.eql(bool, used, output.import_used));
    var published: std.StringHashMapUnmanaged(void) = .empty;
    defer published.deinit(a);
    for (in.exports) |item| {
        try require(names.contains(item.name));
        try published.put(a, item.name, {});
    }
    for (in.public) |at| {
        try require(names.contains(text(in, at)));
        try published.put(a, text(in, at), {});
    }
    for (output.symbols) |symbol| {
        var exported = published.contains(symbol.name);
        if (symbol.owner) |owner| {
            const owner_id = names.get(owner) orelse return error.ComponentProtocol;
            exported = !symbol.restricted and output.symbols[owner_id].exported;
        }
        try require(symbol.exported == exported);
    }
}
fn localSite(in: value.Input, site: value.Site) Error!void {
    try require(site.module == in.context.module);
    try span(site.span, in.context.source.len);
}
fn failure(a: std.mem.Allocator, in: value.Input, problem: value.Problem) Error!void {
    try localSite(in, problem.site);
    const duplicate = same(problem.code, "E_DUPLICATE_SYMBOL") and same(problem.message, "module declaration name is already bound");
    const alias = same(problem.code, "E_IMPORT_ALIAS") and same(problem.message, "declaration conflicts with an import alias");
    const unknown = same(problem.code, "E_UNKNOWN_EXPORT") and (same(problem.message, "export names no local declaration") or
        same(problem.message, "re-export names no exported imported declaration") or same(problem.message, "public declaration names no local declaration"));
    const public = same(problem.code, "E_DUPLICATE_EXPORT") and same(problem.message, "declaration is already public");
    const private = (same(problem.code, "E_PRIVATE_SYMBOL") and same(problem.message, "declaration is private to its module")) or
        (same(problem.code, "E_PRIVATE_FUNCTION") and same(problem.message, "private domain function requires the same declaring domain"));
    try require(duplicate or alias or unknown or public or private);
    try require((problem.related != null) == (duplicate or alias or private));
    var site_matches = false;
    if (duplicate or alias) for (in.declarations) |item| {
        if (sameSpan(item.span, problem.site.span)) site_matches = true;
    };
    if (!alias) for (in.exports) |item| {
        const qualified_unknown = same(problem.message, "re-export names no exported imported declaration");
        const local_unknown = same(problem.message, "export names no local declaration");
        const eligible = if (unknown) (qualified_unknown and item.alias != null) or (local_unknown and item.alias == null) else !public or item.alias == null;
        if (eligible and sameSpan(item.span, problem.site.span)) site_matches = true;
    };
    if (unknown and same(problem.message, "public declaration names no local declaration")) for (in.public) |at| {
        if (sameSpan(at, problem.site.span)) site_matches = true;
    };
    try require(site_matches);
    if (problem.related) |related| {
        if (!private) {
            try localSite(in, related);
            if (alias) {
                for (in.imports) |item| if (sameSpan(item.span, related.span)) return;
            } else {
                for (in.declarations) |item| if (sameSpan(item.span, related.span)) return;
                for (in.exports) |item| if (item.alias != null and sameSpan(item.span, related.span)) return;
            }
            return error.ComponentProtocol;
        }
        try privateRelated(a, in, problem.site, related);
    }
}
fn privateRelated(a: std.mem.Allocator, in: value.Input, site: value.Site, related: value.Site) Error!void {
    var catalog = try Catalog.init(a, in);
    defer catalog.deinit(a);
    var target_matches = false;
    for (in.exports) |item| {
        if (item.alias == null or !sameSpan(item.span, site.span)) continue;
        const resolved = try catalog.target(in, item);
        const imported = in.imports[resolved.import_id];
        if (imported.target == related.module and sameSpan(resolved.symbol.span, related.span)) target_matches = true;
    }
    try require(target_matches);
    for (in.dependencies) |dep| {
        if (dep.module != related.module) continue;
        try span(related.span, dep.source_len);
        for (dep.symbols) |symbol| if (sameSpan(symbol.span, related.span)) return;
    }
    return error.ComponentProtocol;
}

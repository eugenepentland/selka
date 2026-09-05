//! Module declaration identities and export boundaries, before body type checking.
const std = @import("std");
const graph = @import("project.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const typed = @import("typed.zig");
pub const Kind = enum { type, function };
pub const Identity = struct { module: usize, symbol: usize };
pub const Symbol = struct { name: []const u8, kind: Kind, span: source.Span, exported: bool = false, owner: ?[]const u8 = null, restricted: bool = false };
pub const Unit = struct { syntax: ast.Program, symbols: std.ArrayList(Symbol) = .empty, names: std.StringHashMapUnmanaged(usize) = .empty };
/// Storage belongs to project.arena. Do not retain this index after project.deinit.
pub const Index = struct {
    project: *graph.Project,
    units: []Unit,
    fn add(self: *Index, module: usize, span: source.Span, kind: Kind, owner: ?source.Span, restricted: bool) diagnostic.Error!void {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        const name = src.text(span);
        const owner_name = if (owner) |at| src.text(at) else null;
        const key = if (owner_name) |prefix| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name }) else name;
        const unit = &self.units[module];
        if (unit.names.get(key)) |previous| return self.project.fail("E_DUPLICATE_SYMBOL", "module declaration name is already bound", .{ .module = module, .span = span }, .{ .module = module, .span = unit.symbols.items[previous].span });
        if (owner == null) for (self.project.modules.items[module].imports) |imported| {
            if (std.mem.eql(u8, name, imported.alias)) return self.project.fail("E_IMPORT_ALIAS", "declaration conflicts with an import alias", .{ .module = module, .span = span }, .{ .module = module, .span = imported.span });
        };
        try unit.names.put(allocator, key, unit.symbols.items.len);
        try unit.symbols.append(allocator, .{ .name = key, .kind = kind, .span = span, .owner = owner_name, .restricted = restricted });
    }
    /// Resolve a direct import alias or this module's own declaration namespace.
    /// Members use Domain.method; private domain members require the same owner.
    pub fn resolve(self: *Index, from: usize, alias: ?[]const u8, name: []const u8, kind: Kind, owner: ?[]const u8, span: source.Span) diagnostic.Error!Identity {
        var target = from;
        const site: graph.Site = .{ .module = from, .span = span };
        if (alias) |requested| {
            var found = false;
            for (self.project.modules.items[from].imports) |imported| {
                if (!std.mem.eql(u8, requested, imported.alias)) continue;
                target = imported.target;
                found = true;
                break;
            }
            if (!found) return self.project.fail("E_UNKNOWN_IMPORT", "name does not identify a direct import alias", site, null);
        }
        const symbol_id = self.units[target].names.get(name) orelse return self.project.fail("E_UNKNOWN_SYMBOL", "declaration is not present in the resolved module", site, null);
        const symbol = self.units[target].symbols.items[symbol_id];
        const declaration: graph.Site = .{ .module = target, .span = symbol.span };
        if (target != from and !symbol.exported) return self.project.fail("E_PRIVATE_SYMBOL", "declaration is private to its module", site, declaration);
        if (symbol.restricted and (target != from or owner == null or !std.mem.eql(u8, owner.?, symbol.owner.?))) return self.project.fail("E_PRIVATE_FUNCTION", "private domain function requires the same declaring domain", site, declaration);
        if (symbol.kind != kind) return self.project.fail("E_SYMBOL_KIND", "declaration has the wrong kind for this reference", site, declaration);
        return .{ .module = target, .symbol = symbol_id };
    }
    fn signatureType(self: *Index, module: usize, span: source.Span) diagnostic.Error!void {
        const syntax = self.units[module].syntax;
        for (syntax.array_types) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .enum_type) try self.signatureType(module, array.index.enum_type);
            return self.signatureType(module, array.element);
        }
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        if (typed.Type.fromName(src.text(span)) != null) return;
        // Re-lex this short name to normalize whitespace/comments around ::.
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, src.text(span), &sink);
        const text = src.text(span);
        const alias = if (tokens.len == 5) text[tokens[0].span.start..tokens[0].span.end] else null;
        const last = if (alias != null) tokens[3] else tokens[0];
        const name = text[last.span.start..last.span.end];
        const id = try self.resolve(module, alias, name, .type, null, span);
        const symbol = self.units[id.module].symbols.items[id.symbol];
        if (!symbol.exported) return self.project.fail("E_PRIVATE_INTERFACE", "exported interface exposes an unexported type", .{ .module = module, .span = span }, .{ .module = id.module, .span = symbol.span });
    }
    pub fn render(self: *Index, allocator: std.mem.Allocator) ![]u8 {
        if (self.project.problem != null) return error.IncompleteProject;
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        output.writer.writeAll("module interfaces v1; declarations/signature visibility checked; bodies not type checked\n") catch return error.OutOfMemory;
        for (self.project.order.items) |module| {
            output.writer.print("module {s}\n", .{self.project.modules.items[module].name}) catch return error.OutOfMemory;
            for (self.units[module].symbols.items) |symbol| {
                if (!symbol.exported) continue;
                output.writer.print("  export {s} {s}\n", .{ @tagName(symbol.kind), symbol.name }) catch return error.OutOfMemory;
            }
        }
        return output.toOwnedSlice();
    }
};
pub fn build(project: *graph.Project) !Index {
    if (!project.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    var index: Index = .{ .project = project, .units = try allocator.alloc(Unit, project.modules.items.len) };
    for (project.order.items) |module_id| {
        const module = project.modules.items[module_id];
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, module.src.bytes, &sink);
        var start: usize = 0;
        while (tokens[start].span.start < module.body_start) start += 1;
        var parse: parser.Parser = .{ .src = module.src, .allocator = allocator, .tokens = tokens, .pos = start, .sink = &sink, .module_syntax = true };
        const syntax = parse.parse() catch |err| {
            if (err == error.OutOfMemory) return err;
            const problem = sink.items.items[0];
            return project.fail(problem.code, problem.message, .{ .module = module_id, .span = problem.span }, null);
        };
        index.units[module_id] = .{ .syntax = syntax };
        inline for (.{ "records", "domains", "variants", "buffers", "resources", "pools" }) |field| {
            for (@field(syntax, field)) |declaration| try index.add(module_id, declaration.name, .type, null, false);
        }
        for (syntax.pools) |pool| try index.add(module_id, pool.handle, .type, null, false);
        for (syntax.functions) |function| try index.add(module_id, function.name, .function, function.owner, function.restricted);
        for (module.exports) |exported| {
            const id = index.units[module_id].names.get(exported.name) orelse return project.fail("E_UNKNOWN_EXPORT", "export names no local declaration", .{ .module = module_id, .span = exported.span }, null);
            index.units[module_id].symbols.items[id].exported = true;
        }
        for (index.units[module_id].symbols.items) |*symbol| {
            if (symbol.owner) |owner| symbol.exported = !symbol.restricted and index.units[module_id].symbols.items[index.units[module_id].names.get(owner).?].exported;
        }
    }
    // Every module is indexed before checking interface dependencies.
    for (project.order.items) |module| {
        const unit = index.units[module];
        for (unit.syntax.records) |record| {
            if (!unit.symbols.items[unit.names.get(project.modules.items[module].src.text(record.name)).?].exported) continue;
            for (record.fields) |field| try index.signatureType(module, field.ty);
        }
        for (unit.syntax.variants) |variant| {
            if (!unit.symbols.items[unit.names.get(project.modules.items[module].src.text(variant.name)).?].exported) continue;
            for (variant.cases) |case| if (case.payload) |payload| try index.signatureType(module, payload);
        }
        for (unit.syntax.domains) |domain| {
            if (unit.symbols.items[unit.names.get(project.modules.items[module].src.text(domain.name)).?].exported) try index.signatureType(module, domain.backing);
        }
        for (unit.syntax.buffers) |buffer| {
            if (unit.symbols.items[unit.names.get(project.modules.items[module].src.text(buffer.name)).?].exported) try index.signatureType(module, buffer.backing);
        }
        for (unit.syntax.pools) |pool| {
            if (unit.symbols.items[unit.names.get(project.modules.items[module].src.text(pool.name)).?].exported) try index.signatureType(module, pool.element);
        }
        for (unit.syntax.functions) |function| {
            const src = project.modules.items[module].src;
            const name = if (function.owner) |owner| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ src.text(owner), src.text(function.name) }) else src.text(function.name);
            if (!unit.symbols.items[unit.names.get(name).?].exported) continue;
            for (function.parameters) |parameter| try index.signatureType(module, parameter.ty);
            try index.signatureType(module, function.return_type);
        }
    }
    return index;
}

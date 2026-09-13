//! Module declaration identities and export boundaries, before body type checking.
const std = @import("std");
const eGenericArity = "E_GENERIC_ARITY";
const graph = @import("project.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const typed = @import("typed.zig");
/// Distinguish type declarations from callable declarations during name resolution.
pub const Kind = enum { type, function };
/// Identify a declaration by its module and local symbol index.
pub const Identity = struct { module: usize, symbol: usize };
/// Store declaration visibility and optional domain-owner restrictions.
pub const Symbol = struct { name: []const u8, kind: Kind, span: source.Span, exported: bool = false, owner: ?[]const u8 = null, restricted: bool = false };
/// Store parsed module declarations and their local name index.
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
    pub const Request = struct { from: usize, alias: ?[]const u8, name: []const u8, kind: Kind, owner: ?[]const u8, span: source.Span };
    /// Resolve a requested declaration and enforce module and domain visibility.
    pub fn resolve(self: *Index, request: Request) diagnostic.Error!Identity {
        const from = request.from;
        const alias = request.alias;
        const name = request.name;
        const kind = request.kind;
        const owner = request.owner;
        const span = request.span;
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
        if (symbol.restricted and !sameOwner(target == from, owner, symbol.owner.?)) return self.project.fail("E_PRIVATE_FUNCTION", "private domain function requires the same declaring domain", site, declaration);
        if (symbol.kind != kind) return self.project.fail("E_SYMBOL_KIND", "declaration has the wrong kind for this reference", site, declaration);
        return .{ .module = target, .symbol = symbol_id };
    }
    fn signatureType(self: *Index, module: usize, span: source.Span) diagnostic.Error!void {
        const syntax = self.units[module].syntax;
        for (syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            for (callback.parameters) |parameter| try self.signatureType(module, parameter);
            return self.signatureType(module, callback.return_type);
        }
        for (syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .enum_type) try self.signatureType(module, array.index.enum_type);
            return self.signatureType(module, array.element);
        }
        const src = self.project.modules.items[module].src;
        if (typed.Type.fromName(src.text(span)) != null) return;
        if (!self.units[module].names.contains(src.text(span)) and @import("prelude.zig").scalar(src.text(span))) return;
        for (syntax.types.expressions.applications) |application| {
            if (application.span.start == span.start and application.span.end == span.end) return self.applicationType(module, application, &.{});
        }
        const id = try self.typeIdentity(module, span);
        try self.requirePublicType(module, span, id);
        if (self.declaredTypeParameters(id).len != 0) return self.project.fail(
            eGenericArity,
            "nominal type template requires explicit type arguments",
            .{ .module = module, .span = span },
            .{ .module = id.module, .span = self.units[id.module].symbols.items[id.symbol].span },
        );
    }
    fn typeIdentity(self: *Index, module: usize, span: source.Span) diagnostic.Error!Identity {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;

        // Re-lex this short name to normalize whitespace/comments around module separators.
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, src.text(span), &sink);
        const qualified = lexer.qualifiedName(src.text(span), tokens) orelse return error.InternalError;
        return self.resolve(.{ .from = module, .alias = qualified.alias, .name = qualified.name, .kind = .type, .owner = null, .span = span });
    }
    fn requirePublicType(self: *Index, module: usize, span: source.Span, id: Identity) diagnostic.Error!void {
        const symbol = self.units[id.module].symbols.items[id.symbol];
        if (!symbol.exported) return self.project.fail("E_PRIVATE_INTERFACE", "exported interface exposes an unexported type", .{ .module = module, .span = span }, .{ .module = id.module, .span = symbol.span });
    }
    fn applicationType(self: *Index, module: usize, application: ast.TypeApplication, parameters: []const ast.TypeParameter) diagnostic.Error!void {
        const src = self.project.modules.items[module].src;
        for (parameters) |parameter| if (std.mem.eql(u8, src.text(parameter.name), src.text(application.name))) return self.project.fail(
            "E_TYPE_APPLICATION",
            "type parameters cannot be used as type constructors",
            .{ .module = module, .span = application.name },
            null,
        );
        const name = src.text(application.name);
        if (!self.units[module].names.contains(name)) {
            const arity = @import("prelude.zig").arity(name);
            if (arity) |count| {
                if (application.arguments.len != count) return self.project.fail(eGenericArity, "builtin type argument count does not match", .{ .module = module, .span = application.span }, null);
                for (application.arguments) |argument| try self.genericSignatureType(module, argument, parameters);
                return;
            }
        }
        const id = try self.typeIdentity(module, application.name);
        try self.requirePublicType(module, application.name, id);
        const declaration = self.units[id.module].symbols.items[id.symbol].span;
        const arity = self.declaredTypeParameters(id).len;
        if (arity != application.arguments.len) return self.project.fail(
            eGenericArity,
            "type application argument count does not match its declaration",
            .{ .module = module, .span = application.span },
            .{ .module = id.module, .span = declaration },
        );
        for (application.arguments) |argument| try self.genericSignatureType(module, argument, parameters);
    }
    fn declaredTypeParameters(self: *Index, id: Identity) []const ast.TypeParameter {
        const declaration = self.units[id.module].symbols.items[id.symbol].span;
        inline for (.{ "records", "variants" }) |category| {
            for (@field(self.units[id.module].syntax.types, category)) |item| {
                if (item.name.start == declaration.start) return item.type_parameters;
            }
        }
        return &.{};
    }
    fn checkNominalParameters(self: *Index, module: usize, parameters: []const ast.TypeParameter) diagnostic.Error!void {
        try self.checkGenericRequirements(module, parameters);
        const src = self.project.modules.items[module].src;
        for (parameters) |parameter| {
            const name = src.text(parameter.name);
            const site: graph.Site = .{ .module = module, .span = parameter.name };
            if (self.units[module].names.get(name)) |symbol| return self.project.fail("E_SHADOWING", "type parameter shadows a module declaration", site, .{ .module = module, .span = self.units[module].symbols.items[symbol].span });
            for (self.project.modules.items[module].imports) |imported| {
                if (std.mem.eql(u8, name, imported.alias)) return self.project.fail("E_SHADOWING", "type parameter shadows an import alias", site, .{ .module = module, .span = imported.span });
            }
        }
    }
    fn checkGenericRequirements(self: *Index, module: usize, parameters: []const ast.TypeParameter) diagnostic.Error!void {
        var sink: diagnostic.Sink = .{ .allocator = self.project.arena.allocator() };
        _ = @import("generic_requirements.zig").resolve(sink.allocator, self.project.modules.items[module].src, parameters, &sink) catch |err| {
            if (err != error.SourceError) return err;
            const problem = sink.items.items[0];
            return self.project.fail(problem.code, problem.message, .{ .module = module, .span = problem.span }, null);
        };
    }
    fn genericSignatureType(self: *Index, module: usize, span: source.Span, parameters: []const ast.TypeParameter) diagnostic.Error!void {
        const src = self.project.modules.items[module].src;
        for (parameters) |parameter| if (std.mem.eql(u8, src.text(parameter.name), src.text(span))) return;
        for (self.units[module].syntax.types.expressions.applications) |application| {
            if (application.span.start == span.start and application.span.end == span.end) return self.applicationType(module, application, parameters);
        }
        for (self.units[module].syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            for (callback.parameters) |parameter| try self.genericSignatureType(module, parameter, parameters);
            return self.genericSignatureType(module, callback.return_type, parameters);
        }
        for (self.units[module].syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .enum_type) try self.genericSignatureType(module, array.index.enum_type, parameters);
            return self.genericSignatureType(module, array.element, parameters);
        }
        try self.signatureType(module, span);
    }
    fn checkSignatures(self: *Index, module: usize) diagnostic.Error!void {
        const project = self.project;
        const allocator = project.arena.allocator();
        const unit = self.units[module];
        for (unit.syntax.types.records) |record| {
            try self.checkNominalParameters(module, record.type_parameters);
            if (!unit.symbols.items[unit.names.get(project.modules.items[module].src.text(record.name)).?].exported) continue;
            for (record.fields) |field| try self.genericSignatureType(module, field.ty, record.type_parameters);
        }
        for (unit.syntax.types.variants) |variant| {
            try self.checkNominalParameters(module, variant.type_parameters);
            if (!unit.symbols.items[unit.names.get(project.modules.items[module].src.text(variant.name)).?].exported) continue;
            for (variant.cases) |case| if (case.payload) |payload| try self.genericSignatureType(module, payload, variant.type_parameters);
        }
        for (unit.syntax.types.expressions.aliases) |alias| {
            if (unit.symbols.items[unit.names.get(project.modules.items[module].src.text(alias.name)).?].exported) try self.signatureType(module, alias.target);
        }
        for (unit.syntax.types.domains) |domain| {
            if (unit.symbols.items[unit.names.get(project.modules.items[module].src.text(domain.name)).?].exported) try self.signatureType(module, domain.backing);
        }
        for (unit.syntax.functions) |function| {
            try self.checkGenericRequirements(module, function.signature.type_parameters);
            const src = project.modules.items[module].src;
            const name = if (function.policy.owner) |owner| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ src.text(owner), src.text(function.name) }) else src.text(function.name);
            if (!unit.symbols.items[unit.names.get(name).?].exported) continue;
            for (function.signature.type_parameters) |parameter| {
                for (parameter.field_requirements) |field| try self.genericSignatureType(module, field.ty, function.signature.type_parameters);
                for (parameter.operation_requirements) |operation| {
                    for (operation.parameters) |input| try self.genericSignatureType(module, input.ty, function.signature.type_parameters);
                    try self.genericSignatureType(module, operation.return_type, function.signature.type_parameters);
                }
            }
            for (function.signature.parameters) |parameter| try self.genericSignatureType(module, parameter.ty, function.signature.type_parameters);
            try self.genericSignatureType(module, function.signature.return_type, function.signature.type_parameters);
        }
    }
    /// Render exported declarations after interface checking; output belongs to allocator.
    pub fn render(self: *Index, allocator: std.mem.Allocator) (std.mem.Allocator.Error || error{IncompleteProject})![]u8 {
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
/// Parse and index every module before checking exported signature visibility.
pub fn build(project: *graph.Project) (diagnostic.Error || error{IncompleteProject})!Index {
    return buildWithCache(project, null);
}
/// Reuse unchanged parse tables while rebuilding all symbols and exported signature checks.
pub fn buildWithCache(project: *graph.Project, cache: ?*@import("syntax_cache.zig").Cache) (diagnostic.Error || error{IncompleteProject})!Index {
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    var index: Index = .{ .project = project, .units = try allocator.alloc(Unit, project.modules.items.len) };
    for (project.order.items) |module_id| {
        const module = project.modules.items[module_id];
        const syntax = try moduleSyntax(project, module_id, cache);
        index.units[module_id] = .{ .syntax = syntax };
        inline for (.{ "records", "domains", "variants", "resources" }) |field| {
            for (@field(syntax.types, field)) |declaration| try index.add(module_id, declaration.name, .type, null, false);
        }
        for (syntax.types.expressions.aliases) |alias| try index.add(module_id, alias.name, .type, null, false);
        for (syntax.functions) |function| try index.add(module_id, function.name, .function, function.policy.owner, function.policy.restricted);
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
        try index.checkSignatures(module);
    }
    return index;
}

fn sameOwner(local: bool, owner: ?[]const u8, declared: []const u8) bool {
    if (!local) return false;
    return std.mem.eql(u8, owner orelse return false, declared);
}

fn moduleSyntax(project: *graph.Project, module_id: usize, cache: ?*@import("syntax_cache.zig").Cache) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    if (cache) |retained| {
        if (try retained.lookup(project.arena.allocator(), module.src, module.header.body_start)) |syntax| return syntax;
    }
    var sink: diagnostic.Sink = .{ .allocator = project.arena.allocator() };
    const syntax = parseModule(project, module_id, &sink) catch |err| {
        if (err != error.SourceError) return err;
        const problem = sink.items.items[0];
        return project.fail(problem.code, problem.message, .{ .module = module_id, .span = problem.span }, null);
    };
    if (cache) |retained| try retained.remember(module.src, module.header.body_start, syntax);
    return syntax;
}
fn parseModule(project: *graph.Project, module_id: usize, sink: *diagnostic.Sink) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    const tokens = try lexer.lex(project.arena.allocator(), module.src.bytes, sink);
    var parse: parser.Parser = .{ .src = module.src, .arena = &project.arena, .tokens = tokens, .sink = sink };
    return parse.parseModule();
}

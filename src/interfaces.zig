//! Module declaration identities and export boundaries, before body type checking.
const std = @import("std");
const eGenericArity = "E_GENERIC_ARITY";
/// Error code for an export directive that names no visible declaration.
const eUnknownExport = "E_UNKNOWN_EXPORT";
/// Error code for a name absent from the resolved module.
const eUnknownSymbol = "E_UNKNOWN_SYMBOL";
/// Error code for a qualifier that names no direct import alias.
const eUnknownImport = "E_UNKNOWN_IMPORT";
/// Error code for a declaration of the wrong kind for the reference.
const eSymbolKind = "E_SYMBOL_KIND";
/// Format one module-qualified declaration name as `module::symbol`.
const qualified_name_format = "{s}::{s}";
const graph = @import("project.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const typed = @import("typed.zig");
const generic_requirements = @import("generic_requirements.zig");
const structural_declarations = @import("structural_declarations.zig");
const effect_set = @import("effect_set.zig");
const prelude = @import("prelude.zig");
const tests_index = @import("tests_index.zig");
const SyntaxCache = @import("syntax_cache.zig").Cache;
const FrontendCache = @import("frontend_cache.zig").Cache;
/// One exported declaration's canonical declared contract for provider validation.
/// Exact fields (`signature`, `generics`, `shape`) compare for equality; the
/// permission field (`permissions`) uses the frozen directional subset relation
/// so a replacement may be narrower but never stronger.
pub const ContractDeclaration = struct {
    name: []const u8,
    kind: []const u8,
    signature: []const u8 = "",
    generics: []const u8 = "",
    /// `effects=<names>;mutates=<positions>;origin=<tag>`; empty for non-callables.
    permissions: []const u8 = "",
    shape: []const u8 = "",
    /// Present only for a declaration carrying `@test`, so test discovery can
    /// admit a name that does not use the `test_` prefix.
    @"test": ?bool = null,
};
/// One module's exported declared-contract table.
pub const ContractModule = struct { name: []const u8, declarations: []const ContractDeclaration };
/// Versioned declaration-level contract manifest; bodies are not checked.
pub const ContractManifest = struct { version: []const u8 = "interface-contracts-v2", modules: []const ContractModule };
/// Allocation, rejected declarations and an incomplete project all prevent a manifest.
pub const ContractError = diagnostic.Error || error{IncompleteProject};
/// Distinguish type declarations from callable declarations during name resolution.
pub const Kind = enum { type, function, constraint };
/// Identify a declaration by its module and local symbol index.
pub const Identity = struct { module: usize, symbol: usize };
/// Store declaration visibility and optional domain-owner restrictions. A
/// re-export facade carries `re_export` pointing at the defining declaration in
/// its own module; every consumer resolves through that identity.
pub const Symbol = struct { name: []const u8, kind: Kind, span: source.Span, exported: bool = false, owner: ?[]const u8 = null, restricted: bool = false, re_export: ?Identity = null };
/// Store parsed module declarations and their local name index. `import_used`
/// carries one flag per direct import in this module's own order; the resolver
/// sets it when a reference actually resolves through that import, which is the
/// exact evidence `W_UNUSED_IMPORT` reads.
pub const Unit = struct { syntax: ast.Program, symbols: std.ArrayList(Symbol) = .empty, names: std.StringHashMapUnmanaged(usize) = .empty, import_used: []bool = &.{} };
/// One named bound resolution plus the caller-local span that exposed it.
const BoundResolution = struct { identity: Identity, span: source.Span };
/// A resolved constraint identity and the declaring syntax that describes it.
const ConstraintResolution = struct { identity: Identity, declaration: *const ast.Constraint };
/// Interface-time named-bound lookup that records each resolved constraint identity.
const ConstraintLookup = struct {
    index: *Index,
    module: usize,
    bounds: std.ArrayList(BoundResolution),
    fn find(ctx: *anyopaque, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!generic_requirements.Definition {
        const self: *ConstraintLookup = @ptrCast(@alignCast(ctx));
        const resolution = try self.index.constraintDeclaration(self.module, reference, sink);
        const bound_span = if (reference.alias) |alias| source.Span.join(alias, reference.name) else reference.name;
        try self.bounds.append(self.index.project.arena.allocator(), .{ .identity = resolution.identity, .span = bound_span });
        return .{
            .module = resolution.identity.module,
            .name = resolution.declaration.name,
            .subject = resolution.declaration.subject.name,
            .scope = resolution.declaration.span,
            .body = &resolution.declaration.subject,
            // Requirement spans belong to the defining module's source coordinates.
            .copyable = generic_requirements.explicitCopyable(
                self.index.project.modules.items[resolution.identity.module].src,
                resolution.declaration.subject.requirements,
            ),
        };
    }
};
/// Storage belongs to project.arena. Do not retain this index after project.deinit.
pub const Index = struct {
    project: *graph.Project,
    units: []Unit,
    /// Checked bodies, when the caller has them, so `renderContracts` can publish
    /// each unannotated callable's frozen inferred ceiling instead of demanding
    /// the author retype it. Null during pure interface pre-validation.
    program: ?typed.Program = null,
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
            for (self.project.modules.items[from].imports, 0..) |imported, import_index| {
                if (!imported.matches(requested)) continue;
                target = imported.target;
                found = true;
                if (import_index < self.units[from].import_used.len) self.units[from].import_used[import_index] = true;
                break;
            }
            if (!found) return self.project.fail(eUnknownImport, "name does not identify a direct import alias", site, null);
        }
        const symbol_id = self.units[target].names.get(name) orelse {
            const message = if (kind == .function)
                try self.functionMissMessage(from, target, name)
            else
                "declaration is not present in the resolved module";
            return self.project.fail(eUnknownSymbol, message, site, null);
        };
        const symbol = self.units[target].symbols.items[symbol_id];
        const declaration: graph.Site = .{ .module = target, .span = symbol.span };
        if (target != from and !symbol.exported) return self.project.fail("E_PRIVATE_SYMBOL", "declaration is private to its module", site, declaration);
        if (symbol.restricted and !sameOwner(target == from, owner, symbol.owner.?)) return self.project.fail("E_PRIVATE_FUNCTION", "private domain function requires the same declaring domain", site, declaration);
        if (symbol.kind != kind) return self.project.fail(eSymbolKind, "declaration has the wrong kind for this reference", site, declaration);
        // A facade re-export resolves to the declaration that defines it, so the
        // caller sees the defining module's identity and the facade is only a name.
        if (symbol.re_export) |identity| return identity;
        return .{ .module = target, .symbol = symbol_id };
    }
    /// Whether a module's direct import at `import_index` was resolved at least
    /// once, which is the exact evidence `W_UNUSED_IMPORT` reports against.
    pub fn importUsed(self: *const Index, module: usize, import_index: usize) bool {
        if (module >= self.units.len) return false;
        const used = self.units[module].import_used;
        return import_index < used.len and used[import_index];
    }
    /// Recover import usage for declarations whose checked bodies the semantic
    /// cache replayed. `resolve` observes a fresh reference exactly; a replayed
    /// body is never re-resolved, so this pass reads each module's own token
    /// stream past its header and marks an import the way the resolver does: a
    /// dotted qualified name whose qualifier matches the import's alias or full
    /// dotted path. A local binding cannot shadow an import alias
    /// (`E_SHADOWING`), and comments and string literals are single tokens, so a
    /// match is a resolved qualified reference rather than a bare identifier.
    pub fn recoverImportUsage(self: *Index, backing: std.mem.Allocator) void {
        if (self.project.problem != null) return;
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();
        const scratch = arena.allocator();
        for (self.project.order.items) |module_id| {
            const module = self.project.modules.items[module_id];
            if (module.imports.len == 0) continue;
            var sink: diagnostic.Sink = .{ .allocator = scratch };
            const tokens = lexer.lex(scratch, module.src.bytes, &sink) catch continue;
            var index: usize = 0;
            while (index < tokens.len) : (index += 1) {
                if (tokens[index].tag != .ident) continue;
                if (tokens[index].span.start < module.header.body_start) continue;
                var last = index;
                var cursor = index + 1;
                while (cursor + 1 < tokens.len and tokens[cursor].tag == .dot and tokens[cursor + 1].tag == .ident) {
                    last = cursor + 1;
                    cursor += 2;
                }
                if (last == index) continue;
                const qualifier = module.src.bytes[tokens[index].span.start..tokens[last - 2].span.end];
                for (module.imports, 0..) |imported, import_index| {
                    if (!imported.matches(qualifier)) continue;
                    if (import_index < self.units[module_id].import_used.len) self.units[module_id].import_used[import_index] = true;
                    break;
                }
                index = last;
            }
        }
    }
    /// Resolve the target of a `export alias.Name` re-export directive. The
    /// directive does not say whether it names a type, function or constraint,
    /// so each kind is probed in turn; a kind mismatch is retried and only a
    /// missing or private target is reported, as `E_UNKNOWN_EXPORT`/the privacy
    /// code at the directive.
    fn resolveExported(self: *Index, module: usize, alias: []const u8, name: []const u8, span: source.Span) diagnostic.Error!Identity {
        const kinds = [_]Kind{ .type, .function, .constraint };
        for (kinds) |kind| {
            if (self.resolve(.{ .from = module, .alias = alias, .name = name, .kind = kind, .owner = null, .span = span })) |resolved| {
                return resolved;
            } else |err| {
                if (err != error.SourceError) return err;
                const problem = self.project.problem orelse return error.InternalError;
                if (std.mem.eql(u8, problem.code, eSymbolKind)) {
                    self.project.problem = null;
                    continue;
                }
                if (std.mem.eql(u8, problem.code, eUnknownSymbol) or std.mem.eql(u8, problem.code, eUnknownImport)) {
                    return self.project.fail(eUnknownExport, "re-export names no exported imported declaration", .{ .module = module, .span = span }, null);
                }
                return err;
            }
        }
        return self.project.fail(eUnknownExport, "re-export names no exported imported declaration", .{ .module = module, .span = span }, null);
    }
    /// Publish a re-exported declaration in the facade module under its local
    /// name. The new symbol's span stays in the facade source (the directive),
    /// so diagnostics locate the facade while `re_export` carries the defining
    /// identity every consumer resolves through.
    fn addFacade(self: *Index, module: usize, name: []const u8, span: source.Span, target: Identity) diagnostic.Error!void {
        const allocator = self.project.arena.allocator();
        const unit = &self.units[module];
        if (unit.names.get(name)) |previous| return self.project.fail("E_DUPLICATE_SYMBOL", "module declaration name is already bound", .{ .module = module, .span = span }, .{ .module = module, .span = unit.symbols.items[previous].span });
        const target_symbol = self.units[target.module].symbols.items[target.symbol];
        try unit.names.put(allocator, name, unit.symbols.items.len);
        try unit.symbols.append(allocator, .{ .name = name, .kind = target_symbol.kind, .span = span, .exported = true, .re_export = target });
    }
    /// Message for an unresolved function, naming close visible declarations.
    fn functionMissMessage(self: *Index, from: usize, target: usize, name: []const u8) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        var candidates: std.ArrayList([]const u8) = .empty;
        defer candidates.deinit(allocator);
        for (self.units[target].symbols.items) |symbol| {
            if (symbol.kind != .function) continue;
            if (std.mem.indexOfScalar(u8, symbol.name, '.') != null) continue;
            if (target != from and !symbol.exported) continue;
            if (std.mem.eql(u8, symbol.name, name)) continue;
            if (typed.editDistanceAtMost(symbol.name, name, 2) > 2) continue;
            try candidates.append(allocator, symbol.name);
        }
        if (candidates.items.len == 0) return "declaration is not present in the resolved module";
        std.mem.sort([]const u8, candidates.items, {}, tokenLess);
        const shown = candidates.items[0..@min(candidates.items.len, 3)];
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(allocator);
        for (shown, 0..) |candidate, index| {
            if (index != 0) try joined.appendSlice(allocator, "`, `");
            try joined.appendSlice(allocator, candidate);
        }
        return std.fmt.allocPrint(allocator, "declaration is not present in the resolved module; did you mean {s}`{s}`?", .{ if (shown.len == 1) "" else "one of: ", joined.items });
    }
    fn resolveConstraint(self: *Index, module: usize, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!Identity {
        const src = self.project.modules.items[module].src;
        const alias = if (reference.alias) |span| src.text(span) else null;
        return self.resolve(.{
            .from = module,
            .alias = alias,
            .name = src.text(reference.name),
            .kind = .constraint,
            .owner = null,
            .span = reference.name,
        }) catch |err| {
            if (err != error.SourceError) return err;
            const problem = self.project.problem orelse return error.InternalError;
            if (std.mem.eql(u8, problem.code, eUnknownSymbol)) return sink.fail(
                diagnostic.generic_requirement,
                reference.name,
                "unknown requirement; expected copy, equality, integer, codec, storable, or a declared constraint",
            );
            return sink.fail(problem.code, problem.site.span, problem.message);
        };
    }
    fn constraintDeclaration(self: *Index, module: usize, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!ConstraintResolution {
        const identity = try self.resolveConstraint(module, reference, sink);
        const symbol = self.units[identity.module].symbols.items[identity.symbol];
        for (self.units[identity.module].syntax.types.constraints) |*constraint| {
            if (constraint.name.start == symbol.span.start and constraint.name.end == symbol.span.end) return .{ .identity = identity, .declaration = constraint };
        }
        return error.InternalError;
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
        if (!self.units[module].names.contains(src.text(span)) and prelude.scalar(src.text(span))) return;
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
    /// Whether a merged-source function-name span names an exported function.
    ///
    /// E2 uses this after body checking to require an explicit effect ceiling on
    /// every exported declaration, including exported generic templates and
    /// public domain operations exposed through an exported type. Non-exported
    /// helpers (and a non-exported `main`) stay inferred.
    pub fn functionExported(self: *Index, src: source.Source, span: source.Span) bool {
        const original = src.originalSpan(span) catch return false;
        if (original.input >= self.units.len) return false;
        for (self.units[original.input].symbols.items) |symbol| {
            if (symbol.kind != .function) continue;
            if (symbol.span.start == original.span.start and symbol.span.end == original.span.end) return symbol.exported;
        }
        return false;
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
            const arity = prelude.arity(name);
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
    fn checkParameterShadowing(self: *Index, module: usize, parameter: ast.TypeParameter) diagnostic.Error!void {
        const src = self.project.modules.items[module].src;
        const name = src.text(parameter.name);
        const site: graph.Site = .{ .module = module, .span = parameter.name };
        if (typed.Type.fromName(name) != null) return self.project.fail("E_GENERIC_PARAMETER", "type parameter cannot shadow a builtin type", site, null);
        if (self.units[module].names.get(name)) |symbol| return self.project.fail("E_SHADOWING", "type parameter shadows a module declaration", site, .{ .module = module, .span = self.units[module].symbols.items[symbol].span });
        for (self.project.modules.items[module].imports) |imported| {
            if (std.mem.eql(u8, name, imported.alias)) return self.project.fail("E_SHADOWING", "type parameter shadows an import alias", site, .{ .module = module, .span = imported.span });
        }
    }
    fn checkNominalParameters(self: *Index, module: usize, parameters: []const ast.TypeParameter) diagnostic.Error!void {
        for (parameters) |parameter| if (parameter.named_requirements.len != 0) {
            const reference = parameter.named_requirements[0];
            return self.project.fail(
                diagnostic.generic_requirement,
                "named constraints may only bound function type parameters",
                .{ .module = module, .span = boundSpan(reference) },
                null,
            );
        };
        _ = try self.checkGenericRequirements(module, parameters);
        for (parameters) |parameter| try self.checkParameterShadowing(module, parameter);
    }
    fn checkGenericRequirements(self: *Index, module: usize, parameters: []const ast.TypeParameter) diagnostic.Error![]const BoundResolution {
        const allocator = self.project.arena.allocator();
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        var lookup_state: ConstraintLookup = .{ .index = self, .module = module, .bounds = .empty };
        const lookup: generic_requirements.Lookup = .{ .ctx = &lookup_state, .find = ConstraintLookup.find };
        generic_requirements.validateBounds(allocator, self.project.modules.items[module].src, parameters, &sink, lookup) catch |err| {
            if (err != error.SourceError) return err;
            return self.emitSinkProblem(module, &sink);
        };
        return lookup_state.bounds.toOwnedSlice(allocator);
    }
    fn emitSinkProblem(self: *Index, module: usize, sink: *diagnostic.Sink) diagnostic.Error {
        if (sink.items.items.len == 0) return error.InternalError;
        const problem = sink.items.items[0];
        return self.project.fail(problem.code, problem.message, .{ .module = module, .span = problem.span }, null);
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
    fn checkConstraint(self: *Index, module: usize, constraint: ast.Constraint) diagnostic.Error!void {
        const project = self.project;
        const src = project.modules.items[module].src;
        if (constraint.subject.name.start == constraint.subject.name.end) return project.fail(
            diagnostic.generic_requirement,
            "constraint requires exactly one subject binder",
            .{ .module = module, .span = constraint.name },
            null,
        );
        if (constraint.subject.named_requirements.len != 0) {
            const reference = constraint.subject.named_requirements[0];
            return project.fail(
                diagnostic.generic_requirement,
                "a constraint right-hand side may not reference another named constraint",
                .{ .module = module, .span = boundSpan(reference) },
                null,
            );
        }
        try self.checkParameterShadowing(module, constraint.subject);
        var sink: diagnostic.Sink = .{ .allocator = project.arena.allocator() };
        structural_declarations.validate(src, constraint.subject, parameterCopy(src, constraint.subject), &sink) catch |err| {
            if (err != error.SourceError) return err;
            return self.emitSinkProblem(module, &sink);
        };
        const symbol_id = self.units[module].names.get(src.text(constraint.name)) orelse return error.InternalError;
        if (!self.units[module].symbols.items[symbol_id].exported) return;
        const parameters: [1]ast.TypeParameter = .{constraint.subject};
        for (constraint.subject.field_requirements) |field| try self.genericSignatureType(module, field.ty, &parameters);
        for (constraint.subject.operation_requirements) |operation| {
            for (operation.parameters) |input| try self.genericSignatureType(module, input.ty, &parameters);
            try self.genericSignatureType(module, operation.return_type, &parameters);
        }
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
        for (unit.syntax.types.constraints) |constraint| {
            try self.checkConstraint(module, constraint);
        }
        for (unit.syntax.functions) |function| {
            const bounds = try self.checkGenericRequirements(module, function.signature.type_parameters);
            const src = project.modules.items[module].src;
            const name = if (function.policy.owner) |owner| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ src.text(owner), src.text(function.name) }) else src.text(function.name);
            if (!unit.symbols.items[unit.names.get(name).?].exported) continue;
            for (bounds) |bound| {
                // The identity's symbol index belongs to the defining module's table.
                const symbol = self.units[bound.identity.module].symbols.items[bound.identity.symbol];
                if (!symbol.exported) return project.fail(
                    "E_PRIVATE_INTERFACE",
                    "exported generic function exposes an unexported constraint",
                    .{ .module = module, .span = bound.span },
                    .{ .module = bound.identity.module, .span = symbol.span },
                );
            }
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
    /// Render exported declarations after interface checking; output belongs to
    /// allocator. Callable lines carry their whole signature, the inferred
    /// `effects(...)` set, `mutates(...)` parameter names, and the declared
    /// ceiling when the source wrote one.
    pub fn render(self: *Index, allocator: std.mem.Allocator) ContractError![]u8 {
        if (self.project.problem != null) return error.IncompleteProject;
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        // The `tests` column reads the same reachability index `tests-for`
        // answers from; it is absent when no checked program is attached.
        var tests: ?tests_index.Index = try self.buildTestsIndex(allocator);
        defer {
            if (tests) |*index| index.deinit();
        }
        output.writer.writeAll("module interfaces v1; declarations/signature visibility checked; bodies not type checked\n") catch return error.OutOfMemory;
        for (self.project.order.items) |module| {
            output.writer.print("module {s}\n", .{self.project.modules.items[module].name}) catch return error.OutOfMemory;
            for (self.units[module].symbols.items) |symbol| {
                if (!symbol.exported) continue;
                if (symbol.kind == .function) {
                    try self.renderFunctionLine(&output.writer, module, symbol, if (tests) |*index| index else null);
                    continue;
                }
                output.writer.print("  export {s} {s}", .{ @tagName(symbol.kind), symbol.name }) catch return error.OutOfMemory;
                try self.appendDocstringLine(&output.writer, module, symbol);
                output.writer.writeAll("\n") catch return error.OutOfMemory;
            }
        }
        return output.toOwnedSlice();
    }
    /// Render one exported function as `export function NAME def(...) effects(...)
    /// [mutates(names)] [ceiling(...)] [tests(N)] [# first docstring line]`. The
    /// ceiling is the already-inferred mask when a checked program is attached,
    /// or the unbounded mask otherwise, which is what an omitted declaration
    /// promises. `tests` carries the shared reachability index, or null when no
    /// checked program is attached.
    fn renderFunctionLine(self: *Index, writer: *std.Io.Writer, module: usize, symbol: Symbol, tests: ?*const tests_index.Index) ContractError!void {
        const allocator = self.project.arena.allocator();
        const origin = self.declarationSource(module, symbol);
        const function = self.findFunction(self.units[origin.module], origin.symbol.span) orelse return error.InternalError;
        const signature = try self.contractSignatureText(origin.module, function.signature);
        writer.print("  export function {s} {s} effects(", .{ origin.display, signature }) catch return error.OutOfMemory;
        var inferred: std.ArrayList(u8) = .empty;
        try appendEffectNames(&inferred, allocator, self.publishedEffects(origin.module, origin.symbol));
        writer.writeAll(inferred.items) catch return error.OutOfMemory;
        writer.writeAll(")") catch return error.OutOfMemory;
        const mutates = try self.mutatesNamesText(origin.module, function.signature);
        if (mutates.len != 0) writer.print(" mutates({s})", .{mutates}) catch return error.OutOfMemory;
        if (function.policy.effect_bound) |bound| {
            writer.writeAll(" ceiling(") catch return error.OutOfMemory;
            var ceiling: std.ArrayList(u8) = .empty;
            try appendEffectNames(&ceiling, allocator, bound.allowed);
            writer.writeAll(ceiling.items) catch return error.OutOfMemory;
            writer.writeAll(")") catch return error.OutOfMemory;
        }
        if (tests) |index| {
            if (try self.programFunction(origin.module, origin.symbol.name)) |id| {
                const answer = index.answer(id);
                writer.print(" tests({d})", .{answer.reached.len}) catch return error.OutOfMemory;
            }
        }
        try self.appendDocstringLine(writer, origin.module, origin.symbol);
        writer.writeAll("\n") catch return error.OutOfMemory;
    }
    /// The checked function identity of one module-qualified declaration, or
    /// null when the attached program carries no such name.
    fn programFunction(self: *Index, module: usize, name: []const u8) ContractError!?typed.FunctionId {
        const program = self.program orelse return null;
        const qualified = try std.fmt.allocPrint(self.project.arena.allocator(), "{s}::{s}", .{ self.project.modules.items[module].name, name });
        for (program.functions, 0..) |function, index| {
            if (std.mem.eql(u8, function.name, qualified)) return @fromBackingInt(@intCast(index));
        }
        return null;
    }
    /// Build the shared tests index for the attached checked program, or null
    /// when no bodies were checked.
    fn buildTestsIndex(self: *Index, allocator: std.mem.Allocator) ContractError!?tests_index.Index {
        const program = self.program orelse return null;
        const scratch = self.project.arena.allocator();
        const modules = try self.moduleSyntax(scratch);
        const call_graph = try tests_index.callGraph(scratch, program);
        const discovered = try tests_index.discoveredTests(scratch, program, modules);
        const built = try tests_index.build(allocator, program, call_graph, discovered);
        return built;
    }
    /// The parsed syntax and source of every module, the inputs the shared
    /// tests index needs to discover `@test` declarations.
    pub fn moduleSyntax(self: *Index, allocator: std.mem.Allocator) std.mem.Allocator.Error![]tests_index.ModuleSyntax {
        const modules = try allocator.alloc(tests_index.ModuleSyntax, self.project.order.items.len);
        for (self.project.order.items, 0..) |module, slot| {
            modules[slot] = .{
                .name = self.project.modules.items[module].name,
                .src = self.project.modules.items[module].src,
                .syntax = self.units[module].syntax,
            };
        }
        return modules;
    }
    /// Append ` # <first docstring line>` for one declaration, or nothing when it
    /// has no docstring. The line is what a reader sees in the listing.
    fn appendDocstringLine(self: *Index, writer: *std.Io.Writer, module: usize, symbol: Symbol) ContractError!void {
        const doc = ast.docstringOf(self.units[module].syntax, symbol.span) orelse return;
        const line = firstDocLine(doc.text);
        if (line.len == 0) return;
        writer.print(" # {s}", .{line}) catch return error.OutOfMemory;
    }
    /// The unit, symbol and published name an interface entry reads its
    /// declaration from. For a re-export facade the declaration lives in the
    /// defining module while the published name stays the facade's local name.
    const DeclarationSource = struct { module: usize, symbol: Symbol, display: []const u8 };
    fn declarationSource(self: *Index, module: usize, symbol: Symbol) DeclarationSource {
        if (symbol.re_export) |target| return .{
            .module = target.module,
            .symbol = self.units[target.module].symbols.items[target.symbol],
            .display = symbol.name,
        };
        return .{ .module = module, .symbol = symbol, .display = symbol.name };
    }
    /// Render one declared `mutates` footprint by source parameter name, falling
    /// back to the numeric position only if the declaration is malformed.
    fn mutatesNamesText(self: *Index, module: usize, signature: ast.FunctionSignature) ContractError![]const u8 {
        if (signature.mutates.len == 0) return "";
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        var out: std.ArrayList(u8) = .empty;
        for (signature.mutates, 0..) |position, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            if (position < signature.parameters.len) {
                try out.appendSlice(allocator, src.text(signature.parameters[position].name));
            } else {
                try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{position}));
            }
        }
        return out.toOwnedSlice(allocator);
    }
    /// Render exported declarations, plus the unexported `test_` declarations
    /// that already have the defaulting test shape, as a canonical
    /// declared-contract manifest. Bodies are never checked; declared signatures
    /// and explicit public ceilings are, so a provider can be validated before
    /// production bodies run.
    pub fn renderContracts(self: *Index, allocator: std.mem.Allocator) ContractError![]u8 {
        if (self.project.problem != null) return error.IncompleteProject;
        // Intermediate tables live in the project arena; only the final JSON text
        // is owned by the caller. This keeps a one-shot listing leak-free.
        const scratch = self.project.arena.allocator();
        var modules: std.ArrayList(ContractModule) = .empty;
        for (self.project.order.items) |module| {
            var declarations: std.ArrayList(ContractDeclaration) = .empty;
            for (self.units[module].symbols.items) |symbol| {
                // `mylang test` discovers `test_` functions by name and `@test`
                // declarations by attribute, so the discovery contract publishes
                // them beside explicit exports.
                const discovered_test = symbol.kind == .function and (std.mem.startsWith(u8, symbol.name, "test_") or self.isTestDeclaration(module, symbol));
                if (!symbol.exported and !discovered_test) continue;
                const declaration = try self.contractDeclaration(module, symbol);
                // An unexported `test_` name is only discovered when it already
                // has the defaulting test shape; `@test` names its intent, so it
                // needs no shape default.
                if (!symbol.exported) {
                    if (!testShape(declaration) and declaration.@"test" != true) continue;
                }
                try declarations.append(scratch, declaration);
            }
            std.mem.sort(ContractDeclaration, declarations.items, {}, declarationLess);
            try modules.append(scratch, .{
                .name = self.project.modules.items[module].name,
                .declarations = try declarations.toOwnedSlice(scratch),
            });
        }
        std.mem.sort(ContractModule, modules.items, {}, moduleLess);
        return std.json.Stringify.valueAlloc(allocator, ContractManifest{ .modules = try modules.toOwnedSlice(scratch) }, .{ .emit_null_optional_fields = false });
    }
    /// Whether one symbol's declaration carries `@test`.
    fn isTestDeclaration(self: *Index, module: usize, symbol: Symbol) bool {
        const origin = self.declarationSource(module, symbol);
        const function = self.findFunction(self.units[origin.module], origin.symbol.span) orelse return false;
        return ast.hasAttribute(self.units[origin.module].syntax, function.name, .@"test");
    }
    /// The declared shape an unexported `test_` function must already have to be
    /// discovered without `export`: no generic parameters and a zero-argument
    /// `bool` result, which is the one shape discovery can default.
    fn testShape(declaration: ContractDeclaration) bool {
        return declaration.generics.len == 0 and std.mem.eql(u8, declaration.signature, "def()->bool");
    }
    fn contractDeclaration(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const origin = self.declarationSource(module, symbol);
        var declaration = switch (origin.symbol.kind) {
            .function => try self.contractFunction(origin.module, origin.symbol),
            .type => try self.contractType(origin.module, origin.symbol),
            .constraint => try self.contractConstraint(origin.module, origin.symbol),
        };
        declaration.name = origin.display;
        return declaration;
    }
    fn findFunction(self: *Index, unit: Unit, span: source.Span) ?ast.Function {
        _ = self;
        for (unit.syntax.functions) |function| {
            if (function.name.start == span.start and function.name.end == span.end) return function;
        }
        return null;
    }
    fn contractFunction(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const function = self.findFunction(self.units[module], symbol.span) orelse return error.InternalError;
        // An explicit `noalloc`/`noio`/`effects(...)` is an opt-in narrowing and
        // is published exactly as declared. Without one, publish the ceiling the
        // checker already inferred for the body instead of refusing to build the
        // contract; pure interface pre-validation falls back to the unbounded
        // `all` mask, which is what an omitted ceiling promises.
        const mask = if (function.policy.effect_bound) |bound| bound.allowed else self.publishedEffects(module, symbol);
        var out: ContractDeclaration = .{ .name = symbol.name, .kind = "function" };
        out.generics = try self.contractGenericsText(module, function.signature.type_parameters);
        out.signature = try self.contractSignatureText(module, function.signature);
        out.permissions = try permissionsText(self.project.arena.allocator(), mask, function.signature.mutates, "unknown");
        if (ast.hasAttribute(self.units[module].syntax, function.name, .@"test")) out.@"test" = true;
        return out;
    }
    /// Ceiling the interface publishes for one exported function. An explicit
    /// `noalloc`/`noio`/`effects(...)` wins as an opt-in narrowing; otherwise the
    /// typed program's frozen inferred mask is used, matched by the
    /// module-qualified name so ordinary, domain and generic specialization
    /// entries all match. With no checked program attached (pure interface
    /// pre-validation) or no instantiation to read, the published contract is
    /// the unbounded `all` mask, which is what an omitted ceiling promises.
    fn publishedEffects(self: *Index, module: usize, symbol: Symbol) effect_set.Mask {
        const program = self.program orelse return effect_set.all;
        const prefix = std.fmt.allocPrint(
            self.project.arena.allocator(),
            qualified_name_format,
            .{ self.project.modules.items[module].name, symbol.name },
        ) catch return effect_set.all;
        for (program.functions) |function| {
            if (!std.mem.startsWith(u8, function.name, prefix)) continue;
            if (function.name.len != prefix.len and function.name[prefix.len] != '[') continue;
            return function.policy.effects;
        }
        return effect_set.all;
    }
    fn contractSignatureText(self: *Index, module: usize, signature: ast.FunctionSignature) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "def(");
        for (signature.parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, src.text(parameter.name));
            try out.appendSlice(allocator, ":");
            try out.appendSlice(allocator, try self.contractTypeText(module, parameter.ty, signature.type_parameters));
            if (parameter.default_value) |value| {
                const span = self.units[module].syntax.nodes.items[@backingInt(value)].span;
                try out.appendSlice(allocator, "=");
                try out.appendSlice(allocator, std.mem.trim(u8, src.text(span), " \t\r\n"));
            }
        }
        try out.appendSlice(allocator, ")->");
        try out.appendSlice(allocator, try self.contractTypeText(module, signature.return_type, signature.type_parameters));
        return out.toOwnedSlice(allocator);
    }
    fn contractGenericsText(self: *Index, module: usize, parameters: []const ast.TypeParameter) ContractError![]const u8 {
        if (parameters.len == 0) return "";
        const allocator = self.project.arena.allocator();
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "[");
        for (parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, "${d}:", .{index}));
            var tokens: std.ArrayList([]const u8) = .empty;
            defer tokens.deinit(allocator);
            if (parameter.default_copy or hasBuiltinRequirement(self.project.modules.items[module].src, parameter, "copy")) {
                try appendUniqueToken(allocator, &tokens, "copy");
            }
            if (parameter.constant_length) try appendUniqueToken(allocator, &tokens, "length");
            for (parameter.requirements) |span| {
                const name = self.project.modules.items[module].src.text(span);
                if (std.mem.eql(u8, name, "copy")) continue;
                try appendUniqueToken(allocator, &tokens, name);
            }
            for (parameter.named_requirements) |reference| {
                var sink: diagnostic.Sink = .{ .allocator = allocator };
                const resolution = try self.constraintDeclaration(module, reference, &sink);
                try appendUniqueToken(allocator, &tokens, try std.fmt.allocPrint(allocator, qualified_name_format, .{
                    self.project.modules.items[resolution.identity.module].name,
                    self.units[resolution.identity.module].symbols.items[resolution.identity.symbol].name,
                }));
            }
            for (parameter.field_requirements) |field| {
                try appendUniqueToken(allocator, &tokens, try std.fmt.allocPrint(allocator, "field({s}:{s})", .{
                    self.project.modules.items[module].src.text(field.name),
                    try self.contractTypeText(module, field.ty, parameters),
                }));
            }
            for (parameter.operation_requirements) |operation| {
                try appendUniqueToken(allocator, &tokens, try self.contractOperationText(module, operation, parameters));
            }
            std.mem.sort([]const u8, tokens.items, {}, tokenLess);
            for (tokens.items, 0..) |token, token_index| {
                if (token_index != 0) try out.appendSlice(allocator, "+");
                try out.appendSlice(allocator, token);
            }
        }
        try out.appendSlice(allocator, "]");
        return out.toOwnedSlice(allocator);
    }
    fn contractOperationText(self: *Index, module: usize, operation: ast.Operation, parameters: []const ast.TypeParameter) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "op(");
        try out.appendSlice(allocator, self.project.modules.items[module].src.text(operation.name));
        try out.appendSlice(allocator, "(");
        for (operation.parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, self.project.modules.items[module].src.text(parameter.name));
            try out.appendSlice(allocator, ":");
            try out.appendSlice(allocator, try self.contractTypeText(module, parameter.ty, parameters));
        }
        try out.appendSlice(allocator, ")->");
        try out.appendSlice(allocator, try self.contractTypeText(module, operation.return_type, parameters));
        try out.appendSlice(allocator, " effects(");
        try appendEffectNames(&out, allocator, operation.effect_bound.allowed);
        try out.appendSlice(allocator, "))");
        return out.toOwnedSlice(allocator);
    }
    fn contractType(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const unit = self.units[module];
        for (unit.syntax.types.records) |record| {
            if (record.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "record" };
            out.generics = try self.contractGenericsText(module, record.type_parameters);
            out.shape = try self.contractFieldsText(module, record.fields, record.type_parameters);
            return out;
        }
        for (unit.syntax.types.variants) |variant| {
            if (variant.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = if (variant.fallible) "result" else if (variant.is_union) "union" else "enum" };
            out.generics = try self.contractGenericsText(module, variant.type_parameters);
            var shape: std.ArrayList(u8) = .empty;
            const allocator = self.project.arena.allocator();
            try shape.appendSlice(allocator, "cases{");
            for (variant.cases, 0..) |case, index| {
                if (index != 0) try shape.appendSlice(allocator, ",");
                try shape.appendSlice(allocator, self.project.modules.items[module].src.text(case.name));
                if (case.payload) |payload| {
                    try shape.appendSlice(allocator, ":");
                    try shape.appendSlice(allocator, try self.contractTypeText(module, payload, variant.type_parameters));
                }
            }
            try shape.appendSlice(allocator, "}");
            out.shape = try shape.toOwnedSlice(allocator);
            return out;
        }
        for (unit.syntax.types.domains) |domain| {
            if (domain.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = if (domain.managed) "resource" else "domain" };
            out.generics = try self.contractGenericsText(module, domain.type_parameters);
            out.shape = try std.fmt.allocPrint(self.project.arena.allocator(), "backing:{s}", .{try self.contractTypeText(module, domain.backing, domain.type_parameters)});
            return out;
        }
        for (unit.syntax.types.resources) |resource| {
            if (resource.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "resource" };
            out.generics = try self.contractGenericsText(module, resource.type_parameters);
            out.shape = try std.fmt.allocPrint(self.project.arena.allocator(), "backing:{s}", .{try self.contractTypeText(module, resource.backing, resource.type_parameters)});
            return out;
        }
        for (unit.syntax.types.expressions.aliases) |alias| {
            if (alias.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "alias" };
            out.shape = try std.fmt.allocPrint(self.project.arena.allocator(), "target:{s}", .{try self.contractTypeText(module, alias.target, &.{})});
            return out;
        }
        return error.InternalError;
    }
    fn contractFieldsText(self: *Index, module: usize, fields: []const ast.Parameter, parameters: []const ast.TypeParameter) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "fields{");
        for (fields, 0..) |field, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, self.project.modules.items[module].src.text(field.name));
            try out.appendSlice(allocator, ":");
            try out.appendSlice(allocator, try self.contractTypeText(module, field.ty, parameters));
        }
        try out.appendSlice(allocator, "}");
        return out.toOwnedSlice(allocator);
    }
    fn contractConstraint(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const unit = self.units[module];
        for (unit.syntax.types.constraints) |constraint| {
            if (constraint.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "constraint" };
            const allocator = self.project.arena.allocator();
            var shape: std.ArrayList(u8) = .empty;
            try shape.appendSlice(allocator, "subject($0:");
            var tokens: std.ArrayList([]const u8) = .empty;
            defer tokens.deinit(allocator);
            const subject = constraint.subject;
            if (subject.default_copy or hasBuiltinRequirement(self.project.modules.items[module].src, subject, "copy")) try appendUniqueToken(allocator, &tokens, "copy");
            for (subject.requirements) |span| {
                const name = self.project.modules.items[module].src.text(span);
                if (std.mem.eql(u8, name, "copy")) continue;
                try appendUniqueToken(allocator, &tokens, name);
            }
            for (subject.field_requirements) |field| {
                try appendUniqueToken(allocator, &tokens, try std.fmt.allocPrint(allocator, "field({s}:{s})", .{
                    self.project.modules.items[module].src.text(field.name),
                    try self.contractTypeText(module, field.ty, &.{subject}),
                }));
            }
            for (subject.operation_requirements) |operation| {
                try appendUniqueToken(allocator, &tokens, try self.contractOperationText(module, operation, &.{subject}));
            }
            std.mem.sort([]const u8, tokens.items, {}, tokenLess);
            for (tokens.items, 0..) |token, index| {
                if (index != 0) try shape.appendSlice(allocator, "+");
                try shape.appendSlice(allocator, token);
            }
            try shape.appendSlice(allocator, ")");
            out.shape = try shape.toOwnedSlice(allocator);
            return out;
        }
        return error.InternalError;
    }
    fn contractTypeText(self: *Index, module: usize, span: source.Span, parameters: []const ast.TypeParameter) ContractError![]const u8 {
        var path: std.ArrayList(Identity) = .empty;
        defer path.deinit(self.project.arena.allocator());
        return self.contractTypeTextPath(module, span, parameters, &path);
    }
    /// Render one declaration-level type as a canonical descriptor. Builtin
    /// aliases collapse to their checked spelling, transparent aliases expand to
    /// their target recursively, and nominal identities stay qualified. The
    /// `path` guard rejects alias cycles without checking any function body.
    fn contractTypeTextPath(self: *Index, module: usize, span: source.Span, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        const text = src.text(span);
        for (parameters, 0..) |parameter, index| {
            if (std.mem.eql(u8, src.text(parameter.name), text)) return std.fmt.allocPrint(allocator, "${d}", .{index});
        }
        for (self.units[module].syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(allocator, "def(");
            for (callback.parameters, 0..) |parameter, index| {
                if (index != 0) try out.appendSlice(allocator, ",");
                try out.appendSlice(allocator, try self.contractTypeTextPath(module, parameter, parameters, path));
            }
            try out.appendSlice(allocator, ")->");
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, callback.return_type, parameters, path));
            try out.appendSlice(allocator, " effects(");
            try appendEffectNames(&out, allocator, callback.effect_bound.allowed);
            try out.appendSlice(allocator, ")");
            if (callback.mutates.len != 0) {
                try out.appendSlice(allocator, " mutates(");
                for (callback.mutates, 0..) |position, index| {
                    if (index != 0) try out.appendSlice(allocator, ",");
                    try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{position}));
                }
                try out.appendSlice(allocator, ")");
            }
            return out.toOwnedSlice(allocator);
        }
        for (self.units[module].syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            var out: std.ArrayList(u8) = .empty;
            try out.appendSlice(allocator, "[");
            switch (array.index) {
                .length => |length| try out.appendSlice(allocator, src.text(length)),
                .enum_type => |enum_type| try out.appendSlice(allocator, try self.contractTypeTextPath(module, enum_type, parameters, path)),
            }
            try out.appendSlice(allocator, "]");
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, array.element, parameters, path));
            return out.toOwnedSlice(allocator);
        }
        if (typed.Type.fromName(text)) |builtin| return allocator.dupe(u8, prelude.reservedTypeName(builtin) orelse typed.typeName(builtin, &.{}));
        if (!self.units[module].names.contains(text)) {
            if (prelude.reservedType(text)) |reserved| return allocator.dupe(u8, prelude.reservedTypeName(reserved) orelse typed.typeName(reserved, &.{}));
            if (prelude.scalar(text)) return allocator.dupe(u8, text);
        }
        for (self.units[module].syntax.types.expressions.applications) |application| {
            if (application.span.start == span.start and application.span.end == span.end) return self.contractApplicationTextPath(module, application, parameters, path);
        }
        const id = try self.typeIdentity(module, span);
        try self.requirePublicType(module, span, id);
        if (self.aliasDeclaration(id)) |alias| {
            for (path.items) |seen| {
                if (sameIdentity(seen, id)) return self.project.fail(
                    "E_ALIAS_CYCLE",
                    "type aliases must have acyclic dependencies",
                    .{ .module = module, .span = span },
                    null,
                );
            }
            try path.append(allocator, id);
            defer path.items.len -= 1;
            return self.contractTypeTextPath(id.module, alias.target, &.{}, path);
        }
        if (self.declaredTypeParameters(id).len != 0) return self.project.fail(
            eGenericArity,
            "nominal type template requires explicit type arguments",
            .{ .module = module, .span = span },
            .{ .module = id.module, .span = self.units[id.module].symbols.items[id.symbol].span },
        );
        return std.fmt.allocPrint(allocator, qualified_name_format, .{
            self.project.modules.items[id.module].name,
            self.units[id.module].symbols.items[id.symbol].name,
        });
    }
    fn aliasDeclaration(self: *Index, id: Identity) ?ast.TypeAlias {
        const symbol = self.units[id.module].symbols.items[id.symbol];
        for (self.units[id.module].syntax.types.expressions.aliases) |alias| {
            if (alias.name.start == symbol.span.start and alias.name.end == symbol.span.end) return alias;
        }
        return null;
    }
    fn contractApplicationTextPath(self: *Index, module: usize, application: ast.TypeApplication, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        for (parameters) |parameter| if (std.mem.eql(u8, src.text(parameter.name), src.text(application.name))) return self.project.fail(
            "E_TYPE_APPLICATION",
            "type parameters cannot be used as type constructors",
            .{ .module = module, .span = application.name },
            null,
        );
        var out: std.ArrayList(u8) = .empty;
        const name = src.text(application.name);
        if (!self.units[module].names.contains(name)) {
            if (prelude.arity(name)) |arity| {
                if (application.arguments.len != arity) return self.project.fail(eGenericArity, "builtin type argument count does not match", .{ .module = module, .span = application.span }, null);
                try out.appendSlice(allocator, name);
                try self.appendTypeArgumentsPath(&out, module, application, parameters, path);
                return out.toOwnedSlice(allocator);
            }
        }
        const id = try self.typeIdentity(module, application.name);
        try self.requirePublicType(module, application.name, id);
        if (self.declaredTypeParameters(id).len != application.arguments.len) return self.project.fail(
            eGenericArity,
            "type application argument count does not match its declaration",
            .{ .module = module, .span = application.span },
            .{ .module = id.module, .span = self.units[id.module].symbols.items[id.symbol].span },
        );
        try out.appendSlice(allocator, self.project.modules.items[id.module].name);
        try out.appendSlice(allocator, "::");
        try out.appendSlice(allocator, self.units[id.module].symbols.items[id.symbol].name);
        try self.appendTypeArgumentsPath(&out, module, application, parameters, path);
        return out.toOwnedSlice(allocator);
    }
    fn appendTypeArgumentsPath(self: *Index, out: *std.ArrayList(u8), module: usize, application: ast.TypeApplication, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError!void {
        const allocator = self.project.arena.allocator();
        try out.appendSlice(allocator, "[");
        for (application.arguments, 0..) |argument, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, argument, parameters, path));
        }
        try out.appendSlice(allocator, "]");
    }
};
fn sameIdentity(a: Identity, b: Identity) bool {
    return a.module == b.module and a.symbol == b.symbol;
}
fn declarationLess(_: void, a: ContractDeclaration, b: ContractDeclaration) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn moduleLess(_: void, a: ContractModule, b: ContractModule) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn tokenLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
fn appendUniqueToken(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), token: []const u8) !void {
    for (list.items) |existing| if (std.mem.eql(u8, existing, token)) return;
    try list.append(allocator, token);
}
fn hasBuiltinRequirement(src: source.Source, parameter: ast.TypeParameter, name: []const u8) bool {
    for (parameter.requirements) |span| if (std.mem.eql(u8, src.text(span), name)) return true;
    return false;
}
/// Canonical declared permission encoding for one exported callable:
/// `effects=<comma names>;mutates=<position list>;origin=<tag>`.
fn permissionsText(allocator: std.mem.Allocator, mask: effect_set.Mask, mutates: []const u16, origin: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "effects=");
    var separator = false;
    inline for (std.meta.tags(effect_set.Effect)) |effect| {
        if (mask & effect_set.bit(effect) != 0) {
            if (separator) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, @tagName(effect));
            separator = true;
        }
    }
    try out.appendSlice(allocator, ";mutates=");
    for (mutates, 0..) |position, index| {
        if (index != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{position}));
    }
    try out.appendSlice(allocator, ";origin=");
    try out.appendSlice(allocator, origin);
    return out.toOwnedSlice(allocator);
}
fn appendEffectNames(out: *std.ArrayList(u8), allocator: std.mem.Allocator, mask: effect_set.Mask) !void {
    var separator = false;
    inline for (std.meta.tags(effect_set.Effect)) |effect| {
        if (mask & effect_set.bit(effect) != 0) {
            if (separator) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, @tagName(effect));
            separator = true;
        }
    }
}
fn boundSpan(reference: ast.BoundReference) source.Span {
    return if (reference.alias) |alias| source.Span.join(alias, reference.name) else reference.name;
}
/// The first non-empty line of a docstring with surrounding whitespace trimmed.
fn firstDocLine(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const end = std.mem.indexOfScalar(u8, trimmed, '\n') orelse return trimmed;
    return std.mem.trimEnd(u8, trimmed[0..end], " \t\r");
}
fn parameterCopy(src: source.Source, parameter: ast.TypeParameter) bool {
    if (parameter.default_copy) return true;
    for (parameter.requirements) |span| {
        const name = src.text(span);
        if (std.mem.eql(u8, name, "copy") or std.mem.eql(u8, name, "equality") or std.mem.eql(u8, name, "integer")) return true;
    }
    return false;
}
/// Parse and index every module before checking exported signature visibility.
pub fn build(project: *graph.Project) (diagnostic.Error || error{IncompleteProject})!Index {
    return buildWithCache(project, null, null);
}
/// Reuse unchanged parse tables from either an in-process syntax cache, a
/// persistent content-addressed frontend cache, or both, while rebuilding every
/// symbol, export and exported signature check.
pub fn buildWithCache(project: *graph.Project, cache: ?*SyntaxCache, frontend: ?*FrontendCache) (diagnostic.Error || error{IncompleteProject})!Index {
    return buildWithCacheTimed(project, cache, frontend, null);
}
/// Same as `buildWithCache`, with optional opt-in phase timing. Syntax replay and
/// parse are accumulated per module; `declarations_interfaces` is the remaining
/// inclusive wall interval of this function (index construction plus signature
/// validation), so the two records do not double-count syntax work.
pub fn buildWithCacheTimed(
    project: *graph.Project,
    cache: ?*SyntaxCache,
    frontend: ?*FrontendCache,
    timing: ?*@import("timings.zig").Profile,
) (diagnostic.Error || error{IncompleteProject})!Index {
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    const allocator = project.arena.allocator();
    const include_timing = if (timing) |profile| profile.enabled else false;
    const total_start = if (include_timing) timing.?.now() else std.Io.Timestamp.zero;
    var syntax_ns: i96 = 0;
    var index: Index = .{ .project = project, .units = try allocator.alloc(Unit, project.modules.items.len) };
    for (project.order.items) |module_id| {
        const module = project.modules.items[module_id];
        const syntax_start = if (include_timing) timing.?.now() else std.Io.Timestamp.zero;
        var replayed = false;
        const syntax = try moduleSyntax(project, module_id, cache, frontend, &replayed);
        if (include_timing) {
            const elapsed = syntax_start.durationTo(timing.?.now()).nanoseconds;
            syntax_ns += elapsed;
            timing.?.add(if (replayed) "syntax_replay" else "syntax_parse", elapsed, false);
        }
        index.units[module_id] = .{ .syntax = syntax };
        if (module.imports.len != 0) {
            const used = try allocator.alloc(bool, module.imports.len);
            @memset(used, false);
            index.units[module_id].import_used = used;
        }
        inline for (.{ "records", "domains", "variants", "resources" }) |field| {
            for (@field(syntax.types, field)) |declaration| try index.add(module_id, declaration.name, .type, null, false);
        }
        for (syntax.types.expressions.aliases) |alias| try index.add(module_id, alias.name, .type, null, false);
        for (syntax.types.constraints) |constraint| try index.add(module_id, constraint.name, .constraint, null, false);
        for (syntax.functions) |function| try index.add(module_id, function.name, .function, function.policy.owner, function.policy.restricted);
        for (module.exports) |exported| {
            if (exported.alias) |alias| {
                const target = try index.resolveExported(module_id, alias, exported.name, exported.span);
                try index.addFacade(module_id, exported.name, exported.span, target);
                continue;
            }
            const id = index.units[module_id].names.get(exported.name) orelse return project.fail(eUnknownExport, "export names no local declaration", .{ .module = module_id, .span = exported.span }, null);
            if (ast.isPublicDeclaration(syntax, index.units[module_id].symbols.items[id].span)) return project.fail("E_DUPLICATE_EXPORT", "declaration is already public", .{ .module = module_id, .span = exported.span }, null);
            index.units[module_id].symbols.items[id].exported = true;
        }
        // A declaration marked `public` publishes itself, exactly as an `export`
        // directive naming it would; the directive form stays accepted so an
        // existing source keeps its meaning.
        for (syntax.types.public_declarations) |span| {
            const id = index.units[module_id].names.get(module.src.text(span)) orelse return project.fail(eUnknownExport, "public declaration names no local declaration", .{ .module = module_id, .span = span }, null);
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
    if (include_timing) {
        const elapsed = total_start.durationTo(timing.?.now()).nanoseconds;
        timing.?.add("declarations_interfaces", @max(0, elapsed - syntax_ns), false);
    }
    return index;
}

fn sameOwner(local: bool, owner: ?[]const u8, declared: []const u8) bool {
    if (!local) return false;
    return std.mem.eql(u8, owner orelse return false, declared);
}

fn moduleSyntax(project: *graph.Project, module_id: usize, cache: ?*SyntaxCache, frontend: ?*FrontendCache, replayed: *bool) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    const allocator = project.arena.allocator();
    replayed.* = false;
    if (cache) |retained| {
        if (try retained.lookup(allocator, module.src, module.header.body_start)) |syntax| {
            replayed.* = true;
            return syntax;
        }
    }
    // A persistent hit still rebuilds every symbol and signature check below; it
    // only skips lexing and parsing. A rejected or damaged entry is a miss.
    if (frontend) |disk| {
        if (try disk.lookupSyntax(allocator, module.src, module.header.body_start)) |syntax| {
            replayed.* = true;
            return syntax;
        }
    }
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const syntax = parseModule(project, module_id, &sink) catch |err| {
        if (err != error.SourceError) return err;
        const problem = sink.items.items[0];
        return project.fail(problem.code, problem.message, .{ .module = module_id, .span = problem.span }, null);
    };
    if (cache) |retained| try retained.remember(module.src, module.header.body_start, syntax);
    if (frontend) |disk| try disk.rememberSyntax(module.src, module.header.body_start, syntax);
    return syntax;
}
fn parseModule(project: *graph.Project, module_id: usize, sink: *diagnostic.Sink) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    const tokens = try lexer.lexWithMarkers(project.arena.allocator(), module.src.bytes, module.src.mutation_markers, sink);
    var parse: parser.Parser = .{ .src = module.src, .arena = &project.arena, .tokens = tokens, .sink = sink };
    return parse.parseModule();
}

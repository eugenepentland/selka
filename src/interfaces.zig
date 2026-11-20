//! Module declaration identities and export boundaries, before body type checking.
const std = @import("std");
const check_directory = @import("check_directory.zig");
const declaration_borrow = @import("declaration_borrow.zig");
const component_adapter = @import("component_adapter.zig");
const contains_removed = @import("contains_removed.zig");
const guessed_names = @import("guessed_names.zig");
const import_fix = @import("import_fix.zig");
const prelude_names = @import("prelude_names.zig");
const standard_library = @import("standard_library.zig");
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
const number_literal = @import("number_literal.zig");
const parser = @import("parser.zig");
const typed = @import("typed.zig");
const generic_requirements = @import("generic_requirements.zig");
const structural_declarations = @import("structural_declarations.zig");
const fact_status = @import("fact_status.zig");
const prelude = @import("prelude.zig");
const tests_index = @import("tests_index.zig");
const SyntaxCache = @import("syntax_cache.zig").Cache;
const lazy_module = @import("lazy_module.zig");
const compile_mode = @import("builtin").mode;
const FrontendCache = @import("frontend_cache.zig").Cache;
const module_records = @import("module_records.zig");
/// One exported declaration's canonical declared contract for provider validation.
/// Exact fields (`signature`, `generics`, `shape`) compare for equality; the
/// permission field (`permissions`) uses the frozen directional subset relation
/// so a replacement may be narrower but never stronger.
pub const ContractDeclaration = struct {
    name: []const u8,
    kind: []const u8,
    signature: []const u8 = "",
    generics: []const u8 = "",
    /// `mutates=<positions>;origin=<tag>`; empty for non-callables.
    permissions: []const u8 = "",
    shape: []const u8 = "",
    /// Present only for a declaration carrying `@test`, so test discovery can
    /// admit a name that does not use the `test_` prefix.
    @"test": ?bool = null,
    /// The declaration's contract clauses (`@requires`, `@ensures`,
    /// `@invariant`) in source order, whitespace folded; absent when it has none.
    contracts: ?[]const u8 = null,
};
/// One module's exported declared-contract table.
pub const ContractModule = struct { name: []const u8, declarations: []const ContractDeclaration };
/// Versioned declaration-level contracts, independent of inferred body facts.
pub const ContractManifest = struct {
    version: []const u8 = "interface-contracts-v2",
    analysis: ?[]const u8 = null,
    modules: []const ContractModule,
};
/// Allocation, rejected declarations and an incomplete project all prevent a manifest.
pub const ContractError = diagnostic.Error || error{IncompleteProject};
/// Distinguish type declarations from callable declarations during name resolution.
pub const Kind = enum { type, function, constraint };
/// Identify a declaration by its module and local symbol index.
pub const Identity = struct { module: usize, symbol: usize };
/// One exported declaration a listing line renders, and the module it is listed under.
const Exported = struct { module: usize, symbol: Symbol };
/// A checked program's functions by name: `exact` by the whole qualified name,
/// `family` by the name before any `[...]` specialization suffix, each keeping
/// the first function in program order, which is the one a scan would find.
const FunctionTable = struct {
    exact: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    family: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
};
/// Store declaration visibility and optional domain-owner restrictions. A
/// re-export facade carries `re_export` pointing at the defining declaration in
/// its own module; every consumer resolves through that identity.
pub const Symbol = struct { name: []const u8, kind: Kind, span: source.Span, exported: bool = false, owner: ?[]const u8 = null, restricted: bool = false, re_export: ?Identity = null };
/// Store parsed module declarations and their local name index. `import_used`
/// carries one flag per direct import in this module's own order; the resolver
/// sets it when a reference actually resolves through that import, which is the
/// exact evidence `W_UNUSED_IMPORT` reads. `replayed` says the module's syntax came from a syntax cache, not a parse. `lazy` is set when the
/// syntax came from the syntax store as far as its declaration part: `syntax` then holds the declarations and, in tables of the full length,
/// only the trees outside every lazy body (`lazy_module.Module.sparseProgram`); the bodies are read when the merged program asks.
pub const Unit = struct { syntax: ast.Program, symbols: std.ArrayList(Symbol) = .empty, names: std.StringHashMapUnmanaged(usize) = .empty, import_used: []bool = &.{}, replayed: bool = false, lazy: ?*lazy_module.Module = null };
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
/// MODULE-INTERFACE-CUTOFF-1: one name a check looked up in a module's
/// declaration namespace, found or not.
pub const Lookup = struct { module: usize, name: []const u8 };

/// What a miss of a bare name adds when an imported module declares it: the sentence, and the qualifier a repair writes before the name.
pub const ImportedAnswer = struct { sentence: []const u8, qualifier: ?[]const u8 };

/// Storage belongs to project.arena. Do not retain this index after project.deinit.
pub const Index = struct {
    project: *graph.Project,
    units: []Unit,
    /// MODULE-INTERFACE-CUTOFF-1: when set, every name `resolve` (and a
    /// kind or constant probe) looks up in a module, found or missing, and
    /// the declaration a re-export resolves to, in project-arena storage.
    lookups: ?*std.ArrayList(Lookup) = null,
    /// Checked bodies, when available, for reachability and analysis status.
    program: ?typed.Program = null,
    /// The engine's decision on each module's prepared dependency keys (G2g), when an engine decides them; without it every module's
    /// keys are computed.
    decider: ?module_records.Decider = null,
    /// How this index's modules were read from the syntax store; the merge fills the program the same way.
    mode: lazy_module.Mode = .eager,
    fn add(self: *Index, module: usize, span: source.Span, kind: Kind, owner: ?source.Span, restricted: bool) diagnostic.Error!void {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        const name = src.text(span);
        const owner_name = if (owner) |at| src.text(at) else null;
        const key = if (owner_name) |prefix| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name }) else name;
        const unit = &self.units[module];
        if (unit.names.get(key)) |previous| return self.project.fail("E_DUPLICATE_SYMBOL", "module declaration name is already bound", .{ .module = module, .span = span }, .{ .module = module, .span = unit.symbols.items[previous].span });
        if (owner == null) for (self.project.modules.items[module].imports) |imported| {
            if (!std.mem.eql(u8, name, imported.alias) or check_directory.isTestStubMain(src.bytes, span)) continue;
            return self.project.fail("E_IMPORT_ALIAS", "declaration conflicts with an import alias", .{ .module = module, .span = span }, .{ .module = module, .span = imported.span });
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
        try self.noteLookup(target, name);
        const symbol_id = self.units[target].names.get(name) orelse {
            if (alias == null) if (try self.unimportedModule(from, name, span)) |failure| return failure;
            if (try self.guessedName(request, target)) |failure| return failure;
            if (try self.hiddenBuiltin(request)) |failure| return failure;
            if (try self.enumCase(request, target)) |failure| return failure;
            if (try self.importedDeclaration(request)) |failure| return failure;
            const message = try self.missMessage(from, target, alias, name, kind);
            return self.project.fail(eUnknownSymbol, message, site, null);
        };
        const symbol = self.units[target].symbols.items[symbol_id];
        const declaration: graph.Site = .{ .module = target, .span = symbol.span };
        const visible = target == from or symbol.exported or self.testsModule(from, target);
        if (!visible) return self.project.fail("E_PRIVATE_SYMBOL", "declaration is private to its module", site, declaration);
        if (symbol.restricted and !sameOwner(target == from, owner, symbol.owner.?)) return self.project.fail("E_PRIVATE_FUNCTION", "private domain function requires the same declaring domain", site, declaration);
        if (symbol.kind != kind) return self.project.fail(eSymbolKind, "declaration has the wrong kind for this reference", site, declaration);
        // A facade re-export resolves to the declaration that defines it, so the
        // caller sees the defining module's identity and the facade is only a name.
        if (symbol.re_export) |identity| {
            try self.noteLookup(identity.module, self.units[identity.module].symbols.items[identity.symbol].name);
            return identity;
        }
        return .{ .module = target, .symbol = symbol_id };
    }
    /// MODULE-INTERFACE-CUTOFF-1: record one name looked up in module
    /// `module`'s namespace when a caller asked for the record.
    pub fn noteLookup(self: *Index, module: usize, name: []const u8) std.mem.Allocator.Error!void {
        const list = self.lookups orelse return;
        try list.append(self.project.arena.allocator(), .{ .module = module, .name = name });
    }
    /// Whether module `from` is the test file of module `target`: it is named
    /// `<target>_test` and no module imports it, so it is a test entry and
    /// cannot hand the private declarations it reaches to anything else.
    pub fn testsModule(self: *const Index, from: usize, target: usize) bool {
        const modules = self.project.modules.items;
        const tester = modules[from].name;
        const tested = modules[target].name;
        if (tester.len != tested.len + "_test".len) return false;
        if (!std.mem.startsWith(u8, tester, tested) or !std.mem.endsWith(u8, tester, "_test")) return false;
        // A generated entry (a directory check's, or the check a directory test run's roots share) imports every module to load
        // it; that is no importer of a test file. Counting the shared check's entry made that check refuse a test file's call of
        // a private function its own check accepts, and flag the function private to its unit (FX10).
        for (modules) |module| if (!check_directory.isGeneratedEntry(module.name)) for (module.imports) |imported| {
            if (imported.target == from) return false;
        };
        return true;
    }
    /// The module that module `from` is the test file of (`testsModule`), or null. A name has at most one: `<target>_test`
    /// tests `<target>`. Its checked bodies may name that module's private declarations, so the semantic keys fold the answer
    /// (`semantic_key.prepare`) and the engine asks for a module's check under it (`module_check_facts.argumentOf`).
    pub fn testedModule(self: *const Index, from: usize) ?usize {
        const modules = self.project.modules.items;
        if (from >= modules.len or !std.mem.endsWith(u8, modules[from].name, "_test")) return null;
        const tested = modules[from].name[0 .. modules[from].name.len - "_test".len];
        for (modules, 0..) |module, target| {
            if (std.mem.eql(u8, module.name, tested)) return if (self.testsModule(from, target)) target else null;
        }
        return null;
    }
    /// Record that a module's direct import at `import_index` was used. A
    /// compiler-recognised module function (the scalar helpers) resolves before
    /// ordinary name resolution, so the header scan cannot see its qualifier
    /// inside an f-string interpolation; the checker notes it here instead.
    pub fn noteImportUse(self: *Index, module: usize, import_index: usize) void {
        if (module >= self.units.len) return;
        const used = self.units[module].import_used;
        if (import_index < used.len) used[import_index] = true;
    }
    /// Record the direct import one recorded reference goes through: the longest dotted
    /// qualifier of `text` (of `owner` for a domain member) that names an import's alias or
    /// full path. A body a summary stands in for is never resolved again, so its recorded
    /// references mark its imports, qualifiers inside f-string holes included.
    pub fn noteReferenceUse(self: *Index, module: usize, text: []const u8, owner: ?[]const u8) void {
        if (module >= self.project.modules.items.len) return;
        const spelled = owner orelse text;
        var end = spelled.len;
        if (owner == null) end = std.mem.lastIndexOfScalar(u8, spelled, '.') orelse return;
        while (true) {
            for (self.project.modules.items[module].imports, 0..) |imported, import_index| {
                if (!imported.matches(spelled[0..end])) continue;
                return self.noteImportUse(module, import_index);
            }
            end = std.mem.lastIndexOfScalar(u8, spelled[0..end], '.') orelse return;
        }
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
    /// match is a resolved qualified reference rather than a bare identifier. The
    /// holes of a format string hold expressions and are read as well.
    pub fn recoverImportUsage(self: *Index, backing: std.mem.Allocator) void {
        if (self.project.problem != null) return;
        var arena = std.heap.ArenaAllocator.init(backing);
        defer arena.deinit();
        const scratch = arena.allocator();
        for (self.project.order.items) |module_id| {
            const module = self.project.modules.items[module_id];
            if (module.imports.len == 0) continue;
            if (!module.header.usage_scanned) {
                var sink: diagnostic.Sink = .{ .allocator = scratch };
                const tokens = lexer.lex(scratch, module.src.bytes, &sink) catch continue;
                graph.markQualifiedImports(scratch, module.src, tokens, module.header.body_start, module.imports) catch continue;
            }
            for (module.imports, 0..) |imported, import_index| {
                if (imported.seen and import_index < self.units[module_id].import_used.len) self.units[module_id].import_used[import_index] = true;
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
    /// `strings.encode(text)` in a module that does not import `strings`: the qualifier is a standard module, not a name
    /// of this module, and the repair is the import line (W13-S5: `text.encode()` needed none). Null when `name` is not
    /// a standard module written as a qualifier.
    fn unimportedModule(self: *Index, from: usize, name: []const u8, span: source.Span) diagnostic.Error!?diagnostic.Error {
        const bytes = self.project.modules.items[from].src.bytes;
        if (span.end >= bytes.len or bytes[span.end] != '.' or !import_fix.standardModule(name)) return null;
        const allocator = self.project.arena.allocator();
        const message = try import_fix.unimportedMessage(allocator, name);
        const failure = self.project.fail(import_fix.code, message, .{ .module = from, .span = span }, null);
        self.project.problem.?.fix = try import_fix.edit(allocator, import_fix.placement(bytes, name), name);
        return failure;
    }
    /// `strings.contains(text, part)`, `strings.index(text, part)`, `lists.find(values, value)`: a function a standard module of one kind of
    /// value does not have, and an author guessed from another language. `guessed_names.answer` says what does the job for that kind of
    /// value, where the nearest spelling and the other modules that declare the name (`bytes.index`, `spans.is_empty`) would not. The
    /// repair is the call as the operator `in` when both operands are plain (`contains_removed.writtenCall`), or the same call under the
    /// name of the module's own function; none for any other answer. Null for any other miss.
    fn guessedName(self: *Index, request: Request, target: usize) diagnostic.Error!?diagnostic.Error {
        const alias = request.alias orelse return null;
        if (request.kind != .function) return null;
        const module_name = self.project.modules.items[target].name;
        const allocator = self.project.arena.allocator();
        if (standard_library.source(try std.fmt.allocPrint(allocator, "{s}.selka", .{module_name})) == null) return null;
        const src = self.project.modules.items[request.from].src;
        const spelled = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ alias, request.name });
        const written = contains_removed.writtenCall(src.bytes, request.span.start, spelled);
        const found = (try guessed_names.answer(allocator, module_name, alias, request.name, written)) orelse return null;
        const message = try std.fmt.allocPrint(allocator, "{s}; {s}", .{ try self.missHead(target, alias, request.name), found.sentence });
        const failure = self.project.fail(eUnknownSymbol, message, .{ .module = request.from, .span = request.span }, null);
        switch (found.repair) {
            .none => {},
            .operator => |receiver| if (written) |call| if (try contains_removed.inFix(allocator, src, receiver, call)) |repair| {
                self.project.problem.?.fix = repair.edit;
                self.project.problem.?.fix_more = repair.more;
            },
            .rename => |function| self.project.problem.?.fix = renameEdit(src.bytes, request.span.start, spelled, function),
        }
        return failure;
    }
    /// The edit that replaces the name in the call `spelled` (`strings.index`, as written at `start` and followed by its argument list) with
    /// `function`, or null when the text there is not that call.
    fn renameEdit(bytes: []const u8, start: usize, spelled: []const u8, function: []const u8) ?diagnostic.Edit {
        if (start > bytes.len or !std.mem.startsWith(u8, bytes[start..], spelled)) return null;
        const end = start + spelled.len;
        if (end >= bytes.len or bytes[end] != '(') return null;
        const dot = std.mem.indexOfScalar(u8, spelled, '.') orelse return null;
        return .{ .span = .{ .start = start + dot + 1, .end = end }, .text = function };
    }
    /// `argparse.MissingValue(name="db")` or `MissingValue(name="db")` where `MissingValue` is a case of an enum: a case is written with its
    /// enum (`argparse.Error.MissingValue`). When exactly one enum in reach has a case of the name (the exported enums of module `target`
    /// for a qualified call; for an unqualified one the enums of the module itself and of each module it imports) the message says
    /// `did you mean `Enum.case`?` and the repair writes the call with its enum. Null for any other miss: no enum, or two to choose from.
    fn enumCase(self: *Index, request: Request, target: usize) diagnostic.Error!?diagnostic.Error {
        if (request.kind == .constraint) return null;
        const allocator = self.project.arena.allocator();
        const from = request.from;
        var first: ?[]const u8 = null;
        var count: usize = 0;
        if (request.alias) |alias| {
            count = try self.enumsWithCase(from, target, alias, request.name, &first);
        } else {
            count = try self.enumsWithCase(from, from, null, request.name, &first);
            for (self.project.modules.items[from].imports) |imported| count += try self.enumsWithCase(from, imported.target, imported.alias, request.name, &first);
        }
        if (count != 1) return null;
        const message = try std.fmt.allocPrint(allocator, "{s}; did you mean `{s}`? A case of an enum is written with its enum", .{
            try self.missHead(target, request.alias, request.name), first.?,
        });
        const failure = self.project.fail(eUnknownSymbol, message, .{ .module = from, .span = request.span }, null);
        const bytes = self.project.modules.items[from].src.bytes;
        const spelled = if (request.alias) |alias| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ alias, request.name }) else request.name;
        const end = request.span.start + spelled.len;
        if (end < bytes.len and std.mem.startsWith(u8, bytes[request.span.start..], spelled) and bytes[end] == '(') {
            self.project.problem.?.fix = .{ .span = .{ .start = request.span.start, .end = end }, .text = first.? };
        }
        return failure;
    }
    /// `import bitio` and then `new_bitout()` or a parameter of type `BitOut`: the name is bare, this module declares none of that name, and a
    /// module the file imports declares it publicly, as the kind the position needs (a function or constant, a type). The message says which
    /// module, and with one module the repair writes the name with its qualifier (the alias the import gives). With two or three the message
    /// names them all and the author chooses, so there is no repair; with none, or more than three, null: the plain miss follows.
    fn importedDeclaration(self: *Index, request: Request) diagnostic.Error!?diagnostic.Error {
        if (request.alias != null) return null;
        const answer = (try self.importedAnswer(request.from, request.name, request.kind)) orelse return null;
        const allocator = self.project.arena.allocator();
        const message = try std.fmt.allocPrint(allocator, "{s}; {s}", .{ try self.missHead(request.from, null, request.name), answer.sentence });
        const failure = self.project.fail(eUnknownSymbol, message, .{ .module = request.from, .span = request.span }, null);
        const qualifier = answer.qualifier orelse return failure;
        const bytes = self.project.modules.items[request.from].src.bytes;
        if (bareAt(bytes, request.span.start, request.name)) self.project.problem.?.fix = .{
            .span = .{ .start = request.span.start, .end = request.span.start },
            .text = qualifier,
        };
        return failure;
    }
    /// What a miss of the bare `name` (of `kind`) in module `from` adds when modules it imports declare it: `sentence` names the module and
    /// the spelling, and `qualifier` (`bitio.`) is the text a repair writes before the name, null when two or three modules declare it.
    /// Null when none does, when more than three do, and for a private declaration or one of another kind (a function call may construct a
    /// record: `constructs`). Every imported module is looked up by name for the cutoff (`noteLookup`), so a module that later declares the
    /// name re-checks `from`.
    pub fn importedAnswer(self: *Index, from: usize, name: []const u8, kind: Kind) diagnostic.Error!?ImportedAnswer {
        if (kind == .constraint) return null;
        const allocator = self.project.arena.allocator();
        const module = self.project.modules.items[from];
        var declaring: [3]graph.Import = undefined;
        var count: usize = 0;
        for (module.imports, 0..) |imported, position| {
            const repeated = for (module.imports[0..position]) |earlier| {
                if (earlier.target == imported.target) break true;
            } else false;
            if (repeated or imported.target == from) continue;
            try self.noteLookup(imported.target, name);
            const symbol_id = self.units[imported.target].names.get(name) orelse continue;
            const symbol = self.units[imported.target].symbols.items[symbol_id];
            if (!self.offers(imported.target, symbol, kind)) continue;
            if (count < declaring.len) declaring[count] = imported;
            count += 1;
        }
        if (count == 0 or count > declaring.len) return null;
        if (count == 1) return .{
            .sentence = try std.fmt.allocPrint(allocator, "the imported module {s} declares it: write `{s}.{s}`", .{ try self.importedName(declaring[0]), declaring[0].alias, name }),
            .qualifier = try std.fmt.allocPrint(allocator, "{s}.", .{declaring[0].alias}),
        };
        var modules: std.ArrayList(u8) = .empty;
        var spellings: std.ArrayList(u8) = .empty;
        for (declaring[0..count], 0..) |imported, position| {
            const last = position + 1 == count;
            try modules.print(allocator, "{s}{s}", .{ if (position == 0) "" else if (last) " and " else ", ", try self.importedName(imported) });
            try spellings.print(allocator, "{s}`{s}.{s}`", .{ if (position == 0) "" else if (last) " or " else ", ", imported.alias, name });
        }
        return .{ .sentence = try std.fmt.allocPrint(allocator, "the imported modules {s} each declare it: write {s}, whichever you mean", .{ modules.items, spellings.items }), .qualifier = null };
    }
    /// Whether the text at `start` is the bare `name`: it is there, and no `.` or name character comes before it.
    pub fn bareAt(bytes: []const u8, start: usize, name: []const u8) bool {
        if (start > bytes.len or !std.mem.startsWith(u8, bytes[start..], name)) return false;
        return start == 0 or !(bytes[start - 1] == '.' or std.ascii.isAlphanumeric(bytes[start - 1]) or bytes[start - 1] == '_');
    }
    /// Whether a reference of `kind` may be answered with `symbol` of module `target`: it is public, and of that kind or a record the call constructs.
    fn offers(self: *Index, target: usize, symbol: Symbol, kind: Kind) bool {
        if (!symbol.exported) return false;
        return symbol.kind == kind or self.constructs(target, symbol, kind);
    }
    /// Whether `symbol`, a type of module `target`, is the record that the call `Name(field=...)` of a `kind` reference constructs: the call is
    /// resolved as a function, and the record is written with its module's qualifier like a function.
    fn constructs(self: *Index, target: usize, symbol: Symbol, kind: Kind) bool {
        if (kind != .function or symbol.kind != .type) return false;
        const src = self.project.modules.items[target].src;
        for (self.units[target].syntax.types.records) |record| {
            if (std.mem.eql(u8, src.text(record.name), symbol.name)) return true;
        }
        return false;
    }
    /// An imported module as a message names it: `` `bitio` ``, or `` `bitio` (imported as `b`) `` when the import renames it.
    fn importedName(self: *Index, imported: graph.Import) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        const module_name = self.project.modules.items[imported.target].name;
        if (std.mem.eql(u8, module_name, imported.alias)) return std.fmt.allocPrint(allocator, "`{s}`", .{module_name});
        return std.fmt.allocPrint(allocator, "`{s}` (imported as `{s}`)", .{ module_name, imported.alias });
    }
    /// How many enums of module `module` that module `from` can see have a case `name`, and in `first` the spelling of the first one's
    /// case from `from`: `Enum.case`, or `qualifier.Enum.case` when `qualifier` is the alias that reaches the module. An enum may carry
    /// payloads (`is_union`); a `result` and the unexported enums of another module are not counted.
    fn enumsWithCase(self: *Index, from: usize, module: usize, qualifier: ?[]const u8, name: []const u8, first: *?[]const u8) std.mem.Allocator.Error!usize {
        const allocator = self.project.arena.allocator();
        const unit = self.units[module];
        const src = self.project.modules.items[module].src;
        var count: usize = 0;
        for (unit.syntax.types.variants) |variant| {
            if (variant.fallible) continue;
            const enum_name = src.text(variant.name);
            const symbol_id = unit.names.get(enum_name) orelse continue;
            if (module != from and !unit.symbols.items[symbol_id].exported) continue;
            for (variant.cases) |case| {
                if (!std.mem.eql(u8, src.text(case.name), name)) continue;
                count += 1;
                if (first.* != null) continue;
                first.* = if (qualifier) |alias|
                    try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ alias, enum_name, name })
                else
                    try std.fmt.allocPrint(allocator, "{s}.{s}", .{ enum_name, name });
            }
        }
        return count;
    }
    /// `import sort` and then `sort(mut values)`: the imported module owns the name `sort`, so the call is read as a call of the
    /// module, which declares no function of that name, and the builtin is out of reach. The message says so, and names what to
    /// write: a function of the module (`hiddenWrite`), or no import. The repair deletes the import line when the call is written
    /// as the builtin is (`sort(mut values)`) and the module is named nowhere else in the file (no `sort.` qualifier), which leaves
    /// the builtin the author called; null for any other miss.
    fn hiddenBuiltin(self: *Index, request: Request) diagnostic.Error!?diagnostic.Error {
        if (request.alias != null or request.kind != .function or !prelude_names.isPrelude(request.name)) return null;
        const module = self.project.modules.items[request.from];
        const imported = for (module.imports) |candidate| {
            if (std.mem.eql(u8, candidate.alias, request.name)) break candidate;
        } else return null;
        const allocator = self.project.arena.allocator();
        const write = try self.hiddenWrite(imported.target, request.name);
        const message = try std.fmt.allocPrint(allocator, "{s}; `{s}` here names the imported module `{s}`, which hides the builtin `{s}`: write {s}, or remove `import {s}` to reach the builtin", .{
            try self.missHead(request.from, null, request.name), request.name, request.name, request.name, write, request.name,
        });
        const failure = self.project.fail(eUnknownSymbol, message, .{ .module = request.from, .span = request.span }, null);
        const builtin_form = try std.fmt.allocPrint(allocator, "{s}(mut ", .{request.name});
        const written_builtin = request.span.start <= module.src.bytes.len and std.mem.startsWith(u8, module.src.bytes[request.span.start..], builtin_form);
        if (written_builtin and importRemovalCertain(module.src.bytes, request.name)) if (import_fix.importLine(module.src.bytes, imported.span)) |line| {
            self.project.problem.?.fix = .{ .span = line, .text = "" };
        };
        return failure;
    }
    /// What `hiddenBuiltin` says to write instead: a function of the module, with up to two as examples (`siblingFunctions`), and for
    /// a standard module where the whole list is (`selka reference --query NAME`), so the sentence does not go stale as the module grows.
    fn hiddenWrite(self: *Index, target: usize, name: []const u8) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        const examples = try self.siblingFunctions(target, name);
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(allocator, "a function of the module");
        for (examples, 0..) |function, position| {
            try text.print(allocator, "{s}`{s}.{s}(...)`", .{ if (position == 0) ", such as " else " or ", name, function });
        }
        if (examples.len == 0) try text.print(allocator, ", as `{s}.NAME(...)`", .{name});
        if (standard_library.source(try std.fmt.allocPrint(allocator, "{s}.selka", .{name})) != null)
            try text.print(allocator, " (`selka reference --query {s}` lists them)", .{name});
        return text.items;
    }
    /// At most two functions of module `target` that stand where the builtin `name` was written: the exported ones named `name_...`,
    /// those that take their first parameter `mut` (the shape of `name(mut values)`) when there are any, else all of them; the
    /// shorter name first, the same length in alphabetical order. The names are read from the module, so each exists.
    fn siblingFunctions(self: *Index, target: usize, name: []const u8) std.mem.Allocator.Error![]const []const u8 {
        const allocator = self.project.arena.allocator();
        const unit = self.units[target];
        const prefix = try std.fmt.allocPrint(allocator, "{s}_", .{name});
        var in_place: std.ArrayList([]const u8) = .empty;
        var all: std.ArrayList([]const u8) = .empty;
        for (unit.syntax.functions) |function| {
            const written = self.project.modules.items[target].src.text(function.name);
            const symbol_id = unit.names.get(written) orelse continue;
            if (!std.mem.startsWith(u8, written, prefix) or !unit.symbols.items[symbol_id].exported) continue;
            try all.append(allocator, written);
            if (function.signature.mut_positions.len != 0 and function.signature.mut_positions[0] == 0) try in_place.append(allocator, written);
        }
        const chosen = if (in_place.items.len != 0) in_place.items else all.items;
        std.mem.sort([]const u8, chosen, {}, shorterFirst);
        return chosen[0..@min(chosen.len, 2)];
    }
    /// Message for a name module `target` does not declare (F-51): it names the module as the reference spelled it and, for
    /// a function, the close names that module has and the standard modules that declare the exact name.
    fn missMessage(self: *Index, from: usize, target: usize, alias: ?[]const u8, name: []const u8, kind: Kind) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        const module_name = self.project.modules.items[target].name;
        const head = try self.missHead(target, alias, name);
        if (kind != .function) return head;
        const near = try self.functionMissMessage(from, target, name);
        const standard = alias != null and standard_library.source(try std.fmt.allocPrint(allocator, "{s}.selka", .{module_name})) != null;
        var found: [5][]const u8 = undefined;
        const count = if (standard) standard_library.exporting(name, module_name, &found) else 0;
        if (count == 0) return std.fmt.allocPrint(allocator, "{s}{s}", .{ head, near });
        var modules: std.ArrayList(u8) = .empty;
        for (found[0..count], 0..) |module, index| {
            if (index != 0) try modules.appendSlice(allocator, if (index + 1 == count) " and " else ", ");
            try modules.print(allocator, "`{s}`", .{module});
        }
        return std.fmt.allocPrint(allocator, "{s}{s}{s} standard module{s} {s} declare{s} a function `{s}` ({s} `{s}.{s}(...)`)", .{
            head,                        near,                                                          if (near.len == 0) "; the" else " The",
            if (count == 1) "" else "s", modules.items,                                                 if (count == 1) "s" else "",
            name,                        if (count == 1) "import it and call" else "import one, as in", found[0],
            name,
        });
    }
    /// The first words of the message for a name module `target` does not declare: the module as the reference spelled it.
    fn missHead(self: *Index, target: usize, alias: ?[]const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        const module_name = self.project.modules.items[target].name;
        const spelled = alias orelse return std.fmt.allocPrint(allocator, "this module declares no `{s}`", .{name});
        const hidden = try self.hiddenLocalFile(module_name);
        if (std.mem.eql(u8, spelled, module_name)) return std.fmt.allocPrint(allocator, "module `{s}` declares no `{s}`{s}", .{ spelled, name, hidden });
        return std.fmt.allocPrint(allocator, "module `{s}` (imported as `{s}`) declares no `{s}`{s}", .{ module_name, spelled, name, hidden });
    }
    /// What a message about a standard module `module_name` that lacks a name adds when the project has a file of that name beside
    /// the entry (`Options.standard.hidden`): the loader reads the standard module, so the file is not used. Empty otherwise.
    fn hiddenLocalFile(self: *Index, module_name: []const u8) std.mem.Allocator.Error![]const u8 {
        if (self.project.progress.hidden_standard.len == 0) return "";
        const allocator = self.project.arena.allocator();
        const file = try std.fmt.allocPrint(allocator, "{s}.selka", .{module_name});
        if (standard_library.source(file) == null) return "";
        for (self.project.progress.hidden_standard) |local| if (std.mem.eql(u8, local, file)) {
            return std.fmt.allocPrint(allocator, "; `{s}` here is the standard module, so your `{s}` is not used: rename it", .{ module_name, file });
        };
        return "";
    }
    /// The close function names module `target` has for an unresolved `name`, as `; did you mean ...?`, or empty: those within edit
    /// distance two, else those that contain `name` or that it contains once underscores are left out (`splitlines` holds `lines`
    /// and `split`), at most three. They are only named: a nearest name is a guess, and a diagnostic carries a fix only where the
    /// edit is certain (`strings.rfind` one edit from `strings.find` is another function), so `selka fix` leaves the file alone.
    fn functionMissMessage(self: *Index, from: usize, target: usize, name: []const u8) std.mem.Allocator.Error![]const u8 {
        const allocator = self.project.arena.allocator();
        var candidates: std.ArrayList([]const u8) = .empty;
        defer candidates.deinit(allocator);
        var contained: std.ArrayList([]const u8) = .empty;
        defer contained.deinit(allocator);
        for (self.units[target].symbols.items) |symbol| {
            if (symbol.kind != .function) continue;
            if (std.mem.indexOfScalar(u8, symbol.name, '.') != null) continue;
            if (target != from and !symbol.exported) continue;
            if (std.mem.eql(u8, symbol.name, name)) continue;
            if (typed.editDistanceAtMost(symbol.name, name, 2) <= 2) {
                try candidates.append(allocator, symbol.name);
            } else if (sharesName(symbol.name, name)) try contained.append(allocator, symbol.name);
        }
        const listed = if (candidates.items.len != 0) &candidates else &contained;
        if (listed.items.len == 0) return "";
        if (candidates.items.len != 0) std.mem.sort([]const u8, listed.items, {}, tokenLess) else std.mem.sort([]const u8, listed.items, {}, longerFirst);
        const shown = listed.items[0..@min(listed.items.len, 3)];
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(allocator);
        for (shown, 0..) |candidate, index| {
            if (index != 0) try joined.appendSlice(allocator, "`, `");
            try joined.appendSlice(allocator, candidate);
        }
        return std.fmt.allocPrint(allocator, "; did you mean {s}`{s}`?", .{ if (shown.len == 1) "" else "one of: ", joined.items });
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
    /// Whether `module` declares a type named `name`. An import alias of that
    /// name is not a declaration, so it cannot shadow a built-in scalar type (L18).
    fn declaresType(self: *Index, module: usize, name: []const u8) bool {
        for (self.units[module].symbols.items) |symbol| {
            if (symbol.kind != .type) continue;
            if (std.mem.eql(u8, symbol.name, name)) return true;
        }
        return false;
    }

    fn signatureType(self: *Index, module: usize, span: source.Span) diagnostic.Error!void {
        const syntax = self.units[module].syntax;
        for (syntax.types.expressions.suffixes) |suffix| {
            if (suffix.span.start == span.start and suffix.span.end == span.end) return self.signatureType(module, suffix.base);
        }
        for (syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            for (callback.parameters) |parameter| try self.signatureType(module, parameter);
            try self.signatureType(module, callback.return_type);
            if (callback.failure_type) |failure| try self.signatureType(module, failure);
            return;
        }
        for (syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .enum_type) try self.signatureType(module, array.index.enum_type);
            return self.signatureType(module, array.element);
        }
        // A tuple is structural: its element spans are checked in place and the
        // whole spelling names no declaration of its own.
        for (syntax.types.expressions.tuples) |tuple| {
            if (tuple.span.start != span.start or tuple.span.end != span.end) continue;
            for (tuple.elements) |element| try self.signatureType(module, element);
            return;
        }
        const src = self.project.modules.items[module].src;
        if (span.start == span.end or std.mem.eql(u8, src.text(span), "Unit") or std.mem.eql(u8, src.text(span), "()")) return;
        if (typed.Type.fromName(src.text(span)) != null) return;
        // A built-in scalar type is not a declaration, so an import alias that
        // shares one's name (`import bytes`) must not hide it (L18); a type the
        // module declares itself still wins.
        if (!self.declaresType(module, src.text(span)) and prelude.scalar(src.text(span))) return;
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

        // Re-lex this short name to normalize whitespace/comments around module
        // separators; a plain dotted spelling is decided without the lexer.
        const text = src.text(span);
        const qualified = switch (lexer.quickQualifiedName(text)) {
            .name => |quick| quick,
            .none => return error.InternalError,
            .slow => slow: {
                var sink: diagnostic.Sink = .{ .allocator = allocator };
                const tokens = try lexer.lex(allocator, text, &sink);
                break :slow lexer.qualifiedName(text, tokens) orelse return error.InternalError;
            },
        };
        return self.resolve(.{ .from = module, .alias = qualified.alias, .name = qualified.name, .kind = .type, .owner = null, .span = span });
    }
    fn requirePublicType(self: *Index, module: usize, span: source.Span, id: Identity) diagnostic.Error!void {
        const symbol = self.units[id.module].symbols.items[id.symbol];
        if (!symbol.exported) return self.project.fail("E_PRIVATE_INTERFACE", "exported interface exposes an unexported type", .{ .module = module, .span = span }, .{ .module = id.module, .span = symbol.span });
    }
    /// Whether a merged-source function-name span names an exported declaration.
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
            if (std.mem.eql(u8, name, "FixedArray") or std.mem.eql(u8, name, "Simd")) {
                if (application.arguments.len != 2) return self.project.fail(eGenericArity, "FixedArray and Simd require an element type and length", .{ .module = module, .span = application.span }, null);
                return self.genericSignatureType(module, application.arguments[0], parameters);
            }
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
        for (self.units[module].syntax.types.expressions.suffixes) |suffix| {
            if (suffix.span.start == span.start and suffix.span.end == span.end) return self.genericSignatureType(module, suffix.base, parameters);
        }
        for (parameters) |parameter| if (std.mem.eql(u8, src.text(parameter.name), src.text(span))) return;
        for (self.units[module].syntax.types.expressions.applications) |application| {
            if (application.span.start == span.start and application.span.end == span.end) return self.applicationType(module, application, parameters);
        }
        for (self.units[module].syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            for (callback.parameters) |parameter| try self.genericSignatureType(module, parameter, parameters);
            try self.genericSignatureType(module, callback.return_type, parameters);
            if (callback.failure_type) |failure| try self.genericSignatureType(module, failure, parameters);
            return;
        }
        for (self.units[module].syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .enum_type) try self.genericSignatureType(module, array.index.enum_type, parameters);
            return self.genericSignatureType(module, array.element, parameters);
        }
        for (self.units[module].syntax.types.expressions.tuples) |tuple| {
            if (tuple.span.start != span.start or tuple.span.end != span.end) continue;
            for (tuple.elements) |element| try self.genericSignatureType(module, element, parameters);
            return;
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
            for (variant.cases) |case| {
                if (case.payload) |payload| try self.genericSignatureType(module, payload, variant.type_parameters);
                for (case.fields) |field| try self.genericSignatureType(module, field.ty, variant.type_parameters);
            }
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
            if (function.signature.failure_type) |failure| try self.genericSignatureType(module, failure, function.signature.type_parameters);
        }
    }
    /// Render exported declarations and their checked reachability status.
    pub fn render(self: *Index, allocator: std.mem.Allocator) ContractError![]u8 {
        return self.renderUsing(allocator, .reference) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.SourceError => error.SourceError,
            error.IncompleteProject => error.IncompleteProject,
            else => error.InternalError,
        };
    }
    /// Render with the command host's explicit test-index component boundary.
    pub fn renderUsing(self: *Index, allocator: std.mem.Allocator, adapter: component_adapter.Adapter) (ContractError || component_adapter.Error)![]u8 {
        if (self.project.problem != null) return error.IncompleteProject;
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        // The `tests` column reads the same reachability index `tests-for`
        // answers from; it is absent when no checked program is attached.
        var tests: ?tests_index.Index = try self.buildTestsIndex(allocator, adapter);
        defer {
            if (tests) |*index| index.deinit();
        }
        const functions = try self.functionTable();
        output.writer.writeAll("module interfaces v1; declarations/signature visibility checked; bodies not type checked\n") catch return error.OutOfMemory;
        for (self.project.order.items) |module| {
            output.writer.print("module {s}\n", .{self.project.modules.items[module].name}) catch return error.OutOfMemory;
            for (self.units[module].symbols.items) |symbol| {
                if (!symbol.exported) continue;
                if (symbol.kind == .function) {
                    try self.renderFunctionLine(&output.writer, .{ .module = module, .symbol = symbol }, if (tests) |*index| index else null, &functions);
                    continue;
                }
                output.writer.print("  export {s} {s}", .{ @tagName(symbol.kind), symbol.name }) catch return error.OutOfMemory;
                const origin = self.declarationSource(module, symbol);
                try self.appendContractClauses(&output.writer, origin.module, origin.symbol);
                try self.appendDocstringLine(&output.writer, module, symbol);
                output.writer.writeAll("\n") catch return error.OutOfMemory;
            }
        }
        return output.toOwnedSlice();
    }
    /// Render one canonical signature, analysis status, tests and contract clauses.
    fn renderFunctionLine(self: *Index, writer: *std.Io.Writer, exported: Exported, tests: ?*const tests_index.Index, functions: *const FunctionTable) ContractError!void {
        const origin = self.declarationSource(exported.module, exported.symbol);
        const function = self.findFunction(self.units[origin.module], origin.symbol.span) orelse return error.InternalError;
        const signature = try self.contractSignatureText(origin.module, function.signature);
        const analysis = if (try self.programFunction(origin.module, origin.symbol.name, functions) != null)
            .checked
        else
            unavailableAnalysis(self.program, function);
        // A `builtin func` is listed with its word: the compiler supplies its calls, and it has no body (W10).
        const supplied = if (function.policy.builtin) "builtin " else "";
        writer.print("  export {s}function {s} {s} analysis({s})", .{ supplied, origin.display, signature, fact_status.name(analysis) }) catch return error.OutOfMemory;
        if (tests) |index| {
            if (try self.programFunction(origin.module, origin.symbol.name, functions)) |id| {
                const answer = index.answer(id);
                writer.print(" tests({d})", .{answer.reached.len}) catch return error.OutOfMemory;
            }
        } else {
            writer.writeAll(" tests(unavailable)") catch return error.OutOfMemory;
        }
        try self.appendContractClauses(writer, origin.module, origin.symbol);
        try self.appendDocstringLine(writer, origin.module, origin.symbol);
        writer.writeAll("\n") catch return error.OutOfMemory;
    }
    /// The checked function identity of one module-qualified declaration, or
    /// null when the attached program carries no such name.
    fn programFunction(self: *Index, module: usize, name: []const u8, functions: *const FunctionTable) ContractError!?typed.FunctionId {
        const qualified = try std.fmt.allocPrint(self.project.arena.allocator(), qualified_name_format, .{ self.project.modules.items[module].name, name });
        return functions.exact.get(qualified);
    }
    /// Index the attached program's functions by name once per listing, so
    /// each exported callable finds its checked entry with one lookup rather
    /// than a scan of every function (quadratic on a large project). Empty when
    /// no checked program is attached.
    fn functionTable(self: *Index) ContractError!FunctionTable {
        var table: FunctionTable = .{};
        const program = self.program orelse return table;
        const allocator = self.project.arena.allocator();
        for (program.functions, 0..) |function, index| {
            const id: typed.FunctionId = @fromBackingInt(@intCast(index));
            const exact = try table.exact.getOrPut(allocator, function.name);
            if (!exact.found_existing) exact.value_ptr.* = id;
            const base = function.name[0 .. std.mem.indexOfScalar(u8, function.name, '[') orelse function.name.len];
            const family = try table.family.getOrPut(allocator, base);
            if (!family.found_existing) family.value_ptr.* = id;
        }
        return table;
    }
    /// Build the shared tests index for the attached checked program, or null
    /// when no bodies were checked.
    fn buildTestsIndex(self: *Index, allocator: std.mem.Allocator, adapter: component_adapter.Adapter) (ContractError || component_adapter.Error)!?tests_index.Index {
        const program = self.program orelse return null;
        const scratch = self.project.arena.allocator();
        const modules = try self.moduleSyntax(scratch);
        const call_graph = try tests_index.callGraph(scratch, program);
        const discovered = try tests_index.discoveredTests(scratch, program, modules);
        const built = try adapter.build(allocator, program, call_graph, discovered);
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
    /// The contract clauses above one declaration, each spelled as written with
    /// its whitespace folded and joined by one space, or null when it has none.
    fn contractClauses(self: *Index, module: usize, declaration: source.Span) ContractError!?[]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        var out: std.ArrayList(u8) = .empty;
        for (ast.attributesOf(self.units[module].syntax, declaration)) |attribute| {
            if (!attribute.kind.contract()) continue;
            if (out.items.len != 0) try out.append(allocator, ' ');
            try appendFolded(&out, allocator, src.text(attribute.span));
        }
        if (out.items.len == 0) return null;
        const clauses = try out.toOwnedSlice(allocator);
        return clauses;
    }
    /// Append ` <clauses>` for a declaration that carries contract clauses.
    fn appendContractClauses(self: *Index, writer: *std.Io.Writer, module: usize, symbol: Symbol) ContractError!void {
        const clauses = try self.contractClauses(module, symbol.span) orelse return;
        writer.print(" {s}", .{clauses}) catch return error.OutOfMemory;
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
    /// Render declared signatures and mutation contracts for replacement validation.
    pub fn renderContracts(self: *Index, allocator: std.mem.Allocator) ContractError![]u8 {
        if (self.project.problem != null) return error.IncompleteProject;
        // Intermediate tables live in the project arena; only the final JSON text
        // is owned by the caller. This keeps a one-shot listing leak-free.
        const scratch = self.project.arena.allocator();
        var modules: std.ArrayList(ContractModule) = .empty;
        for (self.project.order.items) |module| try modules.append(scratch, try self.contractModule(module));
        std.mem.sort(ContractModule, modules.items, {}, moduleLess);
        return std.json.Stringify.valueAlloc(allocator, ContractManifest{
            .analysis = if (self.program == null) fact_status.name(.declaration_only) else null,
            .modules = try modules.toOwnedSlice(scratch),
        }, .{ .emit_null_optional_fields = false });
    }
    /// MODULE-TEST-4: module `module`'s entry of `renderContracts`: its
    /// exported declarations and its discovered tests, sorted by name,
    /// allocated in the project arena.
    pub fn contractModule(self: *Index, module: usize) ContractError!ContractModule {
        const scratch = self.project.arena.allocator();
        var declarations: std.ArrayList(ContractDeclaration) = .empty;
        for (self.units[module].symbols.items) |symbol| {
            // `selka test` discovers `test_` functions by name and `@test`
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
        return .{ .name = self.project.modules.items[module].name, .declarations = try declarations.toOwnedSlice(scratch) };
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
        return declaration.generics.len == 0 and std.mem.eql(u8, declaration.signature, "func()->bool");
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
    /// The function declaration in `unit` whose name has this span, if any.
    pub fn findFunction(self: *Index, unit: Unit, span: source.Span) ?ast.Function {
        _ = self;
        for (unit.syntax.functions) |function| {
            if (function.name.start == span.start and function.name.end == span.end) return function;
        }
        return null;
    }
    fn contractFunction(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const function = self.findFunction(self.units[module], symbol.span) orelse return error.InternalError;
        var out: ContractDeclaration = .{ .name = symbol.name, .kind = "function" };
        out.generics = try self.contractGenericsText(module, function.signature.type_parameters);
        out.signature = try self.contractSignatureText(module, function.signature);
        out.permissions = try permissionsText(self.project.arena.allocator(), function.signature.mut_positions, if (function.signature.borrowing.len == 0) "fresh" else "params");
        if (ast.hasAttribute(self.units[module].syntax, function.name, .@"test")) out.@"test" = true;
        out.contracts = try self.contractClauses(module, function.name);
        return out;
    }
    fn contractSignatureText(self: *Index, module: usize, signature: ast.FunctionSignature) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "func(");
        for (signature.parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            // Each named parameter carries its published label contract.
            if (parameter.named or (signature.keyword_only_from != null and index >= signature.keyword_only_from.?)) try out.appendSlice(allocator, "named ");
            if (parameter.own) try out.appendSlice(allocator, "own ");
            if (parameter.mut) try out.appendSlice(allocator, "mut ");
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
        const sources = try declaration_borrow.positions(allocator, src, signature);
        for (sources, 0..) |position, n| {
            try out.appendSlice(allocator, if (n == 0) " from " else ",");
            try out.appendSlice(allocator, src.text(signature.parameters[position].name));
        }
        if (signature.failure_type) |failure| {
            try out.appendSlice(allocator, " fails ");
            try out.appendSlice(allocator, try self.contractTypeText(module, failure, signature.type_parameters));
        }
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
            const tokens = try self.requirementTokens(module, parameter, parameters);
            for (tokens, 0..) |token, token_index| {
                if (token_index != 0) try out.appendSlice(allocator, "+");
                try out.appendSlice(allocator, token);
            }
        }
        try out.appendSlice(allocator, "]");
        return out.toOwnedSlice(allocator);
    }
    /// The sorted, duplicate-free requirement tokens one type parameter
    /// declares: `copy`, `length`, builtin bounds, qualified named constraints,
    /// `field(name:type)` and `op(...)` requirements. The slice and its text
    /// live in the project arena.
    pub fn requirementTokens(self: *Index, module: usize, parameter: ast.TypeParameter, parameters: []const ast.TypeParameter) ContractError![]const []const u8 {
        const allocator = self.project.arena.allocator();
        var tokens: std.ArrayList([]const u8) = .empty;
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
        return tokens.toOwnedSlice(allocator);
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
        try out.appendSlice(allocator, ")");
        return out.toOwnedSlice(allocator);
    }
    fn contractFieldDefault(self: *Index, shape: *std.ArrayList(u8), module: usize, default: ?ast.NodeId) ContractError!void {
        const value = default orelse return;
        const src = self.project.modules.items[module].src;
        const span = self.units[module].syntax.nodes.items[@backingInt(value)].span;
        const allocator = self.project.arena.allocator();
        try shape.appendSlice(allocator, "=");
        try shape.appendSlice(allocator, std.mem.trim(u8, src.text(span), " \t\r\n"));
    }
    fn contractType(self: *Index, module: usize, symbol: Symbol) ContractError!ContractDeclaration {
        const unit = self.units[module];
        for (unit.syntax.types.records) |record| {
            if (record.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "record" };
            out.generics = try self.contractGenericsText(module, record.type_parameters);
            out.shape = try self.contractFieldsText(module, record.fields, record.type_parameters);
            out.contracts = try self.contractClauses(module, record.name);
            return out;
        }
        for (unit.syntax.types.variants) |variant| {
            if (variant.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = if (variant.fallible) "result" else "enum" };
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
                } else if (case.fields.len != 0) {
                    // A parenthesized case is part of the exported contract: its
                    // named fields, their types and whether each has a default.
                    try shape.appendSlice(allocator, "(");
                    for (case.fields, 0..) |field, field_index| {
                        if (field_index != 0) try shape.appendSlice(allocator, ",");
                        try shape.appendSlice(allocator, self.project.modules.items[module].src.text(field.name));
                        try shape.appendSlice(allocator, ":");
                        try shape.appendSlice(allocator, try self.contractTypeText(module, field.ty, variant.type_parameters));
                        try self.contractFieldDefault(&shape, module, field.default_value);
                    }
                    try shape.appendSlice(allocator, ")");
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
            out.contracts = try self.contractClauses(module, domain.name);
            return out;
        }
        for (unit.syntax.types.resources) |resource| {
            if (resource.name.start != symbol.span.start) continue;
            var out: ContractDeclaration = .{ .name = symbol.name, .kind = "resource" };
            out.generics = try self.contractGenericsText(module, resource.type_parameters);
            // `resource NAME: family` names an external resource family
            // (`filesystem`, `network`), not a type, so it is rendered as written
            // rather than resolved as a declaration.
            out.shape = try std.fmt.allocPrint(self.project.arena.allocator(), "backing:{s}", .{self.project.modules.items[module].src.text(resource.backing)});
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
    /// Render one `tuple[T1, ..., Tn]` spelling as its canonical descriptor.
    /// Element descriptors are already canonical, so a tuple renders as
    /// `tuple[i64,str]` and the surface rewriter turns it into source spelling.
    fn contractTupleText(self: *Index, module: usize, tuple: ast.TupleType, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "tuple[");
        for (tuple.elements, 0..) |element, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, element, parameters, path));
        }
        try out.appendSlice(allocator, "]");
        return out.toOwnedSlice(allocator);
    }
    /// Render one declaration-level type spelled in `module` as its canonical
    /// descriptor (`i64`, `list[pkg::Name]`, `$0` for a type parameter); the
    /// text lives in the project arena.
    pub fn contractTypeText(self: *Index, module: usize, span: source.Span, parameters: []const ast.TypeParameter) ContractError![]const u8 {
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
        if (span.start == span.end or std.mem.eql(u8, text, "Unit") or std.mem.eql(u8, text, "()") or std.mem.eql(u8, text, "unit")) return allocator.dupe(u8, "Unit");
        for (self.units[module].syntax.types.expressions.suffixes) |suffix| {
            if (suffix.span.start != span.start or suffix.span.end != span.end) continue;
            const base = try self.contractTypeTextPath(module, suffix.base, parameters, path);
            return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, if (suffix.kind == .growable) "[]" else "?" });
        }
        for (parameters, 0..) |parameter, index| {
            if (std.mem.eql(u8, src.text(parameter.name), text)) return std.fmt.allocPrint(allocator, "${d}", .{index});
        }
        for (self.units[module].syntax.types.expressions.callbacks) |callback| {
            if (callback.span.start != span.start or callback.span.end != span.end) continue;
            return self.contractCallbackText(module, callback, parameters, path);
        }
        for (self.units[module].syntax.types.expressions.arrays) |array| {
            if (array.span.start != span.start or array.span.end != span.end) continue;
            if (array.index == .length) {
                const element = try self.contractTypeTextPath(module, array.element, parameters, path);
                const length = try canonicalLength(allocator, src.text(array.index.length));
                return std.fmt.allocPrint(allocator, "FixedArray[{s},{s}]", .{ element, length });
            }
            const index = try self.contractTypeTextPath(module, array.index.enum_type, parameters, path);
            const element = try self.contractTypeTextPath(module, array.element, parameters, path);
            return std.fmt.allocPrint(allocator, "[{s}]{s}", .{ index, element });
        }
        for (self.units[module].syntax.types.expressions.tuples) |tuple| {
            if (tuple.span.start != span.start or tuple.span.end != span.end) continue;
            return self.contractTupleText(module, tuple, parameters, path);
        }
        if (typed.Type.fromName(text)) |builtin| return allocator.dupe(u8, prelude.reservedTypeName(builtin) orelse typed.typeName(builtin, &.{}));
        if (!self.declaresType(module, text)) {
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
    fn contractCallbackText(self: *Index, module: usize, callback: ast.CallbackType, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const src = self.project.modules.items[module].src;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(allocator, "func(");
        for (callback.parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ",");
            const named = index < callback.parameter_modes.named.len and callback.parameter_modes.named[index];
            if (named) try out.appendSlice(allocator, "named ");
            if (index < callback.parameter_modes.mut.len and callback.parameter_modes.mut[index]) try out.appendSlice(allocator, "mut ");
            if (named and index < callback.parameter_names.len) if (callback.parameter_names[index]) |name| {
                try out.appendSlice(allocator, src.text(name));
                try out.appendSlice(allocator, ": ");
            };
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, parameter, parameters, path));
        }
        try out.appendSlice(allocator, ")->");
        try out.appendSlice(allocator, try self.contractTypeTextPath(module, callback.return_type, parameters, path));
        if (callback.failure_type) |failure| {
            try out.appendSlice(allocator, " fails ");
            try out.appendSlice(allocator, try self.contractTypeTextPath(module, failure, parameters, path));
        }

        return out.toOwnedSlice(allocator);
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
            if (std.mem.eql(u8, name, "FixedArray")) {
                if (application.arguments.len != 2) return self.project.fail(eGenericArity, "FixedArray requires an element type and length", .{ .module = module, .span = application.span }, null);
                const element = try self.contractTypeTextPath(module, application.arguments[0], parameters, path);
                const length = try self.contractLengthText(module, application.arguments[1], parameters, path);
                return std.fmt.allocPrint(allocator, "FixedArray[{s},{s}]", .{ element, length });
            }
            if (std.mem.eql(u8, name, "Simd")) {
                if (application.arguments.len != 2) return self.project.fail(eGenericArity, "Simd requires a lane type and length", .{ .module = module, .span = application.span }, null);
                const lane = try self.contractTypeTextPath(module, application.arguments[0], parameters, path);
                const length = try self.contractLengthText(module, application.arguments[1], parameters, path);
                return std.fmt.allocPrint(allocator, "Simd[{s},{s}]", .{ lane, length });
            }
            if ((std.mem.eql(u8, name, "list") or std.mem.eql(u8, name, "Option")) and application.arguments.len == 1) {
                const element = try self.contractTypeTextPath(module, application.arguments[0], parameters, path);
                return std.fmt.allocPrint(allocator, "{s}{s}", .{ element, if (std.mem.eql(u8, name, "list")) "[]" else "?" });
            }
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
    fn contractLengthText(self: *Index, module: usize, span: source.Span, parameters: []const ast.TypeParameter, path: *std.ArrayList(Identity)) ContractError![]const u8 {
        const allocator = self.project.arena.allocator();
        const text = self.project.modules.items[module].src.text(span);
        return switch (number_literal.count(text)) {
            .ok => |value| std.fmt.allocPrint(allocator, "{d}", .{value}),
            else => self.contractTypeTextPath(module, span, parameters, path),
        };
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
/// The decimal spelling of an array length, so `[0x10]u8` and `[16]u8` share one contract
/// descriptor; a text that is not a plain count is kept as written.
fn canonicalLength(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return switch (number_literal.count(text)) {
        .ok => |value| std.fmt.allocPrint(allocator, "{d}", .{value}),
        .bad => text,
    };
}
fn sameIdentity(a: Identity, b: Identity) bool {
    return a.module == b.module and a.symbol == b.symbol;
}
fn declarationLess(_: void, a: ContractDeclaration, b: ContractDeclaration) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn moduleLess(_: void, a: ContractModule, b: ContractModule) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
/// Whether `bytes` names the module `name` as a qualifier nowhere (`sort.sort_ints(...)`): a word `name` followed by a dot. Then the
/// import is used by nothing but the bare call it hides, and removing it changes no other reference.
fn importRemovalCertain(bytes: []const u8, name: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, name)) |found| : (at = found + name.len) {
        const end = found + name.len;
        const before_word = found != 0 and (std.ascii.isAlphanumeric(bytes[found - 1]) or bytes[found - 1] == '_' or bytes[found - 1] == '.');
        if (!before_word and end < bytes.len and bytes[end] == '.') return false;
    }
    return true;
}
fn tokenLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
/// The shorter name first, the same length in alphabetical order.
fn shorterFirst(_: void, a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return a.len < b.len;
    return std.mem.lessThan(u8, a, b);
}
/// The longer name first, the same length in alphabetical order: the name that shares most with a misspelling comes first.
fn longerFirst(_: void, a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return a.len > b.len;
    return std.mem.lessThan(u8, a, b);
}
/// Whether one of the names, with its underscores left out, holds the other, and the shorter has at least four bytes left.
fn sharesName(left: []const u8, right: []const u8) bool {
    var a: [128]u8 = undefined;
    var b: [128]u8 = undefined;
    const x = typed.plainName(&a, left, .{}) orelse return false;
    const y = typed.plainName(&b, right, .{}) orelse return false;
    const short = if (x.len <= y.len) x else y;
    const long = if (x.len <= y.len) y else x;
    return short.len >= 4 and std.mem.indexOf(u8, long, short) != null;
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
/// `mutates=<position list>;origin=<tag>`.
fn permissionsText(allocator: std.mem.Allocator, mutates: []const u16, origin: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "mutates=");
    for (mutates, 0..) |position, index| {
        if (index != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, "{d}", .{position}));
    }
    try out.appendSlice(allocator, ";origin=");
    try out.appendSlice(allocator, origin);
    return out.toOwnedSlice(allocator);
}
/// The status of an inferred summary this listing could not produce: `template`
/// when a checked program exists but never instantiated this generic
/// declaration, and `declaration-only` when the listing has no checked bodies at
/// all. A non-generic declaration missing from a checked program also reports
/// `declaration-only`, because no inferred summary is available for it either.
fn unavailableAnalysis(program: ?typed.Program, function: ast.Function) fact_status.Status {
    if (program == null) return .declaration_only;
    if (function.signature.type_parameters.len != 0) return .template;
    return .declaration_only;
}
fn boundSpan(reference: ast.BoundReference) source.Span {
    return if (reference.alias) |alias| source.Span.join(alias, reference.name) else reference.name;
}
/// Append `text` with every run of spaces, tabs and line breaks folded to one
/// space: the normalized spelling of a clause written across several lines.
pub fn appendFolded(out: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!void {
    var blank = false;
    for (text) |byte| {
        const space = byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
        if (space and blank) continue;
        blank = space;
        try out.append(allocator, if (space) ' ' else byte);
    }
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
    return buildWithMode(project, .{ .cache = cache, .frontend = frontend, .timing = timing, .mode = .eager });
}

/// What `buildWithMode` reads syntax from, and how.
pub const BuildOptions = struct {
    cache: ?*SyntaxCache = null,
    frontend: ?*FrontendCache = null,
    timing: ?*@import("timings.zig").Profile = null,
    /// `.lazy` reads a module the persistent cache holds as far as its declaration part, when no in-process cache serves it first.
    mode: lazy_module.Mode = .eager,
};

/// `buildWithCacheTimed` with the choice of reading stored modules completely or as far as their declarations (`BuildOptions.mode`).
pub fn buildWithMode(project: *graph.Project, options: BuildOptions) (diagnostic.Error || error{IncompleteProject})!Index {
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    const cache = options.cache;
    const frontend = options.frontend;
    const timing = options.timing;
    const allocator = project.arena.allocator();
    const include_timing = if (timing) |profile| profile.enabled else false;
    const total_start = if (include_timing) timing.?.now() else std.Io.Timestamp.zero;
    var syntax_ns: i96 = 0;
    var index: Index = .{ .project = project, .units = try allocator.alloc(Unit, project.modules.items.len), .mode = options.mode };
    for (project.order.items) |module_id| {
        const module = project.modules.items[module_id];
        const syntax_start = if (include_timing) timing.?.now() else std.Io.Timestamp.zero;
        var replayed = false;
        var lazy: ?*lazy_module.Module = null;
        const syntax = try moduleSyntax(project, module_id, .{ .cache = cache, .frontend = frontend, .mode = options.mode }, &replayed, &lazy);
        if (include_timing) {
            const elapsed = syntax_start.durationTo(timing.?.now()).nanoseconds;
            syntax_ns += elapsed;
            timing.?.add(if (replayed) "syntax_replay" else "syntax_parse", elapsed, false);
        }
        index.units[module_id] = .{ .syntax = syntax, .replayed = replayed, .lazy = lazy };
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

/// The digest of a module's bytes: the one loading took, or, when a command deferred it, a fresh one.
fn moduleDigest(module: graph.Module) [32]u8 {
    return if (module.state.digest_pending) @import("source_digest.zig").of(module.src.bytes) else module.digest;
}

/// Where one module's syntax may come from.
const SyntaxSources = struct { cache: ?*SyntaxCache, frontend: ?*FrontendCache, mode: lazy_module.Mode };

fn moduleSyntax(project: *graph.Project, module_id: usize, sources: SyntaxSources, replayed: *bool, lazy: *?*lazy_module.Module) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    const allocator = project.arena.allocator();
    const cache = sources.cache;
    const frontend = sources.frontend;
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
        if (sources.mode.isLazy()) {
            if (try disk.lookupSyntaxLazyOf(allocator, module.src, moduleDigest(module), module.header.body_start)) |stored| {
                // A declaration part whose runs do not fit its own counts is no entry: the module is parsed.
                if (stored.sparseProgram(allocator, if (sources.mode == .lazy_sentinel or compile_mode == .debug) lazy_module.sentinel else null)) |sparse| {
                    replayed.* = true;
                    lazy.* = stored;
                    return sparse;
                } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
            }
        } else if (try disk.lookupSyntaxOf(allocator, module.src, moduleDigest(module), module.header.body_start)) |syntax| {
            replayed.* = true;
            return syntax;
        }
    }
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const syntax = parseModule(project, module_id, &sink) catch |err| {
        if (err != error.SourceError) return err;
        const problem = sink.items.items[0];
        const failure = project.fail(problem.code, problem.message, .{ .module = module_id, .span = problem.span }, null);
        preserveParserDiagnostics(project, sink.items.items);
        return failure;
    };
    if (cache) |retained| try retained.remember(module.src, module.header.body_start, syntax);
    if (frontend) |disk| try disk.rememberSyntaxOf(module.src, moduleDigest(module), module.header.body_start, syntax);
    return syntax;
}
// The sink's storage and every diagnostic payload belong to the project arena.
// Keep each repair on its diagnostic instead of merging unrelated edits.
fn preserveParserDiagnostics(project: *graph.Project, problems: []const diagnostic.Diagnostic) void {
    project.problem.?.recovered = problems;
    if (problems[0].provenance.fix) |fix| {
        project.problem.?.fix = fix.edit;
        project.problem.?.fix_more = fix.more;
    }
}

/// Parse module `module_id` again from its bytes, into the project arena: what a lazily loaded body falls back to when its stored section is
/// gone or damaged. A parse yields the same ids as the one the entry was made from, so a body of this program is the stored body.
pub fn reparse(project: *graph.Project, module_id: usize) diagnostic.Error!ast.Program {
    var sink: diagnostic.Sink = .{ .allocator = project.arena.allocator() };
    return parseModule(project, module_id, &sink);
}

fn parseModule(project: *graph.Project, module_id: usize, sink: *diagnostic.Sink) diagnostic.Error!ast.Program {
    const module = project.modules.items[module_id];
    // ARENA-BOUNDED-1: the syntax outlives the tokens, which nothing reads after
    // the parse, so they come from the child allocator and go back at once
    // instead of staying in the project arena (about 420 MB at a million lines).
    const scratch = project.arena.child_allocator;
    const tokens = try lexer.lex(scratch, module.src.bytes, sink);
    defer scratch.free(tokens);
    var parse: parser.Parser = .{ .src = module.src, .storage = project.arena.allocator(), .tokens = tokens, .sink = sink, .syntax = .{ .growth = scratch } };
    defer parse.release();
    return parse.parseModule();
}

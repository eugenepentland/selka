//! Semantic name adapter: mapped source spans retain their declaring module.
const std = @import("std");
const ast = @import("ast.zig");
const graph = @import("project.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
/// The declaration a function reference finally names: its module's source path and name, and its own name.
pub const FunctionTarget = struct { path: []const u8, module: []const u8, name: []const u8 };
/// A module-level name as `Names.declarationOf` finds it: its kind and, when it maps into the merged source, its span.
pub const TopLevelName = struct {
    /// The kinds a module-level name can be.
    pub const Kind = enum { function, type, constraint, module };
    kind: Kind,
    at: ?source.Span,
};
/// The `E_SHADOWING` sentence for binding `name` as `form` where it would hide `kind` (`the imported module`, `the local`)
/// of the same name (F-10). The sema checker and the generic-body checker share it.
pub fn shadowingMessage(allocator: std.mem.Allocator, form: []const u8, name: []const u8, kind: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} `{s}` would hide {s} `{s}`: a name is bound once where it is visible, so choose another name", .{ form, name, kind, name });
}
/// The words a shadowing refusal uses for a module-level name of `kind`; a function that is a module constant is
/// `constant`.
pub fn shadowedKind(kind: TopLevelName.Kind, constant: bool) []const u8 {
    return switch (kind) {
        .module => "the imported module",
        .type => "the type",
        .constraint => "the constraint",
        .function => if (constant) "the module constant" else "the function",
    };
}
/// Module-aware name resolution over mapped source spans and a checked interface index.
pub const Names = struct {
    index: *interfaces.Index,
    src: source.Source,
    /// Whether the project check repairs `public` functions like private ones (`copy_for_store.Inputs.public_repaired`): the command
    /// layer found no `interface_files` and no module set a package root could hold.
    repairs_public: bool = false,
    /// The constant declarations of one program by identity, built on first use by `constantIndex`.
    constants: struct {
        built: bool = false,
        functions: []const ast.Function = &.{},
        by_identity: std.StringHashMapUnmanaged(usize) = .empty,
    } = .{},
    fn allocator(self: Names) std.mem.Allocator {
        return self.index.project.arena.allocator();
    }
    /// The index of the first constant in `functions` whose module-qualified identity is `identity`.
    /// The table is built once per program; it gives the answer a linear scan over the constants gives.
    pub fn constantIndex(self: *Names, functions: []const ast.Function, identity: []const u8) diagnostic.Error!?usize {
        if (!self.constants.built or self.constants.functions.ptr != functions.ptr or self.constants.functions.len != functions.len) {
            self.constants.by_identity = .empty;
            for (functions, 0..) |function, index| {
                if (!function.policy.constant) continue;
                const declared = try self.functionDeclaration(null, function.name);
                const entry = try self.constants.by_identity.getOrPut(self.allocator(), declared);
                if (!entry.found_existing) entry.value_ptr.* = index;
            }
            self.constants.functions = functions;
            self.constants.built = true;
        }
        return self.constants.by_identity.get(identity);
    }
    /// Allocate the module-qualified identity of a declaration in the project arena.
    pub fn declaration(self: Names, span: source.Span) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[original.input].name, self.src.text(span) });
    }
    /// Allocate a qualified free-function or domain-member declaration name.
    pub fn functionDeclaration(self: Names, owner: ?source.Span, name: source.Span) diagnostic.Error![]const u8 {
        if (owner) |domain| return std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ try self.declaration(domain), self.src.text(name) });
        return self.declaration(name);
    }
    /// Resolve a symbol with module privacy checks and map failures back to source diagnostics.
    pub fn reference(self: Names, span: source.Span, kind: interfaces.Kind, member: ?source.Span, current_owner: ?[]const u8, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const text = self.src.text(span);
        const qualified = (try self.qualify(text)) orelse return error.InternalError;
        const bare = qualified.name;
        const name = if (member) |method| try std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ bare, self.src.text(method) }) else bare;
        const id = self.index.resolve(.{ .from = original.input, .alias = qualified.alias, .name = name, .kind = kind, .owner = current_owner, .span = original.span }) catch |err| {
            if (err != error.SourceError) return err;
            const problem = self.index.project.problem orelse return error.InternalError;
            return self.mapProblem(problem, sink);
        };
        return std.fmt.allocPrint(self.allocator(), "{s}::{s}", .{ self.index.project.modules.items[id.module].name, self.index.units[id.module].symbols.items[id.symbol].name });
    }
    /// Resolve a named constraint bound and map failures through this merged source.
    pub fn constraintIdentity(self: Names, bound: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!interfaces.Identity {
        const original = self.src.originalSpan(bound.name) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const alias = if (bound.alias) |span| self.src.text(span) else null;
        return self.index.resolve(.{
            .from = original.input,
            .alias = alias,
            .name = self.src.text(bound.name),
            .kind = .constraint,
            .owner = null,
            .span = original.span,
        }) catch |err| {
            if (err != error.SourceError) return err;
            const problem = self.index.project.problem orelse return error.InternalError;
            return self.mapProblem(problem, sink);
        };
    }
    fn mapProblem(self: Names, problem: graph.Problem, sink: *diagnostic.Sink) diagnostic.Error {
        const at = self.src.mappedSpan(problem.site.module, problem.site.span) catch return error.InternalError;
        if (problem.related) |related| return sink.failRelated(problem.code, at, problem.message, .{ .span = self.src.mappedSpan(related.module, related.span) catch return error.InternalError, .message = "declaration is here" });
        // A problem with a repair in its module's own coordinates (the import an unimported standard module needs,
        // W13-S5) keeps it, mapped into the merged source.
        if (problem.fix) |edit| if (problem.fix_more.len == 0) {
            const mapped = self.src.mappedSpan(problem.site.module, edit.span) catch return error.InternalError;
            return sink.failFix(problem.code, at, problem.message, .{ .span = mapped, .text = edit.text });
        };
        return sink.fail(problem.code, at, problem.message);
    }
    /// Inspect declaration kind before selecting a call or constructor resolver.
    /// The selected resolver still enforces import visibility and privacy.
    pub fn symbolKind(self: Names, span: source.Span) diagnostic.Error!?interfaces.Kind {
        const identity = (try self.symbolIdentity(span)) orelse return null;
        return self.index.units[identity.module].symbols.items[identity.symbol].kind;
    }
    /// What a miss of the bare name at `span` adds when a module its file imports declares it as a function or constant
    /// (`interfaces.Index.importedAnswer`), or null.
    pub fn importedAnswer(self: Names, span: source.Span) diagnostic.Error!?interfaces.ImportedAnswer {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        return self.index.importedAnswer(original.input, self.src.text(span), .function);
    }
    /// Inspect a declaration's constant policy without resolving visibility or recording
    /// a project problem. Literal hints may resolve only names this identifies as constants.
    pub fn isConstant(self: Names, span: source.Span) diagnostic.Error!bool {
        var identity = (try self.symbolIdentity(span)) orelse return false;
        var remaining = self.index.units.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const unit = self.index.units[identity.module];
            const symbol = unit.symbols.items[identity.symbol];
            if (symbol.re_export) |origin| {
                identity = origin;
                continue;
            }
            if (symbol.kind != .function) return false;
            for (unit.syntax.functions) |function| {
                if (std.meta.eql(function.name, symbol.span)) return function.policy.constant;
            }
            return false;
        }
        return false;
    }
    /// The module and declared name a function reference finally names, without reporting anything: `alias` is the
    /// call's qualifier (null for a bare name), resolved through the importing module's imports, and a re-export is
    /// followed to its declaration. Null when the reference names no function. The import the alias matched is marked
    /// used, as a resolved call marks it.
    pub fn functionTarget(self: Names, span: source.Span, alias: ?[]const u8, name: []const u8) diagnostic.Error!?FunctionTarget {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.project.modules.items.len) return error.InternalError;
        var module = original.input;
        if (alias) |qualifier| {
            var found = false;
            for (self.index.project.modules.items[module].imports, 0..) |imported, import_index| if (imported.matches(qualifier)) {
                self.index.noteImportUse(module, import_index);
                module = imported.target;
                found = true;
                break;
            };
            if (!found) return null;
        }
        var symbol = self.index.units[module].names.get(name) orelse return null;
        var remaining = self.index.units.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const declared = self.index.units[module].symbols.items[symbol];
            if (declared.re_export) |origin| {
                module = origin.module;
                symbol = origin.symbol;
                continue;
            }
            if (declared.kind != .function) return null;
            const unit = self.index.project.modules.items[module];
            return .{ .path = unit.src.path, .module = unit.name, .name = declared.name };
        }
        return null;
    }
    fn symbolIdentity(self: Names, span: source.Span) diagnostic.Error!?interfaces.Identity {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        const text = self.src.text(span);
        const qualified = (try self.qualify(text)) orelse return null;
        var module = original.input;
        if (qualified.alias) |alias| {
            var found = false;
            for (self.index.project.modules.items[module].imports) |imported| if (imported.matches(alias)) {
                module = imported.target;
                found = true;
                break;
            };
            if (!found) return null;
        }
        const unit = self.index.units[module];
        try self.index.noteLookup(module, qualified.name);
        const id = unit.names.get(qualified.name) orelse return null;
        return .{ .module = module, .symbol = id };
    }
    /// Normalize references, including the two builtin spellings that the
    /// parser admits as declared callable names. Qualifier segments stay names.
    fn qualify(self: Names, text: []const u8) diagnostic.Error!?lexer.Qualified {
        switch (lexer.quickQualifiedName(text)) {
            .name => |qualified| return qualified,
            .none, .slow => {},
        }
        var sink: diagnostic.Sink = .{ .allocator = self.allocator() };
        const tokens = try lexer.lex(self.allocator(), text, &sink);
        if (tokens.len >= 2) {
            const last = &tokens[tokens.len - 2];
            if (last.tag == .kw_len or last.tag == .kw_replace) last.tag = .ident;
        }
        return lexer.qualifiedName(text, tokens);
    }
    /// Check whether a name belongs to the originating module's declarations or import aliases.
    pub fn topLevel(self: Names, span: source.Span) error{InternalError}!bool {
        return self.topLevelSpelling(span, self.src.text(span));
    }
    /// Whether the module that writes `span` declares a type of that name itself.
    /// An import alias is not a declaration, so `import bytes` does not shadow the
    /// built-in `bytes` type (L18); a type the module declares still wins.
    pub fn declaresType(self: Names, span: source.Span) diagnostic.Error!bool {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len) return error.InternalError;
        const text = self.src.text(span);
        for (self.index.units[original.input].symbols.items) |symbol| {
            if (symbol.kind != .type) continue;
            if (std.mem.eql(u8, symbol.name, text)) return true;
        }
        return false;
    }
    /// Whether this check sees a module graph rather than one import-free file.
    /// A program whose whole graph is a single file that imports nothing is a
    /// single-file program: the single-unit grammar has no directive to write,
    /// and every command that checks it answers the same way.
    pub fn moduleGraph(self: Names) bool {
        const modules = self.index.project.modules.items;
        if (modules.len > 1) return true;
        return modules.len == 1 and modules[0].imports.len != 0;
    }
    /// The name of the module that writes `span`, so a module can reach the
    /// declarations it defines itself without importing itself.
    pub fn moduleOf(self: Names, span: source.Span) error{InternalError}!?[]const u8 {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.project.modules.items.len) return error.InternalError;
        return self.index.project.modules.items[original.input].name;
    }
    /// Whether the module that writes `span` imports `module`, by alias or by
    /// its full dotted path. A module function needs its import (B2), and a
    /// project's imports live on the module rather than the checked program.
    pub fn importsModule(self: Names, span: source.Span, module: []const u8) error{InternalError}!bool {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.project.modules.items.len) return error.InternalError;
        for (self.index.project.modules.items[original.input].imports, 0..) |imported, import_index| {
            if (!imported.matches(module)) continue;
            // The call is a use: a compiler-recognised module function resolves
            // before ordinary resolution, so `W_UNUSED_IMPORT` needs telling.
            self.index.noteImportUse(original.input, import_index);
            return true;
        }
        return false;
    }
    /// What a module-level name means in the module that writes `span`, for a refusal that must say which kind of
    /// declaration a binding would hide (F-10): a declaration's kind or an import, and where it is in the merged source.
    pub fn declarationOf(self: Names, span: source.Span) error{InternalError}!?TopLevelName {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        const text = self.src.text(span);
        const unit = self.index.units[original.input];
        if (unit.names.get(text)) |symbol_index| {
            const symbol = unit.symbols.items[symbol_index];
            const kind: TopLevelName.Kind = switch (symbol.kind) {
                .type => .type,
                .function => .function,
                .constraint => .constraint,
            };
            return .{ .kind = kind, .at = self.src.mappedSpan(original.input, symbol.span) catch null };
        }
        for (self.index.project.modules.items[original.input].imports) |imported| {
            if (!std.mem.eql(u8, imported.alias, text)) continue;
            return .{ .kind = .module, .at = self.src.mappedSpan(original.input, imported.span) catch null };
        }
        return null;
    }
    /// Inspect a proposed replacement spelling in the source location's module before offering a fix.
    pub fn topLevelSpelling(self: Names, span: source.Span, name: []const u8) error{InternalError}!bool {
        const original = self.src.originalSpan(span) catch return error.InternalError;
        if (original.input >= self.index.units.len or original.input >= self.index.project.modules.items.len) return error.InternalError;
        if (self.index.units[original.input].names.contains(name)) return true;
        // A dotted spelling is a qualified module/type/domain reference, never a
        // bare declaration, so it is top-level without reserving its prefix.
        if (std.mem.indexOfScalar(u8, name, '.') != null) return true;
        const prefix = name[0 .. std.mem.indexOfAny(u8, name, " \t\r\n:.") orelse name.len];
        for (self.index.project.modules.items[original.input].imports) |imported| {
            if (std.mem.eql(u8, imported.alias, prefix)) return true;
        }
        return false;
    }
};

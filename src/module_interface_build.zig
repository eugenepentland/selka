//! Build every module's interface (MODULE-INTERFACE-1) from one checked
//! whole-program compilation: which declarations each interface keeps, the
//! declaration text a dependent parses, the facts it stands in, and the
//! interface fingerprints and hashes. See `module_interface.zig` for the format.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const interfaces = @import("interfaces.zig");
const semantic_key = @import("semantic_key.zig");
const summary = @import("semantic_summary.zig");
const iface = @import("module_interface.zig");

/// Failures of `build`: allocation, or a compilation that is not the checked
/// whole program the inputs promise.
pub const Error = error{ OutOfMemory, InternalError };

/// What one checked whole-program compilation offers the builder. `syntax`
/// and `src` are the merged program the check read, so they must not have
/// been released (`Compilation.releaseSyntax`).
pub const Inputs = struct {
    index: *interfaces.Index,
    src: source.Source,
    syntax: ast.Program,
    program: typed.Program,
    /// The check's declaration identities (stable keys, ordinary instances).
    prepared: semantic_key.Prepared,
    /// The check's summaries: one fact per ordinary instance.
    facts: summary.Table,
};

/// Every module's interface and its two hashes, indexed by module id.
pub const Set = struct {
    interfaces: []iface.Interface,
    interface_hashes: [][32]u8,
    implementation_hashes: [][32]u8,
};

/// Build every module's interface. All storage comes from `allocator`, which
/// should be an arena that outlives the returned set.
pub fn build(allocator: std.mem.Allocator, inputs: Inputs) Error!Set {
    var state: State = .{
        .allocator = allocator,
        .inputs = inputs,
        .surface = try semantic_key.Surface.init(allocator, inputs.src, inputs.syntax, inputs.index),
        .functions = &.{},
        .by_module = &.{},
    };
    defer state.surface.deinit();
    try state.describeFunctions();
    try state.groupByModule();
    try state.indexCatalog();
    const modules = inputs.index.project.modules.items;
    const out: Set = .{
        .interfaces = try allocator.alloc(iface.Interface, modules.len),
        .interface_hashes = try allocator.alloc([32]u8, modules.len),
        .implementation_hashes = try allocator.alloc([32]u8, modules.len),
    };
    for (0..modules.len) |module| {
        out.interfaces[module] = try state.moduleInterface(module);
        out.interface_hashes[module] = iface.interfaceHash(out.interfaces[module]);
    }
    for (modules, 0..) |module, id| {
        const imports = try allocator.alloc(iface.ImportHash, module.imports.len);
        for (module.imports, imports) |imported, *entry| entry.* = .{ .module = modules[imported.target].name, .hash = out.interface_hashes[imported.target] };
        out.implementation_hashes[id] = iface.implementationHash(module.name, module.src, imports);
    }
    return out;
}

/// The role a function's declaration gives it.
pub fn roleOf(function: ast.Function) iface.Role {
    if (function.signature.type_parameters.len != 0) return .template;
    if (function.policy.constant) return .constant;
    if (function.policy.conversion) return .conversion;
    if (function.policy.host != null or function.policy.c_abi) return .foreign;
    return .declared;
}

/// What the builder knows about one merged-program function.
const FunctionInfo = struct {
    module: usize,
    role: iface.Role,
    fact: summary.Fact,
    /// Local name span in its module's source.
    name: source.Span,
    /// Local body span (from the `:` that opens it) in its module's source.
    body: source.Span,
};

/// Memoized interface fingerprints over the declaration graph.
const Fingerprints = struct {
    own: std.AutoHashMapUnmanaged(u64, [32]u8) = .empty,
    edges: std.AutoHashMapUnmanaged(u64, []const u64) = .empty,
    full: std.AutoHashMapUnmanaged(u64, [32]u8) = .empty,
};

/// Catalog record positions and alias targets by qualified name, and the
/// checked instance of each ordinary merged-program function.
const Catalog = struct {
    records: std.StringHashMapUnmanaged(usize) = .empty,
    aliases: std.StringHashMapUnmanaged(typed.Type) = .empty,
    instances: std.AutoHashMapUnmanaged(usize, usize) = .empty,
};

/// One facade name a module re-exports and the declaration it names.
const Reexport = struct { name: []const u8, key: u64 };

/// One module's kept declarations: the closure's keys, sorted, and the
/// declarations of other modules it re-exports.
const Closure = struct { functions: []const usize, types: []const u64, reexports: []const Reexport };

const State = struct {
    allocator: std.mem.Allocator,
    inputs: Inputs,
    surface: semantic_key.Surface,
    functions: []FunctionInfo,
    fingerprints: Fingerprints = .{},
    /// Declaration keys (functions and types) of each module.
    by_module: [][]const u64,
    catalog: Catalog = .{},

    /// Role, facts and local spans of every merged-program function.
    fn describeFunctions(self: *State) Error!void {
        const syntax = self.inputs.syntax;
        const prepared = self.inputs.prepared;
        var facts: std.StringHashMapUnmanaged(summary.Fact) = .empty;
        for (self.inputs.facts.summaries) |stored| try facts.put(self.allocator, stored.key, stored.fact);
        self.functions = try self.allocator.alloc(FunctionInfo, syntax.functions.len);
        for (syntax.functions, self.functions, 0..) |function, *info, i| {
            const name = try localSpan(self.inputs.src, function.name);
            const body = try localSpan(self.inputs.src, syntax.statements.items[@backingInt(function.body)].span);
            info.* = .{
                .module = name.module,
                .role = roleOf(function),
                .fact = facts.get(prepared.keys[i]) orelse .{},
                .name = name.span,
                .body = body.span,
            };
        }
        try self.markEvaluated();
    }

    /// A constant's value is evaluated where the constant is checked, running
    /// the bodies of every function it calls, directly or not: those keep
    /// their bodies (`evaluated`).
    fn markEvaluated(self: *State) Error!void {
        var pending: std.ArrayList(usize) = .empty;
        for (self.functions, 0..) |info, i| if (info.role == .constant) try pending.append(self.allocator, i);
        const seen = try self.allocator.alloc(bool, self.functions.len);
        @memset(seen, false);
        while (pending.pop()) |function| {
            for (try self.surface.bodyReferences(self.allocator, function)) |key| {
                const decl = semantic_key.Surface.declaration(key);
                if (decl.kind != .function or seen[decl.index]) continue;
                seen[decl.index] = true;
                const info = &self.functions[decl.index];
                if (info.role == .declared) info.role = .evaluated;
                try pending.append(self.allocator, decl.index);
            }
        }
    }

    /// Every declaration key, grouped by the module that declares it.
    fn groupByModule(self: *State) Error!void {
        const count = self.inputs.index.project.modules.items.len;
        const lists = try self.allocator.alloc(std.ArrayList(u64), count);
        for (lists) |*list| list.* = .empty;
        for (self.functions, 0..) |info, i| try lists[info.module].append(self.allocator, semantic_key.Surface.functionKey(i));
        const types = self.inputs.syntax.types;
        const tables = .{
            .{ "records", semantic_key.DeclKind.record },
            .{ "domains", semantic_key.DeclKind.domain },
            .{ "variants", semantic_key.DeclKind.variant },
            .{ "constraints", semantic_key.DeclKind.constraint },
            .{ "resources", semantic_key.DeclKind.resource },
        };
        inline for (tables) |table| {
            for (@field(types, table[0]), 0..) |declaration, i| {
                const at = try localSpan(self.inputs.src, declaration.name);
                try lists[at.module].append(self.allocator, semantic_key.Surface.typeKey(table[1], i));
            }
        }
        for (types.expressions.aliases, 0..) |alias, i| {
            const at = try localSpan(self.inputs.src, alias.name);
            try lists[at.module].append(self.allocator, semantic_key.Surface.typeKey(.alias, i));
        }
        self.by_module = try self.allocator.alloc([]const u64, count);
        for (lists, self.by_module) |*list, *out| out.* = try list.toOwnedSlice(self.allocator);
    }

    fn indexCatalog(self: *State) Error!void {
        for (self.inputs.program.records, 0..) |record, i| {
            const entry = try self.catalog.records.getOrPut(self.allocator, record.name);
            if (!entry.found_existing) entry.value_ptr.* = i;
        }
        for (self.inputs.program.aliases) |alias| try self.catalog.aliases.put(self.allocator, alias.name, alias.target);
        for (self.inputs.prepared.ordinary_ast, 0..) |ast_index, instance| try self.catalog.instances.put(self.allocator, ast_index, instance);
    }

    /// The local name span of a type declaration key.
    fn typeName(self: *State, key: u64) Error!source.Span {
        const decl = semantic_key.Surface.declaration(key);
        const types = self.inputs.syntax.types;
        const span = switch (decl.kind) {
            .record => types.records[decl.index].name,
            .domain => types.domains[decl.index].name,
            .variant => types.variants[decl.index].name,
            .constraint => types.constraints[decl.index].name,
            .resource => types.resources[decl.index].name,
            .alias => types.expressions.aliases[decl.index].name,
            .function => return error.InternalError,
        };
        return (try localSpan(self.inputs.src, span)).span;
    }

    /// Where a declaration's name starts in its module's source.
    fn nameStart(self: *State, key: u64) Error!usize {
        const decl = semantic_key.Surface.declaration(key);
        if (decl.kind == .function) return self.functions[decl.index].name.start;
        return (try self.typeName(key)).start;
    }

    fn moduleText(self: *State, module: usize) []const u8 {
        return self.inputs.index.project.modules.items[module].src.bytes;
    }

    /// The owner domain spelling of a merged-program function, if a member.
    fn ownerText(self: *State, function: usize) ?[]const u8 {
        const owner = self.inputs.syntax.functions[function].policy.owner orelse return null;
        return self.inputs.src.text(owner);
    }

    /// The declarations a dependent of `module` can reach: its exported ones
    /// and, transitively, every declaration of the same module they name. A
    /// kept body names more; a domain keeps all its members, and a member its domain.
    fn closure(self: *State, module: usize) Error!Closure {
        var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
        var pending: std.ArrayList(u64) = .empty;
        var reexports: std.ArrayList(Reexport) = .empty;
        const unit = self.inputs.index.units[module];
        for (unit.symbols.items) |symbol| {
            if (!symbol.exported) continue;
            if (symbol.re_export) |target| {
                // A facade's name is the defining declaration: its dependents
                // observe that declaration through this interface.
                const target_name = self.inputs.index.units[target.module].symbols.items[target.symbol].name;
                for (self.surface.named(target.module, target_name)) |key| {
                    if (self.surface.moduleOfKey(key) == target.module) try reexports.append(self.allocator, .{ .name = symbol.name, .key = key });
                }
                continue;
            }
            for (self.surface.named(module, symbol.name)) |key| try self.reach(module, key, &seen, &pending);
        }
        while (pending.pop()) |key| {
            const own = try self.surface.own(key);
            for (own.edges) |edge| try self.reach(module, edge, &seen, &pending);
            const decl = semantic_key.Surface.declaration(key);
            switch (decl.kind) {
                .function => {
                    if (self.functions[decl.index].role.keepsBody()) {
                        for (try self.surface.bodyReferences(self.allocator, decl.index)) |edge| try self.reach(module, edge, &seen, &pending);
                    }
                    if (self.ownerText(decl.index)) |owner| for (self.surface.named(module, owner)) |edge| {
                        if (semantic_key.Surface.declaration(edge).kind == .domain) try self.reach(module, edge, &seen, &pending);
                    };
                },
                .domain => {
                    const name = self.inputs.src.text(self.inputs.syntax.types.domains[decl.index].name);
                    for (self.by_module[module]) |candidate| {
                        const member = semantic_key.Surface.declaration(candidate);
                        if (member.kind != .function) continue;
                        const owner = self.ownerText(member.index) orelse continue;
                        if (std.mem.eql(u8, owner, name)) try self.reach(module, candidate, &seen, &pending);
                    }
                },
                else => {},
            }
        }
        var functions: std.ArrayList(usize) = .empty;
        var types: std.ArrayList(u64) = .empty;
        var keys = seen.keyIterator();
        while (keys.next()) |key| {
            const decl = semantic_key.Surface.declaration(key.*);
            if (decl.kind == .function) try functions.append(self.allocator, decl.index) else try types.append(self.allocator, key.*);
        }
        std.mem.sort(usize, functions.items, {}, std.sort.asc(usize));
        std.mem.sort(u64, types.items, {}, std.sort.asc(u64));
        std.mem.sort(Reexport, reexports.items, {}, reexportBefore);
        return .{ .functions = functions.items, .types = types.items, .reexports = reexports.items };
    }

    fn reach(self: *State, module: usize, key: u64, seen: *std.AutoHashMapUnmanaged(u64, void), pending: *std.ArrayList(u64)) Error!void {
        if (self.surface.moduleOfKey(key) != module) return;
        const entry = try seen.getOrPut(self.allocator, key);
        if (entry.found_existing) return;
        try pending.append(self.allocator, key);
    }

    /// One declaration's own interface content: its declaration digest, and
    /// for a function its role and facts and, when kept, its body's text.
    fn ownFingerprint(self: *State, key: u64) Error![32]u8 {
        if (self.fingerprints.own.get(key)) |known| return known;
        const own = try self.surface.own(key);
        const decl = semantic_key.Surface.declaration(key);
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update("interface-own-v1");
        hash.update(&own.digest);
        hash.update(&.{@as(u8, @backingInt(decl.kind))});
        if (decl.kind == .function) {
            const info = self.functions[decl.index];
            hash.update(&.{@backingInt(info.role)});
            iface.hashFact(&hash, info.fact);
            if (info.role.keepsBody()) {
                const text = self.moduleText(info.module);
                const start = lineStart(text, info.name.start);
                frameInto(&hash, text[start..info.body.end]);
            }
        }
        var out: [32]u8 = undefined;
        hash.final(&out);
        try self.fingerprints.own.put(self.allocator, key, out);
        return out;
    }

    /// The declarations a dependent reaches through one declaration: what its
    /// declaration names, and what its body names when the body is kept.
    fn interfaceEdges(self: *State, key: u64) Error![]const u64 {
        if (self.fingerprints.edges.get(key)) |known| return known;
        const own = try self.surface.own(key);
        const decl = semantic_key.Surface.declaration(key);
        var edges: []const u64 = own.edges;
        if (decl.kind == .function and self.functions[decl.index].role.keepsBody()) {
            const body = try self.surface.bodyReferences(self.allocator, decl.index);
            const joined = try self.allocator.alloc(u64, own.edges.len + body.len);
            @memcpy(joined[0..own.edges.len], own.edges);
            @memcpy(joined[own.edges.len..], body);
            edges = joined;
        }
        try self.fingerprints.edges.put(self.allocator, key, edges);
        return edges;
    }

    /// Interface fingerprint: the declaration's own interface content and that
    /// of every declaration it reaches through interface edges, in any module,
    /// in an order-independent fold (a cycle folds every member into each).
    fn interfaceFingerprint(self: *State, key: u64) Error![32]u8 {
        if (self.fingerprints.full.get(key)) |known| return known;
        var reached: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer reached.deinit(self.allocator);
        var pending: std.ArrayList(u64) = .empty;
        defer pending.deinit(self.allocator);
        var digests: std.ArrayList([32]u8) = .empty;
        defer digests.deinit(self.allocator);
        try reached.put(self.allocator, key, {});
        try pending.append(self.allocator, key);
        while (pending.pop()) |current| {
            if (current != key) try digests.append(self.allocator, try self.ownFingerprint(current));
            for (try self.interfaceEdges(current)) |next| {
                const entry = try reached.getOrPut(self.allocator, next);
                if (!entry.found_existing) try pending.append(self.allocator, next);
            }
        }
        std.mem.sort([32]u8, digests.items, {}, lessDigest);
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update("interface-fingerprint-v1");
        hash.update(&(try self.ownFingerprint(key)));
        for (digests.items) |digest| hash.update(&digest);
        var out: [32]u8 = undefined;
        hash.final(&out);
        try self.fingerprints.full.put(self.allocator, key, out);
        return out;
    }

    /// One module's interface.
    fn moduleInterface(self: *State, module: usize) Error!iface.Interface {
        const kept = try self.closure(module);
        const project_module = self.inputs.index.project.modules.items[module];
        const functions = try self.allocator.alloc(iface.Function, kept.functions.len);
        for (kept.functions, functions) |index, *out| {
            const info = self.functions[index];
            out.* = .{
                .key = self.inputs.prepared.keys[index],
                .role = info.role,
                .exported = self.exported(module, index),
                .fact = info.fact,
                .fingerprint = try self.interfaceFingerprint(semantic_key.Surface.functionKey(index)),
            };
        }
        std.mem.sort(iface.Function, functions, {}, functionBefore);
        const types = try self.allocator.alloc(iface.Type, kept.types.len);
        for (kept.types, types) |key, *out| {
            const name = try self.typeName(key);
            out.* = .{ .name = self.moduleText(module)[name.start..name.end], .fingerprint = try self.interfaceFingerprint(key) };
        }
        std.mem.sort(iface.Type, types, {}, typeBefore);
        const reexports = try self.allocator.alloc(iface.Type, kept.reexports.len);
        for (kept.reexports, reexports) |entry, *out| out.* = .{ .name = entry.name, .fingerprint = try self.interfaceFingerprint(entry.key) };
        var stub = try Stub.render(self, module, kept);
        return .{
            .module = project_module.name,
            .imports = try stub.imports(self, module),
            .text = stub.text.items,
            .declarations = .{ .functions = functions, .types = types, .reexports = reexports, .shapes = try self.shapes(kept) },
            .positions = .{ .origins = stub.origins.items },
        };
    }

    fn exported(self: *State, module: usize, function: usize) bool {
        const unit = self.inputs.index.units[module];
        const name = self.inputs.src.text(self.inputs.syntax.functions[function].name);
        const lookup = if (self.ownerText(function)) |owner| std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ owner, name }) catch return false else name;
        const id = unit.names.get(lookup) orelse return false;
        return unit.symbols.items[id].exported;
    }

    /// The transitive shape digest of every catalog record the kept and
    /// re-exported declarations reach: through a function's parameter and
    /// result types, and a type declaration's own catalog record or alias target.
    fn shapes(self: *State, kept: Closure) Error![]const summary.Shape {
        const records = self.inputs.program.records;
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var reached: std.ArrayList(usize) = .empty;
        var keys: std.ArrayList(u64) = .empty;
        for (kept.functions) |index| try keys.append(self.allocator, semantic_key.Surface.functionKey(index));
        try keys.appendSlice(self.allocator, kept.types);
        for (kept.reexports) |entry| try keys.append(self.allocator, entry.key);
        for (keys.items) |key| {
            const decl = semantic_key.Surface.declaration(key);
            if (decl.kind == .function) {
                const instance = self.catalog.instances.get(decl.index) orelse continue;
                if (instance >= self.inputs.program.functions.len) continue;
                const function = self.inputs.program.functions[instance];
                const count = @min(function.signature.parameter_count, function.scope.locals.len);
                for (function.scope.locals[0..count]) |local| try semantic_key.reachableRecords(self.allocator, local.ty, records, &seen, &reached);
                try semantic_key.reachableRecords(self.allocator, function.signature.return_type, records, &seen, &reached);
                continue;
            }
            const module = self.surface.moduleOfKey(key);
            const name = try self.typeName(key);
            const module_name = self.inputs.index.project.modules.items[module].name;
            const qualified = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ module_name, self.moduleText(module)[name.start..name.end] });
            if (self.catalog.records.get(qualified)) |index| try semantic_key.reachableRecords(self.allocator, records[index].id, records, &seen, &reached);
            if (self.catalog.aliases.get(qualified)) |target| try semantic_key.reachableRecords(self.allocator, target, records, &seen, &reached);
        }
        var digests: semantic_key.Shapes = .{ .allocator = self.allocator, .records = records };
        const out = try self.allocator.alloc(summary.Shape, reached.items.len);
        for (reached.items, out) |index, *shape| shape.* = .{ .name = records[index].name, .digest = (try digests.digest(index)) orelse return error.InternalError };
        std.mem.sort(summary.Shape, out, {}, shapeBefore);
        return out;
    }
};

/// The rendered declaration text of one module's interface, the verbatim
/// stretches it copied, and the identifiers it spells (for its imports).
const Stub = struct {
    text: std.ArrayList(u8) = .empty,
    origins: std.ArrayList(iface.Origin) = .empty,
    identifiers: std.StringHashMapUnmanaged(void) = .empty,

    /// Keep each top-level item of the module that declares a kept
    /// declaration, and its header, re-exports and used imports, in source
    /// order; replace the body of every kept function whose role does not keep
    /// it by `pass`.
    fn render(state: *State, module: usize, kept: Closure) Error!Stub {
        const allocator = state.allocator;
        const text = state.moduleText(module);
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = lexer.lexRange(allocator, text, .{ .start = 0, .end = text.len }, &sink) catch return error.InternalError;
        const items = try topLevelItems(allocator, text, tokens);
        const keep = try allocator.alloc(Keep, items.len);
        const bodies = try allocator.alloc(std.ArrayList(source.Span), items.len);
        for (bodies) |*list| list.* = .empty;
        for (items, keep) |item, *decision| decision.* = classify(text, tokens, item);
        // An item that declares anything is dropped unless the closure keeps it.
        for (state.by_module[module]) |key| {
            const at = itemAt(items, try state.nameStart(key)) orelse return error.InternalError;
            if (keep[at] == .other) keep[at] = .drop;
        }
        for (kept.functions) |index| {
            const info = state.functions[index];
            const at = itemAt(items, info.name.start) orelse return error.InternalError;
            keep[at] = .declaration;
            if (!info.role.keepsBody()) try bodies[at].append(allocator, info.body);
        }
        for (kept.types) |key| {
            const at = itemAt(items, try state.nameStart(key)) orelse return error.InternalError;
            keep[at] = .declaration;
        }
        var stub: Stub = .{};
        // Declarations first: the identifiers their kept text spells, outside
        // the bodies `pass` replaces, decide which imports stay.
        for (items, keep, bodies) |item, decision, list| {
            if (decision != .declaration and decision != .reexport and decision != .other) continue;
            try stub.collectIdentifiers(allocator, text, tokens[item.first_token..item.end_token], list.items);
        }
        for (state.inputs.index.project.modules.items[module].imports) |imported| {
            if (!stub.uses(imported)) continue;
            const at = itemAt(items, imported.span.start) orelse return error.InternalError;
            keep[at] = .used_import;
        }
        const module_source = state.inputs.index.project.modules.items[module].src;
        for (items, keep, bodies, 0..) |item, decision, *list, at| {
            if (decision == .drop or decision == .import) continue;
            const follow = if (at + 1 < items.len) items[at + 1].start else text.len;
            try stub.append(allocator, module_source, .{ .item = item, .follow = follow }, list.items);
        }
        if (stub.text.items.len != 0 and stub.text.items[stub.text.items.len - 1] != '\n') try stub.text.append(allocator, '\n');
        return stub;
    }

    /// Copy one item, replacing each listed body by `:` and an indented
    /// `pass`, followed by the gap up to the next top-level item of the
    /// source with every byte but its newlines blanked. The gap keeps each
    /// position the item's syntax reaches past its last token (a closing
    /// dedent sits at the next item) mapped to its place in the source.
    fn append(self: *Stub, allocator: std.mem.Allocator, module_source: source.Source, place: Placed, bodies: []source.Span) Error!void {
        const text = module_source.bytes;
        const item = place.item;
        std.mem.sort(source.Span, bodies, {}, spanBefore);
        var cursor = item.start;
        for (bodies) |body| {
            if (body.start < cursor or body.end > item.end) return error.InternalError;
            try self.verbatim(allocator, module_source, .{ .start = cursor, .end = body.start }, body.start);
            const line = lineStart(text, body.start);
            var indent: usize = 0;
            while (line + indent < text.len and text[line + indent] == ' ') indent += 1;
            try self.text.appendSlice(allocator, ":\n");
            try self.text.appendNTimes(allocator, ' ', indent + 4);
            try self.text.appendSlice(allocator, "pass");
            cursor = body.end;
        }
        try self.verbatim(allocator, module_source, .{ .start = cursor, .end = item.end }, place.follow);
    }

    /// Copy `copied` verbatim and the gap `[copied.end, gap_end)` blanked,
    /// recording one origin stretch over both.
    fn verbatim(self: *Stub, allocator: std.mem.Allocator, module_source: source.Source, copied: source.Span, gap_end: usize) Error!void {
        if (gap_end <= copied.start) return;
        const location = module_source.locate(copied.start);
        try self.origins.append(allocator, .{
            .text = @intCast(self.text.items.len),
            .source = @intCast(copied.start),
            .len = @intCast(copied.end - copied.start),
            .gap = @intCast(gap_end - copied.end),
            .line = @intCast(location.line),
            .column = @intCast(location.column),
        });
        try self.text.appendSlice(allocator, module_source.bytes[copied.start..copied.end]);
        for (module_source.bytes[copied.end..gap_end]) |byte| try self.text.append(allocator, if (byte == '\n') '\n' else ' ');
    }

    fn collectIdentifiers(self: *Stub, allocator: std.mem.Allocator, text: []const u8, tokens: []const lexer.Token, dropped: []const source.Span) Error!void {
        outer: for (tokens) |token| {
            if (token.tag != .ident) continue;
            for (dropped) |body| if (token.span.start >= body.start and token.span.end <= body.end) continue :outer;
            try self.identifiers.put(allocator, text[token.span.start..token.span.end], {});
        }
    }

    /// Whether the kept text spells an import's alias or the first segment of
    /// its module path, the way a qualified reference through it must.
    fn uses(self: *const Stub, imported: @import("project.zig").Import) bool {
        if (self.identifiers.contains(imported.alias)) return true;
        const head = imported.name[0 .. std.mem.indexOfScalar(u8, imported.name, '.') orelse imported.name.len];
        return self.identifiers.contains(head);
    }

    /// The modules the kept import lines name, sorted.
    fn imports(self: *const Stub, state: *State, module: usize) Error![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        const modules = state.inputs.index.project.modules.items;
        for (modules[module].imports) |imported| {
            if (self.uses(imported)) try out.append(state.allocator, modules[imported.target].name);
        }
        std.mem.sort([]const u8, out.items, {}, lessText);
        return out.items;
    }
};

/// What becomes of one top-level item: dropped, or kept as the module header,
/// an import its declarations use, a re-export, a kept declaration, or an item
/// that declares nothing the builder recognizes (kept, conservatively).
const Keep = enum { drop, header, import, used_import, reexport, declaration, other };

/// One top-level item of a module: from the start of its first line to the
/// end of its last token, with the token range it spans.
const Item = struct { start: usize, end: usize, first_token: usize, end_token: usize };

/// One kept item and where the next top-level item of its source starts.
const Placed = struct { item: Item, follow: usize };

/// Split a module into top-level items. An item starts at a token in column
/// zero outside any bracket; attribute lines join the item that follows them.
fn topLevelItems(allocator: std.mem.Allocator, text: []const u8, tokens: []const lexer.Token) Error![]const Item {
    var starts: std.ArrayList(usize) = .empty;
    var depth: usize = 0;
    var attribute = false;
    for (tokens, 0..) |token, i| {
        if (token.tag == .eof) break;
        const column_zero = token.span.start == 0 or text[token.span.start - 1] == '\n';
        if (depth == 0 and column_zero) {
            if (!attribute) try starts.append(allocator, i);
            attribute = token.tag == .at;
        }
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            else => {},
        }
    }
    const last = if (tokens.len != 0 and tokens[tokens.len - 1].tag == .eof) tokens.len - 1 else tokens.len;
    const items = try allocator.alloc(Item, starts.items.len);
    for (starts.items, items, 0..) |first, *item, n| {
        const end_token = if (n + 1 < starts.items.len) starts.items[n + 1] else last;
        item.* = .{ .start = tokens[first].span.start, .end = tokens[end_token - 1].span.end, .first_token = first, .end_token = end_token };
    }
    return items;
}

/// What an item is before any declaration claims it.
fn classify(text: []const u8, tokens: []const lexer.Token, item: Item) Keep {
    const first = tokens[item.first_token];
    if (first.tag == .bytes) return .drop;
    if (first.tag != .ident) return .other;
    const word = text[first.span.start..first.span.end];
    if (std.mem.eql(u8, word, "module")) return .header;
    if (std.mem.eql(u8, word, "import")) return .import;
    if (std.mem.eql(u8, word, "export")) return .reexport;
    return .other;
}

/// The item whose extent holds `offset`.
fn itemAt(items: []const Item, offset: usize) ?usize {
    for (items, 0..) |item, i| if (offset >= item.start and offset < item.end) return i;
    return null;
}

fn localSpan(src: source.Source, span: source.Span) Error!struct { module: usize, span: source.Span } {
    const original = src.originalSpan(span) catch return error.InternalError;
    return .{ .module = original.input, .span = original.span };
}

fn lineStart(bytes: []const u8, offset: usize) usize {
    var index = @min(offset, bytes.len);
    while (index != 0 and bytes[index - 1] != '\n') index -= 1;
    return index;
}

fn frameInto(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn lessDigest(_: void, a: [32]u8, b: [32]u8) bool {
    return std.mem.order(u8, &a, &b) == .lt;
}

fn lessText(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn functionBefore(_: void, a: iface.Function, b: iface.Function) bool {
    return std.mem.lessThan(u8, a.key, b.key);
}

fn reexportBefore(_: void, a: Reexport, b: Reexport) bool {
    return std.mem.lessThan(u8, a.name, b.name) or (std.mem.eql(u8, a.name, b.name) and a.key < b.key);
}

fn typeBefore(_: void, a: iface.Type, b: iface.Type) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn shapeBefore(_: void, a: summary.Shape, b: summary.Shape) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn spanBefore(_: void, a: source.Span, b: source.Span) bool {
    return a.start < b.start;
}

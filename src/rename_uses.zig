//! What every name spelled one way in a checked program resolves to, for `selka rename`.
//!
//! The rename names a declaration and must change every use the checker resolves to it and nothing else. This file walks
//! the merged program and, for each identifier token spelled `name`, says which declaration it means, using the checker's
//! own tables: the interface index for module-level names, imports, aliases and re-exports (`interfaces.Index`), the block
//! scopes of the function for locals and parameters (a name is bound once where it is visible, `E_SHADOWING`), and the
//! checked tree for anything whose meaning depends on a type: a field of a value, a case named in a pattern. Names in type
//! positions resolve through the same module tables. A token this walk cannot attribute is reported as such, never guessed,
//! so the command refuses rather than leave a use behind (`rename_command.zig` compares every token spelled `name` with
//! this table).
const std = @import("std");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const lexer = @import("lexer.zig");
const pc = @import("project_compile.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");

const Span = source.Span;
const NodeData = @FieldType(ast.Node, "data");
const CallNode = @FieldType(NodeData, "call");
const MethodCallNode = @FieldType(NodeData, "method_call");
const RecordNode = @FieldType(NodeData, "record");
const VariantNode = @FieldType(NodeData, "variant");

/// Allocation, or merged syntax whose spans do not map back to a module.
pub const Error = std.mem.Allocator.Error || error{InternalError};

/// What one token means.
pub const Meaning = union(enum) {
    /// A declaration, by the merged span of its name token.
    declaration: Span,
    /// A pattern field written as one name, `case atom(text)`: the field's label and the local it binds.
    shorthand: struct { field: Span, local: Span },
    /// Something no rename names: a builtin, a module alias, a type parameter, a standard-library parameter.
    other,
    /// Several declarations at once: a field of a generic body that its instances read from different types.
    ambiguous,
};

/// What a token that declares something declares: a module-level name, a member of a type (a field or a case), or a local
/// or parameter; `none` for a use.
pub const Declares = enum { none, module_level, member, local };

/// One token spelled `name` and what it means. `pair` is the other half of a pattern field written `label=binding` with a
/// plain binding, so a rename that makes the two halves equal can write the shorthand instead.
pub const Occurrence = struct { span: Span, meaning: Meaning, pair: ?Span = null, declares: Declares = .none };

/// How far one local is visible: from its declaration to the end of the block that holds it, in merged offsets, inside the
/// function whose name token is `function`.
pub const Visibility = struct { declaration: Span, function: Span, end: usize };

/// Everything one walk found for one spelling.
pub const Table = struct {
    /// Every resolved token spelled `name`, by the merged offset where it starts.
    occurrences: std.array_hash_map.Auto(usize, Occurrence) = .empty,
    /// Every local or parameter declared under `name`, and how far it is visible.
    locals: std.ArrayList(Visibility) = .empty,
    /// Whether the checked tree was available: without it a field or a pattern case cannot be resolved.
    checked: bool = false,

    /// The meaning recorded for the token that starts at `start`, or null for a token the walk did not resolve.
    pub fn at(self: *const Table, start: usize) ?Occurrence {
        return self.occurrences.get(start);
    }
};

/// A module-level declaration as the interface index holds it, after following re-exports.
const Found = struct { module: usize, symbol: usize };

/// One local in the current function's scope.
/// One local in scope: its name, its declaration, and the type its declaration spells, when it spells one.
const Bound = struct { name: []const u8, declaration: Span, annotation: ?Span = null };

/// Where the walk is: the scope of the function it is in, and the declaration around it.
const Walk = struct {
    /// The locals visible at the current point of the current function.
    scope: std.ArrayList(Bound) = .empty,
    /// Locals of the current function declared under `name`, waiting for their block's end.
    open: std.ArrayList(struct { declaration: Span, depth: usize }) = .empty,
    /// The type parameters of the declaration being walked.
    type_parameters: []const ast.TypeParameter = &.{},
    /// The name token of the function being walked.
    function: Span = .{ .start = 0, .end = 0 },
    /// The module of the declaration being walked.
    module: usize = 0,
};

/// Tables built once per walk.
const Lookup = struct {
    /// The checked nodes by the span they were checked from: the first node, then `typed_next` for the others at one span.
    typed_first: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    typed_next: []u32 = &.{},
    /// The functions of the merged syntax by the start of their name token.
    functions: std.AutoHashMapUnmanaged(usize, usize) = .empty,
};

/// The walk over one merged program.
const Resolver = struct {
    allocator: std.mem.Allocator,
    compilation: *const pc.Compilation,
    name: []const u8,
    table: Table = .{},
    walk: Walk = .{},
    lookup: Lookup = .{},

    /// Walk the whole program for tokens spelled `name`.
    fn run(allocator: std.mem.Allocator, compilation: *const pc.Compilation, name: []const u8) Error!Table {
        var self: Resolver = .{ .allocator = allocator, .compilation = compilation, .name = name };
        try ast.ensureAll(compilation.syntax);
        try self.indexTyped();
        for (compilation.syntax.functions, 0..) |function, position| try self.lookup.functions.put(allocator, function.name.start, position);
        try self.declarations();
        try self.exportDirectives();
        try self.importDirectives();
        for (compilation.syntax.functions) |function| try self.functionBody(function);
        return self.table;
    }

    fn src(self: *const Resolver) source.Source {
        return self.compilation.src;
    }

    fn text(self: *const Resolver, span: Span) []const u8 {
        return self.compilation.src.text(span);
    }

    fn wanted(self: *const Resolver, span: Span) bool {
        return std.mem.eql(u8, self.text(span), self.name);
    }

    fn moduleOf(self: *const Resolver, span: Span) Error!usize {
        const original = self.src().originalSpan(span) catch return error.InternalError;
        return original.input;
    }

    fn record(self: *Resolver, span: Span, meaning: Meaning) Error!void {
        return self.recordPaired(span, meaning, null);
    }

    /// Record the token at `span` as the declaration of itself, of kind `declares`.
    fn declare(self: *Resolver, span: Span, declares: Declares) Error!void {
        try self.record(span, .{ .declaration = span });
        if (self.table.occurrences.getPtr(span.start)) |entry| entry.declares = declares;
    }

    fn recordPaired(self: *Resolver, span: Span, meaning: Meaning, pair: ?Span) Error!void {
        if (!self.wanted(span)) return;
        const entry = try self.table.occurrences.getOrPut(self.allocator, span.start);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .span = span, .meaning = meaning, .pair = pair };
            return;
        }
        // A token reached twice (an `is` test's value, a copied arm body) means one thing; two different answers are not a guess.
        if (!sameMeaning(entry.value_ptr.meaning, meaning)) entry.value_ptr.meaning = .ambiguous;
    }

    // ---- The checked tree -------------------------------------------------------------------------------------------

    fn spanKey(span: Span) u64 {
        return (@as(u64, @intCast(span.start)) << 32) | @as(u64, @intCast(span.end & 0xffff_ffff));
    }

    fn indexTyped(self: *Resolver) Error!void {
        const program = self.compilation.program orelse return;
        self.table.checked = true;
        self.lookup.typed_next = try self.allocator.alloc(u32, program.nodes.len);
        for (program.nodes, 0..) |item, position| {
            const key = spanKey(item.span);
            const entry = try self.lookup.typed_first.getOrPut(self.allocator, key);
            if (entry.found_existing) {
                self.lookup.typed_next[position] = entry.value_ptr.*;
            } else self.lookup.typed_next[position] = std.math.maxInt(u32);
            entry.value_ptr.* = @intCast(position);
        }
    }

    /// The record declarations a value at `span` has, as the checked nodes at that span say: one answer, several (a generic
    /// body's instances), or none (no checked node there).
    fn recordsAt(self: *const Resolver, span: Span, out: *std.ArrayList(usize)) Error!bool {
        const program = self.compilation.program orelse return false;
        var cursor = self.lookup.typed_first.get(spanKey(span)) orelse return false;
        while (cursor != std.math.maxInt(u32)) : (cursor = self.lookup.typed_next[cursor]) {
            const ty = program.nodes[cursor].ty;
            if (!ty.isAggregate()) continue;
            const found = ty.recordIndex();
            for (out.items) |seen| {
                if (seen == found) break;
            } else try out.append(self.allocator, found);
        }
        return true;
    }

    /// The function a checked call at `span` calls, when every checked node there agrees.
    fn calledAt(self: *const Resolver, span: Span) ?Span {
        const program = self.compilation.program orelse return null;
        var cursor = self.lookup.typed_first.get(spanKey(span)) orelse return null;
        var found: ?Span = null;
        while (cursor != std.math.maxInt(u32)) : (cursor = self.lookup.typed_next[cursor]) {
            const target = switch (program.nodes[cursor].data) {
                .call => |call| program.functions[@backingInt(call.function)].declaration,
                .function_value => |function| program.functions[@backingInt(function)].declaration,
                else => continue,
            };
            if (found) |seen| if (seen.start != target.start) return null;
            found = target;
        }
        return found;
    }

    /// Resolve a field or case named `member` against the records at `span`: the declaration when every record there has one,
    /// `ambiguous` when they disagree, null when no record there declares it.
    fn memberOfValue(self: *Resolver, span: Span, name: Span) Error!?Meaning {
        var records: std.ArrayList(usize) = .empty;
        defer records.deinit(self.allocator);
        if (try self.recordsAt(span, &records)) return self.memberOfRecords(records.items, name);
        // No checked node (a generic body no instance reached): a local whose declaration spells a record type.
        return self.memberOfDeclaredType(span, name);
    }

    /// The field `name` of the record a local's declared type names, when `span` is that local.
    fn memberOfDeclaredType(self: *Resolver, span: Span, name: Span) ?Meaning {
        const annotation = self.annotationOf(self.text(span)) orelse return null;
        const declaration = self.typeDeclarationIn(self.walk.module, typeHead(self.text(annotation), annotation)) orelse return null;
        return self.fieldNamed(declaration, name);
    }

    /// The field `name` of the record declared at `declaration`.
    fn fieldNamed(self: *const Resolver, declaration: Span, name: Span) ?Meaning {
        const fields = self.recordFields(declaration) orelse return null;
        for (fields) |field| if (std.mem.eql(u8, self.text(field.name), self.text(name))) return .{ .declaration = field.name };
        return null;
    }

    /// The type the declaration of the local `spelled` writes, when it writes one.
    fn annotationOf(self: *const Resolver, spelled: []const u8) ?Span {
        var cursor = self.walk.scope.items.len;
        while (cursor != 0) {
            cursor -= 1;
            const bound = self.walk.scope.items[cursor];
            if (std.mem.eql(u8, bound.name, spelled)) return bound.annotation;
        }
        return null;
    }

    /// The record declaration the place `id` has by declared types alone: a local whose declaration writes its type, then
    /// each field's declared type along a chain (`self.c.unbounded` with `self: Walker`). Null where a type is inferred.
    fn declaredRecordOf(self: *const Resolver, id: ast.NodeId) ?Span {
        const item = self.syntaxNode(id);
        switch (item.data) {
            .name => |span| {
                const annotation = self.annotationOf(self.text(span)) orelse return null;
                return self.typeDeclarationIn(self.walk.module, typeHead(self.text(annotation), annotation));
            },
            .field => |field| {
                const record_ = self.declaredRecordOf(field.base) orelse return null;
                const fields = self.recordFields(record_) orelse return null;
                for (fields) |declared_| {
                    if (!std.mem.eql(u8, self.text(declared_.name), self.text(field.name))) continue;
                    const module = self.moduleOf(declared_.ty) catch return null;
                    return self.typeDeclarationIn(module, typeHead(self.text(declared_.ty), declared_.ty));
                }
                return null;
            },
            else => return null,
        }
    }

    /// The type declaration a plain or qualified type name resolves to in module `from`, without recording anything.
    fn typeDeclarationIn(self: *const Resolver, from: usize, span: Span) ?Span {
        const spelled = std.mem.trim(u8, self.text(span), " ");
        const dot = std.mem.lastIndexOfScalar(u8, spelled, '.');
        const module = if (dot) |at| self.imported(from, spelled[0..at]) orelse return null else from;
        const found = self.memberNamed(module, if (dot) |at| spelled[at + 1 ..] else spelled) orelse return null;
        if (self.foundKind(found) != .type) return null;
        return self.foundSpan(found) catch null;
    }

    fn memberOfRecords(self: *Resolver, records: []const usize, name: Span) Error!?Meaning {
        const program = self.compilation.program orelse return null;
        var found: ?Span = null;
        for (records) |position| {
            const declared = fieldOf(self.compilation.src, program.records[position], self.text(name)) orelse continue;
            if (found) |seen| if (seen.start != declared.start) return .ambiguous;
            found = declared;
        }
        return if (found) |span| .{ .declaration = span } else null;
    }

    fn fieldOf(src_: source.Source, entry: typed.Record, name: []const u8) ?Span {
        for (entry.fields) |field| {
            if (std.mem.eql(u8, src_.text(field.declaration), name)) return field.declaration;
        }
        return null;
    }

    // ---- Module-level names ------------------------------------------------------------------------------------------

    fn interfaceIndex(self: *const Resolver) *interfaces.Index {
        return self.compilation.index;
    }

    /// The declaration `name` names in `module`, following re-exports to the module that declares it.
    fn memberNamed(self: *const Resolver, module: usize, name: []const u8) ?Found {
        const units = self.interfaceIndex().units;
        if (module >= units.len) return null;
        var at: Found = .{ .module = module, .symbol = units[module].names.get(name) orelse return null };
        var remaining = units.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const symbol = units[at.module].symbols.items[at.symbol];
            const origin = symbol.re_export orelse return at;
            at = .{ .module = origin.module, .symbol = origin.symbol };
        }
        return null;
    }

    fn foundSpan(self: *const Resolver, found: Found) Error!Span {
        const symbol = self.interfaceIndex().units[found.module].symbols.items[found.symbol];
        return self.src().mappedSpan(found.module, symbol.span) catch error.InternalError;
    }

    fn foundKind(self: *const Resolver, found: Found) interfaces.Kind {
        return self.interfaceIndex().units[found.module].symbols.items[found.symbol].kind;
    }

    /// The module an import qualifier of `module` names (`alias`, or the full dotted path).
    fn imported(self: *const Resolver, module: usize, qualifier: []const u8) ?usize {
        const modules = self.interfaceIndex().project.modules.items;
        if (module >= modules.len) return null;
        for (modules[module].imports) |entry| if (entry.matches(qualifier)) return entry.target;
        return null;
    }

    fn local(self: *const Resolver, name: []const u8) ?Span {
        var cursor = self.walk.scope.items.len;
        while (cursor != 0) {
            cursor -= 1;
            if (std.mem.eql(u8, self.walk.scope.items[cursor].name, name)) return self.walk.scope.items[cursor].declaration;
        }
        return null;
    }

    fn typeParameter(self: *const Resolver, name: []const u8) bool {
        for (self.walk.type_parameters) |parameter| {
            if (std.mem.eql(u8, self.text(parameter.name), name)) return true;
        }
        return false;
    }

    /// What one dotted path of plain names means where it is written, one segment at a time: each segment's meaning is
    /// recorded, and the meaning of the whole path is returned for the caller to continue from.
    const Path = union(enum) {
        /// A value: a local, a constant, or anything whose fields depend on its checked type. `span` is the path so far,
        /// whose checked node gives that type.
        value: Span,
        module: usize,
        /// A type declared in the program: its declaration, and its checked record when one is known.
        type: Span,
        /// A function declared in the program.
        function: Span,
        /// A case of a type, with the record of its named fields when it has them.
        case: struct { declaration: Span, fields: ?Span },
        /// Something that names nothing in the program.
        other,
    };

    /// The segments of a dotted name that starts at `span.start`: each a plain name.
    fn segments(self: *Resolver, span: Span) Error![]const Span {
        var list: std.ArrayList(Span) = .empty;
        const spelled = self.text(span);
        var start: usize = 0;
        for (spelled, 0..) |byte, at| {
            if (byte != '.') continue;
            try list.append(self.allocator, .{ .start = span.start + start, .end = span.start + at });
            start = at + 1;
        }
        try list.append(self.allocator, .{ .start = span.start + start, .end = span.end });
        return list.items;
    }

    /// Resolve the dotted path `span` as code writes it in an expression: a local first (a name is bound once where it is
    /// visible), then the module's own declarations, then its imports.
    fn path(self: *Resolver, span: Span) Error!Path {
        const parts = try self.segments(span);
        var at: Path = try self.head(parts[0]);
        var consumed: usize = 1;
        // An import qualifier may itself be dotted (`shared.units`): take the longest prefix that names an import.
        if (at == .other and parts.len > 1) {
            var length = parts.len - 1;
            while (length >= 2) : (length -= 1) {
                const prefix: Span = .{ .start = parts[0].start, .end = parts[length - 1].end };
                if (self.imported(self.walk.module, self.text(prefix))) |target| {
                    for (parts[0..length]) |part| try self.record(part, .other);
                    at = .{ .module = target };
                    consumed = length;
                    break;
                }
            }
        }
        for (parts[consumed..]) |part| {
            const so_far: Span = .{ .start = parts[0].start, .end = part.end };
            at = try self.step(at, part, so_far);
        }
        return at;
    }

    /// Whether `part` is spelled like an import alias of the module being walked.
    fn aliased(self: *const Resolver, part: Span) bool {
        const modules = self.interfaceIndex().project.modules.items;
        if (self.walk.module >= modules.len) return false;
        for (modules[self.walk.module].imports) |entry| if (std.mem.eql(u8, entry.alias, self.text(part))) return true;
        return false;
    }

    fn aliasHead(self: *Resolver, part: Span) Error!Path {
        try self.record(part, .other);
        return .{ .module = self.imported(self.walk.module, self.text(part)).? };
    }

    fn head(self: *Resolver, part: Span) Error!Path {
        const spelled = self.text(part);
        if (self.local(spelled)) |declaration| {
            try self.record(part, if (declaration.end == declaration.start) .other else .{ .declaration = declaration });
            return .{ .value = part };
        }
        if (self.typeParameter(spelled)) {
            try self.record(part, .other);
            return .other;
        }
        if (self.memberNamed(self.walk.module, spelled)) |found| return self.declaredAt(part, found);
        if (self.imported(self.walk.module, spelled)) |target| {
            try self.record(part, .other);
            return .{ .module = target };
        }
        try self.record(part, .other);
        return .other;
    }

    fn declaredAt(self: *Resolver, part: Span, found: Found) Error!Path {
        const declaration = try self.foundSpan(found);
        try self.record(part, .{ .declaration = declaration });
        return switch (self.foundKind(found)) {
            .type => .{ .type = declaration },
            .function => if (self.isConstant(declaration)) .{ .value = part } else .{ .function = declaration },
            .constraint => .other,
        };
    }

    fn isConstant(self: *const Resolver, declaration: Span) bool {
        const position = self.lookup.functions.get(declaration.start) orelse return false;
        return self.compilation.syntax.functions[position].policy.constant;
    }

    /// One more segment after `at`; `so_far` is the path up to and including `part`, `before` the segment before it.
    fn step(self: *Resolver, at: Path, part: Span, so_far: Span) Error!Path {
        switch (at) {
            .module => |target| {
                if (self.memberNamed(target, self.text(part))) |found| return self.declaredAt(part, found);
                try self.record(part, .other);
                return .other;
            },
            .type => |declaration| {
                // `Shape.circle`: a case of the type; `Distance.make`: a function the type owns.
                if (self.caseNamed(declaration, self.text(part))) |case| {
                    try self.record(part, .{ .declaration = case.declaration });
                    return .{ .case = .{ .declaration = case.declaration, .fields = case.fields } };
                }
                const owner_module = try self.moduleOf(declaration);
                const qualified = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.text(declaration), self.text(part) });
                if (self.memberNamed(owner_module, qualified)) |found| {
                    const target = try self.foundSpan(found);
                    try self.record(part, .{ .declaration = target });
                    return .{ .function = target };
                }
                return .other;
            },
            .value => |base| {
                if (try self.memberOfValue(base, part)) |meaning| try self.record(part, meaning);
                return .{ .value = so_far };
            },
            .function, .case, .other => return .other,
        }
    }

    /// The case `name` of the enum or union declared at `declaration`, from its syntax, with the declaration of the case
    /// itself as the place its named fields are found.
    fn caseNamed(self: *const Resolver, declaration: Span, name: []const u8) ?struct { declaration: Span, fields: ?Span } {
        for (self.compilation.syntax.types.variants) |variants| {
            if (variants.name.start != declaration.start) continue;
            for (variants.cases) |case| {
                if (std.mem.eql(u8, self.text(case.name), name)) return .{ .declaration = case.name, .fields = case.name };
            }
        }
        return null;
    }

    /// The named fields of the case declared at `case`, from its syntax.
    fn caseFields(self: *const Resolver, case: Span) []const ast.Parameter {
        for (self.compilation.syntax.types.variants) |variants| for (variants.cases) |item| {
            if (item.name.start == case.start) return item.fields;
        };
        return &.{};
    }

    /// The fields of the record declared at `declaration`, from its syntax.
    fn recordFields(self: *const Resolver, declaration: Span) ?[]const ast.Parameter {
        for (self.compilation.syntax.types.records) |entry| {
            if (entry.name.start == declaration.start) return entry.fields;
        }
        return null;
    }

    /// Record each label of `names` as the parameter or field of `fields` it names.
    fn labels(self: *Resolver, names: []const ?Span, fields: ?[]const ast.Parameter) Error!void {
        for (names) |maybe| {
            const label = maybe orelse continue;
            if (!self.wanted(label)) continue;
            const list = fields orelse {
                try self.record(label, .other);
                continue;
            };
            for (list) |field| {
                if (std.mem.eql(u8, self.text(field.name), self.text(label))) {
                    try self.record(label, .{ .declaration = field.name });
                    break;
                }
            }
        }
    }

    fn parametersOf(self: *const Resolver, declaration: Span) ?[]const ast.Parameter {
        const position = self.lookup.functions.get(declaration.start) orelse return null;
        return self.compilation.syntax.functions[position].signature.parameters;
    }

    // ---- Type positions ------------------------------------------------------------------------------------------------

    /// Every name in the type spelled at `span`: `T`, `alias.T`, `T[]`, `dict[K, V]`, `FixedArray[T, N]`, `func(A) -> B`.
    fn typeSpan(self: *Resolver, span: Span) Error!void {
        if (span.end <= span.start) return;
        if (std.mem.indexOf(u8, self.text(span), self.name) == null) return;
        var sink: diagnostic.Sink = .{ .allocator = self.allocator };
        const tokens = lexer.lexRange(self.allocator, self.src().bytes, span, &sink) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        var position: usize = 0;
        while (position < tokens.len) : (position += 1) {
            if (tokens[position].tag != .ident) continue;
            // A dotted name: this identifier and every `.name` after it.
            var last = position;
            while (last + 2 < tokens.len and tokens[last + 1].tag == .dot and tokens[last + 2].tag == .ident) last += 2;
            const whole: Span = .{ .start = tokens[position].span.start, .end = tokens[last].span.end };
            try self.typePath(whole);
            position = last;
        }
    }

    fn typePath(self: *Resolver, span: Span) Error!void {
        const parts = try self.segments(span);
        if (parts.len == 1) {
            const spelled = self.text(parts[0]);
            if (self.typeParameter(spelled)) return self.record(parts[0], .other);
            if (self.memberNamed(self.walk.module, spelled)) |found| {
                _ = try self.declaredAt(parts[0], found);
                return;
            }
            return self.record(parts[0], .other);
        }
        // A type is never a local's: a qualified type whose first segment is an import alias names the module, also where
        // a local of that name is in force, which only a refused program has (`E_SHADOWING`, D-FR18-4).
        if (self.aliased(parts[0])) {
            var at = try self.aliasHead(parts[0]);
            for (parts[1..]) |part| at = try self.step(at, part, .{ .start = parts[0].start, .end = part.end });
            return;
        }
        _ = try self.path(span);
    }

    // ---- Declarations --------------------------------------------------------------------------------------------------

    fn declarations(self: *Resolver) Error!void {
        const syntax = self.compilation.syntax;
        // Module-level declarations and the names their types use.
        for (self.interfaceIndex().units, 0..) |unit, module| for (unit.symbols.items) |symbol| {
            if (symbol.re_export != null) continue;
            const span = self.src().mappedSpan(module, symbol.span) catch continue;
            try self.declare(span, .module_level);
        };
        for (syntax.types.records) |entry| {
            try self.enter(entry.name, entry.type_parameters);
            try self.declare(entry.name, .module_level);
            for (entry.fields) |field| try self.parameterDeclaration(field, false);
            try self.invariants(entry.name);
        }
        for (syntax.types.variants) |variants| {
            try self.enter(variants.name, variants.type_parameters);
            try self.declare(variants.name, .module_level);
            for (variants.cases) |case| {
                try self.declare(case.name, .member);
                if (case.payload) |payload| try self.typeSpan(payload);
                for (case.fields) |field| try self.parameterDeclaration(field, false);
            }
        }
        for ([_][]const ast.Domain{ syntax.types.domains, syntax.types.resources }) |list| for (list) |domain| {
            try self.enter(domain.name, domain.type_parameters);
            try self.declare(domain.name, .module_level);
            try self.typeSpan(domain.backing);
            if (domain.codec) |codec| {
                try self.typeSpan(codec.wire);
                _ = try self.path(codec.decode);
                _ = try self.path(codec.encode);
            }
        };
        for (syntax.types.expressions.aliases) |alias| {
            try self.enter(alias.name, &.{});
            try self.declare(alias.name, .module_level);
            try self.typeSpan(alias.target);
        }
        for (syntax.types.constraints) |constraint| {
            try self.enter(constraint.name, &.{});
            try self.declare(constraint.name, .module_level);
            try self.typeParameterRequirements(constraint.subject);
        }
        self.walk.type_parameters = &.{};
    }

    /// A record's `@invariant(...)` conditions, where `self` is a value of the record.
    fn invariants(self: *Resolver, declared: Span) Error!void {
        const attributes = ast.attributesOf(self.compilation.syntax, declared);
        if (attributes.len == 0) return;
        self.walk.scope.clearRetainingCapacity();
        // `self` is declared nowhere in the source: an empty declaration, which no rename names.
        try self.walk.scope.append(self.allocator, .{ .name = "self", .declaration = .{ .start = 0, .end = 0 }, .annotation = declared });
        defer self.walk.scope.clearRetainingCapacity();
        for (attributes) |attribute| if (attribute.condition) |condition| try self.expression(condition);
    }

    fn enter(self: *Resolver, name: Span, parameters: []const ast.TypeParameter) Error!void {
        self.walk.module = try self.moduleOf(name);
        self.walk.type_parameters = parameters;
        for (parameters) |parameter| {
            try self.record(parameter.name, .other);
            try self.typeParameterRequirements(parameter);
        }
    }

    fn typeParameterRequirements(self: *Resolver, parameter: ast.TypeParameter) Error!void {
        for (parameter.requirements) |requirement| try self.typeSpan(requirement);
        for (parameter.field_requirements) |field| {
            // A field requirement names a field of every type argument, not one declaration.
            try self.record(field.name, .other);
            try self.typeSpan(field.ty);
        }
        for (parameter.operation_requirements) |operation| {
            try self.record(operation.name, .other);
            for (operation.parameters) |item| {
                try self.record(item.name, .other);
                try self.typeSpan(item.ty);
            }
            try self.typeSpan(operation.return_type);
        }
        for (parameter.named_requirements) |bound| {
            if (bound.alias) |alias| {
                try self.record(alias, .other);
                if (self.imported(self.walk.module, self.text(alias))) |target| {
                    if (self.memberNamed(target, self.text(bound.name))) |found| _ = try self.declaredAt(bound.name, found);
                }
            } else if (self.memberNamed(self.walk.module, self.text(bound.name))) |found| _ = try self.declaredAt(bound.name, found);
        }
    }

    /// A field of a record or case: its name, its type, and its default value.
    fn parameterDeclaration(self: *Resolver, field: ast.Parameter, parameter: bool) Error!void {
        if (!parameter) try self.declare(field.name, .member);
        if (parameter) try self.parameterMarkers(field);
        try self.typeSpan(field.ty);
        if (field.default_value) |value| try self.expression(value);
        if (parameter) try self.bindTyped(field.name, field.ty);
    }

    // ---- The contextual words `mut`, `own` and `named` -------------------------------------------------------------------

    /// Whether `word` is one the parser reads as a marker where one stands, and as an ordinary name elsewhere (`mut: int`).
    fn markerWord(word: []const u8) bool {
        return std.mem.eql(u8, word, "mut") or std.mem.eql(u8, word, "own") or std.mem.eql(u8, word, "named");
    }

    /// The identifier that ends just before `offset`, with only spaces or tabs between; null when none does.
    fn wordBefore(self: *const Resolver, offset: usize) ?Span {
        const bytes = self.src().bytes;
        var end = offset;
        while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
        var start = end;
        while (start > 0 and identifierByte(bytes[start - 1])) start -= 1;
        return if (start == end) null else .{ .start = start, .end = end };
    }

    /// The identifier that starts at `offset`, after any spaces or tabs; null when none does.
    fn wordAfter(self: *const Resolver, offset: usize) ?Span {
        const bytes = self.src().bytes;
        var start = offset;
        while (start < bytes.len and (bytes[start] == ' ' or bytes[start] == '\t')) start += 1;
        var end = start;
        while (end < bytes.len and identifierByte(bytes[end])) end += 1;
        return if (start == end) null else .{ .start = start, .end = end };
    }

    /// Record `word` as a marker, which no rename names: the parser read it as `mut`, `own` or `named` before a name, so it is no
    /// use of a declaration that is called the same. Only a word the parser can read so is taken.
    fn marker(self: *Resolver, word: ?Span) Error!void {
        const span = word orelse return;
        if (markerWord(self.text(span))) try self.record(span, .other);
    }

    /// Record the word that starts at `offset` as a marker when the renamed name is one the parser reads so.
    fn markerAt(self: *Resolver, offset: usize) Error!void {
        if (markerWord(self.name)) try self.marker(self.wordAfter(offset));
    }

    /// The markers of a parameter: `named`, then `own` or `mut`, before its name. Only a marker can stand before a parameter's name
    /// in its list, so each word found there is one.
    fn parameterMarkers(self: *Resolver, field: ast.Parameter) Error!void {
        if (!markerWord(self.name)) return;
        var position = field.name.start;
        for (0..2) |_| {
            const word = self.wordBefore(position) orelse return;
            if (!markerWord(self.text(word))) return;
            try self.marker(word);
            position = word.start;
        }
    }

    /// `export units.make` re-export directives: the qualifier and the declaration it publishes.
    fn exportDirectives(self: *Resolver) Error!void {
        for (self.interfaceIndex().project.modules.items, 0..) |module, position| for (module.exports) |directive| {
            const qualifier = directive.alias orelse continue;
            const span = self.src().mappedSpan(position, directive.span) catch continue;
            const spelled = self.text(span);
            // The directive's span covers `alias.Name`, possibly with `export` before it: find the name after the qualifier.
            const at = std.mem.lastIndexOf(u8, spelled, directive.name) orelse continue;
            const name: Span = .{ .start = span.start + at, .end = span.start + at + directive.name.len };
            if (std.mem.indexOf(u8, spelled, qualifier)) |q| try self.record(.{ .start = span.start + q, .end = span.start + q + qualifier.len }, .other);
            const target = self.imported(position, qualifier) orelse continue;
            const found = self.memberNamed(target, directive.name) orelse continue;
            try self.record(name, .{ .declaration = try self.foundSpan(found) });
        };
    }

    /// `import a.b as c` directives: each name there names a module, which no rename names. A local that hides an import
    /// alias is refused (`E_SHADOWING`), so these tokens are met only when a rename repairs that refusal (D-FR18-2).
    fn importDirectives(self: *Resolver) Error!void {
        for (self.interfaceIndex().project.modules.items, 0..) |module, position| for (module.imports) |directive| {
            const path_span = self.src().mappedSpan(position, directive.span) catch continue;
            // The directive's span is its path; `as alias` follows it on the same line.
            const bytes = self.src().bytes;
            const line_end = std.mem.indexOfScalarPos(u8, bytes, path_span.end, '\n') orelse bytes.len;
            const span: Span = .{ .start = path_span.start, .end = line_end };
            const spelled = self.text(span);
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, spelled, at, self.name)) |found| {
                at = found + 1;
                const end = found + self.name.len;
                if (found > 0 and identifierByte(spelled[found - 1])) continue;
                if (end < spelled.len and identifierByte(spelled[end])) continue;
                try self.record(.{ .start = span.start + found, .end = span.start + end }, .other);
            }
        };
    }

    // ---- Function bodies ---------------------------------------------------------------------------------------------

    fn functionBody(self: *Resolver, function: ast.Function) Error!void {
        self.walk.module = try self.moduleOf(function.name);
        self.walk.function = function.name;
        self.walk.type_parameters = function.signature.type_parameters;
        self.walk.scope.clearRetainingCapacity();
        self.walk.open.clearRetainingCapacity();
        for (function.signature.type_parameters) |parameter| {
            try self.record(parameter.name, .other);
            try self.typeParameterRequirements(parameter);
        }
        if (function.policy.owner) |owner| {
            if (self.memberNamed(self.walk.module, self.text(owner))) |found| _ = try self.declaredAt(owner, found) else try self.record(owner, .other);
        }
        for (function.signature.parameters) |parameter| try self.parameterDeclaration(parameter, true);
        try self.typeSpan(function.signature.return_type);
        if (function.signature.failure_type) |failure| try self.typeSpan(failure);
        // `-> T from name`: the parameters the result borrows.
        for (function.signature.borrowing) |name| {
            if (self.local(self.text(name))) |declaration| try self.record(name, .{ .declaration = declaration }) else try self.record(name, .other);
        }
        for (ast.attributesOf(self.compilation.syntax, function.name)) |attribute| {
            if (attribute.condition) |condition| try self.expression(condition);
            for (attribute.olds) |old| try self.expression(old);
        }
        try self.statement(function.body);
        try self.close(0, self.statementEnd(function.body));
        self.walk.type_parameters = &.{};
    }

    fn statementEnd(self: *const Resolver, id: ast.StatementId) usize {
        return self.compilation.syntax.statements.items[@backingInt(id)].span.end;
    }

    fn bind(self: *Resolver, name: ?Span) Error!void {
        return self.bindTyped(name, null);
    }

    /// Bind a local whose declaration spells its type (a parameter, `const x: T = ...`).
    fn bindTyped(self: *Resolver, name: ?Span, annotation: ?Span) Error!void {
        const span = name orelse return;
        const spelled = self.text(span);
        if (std.mem.eql(u8, spelled, "_")) return;
        // The compiler's own `mut x = x` of a bind-or-else re-declares the arm's binding at the same token.
        try self.declare(span, .local);
        try self.walk.scope.append(self.allocator, .{ .name = spelled, .declaration = span, .annotation = annotation });
        if (self.wanted(span)) try self.walk.open.append(self.allocator, .{ .declaration = span, .depth = self.walk.scope.items.len - 1 });
    }

    /// End every binding at or past `mark` at `end`, the end of the block that held it.
    fn close(self: *Resolver, mark: usize, end: usize) Error!void {
        while (self.walk.open.items.len != 0 and self.walk.open.items[self.walk.open.items.len - 1].depth >= mark) {
            const ended = self.walk.open.pop().?;
            try self.table.locals.append(self.allocator, .{ .declaration = ended.declaration, .function = self.walk.function, .end = end });
        }
        self.walk.scope.shrinkRetainingCapacity(@min(mark, self.walk.scope.items.len));
    }

    fn scoped(self: *Resolver, id: ast.StatementId) Error!void {
        const mark = self.walk.scope.items.len;
        try self.statement(id);
        try self.close(mark, self.statementEnd(id));
    }

    fn statement(self: *Resolver, id: ast.StatementId) Error!void {
        const statement_ = self.compilation.syntax.statements.items[@backingInt(id)];
        switch (statement_.data) {
            .block => |members| {
                const mark = self.walk.scope.items.len;
                for (members) |item| try self.statement(item);
                try self.close(mark, statement_.span.end);
            },
            .binding => |binding| {
                // `mut name = ...`: the statement opens with the marker (the compiler's own `adopt` binding has none).
                if (binding.mutable and !binding.adopt and binding.name.start > statement_.span.start) try self.markerAt(statement_.span.start);
                if (binding.annotation) |annotation| try self.typeSpan(annotation);
                if (binding.adopt) {
                    // `mut x = x`: the value is the arm's binding of the same token, which the new local re-declares.
                    try self.expression(binding.value);
                    try self.bind(binding.name);
                    return;
                }
                if (binding.initialized) try self.expression(binding.value);
                try self.bindTyped(binding.name, binding.annotation);
            },
            .for_each => |each| {
                try self.expression(each.iterable);
                const mark = self.walk.scope.items.len;
                try self.bind(each.name);
                try self.bind(each.index_name);
                try self.statement(each.body);
                try self.close(mark, self.statementEnd(each.body));
            },
            .for_range => |range| {
                try self.expression(range.start);
                try self.expression(range.end);
                if (range.step) |item| try self.expression(item);
                const mark = self.walk.scope.items.len;
                try self.bind(range.name);
                try self.statement(range.body);
                try self.close(mark, self.statementEnd(range.body));
            },
            .with_scope => |scope| {
                if (scope.resource) |resource| try self.expression(resource);
                const mark = self.walk.scope.items.len;
                try self.bind(scope.name);
                try self.statement(scope.body);
                try self.close(mark, self.statementEnd(scope.body));
            },
            .branch => |branch| {
                try self.expression(branch.condition);
                try self.scoped(branch.then_body);
                if (branch.else_body) |other| try self.scoped(other);
            },
            .loop => |loop| {
                try self.expression(loop.condition);
                try self.scoped(loop.body);
            },
            .match => |match| {
                try self.expression(match.value);
                try self.arms(match.value, match.arms);
            },
            .assertion => |assertion| {
                try self.expression(assertion.condition);
                if (assertion.value) |message| try self.expression(message);
            },
            .ret, .fail, .yield_value, .discard => |value| try self.expression(value),
            .assignment => |assignment| {
                if (self.local(self.text(assignment.name))) |declaration| {
                    try self.record(assignment.name, .{ .declaration = declaration });
                } else _ = try self.path(assignment.name);
                try self.expression(assignment.value);
            },
            .gather_step => |item| {
                try self.expression(item.value);
                if (item.key) |key| try self.expression(key);
            },
            .loop_exit => {},
        }
    }

    // ---- Patterns --------------------------------------------------------------------------------------------------

    /// The arms of a `match`: each case is a case of the matched value's checked type.
    fn arms(self: *Resolver, value: ast.NodeId, list: []const ast.MatchArm) Error!void {
        const span = self.compilation.syntax.nodes.items[@backingInt(value)].span;
        var records: std.ArrayList(usize) = .empty;
        defer records.deinit(self.allocator);
        const known = try self.recordsAt(span, &records);
        const matched: Matched = .{ .records = records.items, .known = known };
        for (list) |arm| {
            const mark = self.walk.scope.items.len;
            for (arm.literals) |literal| {
                // A bare name in a literal arm is a case when the matched value is an enum or a union, else a constant.
                const item = self.syntaxNode(literal);
                if (item.data == .name and records.items.len != 0) {
                    if (try self.caseIn(matched, item.data.name) == .found) continue;
                }
                try self.expression(literal);
            }
            try self.armPattern(matched, arm);
            try self.statement(arm.body);
            for (arm.alternatives.name_bodies) |copy| try self.statement(copy);
            try self.close(mark, self.statementEnd(arm.body));
        }
    }

    /// The types a pattern is matched against, and whether the checked tree said so (no checked node: a generic body
    /// no instance reached, or a program that did not check).
    const Matched = struct { records: []const usize, known: bool };

    fn armPattern(self: *Resolver, matched: Matched, arm: ast.MatchArm) Error!void {
        if (arm.ty.end > arm.ty.start) try self.typeSpan(arm.ty);
        // A bind-or-else arm takes an option's or a result's case, whatever it spells: its bindings are plain locals.
        if (arm.alternatives.role != .named) {
            for (arm.bindings) |binding| try self.bind(binding);
            for (arm.payload_patterns) |field| try self.patternField(.none, field);
            return;
        }
        const case = try self.caseIn(matched, arm.name);
        if (arm.payload_patterns.len == 0) {
            // `case integer(value=number)` with plain bindings: the labels are in `binding_names`, beside their bindings.
            for (arm.bindings, 0..) |binding, position| {
                const label: ?Span = if (position < arm.binding_names.len) arm.binding_names[position] else null;
                try self.patternField(case, .{ .name = label, .pattern = .{ .span = binding orelse arm.name, .data = .{ .binding = binding } } });
            }
            return;
        }
        for (arm.payload_patterns) |field| try self.patternField(case, field);
    }

    /// The case `name` names among the cases of the matched types, recorded; null when there is none or they disagree.
    fn caseIn(self: *Resolver, matched: Matched, name: Span) Error!CaseLookup {
        if (name.end <= name.start) return .none;
        var found: ?Case = null;
        var conflict = false;
        for (matched.records) |position| {
            const case = self.caseOf(position, self.text(name)) orelse continue;
            if (found) |seen| {
                if (seen.declaration.start != case.declaration.start) conflict = true;
            } else found = case;
        }
        if (conflict) {
            try self.record(name, .ambiguous);
            return .unknown;
        }
        if (found) |case| {
            try self.record(name, .{ .declaration = case.declaration });
            return .{ .found = case };
        }
        if (self.isBuiltinCase(self.text(name))) {
            try self.record(name, .other);
            return .none;
        }
        // A literal arm's bare name over a value the checked tree types but that is no enum: a constant.
        if (matched.known and matched.records.len == 0) {
            if (self.memberNamed(self.walk.module, self.text(name))) |member_| _ = try self.declaredAt(name, member_);
            return .none;
        }
        return .unknown;
    }

    /// What a pattern's case name found: a case of the matched type, nothing the program declares (an option's or a
    /// result's case, a constant), or nothing known here (no checked node: another check may know it).
    const CaseLookup = union(enum) { found: Case, none, unknown };

    /// A case found among the cases of a type: its declaration, the record of its named fields, and the record its single
    /// payload is, when it has one of those.
    const Case = struct { declaration: Span, fields: ?usize = null, payload: ?usize = null };

    /// The case `name` of the enum or union the record `index` is.
    fn caseOf(self: *const Resolver, position: usize, name: []const u8) ?Case {
        const program = self.compilation.program orelse return null;
        const variants = program.records[position].shape.variants orelse return null;
        for (variants.cases) |case| {
            if (!std.mem.eql(u8, self.text(case.declaration), name)) continue;
            const payload = case.payload orelse return .{ .declaration = case.declaration };
            if (!payload.isAggregate()) return .{ .declaration = case.declaration };
            if (case.fielded) return .{ .declaration = case.declaration, .fields = payload.recordIndex() };
            return .{ .declaration = case.declaration, .payload = payload.recordIndex() };
        }
        return null;
    }

    fn isBuiltinCase(_: *const Resolver, name: []const u8) bool {
        for ([_][]const u8{ "Some", "None", "Ok", "Err" }) |builtin| if (std.mem.eql(u8, builtin, name)) return true;
        return false;
    }

    fn patternField(self: *Resolver, lookup: CaseLookup, field: ast.PatternField) Error!void {
        const case: ?Case = if (lookup == .found) lookup.found else null;
        const fields: ?usize = if (case) |found| found.fields else null;
        const binding: ?Span = switch (field.pattern.data) {
            .binding => |name| name,
            .variant => null,
        };
        if (field.name) |label| {
            if (self.fieldIn(case, label)) |declared| try self.recordPaired(label, declared, binding);
            if (binding) |name| {
                try self.bind(name);
                // The binding's pair is the label, so a rename that makes them equal can write the shorthand.
                if (self.wanted(name)) if (self.table.occurrences.getPtr(name.start)) |entry| {
                    entry.pair = label;
                };
            }
        } else if (binding) |name| {
            // `case atom(text)`: the bare name is the field's own, and the local it binds.
            try self.bind(name);
            if (self.wanted(name)) switch (lookup) {
                .found => if (self.fieldIn(case, name)) |declared| {
                    if (self.table.occurrences.getPtr(name.start)) |entry| entry.meaning = .{ .shorthand = .{ .field = declared.declaration, .local = name } };
                },
                .none => {},
                // Whether the name is a field's is not known here (unless no case declares a field of that name); another
                // check of the file may know it.
                .unknown => if (self.anyCaseField(self.text(name))) {
                    _ = self.table.occurrences.swapRemove(name.start);
                },
            };
        }
        switch (field.pattern.data) {
            .binding => {},
            .variant => |nested| {
                // The nested case is a case of the field's own type, or of the single payload's.
                var records: std.ArrayList(usize) = .empty;
                defer records.deinit(self.allocator);
                var known = false;
                if (fields) |payload| if (field.name) |label| {
                    known = true;
                    const program = self.compilation.program.?;
                    for (program.records[payload].fields) |item| {
                        if (!std.mem.eql(u8, self.text(item.declaration), self.text(label))) continue;
                        if (item.ty.isAggregate()) try records.append(self.allocator, item.ty.recordIndex());
                    }
                };
                if (case) |found| if (found.payload) |payload| {
                    known = true;
                    try records.append(self.allocator, payload);
                };
                if (nested.ty.end > nested.ty.start) try self.typeSpan(nested.ty);
                const inner = try self.caseIn(.{ .records = records.items, .known = known }, nested.name);
                for (nested.fields) |item| try self.patternField(inner, item);
            },
        }
    }

    /// Whether some case of the program declares a named field called `name`.
    fn anyCaseField(self: *const Resolver, name: []const u8) bool {
        for (self.compilation.syntax.types.variants) |variants| for (variants.cases) |case| for (case.fields) |field| {
            if (std.mem.eql(u8, self.text(field.name), name)) return true;
        };
        return false;
    }

    /// The field `label` names in a pattern of `case`: the named field its declaration has under that name. Null when the
    /// case is not known here, or has no such field (the check refused it).
    fn fieldIn(self: *Resolver, case: ?Case, label: Span) ?Meaning {
        const found = case orelse return null;
        for (self.caseFields(found.declaration)) |field| {
            if (std.mem.eql(u8, self.text(field.name), self.text(label))) return .{ .declaration = field.name };
        }
        return null;
    }

    // ---- Expressions -------------------------------------------------------------------------------------------------

    fn syntaxNode(self: *const Resolver, id: ast.NodeId) ast.Node {
        return self.compilation.syntax.nodes.items[@backingInt(id)];
    }

    fn expression(self: *Resolver, id: ast.NodeId) Error!void {
        const item = self.syntaxNode(id);
        switch (item.data) {
            .name => |span| _ = try self.path(span),
            .field => _ = try self.pathOf(id),
            .call => |call| {
                for (call.type_arguments) |argument| try self.typeSpan(argument);
                try self.callee(item.span, call);
                for (call.arguments) |argument| try self.expression(argument);
            },
            .method_call => |call| try self.methodCall(item.span, call),
            .record => |built| try self.construction(built),
            .variant => |variant| try self.variantConstruction(variant),
            .buffer_operation => |operation| {
                _ = try self.path(operation.owner);
                for (operation.arguments) |argument| try self.expression(argument);
            },
            .file_operation => |operation| {
                _ = try self.path(operation.owner);
                if (operation.argument) |argument| try self.expression(argument);
            },
            .resource_io => |operation| {
                _ = try self.path(operation.owner);
                try self.typeSpan(operation.ty);
                if (operation.value) |value| try self.expression(value);
            },
            .arena_escape => |escape| {
                _ = try self.path(escape.arena);
                try self.expression(escape.value);
            },
            .cast, .wrap => |value| {
                try self.typeSpan(value.ty);
                try self.expression(value.value);
            },
            .acquire_resource => |resource| {
                try self.typeSpan(resource.ty);
                try self.expression(resource.capability);
                try self.expression(resource.request);
            },
            .complete_resource => |resource| {
                try self.typeSpan(resource.ty);
                try self.expression(resource.value);
            },
            .accept_resource => |resource| {
                try self.typeSpan(resource.ty);
                try self.expression(resource.value);
            },
            .environment_get => |get| {
                try self.typeSpan(get.ty);
                try self.expression(get.capability);
                try self.expression(get.name);
            },
            .external_read => |read| {
                try self.typeSpan(read.ty);
                try self.expression(read.capability);
            },
            .stand_in => |stand_in| {
                if (stand_in.ty) |ty| try self.typeSpan(ty);
                try self.expression(stand_in.first);
                if (stand_in.second) |second| try self.expression(second);
            },
            .match_expression => |match| {
                try self.expression(match.value);
                try self.arms(match.value, match.arms);
            },
            .variant_test => |check| {
                try self.expression(check.value);
                try self.statement(check.check);
            },
            .mut_argument, .own_argument => |value| {
                // The node opens with its marker; the compiler's own `own` of a named argument has the name's span instead.
                if (self.syntaxNode(value).span.start > item.span.start) try self.markerAt(item.span.start);
                try self.expression(value);
            },
            .gather => |gather| try self.scoped(gather.loop),
            .comprehension => |comprehension| {
                const mark = self.walk.scope.items.len;
                switch (comprehension.source) {
                    .iterable => |iterable| try self.expression(iterable),
                    .range => |bounds| {
                        try self.expression(bounds.start);
                        try self.expression(bounds.end);
                        if (bounds.step) |item_| try self.expression(item_);
                    },
                }
                try self.bind(comprehension.name);
                try self.expression(comprehension.output);
                if (comprehension.filter) |filter| try self.expression(filter);
                try self.close(mark, item.span.end);
            },
            else => try self.children(ast.Node, item),
        }
    }

    /// `receiver.name(arguments)`: a case's constructor or a module's function through a qualifier the parser did not join,
    /// or a call on a value, which the checked tree resolves.
    fn methodCall(self: *Resolver, span: Span, call: MethodCallNode) Error!void {
        const base = try self.pathOf(call.base);
        switch (try self.step(base, call.name, span)) {
            .case => |case| try self.labels(call.argument_names, self.caseFields(case.declaration)),
            .function => |declaration| try self.labels(call.argument_names, self.parametersOf(declaration)),
            else => {
                const called: ?Span = if (base == .value) self.calledAt(span) else null;
                if (called) |declaration| try self.record(call.name, .{ .declaration = declaration }) else try self.record(call.name, .other);
                try self.labels(call.argument_names, null);
            },
        }
        for (call.arguments) |argument| try self.expression(argument);
    }

    /// A record built with its fields named: each label is the field of that name.
    fn construction(self: *Resolver, built: RecordNode) Error!void {
        const meaning = try self.typeName(built.name);
        const fields: ?[]const ast.Parameter = if (meaning) |declaration| self.recordFields(declaration) else null;
        for (built.fields) |field| {
            if (fields) |list| for (list) |declared_| {
                if (std.mem.eql(u8, self.text(declared_.name), self.text(field.name))) try self.record(field.name, .{ .declaration = declared_.name });
            };
            try self.expression(field.value);
        }
    }

    /// `Type.case(...)`: the case of the type, and its named fields.
    fn variantConstruction(self: *Resolver, variant: VariantNode) Error!void {
        try self.typeSpan(variant.ty);
        const owner = try self.typeName(variant.ty);
        var fields: []const ast.Parameter = &.{};
        if (owner) |declaration| if (self.caseNamed(declaration, self.text(variant.name))) |case| {
            try self.record(variant.name, .{ .declaration = case.declaration });
            fields = self.caseFields(case.declaration);
        };
        try self.labels(variant.value_names, fields);
        if (variant.value) |value| try self.expression(value);
        for (variant.values) |value| try self.expression(value);
    }

    /// The meaning of a node used as the base of a field read or a member call.
    fn pathOf(self: *Resolver, id: ast.NodeId) Error!Path {
        const item = self.syntaxNode(id);
        switch (item.data) {
            .name => |span| return self.path(span),
            .field => |field| {
                const base = try self.pathOf(field.base);
                switch (base) {
                    .value => {
                        if (try self.memberOfValue(self.syntaxNode(field.base).span, field.name)) |meaning| {
                            try self.record(field.name, meaning);
                        } else if (self.declaredRecordOf(field.base)) |record_| {
                            // No checked node at the base (an assignment's target, a body not checked): its declared type.
                            if (self.fieldNamed(record_, field.name)) |meaning| try self.record(field.name, meaning);
                        }
                        return .{ .value = item.span };
                    },
                    else => return self.step(base, field.name, item.span),
                }
            },
            else => {
                try self.expression(id);
                return .{ .value = item.span };
            },
        }
    }

    /// The type a constructor or variant names, recorded.
    fn typeName(self: *Resolver, span: Span) Error!?Span {
        if (span.end <= span.start) return null;
        // `alias.Type[T]` or `Type[T]`: the name is everything before the first `[`.
        const spelled = self.text(span);
        const cut = std.mem.indexOfScalar(u8, spelled, '[') orelse spelled.len;
        const name: Span = .{ .start = span.start, .end = span.start + cut };
        if (cut != spelled.len) try self.typeSpan(.{ .start = span.start + cut, .end = span.end });
        return switch (try self.path(name)) {
            .type => |declaration| declaration,
            else => null,
        };
    }

    /// The callee of a call: a function, a record's constructor, a case's constructor, a callback, or a builtin; then the
    /// labels of its named arguments, which name the callee's parameters or fields.
    fn callee(self: *Resolver, span: Span, call: CallNode) Error!void {
        if (call.owner) |owner| {
            const base = try self.path(owner);
            const meaning = try self.step(base, call.name, span);
            switch (meaning) {
                .case => |case| return self.labels(call.argument_names, self.caseFields(case.declaration)),
                .function => |declaration| return self.labels(call.argument_names, self.parametersOf(declaration)),
                else => {},
            }
            if (base == .value) {
                if (self.calledAt(span)) |declaration| {
                    try self.record(call.name, .{ .declaration = declaration });
                    return self.labels(call.argument_names, self.parametersOf(declaration));
                }
            }
            try self.record(call.name, .other);
            return self.labels(call.argument_names, null);
        }
        const spelled = self.text(call.name);
        const cut = std.mem.indexOfScalar(u8, spelled, '[') orelse spelled.len;
        const name: Span = .{ .start = call.name.start, .end = call.name.start + cut };
        if (cut != spelled.len) try self.typeSpan(.{ .start = call.name.start + cut, .end = call.name.end });
        switch (try self.path(name)) {
            .function => |declaration| try self.labels(call.argument_names, self.parametersOf(declaration)),
            .type => |declaration| try self.labels(call.argument_names, self.recordFields(declaration)),
            .case => |case| try self.labels(call.argument_names, self.caseFields(case.declaration)),
            else => try self.labels(call.argument_names, null),
        }
    }

    /// Visit every expression and statement a value of type `T` holds, in the order they are written.
    // twin-drift-ok: the same reflective walk as `local_qualifiers.zig`, over this walker's own expression and statement visits.
    fn children(self: *Resolver, comptime T: type, value: T) Error!void {
        if (T == ast.NodeId) return self.expression(value);
        if (T == ast.StatementId) return self.statement(value);
        if (T == Span) return;
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| try self.children(Field, @field(value, name)),
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), name)) try self.children(Field, @field(value, name));
            },
            .optional => |optional| if (value) |present| try self.children(optional.child, present),
            .pointer => |pointer| if (pointer.size == .slice and pointer.child != u8) for (value) |entry| try self.children(pointer.child, entry),
            .array => |array| for (value) |entry| try self.children(array.child, entry),
            else => {},
        }
    }
};

/// Resolve every token spelled `name` in the merged program of `compilation`, allocating the table in `allocator` (an arena
/// the caller frees).
pub fn resolve(allocator: std.mem.Allocator, compilation: *const pc.Compilation, name: []const u8) Error!Table {
    return Resolver.run(allocator, compilation, name);
}

/// The type name a written type starts with: `Box` of `Box[T]`, `alias.Row` of `alias.Row`.
fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn typeHead(written: []const u8, span: Span) Span {
    return .{ .start = span.start, .end = span.start + (std.mem.indexOfScalar(u8, written, '[') orelse written.len) };
}

fn sameMeaning(left: Meaning, right: Meaning) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .declaration => |span| span.start == right.declaration.start,
        .shorthand => |pair| pair.field.start == right.shorthand.field.start and pair.local.start == right.shorthand.local.start,
        .other, .ambiguous => true,
    };
}

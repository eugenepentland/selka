//! Compiler-derived reference answers.
//!
//! Every fact this engine reports comes from data embedded in the executable
//! that runs it: the `src/features.json` manifest, the embedded standard
//! modules behind `src/standard_library.zig`, the curated `reference_text.zig`
//! prose, and the checker's own builtin tables. The engine reads nothing from
//! the filesystem or the environment, which is what keeps an answer correct
//! when the executable is used outside a source checkout.
//!
//! Every entry point takes the compiler surface as a comptime parameter,
//! because a Zig source file may belong to only one module: `src/main.zig`'s
//! module imports the compiler as the `selka` module, so a file it imports may
//! not also import the compiler's own files. The installed executable passes
//! `@import("selka")`; the unit tests pass the same compiler root through
//! their test module.

const std = @import("std");
const product = @import("compiler_root").compiler_language.product;
const reference_text = @import("reference_text.zig");
const user_docs = @import("user_docs.zig");
const reference_source = @import("reference_source.zig");
const diagnostic_codes = @import("diagnostic_codes.zig");
const ownership_rules = @import("compiler_root").compiler_language.ownership_rules;
const typed = @import("compiler_root").compiler_language.typed;

/// Wire version of the JSON envelope this engine emits.
pub const envelope_version = "reference-v1";

/// Rendering the caller asked for.
pub const Format = enum { text, json };

/// Requests the engine rejects, and allocation failure.
pub const Error = error{ OutOfMemory, EmptyQuery };

/// One reference request: the term to match and how to render the answer.
pub const Request = struct {
    /// Term matched case-insensitively as a substring of every fact's slug,
    /// name, summary, signature, receiver families, source table or diagnostic
    /// code. An empty
    /// or whitespace-only term is a usage error.
    query: []const u8,
    /// Rendering to produce; text is the default.
    format: Format = .text,
    /// Whether the embedded standard modules' bodies are checked. The command
    /// always checks; `false` documents and tests the declaration-only path,
    /// where no inferred effect is published.
    check_bodies: bool = true,
};

/// The synthesized entry module's name.
pub const entry_module = "reference";
/// The synthesized entry module's project path.
pub const entry_path = "reference.selka";

/// Read the synthesized entry module and refuse every other path.
///
/// `project.Project` answers the embedded standard modules from
/// `src/standard_library.zig` before any provider is consulted, so this reader
/// is the reference project's whole filesystem surface: one in-memory string.
/// A path it refuses is a path the engine would have had to read from disk,
/// which it never does. The reader is generic only because the provider's
/// callback type names the compiler's own error set.
pub fn EntryReader(comptime language: type) type {
    return struct {
        entry: []const u8,

        /// Serve `reference.selka`; return NotFound for every other path.
        pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (!std.mem.eql(u8, path, entry_path)) return error.NotFound;
            if (self.entry.len > limit) return error.TooLarge;
            return allocator.dupe(u8, self.entry);
        }

        /// The project provider this entry reader backs.
        pub fn provider(self: *@This()) language.project.Provider {
            return .{ .context = self, .read = read };
        }
    };
}

/// Answer one reference request with caller-owned bytes.
pub fn run(comptime language: type, allocator: std.mem.Allocator, request: Request) Error![]u8 {
    const query = std.mem.trim(u8, request.query, " \t\r\n");
    if (query.len == 0) return error.EmptyQuery;
    // Every intermediate fact borrows this arena, which is released before the
    // caller-owned answer is returned.
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const answer = try gather(language, scratch.allocator(), query, request.check_bodies);
    return switch (request.format) {
        .text => renderText(allocator, answer),
        .json => renderJson(allocator, answer),
    };
}

/// How far the analysis of the embedded standard modules got.
const Analysis = enum {
    /// Bodies were checked, so concrete declarations have checked status.
    checked,
    /// Only declarations were parsed; body facts are unavailable.
    declaration_only,
    /// The embedded modules could not be analyzed at all.
    unavailable,
};

/// Where one declaration's published facts come from.
const Derivation = enum {
    /// Bodies were checked and this declaration has a checked instantiation.
    checked,
    /// Bodies were not checked, so body facts are unavailable.
    declaration_only,
    /// Bodies were checked, but this generic declaration was never
    /// instantiated here; its declaration is not presented as a checked body.
    template,
    /// A type, resource or constraint declaration: declared in source, with no
    /// body to analyze.
    declared,
};

/// One implemented feature from the embedded manifest.
const Feature = struct {
    slug: []const u8,
    kind: []const u8,
    summary: []const u8,
    doc: []const u8,

    fn matchesQuery(self: Feature, query: []const u8) bool {
        return containsIgnoreCase(self.slug, query) or containsIgnoreCase(self.kind, query) or
            containsIgnoreCase(self.summary, query) or containsIgnoreCase(self.doc, query);
    }
    fn key(self: Feature) []const u8 {
        return self.slug;
    }
    /// Emit this feature as a reference-v1 record.
    pub fn jsonStringify(self: Feature, writer: anytype) !void {
        try writer.write(.{ .slug = self.slug, .kind = self.kind, .summary = self.summary, .doc = self.doc });
    }
};

/// Why a name that is not a feature is absent from the language.
const ExclusionStatus = enum { unsupported, native_exclusion, removed };

/// One unsupported, native-excluded or removed capability.
const Exclusion = struct {
    slug: []const u8,
    status: ExclusionStatus,
    /// The manifest's note for a removed capability, or null: `unsupported`
    /// and `native_exclusions` record a name and nothing else, and an empty
    /// string would present that absence as an empty fact.
    detail: ?[]const u8,
    date: ?[]const u8,

    fn matchesQuery(self: Exclusion, query: []const u8) bool {
        if (containsIgnoreCase(self.slug, query)) return true;
        if (containsIgnoreCase(exclusionStatusName(self.status), query)) return true;
        if (self.detail) |detail| return containsIgnoreCase(detail, query);
        return false;
    }
    fn key(self: Exclusion) []const u8 {
        return self.slug;
    }
    /// Emit this exclusion as a reference-v1 record.
    pub fn jsonStringify(self: Exclusion, writer: anytype) !void {
        try writer.write(.{
            .slug = self.slug,
            .status = exclusionStatusName(self.status),
            .detail = self.detail,
            .date = self.date,
        });
    }
};

/// One supported boundary from the embedded manifest.
const Limit = struct {
    name: []const u8,
    boundary: []const u8,

    fn matchesQuery(self: Limit, query: []const u8) bool {
        return containsIgnoreCase(self.name, query) or containsIgnoreCase(self.boundary, query);
    }
    fn key(self: Limit) []const u8 {
        return self.name;
    }
    /// Emit this boundary as a reference-v1 record.
    pub fn jsonStringify(self: Limit, writer: anytype) !void {
        try writer.write(.{ .name = self.name, .boundary = self.boundary });
    }
};

/// One curated syntax example with its Python boundary.
const Syntax = struct {
    id: []const u8,
    title: []const u8,
    summary: []const u8,
    python: []const u8,
    example: []const u8,

    fn matchesQuery(self: Syntax, query: []const u8) bool {
        return containsIgnoreCase(self.id, query) or containsIgnoreCase(self.title, query) or
            containsIgnoreCase(self.summary, query) or containsIgnoreCase(self.python, query);
    }
    fn key(self: Syntax) []const u8 {
        return self.id;
    }
    /// Emit this curated entry as a reference-v1 record.
    pub fn jsonStringify(self: Syntax, writer: anytype) !void {
        try writer.write(.{
            .id = self.id,
            .title = self.title,
            .summary = self.summary,
            .python = self.python,
            .example = self.example,
        });
    }
};

/// Whether a builtin name is a callable or a type constructor.
const BuiltinKind = enum { function, type };

/// One name the checker answers without an import.
const Builtin = struct {
    name: []const u8,
    kind: BuiltinKind,
    /// Argument count from the checker's table, or null when that table
    /// carries no count for this name.
    arity: ?usize,
    /// The table this fact was read from.
    source: []const u8,

    fn matchesQuery(self: Builtin, query: []const u8) bool {
        return containsIgnoreCase(self.name, query) or containsIgnoreCase(@tagName(self.kind), query) or
            containsIgnoreCase(self.source, query);
    }
    fn key(self: Builtin) []const u8 {
        return self.name;
    }
    /// Emit this builtin as a reference-v1 record.
    pub fn jsonStringify(self: Builtin, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .kind = @tagName(self.kind),
            .arity = self.arity,
            .source = self.source,
        });
    }
};

/// One accepted collection-method spelling and its receiver families.
const Method = struct {
    name: []const u8,
    arities: []const usize,
    families: []const u8,
    source: []const u8,

    fn matchesQuery(self: Method, query: []const u8) bool {
        return containsIgnoreCase(self.name, query) or containsIgnoreCase(self.families, query) or
            containsIgnoreCase(self.source, query);
    }
    fn key(self: Method) []const u8 {
        return self.name;
    }
    /// Emit this collection method as a reference-v1 record.
    pub fn jsonStringify(self: Method, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .arities = self.arities,
            .families = self.families,
            .source = self.source,
            .method_form = method_form,
        });
    }
};

/// What every collection-method fact says about the spelling: the compiler lists the operation, and refuses it as a method.
const method_form = "refused";
/// The text line that explains `method_form` to a reader of the text answer.
const method_form_note = "  method form: refused (E_METHOD_REMOVED); write the function, a prelude name such as `append(mut xs, x)` or a module function such as `strings.split(text, separator)`\n";

/// One exported standard-library declaration with its derivation status.
const Declaration = struct {
    /// Module-qualified name, `module::symbol`, the identity
    /// `selka list-interfaces` publishes.
    name: []const u8,
    /// Contract kind: `function`, `record`, `enum`, `union`, `result`,
    /// `resource`, `domain` or `constraint`.
    kind: []const u8,
    /// The callable signature for functions, or the declared shape for a type
    /// declaration.
    signature: []const u8,
    analysis: Derivation,
    /// Declared `mutates(...)` parameter names, null when the source wrote no
    /// clause.
    mutates: ?[]const []const u8,
    /// The call form, one-line description and source position the module's own text gives.
    source: reference_source.Found,

    fn matchesQuery(self: Declaration, query: []const u8) bool {
        return containsIgnoreCase(self.name, query) or containsIgnoreCase(self.kind, query) or
            containsIgnoreCase(self.signature, query);
    }
    fn key(self: Declaration) []const u8 {
        return self.name;
    }
    /// Emit this declaration as a reference-v1 record.
    pub fn jsonStringify(self: Declaration, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .kind = self.kind,
            .signature = self.signature,
            .analysis = derivationName(self.analysis),
            .mutates = self.mutates,
            .call = self.source.call,
            .summary = optionalText(self.source.summary),
        });
    }
};

/// One diagnostic code with its general meaning and the guide that covers it.
const Code = struct {
    code: []const u8,
    meaning: []const u8,
    guide: []const u8,
    rules: []const ownership_rules.Rule,

    fn matchesQuery(self: Code, query: []const u8) bool {
        return containsIgnoreCase(self.code, query);
    }
    fn key(self: Code) []const u8 {
        return self.code;
    }
    /// Emit this diagnostic code as a reference-v1 record.
    pub fn jsonStringify(self: Code, writer: anytype) !void {
        var storage: ownership_rules.Grouped = .{};
        try writer.write(.{ .code = self.code, .meaning = self.meaning, .guide = self.guide, .rules = self.rules, .rule_families = ownership_rules.grouped(self.rules, &storage) });
    }
};

/// Matched facts by category, each in deterministic key order.
const Facts = struct {
    syntax: []const Syntax,
    features: []const Feature,
    limits: []const Limit,
    exclusions: []const Exclusion,
    declarations: []const Declaration,
    builtins: []const Builtin,
    methods: []const Method,
    codes: []const Code,
};

/// How the analysis of the embedded standard modules ended.
const Library = struct {
    status: Analysis,
    reason: ?[]const u8,
    modules: usize,
    exports: usize,
};

/// The language identity the embedded manifest reports.
const Language = struct { version: []const u8, backend: []const u8 };

/// Whether the term matched a whole key, part of one, or nothing.
const Match = enum { exact, substring, none };

/// One assembled answer before rendering.
const Answer = struct {
    query: []const u8,
    match: Match,
    language: Language,
    library: Library,
    facts: Facts,
    /// The short answers a name that is a prelude function, a module or a module function earns; empty otherwise.
    lookups: []const Lookup,
};

/// One line of a lookup: a declaration's dotted name, its call form and its one-line description.
const Line = struct {
    name: []const u8,
    call: []const u8,
    summary: ?[]const u8,
};

/// A module's declarations, or one declaration, or the names nearest to a missing one.
const Listing = struct {
    /// The name the lookup answers: the module, or the qualified name asked for.
    name: []const u8,
    /// The standard module the lines come from.
    module: []const u8,
    /// The `selka docs` topic that covers the module.
    guide: []const u8,
    lines: []const Line,
};

/// A short answer to a name that needs no search: the call a program writes, with its description and its guide.
const Lookup = union(enum) {
    /// A bare prelude name such as `len`.
    prelude: reference_text.Prelude,
    /// A module-qualified function or type such as `strings.split`.
    declaration: Listing,
    /// A module's name: its exported declarations in source order.
    module: Listing,
    /// A qualified name no module declares: the declared names nearest to it.
    nearest: Listing,

    /// Emit this lookup as a reference-v1 `answers` record.
    pub fn jsonStringify(self: Lookup, writer: anytype) !void {
        switch (self) {
            .prelude => |entry| try writer.write(.{ .kind = "prelude", .name = entry.name, .call = entry.call, .summary = entry.summary, .guide = entry.guide }),
            .declaration => |listing| try writer.write(.{
                .kind = "declaration",
                .name = listing.name,
                .call = listing.lines[0].call,
                .summary = listing.lines[0].summary,
                .guide = listing.guide,
            }),
            .module => |listing| try writer.write(.{ .kind = "module", .name = listing.name, .guide = listing.guide, .declarations = listing.lines }),
            .nearest => |listing| try writer.write(.{
                .kind = "nearest",
                .name = listing.name,
                .module = listing.module,
                .guide = listing.guide,
                .candidates = listing.lines,
            }),
        }
    }
};

/// Declarations plus the status of the analysis that produced them.
const LibraryFacts = struct { library: Library, declarations: []const Declaration };

/// One declaration parsed from the compiler's `module interfaces v1` listing.
const Listed = struct {
    module: []const u8,
    name: []const u8,
    kind: []const u8,
    signature: []const u8,
    mutates: ?[]const []const u8,
    /// What the module's source says, or null when the scan did not find the declaration.
    source: ?reference_source.Found = null,
};

/// One module's declaration count and the parsed declarations of a listing.
const ListingFacts = struct { declarations: []const Declaration, modules: usize, exports: usize };

/// Curated discovery seeds for the checker's prelude builtin table.
/// `prelude_builtins.reserved` answers names, not a list, so each seed is
/// emitted only when that table accepts it; a seed the table rejects produces
/// no fact at all.
const prelude_seeds = [_][]const u8{
    "function_digest",
    "same_function",
    "sum",
    "min",
    "max",
    "sorted",
    "abs",
    "round",
    "any",
    "all",
    "reversed",
    "list",
    "zip",
};
/// The compile-time file embedding builtins (`EMBED-1`), each answered by `embed.kindOf`.
const embed_seeds = [_][]const u8{ "embed_bytes", "embed_str" };
/// Curated discovery seeds for the checker's float intrinsic table.
const float_seeds = [_][]const u8{ "sqrt", "floor", "ceil", "trunc", "abs" };
/// Curated discovery seeds for the checker's builtin type arity table.
const type_seeds = [_][]const u8{ "list", "Option", "Cell", "dict", "Result" };
/// Curated discovery seeds for the checker's capability type table.
const capability_seeds = [_][]const u8{
    "Filesystem", "Network", "Clock", "Entropy", "Environment", "Host", "Process", "Input", "Stop", "Registers", "Stream", "File",
    "TextFile",
};

/// The module-qualified declaration spelling `module::symbol`, the identity the
/// interface listing and `selka list-interfaces` publish. `src/interfaces.zig`
/// owns the same format string, but it is private to that module and that file
/// is outside this package, so this name records where the copy came from.
const reference_module_name_format = "{s}::{s}";
/// The contract kind of a callable declaration in that listing. Private to
/// `src/incremental.zig` there, so this copy is named for its owner too.
const reference_function_kind = "function";

/// Source attribution recorded on every builtin and method fact.
const io_builtin_source = "io_builtins.Builtin";
const prelude_builtin_source = "prelude_builtins.reserved";
const float_builtin_source = "float_intrinsics.operation";
const embed_builtin_source = "embed.kindOf";
const prelude_type_source = "prelude.arity";
const capability_type_source = "prelude.reservedType";
const method_source = "buffer_operations.methodArities";

/// Match `term` inside `haystack`, ignoring ASCII case.
fn containsIgnoreCase(haystack: []const u8, term: []const u8) bool {
    if (term.len == 0) return true;
    if (term.len > haystack.len) return false;
    var start: usize = 0;
    while (start + term.len <= haystack.len) : (start += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[start .. start + term.len], term)) return true;
    }
    return false;
}

/// A `std.mem.sort` comparator over one fact type's key.
fn lessByKey(comptime T: type) fn (void, T, T) bool {
    return struct {
        fn less(_: void, left: T, right: T) bool {
            return std.mem.lessThan(u8, left.key(), right.key());
        }
    }.less;
}

/// Whether a selected list contains a fact whose key equals the query.
fn anyExactKey(comptime T: type, items: []const T, query: []const u8) bool {
    for (items) |item| if (std.ascii.eqlIgnoreCase(item.key(), query)) return true;
    return false;
}

/// Keep the facts matching the query, sorted by key.
fn select(comptime T: type, arena: std.mem.Allocator, items: []const T, query: []const u8) Error![]const T {
    var kept: std.ArrayList(T) = .empty;
    for (items) |item| if (item.matchesQuery(query)) try kept.append(arena, item);
    std.mem.sort(T, kept.items, {}, lessByKey(T));
    return kept.toOwnedSlice(arena);
}

/// One string field of a JSON object, or null when absent or not a string.
fn stringField(value: std.json.Value, name: []const u8) ?[]const u8 {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return null,
        else => return null,
    };
    return switch (field) {
        .string => |text| text,
        else => null,
    };
}

/// Whether one interface symbol's source declaration is generic, which decides
/// whether only a `name[...]` specialization can establish checked status.
/// The parsed function type is never named: it is read through the interface
/// unit's own syntax.
fn declaredGeneric(
    comptime language: type,
    index: *language.interfaces.Index,
    module_name: []const u8,
    symbol_name: []const u8,
) bool {
    const module = index.project.names.get(module_name) orelse return false;
    for (index.units[module].symbols.items) |symbol| {
        if (!std.mem.eql(u8, symbol.name, symbol_name)) continue;
        for (index.units[module].syntax.functions) |function| {
            if (function.name.start != symbol.span.start or function.name.end != symbol.span.end) continue;
            return function.signature.type_parameters.len != 0;
        }
        return false;
    }
    return false;
}

/// Parse a `name,name` clause such as `mutates(a,b)` or `ceiling(a,b)` out of a
/// listing line, or null when the clause is absent.
fn namesClause(arena: std.mem.Allocator, line: []const u8, keyword: []const u8) Error!?[]const []const u8 {
    const at = std.mem.indexOf(u8, line, keyword) orelse return null;
    const after = line[at + keyword.len ..];
    const close = std.mem.indexOfScalar(u8, after, ')') orelse return null;
    var names: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, after[0..close], ',');
    while (parts.next()) |part| {
        // `ceiling()` with no names is an empty declared set, not one empty name.
        if (part.len == 0) continue;
        try names.append(arena, try arena.dupe(u8, part));
    }
    const names_slice = try names.toOwnedSlice(arena);
    return names_slice;
}

/// Parse one canonical function listing using its analysis clause as a delimiter.
fn parseFunctionLine(arena: std.mem.Allocator, module: []const u8, line: []const u8) Error!?Listed {
    // A `builtin func` of the standard library is listed `export builtin function` (W10).
    const prefix = "  export function ";
    const supplied_prefix = "  export builtin function ";
    const rest = if (std.mem.startsWith(u8, line, prefix)) line[prefix.len..] else if (std.mem.startsWith(u8, line, supplied_prefix)) line[supplied_prefix.len..] else return null;
    const analysis_at = std.mem.lastIndexOf(u8, rest, " analysis(") orelse return null;
    const head = rest[0..analysis_at];
    const split = std.mem.indexOfScalar(u8, head, ' ') orelse return null;
    const signature = head[split + 1 ..];
    if (!std.mem.startsWith(u8, signature, "func(")) return null;
    var clauses = rest[analysis_at..];
    if (std.mem.indexOf(u8, clauses, " # ")) |doc| clauses = clauses[0..doc];
    return .{
        .module = module,
        .name = try arena.dupe(u8, head[0..split]),
        .kind = reference_function_kind,
        .signature = try arena.dupe(u8, signature),
        .mutates = try namesClause(arena, clauses, " mutates("),
    };
}

/// Parse one `export type NAME` or `export constraint NAME` line.
fn parseNominalLine(arena: std.mem.Allocator, module: []const u8, line: []const u8) Error!?Listed {
    const rest = line["  export ".len..];
    const split = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
    const kind = rest[0..split];
    if (std.mem.eql(u8, kind, reference_function_kind)) return null;
    const tail = rest[split + 1 ..];
    const end = std.mem.indexOfAny(u8, tail, " #") orelse tail.len;
    return .{
        .module = module,
        .name = try arena.dupe(u8, tail[0..end]),
        .kind = try arena.dupe(u8, kind),
        .signature = "",
        .mutates = null,
    };
}

/// Parse the whole `module interfaces v1` listing into declarations, counting
/// the modules that publish at least one.
fn gatherDeclarations(
    comptime language: type,
    arena: std.mem.Allocator,
    index: *language.interfaces.Index,
    listing: []const u8,
    checked: bool,
) Error!ListingFacts {
    var declarations: std.ArrayList(Declaration) = .empty;
    var module: []const u8 = "";
    var entries: []const reference_source.Entry = &.{};
    var counted_module: []const u8 = "";
    var modules: usize = 0;
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "module ")) {
            const candidate = line["module ".len..];
            if (std.mem.indexOfScalar(u8, candidate, ' ') == null) {
                module = candidate;
                entries = try scanModule(language, arena, module);
            }
            continue;
        }
        if (!std.mem.startsWith(u8, line, "  export ")) continue;
        var listed = try parseFunctionLine(arena, module, line) orelse
            try parseNominalLine(arena, module, line) orelse continue;
        listed.source = reference_source.lookup(entries, listed.name);
        if (!std.mem.eql(u8, counted_module, module)) {
            counted_module = module;
            modules += 1;
        }
        try declarations.append(arena, try declarationFact(language, arena, index, listed, checked));
    }
    const exports = declarations.items.len;
    return .{ .declarations = try declarations.toOwnedSlice(arena), .modules = modules, .exports = exports };
}

/// The call forms and descriptions of one standard module, read from the embedded source the listing was built from.
fn scanModule(comptime language: type, arena: std.mem.Allocator, module: []const u8) Error![]const reference_source.Entry {
    const path = try std.fmt.allocPrint(arena, "{s}.selka", .{module});
    const text = language.standard_library.source(path) orelse return &.{};
    return reference_source.scan(arena, module, text);
}

/// What a declaration the scan did not find answers: its listing signature under the qualified name, with no description,
/// after every declaration the source ordered.
fn fallbackSource(arena: std.mem.Allocator, listed: Listed) Error!reference_source.Found {
    const call = if (std.mem.startsWith(u8, listed.signature, "func("))
        try std.fmt.allocPrint(arena, "{s}.{s}{s}", .{ listed.module, listed.name, listed.signature["func".len..] })
    else
        try std.fmt.allocPrint(arena, "{s} {s}.{s}", .{ listed.kind, listed.module, listed.name });
    return .{ .call = call, .summary = "", .line = std.math.maxInt(usize) };
}

/// The text, or null when it is empty: an absent description is `null` in JSON, never an empty string.
fn optionalText(text: []const u8) ?[]const u8 {
    return if (text.len == 0) null else text;
}

/// Turn one parsed listing line into a fact, computing the derivation status
/// from the checked program while retaining declared mutation permissions.
fn declarationFact(
    comptime language: type,
    arena: std.mem.Allocator,
    index: *language.interfaces.Index,
    listed: Listed,
    checked: bool,
) Error!Declaration {
    var fact: Declaration = .{
        .name = try std.fmt.allocPrint(arena, reference_module_name_format, .{ listed.module, listed.name }),
        .kind = listed.kind,
        .signature = listed.signature,
        .analysis = .declared,
        .mutates = listed.mutates,
        .source = listed.source orelse try fallbackSource(arena, listed),
    };
    if (!std.mem.eql(u8, listed.kind, reference_function_kind)) return fact;
    fact.analysis = .declaration_only;
    if (!checked) return fact;
    const generic = declaredGeneric(language, index, listed.module, listed.name);
    if (!hasConcreteFunction(language, index, listed.module, listed.name, generic)) {
        fact.analysis = .template;
        return fact;
    }
    fact.analysis = .checked;
    return fact;
}

/// Whether a positioned program-function name is the form this declaration
/// publishes: its own name for an ordinary function, a `name[...]`
/// specialization for a generic one.
fn shapeMatches(suffix: []const u8, generic: bool) bool {
    if (suffix.len == 0) return !generic;
    return suffix[0] == '[';
}

/// Whether the checked program holds a concrete instantiation of a declaration.
/// A generic declaration's symbolic entry is not a checked specialization, so
/// only a `name[...]` function establishes that status.
fn hasConcreteFunction(
    comptime language: type,
    index: *language.interfaces.Index,
    module_name: []const u8,
    symbol_name: []const u8,
    generic: bool,
) bool {
    const program = index.program orelse return false;
    var buffer: [512]u8 = undefined;
    const qualified = std.fmt.bufPrint(&buffer, reference_module_name_format, .{ module_name, symbol_name }) catch return false;
    for (program.functions) |function| {
        if (!std.mem.startsWith(u8, function.name, qualified)) continue;
        if (!shapeMatches(function.name[qualified.len..], generic)) continue;
        return true;
    }
    return false;
}

/// The synthesized entry source: every embedded standard module, plus a `main`
/// so the checker attaches checked bodies. Without an entry point the checker
/// leaves the program unset and every effect falls back to the conservative
/// full mask.
fn entrySource(comptime language: type, arena: std.mem.Allocator) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;

    for (language.standard_library.paths) |path| {
        try out.appendSlice(arena, "import ");
        try out.appendSlice(arena, product.chopSource(path));
        try out.append(arena, '\n');
    }
    try out.appendSlice(arena, "\nfunc main() -> int:\n    return 0\n");
    return out.toOwnedSlice(arena);
}

/// The most specific explanation available for a failed analysis: the
/// project's own diagnostic code when it recorded one, else the error name.
/// The code is copied into `arena` before the project's own arena is released.
fn failureReason(
    comptime language: type,
    arena: std.mem.Allocator,
    problem: ?language.project.Problem,
    fallback: []const u8,
) Error![]const u8 {
    return arena.dupe(u8, if (problem) |known| known.code else fallback);
}

/// An answer that reports no standard-library facts and says why.
fn unavailable(arena: std.mem.Allocator, why: []const u8) Error!LibraryFacts {
    return .{
        .library = .{ .status = .unavailable, .reason = try arena.dupe(u8, why), .modules = 0, .exports = 0 },
        .declarations = &.{},
    };
}

/// Load the embedded standard modules, check them when asked, and collect
/// every exported declaration. The project and its arena live only inside this
/// call; every returned string is copied into `arena`.
fn gatherLibrary(comptime language: type, arena: std.mem.Allocator, check_bodies: bool) Error!LibraryFacts {
    const entry = try entrySource(language, arena);
    var project = language.project.Project.init(arena);
    defer project.deinit();
    var provider: EntryReader(language) = .{ .entry = entry };
    project.load(provider.provider(), entry_module, .{ .max_modules = language.standard_library.count + 1 }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return unavailable(arena, try failureReason(language, arena, project.problem, @errorName(err))),
    };
    var index = language.interfaces.build(&project) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return unavailable(arena, try failureReason(language, arena, project.problem, @errorName(err))),
    };
    var body_failure: ?[]const u8 = null;
    if (check_bodies) {
        const Compilation = language.project_compile.Compilation;
        const attached_or_null: ?Compilation = Compilation.init(&index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
        if (attached_or_null) |compilation_value| {
            var attached = compilation_value;
            // Body checking records its own problem on the project; the
            // interface listing owns declaration diagnostics only, so the
            // pre-check problem is restored exactly as `list-interfaces` does.
            const saved = project.problem;
            // UNTESTED-ERROR: this branch runs only when the executable's own embedded standard
            // modules fail their body check, which no test can cause from outside; the failure is
            // reported as the answer's non-checked reason instead of an error.
            attached.check() catch |err| {
                body_failure = @errorName(err);
            };
            project.problem = saved;
            index.program = attached.program;
        }
    }
    const checked = index.program != null;
    // This embedded-only inspection intentionally uses the pure reference
    // renderer: reference answers depend solely on embedded bytes and remain
    // available offline without a component package or user-project traversal.
    const listing = language.interfaces.Index.render(&index, arena) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return unavailable(arena, try failureReason(language, arena, project.problem, @errorName(err))),
    };
    const listed = try gatherDeclarations(language, arena, &index, listing, checked);
    return .{
        .library = .{
            .status = if (checked) .checked else .declaration_only,
            .reason = if (checked) null else body_failure orelse "bodies not checked",
            .modules = listed.modules,
            .exports = listed.exports,
        },
        .declarations = listed.declarations,
    };
}

/// Every implemented feature recorded by the embedded manifest.
fn gatherFeatures(arena: std.mem.Allocator, manifest: std.json.Value, query: []const u8) Error![]const Feature {
    var all: std.ArrayList(Feature) = .empty;
    const implemented = switch (manifest) {
        .object => |object| object.get("implemented") orelse return select(Feature, arena, all.items, query),
        else => return select(Feature, arena, all.items, query),
    };
    const entries = switch (implemented) {
        .object => |object| object,
        else => return select(Feature, arena, all.items, query),
    };
    var iterator = entries.iterator();
    while (iterator.next()) |entry| {
        // The documentation gate guarantees kind, summary and doc for every
        // implemented slug, so a record missing one is skipped rather than
        // published with an invented empty fact.
        const kind = stringField(entry.value_ptr.*, "kind") orelse continue;
        const summary = stringField(entry.value_ptr.*, "summary") orelse continue;
        const doc = stringField(entry.value_ptr.*, "doc") orelse continue;
        try all.append(arena, .{
            .slug = try arena.dupe(u8, entry.key_ptr.*),
            .kind = try arena.dupe(u8, kind),
            .summary = try arena.dupe(u8, summary),
            .doc = try arena.dupe(u8, doc),
        });
    }
    return select(Feature, arena, all.items, query);
}

/// Every supported boundary recorded by the embedded manifest.
fn gatherLimits(arena: std.mem.Allocator, manifest: std.json.Value, query: []const u8) Error![]const Limit {
    var all: std.ArrayList(Limit) = .empty;
    const limits = switch (manifest) {
        .object => |object| object.get("limits") orelse return select(Limit, arena, all.items, query),
        else => return select(Limit, arena, all.items, query),
    };
    const entries = switch (limits) {
        .object => |object| object,
        else => return select(Limit, arena, all.items, query),
    };
    var iterator = entries.iterator();
    while (iterator.next()) |entry| {
        const boundary = switch (entry.value_ptr.*) {
            .string => |text| text,
            else => continue,
        };
        try all.append(arena, .{ .name = try arena.dupe(u8, entry.key_ptr.*), .boundary = try arena.dupe(u8, boundary) });
    }
    return select(Limit, arena, all.items, query);
}

/// Every unsupported, native-excluded and removed name.
fn gatherExclusions(arena: std.mem.Allocator, manifest: std.json.Value, query: []const u8) Error![]const Exclusion {
    var all: std.ArrayList(Exclusion) = .empty;
    const categories = [_]struct { field: []const u8, status: ExclusionStatus }{
        .{ .field = "unsupported", .status = .unsupported },
        .{ .field = "native_exclusions", .status = .native_exclusion },
    };
    for (categories) |category| {
        const listed = switch (manifest) {
            .object => |object| object.get(category.field) orelse continue,
            else => continue,
        };
        const items = switch (listed) {
            .array => |array| array.items,
            else => continue,
        };
        for (items) |item| {
            const slug = switch (item) {
                .string => |text| text,
                else => continue,
            };
            try all.append(arena, .{
                .slug = try arena.dupe(u8, slug),
                .status = category.status,
                .detail = null,
                .date = null,
            });
        }
    }
    const removed = switch (manifest) {
        .object => |object| object.get("removed") orelse return select(Exclusion, arena, all.items, query),
        else => return select(Exclusion, arena, all.items, query),
    };
    const entries = switch (removed) {
        .object => |object| object,
        else => return select(Exclusion, arena, all.items, query),
    };
    var iterator = entries.iterator();
    while (iterator.next()) |entry| {
        const note = stringField(entry.value_ptr.*, "note") orelse continue;
        const date = stringField(entry.value_ptr.*, "date");
        try all.append(arena, .{
            .slug = try arena.dupe(u8, entry.key_ptr.*),
            .status = .removed,
            .detail = try arena.dupe(u8, note),
            .date = if (date) |text| try arena.dupe(u8, text) else null,
        });
    }
    return select(Exclusion, arena, all.items, query);
}

/// Every curated syntax entry matching the query.
fn gatherSyntax(arena: std.mem.Allocator, query: []const u8) Error![]const Syntax {
    var all: std.ArrayList(Syntax) = .empty;
    for (reference_text.entries) |entry| {
        try all.append(arena, .{
            .id = entry.id,
            .title = entry.title,
            .summary = entry.summary,
            .python = entry.python,
            .example = entry.example,
        });
    }
    return select(Syntax, arena, all.items, query);
}

/// Keep one record per builtin name, preferring a record whose table carries
/// an argument count.
fn dedupeBuiltins(arena: std.mem.Allocator, items: []const Builtin) Error![]const Builtin {
    var kept: std.ArrayList(Builtin) = .empty;
    for (items) |item| {
        var duplicate = false;
        for (kept.items, 0..) |existing, index| {
            if (!std.mem.eql(u8, existing.name, item.name)) continue;
            duplicate = true;
            if (existing.arity == null and item.arity != null) kept.items[index] = item;
            break;
        }
        if (!duplicate) try kept.append(arena, item);
    }
    return kept.toOwnedSlice(arena);
}

/// Every builtin spelling the checker's own tables answer.
fn gatherBuiltins(comptime language: type, arena: std.mem.Allocator, query: []const u8) Error![]const Builtin {
    var all: std.ArrayList(Builtin) = .empty;
    inline for (std.meta.tags(language.reference_tables.io_builtins.Builtin)) |tag| {
        try all.append(arena, .{ .name = @tagName(tag), .kind = .function, .arity = tag.arity(), .source = io_builtin_source });
    }
    for (prelude_seeds) |name| {
        if (!language.reference_tables.prelude_builtins.reserved(name)) continue;
        try all.append(arena, .{ .name = name, .kind = .function, .arity = null, .source = prelude_builtin_source });
    }
    for (embed_seeds) |name| {
        if (language.reference_tables.embed.kindOf(name) == null) continue;
        try all.append(arena, .{ .name = name, .kind = .function, .arity = 1, .source = embed_builtin_source });
    }
    for (float_seeds) |name| {
        if (language.reference_tables.float_intrinsics.operation(name) == null) continue;
        try all.append(arena, .{ .name = name, .kind = .function, .arity = 1, .source = float_builtin_source });
    }
    for (type_seeds) |name| {
        const arity = language.reference_tables.prelude.arity(name) orelse continue;
        try all.append(arena, .{ .name = name, .kind = .type, .arity = arity, .source = prelude_type_source });
    }
    for (capability_seeds) |name| {
        if (language.reference_tables.prelude.reservedType(name) == null) continue;
        try all.append(arena, .{ .name = name, .kind = .type, .arity = null, .source = capability_type_source });
    }
    return select(Builtin, arena, try dedupeBuiltins(arena, all.items), query);
}

/// The managed collections that accept one method spelling.
fn methodFamilies(comptime language: type, arena: std.mem.Allocator, name: []const u8) Error![]const u8 {
    const tables = language.reference_tables;
    var out: std.ArrayList(u8) = .empty;
    inline for (std.meta.tags(tables.runtime_values.ManagedKind)) |family| {
        const selected = try tables.buffer_operations.checkedMethodSpellings(arena, family);
        var found = false;
        for (selected) |spelling| {
            if (std.mem.eql(u8, spelling, name)) found = true;
        }
        if (found) {
            if (out.items.len != 0) try out.append(arena, ',');
            try out.appendSlice(arena, @tagName(family));
        }
    }
    return out.toOwnedSlice(arena);
}

/// The argument counts one method spelling accepts, read from the checker's
/// own operation table: every operation whose source spelling is `name`
/// contributes its own arity, so `split` answers its two forms and the `pop`
/// spelling answers each of its arity variants.
fn methodArities(comptime language: type, arena: std.mem.Allocator, name: []const u8) Error![]const usize {
    const operations = language.reference_tables.buffer_operations;
    var list: std.ArrayList(usize) = .empty;
    inline for (std.meta.tags(operations.Kind)) |kind| {
        if (operations.spelling(kind)) |spelled| {
            if (std.mem.eql(u8, spelled, name)) {
                const arity = kind.arity();
                var duplicate = false;
                for (list.items) |existing| {
                    if (existing == arity) duplicate = true;
                }
                if (!duplicate) try list.append(arena, arity);
            }
        }
    }
    std.mem.sort(usize, list.items, {}, std.sort.asc(usize));
    return list.toOwnedSlice(arena);
}

/// Every accepted collection-method spelling and its argument counts.
fn gatherMethods(comptime language: type, arena: std.mem.Allocator, query: []const u8) Error![]const Method {
    const tables = language.reference_tables;
    const spellings = try tables.buffer_operations.unionMethodSpellings(arena);
    var all: std.ArrayList(Method) = .empty;
    for (spellings) |name| {
        try all.append(arena, .{
            .name = try arena.dupe(u8, name),
            .arities = try methodArities(language, arena, name),
            .families = try methodFamilies(language, arena, name),
            .source = method_source,
        });
    }
    return select(Method, arena, all.items, query);
}

/// Every diagnostic code whose spelling contains the query.
fn gatherCodes(arena: std.mem.Allocator, query: []const u8) Error![]const Code {
    var all: std.ArrayList(Code) = .empty;
    for (diagnostic_codes.entries) |entry| try all.append(arena, .{ .code = entry.code, .meaning = entry.meaning, .guide = entry.guide, .rules = entry.rules });
    return select(Code, arena, all.items, query);
}

/// A standard module's name as the table spells it, for `text` in any case, or null.
fn standardModule(comptime language: type, text: []const u8) ?[]const u8 {
    for (language.standard_library.paths) |path| {
        const stem = product.chopSource(path);
        if (std.ascii.eqlIgnoreCase(stem, text)) return stem;
    }
    return null;
}

/// A query of the form `module.name` where `module` is a standard module.
const Qualified = struct { module: []const u8, name: []const u8 };

/// Read `strings.split` as a module and a name, or null for any other query.
fn splitQualified(comptime language: type, query: []const u8) ?Qualified {
    const dot = std.mem.indexOfScalar(u8, query, '.') orelse return null;
    const name = query[dot + 1 ..];
    if (name.len == 0) return null;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return null;
    const module = standardModule(language, query[0..dot]) orelse return null;
    return .{ .module = module, .name = name };
}

/// The term the facts are searched with: `strings.split` is the listing's `strings::split`, and any other query is itself.
fn searchTerm(comptime language: type, arena: std.mem.Allocator, query: []const u8) Error![]const u8 {
    const qualified = splitQualified(language, query) orelse return query;
    return std.fmt.allocPrint(arena, reference_module_name_format, .{ qualified.module, qualified.name });
}

/// One declaration as a lookup line: `module::name` becomes `module.name`.
fn lineOf(arena: std.mem.Allocator, declaration: Declaration) Error!Line {
    const at = std.mem.indexOf(u8, declaration.name, "::") orelse declaration.name.len;
    const symbol = if (at == declaration.name.len) "" else declaration.name[at + 2 ..];
    return .{
        .name = try std.fmt.allocPrint(arena, "{s}.{s}", .{ declaration.name[0..at], symbol }),
        .call = declaration.source.call,
        .summary = optionalText(declaration.source.summary),
    };
}

/// The module part of a `module::name` declaration.
fn moduleOf(declaration: Declaration) []const u8 {
    return declaration.name[0 .. std.mem.indexOf(u8, declaration.name, "::") orelse declaration.name.len];
}

/// The symbol part of a `module::name` declaration.
fn symbolOf(declaration: Declaration) []const u8 {
    const at = std.mem.indexOf(u8, declaration.name, "::") orelse return declaration.name;
    return declaration.name[at + 2 ..];
}

/// Order declarations as the module's source does.
fn bySourceLine(_: void, left: Declaration, right: Declaration) bool {
    return left.source.line < right.source.line;
}

/// Every declaration of one module, in source order.
fn moduleDeclarations(arena: std.mem.Allocator, declarations: []const Declaration, module: []const u8) Error![]Declaration {
    var kept: std.ArrayList(Declaration) = .empty;
    for (declarations) |declaration| {
        if (std.ascii.eqlIgnoreCase(moduleOf(declaration), module)) try kept.append(arena, declaration);
    }
    std.mem.sort(Declaration, kept.items, {}, bySourceLine);
    return kept.toOwnedSlice(arena);
}

/// The lines of a declaration list.
fn linesOf(arena: std.mem.Allocator, declarations: []const Declaration) Error![]const Line {
    const lines = try arena.alloc(Line, declarations.len);
    for (declarations, lines) |declaration, *line| line.* = try lineOf(arena, declaration);
    return lines;
}

/// A name without its case or underscores, so `isdigit` and `is_digit` are the same name.
fn plainName(buffer: *[64]u8, name: []const u8) []const u8 {
    return typed.plainName(buffer, name, .{ .lower = true, .truncate = true }).?;
}

/// The number of single-character edits that turn `left` into `right`.
fn editDistance(left: []const u8, right: []const u8) usize {
    var row: [65]usize = undefined;
    for (0..right.len + 1) |column| row[column] = column;
    for (left, 0..) |from, index| {
        var diagonal = row[0];
        row[0] = index + 1;
        for (right, 0..) |to, column| {
            const above = row[column + 1];
            row[column + 1] = @min(@min(row[column] + 1, above + 1), diagonal + @intFromBool(from != to));
            diagonal = above;
        }
    }
    return row[right.len];
}

/// One declared name beside how far it is from the name asked for.
const Candidate = struct { declaration: Declaration, distance: usize };

/// Nearest first, then the module's own order.
fn byDistance(_: void, left: Candidate, right: Candidate) bool {
    if (left.distance != right.distance) return left.distance < right.distance;
    return left.declaration.source.line < right.declaration.source.line;
}

/// The most candidates a missing name is answered with.
const nearest_limit = 3;

/// The declared names of a module nearest to `name`: a name a few edits away once case and underscores are ignored, or one
/// that contains or is contained by it (`splitlines` is near `lines`), at most `nearest_limit` of them.
fn nearestDeclarations(arena: std.mem.Allocator, module_declarations: []const Declaration, name: []const u8) Error![]const Declaration {
    var asked_buffer: [64]u8 = undefined;
    const asked = plainName(&asked_buffer, name);
    const reach = @max(2, asked.len / 3);
    var near: std.ArrayList(Candidate) = .empty;
    for (module_declarations) |declaration| {
        var declared_buffer: [64]u8 = undefined;
        const declared = plainName(&declared_buffer, symbolOf(declaration));
        const distance = editDistance(asked, declared);
        const shorter = @min(asked.len, declared.len);
        const contained = shorter >= 3 and (std.mem.indexOf(u8, asked, declared) != null or std.mem.indexOf(u8, declared, asked) != null);
        if (distance <= reach or contained) try near.append(arena, .{ .declaration = declaration, .distance = distance });
    }
    std.mem.sort(Candidate, near.items, {}, byDistance);
    const count = @min(near.items.len, nearest_limit);
    const kept = try arena.alloc(Declaration, count);
    for (near.items[0..count], kept) |candidate, *slot| slot.* = candidate.declaration;
    return kept;
}

/// The short answers a query earns: the call of a prelude name, of a module-qualified name or the declarations of a module;
/// for a qualified name no module declares, the names nearest to it.
fn gatherLookups(comptime language: type, arena: std.mem.Allocator, library: LibraryFacts, query: []const u8) Error![]const Lookup {
    var found: std.ArrayList(Lookup) = .empty;
    for (reference_text.prelude) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, query)) try found.append(arena, .{ .prelude = entry });
    }
    if (library.library.status == .unavailable) return found.toOwnedSlice(arena);
    if (splitQualified(language, query)) |qualified| {
        const declared = try moduleDeclarations(arena, library.declarations, qualified.module);
        const guide = reference_text.moduleGuide(qualified.module);
        for (declared) |declaration| {
            if (!std.ascii.eqlIgnoreCase(symbolOf(declaration), qualified.name)) continue;
            const lines = try linesOf(arena, &.{declaration});
            try found.append(arena, .{ .declaration = .{ .name = lines[0].name, .module = qualified.module, .guide = guide, .lines = lines } });
            return found.toOwnedSlice(arena);
        }
        const near = try nearestDeclarations(arena, declared, qualified.name);
        try found.append(arena, .{ .nearest = .{ .name = query, .module = qualified.module, .guide = guide, .lines = try linesOf(arena, near) } });
    } else if (standardModule(language, query)) |module| {
        const declared = try moduleDeclarations(arena, library.declarations, module);
        const guide = reference_text.moduleGuide(module);
        try found.append(arena, .{ .module = .{ .name = module, .module = module, .guide = guide, .lines = try linesOf(arena, declared) } });
    }
    return found.toOwnedSlice(arena);
}

/// Assemble every fact category once and keep the matching subset.
fn gather(comptime language: type, arena: std.mem.Allocator, query: []const u8, check_bodies: bool) Error!Answer {
    const manifest = std.json.parseFromSlice(std.json.Value, arena, @embedFile("features.json"), .{}) catch return error.OutOfMemory;
    defer manifest.deinit();
    const library = try gatherLibrary(language, arena, check_bodies);
    const term = try searchTerm(language, arena, query);
    const facts: Facts = .{
        .syntax = try gatherSyntax(arena, term),
        .features = try gatherFeatures(arena, manifest.value, term),
        .limits = try gatherLimits(arena, manifest.value, term),
        .exclusions = try gatherExclusions(arena, manifest.value, term),
        .declarations = try select(Declaration, arena, library.declarations, term),
        .builtins = try gatherBuiltins(language, arena, term),
        .methods = try gatherMethods(language, arena, term),
        .codes = try gatherCodes(arena, term),
    };
    return .{
        .query = query,
        .lookups = try gatherLookups(language, arena, library, query),
        .match = matchKind(facts, term),
        .language = .{
            .version = stringField(manifest.value, "language_version") orelse "",
            .backend = stringField(manifest.value, "primary_backend") orelse "",
        },
        .library = library.library,
        .facts = facts,
    };
}

/// How many facts the answer carries across every category.
fn countFacts(facts: Facts) usize {
    return facts.syntax.len + facts.features.len + facts.limits.len + facts.exclusions.len +
        facts.declarations.len + facts.builtins.len + facts.methods.len + facts.codes.len;
}

/// Whether the query hit a whole key, part of one, or nothing at all.
fn matchKind(facts: Facts, query: []const u8) Match {
    if (countFacts(facts) == 0) return .none;
    if (anyExactKey(Syntax, facts.syntax, query)) return .exact;
    if (anyExactKey(Feature, facts.features, query)) return .exact;
    if (anyExactKey(Limit, facts.limits, query)) return .exact;
    if (anyExactKey(Exclusion, facts.exclusions, query)) return .exact;
    if (anyExactKey(Declaration, facts.declarations, query)) return .exact;
    if (anyExactKey(Builtin, facts.builtins, query)) return .exact;
    if (anyExactKey(Method, facts.methods, query)) return .exact;
    if (anyExactKey(Code, facts.codes, query)) return .exact;
    return .substring;
}

fn matchName(match: Match) []const u8 {
    return @tagName(match);
}
fn analysisName(analysis: Analysis) []const u8 {
    return switch (analysis) {
        .checked => "checked",
        .declaration_only => "declaration-only",
        .unavailable => "unavailable",
    };
}
fn derivationName(derivation: Derivation) []const u8 {
    return switch (derivation) {
        .checked => "checked",
        .declaration_only => "declaration-only",
        .template => "template",
        .declared => "declared",
    };
}
fn exclusionStatusName(status: ExclusionStatus) []const u8 {
    return switch (status) {
        .unsupported => "unsupported",
        .native_exclusion => "native-exclusion",
        .removed => "removed",
    };
}

/// Render the versioned JSON envelope.
fn renderJson(allocator: std.mem.Allocator, answer: Answer) Error![]u8 {
    // An unavailable analysis has no declaration set at all, which is a
    // different fact from a set that matched nothing: null, not [].
    const declarations: ?[]const Declaration = if (answer.library.status == .unavailable) null else answer.facts.declarations;
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = envelope_version,
        .query = answer.query,
        .match = matchName(answer.match),
        .count = countFacts(answer.facts),
        .language = .{ .version = answer.language.version, .primary_backend = answer.language.backend },
        .library = .{
            .status = analysisName(answer.library.status),
            .reason = answer.library.reason,
            .modules = answer.library.modules,
            .exports = answer.library.exports,
        },
        .syntax = answer.facts.syntax,
        .features = answer.facts.features,
        .limits = answer.facts.limits,
        .exclusions = answer.facts.exclusions,
        .declarations = declarations,
        .builtins = answer.facts.builtins,
        .methods = answer.facts.methods,
        .diagnostics = answer.facts.codes,
        .answers = answer.lookups,
    }, .{ .whitespace = .indent_2 }) catch return error.OutOfMemory;
}

fn writeNames(writer: *std.Io.Writer, names: []const []const u8) !void {
    if (names.len == 0) return writer.writeAll("(none)");
    for (names, 0..) |name, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(name);
    }
}

fn renderLibrary(writer: *std.Io.Writer, library: Library) !void {
    try writer.print("standard library: {s}", .{analysisName(library.status)});
    switch (library.status) {
        .unavailable => {},
        else => try writer.print(" ({d} modules, {d} exported declarations)", .{ library.modules, library.exports }),
    }
    if (library.reason) |why| try writer.print(" — {s}", .{why});
    try writer.writeByte('\n');
}

fn renderExample(writer: *std.Io.Writer, example: []const u8) !void {
    var lines = std.mem.splitScalar(u8, example, '\n');
    while (lines.next()) |line| {
        try writer.writeAll("    ");
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }
}

fn renderDeclaration(writer: *std.Io.Writer, declaration: Declaration) !void {
    try writer.print("\ndeclaration {s}\n  kind: {s}\n  signature: {s}\n  analysis: {s}\n", .{
        declaration.name,
        declaration.kind,
        declaration.signature,
        derivationName(declaration.analysis),
    });
    try writer.writeAll("  mutates: ");
    if (declaration.mutates) |mutates| try writeNames(writer, mutates) else try writer.writeAll("none declared");
    try writer.writeByte('\n');
}

/// Render the human- and agent-readable text answer.
fn renderText(allocator: std.mem.Allocator, answer: Answer) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    // UNTESTED-ERROR: releases a partially written answer when an allocation fails mid-render;
    // the same allocator-failure path is covered at the `run` boundary, and the release itself
    // leaves nothing observable to assert.
    errdefer out.deinit();
    renderTextInto(&out.writer, answer) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

/// Print one lookup: the call, its description and its guide, or a module's calls, or the names nearest to a missing one.
fn renderLookup(writer: *std.Io.Writer, lookup: Lookup) !void {
    switch (lookup) {
        .prelude => |entry| try writer.print("{s}\n  {s}\n  guide: selka docs {s}\n", .{ entry.call, entry.summary, entry.guide }),
        .declaration => |listing| {
            try writer.print("{s}\n", .{listing.lines[0].call});
            if (listing.lines[0].summary) |summary| try writer.print("  {s}\n", .{summary});
            try writer.print("  guide: selka docs {s}\n", .{listing.guide});
        },
        .module => |listing| {
            try writer.print("module {s}: {d} declarations (guide: selka docs {s})\n", .{ listing.name, listing.lines.len, listing.guide });
            for (listing.lines) |line| try writer.print("  {s}\n", .{line.call});
        },
        .nearest => |listing| {
            try writer.print("no declaration {s} in module {s}", .{ listing.name, listing.module });
            if (listing.lines.len == 0) try writer.writeAll("\n") else try writer.writeAll("; nearest:\n");
            for (listing.lines) |line| try writer.print("  {s}\n", .{line.call});
            try writer.print("  all of {s}: selka reference --query {s} (guide: selka docs {s})\n", .{ listing.module, listing.module, listing.guide });
        },
    }
}

/// Print an answer that is a lookup: its header counts what the lookups show, and the substring search is left out.
fn renderLookups(writer: *std.Io.Writer, answer: Answer) !void {
    var shown: usize = 0;
    for (answer.lookups) |lookup| switch (lookup) {
        .prelude, .declaration => shown += 1,
        .module => |listing| shown += listing.lines.len,
        .nearest => {},
    };
    try writer.print("{s} query=\"{s}\" match={s} facts={d}\n", .{ envelope_version, answer.query, if (shown == 0) "none" else "exact", shown });
    try writer.print("language: {s} primary_backend={s}\n", .{ answer.language.version, answer.language.backend });
    try renderLibrary(writer, answer.library);
    for (answer.lookups) |lookup| {
        try writer.writeByte('\n');
        try renderLookup(writer, lookup);
    }
}

/// Names the guide a feature's documentation pointer (`docs/PAGE.md#section`) is part of, as `guide: selka docs TOPIC
/// (section #section)`. A page that no topic shows is not named at all: the pointer stays in the JSON record for tools,
/// but a text answer never sends a reader to a path `selka docs` cannot print.
fn writeFeatureGuide(writer: *std.Io.Writer, doc: []const u8) !void {
    const hash = std.mem.indexOfScalar(u8, doc, '#');
    const topic = user_docs.topicForPath(if (hash) |at| doc[0..at] else doc) orelse return;
    try writer.print("  guide: selka docs {s}", .{topic.name});
    if (hash) |at| try writer.print(" (section #{s})", .{doc[at + 1 ..]});
    try writer.writeByte('\n');
}

fn renderTextInto(writer: *std.Io.Writer, answer: Answer) !void {
    if (answer.lookups.len != 0) return renderLookups(writer, answer);
    try writer.print("{s} query=\"{s}\" match={s} facts={d}\n", .{
        envelope_version,
        answer.query,
        matchName(answer.match),
        countFacts(answer.facts),
    });
    try writer.print("language: {s} primary_backend={s}\n", .{ answer.language.version, answer.language.backend });
    try renderLibrary(writer, answer.library);
    if (countFacts(answer.facts) == 0) {
        try writer.print("\nno fact in this executable matches \"{s}\"\n", .{answer.query});
        return;
    }
    for (answer.facts.syntax) |entry| {
        try writer.print("\nsyntax {s}\n  title: {s}\n  summary: {s}\n  python: {s}\n  example:\n", .{
            entry.id,
            entry.title,
            entry.summary,
            if (entry.python.len == 0) "(no difference)" else entry.python,
        });
        try renderExample(writer, entry.example);
    }
    for (answer.facts.features) |feature| {
        try writer.print("\nfeature {s}\n  kind: {s}\n  summary: {s}\n", .{ feature.slug, feature.kind, feature.summary });
        try writeFeatureGuide(writer, feature.doc);
    }
    for (answer.facts.limits) |limit| {
        try writer.print("\nlimit {s}\n  boundary: {s}\n", .{ limit.name, limit.boundary });
    }
    for (answer.facts.exclusions) |exclusion| {
        try writer.print("\nexclusion {s}\n  status: {s}\n", .{ exclusion.slug, exclusionStatusName(exclusion.status) });
        if (exclusion.date) |date| try writer.print("  date: {s}\n", .{date});
        if (exclusion.detail) |detail| try writer.print("  detail: {s}\n", .{detail});
    }
    for (answer.facts.declarations) |declaration| try renderDeclaration(writer, declaration);
    for (answer.facts.builtins) |builtin| {
        try writer.print("\nbuiltin {s}\n  kind: {s}\n", .{ builtin.name, @tagName(builtin.kind) });
        if (builtin.arity) |arity| {
            try writer.print("  arity: {d}\n", .{arity});
        } else {
            try writer.writeAll("  arity: not recorded by this table\n");
        }
        try writer.print("  source: {s}\n", .{builtin.source});
    }
    for (answer.facts.methods) |method| {
        try writer.print("\nmethod {s}\n  arities: ", .{method.name});
        for (method.arities, 0..) |arity, index| {
            if (index != 0) try writer.writeByte(',');
            try writer.print("{d}", .{arity});
        }
        try writer.print("\n  families: {s}\n  source: {s}\n", .{ method.families, method.source });
        try writer.writeAll(method_form_note);
    }
    for (answer.facts.codes) |code| {
        try writer.print("\ndiagnostic {s}\n  meaning: {s}\n  guide: selka docs {s}\n", .{ code.code, code.meaning, code.guide });
        if (code.rules.len != 0) {
            // Each heading of the ownership reference that files a rule this code enforces, with the rules it files.
            var storage: ownership_rules.Grouped = .{};
            try writer.writeAll("  ownership rules: ");
            for (ownership_rules.grouped(code.rules, &storage), 0..) |group, index| {
                if (index != 0) try writer.writeAll("; ");
                try writer.print("{s} (", .{group.family});
                for (group.rules, 0..) |rule, position| {
                    if (position != 0) try writer.writeAll(", ");
                    try writer.writeAll(@tagName(rule));
                }
                try writer.writeByte(')');
            }
            try writer.writeByte('\n');
        }
    }
}

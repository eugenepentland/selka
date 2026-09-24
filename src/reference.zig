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
//! module imports the compiler as the `mylang` module, so a file it imports may
//! not also import the compiler's own files. The installed executable passes
//! `@import("mylang")`; the unit tests pass the same compiler root through
//! their test module.

const std = @import("std");
const reference_text = @import("reference_text.zig");

/// Wire version of the JSON envelope this engine emits.
pub const envelope_version = "reference-v1";

/// Rendering the caller asked for.
pub const Format = enum { text, json };

/// Requests the engine rejects, and allocation failure.
pub const Error = error{ OutOfMemory, EmptyQuery };

/// One reference request: the term to match and how to render the answer.
pub const Request = struct {
    /// Term matched case-insensitively as a substring of every fact's slug,
    /// name, summary, signature, receiver families or source table. An empty
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
pub const entry_path = "reference.my";

/// Embedded standard module paths, in manifest order.
///
/// `src/standard_library.zig` exposes only `source(path)`, so the path list is
/// repeated here; `reference_test.zig` asserts this list equals the checkout's
/// `src/stdlib/*.my` set, which turns a fifteenth standard module into a
/// failing test rather than a silent omission.
pub const standard_modules = [_][]const u8{
    "base64.my", "byte_builder.my", "environment.my", "filesystem.my", "hex.my",
    "json.my",   "math.my",         "network.my",     "path.my",       "pool.my",
    "random.my", "sort.my",         "strings.my",     "time.my",
};

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

        /// Serve `reference.my`; return NotFound for every other path.
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
    /// Bodies were checked, so an inferred effect set is a fact.
    checked,
    /// Only declarations were parsed; no inferred effect is available.
    declaration_only,
    /// The embedded modules could not be analyzed at all.
    unavailable,
};

/// Where one declaration's published facts come from.
const Derivation = enum {
    /// Bodies were checked and this declaration has a checked instantiation.
    checked,
    /// Bodies were not checked, so no inferred effect set exists.
    declaration_only,
    /// Bodies were checked, but this generic declaration was never
    /// instantiated here; the checker's conservative full mask is not
    /// published as if it were an inferred fact.
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
        });
    }
};

/// One exported standard-library declaration with its derivation status.
const Declaration = struct {
    /// Module-qualified name, `module::symbol`, the identity
    /// `mylang list-interfaces` publishes.
    name: []const u8,
    /// Contract kind: `function`, `record`, `enum`, `union`, `result`,
    /// `resource`, `domain` or `constraint`.
    kind: []const u8,
    /// The callable signature for functions, or the declared shape for a type
    /// declaration.
    signature: []const u8,
    analysis: Derivation,
    /// Checked inferred effects, null when no checked instantiation exists.
    effects: ?[]const []const u8,
    /// The declared ceiling, null when the source wrote none.
    ceiling: ?[]const []const u8,
    /// Declared `mutates(...)` parameter names, null when the source wrote no
    /// clause.
    mutates: ?[]const []const u8,

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
            .effects = self.effects,
            .ceiling = self.ceiling,
            .mutates = self.mutates,
        });
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
};

/// Declarations plus the status of the analysis that produced them.
const LibraryFacts = struct { library: Library, declarations: []const Declaration };

/// One declaration parsed from the compiler's `module interfaces v1` listing.
const Listed = struct {
    module: []const u8,
    name: []const u8,
    kind: []const u8,
    signature: []const u8,
    ceiling: ?[]const []const u8,
    mutates: ?[]const []const u8,
};

/// One module's declaration count and the parsed declarations of a listing.
const ListingFacts = struct { declarations: []const Declaration, modules: usize, exports: usize };

/// Curated discovery seeds for the checker's prelude builtin table.
/// `prelude_builtins.reserved` answers names, not a list, so each seed is
/// emitted only when that table accepts it; a seed the table rejects produces
/// no fact at all.
const prelude_seeds = [_][]const u8{
    "sum", "min", "max", "sorted", "abs", "round", "any", "all", "reversed", "list", "zip",
};
/// Curated discovery seeds for the checker's float intrinsic table.
const float_seeds = [_][]const u8{ "sqrt", "floor", "ceil", "trunc", "abs" };
/// Curated discovery seeds for the checker's builtin type arity table.
const type_seeds = [_][]const u8{ "list", "Option", "Cell", "dict", "Result" };
/// Curated discovery seeds for the checker's capability type table.
const capability_seeds = [_][]const u8{
    "Filesystem", "Network", "Clock", "Entropy", "Environment", "Host", "Stream", "File", "TextFile",
};

/// The module-qualified declaration spelling `module::symbol`, the identity the
/// interface listing and `mylang list-interfaces` publish. `src/interfaces.zig`
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

/// Render an effect mask in the checker's own effect order.
fn effectNames(comptime language: type, arena: std.mem.Allocator, mask: language.effect_set.Mask) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    inline for (std.meta.tags(language.effect_set.Effect)) |effect| {
        if (mask & language.effect_set.bit(effect) != 0) try names.append(arena, @tagName(effect));
    }
    return names.toOwnedSlice(arena);
}

/// Whether one interface symbol's source declaration is generic, which decides
/// whether only a `name[...]` specialization can carry its inferred effects.
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

/// Parse one `export function NAME def(...)->TYPE clauses` line.
///
/// The grammar is the listing's, not the language's: the signature is every
/// byte between the declaration name and the function's own last ` effects(`,
/// which is what keeps a callback type's inner ` effects()` from ending it
/// early. The fixed clause order that follows is `effects(...)`,
/// `mutates(...)`, `ceiling(...)`, `tests(N)`, then an optional `# docstring`.
fn parseFunctionLine(arena: std.mem.Allocator, module: []const u8, line: []const u8) Error!?Listed {
    const prefix = "  export function ";
    const rest = line[prefix.len..];
    const effects_at = std.mem.lastIndexOf(u8, rest, " effects(") orelse return null;
    const head = rest[0..effects_at];
    const split = std.mem.indexOfScalar(u8, head, ' ') orelse return null;
    const signature = head[split + 1 ..];
    if (!std.mem.startsWith(u8, signature, "def(")) return null;
    var clauses = rest[effects_at..];
    if (std.mem.indexOf(u8, clauses, " # ")) |doc| clauses = clauses[0..doc];
    return .{
        .module = module,
        .name = try arena.dupe(u8, head[0..split]),
        .kind = reference_function_kind,
        .signature = try arena.dupe(u8, signature),
        .ceiling = try namesClause(arena, clauses, " ceiling("),
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
        .ceiling = null,
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
    var counted_module: []const u8 = "";
    var modules: usize = 0;
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "module ")) {
            const candidate = line["module ".len..];
            if (std.mem.indexOfScalar(u8, candidate, ' ') == null) module = candidate;
            continue;
        }
        if (!std.mem.startsWith(u8, line, "  export ")) continue;
        const listed = try parseFunctionLine(arena, module, line) orelse
            try parseNominalLine(arena, module, line) orelse continue;
        if (!std.mem.eql(u8, counted_module, module)) {
            counted_module = module;
            modules += 1;
        }
        try declarations.append(arena, try declarationFact(language, arena, index, listed, checked));
    }
    const exports = declarations.items.len;
    return .{ .declarations = try declarations.toOwnedSlice(arena), .modules = modules, .exports = exports };
}

/// Turn one parsed listing line into a fact, computing the derivation status
/// and the inferred effect set from the checked program.
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
        .effects = null,
        .ceiling = listed.ceiling,
        .mutates = listed.mutates,
    };
    if (!std.mem.eql(u8, listed.kind, reference_function_kind)) return fact;
    fact.analysis = .declaration_only;
    if (!checked) return fact;
    const generic = declaredGeneric(language, index, listed.module, listed.name);
    fact.effects = try effectNames(language, arena, inferredEffects(language, index, listed.module, listed.name, generic) orelse {
        fact.analysis = .template;
        return fact;
    });
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

/// The inferred effect mask of one checked declaration, or null when the
/// checked program holds no concrete instantiation of it. A generic
/// declaration's symbolic entry carries the checker's conservative full mask,
/// so only a specialization `name[...]` answers for it.
fn inferredEffects(
    comptime language: type,
    index: *language.interfaces.Index,
    module_name: []const u8,
    symbol_name: []const u8,
    generic: bool,
) ?language.effect_set.Mask {
    const program = index.program orelse return null;
    var buffer: [512]u8 = undefined;
    const qualified = std.fmt.bufPrint(&buffer, reference_module_name_format, .{ module_name, symbol_name }) catch return null;
    for (program.functions) |function| {
        if (!std.mem.startsWith(u8, function.name, qualified)) continue;
        if (!shapeMatches(function.name[qualified.len..], generic)) continue;
        return function.policy.effects;
    }
    return null;
}

/// The synthesized entry source: every embedded standard module, plus a `main`
/// so the checker attaches checked bodies. Without an entry point the checker
/// leaves the program unset and every effect falls back to the conservative
/// full mask.
fn entrySource(arena: std.mem.Allocator) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "module " ++ entry_module ++ "\n");
    for (standard_modules) |path| {
        try out.appendSlice(arena, "import ");
        try out.appendSlice(arena, path[0 .. path.len - 3]);
        try out.append(arena, '\n');
    }
    try out.appendSlice(arena, "\ndef main() -> int:\n    return 0\n");
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
    const entry = try entrySource(arena);
    var project = language.project.Project.init(arena);
    defer project.deinit();
    var provider: EntryReader(language) = .{ .entry = entry };
    project.load(provider.provider(), entry_module, .{ .max_modules = 32 }) catch |err| switch (err) {
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
    // The listing is the compiler's own versioned `module interfaces v1`
    // surface. Its `effects(...)` value is the published mask, which falls back
    // to the conservative full vocabulary when no checked instantiation exists,
    // so this engine reads its inferred effects from the checked program
    // instead and parses only the declared facts here.
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
        const selected = try tables.buffer_operations.methodSpellings(arena, family);
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

/// Assemble every fact category once and keep the matching subset.
fn gather(comptime language: type, arena: std.mem.Allocator, query: []const u8, check_bodies: bool) Error!Answer {
    const manifest = std.json.parseFromSlice(std.json.Value, arena, @embedFile("features.json"), .{}) catch return error.OutOfMemory;
    defer manifest.deinit();
    const library = try gatherLibrary(language, arena, check_bodies);
    const facts: Facts = .{
        .syntax = try gatherSyntax(arena, query),
        .features = try gatherFeatures(arena, manifest.value, query),
        .limits = try gatherLimits(arena, manifest.value, query),
        .exclusions = try gatherExclusions(arena, manifest.value, query),
        .declarations = try select(Declaration, arena, library.declarations, query),
        .builtins = try gatherBuiltins(language, arena, query),
        .methods = try gatherMethods(language, arena, query),
    };
    return .{
        .query = query,
        .match = matchKind(facts, query),
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
        facts.declarations.len + facts.builtins.len + facts.methods.len;
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
    try writer.writeAll("  effects: ");
    if (declaration.effects) |effects| try writeNames(writer, effects) else try writer.writeAll("unavailable");
    try writer.writeAll("\n  ceiling: ");
    if (declaration.ceiling) |ceiling| try writeNames(writer, ceiling) else try writer.writeAll("none declared");
    try writer.writeAll("\n  mutates: ");
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

fn renderTextInto(writer: *std.Io.Writer, answer: Answer) !void {
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
        try writer.print("\nfeature {s}\n  kind: {s}\n  summary: {s}\n  doc: {s}\n", .{ feature.slug, feature.kind, feature.summary, feature.doc });
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
    }
}

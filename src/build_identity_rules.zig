//! Which sources the build-time identities cover, and how a digest is formed.
//!
//! `build_identity.zig` (a host tool at the repository root) imports this file to
//! decide which files under `src` it reads and to hash them; unit tests import it
//! from `src/root_test.zig`. `compiler_identity` covers every production source; the stage and engine-kind identities are
//! the digests of import closures. The tool analyzes each source once (`analyze`, `Facts`) and may keep the result per
//! file in a record (the last section) so a run after an edit parses only the files that changed. (A `runner_identity`
//! over a hand-kept list of the runner's files once keyed the execution receipts; the `test-exec` kind's closure
//! replaced it, and it is gone.)
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;

/// Source bytes read once per tool run, keyed by path relative to `src`.
pub const Sources = std.array_hash_map.String([]const u8);
/// A build product `build.zig` embeds in the compiler as bytes: the name an `@import` or `@embedFile` takes and the
/// SHA-256 (lowercase hexadecimal) of the bytes the compiler holds. An identity digests these bytes, not the settings that
/// produced them, so no setting of the product's build can be missed.
pub const Embedded = struct { name: []const u8, digest: [64]u8 };
/// The toolchain and optimize mode every identity digest includes, and the embedded build products it covers. Each product
/// adds one `product NAME DIGEST` line to the digested text; with none, the text is as it was before products existed.
pub const Toolchain = struct { zig_version: []const u8, optimize: []const u8, products: []const Embedded = &.{} };
/// Domain tag of `compiler_identity`. Changing it invalidates every cache keyed by it.
pub const compiler_domain = "selka-compiler-identity-v3";
/// Why a digest could not be formed: its text buffer could not grow.
pub const DigestError = error{ OutOfMemory, WriteFailed, MissingSource };

/// True when a source path is consumed only by a test root. The production
/// compiler never imports these, so they must not move `compiler_identity`; a
/// Zig test root already tracks them directly.
pub fn isTestOnly(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, name, "_test.zig")) return true;
    return std.mem.eql(u8, name, "test_support.zig") or
        std.mem.eql(u8, name, "unit_test.zig") or
        std.mem.eql(u8, name, "nominal_provider_fixture.zig") or
        std.mem.eql(u8, name, "stdlib_fixture.zig");
}

/// Every path of `sources` that `keep` accepts (all of them when it is null),
/// sorted bytewise. The caller owns the slice; the paths are borrowed.
pub fn sortedPaths(a: std.mem.Allocator, sources: Sources, keep: ?*const fn ([]const u8) bool) error{OutOfMemory}![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer paths.deinit(a);
    for (sources.keys()) |path| if (keep == null or keep.?(path)) try paths.append(a, path);
    std.mem.sort([]const u8, paths.items, {}, order);
    return paths.toOwnedSlice(a);
}

/// SHA-256, as lowercase hexadecimal, over `domain`, the toolchain, the optimize
/// mode and each listed source's path and content digest (`contentDigest`), in the
/// order of `paths`. A path missing from `sources` is an error (`MissingSource`).
pub fn digest(a: std.mem.Allocator, domain: []const u8, toolchain: Toolchain, sources: Sources, paths: []const []const u8) DigestError![64]u8 {
    return digestChained(a, domain, toolchain, "", sources, paths);
}

/// What one source contributes to an identity: for a Zig source, 128 bits over its
/// tokens (each tag and spelling, in order), so a comment, a doc comment or a change
/// of layout leaves it as it was; for any other file, 128 bits over its bytes.
///
/// The tokens are everything the Zig compiler turns into a program. This tree
/// uses no `@src()` and no reflection over source text, and embeds no Zig file
/// with `@embedFile`, so no run of the compiler or of a cache keyed by this
/// identity can differ between two sources with the same tokens; only the line
/// numbers of Debug-build stack traces do. A non-Zig file (the C runtime, the
/// standard library's `.selka` sources, `.json`, `.zon`) may be embedded, compiled or
/// read as text, so its bytes are all digested.
pub fn contentDigest(a: std.mem.Allocator, path: []const u8, bytes: []const u8) error{OutOfMemory}![16]u8 {
    var first = std.hash.Wyhash.init(0);
    var second = std.hash.Wyhash.init(1);
    if (!std.mem.endsWith(u8, path, ".zig")) {
        for ([_]*std.hash.Wyhash{ &first, &second }) |hash| {
            hash.update("bytes\x00");
            hash.update(bytes);
        }
    } else {
        const terminated = try a.allocSentinel(u8, bytes.len, 0);
        defer a.free(terminated);
        @memcpy(terminated, bytes);
        var tokenizer = std.zig.Tokenizer.init(terminated);
        for ([_]*std.hash.Wyhash{ &first, &second }) |hash| hash.update("zig-tokens\x00");
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            if (token.tag == .doc_comment or token.tag == .container_doc_comment) continue;
            const spelling = terminated[token.loc.start..token.loc.end];
            var header: [6]u8 = undefined;
            std.mem.writeInt(u16, header[0..2], @backingInt(token.tag), .little);
            std.mem.writeInt(u32, header[2..6], @intCast(spelling.len), .little);
            for ([_]*std.hash.Wyhash{ &first, &second }) |hash| {
                hash.update(&header);
                hash.update(spelling);
            }
        }
    }
    var result: [16]u8 = undefined;
    std.mem.writeInt(u64, result[0..8], first.final(), .little);
    std.mem.writeInt(u64, result[8..16], second.final(), .little);
    return result;
}

/// Why a stage's import closure could not be formed. A refused closure fails the build; it is never narrowed.
pub const ClosureError = error{ OutOfMemory, ParseFailed, NonLiteralImport, UnknownModule, TestOnlyImport, MissingSource };

/// A named module `build.zig` wires to a file under `src`: an `@import` or `@embedFile` of `name` means `path`. A `product`
/// is a build output compiled from `path` and embedded as bytes, so its digest joins every identity whose files reach `path`.
pub const NamedFile = struct { name: []const u8, path: []const u8, product: bool = false };
/// The named modules of the compiler's build graph (`build.zig`, `addImport` and `addModule`), and the one build
/// product whose source is under `src`: `core_number_text_object` is the object `core/runtime/core_number_text.zig` compiles to.
pub const named_files = [_]NamedFile{
    .{ .name = "selka", .path = "compiler.zig" },
    .{ .name = "memory_budget", .path = "memory_budget.zig" },
    .{ .name = "core_tool_platform", .path = "config_core_tool_platform.zig" },
    .{ .name = "selka_core", .path = "core/cli.zig" },
    .{ .name = "compiler_root", .path = "main.zig" },
    .{ .name = "test_paths", .path = "core/test_paths.zig" },
    .{ .name = "core_number_text_object", .path = "core/runtime/core_number_text.zig", .product = true },
};
/// The named module called `name`, or null.
fn findNamedFile(name: []const u8) ?NamedFile {
    for (named_files) |entry| if (std.mem.eql(u8, entry.name, name)) return entry;
    return null;
}

/// The `Embedded.digest` of a product's `bytes`: SHA-256, lowercase hexadecimal.
pub fn productDigest(bytes: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    Sha.hash(bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

/// Why the products a build supplies do not match the ones `named_files` marks.
pub const ProductError = error{ UnknownProduct, MissingProduct };

/// Refuse a build that supplies a product `named_files` does not mark (`UnknownProduct`) or leaves out one it marks
/// (`MissingProduct`), so a build product cannot be embedded in the compiler without its bytes joining the identity.
pub fn checkProducts(supplied: []const Embedded) ProductError!void {
    for (supplied) |product| {
        const named = findNamedFile(product.name) orelse return error.UnknownProduct;
        if (!named.product) return error.UnknownProduct;
    }
    for (named_files) |entry| {
        if (!entry.product) continue;
        var found = false;
        for (supplied) |product| found = found or std.mem.eql(u8, product.name, entry.name);
        if (!found) return error.MissingProduct;
    }
}

/// The products among `products` whose source file `reached_files` holds (a stage's closure): what a stage with that closure
/// digests beside its files. A closure holds the source of a product exactly when it reaches the `@embedFile` of that product.
pub fn reachedProducts(a: std.mem.Allocator, products: []const Embedded, reached_files: []const []const u8) error{OutOfMemory}![]const Embedded {
    var reached: std.ArrayList(Embedded) = .empty;
    for (products) |product| {
        const source_path = findNamed(product.name) orelse continue;
        for (reached_files) |path| if (std.mem.eql(u8, path, source_path)) {
            try reached.append(a, product);
            break;
        };
    }
    return reached.toOwnedSlice(a);
}

/// Names an `@import` may use with no file under `src`: the standard library, the language builtins, and the generated
/// identity module (which no stage's code reads as source).
const external_modules = [_][]const u8{ "std", "builtin", "build_identity" };

/// Every production path a stage's roots reach, sorted: the files their code imports at file scope or in function
/// bodies, through `@import` and `@embedFile` (`test` declarations are not followed). Edges are the AST's string
/// literals, so a comment or a string that spells an import is not one. Refuses (returns an error) on a non-literal
/// argument, an unknown module name, a test-only file reached from production code, or a path missing from `sources`.
pub fn closure(a: std.mem.Allocator, sources: Sources, roots: []const []const u8) ClosureError![]const []const u8 {
    return closureWith(a, sources, roots, .{});
}

/// How the walk treats an `@import` of the front end's module (`"selka"`, whose root `compiler.zig` re-exports the
/// front end's files as members). A stage follows the whole module, as every file that names it can reach any member.
/// An engine kind follows the members a file names, so a kind that uses the front end module's `typed` member depends on
/// `typed.zig` and what it imports, not on the compiler.
pub const Walk = enum { whole_modules, members };

/// How `closureWith` walks: the module walk, and the boundary files: files the walk includes (their own tokens join the
/// identity) and does not enter (what they import is not followed from them). A boundary is the glue between the code a
/// kind decides with and the compiler, kept as the old runner identity kept it: by the file, not by its closure.
pub const ClosureOptions = struct { walk: Walk = .whole_modules, boundary: []const []const u8 = &.{} };

/// `closure` with `options`.
pub fn closureWith(a: std.mem.Allocator, sources: Sources, roots: []const []const u8, options: ClosureOptions) ClosureError![]const []const u8 {
    return closureIn(a, .{ .bytes = &sources }, roots, options);
}

/// `closureWith` over either form of the tree (`Corpus`): the same walk, with each file's edges parsed from its bytes or
/// taken from its `FileFacts`.
pub fn closureIn(a: std.mem.Allocator, corpus: Corpus, roots: []const []const u8, options: ClosureOptions) ClosureError![]const []const u8 {
    var seen: std.array_hash_map.String(void) = .empty;
    var pending: std.ArrayList([]const u8) = .empty;
    const members: ?Members = if (options.walk == .members) try corpusMembers(a, corpus) else null;
    for (roots) |root| try pending.append(a, root);
    while (pending.pop()) |path| {
        if (seen.contains(path)) continue;
        if (isTestOnly(path)) return error.TestOnlyImport;
        if (!corpus.contains(path)) return error.MissingSource;
        try seen.put(a, path, {});
        if (isBoundary(options.boundary, path)) continue;
        for (try corpusEdges(a, corpus, path, members)) |next| try pending.append(a, next);
    }
    const out = try a.dupe([]const u8, seen.keys());
    std.mem.sort([]const u8, out, {}, order);
    return out;
}

/// The tree an identity is formed from, in forms that give the same identities: every production source's bytes
/// (`Sources`, parsed again by each closure that reaches a file), the same with each parse held in `scratch` and freed
/// once the file's edges are copied out (`Parsed`, so a whole tree's closures fit in the memory of one file's parse), or
/// what each source contributes, computed once (`Facts`, from `analyze`).
pub const Corpus = union(enum) {
    bytes: *const Sources,
    parsed: Parsed,
    facts: *const Facts,

    /// The bytes form with an allocator whose frees return memory (not an arena) for each file's parse.
    pub const Parsed = struct { sources: *const Sources, scratch: std.mem.Allocator };

    /// True when the tree holds `path`.
    pub fn contains(corpus: Corpus, path: []const u8) bool {
        return switch (corpus) {
            .bytes => |sources| sources.contains(path),
            .parsed => |parsed| parsed.sources.contains(path),
            .facts => |facts| facts.contains(path),
        };
    }

    /// Every path of the tree, sorted bytewise.
    pub fn sortedPaths(corpus: Corpus, a: std.mem.Allocator) error{OutOfMemory}![]const []const u8 {
        const keys = switch (corpus) {
            .bytes => |sources| sources.keys(),
            .parsed => |parsed| parsed.sources.keys(),
            .facts => |facts| facts.keys(),
        };
        const paths = try a.dupe([]const u8, keys);
        std.mem.sort([]const u8, paths, {}, order);
        return paths;
    }
};

/// Why a file's own text refuses every closure that reaches it: the refusals `fileEdges` returns, by name.
pub const Refusal = enum(u8) { parse_failed = 1, non_literal_import = 2, unknown_module = 3 };

fn refusalError(refusal: Refusal) ClosureError {
    return switch (refusal) {
        .parse_failed => error.ParseFailed,
        .non_literal_import => error.NonLiteralImport,
        .unknown_module => error.UnknownModule,
    };
}

/// How a file uses the front end module (`"selka"`) under `Walk.members`: not at all, only by naming members, or in a
/// way that needs the whole module (the module passed as a value, or an alias used other than for a member).
pub const MemberUse = enum(u8) { none = 0, members = 1, whole = 2 };

/// What the identities need from one source, computed once from its bytes by `analyze`: its content digest
/// (`contentDigest`) and its import edges under both walks. `edges` are the edges `Walk.whole_modules` follows; under
/// `Walk.members` a file has `member_edges` (its edges without its imports of the front end module), then the files of
/// the members it names (`member_names`, resolved against the module's member table) and the module itself when
/// `member_use` is `whole` or a name does not resolve. `member_table` is the member table, held by the module's root
/// only. A `refusal` refuses every closure that reaches the file, as parsing its bytes would.
pub const FileFacts = struct {
    digest: [16]u8,
    refusal: ?Refusal = null,
    edges: []const []const u8 = &.{},
    member_edges: []const []const u8 = &.{},
    member_names: []const []const u8 = &.{},
    member_use: MemberUse = .none,
    member_table: []const [2][]const u8 = &.{},
};

/// What each production source contributes, keyed by path relative to `src`.
pub const Facts = std.array_hash_map.String(FileFacts);

/// The facts of one source: everything `contentDigest`, `fileEdgesWith` and `memberFiles` read from its bytes, so a
/// closure or digest over `Facts` never reads it again. Strings are allocated with `a`; `scratch` holds the parse and is
/// reset before returning.
pub fn analyze(a: std.mem.Allocator, scratch: *std.heap.ArenaAllocator, path: []const u8, bytes: []const u8) error{OutOfMemory}!FileFacts {
    defer _ = scratch.reset(.retain_capacity);
    const s = scratch.allocator();
    var facts: FileFacts = .{ .digest = try contentDigest(s, path, bytes) };
    if (!std.mem.endsWith(u8, path, ".zig")) return facts;
    const terminated = try s.allocSentinel(u8, bytes.len, 0);
    @memcpy(terminated, bytes);
    const tree = try std.zig.Ast.parse(s, terminated, .{});
    if (tree.errors.len != 0) {
        facts.refusal = .parse_failed;
        return facts;
    }
    // The member table needs only the parse, as `memberFiles` does: build it before an edge can refuse the file, or a
    // member use of a refused module root would resolve to the whole module instead of the member's file.
    if (std.mem.eql(u8, path, findNamed(member_module).?)) {
        const table = try memberTable(s, tree, path);
        const owned = try a.alloc([2][]const u8, table.len);
        for (owned, table) |*pair, entry| pair.* = .{ try a.dupe(u8, entry[0]), try a.dupe(u8, entry[1]) };
        facts.member_table = owned;
    }
    var tests: std.ArrayList([2]u32) = .empty;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        if (tree.nodeTag(node) == .test_decl) try tests.append(s, .{ tree.firstToken(node), tree.lastToken(node) });
    }
    const directory = std.fs.path.dirname(path) orelse "";
    var edges: std.ArrayList([]const u8) = .empty;
    var member_edges: std.ArrayList([]const u8) = .empty;
    var buffer: [2]std.zig.Ast.Node.Index = undefined;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        switch (tree.nodeTag(node)) {
            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {},
            else => continue,
        }
        const token = tree.nodeMainToken(node);
        const builtin = tree.tokenSlice(token);
        const is_import = std.mem.eql(u8, builtin, "@import");
        if (!is_import and !std.mem.eql(u8, builtin, "@embedFile")) continue;
        if (inSpan(tests.items, token)) continue;
        const params = tree.builtinCallParams(&buffer, node) orelse return refused(facts, .non_literal_import);
        if (params.len != 1 or tree.nodeTag(params[0]) != .string_literal) return refused(facts, .non_literal_import);
        const name = literal(tree.tokenSlice(tree.nodeMainToken(params[0]))) catch return refused(facts, .non_literal_import);
        // The same branches as `fileEdgesWith`, once without a member table (`edges`) and once with one (`member_edges`),
        // where an import of the front end module is resolved later, by the members the file names.
        const target: []const u8 = if (findNamed(name)) |named|
            named
        else if (std.mem.endsWith(u8, name, ".zig") or std.mem.endsWith(u8, name, ".zon") or !is_import)
            try joinNormal(a, directory, name)
        else if (!isExternal(name))
            return refused(facts, .unknown_module)
        else
            continue;
        try edges.append(a, target);
        if (!(is_import and std.mem.eql(u8, name, member_module))) try member_edges.append(a, target);
    }
    facts.edges = edges.items;
    facts.member_edges = member_edges.items;
    const scan = try memberScan(s, tree, tests.items);
    facts.member_use = scan.use;
    facts.member_names = try dupeStrings(a, scan.names);
    return facts;
}

fn refused(facts: FileFacts, refusal: Refusal) FileFacts {
    var out = facts;
    out.refusal = refusal;
    return out;
}

fn dupeStrings(a: std.mem.Allocator, strings: []const []const u8) error{OutOfMemory}![]const []const u8 {
    const out = try a.alloc([]const u8, strings.len);
    for (out, strings) |*slot, text| slot.* = try a.dupe(u8, text);
    return out;
}

/// The member table of the front end module over `corpus`: empty without its root, refused when the root does not parse.
fn corpusMembers(a: std.mem.Allocator, corpus: Corpus) ClosureError!Members {
    switch (corpus) {
        .bytes => |sources| return memberFiles(a, sources.*),
        .parsed => |parsed| {
            var scratch = std.heap.ArenaAllocator.init(parsed.scratch);
            defer scratch.deinit();
            const members = try memberFiles(scratch.allocator(), parsed.sources.*);
            var owned: Members = .empty;
            for (members.keys(), members.values()) |name, target| try owned.put(a, try a.dupe(u8, name), try a.dupe(u8, target));
            return owned;
        },
        .facts => |all| {
            const facts = all.get(findNamed(member_module).?) orelse return .empty;
            if (facts.refusal == .parse_failed) return error.ParseFailed;
            return membersOf(a, facts.member_table);
        },
    }
}

/// The edges of the file at `path` (which `corpus` holds) under the walk `members` selects.
fn corpusEdges(a: std.mem.Allocator, corpus: Corpus, path: []const u8, members: ?Members) ClosureError![]const []const u8 {
    switch (corpus) {
        .bytes => |sources| return fileEdgesWith(a, path, sources.get(path).?, members),
        .parsed => |parsed| {
            var scratch = std.heap.ArenaAllocator.init(parsed.scratch);
            defer scratch.deinit();
            return dupeStrings(a, try fileEdgesWith(scratch.allocator(), path, parsed.sources.get(path).?, members));
        },
        .facts => |all| {
            const facts = all.get(path).?;
            if (facts.refusal) |refusal| return refusalError(refusal);
            const known = members orelse return facts.edges;
            var edges: std.ArrayList([]const u8) = .empty;
            try edges.appendSlice(a, facts.member_edges);
            try resolveMembers(a, facts.member_use, facts.member_names, known, &edges);
            return edges.items;
        },
    }
}

/// The content digest of the file at `path`, or `MissingSource` when `corpus` does not hold it.
fn corpusDigest(a: std.mem.Allocator, corpus: Corpus, path: []const u8) DigestError![16]u8 {
    return switch (corpus) {
        .bytes => |sources| try contentDigest(a, path, sources.get(path) orelse return error.MissingSource),
        .parsed => |parsed| try contentDigest(parsed.scratch, path, parsed.sources.get(path) orelse return error.MissingSource),
        .facts => |facts| (facts.get(path) orelse return error.MissingSource).digest,
    };
}

fn isBoundary(boundary: []const []const u8, path: []const u8) bool {
    for (boundary) |known| if (std.mem.eql(u8, known, path)) return true;
    return false;
}

/// The front end module's members that are files: the `pub const name = ...` declarations of `compiler.zig` that import a file, by name.
const Members = std.array_hash_map.String([]const u8);

/// The module name whose members `Walk.members` resolves.
const member_module = "selka";

fn memberFiles(a: std.mem.Allocator, sources: Sources) ClosureError!Members {
    const root = findNamed(member_module).?;
    const bytes = sources.get(root) orelse return .empty;
    const terminated = try a.allocSentinel(u8, bytes.len, 0);
    @memcpy(terminated, bytes);
    const tree = try std.zig.Ast.parse(a, terminated, .{});
    if (tree.errors.len != 0) return error.ParseFailed;
    return membersOf(a, try memberTable(a, tree, root));
}

/// The member table of the module root `root` (parsed as `tree`), in declaration order: each `pub const name = ...`
/// declaration that imports a `.zig` file, as its name and the file's path relative to `src`.
fn memberTable(a: std.mem.Allocator, tree: std.zig.Ast, root: []const u8) error{OutOfMemory}![]const [2][]const u8 {
    var table: std.ArrayList([2][]const u8) = .empty;
    for (tree.rootDecls()) |decl| {
        const declaration = tree.fullVarDecl(decl) orelse continue;
        const init = declaration.ast.init_node.unwrap() orelse continue;
        const name = importedName(a, tree, init) orelse continue;
        if (!std.mem.endsWith(u8, name, ".zig")) continue;
        try table.append(a, .{ tree.tokenSlice(declaration.ast.mut_token + 1), try joinNormal(a, std.fs.path.dirname(root) orelse "", name) });
    }
    return table.items;
}

/// `table` as a map; a later declaration of a name replaces an earlier one.
fn membersOf(a: std.mem.Allocator, table: []const [2][]const u8) error{OutOfMemory}!Members {
    var members: Members = .empty;
    for (table) |entry| try members.put(a, entry[0], entry[1]);
    return members;
}

/// The literal path of an import call when `node` is exactly that call, else null.
fn importedName(a: std.mem.Allocator, tree: std.zig.Ast, node: std.zig.Ast.Node.Index) ?[]const u8 {
    switch (tree.nodeTag(node)) {
        .builtin_call_two, .builtin_call_two_comma => {},
        else => return null,
    }
    if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import")) return null;
    var buffer: [2]std.zig.Ast.Node.Index = undefined;
    const params = tree.builtinCallParams(&buffer, node) orelse return null;
    if (params.len != 1 or tree.nodeTag(params[0]) != .string_literal) return null;
    _ = a;
    return literal(tree.tokenSlice(tree.nodeMainToken(params[0]))) catch null;
}

/// The paths one file imports: none for a non-Zig file (its bytes are digested whole), else the literal `@import`
/// and `@embedFile` targets outside `test` declarations. Parse errors refuse the file.
fn fileEdges(a: std.mem.Allocator, path: []const u8, bytes: []const u8) ClosureError![]const []const u8 {
    return fileEdgesWith(a, path, bytes, null);
}

/// `fileEdges`, resolving the front end module by its members when `members` is given.
fn fileEdgesWith(a: std.mem.Allocator, path: []const u8, bytes: []const u8, members: ?Members) ClosureError![]const []const u8 {
    if (!std.mem.endsWith(u8, path, ".zig")) return &.{};
    const terminated = try a.allocSentinel(u8, bytes.len, 0);
    @memcpy(terminated, bytes);
    var tree = try std.zig.Ast.parse(a, terminated, .{});
    defer tree.deinit(a);
    if (tree.errors.len != 0) return error.ParseFailed;
    var tests: std.ArrayList([2]u32) = .empty;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        if (tree.nodeTag(node) == .test_decl) try tests.append(a, .{ tree.firstToken(node), tree.lastToken(node) });
    }
    const directory = std.fs.path.dirname(path) orelse "";
    var edges: std.ArrayList([]const u8) = .empty;
    var buffer: [2]std.zig.Ast.Node.Index = undefined;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        switch (tree.nodeTag(node)) {
            .builtin_call_two, .builtin_call_two_comma, .builtin_call, .builtin_call_comma => {},
            else => continue,
        }
        const token = tree.nodeMainToken(node);
        const builtin = tree.tokenSlice(token);
        const is_import = std.mem.eql(u8, builtin, "@import");
        if (!is_import and !std.mem.eql(u8, builtin, "@embedFile")) continue;
        if (inSpan(tests.items, token)) continue;
        const params = tree.builtinCallParams(&buffer, node) orelse return error.NonLiteralImport;
        if (params.len != 1 or tree.nodeTag(params[0]) != .string_literal) return error.NonLiteralImport;
        const name = try literal(tree.tokenSlice(tree.nodeMainToken(params[0])));
        if (is_import and members != null and std.mem.eql(u8, name, member_module)) {
            // Resolved below, once every use of the module in the file is known.
        } else if (findNamed(name)) |target| {
            try edges.append(a, target);
        } else if (std.mem.endsWith(u8, name, ".zig") or std.mem.endsWith(u8, name, ".zon") or !is_import) {
            try edges.append(a, try joinNormal(a, directory, name));
        } else if (!isExternal(name)) {
            return error.UnknownModule;
        }
    }
    if (members) |known| try memberEdges(a, tree, tests.items, known, &edges);
    return edges.items;
}

/// The edges of the front end module's uses in one file under `Walk.members`: the file of each member named, or the
/// whole module (`compiler.zig`) when a use cannot be read as a member: the module passed as a value, a member that is
/// not a plain file, or a name this file does not resolve.
fn memberEdges(a: std.mem.Allocator, tree: std.zig.Ast, tests: []const [2]u32, members: Members, edges: *std.ArrayList([]const u8)) ClosureError!void {
    const scan = try memberScan(a, tree, tests);
    try resolveMembers(a, scan.use, scan.names, members, edges);
}

/// The edges a file's uses of the front end module add under `Walk.members`, given how it uses the module (`use`) and the
/// members it names: the file of each name the member table resolves, then the module itself when a use needs the whole
/// module or a name does not resolve.
fn resolveMembers(a: std.mem.Allocator, use: MemberUse, names: []const []const u8, members: Members, edges: *std.ArrayList([]const u8)) error{OutOfMemory}!void {
    if (use == .none) return;
    var whole = use == .whole;
    for (names) |member| {
        if (members.get(member)) |target| try edges.append(a, target) else whole = true;
    }
    if (whole) try edges.append(a, findNamed(member_module).?);
}

/// How one file uses the front end module, and the members it names in order, independent of the member table.
const MemberScan = struct { use: MemberUse, names: []const []const u8 };

fn memberScan(a: std.mem.Allocator, tree: std.zig.Ast, tests: []const [2]u32) error{OutOfMemory}!MemberScan {
    var aliases: std.ArrayList([]const u8) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var uses: usize = 0;
    var explained: usize = 0;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        if (inSpan(tests, tree.firstToken(node))) continue;
        if (importedName(a, tree, node)) |name| {
            if (std.mem.eql(u8, name, member_module)) uses += 1;
            continue;
        }
        const declaration = tree.fullVarDecl(node) orelse continue;
        const init = declaration.ast.init_node.unwrap() orelse continue;
        const name = importedName(a, tree, init) orelse continue;
        if (!std.mem.eql(u8, name, member_module)) continue;
        try aliases.append(a, tree.tokenSlice(declaration.ast.mut_token + 1));
        explained += 1;
    }
    var named: usize = 0;
    var alias_uses: usize = 0;
    var alias_members: usize = 0;
    for (0..tree.nodes.len) |raw| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(raw));
        if (inSpan(tests, tree.firstToken(node))) continue;
        switch (tree.nodeTag(node)) {
            .identifier => {
                const text = tree.tokenSlice(tree.nodeMainToken(node));
                for (aliases.items) |alias| if (std.mem.eql(u8, alias, text)) {
                    alias_uses += 1;
                };
            },
            .field_access => {
                const lhs, const field = tree.nodeData(node).node_and_token;
                const member = tree.tokenSlice(field);
                if (importedName(a, tree, lhs)) |name| {
                    if (!std.mem.eql(u8, name, member_module)) continue;
                    named += 1;
                    try names.append(a, member);
                } else if (tree.nodeTag(lhs) == .identifier) {
                    const text = tree.tokenSlice(tree.nodeMainToken(lhs));
                    for (aliases.items) |alias| if (std.mem.eql(u8, alias, text)) {
                        alias_members += 1;
                        try names.append(a, member);
                    };
                }
            },
            else => {},
        }
    }
    if (uses == 0) return .{ .use = .none, .names = &.{} };
    // Every use is either a member access on the module import or the initializer of an alias whose every use is a member access.
    const whole = uses != named + explained or alias_uses != alias_members;
    return .{ .use = if (whole) .whole else .members, .names = names.items };
}

/// The target of a named module, or null.
fn findNamed(name: []const u8) ?[]const u8 {
    for (named_files) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.path;
    return null;
}

/// True for the names an `@import` may use with no file under `src`.
fn isExternal(name: []const u8) bool {
    for (external_modules) |module| if (std.mem.eql(u8, module, name)) return true;
    return false;
}

/// The contents of a plain string literal token (`"..."`). Escapes refuse: a path has none.
fn literal(token: []const u8) ClosureError![]const u8 {
    if (token.len < 2 or token[0] != '"' or token[token.len - 1] != '"') return error.NonLiteralImport;
    const body = token[1 .. token.len - 1];
    if (std.mem.indexOfScalar(u8, body, '\\') != null) return error.NonLiteralImport;
    return body;
}

/// `directory/name` with `.` and `..` components resolved, relative to `src`.
fn joinNormal(a: std.mem.Allocator, directory: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.tokenizeScalar(u8, directory, '/');
    while (pieces.next()) |piece| try parts.append(a, piece);
    var rest = std.mem.tokenizeScalar(u8, name, '/');
    while (rest.next()) |piece| {
        if (std.mem.eql(u8, piece, ".")) continue;
        if (std.mem.eql(u8, piece, "..")) {
            if (parts.items.len != 0) _ = parts.pop();
            continue;
        }
        try parts.append(a, piece);
    }
    return std.mem.join(a, "/", parts.items);
}

/// True when token index `token` lies inside one of the `[first, last]` token spans.
fn inSpan(spans: []const [2]u32, token: u32) bool {
    for (spans) |span| if (token >= span[0] and token <= span[1]) return true;
    return false;
}

/// Domain tag of the stage identities. Changing it invalidates every stage-scoped record.
pub const stage_domain = "selka-stage-identity-v1";
/// Stage names in pipeline order, matching `stage_scopes.Stage` (the whole identity is not a stage).
pub const stage_names = [_][]const u8{ "front", "lower", "opt", "emit", "test-runner" };
/// The roots of each stage, in `stage_names` order. A stage's closure is the files its roots import.
pub const stage_roots = [_][]const []const u8{
    &.{ "compiler.zig", "core/frontend_reuse.zig" },
    &.{ "core/build.zig", "core/lowering_cache.zig", "core/lowering_demand.zig", "core/lowering_finish.zig", "core/demand_ir.zig" },
    &.{ "core/passes.zig", "core/optimization_cache.zig", "core/optimizer_shortcut.zig", "core/fusion_checkpoint.zig" },
    &.{ "core/emit_llvm.zig", "core/emit_units.zig", "core/emission_cache.zig", "core/emission_key.zig", "core/native_receipt.zig" },
    &.{ "core/test_runner_facts.zig", "core/test_runner_graph.zig", "core/test_runner_identity.zig" },
};
/// The upstream stage of each stage in `stage_names` order (null for the first). A stage's identity chains the identity of
/// its upstream stage, so it moves with every stage upstream of it. The test-runner stage chains from `lower`, not from
/// `emit`: its records are computed from lowered bodies and canonical digests, never from emitted text.
pub const stage_upstream = [_]?usize{ null, 0, 1, 2, 1 };
comptime {
    if (stage_upstream.len != stage_names.len or stage_roots.len != stage_names.len) @compileError("stage tables differ in length");
    for (stage_upstream, 0..) |upstream, index| {
        if (upstream) |earlier| if (earlier >= index) @compileError("a stage must chain from an earlier stage");
    }
}

/// Domain tag of the engine kind identities. Changing it invalidates every record of every engine kind.
pub const kind_domain = "selka-engine-kind-identity-v1";

/// A query kind of the incremental engine (`docs/design/incremental-engine.md` §3): its name, the files its code starts
/// from, and the kinds whose identities it chains from. Its code identity is the token digest of the import closure of
/// its roots, chained with the identities of its upstream kinds, so it moves exactly with the code that can change what
/// the kind computes. `selka engine closure KIND` prints the closure.
pub const EngineKind = struct {
    name: []const u8,
    /// The kind's implementation, files relative to `src`: what the no-raw-access scan reads.
    roots: []const []const u8,
    /// Files whose code decides what the kind's results mean without being the kind's code: they join the identity (the
    /// closure of `roots` and `covers`) and are not scanned. In shadow a kind's body returns an answer another code path
    /// computed, and `covers` names that path's code; when the kind computes for itself they move into `roots`.
    covers: []const []const u8 = &.{},
    /// Files that join the identity by their own tokens and whose imports are not followed (`ClosureOptions.boundary`).
    boundary: []const []const u8 = &.{},
    /// Names of earlier entries of `engine_kinds` whose identities this one chains from.
    upstream: []const []const u8 = &.{},
};

/// The files whose code decides what a test's execution means: the trial protocol and its budgets, the judging of an
/// outcome (`test_runner_execute.zig`, the examples' transcripts), the property search and the cases file. This is the
/// closure that replaces the hand-kept runner file list (`runner_files`): everything these files import is covered,
/// except the boundary below. Not covered, with the reason: the linked program's bytes (its key is an argument of the
/// query), eligibility (`sema.zig`, `test_runner_portable.zig`: decided when the engine is asked, never stored), the build
/// pipeline and driver (they make the program), the batch entry (emitted into the program), the old receipt code.
const test_exec_covers = [_][]const u8{
    "core/test_runner_execute.zig", "core/test_runner_property.zig",       "core/test_runner_example_report.zig", "core/test_runner_cases.zig",
    "core/process_spawn.zig",       "core/run_budget.zig",                 "core/trap_contract.zig",              "core/property_codec.zig",
    "core/property_execute.zig",    "core/property_generate.zig",          "core/property_ir.zig",                "core/property_render.zig",
    "core/property_schema.zig",     "core/property_shrink.zig",            "core/property_types.zig",             "core/property_validate.zig",
    "core/property_value.zig",      "core/property_campaign_contract.zig", "core/property_campaign_receipt.zig",
};

/// Files `test-exec` includes by their own tokens without entering them: the options and key code the arguments are built from,
/// the work metrics, the cases file's reader, the embedded standard library and the examples' source type. Their imports reach
/// the whole compiler, which the program's bytes already cover.
const test_exec_boundary = [_][]const u8{
    "core/test_runner_options.zig", "core/test_runner_receipt.zig", "core/test_runner_shared.zig",  "core/test_runner_work.zig",
    "core/test_runner_cases.zig",   "standard_library.zig",         "docstring_example_source.zig",
};

/// The files that make a test's program and an entry's report: the front end and every stage of the build, and the runner's
/// planning and printing.
const test_report_covers = [_][]const u8{
    "compiler.zig",               "core/frontend_reuse.zig", "core/build.zig",             "core/lowering_cache.zig",     "core/lowering_demand.zig",
    "core/lowering_finish.zig",   "core/demand_ir.zig",      "core/passes.zig",            "core/optimization_cache.zig", "core/optimizer_shortcut.zig",
    "core/fusion_checkpoint.zig", "core/emit_llvm.zig",      "core/emit_units.zig",        "core/emission_cache.zig",     "core/emission_key.zig",
    "core/native_receipt.zig",    "core/test_runner.zig",    "core/test_runner_facts.zig", "core/test_runner_graph.zig",  "core/test_runner_identity.zig",
    "core/pipeline.zig",          "core/driver.zig",
};

/// The code whose results `module-tokens` returns (test-loop stage 6): the digest of a source's tokens the runner hands the kind,
/// and the lexer and layout pass that produce the tokens.
const module_tokens_covers = [_][]const u8{ "core/test_runner_tokens.zig", "lexer.zig", "python_layout.zig" };

/// The code whose results `module-syntax` returns while the front end computes them (shadow, G2a): the parts of a parsed
/// module, and the lexer, header scan and parser that produce what they cut. Not scanned (the front end reads files freely).
const module_syntax_covers = [_][]const u8{ "core/module_parts.zig", "project.zig", "parser.zig", "lexer.zig", "ast.zig", "standard_library.zig" };

/// The code whose results `project-graph` returns while the front end computes them (shadow, G2a): the module loader and the
/// builder of the graph's payload and parts.
const project_graph_covers = [_][]const u8{ "core/project_graph_answer.zig", "project.zig", "standard_library.zig" };

/// The code whose results `module-interface` returns while the front end computes them (shadow, G2b): the digests of a module's
/// names built from the declaration graph of the merged program, and the code that merges and fingerprints it.
const module_interface_covers = [_][]const u8{ "core/module_interface_facts.zig", "semantic_key.zig", "constant_values.zig", "project_syntax.zig", "interfaces.zig", "ast.zig", "source.zig" };

/// The code whose results `module-check` returns while the front end computes them (shadow, G2c): the keys of the checked bodies
/// and the lookups of their bodies, built over the declaration graph and the dependency contexts of the merged program.
const module_check_covers = [_][]const u8{
    "core/module_check_facts.zig", "core/module_interface_facts.zig", "semantic_key.zig", "constant_values.zig", "project_syntax.zig",
    "interfaces.zig",              "ast.zig",                         "source.zig",       "embed.zig",           "module_records.zig",
    "persist_codec.zig",
};

/// The code whose results `noalloc-closure` returns while the front end computes them (shadow, G2i): the check of the promise over
/// Core, and the lowering and passes it runs, so a change to any of them moves every verdict recorded before it.
const noalloc_closure_covers = [_][]const u8{ "core/noalloc_closure_facts.zig", "core/allocation_contract.zig", "core/module_check_facts.zig", "ast.zig", "source.zig" };

/// The code whose results `module-passes` returns while the front end computes them (shadow, G2e): the summaries of the passes'
/// facts, and the origin analysis and summary format they come from.
const module_passes_covers = [_][]const u8{ "core/module_passes_facts.zig", "core/module_check_facts.zig", "semantic_summary.zig", "origins.zig", "ast.zig", "source.zig" };

/// The code whose results `program-diagnostics` returns while the front end computes them (shadow, G2h): the rendering of the
/// program's diagnostics, and the diagnostic format and sink behind it.
const program_diagnostics_covers = [_][]const u8{ "core/program_diagnostics_facts.zig", "core/module_passes_facts.zig", "core/project_graph_answer.zig", "diagnostic.zig", "diagnostic_output.zig", "source.zig" };

/// The code whose results `unit-lower` returns while lowering computes them (shadow, G3c): the grouping of what lowering did into
/// units, the canonical form of an artifact, and the stable names and op log it is made of.
const unit_lower_covers = [_][]const u8{ "core/lowering_shadow.zig", "core/lowering_cache.zig", "core/demand_sources.zig", "core/record_names.zig", "core/module_parts.zig", "core/op_log.zig", "core/stable_names.zig" };

/// The code whose results `program-facts` returns while the optimizer computes them (shadow, G3h): the digests of the joined facts,
/// the joins themselves (parameter hulls, effects, field intervals, whether the program is closed) and the canonical form of types.
const program_facts_covers = [_][]const u8{ "core/program_facts_shadow.zig", "core/passes.zig", "core/facts.zig", "core/effects.zig", "core/consume.zig", "core/canonical_ir.zig", "core/inline.zig" };

/// The code whose results `unit-optimize` returns while the optimizer computes them (shadow, G3e): the digests of the final bodies, what
/// the passes do to a function (inlining, versioning, ownership, the fact passes) and the canonical form the digests are taken in.
const unit_optimize_covers = [_][]const u8{
    "core/optimize_shadow.zig",    "core/optimizer_shadow.zig",   "core/optimizer_observed.zig", "core/passes.zig", "core/inline.zig",  "core/inline_cfg.zig",
    "core/inline_origins.zig",     "core/facts.zig",              "core/effects.zig",            "core/own.zig",    "core/version.zig", "core/canonical_ir.zig",
    "core/optimizer_shortcut.zig", "core/optimization_cache.zig",
};

/// The code whose results `unit-emit` returns while the emitter computes them (shadow, G4a step 3): the compact key and the text of a
/// unit, the linkage and canonical order that decide which functions a unit holds, and the descriptor ids and catalog its text names.
const unit_emit_covers = [_][]const u8{
    "core/emit_shadow.zig",    "core/emit_units.zig",  "core/emission_key.zig",    "core/emission_cache.zig", "core/emit_llvm.zig",    "core/emit_values.zig",
    "core/emit_constants.zig", "core/emit_render.zig", "core/emit_owned_copy.zig", "core/type_ids.zig",       "core/canonical_ir.zig", "core/effects.zig",
};

/// The code whose results `ownership-proof` returns while the ownership cache computes them (shadow, G1a): the grouping of the
/// proofs, the ownership checker and the declaration reach a function's proof depends on. The closure follows the front end
/// members they name, so a change to any of them can change a verdict and every proof recorded before it is another proof.
const ownership_proof_covers = [_][]const u8{ "core/ownership_proof_facts.zig", "core/single_owner.zig", "core/lowering_cache.zig" };

/// The code whose results `test-facts` and `test-graph` hold (step G4e): the runner's canonical facts and its graph, and the key code
/// both are addressed by. These are the files of the test-runner stage, so a change to any of them is another kind.
const test_facts_covers = [_][]const u8{ "core/test_runner_facts.zig", "core/test_runner_identity.zig", "core/canonical_ir.zig" };
const test_graph_covers = [_][]const u8{ "core/test_runner_graph.zig", "core/test_runner_identity.zig" };

/// The engine's kinds, upstream kinds first. The probe kinds are the engine's own: they exercise a real read, a real
/// dependency and an early cutoff through the whole stack, and give `selka engine` something to answer. `test-exec` and
/// `test-report` are the `selka test` kinds (spec section 13): the kind's body returns the verdict or the report the runner
/// computed, and `covers` names the runner's code so the identity moves with it.
pub const engine_kinds = [_]EngineKind{
    .{ .name = "engine-probe", .roots = &.{"core/engine/kinds/probe.zig"} },
    .{ .name = "engine-probe-size", .roots = &.{"core/engine/kinds/probe_size.zig"}, .upstream = &.{"engine-probe"} },
    .{ .name = "engine-probe-class", .roots = &.{"core/engine/kinds/probe_class.zig"}, .upstream = &.{"engine-probe-size"} },
    .{ .name = "test-exec", .roots = &.{"core/engine/kinds/test_exec.zig"}, .covers = &test_exec_covers, .boundary = &test_exec_boundary },
    .{ .name = "module-tokens", .roots = &.{"core/engine/kinds/module_tokens.zig"}, .covers = &module_tokens_covers },
    .{ .name = "test-report", .roots = &.{"core/engine/kinds/test_report.zig"}, .covers = &test_report_covers, .upstream = &.{"module-tokens"} },
    .{ .name = "module-syntax", .roots = &.{"core/engine/kinds/module_syntax.zig"}, .covers = &module_syntax_covers },
    .{ .name = "project-graph", .roots = &.{"core/engine/kinds/project_graph.zig"}, .covers = &project_graph_covers, .upstream = &.{"module-syntax"} },
    .{ .name = "module-interface", .roots = &.{"core/engine/kinds/module_interface.zig"}, .covers = &module_interface_covers, .upstream = &.{"module-syntax"} },
    .{ .name = "module-check", .roots = &.{"core/engine/kinds/module_check.zig"}, .covers = &module_check_covers, .upstream = &.{ "module-syntax", "module-interface" } },
    .{ .name = "noalloc-closure", .roots = &.{"core/engine/kinds/noalloc_closure.zig"}, .covers = &noalloc_closure_covers, .upstream = &.{"module-check"} },
    .{ .name = "module-passes", .roots = &.{"core/engine/kinds/module_passes.zig"}, .covers = &module_passes_covers, .upstream = &.{ "module-check", "noalloc-closure" } },
    .{ .name = "program-diagnostics", .roots = &.{"core/engine/kinds/program_diagnostics.zig"}, .covers = &program_diagnostics_covers, .upstream = &.{ "project-graph", "module-passes", "noalloc-closure" } },
    .{ .name = "unit-lower", .roots = &.{"core/engine/kinds/unit_lower.zig"}, .covers = &unit_lower_covers, .upstream = &.{ "module-check", "module-interface", "module-syntax" } },
    .{ .name = "program-facts", .roots = &.{"core/engine/kinds/program_facts.zig"}, .covers = &program_facts_covers, .upstream = &.{"unit-lower"} },
    .{ .name = "unit-optimize", .roots = &.{"core/engine/kinds/unit_optimize.zig"}, .covers = &unit_optimize_covers, .upstream = &.{"unit-lower"} },
    .{ .name = "unit-emit", .roots = &.{"core/engine/kinds/unit_emit.zig"}, .covers = &unit_emit_covers, .upstream = &.{"unit-optimize"} },
    .{ .name = "ownership-proof", .roots = &.{"core/engine/kinds/ownership_proof.zig"}, .covers = &ownership_proof_covers },
    .{ .name = "test-facts", .roots = &.{"core/engine/kinds/test_facts.zig"}, .covers = &test_facts_covers },
    .{ .name = "test-graph", .roots = &.{"core/engine/kinds/test_graph.zig"}, .covers = &test_graph_covers },
};

comptime {
    for (engine_kinds, 0..) |kind, index| {
        for (kind.upstream) |name| {
            var found = false;
            for (engine_kinds[0..index]) |earlier| found = found or std.mem.eql(u8, earlier.name, name);
            if (!found) @compileError("engine kind " ++ kind.name ++ " chains from " ++ name ++ ", which is not an earlier kind");
        }
    }
}

/// The files an engine kind's identity covers: the closure of its roots and covers, naming the front end module's members.
pub fn engineKindClosure(a: std.mem.Allocator, sources: Sources, kind: EngineKind) ClosureError![]const []const u8 {
    return engineKindClosureIn(a, .{ .bytes = &sources }, kind);
}

/// `engineKindClosure` over either form of the tree (`Corpus`).
pub fn engineKindClosureIn(a: std.mem.Allocator, corpus: Corpus, kind: EngineKind) ClosureError![]const []const u8 {
    return closureIn(a, corpus, try std.mem.concat(a, []const u8, &.{ kind.roots, kind.covers }), .{ .walk = .members, .boundary = kind.boundary });
}

/// The files an engine kind implements: the closure of its roots alone, which the no-raw-access scan reads.
pub fn engineKindCode(a: std.mem.Allocator, sources: Sources, kind: EngineKind) ClosureError![]const []const u8 {
    return engineKindCodeIn(a, .{ .bytes = &sources }, kind);
}

/// `engineKindCode` over either form of the tree (`Corpus`).
pub fn engineKindCodeIn(a: std.mem.Allocator, corpus: Corpus, kind: EngineKind) ClosureError![]const []const u8 {
    return closureIn(a, corpus, kind.roots, .{ .walk = .members, .boundary = kind.boundary });
}

/// The identity (64 lowercase hexadecimal digits) of the engine kind at `engine_kinds[index]`, given the identities of
/// the kinds before it. The closure of its roots is formed first and refuses as `closure` does.
pub fn engineKindIdentity(a: std.mem.Allocator, toolchain: Toolchain, sources: Sources, index: usize, earlier: []const []const u8) (ClosureError || DigestError)![64]u8 {
    return engineKindIdentityIn(a, toolchain, .{ .bytes = &sources }, index, earlier);
}

/// `engineKindIdentity` over either form of the tree (`Corpus`).
pub fn engineKindIdentityIn(a: std.mem.Allocator, toolchain: Toolchain, corpus: Corpus, index: usize, earlier: []const []const u8) (ClosureError || DigestError)![64]u8 {
    const kind = engine_kinds[index];
    const files = try engineKindClosureIn(a, corpus, kind);
    var chain: std.ArrayList(u8) = .empty;
    for (kind.upstream) |name| {
        for (engine_kinds[0..index], earlier) |known, identity| {
            if (!std.mem.eql(u8, known.name, name)) continue;
            if (chain.items.len != 0) try chain.append(a, ',');
            try chain.appendSlice(a, identity);
        }
    }
    const domain = try std.fmt.allocPrint(a, "{s}:{s}", .{ kind_domain, kind.name });
    // As for a stage: a kind carries an embedded product's bytes exactly when its closure reaches the product's embed.
    const narrowed: Toolchain = .{ .zig_version = toolchain.zig_version, .optimize = toolchain.optimize, .products = try reachedProducts(a, toolchain.products, files) };
    return digestChainedIn(a, domain, narrowed, chain.items, corpus, files);
}

/// SHA-256 over `domain`, the toolchain, the optimize mode, the identity of the upstream stage (empty for the first
/// stage, and then not written, so `digest` is unchanged for the compiler identity) and each listed source's path and
/// content digest. The chain makes a stage's identity move with every stage before it.
pub fn digestChained(a: std.mem.Allocator, domain: []const u8, toolchain: Toolchain, upstream: []const u8, sources: Sources, paths: []const []const u8) DigestError![64]u8 {
    return digestChainedIn(a, domain, toolchain, upstream, .{ .bytes = &sources }, paths);
}

/// `digestChained` over either form of the tree (`Corpus`).
pub fn digestChainedIn(a: std.mem.Allocator, domain: []const u8, toolchain: Toolchain, upstream: []const u8, corpus: Corpus, paths: []const []const u8) DigestError![64]u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    defer text.deinit();
    try text.writer.print("{s}\n{s}\n{s}\n", .{ domain, toolchain.zig_version, toolchain.optimize });
    if (upstream.len != 0) try text.writer.print("upstream {s}\n", .{upstream});
    for (toolchain.products) |product| try text.writer.print("product {s} {s}\n", .{ product.name, &product.digest });
    for (paths) |path| {
        const content = try corpusDigest(a, corpus, path);
        try text.writer.print("{s}\x00{s}\n", .{ path, &std.fmt.bytesToHex(content, .lower) });
    }
    var hash: [32]u8 = undefined;
    Sha.hash(text.written(), &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

fn order(_: void, a: []const u8, c: []const u8) bool {
    return std.mem.lessThan(u8, a, c);
}

// The build-identity tool's per-file record: what each production source contributed to the identities (`FileFacts`)
// the last time the tool read it, keyed by the hash of the file's bytes, so a run after a one-file edit tokenizes and
// parses only that file.
//
// The record is an accelerator, never evidence. Every run reads every source and hashes its bytes (`contentKey`,
// BLAKE3); an entry is used only for the same path and the same hash, and the facts a run records are computed from the
// very bytes it hashed. No file status (sizes, times, inodes) decides anything: a write through a shared memory mapping,
// a restored modification time or a write within one timestamp tick changes the bytes, and so the key. What the record
// saves is tokenizing and parsing (D-DL3-7).
//
// A record is bound to the tool that wrote it (`RecordHeader.tool`, a digest of the tool's sources and the toolchain that
// compiled it) and to one tree (`RecordHeader.root`, the absolute path of `src`). A record of another tool or tree, or
// one that is truncated, damaged or of another format, decodes to nothing and the tool analyzes every file. It ends with
// the SHA-256 of everything before it, and the tool replaces it by renaming a complete new file over it, so two runs at
// once each read a whole record.

/// One file's entry: the hash of the bytes it was computed from (`contentKey`) and what they contribute.
pub const RecordEntry = struct { content: [32]u8, facts: FileFacts };

/// A record's entries, keyed by path relative to `src`.
pub const RecordEntries = std.array_hash_map.String(RecordEntry);

/// What a record must have been written for: the tool (`tool`) and the tree (`root`, the absolute path of `src`).
pub const RecordHeader = struct { tool: [32]u8, root: []const u8 };

/// The key of a file's entry: the BLAKE3 hash of its bytes.
pub fn contentKey(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &out, .{});
    return out;
}

/// The largest record the tool reads; a larger file is ignored.
pub const max_record_bytes: usize = 256 << 20;

const record_magic = "selka build-identity record\n";
/// The record's layout; a record of another layout is ignored.
pub const record_format_version: u32 = 2;

/// True when `entry` may stand for a file whose bytes hash to `content`: it was computed from the same bytes.
pub fn recordServes(entry: RecordEntry, content: [32]u8) bool {
    return std.mem.eql(u8, &entry.content, &content);
}

/// The digest that binds a record to the tool: the format version, the toolchain the tool was compiled with (its
/// tokenizer and parser decide the facts) and the bytes of every source of the tool.
pub fn recordToolKey(zig_version: []const u8, tool_sources: []const []const u8) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var header: [4]u8 = undefined;
    std.mem.writeInt(u32, &header, record_format_version, .little);
    hash.update(record_magic);
    hash.update(&header);
    frameRecordKey(&hash, zig_version);
    for (tool_sources) |text| frameRecordKey(&hash, text);
    return hash.finalResult();
}

fn frameRecordKey(hash: *std.crypto.hash.sha2.Sha256, text: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, text.len, .little);
    hash.update(&length);
    hash.update(text);
}

/// The record holding `entries` for `header`, ending with the SHA-256 of everything before it.
pub fn encodeRecord(a: std.mem.Allocator, header: RecordHeader, entries: *const RecordEntries) error{OutOfMemory}![]u8 {
    var out: RecordOut = .{ .a = a };
    try out.list.appendSlice(a, record_magic);
    try out.int(u32, record_format_version);
    try out.list.appendSlice(a, &header.tool);
    try out.bytes(header.root);
    try out.int(u32, @intCast(entries.count()));
    for (entries.keys(), entries.values()) |path, entry| {
        try out.bytes(path);
        try out.list.appendSlice(a, &entry.content);
        const facts = entry.facts;
        try out.list.appendSlice(a, &facts.digest);
        try out.int(u8, if (facts.refusal) |refusal| @backingInt(refusal) else 0);
        try out.int(u8, @backingInt(facts.member_use));
        try out.strings(facts.edges);
        try out.strings(facts.member_edges);
        try out.strings(facts.member_names);
        try out.int(u32, @intCast(facts.member_table.len));
        for (facts.member_table) |pair| {
            try out.bytes(pair[0]);
            try out.bytes(pair[1]);
        }
    }
    var checksum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(out.list.items, &checksum, .{});
    try out.list.appendSlice(a, &checksum);
    return out.list.items;
}

/// The entries of `record` when it is a whole record of this format written for `header`, else null. The entries'
/// strings point into `record`, which must outlive them.
pub fn decodeRecord(a: std.mem.Allocator, record: []const u8, header: RecordHeader) error{OutOfMemory}!?RecordEntries {
    if (record.len < record_magic.len + 32) return null;
    const body = record[0 .. record.len - 32];
    var checksum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(body, &checksum, .{});
    if (!std.mem.eql(u8, &checksum, record[record.len - 32 ..])) return null;
    var in: RecordIn = .{ .data = body };
    if (!std.mem.eql(u8, in.take(record_magic.len) orelse return null, record_magic)) return null;
    if ((in.int(u32) orelse return null) != record_format_version) return null;
    if (!std.mem.eql(u8, in.take(32) orelse return null, &header.tool)) return null;
    if (!std.mem.eql(u8, in.bytes() orelse return null, header.root)) return null;
    const count = in.int(u32) orelse return null;
    var entries: RecordEntries = .empty;
    for (0..count) |_| {
        const path = in.bytes() orelse return null;
        const entry = (try in.entry(a)) orelse return null;
        const slot = try entries.getOrPut(a, path);
        if (slot.found_existing) return null;
        slot.value_ptr.* = entry;
    }
    if (in.at != body.len) return null;
    return entries;
}

const RecordOut = struct {
    a: std.mem.Allocator,
    list: std.ArrayList(u8) = .empty,

    fn int(out: *RecordOut, comptime T: type, value: T) error{OutOfMemory}!void {
        var buffer: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buffer, value, .little);
        try out.list.appendSlice(out.a, &buffer);
    }

    fn bytes(out: *RecordOut, text: []const u8) error{OutOfMemory}!void {
        try out.int(u32, @intCast(text.len));
        try out.list.appendSlice(out.a, text);
    }

    fn strings(out: *RecordOut, texts: []const []const u8) error{OutOfMemory}!void {
        try out.int(u32, @intCast(texts.len));
        for (texts) |text| try out.bytes(text);
    }
};

const RecordIn = struct {
    data: []const u8,
    at: usize = 0,

    fn take(in: *RecordIn, length: usize) ?[]const u8 {
        if (length > in.data.len - in.at) return null;
        defer in.at += length;
        return in.data[in.at..][0..length];
    }

    fn int(in: *RecordIn, comptime T: type) ?T {
        const raw = in.take(@sizeOf(T)) orelse return null;
        return std.mem.readInt(T, raw[0..@sizeOf(T)], .little);
    }

    fn bytes(in: *RecordIn) ?[]const u8 {
        return in.take(in.int(u32) orelse return null);
    }

    fn strings(in: *RecordIn, a: std.mem.Allocator) error{OutOfMemory}!?[]const []const u8 {
        const count = in.int(u32) orelse return null;
        // Each string takes at least its four-byte length, so a count the rest cannot hold is damage.
        if (count > (in.data.len - in.at) / 4) return null;
        const out = try a.alloc([]const u8, count);
        for (out) |*slot| slot.* = in.bytes() orelse return null;
        return out;
    }

    fn entry(in: *RecordIn, a: std.mem.Allocator) error{OutOfMemory}!?RecordEntry {
        var result: RecordEntry = .{
            .content = (in.take(32) orelse return null)[0..32].*,
            .facts = .{ .digest = (in.take(16) orelse return null)[0..16].* },
        };
        result.facts.refusal = switch (in.int(u8) orelse return null) {
            0 => null,
            1 => .parse_failed,
            2 => .non_literal_import,
            3 => .unknown_module,
            else => return null,
        };
        result.facts.member_use = switch (in.int(u8) orelse return null) {
            0 => .none,
            1 => .members,
            2 => .whole,
            else => return null,
        };
        result.facts.edges = (try in.strings(a)) orelse return null;
        result.facts.member_edges = (try in.strings(a)) orelse return null;
        result.facts.member_names = (try in.strings(a)) orelse return null;
        const pairs = in.int(u32) orelse return null;
        if (pairs > (in.data.len - in.at) / 8) return null;
        const table = try a.alloc([2][]const u8, pairs);
        for (table) |*pair| pair.* = .{ in.bytes() orelse return null, in.bytes() orelse return null };
        result.facts.member_table = table;
        return result;
    }
};

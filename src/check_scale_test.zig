//! Check-at-scale coverage: the lexer-free paths the per-edit check relies on
//! agree exactly with the full lexer, and a check that stands summaries in for
//! unchanged bodies reports exactly what a check without them reports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const diagnostic = language.diagnostic;
const summary = language.semantic_summary;
const File = language.embedded_project.File;
const semantic_key = @import("semantic_key.zig");

const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

/// What one project check did and reported.
const Outcome = struct {
    /// Bodies actually checked.
    checked: usize,
    /// Bodies (or, for a lowering command, body facts) a summary stood in for
    /// in the final check; zero after a repeat in full.
    stood_in: usize,
    /// Every diagnostic rendered in order; owned by `t.allocator`.
    diagnostics: []u8,
    /// Every checked function's published effect and mutation facts, one line
    /// each; owned by `t.allocator` and empty when the check failed.
    facts: []u8,
    /// The encoded summaries the check produced, or null when it published none.
    summaries: ?[]u8,

    fn deinit(self: Outcome) void {
        t.allocator.free(self.diagnostics);
        t.allocator.free(self.facts);
        if (self.summaries) |payload| t.allocator.free(payload);
    }
};

/// How a check runs: as `check` (summaries stand in for bodies) or as a command
/// that lowers the program (every body checked, summaries stand in for facts).
const Mode = enum { check, lowering };

/// Check the project `files` (entry module `main`) with the given previous
/// summaries, exactly as `check` or a lowering command does through a cache.
fn checkProject(files: []const File, previous: ?[]const u8, mode: Mode) !Outcome {
    var provider: Files = .{ .entries = files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    var cache = language.semantic_cache.Cache.init(t.allocator, 0);
    defer cache.deinit();
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    var request: summary.Request = .{ .facts_only = mode == .lowering };
    var decoded: summary.Index = .{};
    if (previous) |payload| {
        decoded = summary.decode(arena_state.allocator(), payload).?;
        request.previous = &decoded;
    }
    cache.context.summaries = &request;
    compilation.checkWithCache(&cache) catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    var rendered: std.Io.Writer.Allocating = .init(t.allocator);
    defer rendered.deinit();
    for (compilation.diagnostics.items.items) |item| {
        const text = try item.render(arena_state.allocator(), compilation.src);
        try rendered.writer.writeAll(text);
    }
    var facts: std.Io.Writer.Allocating = .init(t.allocator);
    defer facts.deinit();
    if (compilation.program) |program| for (program.functions) |function| {
        try facts.writer.print("{s} effects={d} mutates={any} writes={} external={} origin={s}\n", .{
            function.name,
            function.policy.effects,
            function.signature.mutates,
            function.signature.inferred.writes,
            function.signature.inferred.external,
            @tagName(function.signature.return_origin),
        });
    };
    return .{
        .checked = cache.statistics.checked,
        .stood_in = request.stood_in,
        .diagnostics = try rendered.toOwnedSlice(),
        .facts = try facts.toOwnedSlice(),
        .summaries = if (request.produced) |produced| try summary.encode(t.allocator, produced) else null,
    };
}

/// Check `changed` in `mode` with the summaries of a successful `check` of
/// `original`, and again with none. Both outcomes are returned for comparison.
fn checkAfterEditAs(original: []const File, changed: []const File, mode: Mode) !struct { warm: Outcome, cold: Outcome } {
    const seed = try checkProject(original, null, .check);
    defer seed.deinit();
    const warm = try checkProject(changed, seed.summaries.?, mode);
    errdefer warm.deinit();
    const cold = try checkProject(changed, null, mode);
    return .{ .warm = warm, .cold = cold };
}

/// `checkAfterEditAs` for `check` itself.
fn checkAfterEdit(original: []const File, changed: []const File) !struct { warm: Outcome, cold: Outcome } {
    const outcome = try checkAfterEditAs(original, changed, .check);
    return .{ .warm = outcome.warm, .cold = outcome.cold };
}

const lib_source =
    \\module lib
    \\
    \\
    \\public record Acc:
    \\    total: int
    \\    count: int
    \\
    \\
    \\public def gather(n: int) -> int:
    \\    xs: list[int] = []
    \\    for k in range(n):
    \\        xs.append(k * 2)
    \\    acc = Acc(total=0, count=0)
    \\    for x in xs:
    \\        acc = Acc(total=acc.total + x, count=acc.count + 1)
    \\    return acc.total
    \\
    \\
    \\public def spread(n: int) -> int:
    \\    ys: list[int] = [n, n + 1]
    \\    unused = 3
    \\    return ys[0] + ys[1]
    \\
    \\
    \\public def plain(n: int) -> int:
    \\    return n + 1
    \\
;
const mid_source =
    \\module mid
    \\import lib
    \\
    \\
    \\public def twice(n: int) -> int:
    \\    return lib.gather(n) + lib.gather(n + 1)
    \\
    \\
    \\public def bounded(n: int) -> int noalloc:
    \\    return lib.plain(n) * 2
    \\
    \\
    \\public def count(n: int) -> int:
    \\    zs: list[int] = [n]
    \\    return lib.spread(zs[0])
    \\
;
const main_source =
    \\module main
    \\import mid
    \\
    \\
    \\def main() -> int:
    \\    return mid.twice(3) + mid.bounded(2) + mid.count(1)
    \\
;

fn projectFiles(lib: []const u8) [3]File {
    return .{
        .{ .path = "main.my", .bytes = main_source },
        .{ .path = "mid.my", .bytes = mid_source },
        .{ .path = "lib.my", .bytes = lib },
    };
}

/// `lib_source` with one occurrence of `from` replaced by `to`.
fn libEdited(comptime from: []const u8, comptime to: []const u8) []const u8 {
    const at = comptime std.mem.indexOf(u8, lib_source, from).?;
    return lib_source[0..at] ++ to ++ lib_source[at + from.len ..];
}

// spec: CHECK-SUMMARY-1
test "a body edit checks only that body and reports what a check without summaries reports" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("xs.append(k * 2)", "xs.append(k * 3)"));
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // The edited body and the entry point are checked; the other five stand in.
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expectEqual(@as(usize, 5), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 7), outcome.cold.checked);
    // The stood-in `spread` still reports its unused binding.
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "W_UNUSED_BINDING") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

// spec-case: CHECK-SUMMARY-1
test "an unchanged project stands in every body but the entry point" {
    const original = projectFiles(lib_source);
    const outcome = try checkAfterEdit(&original, &original);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 1), outcome.warm.checked);
    try t.expectEqual(@as(usize, 6), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec-case: CHECK-SUMMARY-1
test "a record shape edit re-checks every body that uses the record" {
    const original = projectFiles(lib_source);
    // A new defaulted field changes `Acc`'s shape but keeps every use valid.
    const widened = projectFiles(libEdited("    count: int\n", "    count: int\n    note: int = 0\n"));
    const outcome = try checkAfterEdit(&original, &widened);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `gather` builds `Acc`; its callers' contexts name only its signature.
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // A field type edit breaks the body that builds the record: the same error.
    const retyped = projectFiles(libEdited("    total: int\n", "    total: str\n"));
    const broken = try checkAfterEdit(&original, &retyped);
    defer broken.warm.deinit();
    defer broken.cold.deinit();
    try t.expect(broken.warm.summaries == null);
    try t.expect(std.mem.indexOf(u8, broken.warm.diagnostics, "error[") != null);
    try t.expectEqualStrings(broken.cold.diagnostics, broken.warm.diagnostics);
}

// spec-case: CHECK-SUMMARY-1
test "a callee whose inferred effects change makes the check repeat in full" {
    const original = projectFiles(lib_source);
    // `plain` now allocates, which the stood-in `noalloc` caller `bounded` forbids.
    const allocating = projectFiles(libEdited("    return n + 1\n", "    ws: list[int] = [n]\n    return ws[0] + 1\n"));
    const outcome = try checkAfterEdit(&original, &allocating);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 0), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "E_EFFECT_BOUND") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// A signature that names no identifier (not even a return type) leaves
// nothing module-scoped in its fingerprint but the defining module itself.
const alpha_source =
    \\module alpha
    \\
    \\
    \\public def value():
    \\    pass
    \\
;
// The same declaration text as `alpha.value`, but its body allocates.
const beta_source =
    \\module beta
    \\
    \\
    \\public def value():
    \\    xs: list[int] = [1]
    \\    assert xs[0] == 1
    \\
;

fn aliasProject(user: []const u8) [4]File {
    return .{
        .{ .path = "main.my", .bytes = "module main\nimport user\nimport beta\n\n\ndef main() -> int:\n    user.bounded()\n    beta.value()\n    return 0\n" },
        .{ .path = "user.my", .bytes = user },
        .{ .path = "alpha.my", .bytes = alpha_source },
        .{ .path = "beta.my", .bytes = beta_source },
    };
}

// spec: SEMANTIC-KEY-IDENTITY-1
test "an import alias retargeted to an identical declaration elsewhere re-checks its users" {
    const through_alpha = aliasProject("module user\nimport alpha as source\n\n\npublic def bounded() -> None noalloc:\n    source.value()\n");
    const through_beta = aliasProject("module user\nimport beta as source\n\n\npublic def bounded() -> None noalloc:\n    source.value()\n");
    const outcome = try checkAfterEdit(&through_alpha, &through_beta);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `bounded`'s region and the callee's text are unchanged, but the callee
    // is another declaration, which allocates under `noalloc`.
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "E_EFFECT_BOUND") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec-case: SEMANTIC-KEY-IDENTITY-1
test "deprecating a callee in another module warns at its stood-in callers" {
    const original = projectFiles(lib_source);
    const deprecated = projectFiles(libEdited("public def plain(", "@deprecated(\"use twice\")\npublic def plain("));
    const outcome = try checkAfterEdit(&original, &deprecated);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "W_DEPRECATED") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec: CHECK-SUMMARY-2
test "a lowering command checks every body and stands summaries in only for their facts" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("xs.append(k * 2)", "xs.append(k * 3)"));
    const outcome = try checkAfterEditAs(&original, &changed, .lowering);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // Every body is checked, because lowering needs its tree; the five
    // unchanged bodies' effect and mutation facts come from their summaries.
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expectEqual(@as(usize, 5), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // It had summaries to stand in, so it publishes none; without any it does.
    try t.expect(outcome.warm.summaries == null);
    try t.expect(outcome.cold.summaries != null);
}

// spec-case: CHECK-SUMMARY-2
test "a lowering command whose edit changes a callee's facts publishes the facts it computed in full" {
    const original = projectFiles(lib_source);
    const allocating = projectFiles(libEdited("    return n + 1\n", "    ws: list[int] = [n]\n    return ws[0] + 1\n"));
    const outcome = try checkAfterEditAs(&original, &allocating, .lowering);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 0), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // The edit breaks `bounded`'s `noalloc`, so nothing is published.
    try t.expect(outcome.warm.summaries == null);
    // `spread` stops allocating: a changed fact in a still-valid program. The
    // command repeats in full and publishes, so the next one stands in again.
    const pure = projectFiles(libEdited("    ys: list[int] = [n, n + 1]\n    unused = 3\n    return ys[0] + ys[1]\n", "    unused = 3\n    return n + n + 1\n"));
    const repeated = try checkAfterEditAs(&original, &pure, .lowering);
    defer repeated.warm.deinit();
    defer repeated.cold.deinit();
    try t.expectEqual(@as(usize, 0), repeated.warm.stood_in);
    try t.expectEqual(@as(usize, 7), repeated.warm.checked);
    try t.expect(repeated.warm.summaries != null);
    try t.expectEqualStrings(repeated.cold.facts, repeated.warm.facts);
    try t.expectEqualStrings(repeated.cold.diagnostics, repeated.warm.diagnostics);
}

/// A recall over one earlier preparation's own names, or over wrong digests.
const TestRecall = struct {
    prepared: *const semantic_key.Prepared,
    corrupt: bool,

    fn names(context: *const anyopaque, key: []const u8, digest: [32]u8) ?[]const semantic_key.Name {
        const self: *const TestRecall = @ptrCast(@alignCast(context));
        for (self.prepared.keys, 0..) |candidate, index| {
            if (!std.mem.eql(u8, candidate, key)) continue;
            var stored = self.prepared.recalled.digests[index];
            if (self.corrupt) stored[0] ^= 1;
            if (!std.mem.eql(u8, &stored, &digest)) return null;
            return self.prepared.recalled.names[index];
        }
        return null;
    }
};

/// Prepare the dependency keys of the lib project with `recall`.
fn prepareKeys(arena: std.mem.Allocator, recall: ?semantic_key.Recall) !semantic_key.Prepared {
    const files = projectFiles(lib_source);
    var provider: Files = .{ .entries = &files };
    const project = try arena.create(language.project.Project);
    project.* = language.project.Project.init(arena);
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const index = try arena.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    const compilation = try language.project_compile.Compilation.init(index);
    return semantic_key.prepare(arena, compilation.src, compilation.syntax, .{ .build = "test", .mutation = "mutation-v1" }, index, recall);
}

// spec: CHECK-SCALE-KEYS-1
test "dependency keys resolved from recalled names equal those from walking the syntax" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const walked = try prepareKeys(arena, null);
    try t.expect(walked.recalled.names.len == walked.keys.len);
    var matching: TestRecall = .{ .prepared = &walked, .corrupt = false };
    const recalled = try prepareKeys(arena, .{ .context = &matching, .names = TestRecall.names });
    try t.expectEqual(walked.contexts.len, recalled.contexts.len);
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.contexts), std.mem.sliceAsBytes(recalled.contexts));
    // A recall whose digest no longer matches the region is ignored.
    var stale: TestRecall = .{ .prepared = &walked, .corrupt = true };
    const fallback = try prepareKeys(arena, .{ .context = &stale, .names = TestRecall.names });
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.contexts), std.mem.sliceAsBytes(fallback.contexts));
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.recalled.digests), std.mem.sliceAsBytes(fallback.recalled.digests));
}

// spec-case: CHECK-SCALE-LEX-1
test "header discovery keeps its diagnostics and import facts after its scratch tokens are reset" {
    // Every module's tokens are released before the next module is read, so
    // what discovery keeps must live in the project arena.
    const files = [_]File{
        .{ .path = "main.my", .bytes = "module main\nimport lib\nimport unused\n\n\ndef main() -> int:\n    return lib.value()\n" },
        .{ .path = "lib.my", .bytes = "module lib\n\n\npublic def value() -> int:\n    return 1\n" },
        .{ .path = "unused.my", .bytes = "module unused\n\n\npublic def other() -> int:\n    return 2\n" },
    };
    var provider: Files = .{ .entries = &files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const imports = project.modules.items[0].imports;
    try t.expectEqual(@as(usize, 2), imports.len);
    try t.expectEqualStrings("lib", imports[0].name);
    try t.expect(imports[0].seen);
    try t.expect(!imports[1].seen);
    // A lexical failure in an imported module reports its located message.
    const broken = [_]File{
        .{ .path = "main.my", .bytes = "module main\nimport lib\n\n\ndef main() -> int:\n    return lib.value()\n" },
        .{ .path = "lib.my", .bytes = "module lib\n\n\npublic def value() -> int:\n    return 1 $ 2\n" },
    };
    var broken_provider: Files = .{ .entries = &broken };
    var failed = language.project.Project.init(t.allocator);
    defer failed.deinit();
    try t.expectError(error.SourceError, failed.load(.{ .context = &broken_provider, .read = Files.read }, "main", .{}));
    try t.expectEqualStrings("E_TOKEN", failed.problem.?.code);
    try t.expectEqualStrings("unexpected character in source", failed.problem.?.message);
}

// spec-case: CACHE-CHECKSUM-1
test "cached syntax decodes in place and a damaged entry is still a counted miss" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var cache = language.frontend_cache.Cache.init(t.allocator, t.io, root, "check-scale-identity");
    const files = projectFiles(lib_source);
    var provider: Files = .{ .entries = &files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);
    const hit = (try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)).?;
    try t.expectEqual(index.units[0].syntax.nodes.items.len, hit.nodes.items.len);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.hits);
    const path = try cache.entryPath(cache.syntaxKey(module.src, module.header.body_start));
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .limited(1 << 24));
    defer t.allocator.free(bytes);
    bytes[bytes.len - 9] ^= 0x40;
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    try t.expect((try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)) == null);
    try t.expectEqual(@as(usize, 1), cache.statistics.damaged);
}

// `user` reaches `shapes.Inner` only through a list element, a dictionary
// value, an Option payload and a call's return type, never by naming it.
const reach_shapes =
    \\module shapes
    \\public record Inner:
    \\    x: int
    \\public record Outer:
    \\    items: list[Inner]
    \\    table: dict[str, Inner]
    \\    maybe: Option[Inner]
    \\public def make() -> Outer:
    \\    items: list[Inner] = []
    \\    items.append(Inner(x=1))
    \\    table: dict[str, Inner] = {}
    \\    return Outer(items=items, table=table, maybe=None)
    \\
;
const reach_user =
    \\module user
    \\import shapes
    \\public def first(o: shapes.Outer) -> int:
    \\    v = o.items[0]
    \\    return v.x
    \\public def looked(o: shapes.Outer) -> int:
    \\    return o.table["k"].x
    \\public def maybe(o: shapes.Outer) -> int:
    \\    match o.maybe:
    \\        case Some(v):
    \\            return v.x
    \\        case None:
    \\            return 0
    \\public def chained() -> int:
    \\    return shapes.make().items[0].x
    \\
;

fn reachFiles(shapes: []const u8) [3]File {
    return .{
        .{ .path = "main.my", .bytes = "module main\nimport shapes\nimport user\ndef main() -> int:\n    o = shapes.make()\n    return user.first(o) + user.looked(o) + user.maybe(o) + user.chained()\n" },
        .{ .path = "user.my", .bytes = reach_user },
        .{ .path = "shapes.my", .bytes = shapes },
    };
}

/// `reach_shapes` with each `from` replaced by the matching `to`.
fn shapesEdited(comptime edits: []const [2][]const u8) []const u8 {
    comptime var text: []const u8 = reach_shapes;
    inline for (edits) |edit| {
        const at = comptime std.mem.indexOf(u8, text, edit[0]).?;
        text = text[0..at] ++ edit[1] ++ text[at + edit[0].len ..];
    }
    return text;
}

// spec: SEMANTIC-KEY-TRANSITIVE-1
test "renaming a field reached only through list, dict, Option and return types re-checks every user" {
    const original = reachFiles(reach_shapes);
    const renamed = reachFiles(shapesEdited(&.{ .{ "    x: int", "    y: int" }, .{ "Inner(x=1)", "Inner(y=1)" } }));
    const outcome = try checkAfterEdit(&original, &renamed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // All four `user` bodies read the renamed field: none may stand in.
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, outcome.cold.diagnostics, "E_UNKNOWN_FIELD"));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    const lowering = try checkAfterEditAs(&original, &renamed, .lowering);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqualStrings(lowering.cold.diagnostics, lowering.warm.diagnostics);
}

// spec-case: SEMANTIC-KEY-TRANSITIVE-1
test "retyping a field reached only through element and return types re-checks every user" {
    const original = reachFiles(reach_shapes);
    const retyped = reachFiles(shapesEdited(&.{ .{ "    x: int", "    x: float" }, .{ "Inner(x=1)", "Inner(x=1.0)" } }));
    const outcome = try checkAfterEdit(&original, &retyped);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, outcome.cold.diagnostics, "error["));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // A field type edit that keeps every body valid still re-checks them, and
    // the facts a lowering command publishes are the cold ones.
    const widened = reachFiles(shapesEdited(&.{ .{ "    x: int", "    x: int\n    tags: list[int]" }, .{ "Inner(x=1)", "Inner(x=1, tags=[])" } }));
    const lowering = try checkAfterEditAs(&original, &widened, .lowering);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqualStrings(lowering.cold.facts, lowering.warm.facts);
    try t.expectEqualStrings(lowering.cold.diagnostics, lowering.warm.diagnostics);
}

// spec: CHECK-SHAPES-1
test "a summary whose touched record shape no longer matches is not stood in" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const files = reachFiles(reach_shapes);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    const decoded = summary.decode(arena, seed.summaries.?).?;
    try t.expect(decoded.records.len != 0);
    // Pretend `first` was checked against a different `Inner`.
    const changed = try arena.dupe(summary.Summary, decoded.summaries);
    const first = decoded.find("fn\x1fuser\x1f\x1ffirst").?;
    try t.expect(changed[first].stubbable and changed[first].uses.records.len != 0);
    changed[first].uses.shape[0] ^= 1;
    const tampered = try summary.encode(arena, .{ .records = decoded.records, .summaries = changed });
    const warm = try checkProject(&files, tampered, .check);
    defer warm.deinit();
    const untouched = try checkProject(&files, seed.summaries.?, .check);
    defer untouched.deinit();
    try t.expectEqual(untouched.stood_in - 1, warm.stood_in);
    try t.expectEqual(untouched.checked + 1, warm.checked);
    try t.expectEqualStrings(untouched.diagnostics, warm.diagnostics);
}

// spec-case: CHECK-SHAPES-1
test "a retained checked tree whose touched record shape no longer matches misses" {
    const files = reachFiles(reach_shapes);
    var cache = language.semantic_cache.Cache.init(t.allocator, 16 * 1024 * 1024);
    defer cache.deinit();
    try checkRetained(&files, &cache);
    try t.expect(cache.entries.len != 0);
    try checkRetained(&files, &cache);
    const reason = @backingInt(language.semantic_cache.MissReason.record_shape_changed);
    try t.expectEqual(@as(usize, 0), cache.statistics.misses[reason]);
    corruptRecordShapes(&cache);
    const reused_before = cache.statistics.reused;
    try checkRetained(&files, &cache);
    try t.expect(cache.statistics.misses[reason] != 0);
    try t.expectEqual(reused_before, cache.statistics.reused);
}

/// Pretend every retained tree was checked against different records.
fn corruptRecordShapes(cache: *language.semantic_cache.Cache) void {
    for (cache.entries) |entry| for (@constCast(entry.meta.record_refs)) |*reference| {
        reference.shape[0] ^= 1;
    };
}

/// Check the project `files` through the retained checked-tree path.
fn checkRetained(files: []const File, cache: *language.semantic_cache.Cache) !void {
    var provider: Files = .{ .entries = files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.checkWithCache(cache);
}

// spec-case: CHECK-SUMMARY-1
test "stored summaries round-trip and a foreign payload is refused" {
    const original = projectFiles(lib_source);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    try t.expectEqual(@as(usize, 7), decoded.summaries.len);
    try t.expect(decoded.find("fn\x1fmain\x1f\x1fmain") != null);
    try t.expect(!decoded.summaries[decoded.find("fn\x1fmain\x1f\x1fmain").?].stubbable);
    try t.expect(summary.decode(arena_state.allocator(), seed.summaries.?[0 .. seed.summaries.?.len - 1]) == null);
    try t.expect(summary.decode(arena_state.allocator(), "not a summary table") == null);
}

/// Count spellings whose lexer-free answer differs from `qualifiedName(lex(...))`.
/// A spelling the fast path defers (`slow`) is not compared: the caller lexes it.
fn quickDisagreements(spellings: []const []const u8) !usize {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var count: usize = 0;
    for (spellings) |text| {
        const quick = lexer.quickQualifiedName(text);
        if (quick == .slow) continue;
        var sink: diagnostic.Sink = .{ .allocator = arena };
        const tokens = lexer.lex(arena, text, &sink) catch {
            count += 1;
            continue;
        };
        const slow = lexer.qualifiedName(text, tokens);
        const same = switch (quick) {
            .slow => unreachable,
            .none => slow == null,
            .name => |name| if (slow) |expected|
                std.mem.eql(u8, name.name, expected.name) and
                    (name.alias == null) == (expected.alias == null) and
                    std.mem.eql(u8, name.alias orelse "", expected.alias orelse "")
            else
                false,
        };
        if (!same) count += 1;
    }
    return count;
}

/// Lex `bytes` and return its token tags, owned by `arena`.
fn tags(arena: std.mem.Allocator, bytes: []const u8) ![]lexer.Tag {
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const tokens = try lexer.lex(arena, bytes, &sink);
    const out = try arena.alloc(lexer.Tag, tokens.len);
    for (tokens, out) |token, *tag| tag.* = token.tag;
    return out;
}

// spec: CHECK-SCALE-LEX-1
test "a dotted reference spelling normalizes without the lexer exactly as with it" {
    const spellings = [_][]const u8{
        "value",         "m239.f239_00", "shared.units.area", "_hidden.x9", "len",     "xs.len",    "a.b.len", "True",
        "a.None",        "push",         "List",              "contains",   "f64_add", "a.f64_add", "a . b",   "a::b",
        "9lives",        "a..b",         ".a",                "a.",         "",        "x#y",
        "é",
        "Domain.member",
    };
    try t.expectEqual(@as(usize, 0), try quickDisagreements(&spellings));
    try t.expectEqualStrings("m239", lexer.quickQualifiedName("m239.f239_00").name.alias.?);
    try t.expectEqualStrings("f239_00", lexer.quickQualifiedName("m239.f239_00").name.name);
    try t.expectEqualStrings("shared.units", lexer.quickQualifiedName("shared.units.area").name.alias.?);
    try t.expect(lexer.quickQualifiedName("xs.len") == .none);
    try t.expect(lexer.quickQualifiedName("a . b") == .slow);
    // A removed spelling is left to the lexer, which alone reports it.
    try t.expect(lexer.quickQualifiedName("a.f64_add") == .slow);
}

// spec-case: CHECK-SCALE-LEX-1
test "reserved words removed spellings and layout lex exactly as before the keyword map" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const words = try tags(arena, "def class True False None and or not while whilex len push List __float_sqrt assert");
    const expected = [_]lexer.Tag{
        .kw_def, .kw_class, .kw_true, .kw_false, .kw_none, .and_and, .or_or, .bang, .kw_while, .ident, .kw_len, .ident, .ident, .kw_f64_sqrt, .kw_assert, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &expected, words);
    try t.expect(!lexer.isIdentifier("while"));
    try t.expect(lexer.isIdentifier("whilex"));
    var sink: diagnostic.Sink = .{ .allocator = arena };
    try t.expectError(error.SourceError, lexer.lex(arena, "x = f64_add", &sink));
    try t.expectEqualStrings("E_REMOVED_SPELLING", sink.items.items[0].code);
    // A multi-line string ends its line; the next token opens a new statement.
    const layout = try tags(arena, "def f() -> str:\n    s = '''a\nb'''\n    return s\nx = 1\n");
    const layout_expected = [_]lexer.Tag{
        .kw_def, .ident, .lparen, .rparen, .arrow, .ident, .indent, .ident, .equal, .bytes, .kw_return, .ident, .dedent, .ident, .equal, .integer, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &layout_expected, layout);
}

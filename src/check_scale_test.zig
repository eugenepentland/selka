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
    /// Bodies a summary stood in for in the final check (zero after a retry).
    stood_in: usize,
    /// Every diagnostic rendered in order; owned by `t.allocator`.
    diagnostics: []u8,
    /// The encoded summaries the check produced, or null when it failed.
    summaries: ?[]u8,

    fn deinit(self: Outcome) void {
        t.allocator.free(self.diagnostics);
        if (self.summaries) |payload| t.allocator.free(payload);
    }
};

/// Check the project `files` (entry module `main`) with the given previous
/// summaries, exactly as `check` does through a semantic cache.
fn checkProject(files: []const File, previous: ?[]const u8) !Outcome {
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
    var request: summary.Request = .{};
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
    return .{
        .checked = cache.statistics.checked,
        .stood_in = request.stood_in,
        .diagnostics = try rendered.toOwnedSlice(),
        .summaries = if (request.produced) |produced| try summary.encode(t.allocator, produced) else null,
    };
}

/// Check `changed` with the summaries of a successful check of `original`, and
/// check it again with none. Both outcomes are returned for comparison.
fn checkAfterEdit(original: []const File, changed: []const File) !struct { warm: Outcome, cold: Outcome } {
    const seed = try checkProject(original, null);
    defer seed.deinit();
    const warm = try checkProject(changed, seed.summaries.?);
    errdefer warm.deinit();
    const cold = try checkProject(changed, null);
    return .{ .warm = warm, .cold = cold };
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

// spec-case: CHECK-SUMMARY-1
test "stored summaries round-trip and a foreign payload is refused" {
    const original = projectFiles(lib_source);
    const seed = try checkProject(&original, null);
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

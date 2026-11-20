//! Structured fixes: the exact edits diagnostics carry, how `diagnostic-v1`
//! publishes them, and that applying them repairs the source they came from.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const output = language.diagnostic_output;
const File = language.embedded_project.File;
const Value = std.json.Value;
const fixture_path = "fixes.selka";
const marker_code = @import("origins.zig").mutation_marker_code;

fn field(value: Value, name: []const u8) Value {
    return value.object.get(name).?;
}

/// What one check reported: every diagnostic code in order, how many carried a
/// fix, and the source with every carried fix applied. All slices are owned by
/// the testing allocator and released by `deinit`.
const Round = struct {
    codes: []const []const u8,
    fixes: usize,
    fixed: []u8,
    passed: bool,

    fn deinit(self: Round) void {
        for (self.codes) |code| t.allocator.free(code);
        t.allocator.free(self.codes);
        t.allocator.free(self.fixed);
    }

    fn count(self: Round, code: []const u8) usize {
        var found: usize = 0;
        for (self.codes) |item| found += @intFromBool(std.mem.eql(u8, item, code));
        return found;
    }
};

/// Check one single-file program and apply every fix its diagnostics carry,
/// as `selka fix` does: identical edits once, from the end of the file back.
fn round(source: []const u8) !Round {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    const passed = if (c.check()) true else |err| switch (err) {
        error.SourceError => false,
        else => return err,
    };
    var codes: std.ArrayList([]const u8) = .empty;
    var edits: std.ArrayList(language.diagnostic.Edit) = .empty;
    defer edits.deinit(t.allocator);
    var fixes: usize = 0;
    for (c.diagnostics.items) |item| {
        try codes.append(t.allocator, try t.allocator.dupe(u8, item.code));
        const fix = item.provenance.fix orelse continue;
        fixes += 1;
        var index: usize = 0;
        while (index < fix.count()) : (index += 1) try addEdit(&edits, fix.at(index));
    }
    std.mem.sort(language.diagnostic.Edit, edits.items, {}, later);
    var fixed: std.ArrayList(u8) = .empty;
    try fixed.appendSlice(t.allocator, source);
    for (edits.items) |edit| try fixed.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return .{ .codes = try codes.toOwnedSlice(t.allocator), .fixes = fixes, .fixed = try fixed.toOwnedSlice(t.allocator), .passed = passed };
}

fn addEdit(edits: *std.ArrayList(language.diagnostic.Edit), edit: language.diagnostic.Edit) !void {
    for (edits.items) |other| {
        if (other.span.start == edit.span.start and other.span.end == edit.span.end and std.mem.eql(u8, other.text, edit.text)) return;
    }
    try edits.append(t.allocator, edit);
}

fn later(_: void, a: language.diagnostic.Edit, b: language.diagnostic.Edit) bool {
    return a.span.start > b.span.start;
}

/// Apply fixes round after round until a check carries none, and return the
/// final source. Fails when the rounds do not settle.
fn settle(source: []const u8) ![]u8 {
    var current = try t.allocator.dupe(u8, source);
    var rounds: usize = 0;
    while (rounds < 8) : (rounds += 1) {
        const outcome = try round(current);
        defer outcome.deinit();
        if (outcome.fixes == 0) return current;
        t.allocator.free(current);
        current = try t.allocator.dupe(u8, outcome.fixed);
    }
    t.allocator.free(current);
    return error.TestUnexpectedResult;
}

/// Whether a program checks without an error.
fn checks(source: []const u8) !bool {
    const outcome = try round(source);
    defer outcome.deinit();
    return outcome.passed;
}

/// The `fix` object of the first JSON record for `diagnostic`, rendered against
/// `src`, or null when the record carries none.
fn renderedFix(allocator: std.mem.Allocator, diagnostic: language.diagnostic.Diagnostic, src: language.source.Source) !?std.json.Parsed(Value) {
    const text = try output.render(allocator, diagnostic, src, .json);
    defer allocator.free(text);
    const parsed = try std.json.parseFromSlice(Value, allocator, text, .{});
    if (field(parsed.value, "diagnostic").object.get("fix") == null) {
        parsed.deinit();
        return null;
    }
    return parsed;
}

// spec-case: DIAGNOSTIC-FIX-1
test "diagnostic-v1 publishes a fix as file, byte range and text, mapped to its own module" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const first = try language.source.Source.init(arena.allocator(), "first.selka", "abc\n");
    const second = try language.source.Source.init(arena.allocator(), "pkg/second.selka", "f(xs)\n");
    const src = try language.source.Source.initMapped(arena.allocator(), &.{ first, second });
    const at = try src.mappedSpan(1, .{ .start = 2, .end = 2 });
    const fixed: language.diagnostic.Diagnostic = .{
        .code = marker_code,
        .span = at,
        .message = "write `mut`",
        .provenance = .{ .fix = .{ .edit = .{ .span = at, .text = "mut " } } },
    };
    const parsed = (try renderedFix(t.allocator, fixed, src)).?;
    defer parsed.deinit();
    const edits = field(field(field(parsed.value, "diagnostic"), "fix"), "edits").array.items;
    try t.expectEqual(@as(usize, 1), edits.len);
    try t.expectEqualStrings("pkg/second.selka", field(edits[0], "path").string);
    try t.expectEqual(@as(i64, 2), field(field(edits[0], "bytes"), "start").integer);
    try t.expectEqual(@as(i64, 2), field(field(edits[0], "bytes"), "end").integer);
    try t.expectEqualStrings("mut ", field(edits[0], "text").string);
    // An edit that straddles two modules cannot be located, so the whole fix is dropped.
    var straddling = fixed;
    straddling.provenance.fix = .{ .edit = .{ .span = at, .text = "" }, .more = &.{.{ .span = .{ .start = 1, .end = 6 }, .text = "" }} };
    try t.expect((try renderedFix(t.allocator, straddling, src)) == null);
    // A diagnostic without a fix keeps its exact bytes: no `fix` key at all.
    var plain = fixed;
    plain.provenance.fix = null;
    const text = try output.render(t.allocator, plain, src, .json);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "\"fix\"") == null);
    // The text rendering never shows the fix.
    const human = try output.render(t.allocator, fixed, src, .text);
    defer t.allocator.free(human);
    const legacy = try plain.render(t.allocator, src);
    defer t.allocator.free(legacy);
    try t.expectEqualStrings(legacy, human);
}

// spec-case: DIAGNOSTIC-FIX-1
test "a symbolic note carrying a fix is never retained for replay" {
    const region: language.source.Span = .{ .start = 0, .end = 20 };
    const note: language.diagnostic.Diagnostic = .{
        .code = "E_EXPLICIT_DISCARD_REQUIRED",
        .span = .{ .start = 2, .end = 4 },
        .message = "discard",
        .provenance = .{ .fix = .{ .edit = .{ .span = .{ .start = 2, .end = 2 }, .text = "_ = " } } },
    };
    try t.expectError(error.Unrepresentable, @import("generic_cache.zig").captureNote(t.allocator, region, note));
}

const call_sites =
    // migrate-embedded: skip original located diagnostic or convergent repair input
    \\func grow(mut xs: int[]) -> Unit:
    \\    append(mut xs, 1)
    \\
    \\
    \\func peek(xs: int[]) -> int:
    \\    return xs[0]
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    grow(xs)
    \\    grow(xs)
    \\    return peek(mut xs)
;

// spec: DIAGNOSTIC-FIX-2
test "call-site mut markers carry the insertion or deletion that repairs them" {
    const outcome = try round(call_sites);
    defer outcome.deinit();
    try t.expect(!outcome.passed);
    try t.expectEqual(@as(usize, 3), outcome.count(marker_code));
    try t.expectEqual(@as(usize, 3), outcome.fixes);
    try t.expect(std.mem.endsWith(u8, outcome.fixed, "    grow(mut xs)\n    grow(mut xs)\n    return peek(xs)"));
    try t.expect(try checks(outcome.fixed));
}

// spec-case: DIAGNOSTIC-FIX-2
test "readonly parameters reject mutation without guessing a caller-update contract" {
    const readonly = try round(
        \\func touch(values: int[], other: int[]) -> Unit:
        \\    values[0] = other[0]
        \\func main() -> int:
        \\    return 0
    );
    defer readonly.deinit();
    try t.expectEqual(@as(usize, 1), readonly.count("E_IMMUTABLE"));
    try t.expectEqual(@as(usize, 0), readonly.fixes);
    const writable =
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\func look(mut values: int[], mut n: int) -> int:
        \\    return values[0] + n
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut number = 2
        \\    return look(mut values, number)
    ;
    const repaired = try settle(writable);
    defer t.allocator.free(repaired);
    try t.expect(std.mem.indexOf(u8, repaired, "func look(mut values: int[], mut n: int)") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "look(mut values, mut number)") != null);
    try t.expect(try checks(repaired));
}

// spec-case: DIAGNOSTIC-FIX-2
test "removed spellings with a rename, a stray discard and a mutates clause carry their fix" {
    const removed =
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\def grow(xs: int[]) -> None mutates(xs):
        \\    xs.push(1)
        \\
        \\
        \\def main() -> int:
        \\    xs: list[int] = []
        \\    grow(&xs)
        \\    min(len(xs), 3)
        \\    return len(xs)
    ;
    const repaired = try settle(removed);
    defer t.allocator.free(repaired);
    // The stray value is `min(...)`, not `xs.exchange(0, 1)`, whose W13 warning carries the `lists` import since W13-S3,
    // which this single-unit check cannot resolve.
    try t.expectEqualStrings(
        \\func grow(mut xs: int[]) -> Unit:
        \\    append(mut xs, 1)
        \\
        \\
        \\func main() -> int:
        \\    mut xs: int[] = []
        \\    grow(mut xs)
        \\    _ = min(len(xs), 3)
        \\    return len(xs)
    , repaired);
    try t.expect(try checks(repaired));
    const capability = try settle("def main(fs: filesystem_cap) -> int:\n    _ = fs\n    return 0\n");
    defer t.allocator.free(capability);
    try t.expectEqualStrings("func main(fs: Filesystem) -> int:\n    _ = fs\n    return 0\n", capability);
}

// spec-case: DIAGNOSTIC-FIX-2
test "a positional operand on a keyword-only parameter is fixed by naming it" {
    const repaired = try settle(
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\func f(a: int, named b: int, named c: int) -> int:
        \\    return a + b + c
        \\
        \\
        \\func main() -> int:
        \\    return f(1, 2, c=3)
    );
    defer t.allocator.free(repaired);
    try t.expect(std.mem.endsWith(u8, repaired, "    return f(1, b=2, c=3)"));
    try t.expect(try checks(repaired));
}

// spec-case: DIAGNOSTIC-FIX-2
test "a discarded result and an unassignable mut argument carry no fix" {
    const result = try round("func rejected_result() -> int fails int:\n    fail 7\n\nfunc main() -> int:\n    rejected_result()\n    return 0\n");
    defer result.deinit();
    try t.expectEqual(@as(usize, 1), result.count("E_EXPLICIT_DISCARD_REQUIRED"));
    try t.expectEqual(@as(usize, 0), result.fixes);
    const literal = try round("func grow(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\n\nfunc main() -> int:\n    grow(mut [1])\n    return 0\n");
    defer literal.deinit();
    try t.expectEqual(@as(usize, 1), literal.count(marker_code));
    try t.expectEqual(@as(usize, 0), literal.fixes);
}

// spec: MUT-PARAM-8
test "one check reports every call-site marker a function needs" {
    const outcome = try round(
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\func grow(mut xs: int[]) -> Unit:
        \\    append(mut xs, 1)
        \\
        \\
        \\func main() -> int:
        \\    mut a: int[] = []
        \\    mut b: int[] = []
        \\    grow(a)
        \\    grow(b)
        \\    grow(a)
        \\    grow(b)
        \\    return len(a) + len(b)
    );
    defer outcome.deinit();
    try t.expect(!outcome.passed);
    try t.expectEqual(@as(usize, 4), outcome.count(marker_code));
    try t.expectEqual(@as(usize, 4), outcome.codes.len);
    try t.expect(try checks(outcome.fixed));
}

/// In-memory module files for a project check.
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

// spec-case: DIAGNOSTIC-FIX-2
test "an unused import's fix deletes its whole line, comment and newline included" {
    const edit = try unusedImportEdit();
    try t.expectEqual(@as(i64, 0), edit.start);
    try t.expectEqual(@as(i64, 27), edit.end);
    try t.expect(edit.deletes);
}

// spec-case: DIAGNOSTIC-FIX-2
test "a legacy module header carries a deletion fix for path-derived identity" {
    var named: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import util.text\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "util/text.selka", .bytes = "module text\n\n\npublic func size() -> int:\n    return 1\n" },
    } };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(.{ .context = &named, .read = Files.read }, "main", .{}));
    const text = try output.renderProject(t.allocator, &project, .json);
    defer t.allocator.free(text);
    var parsed = try std.json.parseFromSlice(Value, t.allocator, text, .{});
    defer parsed.deinit();
    const edit = field(field(field(parsed.value, "diagnostic"), "fix"), "edits").array.items[0];
    try t.expectEqualStrings("util/text.selka", field(edit, "path").string);
    try t.expectEqual(@as(i64, 0), field(field(edit, "bytes"), "start").integer);
    try t.expectEqual(@as(i64, 11), field(field(edit, "bytes"), "end").integer);
    try t.expectEqualStrings("", field(edit, "text").string);
}

/// Check a project whose entry imports a module it never uses, and return the
/// byte range of the one edit its `W_UNUSED_IMPORT` fix makes in `main.selka`.
fn unusedImportEdit() !struct { start: i64, end: i64, deletes: bool } {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import util.text  # unused\n\n\nfunc main() -> int:\n    return 0\n" },
        .{ .path = "util/text.selka", .bytes = "\n\npublic func size() -> int:\n    return 1\n" },
    } };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    for (compilation.diagnostics.items.items) |item| {
        if (!std.mem.eql(u8, item.code, "W_UNUSED_IMPORT")) continue;
        const parsed = (try renderedFix(t.allocator, item, compilation.src)).?;
        defer parsed.deinit();
        const edit = field(field(field(parsed.value, "diagnostic"), "fix"), "edits").array.items[0];
        try t.expectEqualStrings("main.selka", field(edit, "path").string);
        return .{
            .start = field(field(edit, "bytes"), "start").integer,
            .end = field(field(edit, "bytes"), "end").integer,
            .deletes = field(edit, "text").string.len == 0,
        };
    }
    return error.TestUnexpectedResult;
}

/// Check one legacy program and require that its removed spelling reports no
/// rename, because the file declares or binds the new name.
fn withheldRename(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const item = c.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", item.code);
    try t.expect(item.provenance.fix == null);
    try t.expect(std.mem.indexOf(u8, item.message, "rename the call by hand") != null);
}

/// Check one legacy program and require its first round of fixes to produce `expected`.
fn keptRename(source: []const u8, expected: []const u8) !void {
    const outcome = try round(source);
    defer outcome.deinit();
    try t.expectEqual(@as(usize, 1), outcome.fixes);
    try t.expect(std.mem.indexOf(u8, outcome.fixed, expected) != null);
}

// spec: FIX-MIGRATION-CAPTURE-1
test "a removed float or capability spelling is not renamed onto a name the file declares" {
    try withheldRename("func abs(x: float) -> float:\n    return f64_abs(x)\n\n\nfunc main() -> int:\n    return 0\n");
    try withheldRename("func main() -> int:\n    mut floor = 2.5\n    return int(f64_floor(floor))\n");
    try withheldRename("func scale(x: float, ceil: float) -> float:\n    return f64_ceil(x) + ceil\n\n\nfunc main() -> int:\n    return 0\n");
    try withheldRename("record Filesystem:\n    x: int\n\n\nfunc helper(fs: filesystem_cap) -> int:\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try withheldRename("func total(xs: float[]) -> float:\n    mut s = 0.0\n    for trunc in xs:\n        s = s + f64_trunc(trunc)\n    return s\n\n\nfunc main() -> int:\n    return 0\n");
    try withheldRename("func pick(found: Result[float, str]) -> float:\n    match found:\n        case Ok(abs):\n            return f64_abs(abs)\n        case Err(_):\n            return 0.0\n\n\nfunc main() -> int:\n    return 0\n");
}

// spec-case: FIX-MIGRATION-CAPTURE-1
test "a removed spelling is still renamed when the file only uses the new name" {
    try keptRename("func g(x: float) -> float:\n    return abs(x) + f64_abs(x)\n\n\nfunc main() -> int:\n    return 0\n", "abs(x) + abs(x)");
    try keptRename("func g(fs: Filesystem, other: filesystem_cap) -> Filesystem:\n    return fs\n\n\nfunc main() -> int:\n    return 0\n", "other: Filesystem");
    try keptRename("func root(x: float) -> float:\n    return f64_sqrt(x)\n\n\nfunc main() -> int:\n    return 0\n", "return sqrt(x)");
}

// spec-case: FIX-MIGRATION-1
test "a Result return clause is fixed to fails with every return rewritten" {
    const source =
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\func read(text: str) -> Result[int, str]:
        \\    if text == "":
        \\        return Err("empty")
        \\    return Ok(len(text))
        \\
        \\func main() -> int:
        \\    return 0
    ;
    var first = try round(source);
    defer first.deinit();
    try t.expect(!first.passed);
    try t.expectEqual(@as(usize, 1), first.count("E_RESULT_RETURN_REMOVED"));
    try t.expect(std.mem.indexOf(u8, first.fixed, "func read(text: str) -> int fails str:") != null);
    try t.expect(std.mem.indexOf(u8, first.fixed, "fail \"empty\"") != null);
    try t.expect(std.mem.indexOf(u8, first.fixed, "return len(text)") != null);
    var second = try round(first.fixed);
    defer second.deinit();
    try t.expect(second.passed);
}

test "an f32 and a float meet in one operation: the repair widens the f32 operand exactly" {
    const mixed =
        // migrate-embedded: skip original located diagnostic or convergent repair input
        \\func main() -> int:
        \\    const a: f32 = 1.5f32
        \\    const b: float = 2.0
        \\    const total = a + b
        \\    return int(total)
    ;
    const first = try round(mixed);
    defer first.deinit();
    try t.expectEqual(@as(usize, 1), first.count("E_FLOAT_WIDTH"));
    try t.expectEqual(@as(usize, 1), first.fixes);
    const repaired = try settle(mixed);
    defer t.allocator.free(repaired);
    try t.expectEqualStrings(
        \\func main() -> int:
        \\    const a: f32 = 1.5f32
        \\    const b: float = 2.0
        \\    const total = float(a) + b
        \\    return int(total)
    , repaired);
}

test "a generic body's repair is the same repair for two refused kinds only when every edit's span and text agree (FR88)" {
    const own: language.diagnostic.Fix = .{ .edit = .{ .span = .{ .start = 40, .end = 40 }, .text = "own " } };
    const own_again: language.diagnostic.Fix = .{ .edit = .{ .span = .{ .start = 40, .end = 40 }, .text = "own " } };
    const copied: language.diagnostic.Fix = .{ .edit = .{ .span = .{ .start = 40, .end = 40 }, .text = "copy(" }, .more = &.{.{ .span = .{ .start = 45, .end = 45 }, .text = ")" }} };
    const elsewhere: language.diagnostic.Fix = .{ .edit = .{ .span = .{ .start = 41, .end = 41 }, .text = "own " } };
    try t.expect(own.same(own_again));
    try t.expect(!own.same(copied));
    try t.expect(!copied.same(own));
    try t.expect(!own.same(elsewhere));
    try t.expect(copied.same(copied));
}

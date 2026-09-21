//! The parser names the accepted spelling at the declaration forms an agent
//! writes first. One table holds those forms so the friction classifier can file
//! the same shapes; the agreement test here reads the classifier itself.
const std = @import("std");
const t = std.testing;
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");

/// The classifier the hint table is kept in step with, relative to the repository
/// root every `zig build` step runs from.
const classifier_path = "velocity/friction/classifier.json";
/// Candidate roots for the classifier, for a build started in a subdirectory.
const classifier_candidates = [_][]const u8{ classifier_path, "../" ++ classifier_path, "../../" ++ classifier_path };
/// The classifier is a small hand-written table; this bounds a runaway read.
const classifier_limit = 256 * 1024;

/// Parse one single-unit source and answer its first diagnostic from `arena`.
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    sink: diagnostic.Sink,
    src: source.Source = undefined,

    fn init(allocator: std.mem.Allocator) Fixture {
        return .{ .arena = .init(allocator), .sink = .{ .allocator = allocator } };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    /// Parse one single-unit source and answer its first diagnostic, which stays
    /// valid until `deinit` at the earliest.
    fn failure(self: *Fixture, bytes: []const u8) !*const diagnostic.Diagnostic {
        const allocator = self.arena.allocator();
        self.src = try source.Source.init(allocator, "hint.my", bytes);
        var sink: diagnostic.Sink = .{ .allocator = allocator };
        const tokens = try lexer.lex(allocator, bytes, &sink);
        var p: parser.Parser = .{ .src = self.src, .arena = &self.arena, .tokens = tokens, .sink = &sink };
        try t.expectError(error.SourceError, p.parse());
        self.sink = sink;
        return &self.sink.items.items[0];
    }
};

/// Assert one hint: its code, its message, the accepted spelling under the
/// counted `alternative` role, and the location the rejected token keeps.
fn expectHint(fixture: *const Fixture, failure: *const diagnostic.Diagnostic, message: []const u8, accepted: []const u8, line: usize, column: usize) !void {
    const at = fixture.src.locate(failure.span.start);
    try t.expectEqualStrings("E_SYNTAX", failure.code);
    try t.expectEqualStrings(message, failure.message);
    try t.expect(failure.related != null);
    try t.expectEqual(diagnostic.Role.alternative, failure.related.?.role);
    try t.expectEqualStrings(accepted, failure.related.?.message);
    try t.expectEqual(line, at.line);
    try t.expectEqual(column, at.column);
}

/// Read the first candidate that exists. `error.ClassifierUnreadable` means the
/// table could not be checked at all: a failure, never a silent skip.
fn readFirst(allocator: std.mem.Allocator, candidates: []const []const u8) ![]u8 {
    for (candidates) |candidate| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(t.io, candidate, allocator, .limited(classifier_limit)) catch continue;
        return bytes;
    }
    return error.ClassifierUnreadable;
}

/// The classifier document the agreement test reads.
fn readClassifier(allocator: std.mem.Allocator) ![]u8 {
    return readFirst(allocator, &classifier_candidates);
}

/// Whether some `E_SYNTAX` rule in the classifier files `idiom`.
fn classifierRulesHint(object: std.json.ObjectMap, idiom: []const u8) bool {
    const rules = object.get("rules") orelse return false;
    for (rules.array.items) |rule| {
        if (!std.mem.eql(u8, rule.object.get("code").?.string, "E_SYNTAX")) continue;
        if (std.mem.eql(u8, rule.object.get("idiom").?.string, idiom)) return true;
    }
    return false;
}

/// Assert that the classifier's `hints` array is exactly the parser's table, in
/// order, and that every hinted form has an `E_SYNTAX` rule behind it. A
/// classifier without the array fails on the assertion, never silently passes.
fn checkAgreement(root: std.json.Value) !void {
    const object = root.object;
    const listed = object.get("hints");
    try t.expect(listed != null);
    try t.expectEqual(parser.declaration_hints.len, listed.?.array.items.len);
    for (parser.declaration_hints, listed.?.array.items) |hint, entry| try t.expectEqualStrings(hint.idiom, entry.string);
    for (parser.declaration_hints) |hint| try t.expect(classifierRulesHint(object, hint.idiom));
}

/// Assert the table's own invariants: one row per form, in form order, each with
/// a distinct nonempty idiom.
fn checkTable() !void {
    for (parser.declaration_hints, 0..) |hint, index| {
        try t.expectEqual(@as(parser.HintForm, @fromBackingInt(@intCast(index))), hint.form);
        try t.expect(hint.idiom.len != 0);
        try t.expect(hint.message.len != 0);
        try t.expect(hint.accepted.len != 0);
    }
}

// spec: PARSER-HINT-1
test "a union or enum case without its comma names the rule and the fix" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const union_case = try fixture.failure(
        \\union Event:
        \\    heartbeat
        \\    count: int
        \\
    );
    try expectHint(&fixture, union_case, "union cases are separated by commas", "insert a comma after the previous case", 3, 5);
    const enum_case = try fixture.failure(
        \\enum Level:
        \\    debug
        \\    warning
        \\
    );
    try expectHint(&fixture, enum_case, "enum cases are separated by commas", "insert a comma after the previous case", 3, 5);
    const result_case = try fixture.failure(
        \\result Parse:
        \\    ok: int
        \\    err: str
        \\
    );
    try expectHint(&fixture, result_case, "result cases are separated by commas", "insert a comma after the previous case", 3, 5);
}

// spec: PARSER-HINT-2
test "a bare module-level assignment names the const declaration it needs" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const bare = try fixture.failure("MAX = 42\n");
    try expectHint(&fixture, bare, "a bare assignment declares no module-level binding", "declare it as a constant: const MAX: int = 42", 1, 1);
    const annotated = try fixture.failure("MAX: int = 42\n");
    try expectHint(&fixture, annotated, "a bare assignment declares no module-level binding", "declare it as a constant: const MAX: int = 42", 1, 1);
}

// spec: PARSER-HINT-3
test "a def inside a record or class body names the function that takes the record" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const after_field = try fixture.failure(
        \\record Point:
        \\    x: int
        \\    def norm1(self) -> int:
        \\        return self.x
        \\
    );
    try expectHint(&fixture, after_field, "a record or class body declares fields, not methods", "declare a top-level function taking the record: def norm1(p: Point) -> int", 3, 5);
    const first_member = try fixture.failure(
        \\class Point:
        \\    def __init__(self, x: int, y: int):
        \\        self.x = x
        \\
    );
    try expectHint(&fixture, first_member, "a record or class body declares fields, not methods", "declare a top-level function taking the record: def norm1(p: Point) -> int", 2, 5);
}

// spec: PARSER-HINT-4
test "a from-import names the accepted module import and record declaration" {
    var fixture = Fixture.init(t.allocator);
    defer fixture.deinit();
    const failure = try fixture.failure(
        \\from dataclasses import dataclass
        \\
        \\@dataclass
        \\class Point:
        \\    x: int
        \\
    );
    try expectHint(&fixture, failure, "a from-import is not a declaration", "import the module and declare a record: import dataclasses", 1, 1);
}

// spec: PARSER-HINT-5
test "the hinted forms and the friction classifier name one table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = try readClassifier(arena.allocator());
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), text, .{});
    try checkTable();
    try checkAgreement(parsed.value);
}

// The agreement check above must fail loudly when the classifier cannot be read
// at all: an unreadable table is a failure, never a silent pass.
test "an unreadable classifier fails the agreement check instead of skipping it" {
    try t.expectError(error.ClassifierUnreadable, readFirst(t.allocator, &.{"no/such/classifier.json"}));
}

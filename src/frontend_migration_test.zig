//! Migration edits are parser-derived, preserve text outside their spans, and
//! converge without changing canonical sources.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const migration = @import("frontend_migration.zig");
const migration_path = "migration.my";

// spec-case: FRONTEND-NUMBERS-1
test "frontend text conversion repair changes only the builtin callee" {
    var compilation = try language.Compilation.init(t.allocator, "parse.my", "func parse(text: str) -> int?:\n    return int(text)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_NUMERIC_PARSE", item.code);
    const edit = item.provenance.fix.?.edit;
    try t.expectEqualStrings("int", compilation.src.text(edit.span));
    try t.expectEqualStrings("parse_int", edit.text);
}

// spec-case: FRONTEND-NUMBERS-1
test "frontend text parser rejects a numeric argument" {
    var compilation = try language.Compilation.init(t.allocator, "parse.my", "func parse() -> int?:\n    return parse_int(7)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    try t.expectEqualStrings("E_TYPE", compilation.diagnostics.items[0].code);
}

fn parseLegacy(compilation: *language.Compilation) !void {
    const allocator = compilation.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    compilation.tokens = try @import("lexer.zig").lex(allocator, compilation.src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{
        .src = compilation.src,
        .storage = allocator,
        .tokens = compilation.tokens.?,
        .sink = &sink,
        .cursor = .{ .dialect = .migration },
    };
    compilation.syntax = try parser.parse();
}

fn migrated(text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try parseLegacy(&compilation);
    const allocator = compilation.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    _ = try migration.publish(compilation.src, compilation.syntax.?, compilation.tokens.?, &sink);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    for (sink.items.items) |item| {
        const fix = item.provenance.fix orelse continue;
        try edits.append(allocator, fix.edit);
        try edits.appendSlice(allocator, fix.more);
    }
    std.mem.sort(diagnostic.Edit, edits.items, {}, later);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    var earliest = text.len + 1;
    for (edits.items) |edit| {
        if (edit.span.end > earliest) continue;
        try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
        earliest = edit.span.start;
    }
    return out.toOwnedSlice(t.allocator);
}

fn later(_: void, left: diagnostic.Edit, right: diagnostic.Edit) bool {
    return left.span.start > right.span.start;
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend canonical conditionals inside interpolations need no migration" {
    var compilation = try language.Compilation.init(t.allocator, migration_path,
        \\func describe(count: int) -> str:
        \\    return f"{if count == 1 then 'item' else 'items'}"
    );
    defer compilation.deinit();
    try compilation.checkLibrary();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// spec: FRONTEND-FUNC-1
test "frontend func discovery recognizes public and ordinary entry declarations" {
    const config = @import("project_config.zig");
    try t.expect(config.declaresMain("func main() -> int:\n    return 0\n"));
    try t.expect(config.declaresMain("public func main() -> int:\n    return 0\n"));
    try t.expect(!config.declaresMain("# func main()\nfunc other() -> int:\n    return 0\n"));
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend renderType reports allocation failure when constructing replacement text" {
    var compilation = try language.Compilation.init(t.allocator, migration_path, "type Values = list[int]\n");
    defer compilation.deinit();
    try parseLegacy(&compilation);
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    const expressions = compilation.syntax.?.types.expressions;
    try t.expectError(error.OutOfMemory, migration.renderType(failing.allocator(), compilation.src, expressions, expressions.aliases[0].target));
}

// spec: FRONTEND-MIGRATION-1
test "frontend migration rewrites parsed types and parameter markers without touching strings" {
    const result = try migrated(
        \\def copy(xs: mut list[Option[int]], *, extra: int = 1) -> None:
        \\    values: list[int] = []
        \\    const text = "list[int] and Option[int] remain text"
        \\    return
        \\
    );
    defer t.allocator.free(result);
    try t.expectEqualStrings(
        \\func copy(mut xs: int?[], named extra: int = 1) -> Unit:
        \\    mut values: int[] = []
        \\    const text = "list[int] and Option[int] remain text"
        \\    return
        \\
    , result);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend migration preserves canonical spacing and nested optional layers" {
    const text =
        \\type Fields = dict[str,int?[]?]
        \\func value(named input: int??) -> FixedArray[int,2]:
        \\    const fixed: FixedArray[int,2] = FixedArray[int,2]([1, 2])
        \\    return fixed
        \\
    ;
    const result = try migrated(text);
    defer t.allocator.free(result);
    try t.expectEqualStrings(text, result);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend conditional migration retains enclosing expression precedence" {
    const legacy = "func main() -> bool:\n    return (1 if True else 2) == 1\n";
    const result = try migrated(legacy);
    defer t.allocator.free(result);
    try t.expectEqualStrings("func main() -> bool:\n    return (if (True) then (1) else (2)) == 1\n", result);
    const settled = try migrated(result);
    defer t.allocator.free(settled);
    try t.expectEqualStrings(result, settled);
}

// spec: FRONTEND-FORMAT-1
test "frontend formatter spaces contextual expression words and optional failure signatures" {
    const text =
        \\func select(named flag: bool)->int? fails Error:
        \\    const value=if flag then (1) else (2)
        \\    const values=[for x in source() if visible(x) yield (x+1)]
        \\    return try (load())
        \\
    ;
    var compilation = try language.Compilation.init(t.allocator, "format.my", text);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(
        \\func select(named flag: bool) -> int? fails Error:
        \\    const value = if flag then (1) else (2)
        \\    const values = [for x in source() if visible(x) yield (x + 1)]
        \\    return try (load())
        \\
    , formatted);
}

fn migratedVariants(text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try parseLegacy(&compilation);
    const allocator = compilation.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    _ = try @import("frontend_migration_variants.zig").publish(compilation.src, compilation.syntax.?, compilation.tokens.?, &sink);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    for (sink.items.items) |item| {
        const fix = item.provenance.fix orelse continue;
        try edits.append(allocator, fix.edit);
        try edits.appendSlice(allocator, fix.more);
    }
    std.mem.sort(diagnostic.Edit, edits.items, {}, later);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    var earliest = text.len + 1;
    for (edits.items) |edit| {
        if (edit.span.end > earliest) continue;
        try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
        earliest = edit.span.start;
    }
    return out.toOwnedSlice(t.allocator);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend variant migration labels declared payload constructors and scoped patterns" {
    const original =
        \\union Choice:
        \\    empty, number: int, pair(left: int, right: int)
        \\func choose(choice: Choice) -> int:
        \\    const made = Choice.number(3)
        \\    const paired = Choice.pair(1, 2)
        \\    match choice:
        \\        case number(value):
        \\            return value
        \\        case pair(left, right):
        \\            return left + right
        \\        case _:
        \\            return 0
    ;
    const result = try migratedVariants(original);
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "enum Choice:\n    empty\n    number(value: int)\n    pair(left: int, right: int)") != null);
    try t.expect(std.mem.indexOf(u8, result, "Choice.number(value=3)") != null);
    try t.expect(std.mem.indexOf(u8, result, "Choice.pair(left=1, right=2)") != null);
    try t.expect(std.mem.indexOf(u8, result, "case number(value=value)") != null);
    try t.expect(std.mem.indexOf(u8, result, "case pair(left=left, right=right)") != null);
    const second = try migratedVariants(result);
    defer t.allocator.free(second);
    try t.expectEqualStrings(result, second);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend variant migration preserves nominal result declarations and labels nested enum cases" {
    const original =
        \\enum Error:
        \\    bad(message: str)
        \\result Outcome:
        \\    ok: int,
        \\    err: Error
        \\func handle(value: Outcome) -> int:
        \\    match value:
        \\        case Outcome.err(Error.bad(message)):
        \\            return 0
        \\        case Outcome.ok(number):
        \\            return number
        \\
    ;
    const result = try migratedVariants(original);
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "result Outcome:\n    ok: int,\n    err: Error") != null);
    try t.expect(std.mem.indexOf(u8, result, "Outcome.err(Error.bad(message=message))") != null);
    try t.expect(std.mem.indexOf(u8, result, "Outcome.ok(number)") != null);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend variant migration skips shadowed receivers and unresolved imported cases" {
    const original = "enum Choice:\n    number(value: int)\nfunc use(Choice: Other) -> Unit:\n    Choice.number(3)\n    imported.number(3)\n";
    const result = try migratedVariants(original);
    defer t.allocator.free(result);
    try t.expectEqualStrings(original, result);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend variant migration keeps case comments and does not expose branch-local types" {
    const original =
        \\enum Choice:
        \\    empty, # keep this comment
        \\    number(value: int),
        \\func use() -> Unit:
        \\    if True:
        \\        const value: Choice = Choice.number(3)
        \\    match value:
        \\        case number(number):
        \\            pass
        \\
    ;
    const result = try migratedVariants(original);
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "empty # keep this comment") != null);
    try t.expect(std.mem.indexOf(u8, result, "case number(number)") != null);
}

fn migratedExpressions(text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try parseLegacy(&compilation);
    const allocator = compilation.arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    _ = try @import("frontend_migration_expressions.zig").publish(compilation.src, compilation.syntax.?, compilation.tokens.?, &sink);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    for (sink.items.items) |item| {
        const fix = item.provenance.fix orelse continue;
        try edits.append(allocator, fix.edit);
        try edits.appendSlice(allocator, fix.more);
    }
    std.mem.sort(diagnostic.Edit, edits.items, {}, later);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    var earliest = text.len + 1;
    for (edits.items) |edit| {
        if (edit.span.end > earliest) continue;
        try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
        earliest = edit.span.start;
    }
    return out.toOwnedSlice(t.allocator);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend expression migration preserves source and filter evaluation order" {
    const result = try migratedExpressions("func work(xs: int[]) -> int[]:\n    const first = [x + 1 for x in xs]\n    return [x * 2 for x in range(1, 9, 2) if x > 2 if valid(x)]\n");
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "[for x in xs yield x + 1]") != null);
    try t.expect(std.mem.indexOf(u8, result, "[for x in range(1, 9, 2) if (x > 2) and (valid(x)) yield x * 2]") != null);
    const second = try migratedExpressions(result);
    defer t.allocator.free(second);
    try t.expectEqualStrings(result, second);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend expression migration repairs explicit semicolons and preserves comments" {
    const original = "func work() -> int:\n    mut value = 1; value = 2; # preserve\n    return value;\n";
    const result = try migratedExpressions(original);
    defer t.allocator.free(result);
    try t.expectEqualStrings("func work() -> int:\n    mut value = 1\n    value = 2 # preserve\n    return value\n", result);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend nested comprehension migration publishes a diagnostic without speculative repair" {
    var compilation = try language.Compilation.init(t.allocator, "nested.my", "func work(xs: int[]) -> int[]:\n    return [x + y for x in xs for y in xs]\n");
    defer compilation.deinit();
    try parseLegacy(&compilation);
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try t.expect(try @import("frontend_migration_expressions.zig").publish(compilation.src, compilation.syntax.?, compilation.tokens.?, &sink));
    try t.expectEqual(@as(usize, 1), sink.items.items.len);
    try t.expectEqualStrings("E_FRONTEND_EXPRESSION", sink.items.items[0].code);
    try t.expect(sink.items.items[0].provenance.fix == null);
}

// spec-case: FRONTEND-TYPES-1
test "frontend functionless structural libraries validate without a synthetic function scope" {
    var compilation = try language.Compilation.init(t.allocator, migration_path,
        \\public record ID:
        \\    value: int
        \\public constraint HasValue[T] = copy + field(value: ID)
    );
    defer compilation.deinit();
    try compilation.checkLibrary();
}

fn repairedFields(text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const fix = compilation.diagnostics.items[0].provenance.fix orelse return error.TestUnexpectedResult;
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    defer edits.deinit(t.allocator);
    try edits.append(t.allocator, fix.edit);
    try edits.appendSlice(t.allocator, fix.more);
    std.mem.sort(diagnostic.Edit, edits.items, {}, later);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    for (edits.items) |edit| try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return out.toOwnedSlice(t.allocator);
}

// spec: FRONTEND-RECORD-FIELDS-1
test "frontend named record repair labels all operands and converges without reordering calls" {
    const original =
        \\record Point:
        \\    x: int
        \\    y: int
        \\
        \\func first() -> int:
        \\    return 1
        \\
        \\func second() -> int:
        \\    return 2
        \\
        \\func make() -> Point:
        \\    return Point(first(), second())
    ;
    const repaired = try repairedFields(original);
    defer t.allocator.free(repaired);
    try t.expect(std.mem.indexOf(u8, repaired, "Point(x=first(), y=second())") != null);
    var compilation = try language.Compilation.init(t.allocator, migration_path, repaired);
    defer compilation.deinit();
    try compilation.checkLibrary();
    const unchanged = try migrated(repaired);
    defer t.allocator.free(unchanged);
    try t.expectEqualStrings(repaired, unchanged);
}

const NamedImported = struct {
    app: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *NamedImported = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "app.my")) return allocator.dupe(u8, self.app);
        if (std.mem.eql(u8, path, "messages.my")) return allocator.dupe(u8,
            \\public enum Message:
            \\    pair(left: int, right: int)
        );
        return error.NotFound;
    }
};

fn repairImported(text: []const u8) ![]u8 {
    var files: NamedImported = .{ .app = text };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = NamedImported.read }, "app", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    defer edits.deinit(t.allocator);
    var rejected_source = false;
    compilation.check() catch |err| {
        rejected_source = true;
        if (err != error.SourceError) return err;
        for (compilation.diagnostics.items.items) |item| if (item.provenance.fix) |fix| {
            for (0..fix.count()) |position| {
                const edit = fix.at(position);
                const original = try compilation.src.originalSpan(edit.span);
                try edits.append(t.allocator, .{ .span = original.span, .text = edit.text });
            }
        };
    };
    if (rejected_source and edits.items.len == 0) return error.TestUnexpectedResult;
    std.mem.sort(diagnostic.Edit, edits.items, {}, later);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    for (edits.items) |edit| try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return out.toOwnedSlice(t.allocator);
}

// spec-case: FRONTEND-MATCH-1
test "frontend imported enum operand and discard pattern labels repair and converge" {
    const original =
        \\import messages as m
        \\
        \\func main() -> int:
        \\    const value = m.Message.pair(1, 2)
        \\    match value:
        \\        case m.Message.pair(left, _):
        \\            return left
    ;
    const first = try repairImported(original);
    defer t.allocator.free(first);
    const second = try repairImported(first);
    defer t.allocator.free(second);
    try t.expect(std.mem.indexOf(u8, second, "m.Message.pair(left=1, right=2)") != null);
    try t.expect(std.mem.indexOf(u8, second, "m.Message.pair(left=left, right=_)") != null);
    const third = try repairImported(second);
    defer t.allocator.free(third);
    try t.expectEqualStrings(second, third);
}

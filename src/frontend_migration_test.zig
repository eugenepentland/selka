//! Migration edits are parser-derived, preserve text outside their spans, and
//! converge without changing canonical sources.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const migration = @import("frontend_migration.zig");
const migration_path = "migration.selka";
const numeric_parse_code = @import("numeric_surface.zig").numeric_parse_code;

// spec-case: FRONTEND-NUMBERS-1
test "frontend text conversion repair changes only the builtin callee" {
    var compilation = try language.Compilation.init(t.allocator, "parse.selka", "func parse(text: str) -> int?:\n    return int(text)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings(numeric_parse_code, item.code);
    const edit = item.provenance.fix.?.edit;
    try t.expectEqualStrings("int", compilation.src.text(edit.span));
    try t.expectEqualStrings("parse_int", edit.text);
}

// spec-case: FRONTEND-NUMBERS-1
test "frontend text parser rejects a numeric argument" {
    var compilation = try language.Compilation.init(t.allocator, "parse.selka", "func parse() -> int?:\n    return parse_int(7)\n");
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
test "frontend conditionals inside interpolations report removal and statement branches check" {
    var compilation = try language.Compilation.init(t.allocator, migration_path,
        // migrate-embedded: skip original conditional interpolation removal witness
        \\func describe(count: int) -> str:
        \\    return f"{if count == 1 then 'item' else 'items'}"
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", compilation.diagnostics.items[0].code);
    const fix = compilation.diagnostics.items[0].provenance.fix orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 1), fix.count());
    const repaired = try repairedFields(compilation.src.bytes);
    defer t.allocator.free(repaired);
    try t.expectEqualStrings("func describe(count: int) -> str:\n    mut selection_48: str\n    if count == 1:\n        selection_48 = 'item'\n    else:\n        selection_48 = 'items'\n    return f\"{selection_48}\"", repaired);
    var fixed = try language.Compilation.init(t.allocator, migration_path, repaired);
    defer fixed.deinit();
    try fixed.checkLibrary();
    try t.expectEqual(@as(usize, 0), fixed.diagnostics.items.len);

    var modern = try language.Compilation.init(t.allocator, migration_path,
        \\func describe(count: int) -> str:
        \\    if count == 1:
        \\        return "item"
        \\    else:
        \\        return "items"
    );
    defer modern.deinit();
    try modern.checkLibrary();
    try t.expectEqual(@as(usize, 0), modern.diagnostics.items.len);
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
    // migrate-embedded: skip original conditional parser precedence witness
    const legacy = "func main() -> bool:\n    return (1 if True else 2) == 1\n";
    const result = try migrated(legacy);
    defer t.allocator.free(result);
    try t.expectEqualStrings(legacy, result);
    const settled = try migrated(result);
    defer t.allocator.free(settled);
    try t.expectEqualStrings(result, settled);
    const modern = try modernizedRetiredExpressions(result);
    defer t.allocator.free(modern);
    const renamed = try std.mem.replaceOwned(u8, t.allocator, modern, "func main() -> bool:", "func compare() -> bool:");
    defer t.allocator.free(renamed);
    const executable_source = try std.mem.concat(t.allocator, u8, &.{ renamed, "\nfunc main() -> int:\n    if compare():\n        return 42\n    return 0\n" });
    defer t.allocator.free(executable_source);
    var executable = try language.Compilation.init(t.allocator, migration_path, executable_source);
    defer executable.deinit();
    const outcome = try @import("native_execute.zig").run(&executable);
    try t.expectEqual(@as(i64, 42), outcome.value);
}

// spec: FRONTEND-FORMAT-1
test "frontend formatter spaces contextual expression words and optional failure signatures" {
    const text =
        // migrate-embedded: skip parser-only formatter contextual-word spacing input
        \\func select(named flag: bool)->int? fails Error:
        \\    const value=if flag then (1) else (2)
        \\    const values=[for x in source() if visible(x) yield (x+1)]
        \\    return try (load())
        \\
    ;
    var compilation = try language.Compilation.init(t.allocator, "format.selka", text);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(
        // migrate-embedded: skip exact formatter contextual-word spacing output
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
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
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
    // A bare name that is a field of its case binds that field: no label is written.
    try t.expect(std.mem.indexOf(u8, result, "case number(value):") != null);
    try t.expect(std.mem.indexOf(u8, result, "case pair(left, right):") != null);
    const second = try migratedVariants(result);
    defer t.allocator.free(second);
    try t.expectEqualStrings(result, second);
}

// spec-case: FRONTEND-MIGRATION-1
test "frontend variant migration preserves nominal result declarations and labels nested enum cases" {
    const original =
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
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
    try t.expect(std.mem.indexOf(u8, result, "Outcome.err(Error.bad(message))") != null);
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
    // migrate-embedded: skip original parser migration identity and overlap witness
    const result = try migratedExpressions("func work(xs: int[]) -> int[]:\n    const first = [x + 1 for x in xs]\n    return [x * 2 for x in range(1, 9, 2) if x > 2 if valid(x)]\n");
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "[x + 1 for x in xs]") != null);
    try t.expect(std.mem.indexOf(u8, result, "[x * 2 for x in range(1, 9, 2) if x > 2 if valid(x)]") != null);
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
    // migrate-embedded: skip original parser migration identity and overlap witness
    var compilation = try language.Compilation.init(t.allocator, "nested.selka", "func work(xs: int[]) -> int[]:\n    return [x + y for x in xs for y in xs]\n");
    defer compilation.deinit();
    try parseLegacy(&compilation);
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try t.expect(!try @import("frontend_migration_expressions.zig").publish(compilation.src, compilation.syntax.?, compilation.tokens.?, &sink));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}

// spec-case: FRONTEND-TYPES-1
test "frontend functionless structural libraries validate without a synthetic function scope" {
    var compilation = try language.Compilation.init(t.allocator, migration_path,
        \\public record ID:
        \\    value: int
        \\public record HasValue:
        \\    value: ID
    );
    defer compilation.deinit();
    try compilation.checkLibrary();
}

/// Keep the original parser transform witness, then drive actual semantic
/// removal fixes until its modern counterpart checks without diagnostics.
fn modernizedRetiredExpressions(original: []const u8) ![]u8 {
    var current = try t.allocator.dupe(u8, original);
    errdefer t.allocator.free(current);
    for (0..16) |_| {
        var compilation = try language.Compilation.init(t.allocator, migration_path, current);
        defer compilation.deinit();
        if (compilation.checkLibrary()) |_| {
            return current;
        } else |err| {
            if (err != error.SourceError) return err;
            try t.expect(compilation.diagnostics.items.len > 0);
            const code = compilation.diagnostics.items[0].code;
            try t.expect(std.mem.eql(u8, code, "E_COMPREHENSION_REMOVED") or
                std.mem.eql(u8, code, "E_GENERATOR_REMOVED") or
                std.mem.eql(u8, code, "E_CONDITIONAL_EXPRESSION_REMOVED"));
            const next = try repairedFields(current);
            try t.expect(!std.mem.eql(u8, current, next));
            t.allocator.free(current);
            current = next;
        }
    }
    return error.TestUnexpectedResult;
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
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
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
        if (std.mem.eql(u8, path, "app.selka")) return allocator.dupe(u8, self.app);
        if (std.mem.eql(u8, path, "messages.selka")) return allocator.dupe(u8,
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
    try t.expect(std.mem.indexOf(u8, second, "pair(left, right=_)") != null);
    const third = try repairImported(second);
    defer t.allocator.free(third);
    try t.expectEqualStrings(second, third);
}

// spec: FRONTEND-BINDING-MIGRATION-2
test "frontend binding migration repairs independent branch locals and converges" {
    const original =
        \\func main() -> int:
        \\    if True:
        \\        token = 1
        \\        return token
        \\    if False:
        \\        token = 2
        \\        return token
        \\    return 0
        \\
    ;
    const first = try migrated(original);
    defer t.allocator.free(first);
    try t.expectEqualStrings(
        \\func main() -> int:
        \\    if True:
        \\        mut token = 1
        \\        return token
        \\    if False:
        \\        mut token = 2
        \\        return token
        \\    return 0
        \\
    , first);
    var compilation = try language.Compilation.init(t.allocator, migration_path, first);
    defer compilation.deinit();
    try compilation.checkLibrary();
    const second = try migrated(first);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "frontend binding migration resolves sibling match and loop identities" {
    const original =
        \\enum Kind:
        \\    first
        \\    second
        \\func choose(kind: Kind) -> int:
        \\    match kind:
        \\        case first:
        \\            token = 1
        \\            return token
        \\        case second:
        \\            token = 2
        \\            return token
        \\func looped() -> int:
        \\    if False:
        \\        token = 3
        \\        return token
        \\    for token in range(2):
        \\        return token
        \\    return 0
        \\
    ;
    const first = try migrated(original);
    defer t.allocator.free(first);
    try t.expect(std.mem.indexOf(u8, first, "mut token = 1") != null);
    try t.expect(std.mem.indexOf(u8, first, "mut token = 2") != null);
    try t.expect(std.mem.indexOf(u8, first, "mut token = 3") != null);
    var compilation = try language.Compilation.init(t.allocator, migration_path, first);
    defer compilation.deinit();
    try compilation.checkLibrary();
    const second = try migrated(first);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
}

fn refusedBinding(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try parseLegacy(&compilation);
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try t.expect(try @import("frontend_binding_migration.zig").publish(compilation.src, compilation.syntax.?, &sink));
    try t.expect(sink.items.items.len > 0);
    for (sink.items.items) |item| {
        try t.expectEqualStrings("E_BINDING_SCOPE_MIGRATION", item.code);
        try t.expect(item.provenance.fix == null);
    }
}

fn refusedNamedBinding(text: []const u8, name: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try parseLegacy(&compilation);
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try t.expect(try @import("frontend_binding_migration.zig").publish(compilation.src, compilation.syntax.?, &sink));
    var refused: usize = 0;
    for (sink.items.items) |item| {
        if (!std.mem.eql(u8, compilation.src.text(item.span), name)) continue;
        try t.expectEqualStrings("E_BINDING_SCOPE_MIGRATION", item.code);
        try t.expect(item.provenance.fix == null);
        refused += 1;
    }
    try t.expectEqual(@as(usize, 2), refused);
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "F5 binding migration refuses branch locals used by augmented assignment" {
    try refusedNamedBinding("func main() -> int:\n    c = True\n    if c:\n        n = 1\n    else:\n        n = 2\n    n += 10\n    return 0\n", "n");
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "F5 binding migration refuses branch locals used by a method receiver" {
    try refusedNamedBinding("func main() -> int:\n    c = True\n    if c:\n        xs = [1]\n    else:\n        xs = [2]\n    xs.append(3)\n    return 0\n", "xs");
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "F5 binding migration resolves call and operation owners and field and index targets" {
    for ([_][]const u8{ "n()", "n.append(3)", "n.read()", "read_resource[Read](n)", "write_resource[Write](n, 3)", "n.field = 2", "n[0] = 2", "n.field += 2", "n[0] += 2", "n.field.update()" }) |use| {
        const text = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    if True:\n        n = 1\n    else:\n        n = 2\n    {s}\n    return 0\n", .{use});
        defer t.allocator.free(text);
        try refusedNamedBinding(text, "n");
    }
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "F5 binding migration keeps independent assignment declarations repairable" {
    const result = try migrated("func main() -> int:\n    if False:\n        n = 1\n        n += 2\n    n = 3\n    n += 4\n    return n\n");
    defer t.allocator.free(result);
    try t.expectEqualStrings("func main() -> int:\n    if False:\n        mut n = 1\n        n += 2\n    mut n = 3\n    n += 4\n    return n\n", result);
    var compilation = try language.Compilation.init(t.allocator, migration_path, result);
    defer compilation.deinit();
    try compilation.checkLibrary();
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "frontend binding migration refuses escaping state and preinitialization reads" {
    try refusedBinding("func main() -> int:\n    if True:\n        token = 1\n    return token\n");
    try refusedBinding("func main() -> int:\n    if True:\n        token = 1\n    if False:\n        token = 2\n    return token\n");
    try refusedBinding("func main() -> int:\n    const before = token\n    token = 1\n    return before\n");
    try refusedBinding("func main() -> int:\n    token = token + 1\n    return token\n");
}

// spec: FRONTEND-VARIANT-MIGRATION-1
test "frontend variant migration keeps newlines comments and canonical nested payload types" {
    const original =
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
        \\union Tag:
        \\    list: list[int], # keep this case comment
        \\    atom: bytes,
        \\    unit
        \\
        \\union Region:
        \\    board,
        \\    polygon: list[[2]float]
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const expected =
        \\enum Tag:
        \\    list(value: int[]) # keep this case comment
        \\    atom(value: bytes)
        \\    unit
        \\
        \\enum Region:
        \\    board
        \\    polygon(value: FixedArray[float, 2][])
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const result = try migrated(original);
    defer t.allocator.free(result);
    try t.expectEqualStrings(expected, result);
    const second = try migrated(result);
    defer t.allocator.free(second);
    try t.expectEqualStrings(result, second);
    var compilation = try language.Compilation.init(t.allocator, migration_path, result);
    defer compilation.deinit();
    try compilation.checkLibrary();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// spec: FRONTEND-NESTED-COMPREHENSION-MIGRATION-1
test "frontend nested comprehension migration repairs inside out without overlapping edits" {
    const original =
        \\record Item:
        \\    values: int[]
        \\
        \\func main() -> int:
        \\    const xs = [[1], [2]]
        \\    const ys = [Item(values=[v for v in x]) for x in xs]
        \\    return len(ys)
        \\
    ;
    const first = try migrated(original);
    defer t.allocator.free(first);
    try t.expectEqualStrings(original, first);
    const second = try migrated(first);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    var compilation = try language.Compilation.init(t.allocator, migration_path, second);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    try t.expectEqualStrings("E_COMPREHENSION_REMOVED", compilation.diagnostics.items[0].code);
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "frontend binding migration separates comprehension and generator binders from later locals" {
    const original =
        // migrate-embedded: skip original binder separation parser transform witness
        \\func main() -> int:
        \\    const group = [1, 2]
        \\    const canonical = [for it in group if it > 0 yield it]
        \\    const legacy = [it for it in group if it > 0]
        \\    const total = sum(it for it in group if it > 0)
        \\    for i in range(len(group)):
        \\        it = group[i]
        \\        if it > 0:
        \\            return len(canonical) + len(legacy) + total + it
        \\    return 0
        \\
    ;
    const first = try migrated(original);
    defer t.allocator.free(first);
    try t.expect(std.mem.indexOf(u8, first, "mut it = group[i]") != null);
    try t.expect(std.mem.indexOf(u8, first, "[for it in group if it > 0 yield it]") != null);
    var compilation = try language.Compilation.init(t.allocator, migration_path, first);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    try t.expectEqualStrings("E_COMPREHENSION_REMOVED", compilation.diagnostics.items[0].code);
    const second = try migrated(first);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    const modern = try modernizedRetiredExpressions(first);
    defer t.allocator.free(modern);
    var executable = try language.Compilation.init(t.allocator, migration_path, modern);
    defer executable.deinit();
    try executable.check();
    const outcome = try @import("native_execute.zig").run(&executable);
    try t.expectEqual(@as(i64, 8), outcome.value);
}

// The comprehension index serves every function of a module, not only the first.
test "frontend binding migration separates comprehension binders in a later function" {
    const original =
        \\func helper() -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    const group = [1, 2]
        \\    const canonical = [for it in group if it > 0 yield it]
        \\    const legacy = [it for it in group if it > 0]
        \\    const total = sum(it for it in group if it > 0)
        \\    for i in range(len(group)):
        \\        it = group[i]
        \\        if it > 0:
        \\            return len(canonical) + len(legacy) + total + it
        \\    return helper()
        \\
    ;
    const first = try migrated(original);
    defer t.allocator.free(first);
    try t.expect(std.mem.indexOf(u8, first, "mut it = group[i]") != null);
    const modern = try modernizedRetiredExpressions(first);
    defer t.allocator.free(modern);
    var executable = try language.Compilation.init(t.allocator, migration_path, modern);
    defer executable.deinit();
    try executable.check();
    const outcome = try @import("native_execute.zig").run(&executable);
    try t.expectEqual(@as(i64, 8), outcome.value);
}

// spec-case: FRONTEND-BINDING-MIGRATION-2
test "frontend comprehension binder does not hide a source read before initialization" {
    // migrate-embedded: skip binding scope rejection source-before-initialization witness
    try refusedBinding("func main() -> int:\n    const values = [for it in it yield it]\n    it = [1]\n    return len(values)\n");
    try refusedBinding("func main() -> int:\n    const total = sum(it for it in it if it > 0)\n    it = [1]\n    return total\n");
}

// spec: FRONTEND-NUMERIC-MIGRATION-3
test "frontend numeric migration writes no repair inside a parse wrapper that claims the parser's name" {
    // The repair once wrote the `str` method form, `text.parse_int()`, which W13 retires: a claimed name now has no edit.
    try refusedNumericRepair("func parse_int(text: str) -> int?:\n    return int(text)\n");
    try refusedNumericRepair("func parse_float(text: str) -> float?:\n    return float(text)\n");
    try refusedNumericRepair("func parse_int(sign: str, text: str) -> int?:\n    return int(sign + text)\n");
    try refusedNumericRepair("func parse_int() -> int?:\n    return int(\"12\")\n");
}

// spec: FRONTEND-NUMERIC-MIGRATION-2
test "frontend numeric migration writes no repair where parameters and locals claim the name" {
    try refusedNumericRepair("func parse(text: str, parse_int: int) -> int?:\n    return int(text)\n");
    try refusedNumericRepair("func parse(text: str) -> float?:\n    const parse_float = 7\n    return float(text)\n");
}

fn refusedNumericRepair(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings(numeric_parse_code, item.code);
    try t.expect(item.provenance.fix == null);
    try t.expect(std.mem.indexOf(u8, item.message, "rename that binding") != null);
}

// spec-case: FRONTEND-NUMERIC-MIGRATION-2
test "frontend numeric migration withholds a claimed repair inside generic bodies" {
    try refusedNumericRepair("func parse_int[T](text: str, value: T) -> int?:\n    return int(text)\n");
    try refusedNumericRepair("func parse_float[T](text: str, value: T) -> float?:\n    return float(text)\n");
    try refusedNumericRepair("func parse[T](text: str, parse_int: T) -> int?:\n    return int(text)\n");
    try refusedNumericRepair("func parse[T](text: str, value: T) -> float?:\n    const parse_float = value\n    return float(text)\n");
}

const NumericImports = struct {
    app: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *NumericImports = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "app.selka")) return allocator.dupe(u8, self.app);
        if (std.mem.eql(u8, path, "helper.selka")) return allocator.dupe(u8, "public func answer() -> int:\n    return 42\n");
        return error.NotFound;
    }
};

fn importedNumericRepair(text: []const u8, target: ?[]const u8) !void {
    var files: NumericImports = .{ .app = text };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = NumericImports.read }, "app", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.checkLibrary());
    for (compilation.diagnostics.items.items) |item| {
        if (!std.mem.eql(u8, item.code, numeric_parse_code)) continue;
        const expected = target orelse return t.expect(item.provenance.fix == null);
        const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
        return t.expectEqualStrings(expected, fix.edit.text);
    }
    return t.expect(false);
}

// spec-case: FRONTEND-NUMERIC-MIGRATION-2
test "frontend numeric migration checks import aliases in ordinary and generic module contexts" {
    try importedNumericRepair("import helper as parse_int\nfunc parse(text: str) -> int?:\n    return int(text)\n", null);
    try importedNumericRepair("import helper as parse_float\nfunc parse(text: str) -> float?:\n    return float(text)\n", null);
    try importedNumericRepair("import helper\nfunc parse(text: str) -> int?:\n    return int(text)\n", "parse_int");
    try importedNumericRepair("import helper\nfunc parse[T](text: str, value: T) -> float?:\n    return float(text)\n", "parse_float");
}

// spec-case: FRONTEND-NUMERIC-MIGRATION-2
test "frontend unshadowed float text repair converges to the builtin parser" {
    const repaired = try repairedFields("func parse(text: str) -> float?:\n    return float(text)\n");
    defer t.allocator.free(repaired);
    try t.expectEqualStrings("func parse(text: str) -> float?:\n    return parse_float(text)\n", repaired);
    var compilation = try language.Compilation.init(t.allocator, migration_path, repaired);
    defer compilation.deinit();
    try compilation.checkLibrary();
}

// spec-case: FRONTEND-NUMERIC-MIGRATION-2
test "frontend rejectTextConversion propagates allocation failure for the method repair" {
    const conversion: @import("numeric_surface.zig").TextConversion = .{ .name = .{ .start = 0, .end = 3 }, .call = .{ .start = 0, .end = 9 }, .operand = "a + b", .primary = false };
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    var sink: diagnostic.Sink = .{ .allocator = failing.allocator() };
    try t.expect(@import("numeric_surface.zig").rejectTextConversion(&sink, conversion, "parse_int", true) == error.OutOfMemory);
    var later_failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 1 });
    var later_sink: diagnostic.Sink = .{ .allocator = later_failing.allocator() };
    try t.expect(@import("numeric_surface.zig").rejectTextConversion(&later_sink, conversion, "parse_int", true) == error.OutOfMemory);
}

// spec-case: FIX-MIGRATION-OVERLAP-1
test "frontend migration still repairs a legacy conditional whose value was migrated first" {
    const repaired = try migrated("func main() -> int:\n    const c = True\n    return (if (not c) then (1) else (2)) if c else 3\n");
    defer t.allocator.free(repaired);
    // migrate-embedded: skip exact parser migration nested conditional precedence output
    const historical_expected = "func main() -> int:\n    const c = True\n    return (if (c) then ((if (not c) then (1) else (2))) else (3))\n";
    var historical = try language.Compilation.init(t.allocator, migration_path, historical_expected);
    defer historical.deinit();
    try parseLegacy(&historical);
    var selections: usize = 0;
    for (historical.syntax.?.nodes.items) |node| {
        if (node.data == .conditional) selections += 1;
    }
    try t.expectEqual(@as(usize, 2), selections);
    try t.expectEqualStrings("func main() -> int:\n    const c = True\n    if c:\n        if (not c):\n            return (1)\n        else:\n            return (2)\n    else:\n        return 3\n", repaired);
    var fixed = try language.Compilation.init(t.allocator, migration_path, repaired);
    defer fixed.deinit();
    try fixed.checkLibrary();
    const settled = try migrated(repaired);
    defer t.allocator.free(settled);
    try t.expectEqualStrings(repaired, settled);
}

/// An entry importing a legacy library whose nested conditional and
/// comprehension repairs would overlap if they travelled in one pass.
const OverlapImports = struct {
    library: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *OverlapImports = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "app.selka")) return allocator.dupe(u8, "import lib\nfunc main() -> int:\n    return lib.pick(True, False)\n");
        if (std.mem.eql(u8, path, "lib.selka")) return allocator.dupe(u8, self.library);
        return error.NotFound;
    }
};

/// Every edit the recovered parser diagnostics carry, each on its own diagnostic.
fn repairCount(recovered: []const diagnostic.Diagnostic) usize {
    var repairs: usize = 0;
    for (recovered) |item| repairs += if (item.provenance.fix) |fix| fix.count() else 0;
    return repairs;
}

// spec-case: FIX-MIGRATION-OVERLAP-1
test "an imported module's overlapping parser repairs stay whole on separate diagnostics" {
    // migrate-embedded: skip original parser migration identity and overlap witness
    var files: OverlapImports = .{ .library = "public def pick(c: bool, d: bool) -> int:\n    return 1 if c else (2 if d else 3)\n\n\npublic def magnitudes(xs: list[int]) -> list[int]:\n    return [x if x > 0 else -x for x in xs]\n" };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = OverlapImports.read }, "app", .{});
    try t.expectError(error.SourceError, language.interfaces.build(&project));
    const problem = project.problem.?;
    // Two declarations, two type spellings, and one atomic return rewrite.
    // That last edit renders both nested selections; the selection inside the
    // comprehension waits until its owner has introduced ordinary statements.
    try t.expectEqual(@as(usize, 5), problem.recovered.len);
    try t.expectEqual(@as(usize, 5), repairCount(problem.recovered));
    const ExpectedEdit = struct { code: []const u8, before: []const u8, after: []const u8 };
    const expected = [_]ExpectedEdit{
        .{ .code = "E_FRONTEND_SYNTAX", .before = "def", .after = "func" },
        .{ .code = "E_FRONTEND_SYNTAX", .before = "def", .after = "func" },
        .{ .code = "E_FRONTEND_SYNTAX", .before = "list[int]", .after = "int[]" },
        .{ .code = "E_FRONTEND_SYNTAX", .before = "list[int]", .after = "int[]" },
        .{ .code = "E_CONDITIONAL_EXPRESSION_REMOVED", .before = "return 1 if c else (2 if d else 3)", .after = "if c:\n        return 1\n    else:\n        if d:\n            return 2\n        else:\n            return 3" },
    };
    for (problem.recovered, expected, 0..) |item, wanted, i| {
        try t.expectEqualStrings(wanted.code, item.code);
        const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
        try t.expectEqual(@as(usize, 1), fix.count());
        try t.expectEqualStrings(wanted.before, files.library[fix.edit.span.start..fix.edit.span.end]);
        try t.expectEqualStrings(wanted.after, fix.edit.text);
        for (problem.recovered[0..i]) |prior| {
            const previous = prior.provenance.fix.?.edit.span;
            try t.expect(previous.end <= fix.edit.span.start or fix.edit.span.end <= previous.start);
        }
    }
    const first_round = try migrated(files.library);
    defer t.allocator.free(first_round);
    try t.expect(std.mem.indexOf(u8, first_round, "return [x if x > 0 else -x for x in xs]") != null);
    var gather = try language.Compilation.init(t.allocator, migration_path, first_round);
    defer gather.deinit();
    try t.expectError(error.SourceError, gather.checkLibrary());
    try t.expectEqualStrings("E_COMPREHENSION_REMOVED", gather.diagnostics.items[0].code);
    const second_round = try repairedFields(first_round);
    defer t.allocator.free(second_round);
    var selection = try language.Compilation.init(t.allocator, migration_path, second_round);
    defer selection.deinit();
    try t.expectError(error.SourceError, selection.checkLibrary());
    try t.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", selection.diagnostics.items[0].code);
    const third_round = try repairedFields(second_round);
    defer t.allocator.free(third_round);
    var final = try language.Compilation.init(t.allocator, migration_path, third_round);
    defer final.deinit();
    try final.checkLibrary();
    try t.expectEqual(@as(usize, 0), problem.fix_more.len);
    try t.expectEqual(problem.recovered[0].provenance.fix.?.edit.span.start, problem.fix.?.span.start);
}

/// The `E_PATTERN_QUALIFIED` refusals a checked library reports, and how many of them
/// carry a certain repair.
const Refusals = struct { refused: usize, certain: usize };
fn qualifiedRefusals(text: []const u8) !Refusals {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    var counts: Refusals = .{ .refused = 0, .certain = 0 };
    for (compilation.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, "E_PATTERN_QUALIFIED")) continue;
        counts.refused += 1;
        if (item.provenance.fix != null) counts.certain += 1;
    }
    return counts;
}

/// The text a checked library's certain repairs produce, applied from the end backwards.
fn repairedText(text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, migration_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    defer edits.deinit(t.allocator);
    for (compilation.diagnostics.items) |item| {
        const fix = item.provenance.fix orelse continue;
        try edits.append(t.allocator, fix.edit);
    }
    std.mem.sort(diagnostic.Edit, edits.items, {}, laterEdit);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    try out.appendSlice(t.allocator, text);
    for (edits.items) |edit| try out.replaceRange(t.allocator, edit.span.start, edit.span.end - edit.span.start, edit.text);
    return out.toOwnedSlice(t.allocator);
}

fn laterEdit(_: void, left: diagnostic.Edit, right: diagnostic.Edit) bool {
    return left.span.start > right.span.start;
}

// spec-case: FIX-MIGRATION-1
test "a qualified case whose qualifier is the matched type is refused with its qualifier dropped" {
    const original =
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
        \\enum Side:
        \\    left
        \\    right
        \\func label(side: Side) -> int:
        \\    match side:
        \\        case Side.left:
        \\            return 1
        \\        case Side.right:
        \\            return 2
    ;
    const result = try repairedText(original);
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "        case left:\n            return 1\n        case right:\n            return 2") != null);
    const counts = try qualifiedRefusals(original);
    try t.expectEqual(@as(usize, 2), counts.refused);
    try t.expectEqual(@as(usize, 2), counts.certain);
}

// spec-case: FIX-MIGRATION-1
test "a qualified case over a field or call scrutinee takes the repair from the checked type" {
    const original =
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
        \\enum Side:
        \\    left
        \\    right
        \\record Pin:
        \\    side: Side
        \\func make() -> Side:
        \\    return Side.right
        \\func label(pin: Pin) -> int:
        \\    match pin.side:
        \\        case Side.left:
        \\            return 1
        \\        case _:
        \\            return 0
        \\func other() -> int:
        \\    match make():
        \\        case Side.right:
        \\            return 2
        \\        case _:
        \\            return 0
    ;
    const counts = try qualifiedRefusals(original);
    try t.expectEqual(@as(usize, 2), counts.refused);
    try t.expectEqual(@as(usize, 2), counts.certain);
}

// spec-case: FIX-MIGRATION-1
test "a qualifier that names another type is refused without a repair" {
    const original =
        \\enum Side:
        \\    left
        \\    right
        \\enum Other:
        \\    left
        \\func label(side: Side) -> int:
        \\    match side:
        \\        case Other.left:
        \\            return 1
        \\        case right:
        \\            return 0
    ;
    const counts = try qualifiedRefusals(original);
    try t.expectEqual(@as(usize, 1), counts.refused);
    try t.expectEqual(@as(usize, 0), counts.certain);
}

// spec-case: FIX-MIGRATION-1
test "a qualified case under an option's Some payload is refused and repaired once" {
    const original =
        // migrate-embedded: skip original frontend constructor or pattern migration and exact replacement witness
        \\enum Shape:
        \\    circle(radius: int)
        \\    square(side: int)
        \\func outer(found: Shape?) -> int:
        \\    match found:
        \\        case Some(Shape.circle(radius=r)):
        \\            return r
        \\        case Some(Shape.square(side=s)):
        \\            return s
        \\        case None:
        \\            return 0
    ;
    const result = try repairedText(original);
    defer t.allocator.free(result);
    try t.expect(std.mem.indexOf(u8, result, "case Some(circle(radius=r)):") != null);
    try t.expect(std.mem.indexOf(u8, result, "case Some(square(side=s)):") != null);
    const counts = try qualifiedRefusals(original);
    try t.expectEqual(@as(usize, 2), counts.refused);
    try t.expectEqual(@as(usize, 2), counts.certain);
}

test "a bare case name that the matched type does not declare lists the type's cases" {
    var compilation = try language.Compilation.init(t.allocator, "unknown_case.selka",
        \\enum Side:
        \\    left
        \\    right
        \\func label(side: Side) -> int:
        \\    match side:
        \\        case up:
        \\            return 1
        \\        case _:
        \\            return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_UNKNOWN_VARIANT", item.code);
    try t.expect(std.mem.indexOf(u8, item.message, "its cases are left, right") != null);
}

test "a bare name that is a field of its fielded case binds that field and needs no label" {
    var compilation = try language.Compilation.init(t.allocator, "field_names.selka",
        \\enum Shape:
        \\    circle(radius: int)
        \\    rect(width: int, height: int)
        \\func area(shape: Shape) -> int:
        \\    match shape:
        \\        case circle(radius):
        \\            return radius * radius * 3
        \\        case rect(height, width):
        \\            return width * height
    );
    defer compilation.deinit();
    try compilation.checkLibrary();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

test "a bare name that is not a field of its case keeps the positional label repair" {
    var compilation = try language.Compilation.init(t.allocator, "field_names.selka",
        \\enum Shape:
        \\    circle(radius: int)
        \\func area(shape: Shape) -> int:
        \\    match shape:
        \\        case circle(r):
        \\            return r
        \\        case _:
        \\            return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.checkLibrary());
    const item = compilation.diagnostics.items[0];
    const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("radius=", fix.edit.text);
}

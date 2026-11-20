//! Canonical formatter regressions: noncanonical input becomes fixed canonical
//! bytes, a second format is byte-stable, comments and literal text survive, and
//! formatted programs still run. The formatter never type-checks, so these tests
//! keep the parse-only drafts and unresolved modules that `fmt` must still accept.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const formatter = @import("formatter.zig");
const lexer = language.lexer;
const diagnostics = language.diagnostic;
const native = @import("native_execute.zig");

const canonical_path = "canonical.selka";

fn formatOnce(allocator: std.mem.Allocator, path: []const u8, text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    return compilation.format(allocator);
}

fn formatModuleOnce(allocator: std.mem.Allocator, path: []const u8, text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    return compilation.formatModule(allocator);
}

/// Every quoting shape canonicalizes to the spelling `expected` and settles there.
fn expectLiteral(expected: []const u8, input: []const u8) !void {
    const text = try formatter.canonicalLiteral(t.allocator, input);
    defer t.allocator.free(text);
    try t.expectEqualStrings(expected, text);
    const settled = try formatter.canonicalLiteral(t.allocator, text);
    defer t.allocator.free(settled);
    try t.expectEqualStrings(expected, settled);
}

fn expectCanonical(allocator: std.mem.Allocator, input: []const u8, expected: []const u8) !void {
    const formatted = try formatOnce(allocator, canonical_path, input);
    defer allocator.free(formatted);
    try t.expectEqualStrings(expected, formatted);
    const twice = try formatOnce(allocator, canonical_path, formatted);
    defer allocator.free(twice);
    try t.expectEqualStrings(expected, twice);
}

fn expectCanonicalModule(allocator: std.mem.Allocator, input: []const u8, expected: []const u8) !void {
    const formatted = try formatModuleOnce(allocator, canonical_path, input);
    defer allocator.free(formatted);
    try t.expectEqualStrings(expected, formatted);
    const twice = try formatModuleOnce(allocator, canonical_path, formatted);
    defer allocator.free(twice);
    try t.expectEqualStrings(expected, twice);
}

// Both historical formatter operands remain executable removal witnesses.
fn expectRetiredFormatting(allocator: std.mem.Allocator, module: bool, input: []const u8, expected: []const u8) !void {
    for ([_][]const u8{ input, expected }) |text| {
        var compilation = try language.Compilation.init(allocator, canonical_path, text);
        defer compilation.deinit();
        if (module) {
            try t.expectError(error.SourceError, compilation.formatModule(allocator));
        } else {
            try t.expectError(error.SourceError, compilation.format(allocator));
        }
        try t.expect(compilation.diagnostics.items.len != 0);
        for (compilation.diagnostics.items) |item| try t.expectEqualStrings("E_EFFECTS_REMOVED", item.code);
    }
}

// spec: FMT-1
test "formatter lays a multi-line delimiter out one item per line with a trailing comma" {
    try expectCanonical(t.allocator,
        \\func add(a: int, b: int) -> int:
        \\    return a + b
        \\
        \\
        \\func main() -> int:
        \\    const xs = [
        \\        1,
        \\        2,
        \\    ]
        \\    const total = add(
        \\        xs[0],
        \\        xs[1],
        \\    )
        \\    return total
        \\
    ,
        \\func add(a: int, b: int) -> int:
        \\    return a + b
        \\
        \\
        \\func main() -> int:
        \\    const xs = [
        \\        1,
        \\        2,
        \\    ]
        \\    const total = add(
        \\        xs[0],
        \\        xs[1],
        \\    )
        \\    return total
        \\
    );
}

// spec: FMT-1
test "formatter adds the trailing comma a multi-line list's last item lacks" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    const xs = [
        \\        1,
        \\        2
        \\    ]
        \\    return xs[0]
        \\
    ,
        \\func main() -> int:
        \\    const xs = [
        \\        1,
        \\        2,
        \\    ]
        \\    return xs[0]
        \\
    );
}

// spec: FMT-1
test "formatter keeps a trailing comment on its item's line inside a multi-line list" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    const xs = [
        \\        1, # the first value
        \\        # the second value
        \\        2, # the last one
        \\    ]
        \\    return xs[0]
        \\
    ,
        \\func main() -> int:
        \\    const xs = [
        \\        1, # the first value
        \\        # the second value
        \\        2, # the last one
        \\    ]
        \\    return xs[0]
        \\
    );
}

// spec: FMT-1
test "formatter collapses a one-line delimiter, an empty multi-line one and a multi-line subscript" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    const xs = [1, 2, 3]
        \\    const a = xs[
        \\        1
        \\    ]
        \\    const b = add(
        \\    )
        \\    return a + b
        \\
        \\
        \\func add() -> int:
        \\    return 0
        \\
    ,
        \\func main() -> int:
        \\    const xs = [1, 2, 3]
        \\    const a = xs[1]
        \\    const b = add()
        \\    return a + b
        \\
        \\
        \\func add() -> int:
        \\    return 0
        \\
    );
}

// spec: FMT-1
test "formatter nests one-item-per-line delimiters by their own indentation" {
    try expectCanonical(t.allocator,
        \\func add(a: int, b: int) -> int:
        \\    return a + b
        \\
        \\
        \\func main() -> int:
        \\    const total = add(
        \\        add(
        \\            1,
        \\            2,
        \\        ),
        \\        3,
        \\    )
        \\    return total
        \\
    ,
        \\func add(a: int, b: int) -> int:
        \\    return a + b
        \\
        \\
        \\func main() -> int:
        \\    const total = add(
        \\        add(
        \\            1,
        \\            2,
        \\        ),
        \\        3,
        \\    )
        \\    return total
        \\
    );
}

/// How many opening delimiters the pre-scan marks; a helper keeps the test body
/// straight-line, as the gate requires of a test.
fn markedOpeners(breaks: []const bool) usize {
    var count: usize = 0;
    for (breaks) |mark| {
        if (mark) count += 1;
    }
    return count;
}

// spec: FMT-1
test "formatter delimiter pre-scan marks the multi-line item lists" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sink: diagnostics.Sink = .{ .allocator = arena };
    const source = "func main() -> int:\n    const xs = [\n        1,\n    ]\n    return xs[0]\n";
    const tokens = try lexer.lex(arena, source, &sink);
    const breaks = try formatter.multilineDelimiters(arena, source, tokens);
    try t.expectEqual(@as(usize, 1), markedOpeners(breaks));
    try t.expectEqual(tokens.len, breaks.len);
}

// spec: FMT-1
test "formatter delimiter pre-scan leaves a multi-line subscript and an empty list alone" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sink: diagnostics.Sink = .{ .allocator = arena };
    const source = "func main() -> int:\n    const xs = [1]\n    const a = xs[\n        0\n    ]\n    const b = add(\n    )\n    return a + b\n";
    const tokens = try lexer.lex(arena, source, &sink);
    const breaks = try formatter.multilineDelimiters(arena, source, tokens);
    try t.expectEqual(@as(usize, 0), markedOpeners(breaks));
}

/// Sort a small import block through every allocation failure, so the post-pass's
/// error path is exercised as well as its ordering.
fn sortImportsOnce(allocator: std.mem.Allocator) !void {
    const text = "import zed\nimport alpha\n\nfunc main() -> int:\n    return 0\n";
    const sorted = try formatter.sortImports(allocator, text);
    defer allocator.free(sorted);
    try t.expect(std.mem.startsWith(u8, sorted, "import alpha\nimport zed\n"));
}

// spec: FMT-1
test "formatter import sort releases its storage under allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, sortImportsOnce, .{});
    // Names the post-pass in the test body itself, which is where the gate's
    // error-path check looks as well as at the failure sweep.
    const direct = try formatter.sortImports(t.allocator, "import zed\nimport alpha\n");
    defer t.allocator.free(direct);
    try t.expect(std.mem.startsWith(u8, direct, "import alpha\nimport zed\n"));
}

// spec: FMT-1
test "formatter sorts a run of imports by module path and keeps each line whole" {
    try expectCanonical(t.allocator,
        \\import zed
        \\import alpha as a  # the alias
        \\import model.core
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ,
        \\import alpha as a # the alias
        \\import model.core
        \\import zed
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

// spec: FMT-1
test "formatter keeps two import groups apart when a comment line separates them" {
    try expectCanonical(t.allocator,
        \\import zed
        \\# the second group
        \\import alpha
        \\import beta
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ,
        \\import zed
        \\# the second group
        \\import alpha
        \\import beta
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

// spec: FMT-1
test "formatter canonicalizes a literal through canonicalLiteral for each quoting shape" {
    // A bare single-quoted word becomes double-quoted.
    try expectLiteral("\"plain\"", "'plain'");
    // Text that holds a double quote and no single one keeps single quotes.
    try expectLiteral("'has \"double\"'", "'has \"double\"'");
    // Text that holds both uses double quotes: the single quote is unescaped and
    // the double quote is escaped, so the value is unchanged.
    try expectLiteral("\"both ' and \\\"\"", "'both \\' and \"'");
    // A double-quoted literal with nothing to change keeps its spelling.
    try expectLiteral("\"already double\"", "\"already double\"");
    // A quote escape the chosen delimiter does not need is dropped.
    try expectLiteral("\"it's\"", "'it\\'s'");
    // The byte and format prefixes carry through.
    try expectLiteral("b\"bytes\"", "b'bytes'");
    try expectLiteral("f\"{value}\"", "f'{value}'");
    // A docstring literal keeps its delimiters and its body byte for byte.
    try expectLiteral("'''first line\nsecond line'''", "'''first line\nsecond line'''");
}

// spec: FMT-1
test "formatter writes a canonical quoting in a whole program" {
    try expectCanonical(t.allocator,
        \\func f() -> str:
        \\    const a = 'plain'
        \\    const b = 'has "double"'
        \\    const c = 'both \' and "'
        \\    return a + b + c
        \\
    ,
        \\func f() -> str:
        \\    const a = "plain"
        \\    const b = 'has "double"'
        \\    const c = "both ' and \""
        \\    return a + b + c
        \\
    );
}

// spec-case: EFFECTS-REMOVED-1
test "formatter keeps the space between a bracketed return type and its effect clause" {
    try expectRetiredFormatting(t.allocator, true,
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\
        \\
        \\public func find(values: int[]) -> int? effects():
        \\    return None
        \\
        \\
        \\func keys(pick: func(int) -> int? effects(), xs: int[]) -> int[] noalloc:
        \\    return xs
        \\
        \\
        \\func first(xs: Point[]) -> int:
        \\    return xs[0].x
    ,
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\public func find(values: int[]) -> int? effects():
        \\    return None
        \\
        \\
        \\func keys(pick: func(int) -> int? effects(), xs: int[]) -> int[] noalloc:
        \\    return xs
        \\
        \\
        \\func first(xs: Point[]) -> int:
        \\    return xs[0].x
        \\
    );
    try expectCanonicalModule(t.allocator,
        \\
        \\
        \\public func find(values: int[]) -> int?:
        \\    return None
        \\
        \\
        \\@noalloc
        \\func keys(pick: func(int) -> int?, xs: int[]) -> int[]:
        \\    return xs
        \\
        \\
        \\func first(xs: Point[]) -> int:
        \\    return xs[0].x
    ,
        \\public func find(values: int[]) -> int?:
        \\    return None
        \\
        \\
        \\@noalloc
        \\func keys(pick: func(int) -> int?, xs: int[]) -> int[]:
        \\    return xs
        \\
        \\
        \\func first(xs: Point[]) -> int:
        \\    return xs[0].x
        \\
    );
    // The standard library's own signatures are already canonical.
    const sort_source = @embedFile("stdlib/sort.selka");
    const formatted = try formatModuleOnce(t.allocator, "sort.selka", sort_source);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "]effects(") == null);
    try t.expect(std.mem.indexOf(u8, formatted, "effects(") == null);
    try t.expect(std.mem.indexOf(u8, formatted, "-> int?:") != null);
}

// spec: TOOL-5
test "formatter canonicalizes operator and assignment spacing" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    mut value=  40+2
        \\    return value*3-1
    ,
        \\func main() -> int:
        \\    mut value = 40 + 2
        \\    return value * 3 - 1
        \\
    );
}

// spec-case: TOOL-5
test "formatter preserves comments, literal values and precedence" {
    try expectCanonical(t.allocator,
        \\# heading
        \\func main() -> i64: # suite note
        \\    # leading note
        \\    mut raw = "a  b # not a comment"
        \\    mut data = b"raw bytes"
        \\    mut label = f"v={ 1+2 }"
        \\    mut value=  40+2 # trailing
        \\    return value + strings.char_count(raw) + len(data) + strings.char_count(label)
    ,
        \\# heading
        \\func main() -> i64: # suite note
        \\    # leading note
        \\    mut raw = "a  b # not a comment"
        \\    mut data = b"raw bytes"
        \\    mut label = f"v={ 1+2 }"
        \\    mut value = 40 + 2 # trailing
        \\    return value + strings.char_count(raw) + len(data) + strings.char_count(label)
        \\
    );
}

// spec-case: TOOL-5
test "formatter normalizes unary operators and nested blocks" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    mut x=-1+2*3
        \\    mut y=not x==0
        \\    if x>0:
        \\        while x>1:
        \\            x-=1
        \\            if x==2:
        \\                x=x+1
        \\            else:
        \\                break
        \\    return x
    ,
        \\func main() -> int:
        \\    mut x = -1 + 2 * 3
        \\    mut y = not x == 0
        \\    if x > 0:
        \\        while x > 1:
        \\            x -= 1
        \\            if x == 2:
        \\                x = x + 1
        \\            else:
        \\                break
        \\    return x
        \\
    );
}

// spec-case: TOOL-5
test "formatter preserves generics, named constraints and slices" {
    try expectRetiredFormatting(t.allocator, false,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\func sum[T: integer](value: T) -> T:
        \\    return value+value
        \\
        \\func score[T: copy+op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\
        \\constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\func first(xs: int[]) -> int:
        \\    return xs[ 1 : 2 ][0]
    ,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\func sum[T: integer](value: T) -> T:
        \\    return value + value
        \\
        \\
        \\func score[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\
        \\
        \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\func first(xs: int[]) -> int:
        \\    return xs[1:2][0]
        \\
    );
    try expectCanonical(t.allocator,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        \\func sum[T: integer](value: T) -> T:
        \\    return value+value
        \\
        \\func score[T: copy+op(score(item: T) -> int)](item: T) -> int:
        \\    return T.score(item)
        \\
        \\constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int)
        \\
        \\func first(xs: int[]) -> int:
        \\    return xs[ 1 : 2 ][0]
    ,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        \\func sum[T: integer](value: T) -> T:
        \\    return value + value
        \\
        \\
        \\func score[T: copy + op(score(item: T) -> int)](item: T) -> int:
        \\    return T.score(item)
        \\
        \\
        \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int)
        \\
        \\
        \\func first(xs: int[]) -> int:
        \\    return xs[1:2][0]
        \\
    );
}

// spec-case: TOOL-5
test "top-level declarations get two blank lines and the header group one" {
    try expectCanonical(t.allocator,
        \\func a() -> int:
        \\    return 1
        \\func b() -> int:
        \\    return 2
        \\func c() -> int:
        \\    return 3
    ,
        \\func a() -> int:
        \\    return 1
        \\
        \\
        \\func b() -> int:
        \\    return 2
        \\
        \\
        \\func c() -> int:
        \\    return 3
        \\
    );
}

// spec-case: TOOL-5
test "a block of one-line constants and the comment above it stay together" {
    try expectCanonical(t.allocator,
        \\import strings
        \\
        \\# Phases of a request.
        \\const PHASE_HEAD: int = 0
        \\const PHASE_FIXED: int = 1
        \\public const PHASE_BODY: int = 2
        \\func a() -> int:
        \\    return PHASE_HEAD
    ,
        \\import strings
        \\
        \\# Phases of a request.
        \\const PHASE_HEAD: int = 0
        \\const PHASE_FIXED: int = 1
        \\public const PHASE_BODY: int = 2
        \\
        \\
        \\func a() -> int:
        \\    return PHASE_HEAD
        \\
    );
}

// spec-case: TOOL-5
test "constants a blank line apart or spread over lines keep two blank lines" {
    try expectCanonical(t.allocator,
        \\const A: int = 1
        \\
        \\const B: int = 2
        \\const C: int[] = [
        \\    1,
        \\    2,
        \\]
        \\const D: int = 3
        \\const E: int = 4
    ,
        \\const A: int = 1
        \\
        \\
        \\const B: int = 2
        \\
        \\
        \\const C: int[] = [
        \\    1,
        \\    2,
        \\]
        \\
        \\
        \\const D: int = 3
        \\const E: int = 4
        \\
    );
}

// spec-case: TOOL-5
test "a comment between two adjacent constants stays between them" {
    try expectCanonical(t.allocator,
        \\const A: int = 1
        \\# the second
        \\const B: int = 2
        \\# a function
        \\func f() -> int:
        \\    return A + B
    ,
        \\const A: int = 1
        \\# the second
        \\const B: int = 2
        \\
        \\
        \\# a function
        \\func f() -> int:
        \\    return A + B
        \\
    );
}

// spec-case: TOOL-5
test "empty, whitespace-only and comment-only inputs have explicit fixtures" {
    try expectCanonical(t.allocator, "", "");
    try expectCanonical(t.allocator, "  \n\t\n", "");
    try expectCanonical(t.allocator, " # one\n\n# two", "# one\n# two\n");
}

// spec-case: TOOL-5
test "module formatter canonicalizes headers, directives and unresolved drafts" {
    try expectRetiredFormatting(t.allocator, true,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\import contracts.missing as c
        \\
        \\
        \\
        \\public constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\
        \\func total[P: c.Prices](policy: P, subtotal: int) -> int effects():
        \\    return policy.price(policy=policy, subtotal=subtotal)
    ,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\import contracts.missing as c
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\func total[P: c.Prices](policy: P, subtotal: int) -> int effects():
        \\    return policy.price(policy=policy, subtotal=subtotal)
        \\
    );
    try expectCanonicalModule(t.allocator,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        \\import contracts.missing as c
        \\
        \\
        \\
        \\public constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int)
        \\
        \\
        \\
        \\func total[P: c.Prices](policy: P, subtotal: int) -> int:
        \\    return policy.price(policy=policy, subtotal=subtotal)
    ,
        // migrate-embedded: skip intentional formatter syntax recognition and exact canonical bytes
        \\import contracts.missing as c
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int)
        \\
        \\
        \\func total[P: c.Prices](policy: P, subtotal: int) -> int:
        \\    return policy.price(policy=policy, subtotal=subtotal)
        \\
    );
}

// spec-case: TOOL-5
test "formatting a program preserves its native execution result" {
    const input =
        \\func total(values: int[]) -> int:
        \\    mut sum=0
        \\    for value in values:
        \\        sum+=value
        \\    return sum
        \\
        \\func main() -> i64:
        \\    mut values=[1,2,3,4]
        \\    mut doubled=total(values)*2
        \\    return doubled+len(values)
    ;
    var before = try language.Compilation.init(t.allocator, "before.selka", input);
    defer before.deinit();
    const before_run = try native.run(&before);
    try t.expect(!before_run.failed);
    try t.expectEqual(@as(i64, 24), before_run.value);

    const formatted = try before.format(t.allocator);
    defer t.allocator.free(formatted);

    var after = try language.Compilation.init(t.allocator, "after.selka", formatted);
    defer after.deinit();
    const after_run = try native.run(&after);
    try t.expect(!after_run.failed);
    try t.expectEqual(before_run.value, after_run.value);
}

test "formatter orders borrowing sources by parameters before fails and preserves comments" {
    try expectCanonical(t.allocator,
        \\func choose(a: Json, long_source: Json)->Json? from long_source,a fails Error: # keep
        \\    return a
        \\
        \\func other(len: str, fallback: str) -> str from fallback,len:
        \\    return fallback
    ,
        \\func choose(a: Json, long_source: Json) -> Json? from a, long_source fails Error: # keep
        \\    return a
        \\
        \\
        \\func other(len: str, fallback: str) -> str from len, fallback:
        \\    return fallback
        \\
    );
}

test "formatter keeps unresolved borrowing drafts and contextual names parseable" {
    try expectCanonical(t.allocator,
        \\func choose(a: Unknown, b: Unknown)->FixedArray[Unknown, 2] from missing,b,a:
        \\    return unresolved
        \\
        \\func from(first: Unknown, from: Unknown)->Unknown from from,first,from:
        \\    return from
    ,
        \\func choose(a: Unknown, b: Unknown) -> FixedArray[Unknown, 2] from missing, b, a:
        \\    return unresolved
        \\
        \\
        \\func from(first: Unknown, from: Unknown) -> Unknown from first, from, from:
        \\    return from
        \\
    );
}

test "O4 own formatter preserves contextual calls subscripts and marker spacing" {
    try expectCanonical(t.allocator,
        // migrate-embedded: skip intentional O4 formatter input marker spacing and contextual syntax
        \\func draft():
        \\    const borrowed=source
        \\    const moved=own    source
        \\    const fresh=own make()
        \\    const grouped=(own left)+right
        \\    const call=own(value)
        \\    const indexed=own[0:2]
        \\    const boxed=Row(items=own value)
        \\    return own moved
    ,
        // migrate-embedded: skip intentional O4 formatter output exact canonical marker bytes
        \\func draft():
        \\    const borrowed = source
        \\    const moved = own source
        \\    const fresh = own make()
        \\    const grouped = (own left) + right
        \\    const call = own(value)
        \\    const indexed = own[0:2]
        \\    const boxed = Row(items=own value)
        \\    return own moved
        \\
    );
}

fn failureScenario(allocator: std.mem.Allocator) !void {
    const input =
        \\# draft
        \\func unfinished(x: Unknown, backup: Unknown) -> FixedArray[Unknown, 2] from backup, x: # keep
        \\    mut value=  40+2
        \\    # note
        \\    return missing(x)+value
        \\
        \\func other(first: Unknown, last: Unknown) -> Unknown from last, first:
        \\    return first
    ;
    const formatted = try formatOnce(allocator, "failure.selka", input);
    defer allocator.free(formatted);
    const twice = try formatOnce(allocator, "failure.selka", formatted);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec-case: TOOL-5
test "formatter allocation failures release borrowing copies collectComments and collectTopStarts storage" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), failureScenario, .{});
}

// spec: FMT-MODULE-DETECT-1
test "fmt accepts headerless imported modules and standalone declarations" {
    const module_text = "\n\nfunc twice(x: int) -> int:\n    return x*2\n";
    const formatted = try formatOnce(t.allocator, "calc.selka", module_text);
    defer t.allocator.free(formatted);
    const expected = try formatModuleOnce(t.allocator, "calc.selka", module_text);
    defer t.allocator.free(expected);
    try t.expectEqualStrings(expected, formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "x * 2") != null);
    const script = "# a script\nimport math\n\n\nfunc main() -> int:\n    return int(math.floor(2.5))\n";
    const imported = try formatOnce(t.allocator, "script.selka", script);
    defer t.allocator.free(imported);
    const imported_module = try formatModuleOnce(t.allocator, "script.selka", script);
    defer t.allocator.free(imported_module);
    try t.expectEqualStrings(imported_module, imported);
    try t.expect(!language.opensAsModule("func module_count() -> int:\n    return 0\n"));
    try t.expect(!language.opensAsModule("# module notes\nmodulex = 1\n"));
}

test "formatter still rejects invalid syntax and reports its source diagnostic" {
    const invalid =
        \\def main() -> i64:
        \\    return +
    ;
    var compilation = try language.Compilation.init(t.allocator, "invalid.selka", invalid);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.format(t.allocator));
}

// spec: MUT-PARAM-6
test "formatter keeps the mut parameter and the mut argument marker canonical" {
    const expected =
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\func replace_first(mut values: int[], replacement: int) -> Unit effects(mutation):
        \\    values[0] = replacement
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    replace_first(mut values, replacement=2)
        \\    return values[0] - 2
        \\
    ;
    const unformatted =
        // migrate-embedded: skip intentional original effect-clause formatter input/output
        \\func replace_first(mut values: int[],  replacement: int) -> Unit   effects(mutation):
        \\    values[0] = replacement
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    replace_first(  mut   values , replacement = 2 )
        \\    return values[0] - 2
        \\
    ;
    try expectRetiredFormatting(t.allocator, false, unformatted, expected);
    const modern_expected =
        \\func replace_first(mut values: int[], replacement: int) -> Unit:
        \\    values[0] = replacement
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    replace_first(mut values, replacement=2)
        \\    return values[0] - 2
        \\
    ;
    const modern_unformatted =
        \\func replace_first(mut values: int[],  replacement: int) -> Unit:
        \\    values[0] = replacement
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    replace_first(  mut   values , replacement = 2 )
        \\    return values[0] - 2
        \\
    ;
    try expectCanonical(t.allocator, modern_unformatted, modern_expected);
}

// spec: ATTR-1
test "formatter round-trips declaration attributes beside their definition" {
    try expectCanonical(t.allocator,
        \\@deprecated(  "use square_v2" )
        \\func square(x: int) -> int:
        \\    return x*x
        \\@test
        \\func square_of_three() -> bool:
        \\    return square(3)==9
        \\@allow( "dead-private" , reason = "kept" )
        \\func helper() -> int:
        \\    return 1
    ,
        \\@deprecated("use square_v2")
        \\func square(x: int) -> int:
        \\    return x * x
        \\
        \\
        \\@test
        \\func square_of_three() -> bool:
        \\    return square(3) == 9
        \\
        \\
        \\@allow("dead-private", reason="kept")
        \\func helper() -> int:
        \\    return 1
        \\
    );
}

// spec-case: TOOL-5
test "formatter round-trips triple-quoted docstrings with newlines and hashes" {
    try expectCanonical(t.allocator,
        \\func area(width: int, height: int) -> int:
        \\    """The rectangle's area.
        \\
        \\    # a hash stays literal
        \\    """
        \\    return width * height
        \\
        \\
        \\func tail() -> int:
        \\    """First line
        \\    second line ends here"""
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    return area(2, 7) + tail()
    ,
        \\func area(width: int, height: int) -> int:
        \\    """The rectangle's area.
        \\
        \\    # a hash stays literal
        \\    """
        \\    return width * height
        \\
        \\
        \\func tail() -> int:
        \\    """First line
        \\    second line ends here"""
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    return area(2, 7) + tail()
        \\
    );
}

// spec: PARSE-RECOVERY-1
test "parser recovery reports independent statements across newline and dedent" {
    const input =
        \\func broken() -> int:
        \\    const first = +
        \\    if True:
        \\        const nested = +
        \\    const last = +
        \\    return 0
        \\
        \\func another() -> int:
        \\    const separate = +
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "recovery.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expect(compilation.syntax == null);
    try t.expectEqual(@as(usize, 4), compilation.diagnostics.items.len);
    const lines = [_]usize{ 2, 4, 5, 9 };
    for (compilation.diagnostics.items, lines) |diagnostic, line| {
        try t.expectEqualStrings("E_EXPRESSION", diagnostic.code);
        try t.expectEqual(line, compilation.src.locate(diagnostic.span.start).line);
        try t.expect(diagnostic.span.end <= input.len);
    }
    try t.expectEqualStrings(input, compilation.src.bytes);
}

// spec-case: PARSE-RECOVERY-1
test "parser recovery rejects formatting and recovers declaration headers" {
    const input =
        \\func bad(first int) -> int:
        \\    return 0
        \\
        \\func second() -> int:
        \\    const value = +
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "headers.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.format(t.allocator));
    try t.expect(compilation.syntax == null);
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    try t.expectEqual(@as(usize, 1), compilation.src.locate(compilation.diagnostics.items[0].span.start).line);
    try t.expectEqual(@as(usize, 5), compilation.src.locate(compilation.diagnostics.items[1].span.start).line);
    try t.expectEqualStrings(input, compilation.src.bytes);
}

// spec-case: PARSE-RECOVERY-1
test "parser recovery withholds structural migration fixes from malformed syntax" {
    const input =
        \\def legacy() -> i64:
        \\    return 0
        \\
        \\func broken() -> int:
        \\    const value = +
    ;
    var compilation = try language.Compilation.init(t.allocator, "migration.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expect(compilation.diagnostics.items[0].provenance.fix == null);
    try t.expect(compilation.syntax == null);
}

// spec-case: PARSE-RECOVERY-1
test "parser recovery preserves next statement when missing expression consumed its head" {
    const input =
        \\func broken() -> int:
        \\    const first =
        \\    const second = +
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "missing.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    try t.expectEqualStrings("const", compilation.src.text(compilation.diagnostics.items[0].span));
    try t.expectEqualStrings("+", compilation.src.text(compilation.diagnostics.items[1].span));
}

fn boundedRecoveryMutations() !void {
    const input =
        \\func helper(value: int) -> int:
        \\    if value > 0:
        \\        while value > 2:
        \\            return value
        \\    return 0
        \\
        \\func main() -> int:
        \\    const answer = helper(4)
        \\    return answer
    ;
    const mutations = [_]u8{ '\n', ')', ',', '+', ':' };
    for (mutations) |byte| for (input, 0..) |original, at| {
        if (original == ' ' or original == '\n') continue;
        var changed: [input.len]u8 = input.*;
        changed[at] = byte;
        var compilation = try language.Compilation.init(t.allocator, "bounded-recovery.selka", &changed);
        defer compilation.deinit();
        compilation.parse() catch |err| {
            try t.expectEqual(error.SourceError, err);
            try t.expect(compilation.syntax == null);
            try t.expect(compilation.diagnostics.items.len > 0);
            for (compilation.diagnostics.items) |diagnostic| {
                try t.expect(diagnostic.span.start <= diagnostic.span.end);
                try t.expect(diagnostic.span.end <= changed.len);
            }
            continue;
        };
        try t.expect(compilation.syntax != null);
        try t.expectEqualStrings(&changed, compilation.src.bytes);
    };
}

// spec-case: PARSE-RECOVERY-1
test "parser recovery bounded nested token mutations keep all diagnostic spans owned" {
    try boundedRecoveryMutations();
}

// spec-case: PARSE-RECOVERY-1
test "F4 parser recovery counts braces in a four-line dictionary literal" {
    const input = "func main() -> int:\n    const values = {\n        1: ,\n        2: 3,\n    }\n    return 0\n";
    var compilation = try language.Compilation.init(t.allocator, "braces.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expect(compilation.syntax == null);
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqual(@as(usize, 3), compilation.src.locate(compilation.diagnostics.items[0].span.start).line);
}

// spec-case: PARSE-RECOVERY-1
test "F6 parser recovery skips continuations after a malformed elif header" {
    const input = "func main() -> int:\n    const a = 1\n    if a == 1:\n        pass\n    elif a == = 2:\n        pass\n    else:\n        pass\n    return 0\n";
    var compilation = try language.Compilation.init(t.allocator, "continuations.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expect(compilation.syntax == null);
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqual(@as(usize, 5), compilation.src.locate(compilation.diagnostics.items[0].span.start).line);
}

// spec-case: PARSE-RECOVERY-1
test "F6 parser recovery skips compound continuations but retains later independent errors" {
    for ([_][]const u8{ "elif True", "else", "except Error", "finally", "case Choice.one" }) |header| {
        const input = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    if True == = False:\n        pass\n    {s}:\n        pass\n    const except = )\n    const finally = )\n    return 0\n", .{header});
        defer t.allocator.free(input);
        var compilation = try language.Compilation.init(t.allocator, "continuations.selka", input);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.parse());
        try t.expect(compilation.syntax == null);
        try t.expectEqual(@as(usize, 3), compilation.diagnostics.items.len);
        for (compilation.diagnostics.items, [_]usize{ 2, 6, 7 }) |item, line| {
            try t.expectEqual(line, compilation.src.locate(item.span.start).line);
        }
    }
}

// spec-case: PARSE-RECOVERY-1
test "F6 parser recovery preserves assignment statements named except and finally" {
    const input = "func main() -> int:\n    mut except = 0\n    mut finally = 0\n    const broken = )\n    except += )\n    finally += )\n    return 0\n";
    var compilation = try language.Compilation.init(t.allocator, "names.selka", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqual(@as(usize, 3), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items, [_]usize{ 4, 5, 6 }) |item, line| {
        try t.expectEqual(line, compilation.src.locate(item.span.start).line);
    }
}

test "F2 formatter treats spaced own calls and indexes as names and preserves subtraction" {
    // migrate-embedded: skip intentional F2 noncanonical contextual-name formatter input.
    const input =
        \\func draft():
        \\    const call=own (value)
        \\    const indexed=own [0]
        \\    const own=10
        \\    const difference=own - 1
        \\    return difference
    ;
    // migrate-embedded: skip intentional F2 exact canonical formatter golden.
    const expected =
        \\func draft():
        \\    const call = own(value)
        \\    const indexed = own[0]
        \\    const own = 10
        \\    const difference = own - 1
        \\    return difference
        \\
    ;
    const actual = try formatOnce(t.allocator, canonical_path, input);
    defer t.allocator.free(actual);
    try t.expectEqualStrings(expected, actual);
    const stable = try formatOnce(t.allocator, canonical_path, actual);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(expected, stable);
    var c = try language.Compilation.init(t.allocator, canonical_path, actual);
    defer c.deinit();
    try c.parse();
    const p = c.syntax.?;
    const body = p.statements.items[@backingInt(p.functions[0].body)].data.block;
    const call = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[0])].data.binding.value)];
    const indexed = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[1])].data.binding.value)];
    const subtraction = p.nodes.items[@backingInt(p.statements.items[@backingInt(body[3])].data.binding.value)];
    try t.expect(call.data == .call);
    try t.expectEqualStrings("own", c.src.text(call.data.call.name));
    try t.expect(indexed.data == .index);
    try t.expectEqualStrings("own", c.src.text(p.nodes.items[@backingInt(indexed.data.index.base)].data.name));
    try t.expect(subtraction.data == .binary);
    try t.expectEqual(language.ast.BinaryOp.sub, subtraction.data.binary.op);
    try t.expectEqualStrings("own", c.src.text(p.nodes.items[@backingInt(subtraction.data.binary.left)].data.name));
}

// F-S1a-10: a parenthesized expression that spans lines is not an item list. `(a and b,)` is a one-element tuple, which no
// longer parses, so the group goes on a line of its own with no trailing comma.
test "formatter lays a multi-line parenthesized expression on a line of its own without a trailing comma" {
    try expectCanonical(t.allocator,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a
        \\        and b
        \\    )
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\    return 0
        \\
    ,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a and b
        \\    )
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\    return 0
        \\
    );
}

test "formatter keeps a multi-line parenthesized expression comma-free after each operator, keyword and separator that precedes it" {
    try expectCanonical(t.allocator,
        \\func pick(a: bool, b: bool, c: bool) -> int:
        \\    const ok = (
        \\        a
        \\        and b
        \\    )
        \\    if (
        \\        ok
        \\        or c
        \\    ):
        \\        return 1
        \\    while (
        \\        not a
        \\        and b
        \\    ):
        \\        return 2
        \\    const wide = 1 + (
        \\        2
        \\        * 3
        \\    )
        \\    const flipped = not (
        \\        a
        \\        and b
        \\    )
        \\    return both(
        \\        (
        \\            a
        \\            and b
        \\        ),
        \\        (
        \\            c
        \\            or a
        \\        )
        \\    )
        \\
    ,
        \\func pick(a: bool, b: bool, c: bool) -> int:
        \\    const ok = (
        \\        a and b
        \\    )
        \\    if (
        \\        ok or c
        \\    ):
        \\        return 1
        \\    while (
        \\        not a and b
        \\    ):
        \\        return 2
        \\    const wide = 1 + (
        \\        2 * 3
        \\    )
        \\    const flipped = not (
        \\        a and b
        \\    )
        \\    return both(
        \\        (
        \\            a and b
        \\        ),
        \\        (
        \\            c or a
        \\        ),
        \\    )
        \\
    );
}

test "formatter keeps a multi-line parenthesized expression comma-free after assert, elif and try" {
    try expectCanonical(t.allocator,
        \\func run(a: bool, b: bool) -> int fails str:
        \\    assert (
        \\        a
        \\        or b
        \\    ), "needs one"
        \\    const v = try (
        \\        load(
        \\            1
        \\        )
        \\    )
        \\    if a:
        \\        return v
        \\    elif (
        \\        b
        \\        and a
        \\    ):
        \\        return 2
        \\    return v
        \\
    ,
        \\func run(a: bool, b: bool) -> int fails str:
        \\    assert (
        \\        a or b
        \\    ), "needs one"
        \\    const v = try (
        \\        load(1)
        \\    )
        \\    if a:
        \\        return v
        \\    elif (
        \\        b and a
        \\    ):
        \\        return 2
        \\    return v
        \\
    );
}

test "formatter keeps the trailing comma of a multi-line tuple, call and constructor" {
    try expectCanonical(t.allocator,
        \\func main() -> int:
        \\    const pair = (
        \\        1,
        \\        2
        \\    )
        \\    const point = Point(
        \\        x=1,
        \\        y=pair[0]
        \\    )
        \\    return point.x
        \\
    ,
        \\func main() -> int:
        \\    const pair = (
        \\        1,
        \\        2,
        \\    )
        \\    const point = Point(
        \\        x=1,
        \\        y=pair[0],
        \\    )
        \\    return point.x
        \\
    );
}

test "formatter keeps a trailing comment on the line of a parenthesized expression's last token" {
    try expectCanonical(t.allocator,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a # the left
        \\        and b # the right
        \\    )
        \\
    ,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a # the left
        \\        and b # the right
        \\    )
        \\
    );
}

// F-S1a-10: an attribute's arguments, a pattern that ends with the rest marker, a comprehension and the type arguments of a
// keyword intrinsic are not item lists either: a comma after their last item does not parse.
test "formatter ends a multi-line attribute's arguments without a trailing comma" {
    try expectCanonical(t.allocator,
        \\@ensures(
        \\result >= 0
        \\)
        \\@requires(
        \\x > 0,
        \\"x is positive"
        \\)
        \\func f(x: int) -> int:
        \\    return x
        \\
    ,
        \\@ensures(
        \\    result >= 0
        \\)
        \\@requires(
        \\    x > 0,
        \\    "x is positive"
        \\)
        \\func f(x: int) -> int:
        \\    return x
        \\
    );
}

test "formatter ends a multi-line pattern at its rest marker without a trailing comma" {
    try expectCanonical(t.allocator,
        \\enum Token:
        \\    atom(text: str, line: int)
        \\    other
        \\
        \\
        \\func f(t: Token) -> int:
        \\    match t:
        \\        case atom(
        \\            text,
        \\            ..
        \\        ):
        \\            return 1
        \\        case other:
        \\            return 0
        \\
    ,
        \\enum Token:
        \\    atom(text: str, line: int)
        \\    other
        \\
        \\
        \\func f(t: Token) -> int:
        \\    match t:
        \\        case atom(
        \\            text,
        \\            ..
        \\        ):
        \\            return 1
        \\        case other:
        \\            return 0
        \\
    );
}

test "formatter keeps a multi-line comprehension on one line inside its delimiters without a trailing comma" {
    try expectCanonical(t.allocator,
        \\func f(xs: int[]) -> int:
        \\    const total = sum(
        \\        x * x
        \\        for x in xs
        \\    )
        \\    const table = {
        \\        k: v
        \\        for k, v in zip(xs, xs)
        \\    }
        \\    return total
        \\
    ,
        \\func f(xs: int[]) -> int:
        \\    const total = sum(
        \\        x * x for x in xs
        \\    )
        \\    const table = {
        \\        k: v for k, v in zip(xs, xs)
        \\    }
        \\    return total
        \\
    );
}

test "formatter collapses the type arguments of a keyword intrinsic like any other type argument list" {
    try expectCanonical(t.allocator,
        \\import network
        \\
        \\func serve(mut listener: network.Listener) -> int:
        \\    match accept_resource[
        \\        network.Accepted
        \\    ](listener):
        \\        case Ok(connection):
        \\            return 0
        \\        case Err(error):
        \\            return 1
        \\
    ,
        \\import network
        \\
        \\func serve(mut listener: network.Listener) -> int:
        \\    match accept_resource[network.Accepted](listener):
        \\        case Ok(connection):
        \\            return 0
        \\        case Err(error):
        \\            return 1
        \\
    );
}

test "formatter specials mark the parenthesized expressions, the bare lists and nothing else" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sink: diagnostics.Sink = .{ .allocator = arena };
    const text = "func f(a: bool, b: bool) -> bool:\n    const pair = (a, b)\n    const g = (a and b)\n    return g and (a or b) and f(a, b)\n";
    const tokens = try lexer.lex(arena, text, &sink);
    const specials = try formatter.delimiterSpecials(arena, text, tokens);
    var groups: usize = 0;
    var bare: usize = 0;
    for (specials) |special| {
        groups += @intFromBool(special == .group);
        bare += @intFromBool(special == .bare);
    }
    try t.expectEqual(tokens.len, specials.len);
    try t.expectEqual(@as(usize, 2), groups);
    try t.expectEqual(@as(usize, 0), bare);
}

test "formatter keeps the space before not in after every operand end" {
    try expectCanonical(t.allocator,
        \\func check(xs: str[], d: Dict[str, int], i: int) -> bool:
        \\    const a = xs[i]not in d
        \\    const b = xs[i]in d
        \\    const c = xs[0:2]not in d
        \\    const e = [1, 2]not in d
        \\    const f = d.size not  in d
        \\    const g = len(xs) not in d
        \\    const h = "k" not in d
        \\    const j = xs[i] is None
        \\    const k = not xs[i]
        \\    return a
        \\
    ,
        \\func check(xs: str[], d: Dict[str, int], i: int) -> bool:
        \\    const a = xs[i] not in d
        \\    const b = xs[i] in d
        \\    const c = xs[0:2] not in d
        \\    const e = [1, 2] not in d
        \\    const f = d.size not in d
        \\    const g = len(xs) not in d
        \\    const h = "k" not in d
        \\    const j = xs[i] is None
        \\    const k = not xs[i]
        \\    return a
        \\
    );
}

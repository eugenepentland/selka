//! Canonical formatter regressions: noncanonical input becomes fixed canonical
//! bytes, a second format is byte-stable, comments and literal text survive, and
//! formatted programs still run. The formatter never type-checks, so these tests
//! keep the parse-only drafts and unresolved modules that `fmt` must still accept.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const canonical_path = "canonical.my";

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

// spec: FMT-CLAUSE-SPACE-1
test "formatter keeps the space between a bracketed return type and its effect clause" {
    try expectCanonicalModule(t.allocator,
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
    // The standard library's own signatures are already canonical.
    const sort_source = @embedFile("stdlib/sort.my");
    const formatted = try formatModuleOnce(t.allocator, "sort.my", sort_source);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "]effects(") == null);
    try t.expect(std.mem.indexOf(u8, formatted, "-> int? effects():") != null);
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
        \\    return value + len(raw) + len(data) + len(label)
    ,
        \\# heading
        \\func main() -> i64: # suite note
        \\    # leading note
        \\    mut raw = "a  b # not a comment"
        \\    mut data = b"raw bytes"
        \\    mut label = f"v={ 1+2 }"
        \\    mut value = 40 + 2 # trailing
        \\    return value + len(raw) + len(data) + len(label)
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
    try expectCanonical(t.allocator,
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
test "empty, whitespace-only and comment-only inputs have explicit fixtures" {
    try expectCanonical(t.allocator, "", "");
    try expectCanonical(t.allocator, "  \n\t\n", "");
    try expectCanonical(t.allocator, " # one\n\n# two", "# one\n# two\n");
}

// spec-case: TOOL-5
test "module formatter canonicalizes headers, directives and unresolved drafts" {
    try expectCanonicalModule(t.allocator,
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
        \\import contracts.missing as c
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\func total[P: c.Prices](policy: P, subtotal: int) -> int effects():
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
    var before = try language.Compilation.init(t.allocator, "before.my", input);
    defer before.deinit();
    const before_run = try native.run(&before);
    try t.expect(!before_run.failed);
    try t.expectEqual(@as(i64, 24), before_run.value);

    const formatted = try before.format(t.allocator);
    defer t.allocator.free(formatted);

    var after = try language.Compilation.init(t.allocator, "after.my", formatted);
    defer after.deinit();
    const after_run = try native.run(&after);
    try t.expect(!after_run.failed);
    try t.expectEqual(before_run.value, after_run.value);
}

fn failureScenario(allocator: std.mem.Allocator) !void {
    const input =
        \\# draft
        \\func unfinished(x: Unknown) -> FixedArray[Unknown, 2]: # keep
        \\    mut value=  40+2
        \\    # note
        \\    return missing(x)+value
    ;
    const formatted = try formatOnce(allocator, "failure.my", input);
    defer allocator.free(formatted);
    const twice = try formatOnce(allocator, "failure.my", formatted);
    defer allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec-case: TOOL-5
test "formatter allocation failures release collectComments and collectTopStarts storage" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), failureScenario, .{});
}

// spec: FMT-MODULE-DETECT-1
test "fmt accepts headerless imported modules and standalone declarations" {
    const module_text = "\n\nfunc twice(x: int) -> int:\n    return x*2\n";
    const formatted = try formatOnce(t.allocator, "calc.my", module_text);
    defer t.allocator.free(formatted);
    const expected = try formatModuleOnce(t.allocator, "calc.my", module_text);
    defer t.allocator.free(expected);
    try t.expectEqualStrings(expected, formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "x * 2") != null);
    const script = "# a script\nimport math\n\n\nfunc main() -> int:\n    return int(math.floor(2.5))\n";
    const imported = try formatOnce(t.allocator, "script.my", script);
    defer t.allocator.free(imported);
    const imported_module = try formatModuleOnce(t.allocator, "script.my", script);
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
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", invalid);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.format(t.allocator));
}

// spec: MUT-PARAM-6
test "formatter keeps the mut parameter and the mut argument marker canonical" {
    const expected =
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
    try expectCanonical(t.allocator, unformatted, expected);
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
    var compilation = try language.Compilation.init(t.allocator, "recovery.my", input);
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
    var compilation = try language.Compilation.init(t.allocator, "headers.my", input);
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
    var compilation = try language.Compilation.init(t.allocator, "migration.my", input);
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
    var compilation = try language.Compilation.init(t.allocator, "missing.my", input);
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
        var compilation = try language.Compilation.init(t.allocator, "bounded-recovery.my", &changed);
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
    var compilation = try language.Compilation.init(t.allocator, "braces.my", input);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    try t.expect(compilation.syntax == null);
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqual(@as(usize, 3), compilation.src.locate(compilation.diagnostics.items[0].span.start).line);
}

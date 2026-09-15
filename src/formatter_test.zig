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

// spec: TOOL-5
test "formatter canonicalizes operator and assignment spacing" {
    try expectCanonical(t.allocator,
        \\def main() -> int:
        \\    value=  40+2
        \\    return value*3-1
    ,
        \\def main() -> int:
        \\    value = 40 + 2
        \\    return value * 3 - 1
        \\
    );
}

// spec-case: TOOL-5
test "formatter preserves comments, literal values and precedence" {
    try expectCanonical(t.allocator,
        \\# heading
        \\def main() -> i64: # suite note
        \\    # leading note
        \\    raw = "a  b # not a comment"
        \\    data = b"raw bytes"
        \\    label = f"v={ 1+2 }"
        \\    value=  40+2 # trailing
        \\    return value + len(raw) + len(data) + len(label)
    ,
        \\# heading
        \\def main() -> i64: # suite note
        \\    # leading note
        \\    raw = "a  b # not a comment"
        \\    data = b"raw bytes"
        \\    label = f"v={ 1+2 }"
        \\    value = 40 + 2 # trailing
        \\    return value + len(raw) + len(data) + len(label)
        \\
    );
}

// spec-case: TOOL-5
test "formatter normalizes unary operators and nested blocks" {
    try expectCanonical(t.allocator,
        \\def main() -> int:
        \\    x=-1+2*3
        \\    y=not x==0
        \\    if x>0:
        \\        while x>1:
        \\            x-=1
        \\            if x==2:
        \\                x=x+1
        \\            else:
        \\                break
        \\    return x
    ,
        \\def main() -> int:
        \\    x = -1 + 2 * 3
        \\    y = not x == 0
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
        \\def sum[T: integer](value: T) -> T:
        \\    return value+value
        \\
        \\def score[T: copy+op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\
        \\constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\def first(xs: list[int]) -> int:
        \\    return xs[ 1 : 2 ][0]
    ,
        \\def sum[T: integer](value: T) -> T:
        \\    return value + value
        \\
        \\
        \\def score[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\
        \\
        \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\def first(xs: list[int]) -> int:
        \\    return xs[1:2][0]
        \\
    );
}

// spec-case: TOOL-5
test "top-level declarations get two blank lines and the header group one" {
    try expectCanonical(t.allocator,
        \\def a() -> int:
        \\    return 1
        \\def b() -> int:
        \\    return 2
        \\def c() -> int:
        \\    return 3
    ,
        \\def a() -> int:
        \\    return 1
        \\
        \\
        \\def b() -> int:
        \\    return 2
        \\
        \\
        \\def c() -> int:
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
        \\module app.main
        \\import contracts.missing as c
        \\export Prices
        \\
        \\
        \\
        \\constraint Prices[P] = copy+op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\
        \\def total[P: c.Prices](policy: P, subtotal: int) -> int effects():
        \\    return policy.price(policy=policy, subtotal=subtotal)
    ,
        \\module app.main
        \\import contracts.missing as c
        \\export Prices
        \\
        \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\def total[P: c.Prices](policy: P, subtotal: int) -> int effects():
        \\    return policy.price(policy=policy, subtotal=subtotal)
        \\
    );
}

// spec-case: TOOL-5
test "formatting a program preserves its native execution result" {
    const input =
        \\def total(values: list[int]) -> int:
        \\    sum=0
        \\    for value in values:
        \\        sum+=value
        \\    return sum
        \\
        \\def main() -> i64:
        \\    values=[1,2,3,4]
        \\    doubled=total(values)*2
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
        \\def unfinished(x: Unknown) -> [2]Unknown: # keep
        \\    value=  40+2
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

test "formatter still rejects invalid syntax and reports its source diagnostic" {
    const invalid =
        \\def main() -> i64:
        \\    return +
    ;
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", invalid);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.format(t.allocator));
}

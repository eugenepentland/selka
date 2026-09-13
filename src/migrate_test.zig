//! Legacy-to-Python migration keeps meaning, comments, and reports every gap.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const migrate = @import("migrate.zig");
const diagnostic = @import("diagnostic.zig");
const path = "input.my";

/// Allocate the migrated spelling of one source, discarding collected diagnostics.
fn convert(allocator: std.mem.Allocator, text: []const u8, options: migrate.Options) ![]u8 {
    var compilation = try language.Compilation.init(allocator, path, text);
    defer compilation.deinit();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator(), .items = compilation.diagnostics };
    defer compilation.diagnostics = sink.items;
    return migrate.render(allocator, compilation.src, options, &sink);
}

/// Migration must produce the expected spelling and reproduce it when re-run.
fn expectMigration(text: []const u8, expected: []const u8) !void {
    const output = try convert(t.allocator, text, .{});
    defer t.allocator.free(output);
    try t.expectEqualStrings(expected, output);
    const again = try convert(t.allocator, output, .{});
    defer t.allocator.free(again);
    try t.expectEqualStrings(expected, again);
}

/// Rejected migrations report one located diagnostic naming the construct.
fn expectRejection(text: []const u8, message: []const u8, spelling: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, path, text);
    defer compilation.deinit();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator(), .items = compilation.diagnostics };
    defer compilation.diagnostics = sink.items;
    try t.expectError(error.SourceError, migrate.render(t.allocator, compilation.src, .{}, &sink));
    try t.expectEqual(@as(usize, 1), sink.items.items.len);
    try t.expectEqualStrings(migrate.unsupported_code, sink.items.items[0].code);
    try t.expectEqualStrings(message, sink.items.items[0].message);
    try t.expectEqualStrings(spelling, compilation.src.text(sink.items.items[0].span));
}

// spec: MIGRATE-1
test "legacy functions bindings and control flow become Python suites" {
    try expectMigration(
        \\fn main() -> i64 {
        \\    let mut total = 0;
        \\    let limit: i64 = 3;
        \\    while total < limit {
        \\        total += 1;
        \\        if total == 2 { continue; } else if total == 5 { break; }
        \\    }
        \\    for i in 0..limit {
        \\        total = total - 1;
        \\    }
        \\    return total;
        \\}
    ,
        \\def main() -> i64:
        \\    total = 0
        \\    limit: i64 = 3
        \\    while total < limit:
        \\        total += 1
        \\        if total == 2:
        \\            continue
        \\        elif total == 5:
        \\            break
        \\    for i in range(0, limit):
        \\        total = total - 1
        \\    return total
        \\
    );
}

// spec: MIGRATE-2
test "records variants aliases and constants keep their declaration order" {
    try expectMigration(
        \\struct Point { x: i64, y: i64 }
        \\enum Color { red, green }
        \\type Count = i64;
        \\const LIMIT: i64 = 7;
        \\fn main() -> i64 {
        \\    let p = new Point { x: LIMIT, y: 2 };
        \\    let c = new Color.red;
        \\    let d = Point { x: 1, y: 1 };
        \\    if c == Color.green { return 0; }
        \\    return p.x + p.y + d.x;
        \\}
    ,
        \\class Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\enum Color:
        \\    red,
        \\    green
        \\
        \\
        \\type Count = i64
        \\
        \\
        \\const LIMIT: i64 = 7
        \\
        \\
        \\def main() -> i64:
        \\    p = Point(x=LIMIT, y=2)
        \\    c = Color.red
        \\    d = Point(x=1, y=1)
        \\    if c == Color.green:
        \\        return 0
        \\    return p.x + p.y + d.x
        \\
    );
}

// spec-case: MIGRATE-3
test "inverted comparison keeps its legacy precedence under Python not" {
    try expectMigration(
        \\fn main() -> i64 {
        \\    let ready = !(1 == 2);
        \\    if !ready == false { return 1; }
        \\    return 0;
        \\}
    ,
        \\def main() -> i64:
        \\    ready = not (1 == 2)
        \\    if (not ready) == False:
        \\        return 1
        \\    return 0
        \\
    );
}

// spec-case: MIGRATE-3
test "unannotated result bindings gain the annotation contextual Ok requires" {
    try expectMigration(
        \\result Answer { ok: i64, err: i64 }
        \\fn main() -> i64 {
        \\    let value = new Answer.ok(42);
        \\    match value {
        \\        Answer.ok(v) => { return v; },
        \\        Answer.err(e) => { return e; }
        \\    }
        \\}
    ,
        \\result Answer:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def main() -> i64:
        \\    value: Answer = Ok(42)
        \\    match value:
        \\        case Answer.ok(v):
        \\            return v
        \\        case Answer.err(e):
        \\            return e
        \\
    );
}

// spec: MIGRATE-4
test "module directives qualification and comments survive migration" {
    try expectMigration(
        \\// Leading module note.
        \\module demo;
        \\import other as o;
        \\export main;
        \\
        \\// Doubled note.
        \\fn main() -> i64 {
        \\    // Inner note.
        \\    let value = o::make();
        \\
        \\    // Trailing note.
        \\    return value;
        \\}
    ,
        \\# Leading module note.
        \\module demo
        \\import other as o
        \\export main
        \\
        \\
        \\# Doubled note.
        \\def main() -> i64:
        \\    # Inner note.
        \\    value = o.make()
        \\
        \\    # Trailing note.
        \\    return value
        \\
    );
}

// spec: MIGRATE-6
test "partial migration marks every gap and keeps the surrounding suite" {
    const output = try convert(t.allocator,
        \\fn main() -> i64 {
        \\    let first = match 1 { };
        \\    let second = match 2 { };
        \\    return first + second;
        \\}
    , .{ .allow_partial = true });
    defer t.allocator.free(output);
    try t.expectEqualStrings(
        \\def main() -> i64:
        \\    first = todo<i64>()  # MIGRATE: unsupported a match expression
        \\    second = todo<i64>()  # MIGRATE: unsupported a match expression
        \\    return first + second
        \\
    , output);
}

// spec-case: MIGRATE-6
test "partial migration records one warning for every reported gap" {
    var compilation = try language.Compilation.init(t.allocator, path,
        \\fn main() -> i64 {
        \\    return match 1 { } + match 2 { };
        \\}
    );
    defer compilation.deinit();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator(), .items = compilation.diagnostics };
    defer compilation.diagnostics = sink.items;
    const output = try migrate.render(t.allocator, compilation.src, .{ .allow_partial = true }, &sink);
    defer t.allocator.free(output);
    try t.expectEqual(@as(usize, 2), sink.items.items.len);
    for (sink.items.items) |item| {
        try t.expectEqual(diagnostic.Severity.warning, item.severity);
        try t.expectEqualStrings(migrate.unsupported_code, item.code);
    }
}

// spec: MIGRATE-7
test "already Python source migrates to itself byte for byte" {
    const text =
        \\class Point:
        \\    x: int
        \\
        \\
        \\def main() -> int:
        \\    # keep this comment exactly here
        \\    p = Point(x=42)
        \\    return p.x
        \\
    ;
    try expectMigration(text, text);
}

/// Migrated source must check and return what the legacy program returned.
fn parityScenario(allocator: std.mem.Allocator) !void {
    const legacy =
        \\struct Counter { value: i64 }
        \\fn step(c: Counter) -> Counter {
        \\    return new Counter { value: c.value + 1 };
        \\}
        \\fn main() -> i64 {
        \\    let mut c = new Counter { value: 0 };
        \\    let mut i = 0;
        \\    while i < 42 {
        \\        c = step(c);
        \\        i += 1;
        \\    }
        \\    return c.value;
        \\}
    ;
    const output = try convert(allocator, legacy, .{});
    defer allocator.free(output);
    var before = try language.Compilation.init(allocator, path, legacy);
    defer before.deinit();
    var after = try language.Compilation.init(allocator, path, output);
    defer after.deinit();
    try t.expectEqual(@as(i64, 42), (try before.execute(allocator)).value);
    try t.expectEqual(@as(i64, 42), (try after.execute(allocator)).value);
}

// spec-case: MIGRATE-6
test "migrated programs reproduce the original result on the VM" {
    try parityScenario(t.allocator);
}

// spec: MIGRATE-8
test "python-only arena scopes and escapes reprint in their canonical spelling" {
    const text =
        \\def collect(count: int) -> list[int]:
        \\    values: list[int] = []
        \\    for index in range(count):
        \\        values.append(index)
        \\    return values
        \\
        \\def main() -> int:
        \\    kept: list[int] = []
        \\    with arena() as scratch:
        \\        kept = scratch.escape(collect(3))
        \\    with arena():
        \\        _ = collect(2)
        \\    return len(kept)
        \\
    ;
    const passthrough = try convert(t.allocator, text, .{});
    defer t.allocator.free(passthrough);
    try t.expectEqualStrings(text, passthrough);
    const reprinted = try convert(t.allocator, text, .{ .reprint = true });
    defer t.allocator.free(reprinted);
    try t.expectEqualStrings(
        \\def collect(count: int) -> list[int]:
        \\    values: list[int] = []
        \\    for index in range(count):
        \\        values.append(index)
        \\    return values
        \\
        \\
        \\def main() -> int:
        \\    kept: list[int] = []
        \\    with arena() as scratch:
        \\        kept = scratch.escape(collect(3))
        \\    with arena():
        \\        _ = collect(2)
        \\    return len(kept)
        \\
    , reprinted);
}

// spec-case: MIGRATE-1
test "unit results discard statements and bare returns adopt Python spellings" {
    try expectMigration(
        \\fn noop() -> unit {
        \\    return;
        \\}
        \\fn main() -> i64 {
        \\    noop();
        \\    _ = noop();
        \\    return 0;
        \\}
    ,
        \\def noop():
        \\    return
        \\
        \\
        \\def main() -> i64:
        \\    noop()
        \\    _ = noop()
        \\    return 0
        \\
    );
}

// spec: MIGRATE-3
test "operators propagation matching and generics adopt Python spellings" {
    try expectMigration(
        \\result Answer { ok: i64, err: i64 }
        \\fn checked(value: i64) -> Answer {
        \\    if !(value < 0) && true || false { return new Answer.ok(value); }
        \\    return new Answer.err(1);
        \\}
        \\fn identity<T: copy>(value: T) -> T { return value; }
        \\fn twice(step: fn(i64) -> unit effects(), value: i64) -> unit { step(value); step(value); }
        \\fn main() -> i64 {
        \\    let answer = checked(40)?;
        \\    match checked(answer) {
        \\        Answer.ok(v) => { return identity::<i64>(v) + 2; },
        \\        Answer.err(e) => { return e; }
        \\    }
        \\}
    ,
        \\result Answer:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def checked(value: i64) -> Answer:
        \\    if not (value < 0) and True or False:
        \\        return Ok(value)
        \\    return Err(1)
        \\
        \\
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def twice(step: fn(i64) -> None effects(), value: i64):
        \\    step(value)
        \\    step(value)
        \\
        \\
        \\def main() -> i64:
        \\    answer = checked(40)?
        \\    match checked(answer):
        \\        case Answer.ok(v):
        \\            return identity[i64](v) + 2
        \\        case Answer.err(e):
        \\            return e
        \\
    );
}

// spec-case: MIGRATE-6
test "migration releases every allocation when the allocator fails" {
    try t.checkAllAllocationFailures(t.allocator, parityScenario, .{});
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), parityScenario, .{});
}

// spec: MIGRATE-5
test "constructs without a Python spelling are rejected with their source spans" {
    try expectRejection(
        \\fn main() -> i64 {
        \\    let a = 7;
        \\    { let a = 1; return a; }
        \\    return a;
        \\}
    , "no Python spelling for a bare nested scope block", "{ let a = 1; return a; }");
    try expectRejection(
        \\fn main() -> i64 {
        \\    return match 1 { };
        \\}
    , "no Python spelling for a match expression", "match 1 { }");
    try expectRejection(
        \\fn delegate(fs: filesystem_cap) -> filesystem_cap effects() {
        \\    return restrict_resource<read>(fs);
        \\}
        \\fn main() -> i64 { return 0; }
    , "no Python spelling for restrict_resource", "restrict_resource<read>(fs)");
}

// spec: MIGRATE-9
test "contextual literals print with the annotation that supplies their type" {
    try expectMigration(
        \\enum Kind { first, second }
        \\union Link { none, some: i64 }
        \\fn pick<T: copy>(value: T) -> T { return value; }
        \\fn main() -> i64 {
        \\    let held = new Link.some(2);
        \\    let fixed = new [2]i64 [1, 2];
        \\    let codes = new [Kind]i64 { first: 3, second: 4 };
        \\    let chosen = pick::<i64>(5);
        \\    match held {
        \\        Link.none => { return 0; },
        \\        Link.some(value) => { return value + fixed[0] + codes[new Kind.first] + chosen; }
        \\    }
        \\}
        \\
    ,
        \\enum Kind:
        \\    first,
        \\    second
        \\
        \\
        \\union Link:
        \\    none,
        \\    some: i64
        \\
        \\
        \\def pick[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def main() -> i64:
        \\    held = Link.some(2)
        \\    fixed: [2]i64 = [1, 2]
        \\    codes: [Kind]i64 = {Kind.first: 3, Kind.second: 4}
        \\    chosen = pick[i64](5)
        \\    match held:
        \\        case Link.none:
        \\            return 0
        \\        case Link.some(value):
        \\            return value + fixed[0] + codes[Kind.first] + chosen
        \\
    );
}

// spec: MIGRATE-10
test "truncating division keeps its rounding unless an operand is certainly unsigned" {
    try expectMigration(
        \\fn split(signed: i64, wide: u64) -> i64 {
        \\    let quotient = signed / 2;
        \\    let counted = wide % 3u64;
        \\    let sized = len(new [4]i64 [0, 0, 0, 0]) / 2;
        \\    return quotient + cast<i64>(counted) + cast<i64>(sized) + signed % 3;
        \\}
        \\fn main() -> i64 { return split(7, 9u64); }
        \\
    ,
        \\def split(signed: i64, wide: u64) -> i64:
        \\    quotient = divtrunc(signed, 2)
        \\    counted = wide % 3u64
        \\    sized = len([0, 0, 0, 0]) // 2
        \\    return quotient + cast<i64>(counted) + cast<i64>(sized) + remtrunc(signed, 3)
        \\
        \\
        \\def main() -> i64:
        \\    return split(7, 9u64)
        \\
    );
}

// spec-case: MIGRATE-5
test "a bare scope block inlines when its bindings are unique and reports otherwise" {
    try expectMigration(
        \\fn main() -> i64 {
        \\    let factor = 7;
        \\    let mut total = 0;
        \\    {
        \\        let amount = 3;
        \\        total = factor * amount;
        \\    }
        \\    return total;
        \\}
        \\
    ,
        \\def main() -> i64:
        \\    factor = 7
        \\    total = 0
        \\    amount = 3
        \\    total = factor * amount
        \\    return total
        \\
    );
    try expectRejection(
        \\fn main() -> i64 {
        \\    let mut total = 0;
        \\    { let amount = 1; total += amount; }
        \\    { let amount = 2; total += amount; }
        \\    return total;
        \\}
        \\
    , "no Python spelling for a bare nested scope block", "{ let amount = 1; total += amount; }");
}

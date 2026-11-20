//! Ownership migration exercises the exact diagnostic edits through the public CLI.
const std = @import("std");
const testing = std.testing;

/// Skips the calling test while release builds are off (`-Dtest-release=true` runs them).
fn requireRelease() error{SkipZigTest}!void {
    if (!@import("test_release_options").enabled) return error.SkipZigTest;
}

/// Skips the calling test while release builds are off, when the compiler flags ask for `--release`.
fn requireReleaseArgs(argv: []const []const u8) error{SkipZigTest}!void {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--release")) return requireRelease();
    }
}

const Project = struct {
    temp: testing.TmpDir,
    compiler: [:0]const u8,

    fn init(source: []const u8) !Project {
        var temp = testing.tmpDir(.{});
        errdefer temp.cleanup();
        try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
        return .{ .temp = temp, .compiler = compiler };
    }

    fn deinit(self: *Project) void {
        testing.allocator.free(self.compiler);
        self.temp.cleanup();
    }

    fn run(self: *const Project, command: []const u8, flags: []const []const u8) !Outcome {
        try requireReleaseArgs(flags);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ self.compiler, command, "main.selka", "--no-cache" });
        try argv.appendSlice(testing.allocator, flags);
        var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
        defer environment.deinit();
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir }, .environ_map = &environment });
        return .{ .status = switch (result.term) {
            .exited => |status| status,
            else => 255,
        }, .stdout = result.stdout, .stderr = result.stderr };
    }

    fn read(self: *const Project) ![]const u8 {
        return self.temp.dir.readFileAlloc(testing.io, "main.selka", testing.allocator, .limited(1 << 20));
    }
};

const Outcome = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// Whether `stderr` of `fix` holds nothing but `W_COPY_MOVE` hints: advice that never fails a build, and that a migrated program may
/// still draw where the rewrite is more than a fix can make (`build`, `run` and `test` leave the hints out). Each hint is a header line, its source line and a caret line.
fn onlyHints(stderr: []const u8) bool {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (!contains(line, "warning[W_COPY_MOVE]")) return false;
        _ = lines.next();
        _ = lines.next();
    }
    return true;
}

fn migrate(original: []const u8, expected: []const u8, code: []const u8) !bool {
    return migrateWith(original, expected, code, false);
}

/// `migrate` for a source whose repairs include a warning's, which a file run applies only with `--warnings`.
fn migrateWarnings(original: []const u8, expected: []const u8, code: []const u8) !bool {
    return migrateWith(original, expected, code, true);
}

fn migrateWith(original: []const u8, expected: []const u8, code: []const u8, warnings: bool) !bool {
    var project = try Project.init(original);
    defer project.deinit();
    const apply: []const []const u8 = if (warnings) &.{"--warnings"} else &.{};
    const list: []const []const u8 = if (warnings) &.{ "--check", "--warnings" } else &.{"--check"};
    const diagnostic = try project.run("check", &.{"--diagnostics=json"});
    defer diagnostic.deinit();
    try testing.expectEqual(@as(u8, 1), diagnostic.status);
    try testing.expect(contains(diagnostic.stderr, code));
    try testing.expect(contains(diagnostic.stderr, "\"fix\":{\"edits\":"));
    const preview = try project.run("fix", list);
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix main.selka:"));
    const before = try project.read();
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", apply);
    defer fixed.deinit();
    try testing.expect(onlyHints(fixed.stderr));
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read();
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(expected, after);
    const checked = try project.run("check", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", list);
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    return true;
}

fn unfixable(original: []const u8, code: []const u8) !bool {
    var project = try Project.init(original);
    defer project.deinit();
    const diagnostic = try project.run("check", &.{"--diagnostics=json"});
    defer diagnostic.deinit();
    try testing.expectEqual(@as(u8, 1), diagnostic.status);
    try testing.expect(contains(diagnostic.stderr, code));
    try testing.expect(!contains(diagnostic.stderr, "\"fix\":"));
    const fixed = try project.run("fix", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const after = try project.read();
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
    return true;
}

test "ownership fix copies owned variant payload slices and reaches a fixed point" {
    const original =
        // migrate-embedded: skip intentional V2 owned variant payload missing-copy diagnostic
        \\record Kept:
        \\    data: bytes? = None
        \\func main() -> int:
        \\    const data = b"abcd"
        \\    mut kept = Kept()
        \\    kept.data = Some(data[1:3])
        \\    return 0
    ;
    const expected =
        \\record Kept:
        \\    data: bytes? = None
        \\func main() -> int:
        \\    const data = b"abcd"
        \\    mut kept = Kept()
        \\    kept.data = Some(copy(data[1:3]))
        \\    return 0
    ;
    try testing.expect(try migrate(original, expected, "E_SLICE_ESCAPES"));
    const marked = try std.mem.replaceOwned(u8, testing.allocator, original, "Some(data[", "Some(own data[");
    defer testing.allocator.free(marked);
    try testing.expect(try migrate(marked, expected, "E_OWN_MARKER"));
}

// spec: OWNERSHIP-COPY-FIX-1
test "ownership fix declares a borrowed return exactly and reaches a fixed point" {
    try testing.expect(try migrate(@embedFile("fixtures/fix-migration/ownership-default-borrow.selka"),
        \\func keep(values: int[]) -> int[] from values:
        \\    return values
        \\
        \\func main() -> int:
        \\    return len(keep([1, 2]))
        \\
    , "E_BORROW_UNDECLARED"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix copies a borrowed field without repeating its receiver" {
    try testing.expect(try migrate(
        // migrate-embedded: skip intentional OWNERSHIP-COPY-FIX-1 missing-copy diagnostic input
        \\record Batch:
        \\    items: int[]
        \\func keep(batch: Batch) -> int[]:
        \\    mut kept = batch.items
        \\    append(mut kept, 1)
        \\    return kept
    ,
        \\record Batch:
        \\    items: int[]
        \\func keep(batch: Batch) -> int[]:
        \\    mut kept = copy(batch.items)
        \\    append(mut kept, 1)
        \\    return kept
    , "E_SINGLE_OWNER_BORROW"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix copies a borrowed index without repeating its index" {
    try testing.expect(try migrate(
        // migrate-embedded: skip intentional OWNERSHIP-COPY-FIX-1 missing-copy diagnostic input
        \\func keep(rows: int[][], index: int) -> int[]:
        \\    mut kept = rows[index]
        \\    append(mut kept, 1)
        \\    return kept
    ,
        \\func keep(rows: int[][], index: int) -> int[]:
        \\    mut kept = copy(rows[index])
        \\    append(mut kept, 1)
        \\    return kept
    , "E_SINGLE_OWNER_BORROW"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix detaches an iteration value before storing it" {
    try testing.expect(try migrate(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const rows = [[1]]
        \\    mut result: int[][] = []
        \\    for row in rows:
        \\        append(mut result, row)
        \\    append(mut result, [2])
        \\    return len(result) + len(rows)
    ,
        \\func main() -> int:
        \\    const rows = [[1]]
        \\    mut result: int[][] = []
        \\    for row in rows:
        \\        append(mut result, copy(row))
        \\    append(mut result, [2])
        \\    return len(result) + len(rows)
    , "E_SINGLE_OWNER_OVERLAP"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix never proposes copying an already moved value" {
    try testing.expect(try unfixable(
        \\func main() -> int:
        \\    const first = [1]
        \\    const second = own first
        \\    return len(first) + len(second)
    , "E_SINGLE_OWNER_MOVED"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix never redirects a mutation to a throwaway copy" {
    try testing.expect(try unfixable(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut values = [1]
        \\    for value in values:
        \\        append(mut values, value)
        \\    return len(values)
    , "E_SINGLE_OWNER_OVERLAP"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix copies a dictionary selection after its operands run once" {
    try testing.expect(try migrate(
        // migrate-embedded: skip intentional OWNERSHIP-COPY-FIX-1 missing-copy diagnostic input
        \\import dicts
        \\
        \\func keep(values: dict[str, int[]]) -> int[]:
        \\    mut kept = dicts.get(values, "x", [1])
        \\    append(mut kept, 2)
        \\    return kept
    ,
        \\import dicts
        \\
        \\func keep(values: dict[str, int[]]) -> int[]:
        \\    mut kept = copy(dicts.get(values, "x", [1]))
        \\    append(mut kept, 2)
        \\    return kept
    , "E_SINGLE_OWNER_BORROW"));
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix leaves a returned capability alone: a capability is a handle (5C)" {
    var project = try Project.init(
        \\func keep(fs: Filesystem) -> Filesystem:
        \\    return fs
    );
    defer project.deinit();
    const checked = try project.run("check", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
}

// spec-case: OWNERSHIP-COPY-FIX-1
test "ownership fix copies an assignment operand without wrapping its synthetic assignment" {
    try testing.expect(try migrate(
        // migrate-embedded: skip intentional OWNERSHIP-COPY-FIX-1 missing-copy diagnostic input
        \\func main() -> int:
        \\    mut values = [[7], [11]]
        \\    values[0] = values[0]
        \\    return values[0][0]
    ,
        \\func main() -> int:
        \\    mut values = [[7], [11]]
        \\    values[0] = copy(values[0])
        \\    return values[0][0]
    , "E_SINGLE_OWNER_BORROW"));
}

// spec: OWNERSHIP-GENERATED-1
test "ownership fix preserves invariant parameter declarations and borrowed inputs" {
    const source =
        \\@invariant(self.low <= self.high)
        \\record Span:
        \\    low: int
        \\    high: int
        \\
        \\record Holder:
        \\    spans: Span[]
        \\    best: Span?
        \\
        \\record ArgumentPair:
        \\    first: Span
        \\    second: int
        \\
        \\func test_holder(holder: Holder, keyed: dict[str, Span], pair: ArgumentPair) -> bool:
        \\    const first = pair.first
        \\    return len(holder.spans) + len(keyed) == 3 and first.low == 1
        \\
        \\func plain(holder: Holder) -> int:
        \\    return len(holder.spans)
        \\
        \\func main() -> int:
        \\    mut holder = Holder(spans=[Span(low=1, high=2), Span(low=3, high=3)], best=Some(Span(low=0, high=9)))
        \\    mut passed = test_holder(holder, {"a": Span(low=-1, high=1)}, ArgumentPair(first=Span(low=1, high=4), second=0))
        \\    const base = plain(holder)
        \\    if passed:
        \\        return base + 40
        \\    else:
        \\        return base + 0
    ;
    var project = try Project.init(source);
    defer project.deinit();
    const checked = try project.run("check", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const fixed = try project.run("fix", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read();
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(source, after);
    const executed = try project.run("run", &.{ "--release", "--verify-facts", "--max-memory", "0" });
    defer executed.deinit();
    try testing.expectEqual(@as(u8, 42), executed.status);
    try testing.expectEqualStrings("", executed.stderr);
}

fn migratedRun(source: []const u8, fragment: []const u8) !void {
    var project = try Project.init(source);
    defer project.deinit();
    const preview = try project.run("fix", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const before = try project.read();
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(source, before);
    const fixed = try project.run("fix", &.{});
    defer fixed.deinit();
    if (fixed.status != 0) std.debug.print("ownership migration: {s}{s}\n", .{ fixed.stdout, fixed.stderr });
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read();
    defer testing.allocator.free(after);
    try testing.expect(contains(after, fragment));
    const checked = try project.run("check", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    const executed = try project.run("run", &.{ "--release", "--verify-facts", "--max-memory", "0" });
    defer executed.deinit();
    try testing.expectEqual(@as(u8, 0), executed.status);
    try testing.expectEqualStrings("", executed.stderr);
}

// spec-case: FIX-MIGRATION-1
test "C2 marker proof CLI converges direct element and slice copies without repeating evaluation" {
    const source =
        // migrate-embedded: skip intentional payload marker and independent element/slice copy migration.
        \\import strings
        \\func payload_text() -> str?:
        \\    return Some("payload")
        \\func payload_bytes() -> bytes?:
        \\    return Some(b"abc")
        \\func next(mut trace: int[]) -> int:
        \\    append(mut trace, 1)
        \\    return 0
        \\func stop(mut trace: int[]) -> int:
        \\    append(mut trace, 2)
        \\    return 1
        \\func last(mut trace: int[]) -> int:
        \\    append(mut trace, 3)
        \\    return 1
        \\func main(out: Stream) -> int:
        \\    mut text = ""
        \\    match payload_text():
        \\        case Some(t):
        \\            text = t
        \\        case None:
        \\            return 1
        \\    mut data = b""
        \\    match payload_bytes():
        \\        case Some(b):
        \\            data = b
        \\        case None:
        \\            return 1
        \\    mut trace: int[] = []
        \\    const source = ["later"]
        \\    mut rows: str[] = []
        \\    append(mut rows, source[next(mut trace)])
        \\    mut section = data[0:stop(mut trace)]
        \\    mut scalar = strings.char_slice(text, 0, last(mut trace))
        \\    if len(section) > 9:
        \\        section = copy(data)
        \\    if len(scalar) > 9:
        \\        scalar = copy(text)
        \\    assert trace == [1, 2, 3]
        \\    assert text == "payload" and section == b"a" and rows[0] == "later" and scalar == "p"
        \\    print(out, "marker-proof-ok")
        \\    return 0
        \\# lint: allow-file match-else reason="this corpus pins its own migration; the flat forms have unwrapping-match.selka"
        \\# lint: allow-file match-is reason="this corpus pins its own migration; the flat forms have unwrapping-match.selka"
    ;
    const first = try std.mem.replaceOwned(u8, testing.allocator, source, "text = t\n", "text = own t\n");
    defer testing.allocator.free(first);
    const second = try std.mem.replaceOwned(u8, testing.allocator, first, "data = b\n", "data = own b\n");
    defer testing.allocator.free(second);
    // The marker repair writes `copy(source[...])`; the next round sees that nothing reads `source` again and takes the element
    // (COPY-A2b): `const source` becomes `mut source`, and the index is still evaluated once.
    const taken = try std.mem.replaceOwned(u8, testing.allocator, second, "const source = [\"later\"]", "mut source = [\"later\"]");
    defer testing.allocator.free(taken);
    const third = try std.mem.replaceOwned(u8, testing.allocator, taken, "source[next(mut trace)]", "take(mut source[next(mut trace)])");
    defer testing.allocator.free(third);
    const fourth = try std.mem.replaceOwned(u8, testing.allocator, third, "data[0:stop(mut trace)]", "copy(data[0:stop(mut trace)])");
    defer testing.allocator.free(fourth);
    const expected = try std.mem.replaceOwned(u8, testing.allocator, fourth, "strings.char_slice(text, 0, last(mut trace))", "copy(strings.char_slice(text, 0, last(mut trace)))");
    defer testing.allocator.free(expected);
    try testing.expect(try migrateWarnings(source, expected, "E_OWN_MARKER"));
    var project = try Project.init(expected);
    defer project.deinit();
    const executed = try project.run("run", &.{ "--release", "--verify-facts", "--max-memory", "0" });
    defer executed.deinit();
    try testing.expectEqual(@as(u8, 0), executed.status);
    try testing.expectEqualStrings("marker-proof-ok\n", executed.stdout);
    try testing.expectEqualStrings("", executed.stderr);
}

test "C2 marker proof CLI converges a loop transfer beside an independent R5 return" {
    const source =
        // migrate-embedded: skip intentional named loop transfer and independent mixed borrowed return migration input.
        \\func merge(xs: bytes[], small: bool) -> bytes[]:
        \\    if small:
        \\        return xs
        \\    mut src = copy(xs)
        \\    mut width = 0
        \\    while width < 2:
        \\        mut dst: bytes[] = []
        \\        for value in src:
        \\            append(mut dst, copy(value))
        \\        src = dst
        \\        width += 1
        \\    return src
        \\func main() -> int:
        \\    const source = [b"a", b"b"]
        \\    assert merge(source, True) == source
        \\    assert merge(source, False) == source
        \\    return 0
    ;
    const first = try std.mem.replaceOwned(u8, testing.allocator, source, "src = dst", "src = own dst");
    defer testing.allocator.free(first);
    const expected = try std.mem.replaceOwned(u8, testing.allocator, first, "return xs", "return copy(xs)");
    defer testing.allocator.free(expected);
    try testing.expect(try migrate(source, expected, "E_OWN_MARKER"));
    var project = try Project.init(expected);
    defer project.deinit();
    const executed = try project.run("run", &.{ "--release", "--verify-facts", "--max-memory", "0" });
    defer executed.deinit();
    try testing.expectEqual(@as(u8, 0), executed.status);
    try testing.expectEqualStrings("", executed.stdout);
    // `run` leaves the hints out, so a migrated program that still draws one prints nothing.
    try testing.expectEqualStrings("", executed.stderr);
}

// spec-case: COMPREHENSION-1
test "ownership fix replaces a managed fold accumulator only after its match borrow ends" {
    try migratedRun(
        // migrate-embedded: skip intentional COMPREHENSION-1 pre-removal source
        \\func main() -> int:
        \\    const low = min(x for x in ["z", "alpha", "b"])
        \\    const high = max(x for x in ["z", "alpha", "b"])
        \\    assert low == "alpha" and high == "z"
        \\    return 0
    , "mut gather_replace_");
}

// spec-case: TUPLE-REMOVED-1
test "ownership fix snapshots a tuple local before a later operand reads or mutates it" {
    try migratedRun(
        // migrate-embedded: skip intentional TUPLE-REMOVED-1 pre-removal source
        \\func changed(mut values: int[]) -> int[]:
        \\    values.append(9)
        \\    return copy(values)
        \\func main() -> int:
        \\    mut left = [1]
        \\    mut right = [2]
        \\    left, right = right, changed(mut right)
        \\    assert left == [2] and right == [2, 9]
        \\    left, right = right, right
        \\    assert left == [2, 9] and right == [2, 9]
        \\    return 0
    , "= copy(right)");
}

// spec-case: TUPLE-REMOVED-1
test "ownership fix withholds tuple snapshots that would clone shared class identity" {
    const source =
        // migrate-embedded: skip intentional TUPLE-REMOVED-1 pre-removal source
        \\class Identity:
        \\    value: int
        \\func main() -> int:
        \\    mut left = [Identity(value=1)]
        \\    mut right = [Identity(value=2)]
        \\    left, right = right, right
        \\    return 0
    ;
    var project = try Project.init(source);
    defer project.deinit();
    const fixed = try project.run("fix", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stderr, "E_TUPLE_REMOVED"));
    const after = try project.read();
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(source, after);
}

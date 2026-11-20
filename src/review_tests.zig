//! The tests of a change. A test is a top-level `test_*` function in a project source,
//! found by a text scan of both sides and compared by module and name. A test whose
//! body differs keeps a bounded line diff. Also reads the verdict counts of a
//! `selka test` run, for `--test`. Pure: nothing is run or written here.
const std = @import("std");
const product = @import("product.zig");
const review_side = @import("review_side.zig");
const generated_marker = @import("generated_marker.zig");

/// Allocation is the only failure: the scan and the diff are built in memory.
pub const Error = std.mem.Allocator.Error;

/// Diff lines one changed test keeps. A longer diff ends with a count of what it left out.
pub const max_diff_lines = 40;
/// Output lines `--test` keeps from the end of a test run, for the JSON reader.
pub const max_tail_lines = 20;
/// Table cells the line diff may build. A larger pair of bodies is shown as a whole replacement.
const max_table_cells = 1 << 20;

/// One test function: its module, its name and its lines, from the declaration to the
/// end of its indented body, each line trimmed of trailing whitespace.
pub const Entry = struct { module: []const u8, name: []const u8, lines: []const []const u8 };

/// A test a change adds or removes, by module and name.
pub const Ref = struct { module: []const u8, name: []const u8 };

/// A test whose body differs, with its bounded line diff (`-` lines before, `+` lines after).
pub const Changed = struct { module: []const u8, name: []const u8, diff: []const []const u8 };

/// The tests a change adds, changes and removes, each list in module then name order.
pub const Changes = struct { added: []const Ref = &.{}, changed: []const Changed = &.{}, removed: []const Ref = &.{} };

/// The verdict counts of one `selka test` run and the tail of its output. `found` is
/// false when the run printed no summary line, so the counts are not a verdict.
pub const Run = struct { found: bool = false, passed: usize = 0, failed: usize = 0, skipped: usize = 0, cached: usize = 0, output_tail: []const u8 = "" };

/// Compare the test functions of two sets of project source files. Generated files are
/// not read, and only `.selka` files count.
pub fn compare(a: std.mem.Allocator, base: []const review_side.File, head: []const review_side.File) Error!Changes {
    const before = try collect(a, base);
    const after = try collect(a, head);
    var known: std.StringHashMapUnmanaged(usize) = .empty;
    for (before, 0..) |entry, index| try known.put(a, try keyOf(a, entry), index);
    const seen = try a.alloc(bool, before.len);
    @memset(seen, false);
    var added: std.ArrayList(Ref) = .empty;
    var changed: std.ArrayList(Changed) = .empty;
    for (after) |entry| {
        const index = known.get(try keyOf(a, entry)) orelse {
            try added.append(a, .{ .module = entry.module, .name = entry.name });
            continue;
        };
        seen[index] = true;
        if (sameLines(before[index].lines, entry.lines)) continue;
        try changed.append(a, .{ .module = entry.module, .name = entry.name, .diff = try diffLines(a, before[index].lines, entry.lines) });
    }
    var removed: std.ArrayList(Ref) = .empty;
    for (before, seen) |entry, found| {
        if (!found) try removed.append(a, .{ .module = entry.module, .name = entry.name });
    }
    std.mem.sort(Ref, added.items, {}, refLess);
    std.mem.sort(Changed, changed.items, {}, changedLess);
    std.mem.sort(Ref, removed.items, {}, refLess);
    return .{ .added = added.items, .changed = changed.items, .removed = removed.items };
}

/// Every test function of the non-generated `.selka` files, in path order.
fn collect(a: std.mem.Allocator, files: []const review_side.File) Error![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    for (files) |file| {
        if (!product.isSource(file.path) or generated_marker.isGenerated(file.bytes)) continue;
        try out.appendSlice(a, try scan(a, try moduleOf(a, file.path), file.bytes));
    }
    return out.items;
}

/// The `test_*` functions of one source text, each with its indented body. A body ends
/// at the first non-blank line that is not indented, and its trailing blank lines are
/// not part of it.
pub fn scan(a: std.mem.Allocator, module: []const u8, text: []const u8) Error![]const Entry {
    var split = std.mem.splitScalar(u8, text, '\n');
    var lines: std.ArrayList([]const u8) = .empty;
    while (split.next()) |raw| try lines.append(a, std.mem.trimEnd(u8, raw, " \t\r"));
    var out: std.ArrayList(Entry) = .empty;
    var index: usize = 0;
    while (index < lines.items.len) {
        const name = testName(lines.items[index]) orelse {
            index += 1;
            continue;
        };
        var end = index + 1;
        while (end < lines.items.len and (blank(lines.items[end]) or indented(lines.items[end]))) end += 1;
        while (end > index + 1 and blank(lines.items[end - 1])) end -= 1;
        try out.append(a, .{ .module = module, .name = name, .lines = lines.items[index..end] });
        index = end;
    }
    return out.items;
}

/// The name of a top-level `test_*` function declared on `line`, or null. The line
/// must start at column zero, as a top-level declaration does, with `func` or `public func`.
pub fn testName(line: []const u8) ?[]const u8 {
    var rest = line;
    if (std.mem.startsWith(u8, rest, "public ")) rest = rest["public ".len..];
    if (!std.mem.startsWith(u8, rest, "func ")) return null;
    rest = rest["func ".len..];
    var end: usize = 0;
    while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
    const name = rest[0..end];
    if (!std.mem.startsWith(u8, name, "test_")) return null;
    return name;
}

/// A line diff of two line lists: each removed line as `-line`, each added line as
/// `+line`, in order, with no context. At most `max_diff_lines` lines; a longer diff
/// keeps its first lines and ends with a count of the rest.
pub fn diffLines(a: std.mem.Allocator, before: []const []const u8, after: []const []const u8) Error![]const []const u8 {
    return bounded(a, try fullDiff(a, before, after));
}

/// The whole line diff of two line lists, unbounded, in the form `diffLines` gives: `-line`
/// for each removed line and `+line` for each added one, in order, with no context.
pub fn fullDiff(a: std.mem.Allocator, before: []const []const u8, after: []const []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    if ((before.len + 1) * (after.len + 1) > max_table_cells) {
        for (before) |line| try out.append(a, try std.fmt.allocPrint(a, "-{s}", .{line}));
        for (after) |line| try out.append(a, try std.fmt.allocPrint(a, "+{s}", .{line}));
        return out.items;
    }
    const width = after.len + 1;
    const table = try a.alloc(u32, (before.len + 1) * width);
    @memset(table, 0);
    // table[i * width + j] is the longest common run of before[i..] and after[j..].
    var i = before.len;
    while (i > 0) : (i -= 1) {
        var j = after.len;
        while (j > 0) : (j -= 1) {
            table[(i - 1) * width + (j - 1)] = if (std.mem.eql(u8, before[i - 1], after[j - 1]))
                table[i * width + j] + 1
            else
                @max(table[i * width + (j - 1)], table[(i - 1) * width + j]);
        }
    }
    var x: usize = 0;
    var y: usize = 0;
    while (x < before.len or y < after.len) {
        if (x < before.len and y < after.len and std.mem.eql(u8, before[x], after[y])) {
            x += 1;
            y += 1;
        } else if (y < after.len and (x == before.len or table[x * width + (y + 1)] > table[(x + 1) * width + y])) {
            try out.append(a, try std.fmt.allocPrint(a, "+{s}", .{after[y]}));
            y += 1;
        } else {
            try out.append(a, try std.fmt.allocPrint(a, "-{s}", .{before[x]}));
            x += 1;
        }
    }
    return out.items;
}

/// The first `max_diff_lines - 1` lines of a diff, then a count of the rest, when it is longer.
fn bounded(a: std.mem.Allocator, lines: []const []const u8) Error![]const []const u8 {
    if (lines.len <= max_diff_lines) return lines;
    const kept = max_diff_lines - 1;
    const out = try a.alloc([]const u8, max_diff_lines);
    @memcpy(out[0..kept], lines[0..kept]);
    out[kept] = try std.fmt.allocPrint(a, "… {d} more diff lines", .{lines.len - kept});
    return out;
}

/// The verdict counts of a `selka test` run, read from its last summary line,
/// `N passed, N cached, N failed, N skipped`. The tail and `found` are left to the caller.
pub fn summary(output: []const u8) Run {
    var run: Run = .{};
    var split = std.mem.splitScalar(u8, output, '\n');
    while (split.next()) |line| {
        if (countsOf(line)) |counts| run = counts;
    }
    return run;
}

/// The four counts of one summary line, or null unless the line carries all four.
fn countsOf(line: []const u8) ?Run {
    var run: Run = .{ .found = true };
    var seen: u8 = 0;
    var parts = std.mem.splitScalar(u8, line, ',');
    while (parts.next()) |part| {
        var words = std.mem.tokenizeAny(u8, part, " \t");
        var number: []const u8 = "";
        var word: []const u8 = "";
        while (words.next()) |next| {
            number = word;
            word = next;
        }
        const count = std.fmt.parseInt(usize, number, 10) catch continue;
        if (std.mem.eql(u8, word, "passed")) {
            run.passed = count;
            seen |= 1;
        } else if (std.mem.eql(u8, word, "cached")) {
            run.cached = count;
            seen |= 2;
        } else if (std.mem.eql(u8, word, "failed")) {
            run.failed = count;
            seen |= 4;
        } else if (std.mem.eql(u8, word, "skipped")) {
            run.skipped = count;
            seen |= 8;
        }
    }
    return if (seen == 15) run else null;
}

/// The last `lines` lines of a test run's output, without its final newline.
pub fn tail(text: []const u8, lines: usize) []const u8 {
    const body = std.mem.trimEnd(u8, text, "\n");
    var newlines: usize = 0;
    var index = body.len;
    while (index > 0) {
        index -= 1;
        if (body[index] != '\n') continue;
        newlines += 1;
        if (newlines == lines) return body[index + 1 ..];
    }
    return body;
}

/// The module a source path names: `app/serve.selka` is `app.serve`.
pub fn moduleOf(a: std.mem.Allocator, path: []const u8) Error![]const u8 {
    const name = try a.dupe(u8, product.chopSource(path));
    std.mem.replaceScalar(u8, name, '/', '.');
    return name;
}

fn keyOf(a: std.mem.Allocator, entry: Entry) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}::{s}", .{ entry.module, entry.name });
}

fn blank(line: []const u8) bool {
    return line.len == 0;
}

fn indented(line: []const u8) bool {
    return line.len != 0 and (line[0] == ' ' or line[0] == '\t');
}

fn sameLines(before: []const []const u8, after: []const []const u8) bool {
    if (before.len != after.len) return false;
    for (before, after) |left, right| {
        if (!std.mem.eql(u8, left, right)) return false;
    }
    return true;
}

fn refLess(_: void, left: Ref, right: Ref) bool {
    return orderedBefore(left.module, left.name, right.module, right.name);
}

fn changedLess(_: void, left: Changed, right: Changed) bool {
    return orderedBefore(left.module, left.name, right.module, right.name);
}

fn orderedBefore(module: []const u8, name: []const u8, other_module: []const u8, other_name: []const u8) bool {
    const order = std.mem.order(u8, module, other_module);
    if (order != .eq) return order == .lt;
    return std.mem.lessThan(u8, name, other_name);
}

test "review tests finds each test_ function with its indented body only" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const text = "public func test_one() -> bool:\n    return true\n\n\nfunc helper() -> int:\n    return 1\n\n\nfunc test_two() -> bool:\n    return false   \n    \n";
    const found = try scan(arena.allocator(), "main", text);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("test_one", found[0].name);
    try std.testing.expectEqualStrings("main", found[0].module);
    try std.testing.expectEqual(@as(usize, 2), found[0].lines.len);
    try std.testing.expectEqualStrings("    return true", found[0].lines[1]);
    try std.testing.expectEqualStrings("    return false", found[1].lines[1]);
}

test "review tests names only top-level test functions" {
    try std.testing.expectEqualStrings("test_answer", testName("public func test_answer() -> bool:").?);
    try std.testing.expectEqualStrings("test_b", testName("func test_b(x: int) -> bool:").?);
    try std.testing.expect(testName("    func test_nested() -> bool:") == null);
    try std.testing.expect(testName("public func answer() -> int:") == null);
    try std.testing.expect(testName("# func test_commented() -> bool:") == null);
}

test "review tests diffs a changed body line by line" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const before = [_][]const u8{ "public func test_x() -> bool:", "    return answer() == 42" };
    const after = [_][]const u8{ "public func test_x() -> bool:", "    return answer() == 40 + 2" };
    const diff = try diffLines(arena.allocator(), &before, &after);
    try std.testing.expectEqual(@as(usize, 2), diff.len);
    try std.testing.expectEqualStrings("-    return answer() == 42", diff[0]);
    try std.testing.expectEqualStrings("+    return answer() == 40 + 2", diff[1]);
}

/// `count` lines of the form `prefix N`, for the diff bound test.
fn numbered(a: std.mem.Allocator, prefix: []const u8, count: usize) Error![]const []const u8 {
    const out = try a.alloc([]const u8, count);
    for (out, 0..) |*line, index| line.* = try std.fmt.allocPrint(a, "{s} {d}", .{ prefix, index });
    return out;
}

test "review tests shows a pair of very long bodies as a whole replacement" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const diff = try diffLines(scratch, try numbered(scratch, "old", 2000), try numbered(scratch, "new", 2000));
    try std.testing.expectEqual(@as(usize, max_diff_lines), diff.len);
    try std.testing.expectEqualStrings("-old 0", diff[0]);
}

test "review tests bounds a long diff at forty lines and counts the rest" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const diff = try diffLines(scratch, try numbered(scratch, "old", 50), try numbered(scratch, "new", 50));
    try std.testing.expectEqual(@as(usize, max_diff_lines), diff.len);
    try std.testing.expectEqualStrings("… 61 more diff lines", diff[max_diff_lines - 1]);
}

test "review tests compares added, changed and removed tests by module and name" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const base = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "public func test_gone() -> bool:\n    return true\n\n\npublic func test_kept() -> bool:\n    return true\n" },
    };
    const head = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "public func test_kept() -> bool:\n    return false\n\n\npublic func test_new() -> bool:\n    return true\n" },
    };
    const changes = try compare(scratch, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), changes.added.len);
    try std.testing.expectEqualStrings("test_new", changes.added[0].name);
    try std.testing.expectEqual(@as(usize, 1), changes.changed.len);
    try std.testing.expectEqualStrings("test_kept", changes.changed[0].name);
    try std.testing.expectEqual(@as(usize, 1), changes.removed.len);
    try std.testing.expectEqualStrings("test_gone", changes.removed[0].name);
}

test "review tests reads a test in a nested module by its dotted module name" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const head = [_]review_side.File{.{ .path = "app/serve_test.selka", .bytes = "public func test_port() -> bool:\n    return true\n" }};
    const changes = try compare(scratch, &.{}, &head);
    try std.testing.expectEqualStrings("app.serve_test", changes.added[0].module);
    try std.testing.expectEqualStrings("test_port", changes.added[0].name);
}

test "review tests skips the tests of a generated file" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const head = [_]review_side.File{.{ .path = "ports.selka", .bytes = "# GENERATED by gen_ports.py\npublic func test_port() -> bool:\n    return true\n" }};
    const changes = try compare(arena.allocator(), &.{}, &head);
    try std.testing.expectEqual(@as(usize, 0), changes.added.len);
}

test "review tests reads the verdict counts from the summary line of a run" {
    const run = summary("passed main::test_answer\nfailed main::test_bad: expected true\n1 passed, 0 cached, 1 failed, 0 skipped\n");
    try std.testing.expect(run.found);
    try std.testing.expectEqual(@as(usize, 1), run.passed);
    try std.testing.expectEqual(@as(usize, 0), run.cached);
    try std.testing.expectEqual(@as(usize, 1), run.failed);
    try std.testing.expectEqual(@as(usize, 0), run.skipped);
}

test "review tests reports no summary when a run printed none" {
    const run = summary("selka: cannot build main.selka\n");
    try std.testing.expect(!run.found);
    try std.testing.expectEqual(@as(usize, 0), run.passed);
}

test "review tests keeps the last lines of a run's output" {
    try std.testing.expectEqualStrings("b\nc", tail("a\nb\nc\n", 2));
    try std.testing.expectEqualStrings("c", tail("a\nb\nc\n", 1));
    try std.testing.expectEqualStrings("only", tail("only", 2));
}

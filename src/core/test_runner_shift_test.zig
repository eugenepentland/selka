//! T1 of lane T (6 November 2026): a test's IR key leaves out source positions, so lines moved by an edit above a test rerun
//! none of the tests they do not change, while every failure still runs and reports where it is now. The soundness list these
//! tests stand for is `experiments/test-keys-20261106/DECISIONS.md`, D-T1-1.
const std = @import("std");
const language = @import("selka");
const tools = @import("core_test_options");
const v = @import("property_value.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const pipeline = @import("pipeline.zig");
const closure = @import("canonical_closure.zig");

const Outcome = struct { status: u8, report: std.json.Value, stderr: []const u8 };

const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    /// Read every source of the stored report by its bytes (`SELKA_TEST_TOKEN_REPORTS=0`), so that a comment edit is
    /// checked again and the key derivation it exercises runs (stage 6 of the test-loop plan replays the report otherwise).
    bytes_reports: bool = false,

    fn write(self: Project, bytes: []const u8) !void {
        const absolute = try std.fs.path.join(self.arena, &.{ self.root, "app.selka" });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = absolute, .data = bytes });
    }

    fn run(self: Project) !Outcome {
        const path = try std.fs.path.join(self.arena, &.{ self.root, "app.selka" });
        const cache = try std.fs.path.join(self.arena, &.{ self.root, "cache" });
        const argv = [_][]const u8{ tools.corePath(), "test", path, "--json", "--cache-dir", cache };
        // These tests count the project's own runs and records: no shared store.
        var environment = try tools.privateEnvironment(self.arena);
        if (self.bytes_reports) try environment.put("SELKA_TEST_TOKEN_REPORTS", "0");
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{}) catch .null;
        const status: u8 = switch (result.term) {
            .exited => |code| code,
            else => 255,
        };
        return .{ .status = status, .report = parsed, .stderr = result.stderr };
    }
};

fn testOf(report: std.json.Value, name: []const u8) !std.json.Value {
    for (v.array(v.get(report, "tests"))) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
    return error.MissingTestVerdict;
}

fn expectStatus(report: std.json.Value, name: []const u8, wanted: []const u8) !void {
    try std.testing.expectEqualStrings(wanted, v.text(v.get(try testOf(report, name), "status")));
}

fn expectCachedBy(report: std.json.Value, name: []const u8, reason: []const u8) !void {
    const item = try testOf(report, name);
    try std.testing.expectEqualStrings("cached", v.text(v.get(item, "status")));
    try std.testing.expectEqualStrings(reason, v.text(v.get(v.get(item, "cache"), "reason")));
}

/// Whether the failure text of `name` names `app.selka` at `line`.
fn namesLine(a: std.mem.Allocator, report: std.json.Value, name: []const u8, line: usize) !bool {
    const reason = v.text(v.get(try testOf(report, name), "reason"));
    return std.mem.indexOf(u8, reason, try std.fmt.allocPrint(a, "app.selka:{d}:", .{line})) != null;
}

/// The one-based line of the first occurrence of `needle` in `text`.
fn lineOf(text: []const u8, needle: []const u8) usize {
    const at = std.mem.indexOf(u8, text, needle).?;
    return std.mem.count(u8, text[0..at], "\n") + 1;
}

const shift_source =
    \\func helper() -> int:
    \\    return 1
    \\
    \\
    \\public func answer() -> int:
    \\    """The answer, with an example that expects another one.
    \\
    \\    >>> answer()
    \\    41
    \\    """
    \\    return 42
    \\
    \\
    \\func fails_here() -> int fails str:
    \\    fail "always"
    \\
    \\
    \\public func test_dependent() -> bool:
    \\    return helper() > 0
    \\
    \\
    \\public func test_unrelated() -> bool:
    \\    return True
    \\
    \\
    \\public func test_asserts() -> bool:
    \\    assert helper() == 2, "helper should be two"
    \\    return True
    \\
    \\
    \\public func test_propagates() -> bool fails str:
    \\    const value = try fails_here()
    \\    return value > 0
    \\
    \\
    \\public func test_traps() -> bool:
    \\    const values = [1, 2, 3]
    \\    return values[helper() + 6] > 0
    \\
;

const shift_line = "# A comment line, which moves every line below it down by one.\n";

// spec: T1-SHIFT-1
test "a comment line added above every function reruns none of the passing tests, and each failure reports its new line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try project.write(shift_source);
    const before = try project.run();
    try std.testing.expectEqual(@as(u8, 1), before.status);
    try expectStatus(before.report, "app::test_dependent", "passed");
    try expectStatus(before.report, "app::test_unrelated", "passed");
    try expectFailuresAt(a, before.report, shift_source, null);
    const moved = try std.mem.concat(a, u8, &.{ shift_line, shift_source });
    try project.write(moved);
    const after = try project.run();
    try std.testing.expectEqual(@as(u8, 1), after.status);
    // Neither passing test is rerun, and neither is served by a replayed report (the file changed): by its IR key.
    try expectCachedBy(after.report, "app::test_dependent", "engine-hit");
    try expectCachedBy(after.report, "app::test_unrelated", "engine-hit");
    try std.testing.expectEqual(@as(i64, 0), v.get(after.report, "passed").integer);
    // A failure is never recorded: each one runs again and names the line it is on now, not the line it was on.
    try expectFailuresAt(a, after.report, moved, shift_source);
}

/// Every failing test of `shift_source` failed, naming the line its failing site is on in `source` and, when `earlier` is
/// given, not the line it was on in `earlier`.
fn expectFailuresAt(a: std.mem.Allocator, report: std.json.Value, source: []const u8, earlier: ?[]const u8) !void {
    const sites = [_][]const u8{ "assert helper()", "fail \"always\"", ">>> answer()", "return values[" };
    const failing = [_][]const u8{ "app::test_asserts", "app::test_propagates", "app::answer.example", "app::test_traps" };
    for (failing, sites) |name, site| {
        try expectStatus(report, name, "failed");
        try std.testing.expect(try namesLine(a, report, name, lineOf(source, site)));
        if (earlier) |old| try std.testing.expect(!try namesLine(a, report, name, lineOf(old, site)));
    }
}

// spec-case: T1-SHIFT-1
test "an edited function body reruns the tests that reach it even when the edit also moves every line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const source = "func helper() -> int:\n    return 1\n\n\npublic func test_dependent() -> bool:\n    return helper() > 0\n\n\npublic func test_unrelated() -> bool:\n    return True\n";
    try project.write(source);
    const cold = try project.run();
    try std.testing.expectEqual(@as(u8, 0), cold.status);
    try expectStatus(cold.report, "app::test_dependent", "passed");
    const edited = try std.mem.replaceOwned(u8, a, source, "return 1", "return 2");
    try project.write(try std.mem.concat(a, u8, &.{ shift_line, edited }));
    const changed = try project.run();
    try std.testing.expectEqual(@as(u8, 0), changed.status);
    try expectStatus(changed.report, "app::test_dependent", "passed");
    try expectCachedBy(changed.report, "app::test_unrelated", "engine-hit");
    // The edit that breaks the helper's test is a failure on the first run after it.
    try project.write(try std.mem.concat(a, u8, &.{ shift_line, shift_line, try std.mem.replaceOwned(u8, a, source, "return 1", "return 0") }));
    const broken = try project.run();
    try std.testing.expectEqual(@as(u8, 1), broken.status);
    try expectStatus(broken.report, "app::test_dependent", "failed");
    try expectCachedBy(broken.report, "app::test_unrelated", "engine-hit");
}

/// A program that reaches the constructs whose behaviour reads a position on a failure: an assertion, a bounds trap, an
/// error return trace, a `match`, a record, a loop and string and number text.
const corpus =
    \\record Pair:
    \\    left: int
    \\    right: str
    \\
    \\
    \\enum Shape:
    \\    Dot(at: int)
    \\    Line(from: int, to: int)
    \\
    \\
    \\func origin(value: int) -> int fails str:
    \\    if value < 0:
    \\        fail "negative"
    \\    return value
    \\
    \\
    \\func carried(value: int) -> int fails str:
    \\    const found = try origin(value)
    \\    return found + 1
    \\
    \\
    \\func measure(shape: Shape) -> int:
    \\    match shape:
    \\        case Dot(at):
    \\            return at
    \\        case Line(from, to):
    \\            return to - from
    \\
    \\
    \\func total(values: int[]) -> int:
    \\    mut sum = 0
    \\    for value in values:
    \\        assert value >= 0, "values are counts"
    \\        sum += value
    \\    return sum + values[2]
    \\
    \\
    \\func main() -> int:
    \\    const pair = Pair(left=1, right="one")
    \\    const shapes = [Shape.Dot(at=2), Shape.Line(from=1, to=4)]
    \\    mut sum = total([1, 2, 3]) + measure(shapes[1]) + pair.left
    \\    match carried(sum):
    \\        case Ok(value):
    \\            sum = value
    \\        case Err(_):
    \\            return 1
    \\    if str(sum) == pair.right:
    \\        return 2
    \\    return sum
    \\
;

const Lowered = struct { module: ir.Module, source: *language.source.Source };

fn lowered(a: std.mem.Allocator, bytes: []const u8) !Lowered {
    const source = try a.create(language.source.Source);
    source.* = try language.source.Source.init(a, "app.selka", bytes);
    var unit = try language.Compilation.init(a, source.path, source.bytes);
    unit.src = source.*;
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildRootsSource(a, unit.program.?, &.{unit.program.?.main}, source.*, &refusal);
    return .{ .module = module, .source = source };
}

// spec-case: T1-SHIFT-1
test "lines moved above a program change only the spans of its Core IR: every plain digest and string stays, positions move" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try lowered(a, corpus);
    const moved = try lowered(a, try std.mem.concat(a, u8, &.{ shift_line, "\n# and another\n", corpus }));
    try std.testing.expectEqual(original.module.functions.items.len, moved.module.functions.items.len);
    try std.testing.expect(original.module.functions.items.len > 4);
    try std.testing.expectEqual(original.module.strings.items.len, moved.module.strings.items.len);
    try std.testing.expectEqualDeep(original.module.strings.items, moved.module.strings.items);
    const plain_before = try closure.Shared.plain(a, &original.module, pipeline.locator(original.source));
    const plain_after = try closure.Shared.plain(a, &moved.module, pipeline.locator(moved.source));
    try std.testing.expectEqualDeep(plain_before, plain_after);
    // The positioned digests, which the program key and the optimizer's records keep, do move.
    const placed_before = try closure.Shared.build(a, &original.module, pipeline.locator(original.source));
    const placed_after = try closure.Shared.build(a, &moved.module, pipeline.locator(moved.source));
    try std.testing.expect(differing(placed_before.digests, placed_after.digests) > 4);
    // An edit to one body moves its plain digest.
    const edited = try lowered(a, try std.mem.replaceOwned(u8, a, corpus, "return found + 1", "return found + 2"));
    const plain_edited = try closure.Shared.plain(a, &edited.module, pipeline.locator(edited.source));
    try std.testing.expectEqual(@as(usize, 1), differing(plain_before.digests, plain_edited.digests));
}

fn differing(left: []const closure.Digest, right: []const closure.Digest) usize {
    var count: usize = 0;
    for (left, right) |one, other| count += @intFromBool(!std.mem.eql(u8, &one, &other));
    return count;
}

/// Two recursive enums of one structure, each copied: their owned-copy helpers share a canonical identity.
const twin_copies =
    \\enum Left:
    \\    leaf(value: int)
    \\    node(children: Left[])
    \\
    \\
    \\enum Right:
    \\    leaf(value: int)
    \\    node(children: Right[])
    \\
    \\
    \\func first(left: Left) -> Left:
    \\    return copy(left)
    \\
    \\
    \\func second(right: Right) -> Right:
    \\    return copy(right)
    \\
    \\
    \\public func test_copies() -> bool:
    \\    const left = Left.node(children=[Left.leaf(value=1)])
    \\    const right = Right.node(children=[Right.leaf(value=2)])
    \\    _ = first(left)
    \\    _ = second(right)
    \\    return True
    \\
;

fn producerOf(report: std.json.Value, name: []const u8) !std.json.Value {
    return v.get(v.get(v.get(try testOf(report, name), "cache"), "work"), "producer");
}

// spec: T2-FACTS-1
test "owned-copy helpers of two types of one structure keep a test's keys on the stored facts, which the next run reuses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    // The comment edit below must reach the key derivation, not a replay of the stored report.
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), .bytes_reports = true };
    try project.write(twin_copies);
    const cold = try project.run();
    try std.testing.expectEqual(@as(u8, 0), cold.status);
    // Until 6 November the two helpers' shared identity refused the stored facts, and every run lowered the whole program again
    // (`reachable-ir`).
    try std.testing.expectEqualStrings("canonical-facts", v.text(v.get(v.get(try testOf(cold.report, "app::test_copies"), "cache"), "key_method")));
    try std.testing.expectEqualStrings("", v.text(v.get(try producerOf(cold.report, "app::test_copies"), "refused")));
    // A comment after every declaration changes the file and no function's key.
    try project.write(try std.mem.concat(a, u8, &.{ twin_copies, shift_line }));
    const warm = try project.run();
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    try expectCachedBy(warm.report, "app::test_copies", "engine-hit");
    const producer = try producerOf(warm.report, "app::test_copies");
    try std.testing.expect(v.get(v.get(producer, "facts"), "reused").integer > 0);
    try std.testing.expectEqual(@as(i64, 0), v.get(v.get(producer, "lowering"), "fresh").integer);
}

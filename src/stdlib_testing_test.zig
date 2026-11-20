//! The `testing` module: measured blocks and managed allocations, the 1.5x growth
//! rule with its failure text, the counter readers' refusal without step
//! accounting, and the reserved internal spellings. Every check runs in the two
//! gate modes, optimized debug and release.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const support = @import("test_support.zig");

/// The two gate modes, as the `selka run` flags that select them.
const modes = [_][]const u8{ "", "--release" };

/// Step ceiling for a fixture whose quadratic workload is far above the test
/// budget; a plain run of the same fixture carries no accounting on purpose.
const budget = 40_000_000;

const store_work =
    \\func store(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        const line = f"x {i}"
    \\        total += len(line)
    \\    return total
    \\
;

const quadratic_work =
    \\func scan(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        mut j = 0
    \\        while j < n:
    \\            total += 1
    \\            j += 1
    \\    return total
    \\
;

/// True when `mode` is the release mode and release builds are off (`-Dtest-release=true` turns them on). The mode loops leave
/// that iteration out so the debug mode still runs and asserts; every test that uses them then ends with
/// `support.requireRelease()`, which reports it as skipped, never as passed.
fn releaseOff(mode: []const u8) bool {
    support.requireReleaseArgs(&.{mode}) catch return true;
    return false;
}

/// Run one fixture in one mode, with or without a step ceiling.
fn execute(allocator: std.mem.Allocator, text: []const u8, mode: []const u8, steps: ?u64) !native.Run {
    try support.requireReleaseArgs(&.{mode});
    var entry: fixture.Entry = .{ .text = text };
    var loaded: language.embedded_project.Program = undefined;
    try loaded.init(allocator, .{ .context = &entry, .read = fixture.Entry.read });
    defer loaded.deinit();
    var flags: [1][]const u8 = .{mode};
    var arguments: []const []const u8 = &.{};
    if (mode.len != 0) arguments = flags[0..];
    const options: native.Options = .{ .max_steps = steps, .arguments = arguments };
    return native.runWithOptions(&loaded.compilation, options);
}

/// Require `text` to return `wanted` in both gate modes.
fn expectModes(allocator: std.mem.Allocator, text: []const u8, wanted: i64) !void {
    for (modes) |mode| {
        if (releaseOff(mode)) continue;
        const outcome = try execute(allocator, text, mode, budget);
        try t.expect(!outcome.trapped());
        try t.expectEqual(wanted, outcome.value);
    }
}

/// Require `text` to trap with `code` in both gate modes and to name every
/// `fragment` of its report.
fn trapModes(allocator: std.mem.Allocator, text: []const u8, code: []const u8, fragments: []const []const u8) !void {
    for (modes) |mode| {
        if (releaseOff(mode)) continue;
        const outcome = try execute(allocator, text, mode, budget);
        try t.expect(outcome.trapped());
        try t.expectEqualStrings(code, outcome.trap.code);
        for (fragments) |fragment| try t.expect(std.mem.indexOf(u8, outcome.stderr, fragment) != null);
    }
}

/// A program assembled from a header, a work function and a `main` body.
fn fixtureProgram(allocator: std.mem.Allocator, work: []const u8, main_body: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ "import testing\n\n", work, "\nfunc main() -> int:\n", main_body });
}

test "testing counts executed blocks and managed allocations for a workload" {
    const text = try fixtureProgram(t.allocator, store_work ++
        \\func sum_to(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        total += i
        \\    return total
        \\
    , "    if testing.steps(store, 100) <= 0:\n" ++
        "        return 1\n" ++
        "    if testing.allocations(store, 200) != 200:\n" ++
        "        return 2\n" ++
        "    if testing.allocations(sum_to, 1000) != 0:\n" ++
        "        return 3\n" ++
        "    return 42\n");
    defer t.allocator.free(text);
    try expectModes(t.allocator, text, 42);
    try support.requireRelease();
}

test "testing.linear passes a linear workload and fails a quadratic one naming the counter, the values and the ratio" {
    const passing = try fixtureProgram(t.allocator, store_work, "    if not testing.linear(store, 500, 2000):\n        return 1\n    return 42\n");
    defer t.allocator.free(passing);
    try expectModes(t.allocator, passing, 42);
    const failing = try fixtureProgram(t.allocator, quadratic_work, "    if not testing.linear(scan, 100, 400):\n        return 1\n    return 42\n");
    defer t.allocator.free(failing);
    try trapModes(t.allocator, failing, "R_ASSERT", &.{ "testing.linear: steps grew", " at n=100 to ", " at n=400", "the limit is 6.0×" });
    try support.requireRelease();
}

test "testing.constant allows 1.5x plus two counts and fails a workload that grows" {
    const passing = try fixtureProgram(t.allocator, "func fixed(n: int) -> int:\n    return n * 3\n\n", "    if not testing.constant(fixed, 1000, 4000):\n        return 1\n    return 42\n");
    defer t.allocator.free(passing);
    try expectModes(t.allocator, passing, 42);
    const failing = try fixtureProgram(t.allocator, store_work, "    if not testing.constant(store, 100, 400):\n        return 1\n    return 42\n");
    defer t.allocator.free(failing);
    try trapModes(t.allocator, failing, "R_ASSERT", &.{ "testing.constant: steps grew", "× from ", " at n=100 to ", " at n=400", "the limit is 1.5× plus 2 counts" });
    try support.requireRelease();
}

test "the growth limit is 1.5 times the size step, so exactly six times passes and six point zero zero one fails" {
    const exact = try fixtureProgram(t.allocator, "func six_x(n: int) -> int:\n" ++
        "    const blocks = n + (n - 1000) * 2 // 3\n" ++
        "    mut total = 0\n" ++
        "    for i in range(blocks):\n" ++
        "        const line = f\"x {i}\"\n" ++
        "        total += len(line)\n" ++
        "    return total\n\n", "    if testing.growth(six_x, 1000, 4000) != 6.0:\n        return 1\n" ++
        "    if not testing.linear(six_x, 1000, 4000):\n        return 2\n" ++
        "    return 42\n");
    defer t.allocator.free(exact);
    try expectModes(t.allocator, exact, 42);
    const over = try fixtureProgram(t.allocator, "func six_x_plus(n: int) -> int:\n" ++
        "    const blocks = n + (n - 1000) * 2 // 3 + (n - 1000) // 3000\n" ++
        "    mut total = 0\n" ++
        "    for i in range(blocks):\n" ++
        "        const line = f\"x {i}\"\n" ++
        "        total += len(line)\n" ++
        "    return total\n\n", "    if not testing.linear(six_x_plus, 1000, 4000):\n        return 1\n    return 42\n");
    defer t.allocator.free(over);
    try trapModes(t.allocator, over, "R_ASSERT", &.{ "testing.linear: allocations grew 6.001×", "at n=1000 to 6001 at n=4000" });
    try support.requireRelease();
}

/// Require a fixture to refuse a counter read without step accounting and to
/// count once a budget installs it, in both gate modes.
fn expectAccountingRequired(allocator: std.mem.Allocator, text: []const u8) !void {
    for (modes) |mode| {
        if (releaseOff(mode)) continue;
        const refused = try execute(allocator, text, mode, null);
        try t.expect(refused.trapped());
        try t.expectEqualStrings("R_NO_STEP_ACCOUNTING", refused.trap.code);
        const counted = try execute(allocator, text, mode, 1_000_000);
        try t.expect(!counted.trapped());
        try t.expectEqual(@as(i64, 42), counted.value);
    }
}

test "the counter readers refuse a program that carries no step accounting" {
    const work = "func sum_to(n: int) -> int:\n    mut total = 0\n    for i in range(n):\n        total += i\n    return total\n\n";
    const body = "    if testing.steps(sum_to, 10) <= 0:\n        return 1\n    return 42\n";
    const text = try fixtureProgram(t.allocator, work, body);
    defer t.allocator.free(text);
    try expectAccountingRequired(t.allocator, text);
    try support.requireRelease();
}

/// Check that ordinary source spelling `body` inside `main` is refused as an
/// internal name.
fn rejectInternal(body: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ "func main() -> int:\n", body, "    return 0\n" });
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "main.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", compilation.diagnostics.items[0].code);
}

test "ordinary source cannot spell the testing module's counter readers" {
    try rejectInternal("    _ = __test_blocks()\n");
    try rejectInternal("    _ = __test_allocations(True)\n");
    try rejectInternal("    mut __test_blocks = 0\n    return __test_blocks\n");
}

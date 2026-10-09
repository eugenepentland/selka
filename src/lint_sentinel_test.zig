//! `sentinel-int`: an `int` used as a sentinel is reported where a negative
//! literal marks it, and it names the `Option[int]` rewrite. Under `agent` it
//! reports; under `strict` it blocks. `find` and `find_any` are exempt by name,
//! because `-1` is that method's own contract.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");

const lint = language.lint;

/// The plan's `find_pin`/`wire` pair: one path returns `-1` and the caller
/// tests the result against a negative literal.
const sentinel_fixture =
    \\
    \\
    \\record Pin:
    \\    name: str
    \\    net: int
    \\
    \\
    \\func find_pin(pins: Pin[], name: str) -> int:
    \\    for index, pin in enumerate(pins):
    \\        if pin.name == name:
    \\            return index
    \\    return -1
    \\
    \\
    \\func wire(pins: Pin[], name: str) -> int:
    \\    mut index = find_pin(pins, name)
    \\    if index < 0:
    \\        return 0
    \\    return pins[index].net
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// `find` returns `-1` by contract, and `str.find`/`bytes.find` mirror it, so a
/// project function of that name is exempt and its caller is quiet.
const find_fixture =
    \\
    \\
    \\func find(text: str, needle: str) -> int:
    \\    for index, value in enumerate(text):
    \\        if value == needle:
    \\            return index
    \\    return -1
    \\
    \\
    \\func scan(text: str, needle: str) -> int:
    \\    mut at = find(text, needle)
    \\    if at < 0:
    \\        return 0
    \\    return at
    \\
    \\
    \\func locate(raw: bytes) -> int:
    \\    return raw.find(b"z")
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// One record field and one parameter, each compared against `-1` twice.
const repeated_fixture =
    \\
    \\
    \\record Probe:
    \\    state: int
    \\
    \\
    \\func failed(probe: Probe) -> bool:
    \\    return probe.state == -1
    \\
    \\
    \\func cleared(probe: Probe) -> bool:
    \\    return probe.state != -1
    \\
    \\
    \\func repeated(code: int) -> bool:
    \\    if code == -1:
    \\        return False
    \\    return code != -1
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// Evaluate the whole lint pipeline over one fixture entry without writing to
/// stdout, which is the test runner's own protocol pipe.
fn evaluateFixture(scratch: std.mem.Allocator, root: []const u8, profile: ?lint_config.Profile, gate: bool) !lint.Outcome {
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(scratch, &.{ root, "main.my" });
    return lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{ .gate = gate, .profile = profile },
        .diagnostics = .text,
    }, scratch);
}

/// Write one fixture as a module entry under a fresh temp root and return that
/// root; the caller frees it.
fn writeFixture(temp: *std.testing.TmpDir, text: []const u8) ![:0]u8 {
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = text });
    return temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

/// The one `L_SENTINEL_INT` finding whose message contains `needle`, or null.
fn sentinelFinding(outcome: lint.Outcome, needle: []const u8) ?lint.Finding {
    for (outcome.findings) |finding| {
        if (!std.mem.eql(u8, finding.code, "L_SENTINEL_INT")) continue;
        if (std.mem.indexOf(u8, finding.message, needle) != null) return finding;
    }
    return null;
}

/// How many `L_SENTINEL_INT` findings one outcome carries.
fn sentinelCount(outcome: lint.Outcome) usize {
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (std.mem.eql(u8, finding.code, "L_SENTINEL_INT")) count += 1;
    }
    return count;
}

// spec: OPTION-METHODS-3
test "sentinel lint reports the find_pin shape under agent and refuses under strict" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeFixture(&temp, sentinel_fixture);
    defer t.allocator.free(root);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const agent = try evaluateFixture(scratch, root, null, false);
    const reported = sentinelFinding(agent, "find_pin");
    try t.expect(reported != null);
    try t.expectEqualStrings("`find_pin` returns -1 on one path and its result is tested against a negative literal here; return `Option[int]` and test `is None` or use `unwrap_or`", reported.?.message);
    try t.expect(reported.?.severity == .warning);
    try t.expectEqual(@as(usize, 0), agent.blocking);

    const strict = try evaluateFixture(scratch, root, .strict, true);
    const refused = sentinelFinding(strict, "find_pin");
    try t.expect(refused != null);
    try t.expect(refused.?.severity == .err);
    try t.expect(strict.blocking >= 1);
}

// spec-case: OPTION-METHODS-3
test "sentinel lint exempts find by name and leaves ordinary code quiet" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeFixture(&temp, find_fixture);
    defer t.allocator.free(root);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, null, false);
    try t.expectEqual(@as(usize, 0), sentinelCount(outcome));
}

// spec-case: OPTION-METHODS-3
test "sentinel lint reports a field and a parameter compared against -1 twice" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeFixture(&temp, repeated_fixture);
    defer t.allocator.free(root);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, null, false);
    try t.expectEqual(@as(usize, 2), sentinelCount(outcome));
    const field = sentinelFinding(outcome, "field `state` of `Probe`");
    try t.expect(field != null);
    try t.expectEqualStrings("field `state` of `Probe` is compared against -1 in 2 places; declare it `Option[int]` and test `is None` or use `unwrap_or`", field.?.message);
    const parameter = sentinelFinding(outcome, "parameter `code` of `repeated`");
    try t.expect(parameter != null);
    try t.expectEqualStrings("parameter `code` of `repeated` is compared against -1 in 2 places; declare it `Option[int]` and test `is None` or use `unwrap_or`", parameter.?.message);
}

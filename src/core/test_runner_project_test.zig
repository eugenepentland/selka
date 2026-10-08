//! Project tests exercise fresh runs, unchanged receipts, provider edits and
//! dependency invalidation through the actual command and native processes.
const std = @import("std");
const tools = @import("core_test_options");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const v = @import("property_value.zig");
const Outcome = struct { status: u8, report: std.json.Value, stderr: []const u8 };
const command_cache = "--cache-dir";
const InvalidCase = struct { name: []const u8, body: []const u8, settings: []const u8 };
const diagnostic = std.debug.print;
const Context = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    fn write(self: Context, path: []const u8, bytes: []const u8) !void {
        const absolute = try std.fs.path.join(self.arena, &.{ self.root, path });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(absolute).?);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = absolute, .data = bytes });
    }
    fn writeInterfaces(self: Context, source: []const u8) !void {
        const path = try std.fs.path.join(self.arena, &.{ self.root, source });
        var diagnostics: std.ArrayList(u8) = .empty;
        const located = try project_entry.resolve(self.arena, std.testing.io, path, &diagnostics);
        var session = frontend.Session.init(self.arena, std.testing.io, located.root);
        defer session.deinit();
        located.configure(&session);
        session.entry_suffix = @import("test_runner.zig").check_stub;
        _ = try session.checkFile(self.arena, located.path, &diagnostics);
        const written = try language.api_files.run(self.arena, .{ .io = std.testing.io, .root = located.root, .entry = located.path, .mode = .write, .json = false }, session.interfaceIndex());
        try std.testing.expectEqual(@as(u8, 0), written.status);
    }
    fn run(self: Context, source: []const u8, extra: []const []const u8) !Outcome {
        const path = try std.fs.path.join(self.arena, &.{ self.root, source });
        const cache = try std.fs.path.join(self.arena, &.{ self.root, "cache" });
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(self.arena, &.{ tools.core_path, "test", path, "--json", command_cache, cache, "--jobs", "2", "--property-runs", "5" });
        try args.appendSlice(self.arena, extra);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = args.items });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{}) catch .null;
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .report = parsed, .stderr = result.stderr };
    }
};
const project_source =
    \\module app
    \\import dep
    \\
    \\public def test_dependency() -> bool:
    \\    return dep.value() == 3
    \\
    \\public def test_constant() -> bool:
    \\    return True
    \\
    \\public def test_property(x: int) -> bool:
    \\    return x == x
    \\
    \\def main() -> int:
    \\    return 0
    \\
;
const dependency_three = "module dep\n\npublic def value() -> int:\n    return 3\n";
const dependency_four = "module dep\n\npublic def value() -> int:\n    return 4\n";

// spec-case: NEW-CORE-S4-TEST-3
test "guestTool refuses a missing executable before checking or replaying tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", project_source);
    try context.write("dep.my", dependency_three);
    const missing = try std.fs.path.join(a, &.{ context.root, "absent-zig" });
    const found = try context.run("app.my", &.{ "--zig", missing });
    try std.testing.expectEqual(@as(u8, 1), found.status);
    try std.testing.expect(std.mem.indexOf(u8, found.stderr, "ToolNotFound") != null);
    const directory = try context.run(".", &.{ "--zig", missing });
    try std.testing.expectEqual(@as(u8, 1), directory.status);
    try std.testing.expect(std.mem.indexOf(u8, directory.stderr, "ToolNotFound") != null);
}

fn verdict(value: std.json.Value, name: []const u8, wanted: []const u8) !void {
    for (v.array(v.get(value, "tests"))) |item| {
        if (!std.mem.eql(u8, v.text(v.get(item, "name")), name)) continue;
        try std.testing.expectEqualStrings(wanted, v.text(v.get(item, "status")));
        return;
    }
    return error.MissingTestVerdict;
}
fn expectStatus(context: Context, found: Outcome, status: u8) !void {
    if (found.status != status) {
        const json = try std.json.Stringify.valueAlloc(context.arena, found.report, .{});
        diagnostic("unexpected project test result: {s}\n{s}\n", .{ found.stderr, json });
    }
    try std.testing.expectEqual(status, found.status);
}

// spec: NEW-CORE-S4-TEST-2
// spec: NEW-CORE-S4-TEST-3
test "directory receipts account for orphan libraries and rerun only the edited reachable program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("app.my", project_source);
    try context.write("dep.my", dependency_three);
    try context.write("orphan.my", "module orphan\n\ndef test_orphan() -> bool:\n    return True\n");
    const cold = try context.run(".", &.{});
    try expectStatus(context, cold, 0);
    try std.testing.expectEqual(@as(u64, 4), v.number(v.get(cold.report, "passed")));
    const warm = try context.run(".", &.{});
    try expectStatus(context, warm, 0);
    try std.testing.expectEqual(@as(u64, 4), v.number(v.get(warm.report, "cached")));
    try context.write("dep.my", dependency_four);
    const changed = try context.run(".", &.{});
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try verdict(changed.report, "app::test_constant", "cached");
    try verdict(changed.report, "app::test_property", "cached");
    try verdict(changed.report, "orphan::test_orphan", "cached");
    const force = try context.run("app.my", &.{ "--force", "--filter", "test_constant" });
    try expectStatus(context, force, 0);
    try verdict(force.report, "app::test_constant", "passed");
}

// spec: NEW-CORE-S4-TEST-4
test "localReplay invalidates provider edits and explicit expectations in successful test receipts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", project_source);
    try context.write("dep.my", dependency_three);
    const fixture = try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.my" = dependency_four }, .expected = false } }, .{});
    try context.write("app.cases.json", fixture);
    const cold = try context.run("app.my", &.{ "--filter", "test_dependency" });
    try expectStatus(context, cold, 0);
    try verdict(cold.report, "app::test_dependency", "passed");
    const warm = try context.run("app.my", &.{ "--filter", "test_dependency" });
    try expectStatus(context, warm, 0);
    try verdict(warm.report, "app::test_dependency", "cached");
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.my" = dependency_three }, .expected = false } }, .{}));
    const changed = try context.run("app.my", &.{ "--filter", "test_dependency" });
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try context.write("app.cases.json", "{\"missing::test_unknown\":{}}");
    const unknown = try context.run("app.my", &.{});
    try expectStatus(context, unknown, 1);
    try std.testing.expect(std.mem.indexOf(u8, unknown.stderr, "UnknownTestCase") != null);
    const replacement = try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"app.my" = project_source } } }, .{});
    try context.write("app.cases.json", replacement);
    const entry_override = try context.run("app.my", &.{});
    try expectStatus(context, entry_override, 1);
    try std.testing.expect(std.mem.indexOf(u8, entry_override.stderr, "invalid test provider dependencies") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
// spec-case: NEW-CORE-S4-TEST-3
test "provider-only imports and embedded assets participate in receipt invalidation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", project_source);
    try context.write("dep.my", dependency_three);
    try context.write("extra.my", "module extra\n\npublic def value() -> int:\n    return 3\n");
    const provided = "module dep\nimport extra\n\npublic def value() -> int:\n    return extra.value() + len(embed_bytes(\"data.bin\")) - 1\n";
    try context.write("data.bin", "x");
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.my" = provided } } }, .{}));
    try expectStatus(context, try context.run("app.my", &.{ "--filter", "test_dependency" }), 0);
    const warm = try context.run("app.my", &.{ "--filter", "test_dependency" });
    try verdict(warm.report, "app::test_dependency", "cached");
    try context.write("extra.my", "module extra\n\npublic def value() -> int:\n    return 4\n");
    const changed = try context.run("app.my", &.{ "--filter", "test_dependency" });
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try context.write("extra.my", "module extra\n\npublic def value() -> int:\n    return 3\n");
    try context.write("data.bin", "xx");
    try expectStatus(context, try context.run("app.my", &.{ "--filter", "test_dependency" }), 1);
}

// spec-case: NEW-CORE-S4-TEST-4
test "configuredCases require canonical discovered names and never ignore an expectation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("plain.my", "def test_value() -> bool:\n    return True\n");
    try context.write("plain.cases.json", "{\"test_value\":{\"expected\":false}}");
    const alias = try context.run("plain.my", &.{});
    try expectStatus(context, alias, 1);
    try std.testing.expect(std.mem.indexOf(u8, alias.stderr, "UnknownTestCase") != null);
    try context.write("plain.cases.json", "{\"plain::test_value\":{\"expected\":false}}");
    const canonical = try context.run("plain.my", &.{});
    try expectStatus(context, canonical, 1);
    try verdict(canonical.report, "plain::test_value", "failed");
}

// spec-case: NEW-CORE-S4-PROJECT-1
// spec-case: NEW-CORE-S4-TEST-3
test "embedded bytes and stricter project budgets invalidate unchanged test manifests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("asset.my", "module asset\n\ndef test_asset() -> bool:\n    return len(embed_bytes(\"data.bin\")) == 1\n");
    try context.write("data.bin", "x");
    try expectStatus(context, try context.run("asset.my", &.{}), 0);
    const cached = try context.run("asset.my", &.{});
    try verdict(cached.report, "asset::test_asset", "cached");
    try context.write("data.bin", "xx");
    const changed = try context.run("asset.my", &.{});
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "asset::test_asset", "failed");
    try context.write("data.bin", "x");
    try expectStatus(context, try context.run("asset.my", &.{}), 0);
    try context.write("mylang.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":16}}");
    const bounded = try context.run("asset.my", &.{});
    try expectStatus(context, bounded, 1);
    try std.testing.expect(std.mem.indexOf(u8, bounded.stderr, "E_PROJECT_BYTES") != null);
}

// spec-case: NEW-CORE-S4-TEST-1
test "native test step and wall bounds are honored while force bypasses reuse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("loop.my", "module loop\n\ndef test_loop() -> bool:\n    total = 0\n    for i in range(100):\n        total = total + i\n    return total == 4950\n");
    try context.write("mylang.json", "{\"version\":1,\"limits\":{\"test\":{\"max_steps\":2}}}");
    try expectStatus(context, try context.run("loop.my", &.{}), 1);
    try expectStatus(context, try context.run("loop.my", &.{ "--max-steps", "100000" }), 0);
    const limited = try context.run("loop.my", &.{ "--max-steps", "2" });
    try expectStatus(context, limited, 1);
    try verdict(limited.report, "loop::test_loop", "failed");
    try context.write("loop.my", "module loop\n\ndef test_loop() -> bool:\n    while True:\n        pass\n    return True\n");
    try expectStatus(context, try context.run("loop.my", &.{ "--max-steps", "0", "--timeout-ms", "50" }), 1);
}

// spec: NEW-CORE-S4-STEPS-1
test "the default step budget charges one step per executed block, like the old core's dispatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("long.my", "module long\n\ndef test_long() -> bool:\n    values: list[int] = []\n    for i in range(200000):\n        values.append(i * 3 + 1)\n    return len(values) == 200000\n");
    try expectStatus(context, try context.run("long.my", &.{}), 0);
    const limited = try context.run("long.my", &.{ "--max-steps", "1000" });
    try expectStatus(context, limited, 1);
    try verdict(limited.report, "long::test_long", "failed");
}

/// The reason a named test's verdict gives, or an error when the report has no such test.
fn reasonOf(value: std.json.Value, name: []const u8) ![]const u8 {
    for (v.array(v.get(value, "tests"))) |item| {
        if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return v.text(v.get(item, "reason"));
    }
    return error.MissingTestVerdict;
}

/// Run `mylang-core test` on `source` under a 1 MiB native stack limit, which a
/// recursion 40,000 calls deep overflows unless the runtime maps the trial's stack.
fn runSmallStack(context: Context, source: []const u8, extra: []const u8) !Outcome {
    const path = try std.fs.path.join(context.arena, &.{ context.root, source });
    const cache = try std.fs.path.join(context.arena, &.{ context.root, "cache" });
    const command = try std.fmt.allocPrint(context.arena, "ulimit -s 1024 && exec \"$0\" test \"$1\" --json --cache-dir \"$2\" --max-steps 0 {s}", .{extra});
    const result = try std.process.run(context.arena, std.testing.io, .{ .argv = &.{ "sh", "-c", command, tools.core_path, path, cache } });
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, context.arena, result.stdout, .{}) catch .null;
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .report = parsed, .stderr = result.stderr };
}

const deep_source = "module deep\n\ndef down(n: int) -> int:\n    if n == 0:\n        return 0\n    return 1 + down(n - 1)\n\n" ++
    "def test_deep() -> bool:\n    return down(40000) == 40000\n\ndef test_shallow() -> bool:\n    return down(10) == 10\n";

// spec: NEW-CORE-S4-FRAMES-1
test "a test's call depth is bounded by --max-frames, 1024 by default, on a stack mapped for the whole budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("deep.my", deep_source);
    // The default budget traps the deep test and leaves the shallow one alone.
    const default = try context.run("deep.my", &.{ "--max-steps", "0" });
    try expectStatus(context, default, 1);
    try verdict(default.report, "deep::test_shallow", "passed");
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(default.report, "deep::test_deep"), "error[R_FRAME_LIMIT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(default.report, "deep::test_deep"), "raise it with --max-frames=N") != null);
    // 40,002 frames (the test and 40,001 calls of `down`) run on 1.2 GiB of mapped stack, not the 1 MiB native one.
    try expectStatus(context, try runSmallStack(context, "deep.my", "--max-frames 40002 --max-memory 2G"), 0);
    try expectStatus(context, try runSmallStack(context, "deep.my", "--max-frames=40002 --max-memory=2G --release"), 0);
    const short = try runSmallStack(context, "deep.my", "--max-frames 40001 --max-memory 2G");
    try expectStatus(context, short, 1);
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(short.report, "deep::test_deep"), "error[R_FRAME_LIMIT]") != null);
    // A budget whose stack the byte ceiling cannot back is refused before anything is built.
    const refused = try context.run("deep.my", &.{ "--max-frames", "40002" });
    try expectStatus(context, refused, 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "raise --max-memory to at least 2G") != null);
    try expectStatus(context, try context.run("deep.my", &.{ "--max-frames", "0" }), 2);
    // The project's `limits.test` supplies both ceilings; a flag still wins.
    try context.write("mylang.json", "{\"version\":1,\"limits\":{\"test\":{\"max_steps\":4000000000,\"max_frames\":40002,\"max_memory\":\"2G\"}}}");
    try expectStatus(context, try context.run("deep.my", &.{}), 0);
    try expectStatus(context, try context.run("deep.my", &.{ "--max-frames", "100" }), 1);
}

// spec: NEW-CORE-S4-MEMORY-1
test "a test's managed heap is bounded by --max-memory and a runaway allocation traps R_MEMORY_BUDGET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const source = "module grow\n\ndef fill(rounds: int) -> int:\n    values: list[int] = []\n    for r in range(rounds):\n        values.append(r)\n    return len(values)\n\n" ++
        "def test_runaway() -> bool:\n    return fill(100000000) > 0\n\ndef test_modest() -> bool:\n    return fill(1000000) == 1000000\n\n" ++
        "def test_words() -> bool:\n    words: list[str] = []\n    for i in range(200000):\n        words.append(str(i))\n    return len(words) == 200000\n";
    try context.write("grow.my", source);
    const bounded = try context.run("grow.my", &.{ "--max-steps", "0", "--max-memory", "64M" });
    try expectStatus(context, bounded, 1);
    try verdict(bounded.report, "grow::test_modest", "passed");
    try verdict(bounded.report, "grow::test_words", "passed");
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(bounded.report, "grow::test_runaway"), "error[R_MEMORY_BUDGET]") != null);
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(bounded.report, "grow::test_runaway"), "memory budget exhausted; raise it with --max-memory=SIZE") != null);
    // The ceiling is part of the receipt key: a lower one runs the passing tests again.
    const lower = try context.run("grow.my", &.{ "--max-steps", "0", "--max-memory=4M", "--filter", "words" });
    try expectStatus(context, lower, 1);
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(lower.report, "grow::test_words"), "R_MEMORY_BUDGET") != null);
    try expectStatus(context, try context.run("grow.my", &.{ "--max-memory", "12X" }), 2);
}

// spec-case: NEW-CORE-S4-TEST-2
test "directory assertion detects an omitted test verdict" {
    try std.testing.expectError(error.MissingTestVerdict, verdict(.null, "missing", "passed"));
}

// spec-case: NEW-CORE-S4-PROJECT-1
// spec-case: NEW-CORE-S4-TEST-3
test "warm project tests revalidate import policy and required generated interfaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const source = "module app\nimport dep\n\npublic def test_dependency() -> bool:\n    return dep.value() == 3\n";
    try context.write("app.my", source);
    try context.write("dep.my", dependency_three);
    try expectStatus(context, try context.run("app.my", &.{}), 0);
    try context.write("mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try context.write("policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    const denied = try context.run("app.my", &.{});
    // A denied import policy exits 3, as the old CLI's policy gate does (NEW-CORE-S5-POLICY-1).
    try expectStatus(context, denied, 3);
    try std.testing.expect(std.mem.indexOf(u8, denied.stderr, "deny") != null);
    try context.write("policy.json", "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}");
    try expectStatus(context, try context.run("app.my", &.{}), 0);
    try context.write("mylang.json", "{\"version\":1,\"interface_files\":true}");
    const missing = try context.run("app.my", &.{});
    try expectStatus(context, missing, 1);
    try std.testing.expect(std.mem.indexOf(u8, missing.stderr, "E_INTERFACE_FILE_STALE") != null);
    try context.writeInterfaces("app.my");
    try expectStatus(context, try context.run("app.my", &.{}), 0);
    try context.write("dep.api", "damaged interface\n");
    const stale = try context.run("app.my", &.{});
    try expectStatus(context, stale, 1);
    try std.testing.expect(std.mem.indexOf(u8, stale.stderr, "E_INTERFACE_FILE_STALE") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
test "providers preserve exported record layouts behind unchanged function signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", "module app\nimport dep\n\npublic def test_answer() -> bool:\n    return dep.answer()\n");
    const old = "module dep\n\npublic record Cell:\n    value: int\n\npublic def answer() -> bool:\n    return Cell(value=1).value == 1\n";
    const changed = "module dep\n\npublic record Cell:\n    value: bool\n\npublic def answer() -> bool:\n    return Cell(value=True).value\n";
    try context.write("dep.my", old);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.my" = old } } }, .{}));
    try expectStatus(context, try context.run("app.my", &.{}), 0);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.my" = changed } } }, .{}));
    // NATIVE-TEST-5: the changed declaration is refused before any body is checked.
    const refused = try context.run("app.my", &.{});
    try expectStatus(context, refused, 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "IncompatibleProvider") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
test "a provider may drop an import while its module keeps the same exports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", "module app\nimport dep\n\npublic def test_answer() -> bool:\n    return dep.answer() == 3\n");
    try context.write("dep.my", "module dep\nimport math\n\npublic def answer() -> int:\n    return math.clamp(9, 0, 3)\n");
    const stub = "module dep\n\npublic def answer() -> int:\n    return 3\n";
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.my" = stub } } }, .{}));
    const accepted = try context.run("app.my", &.{});
    try expectStatus(context, accepted, 0);
    try verdict(accepted.report, "app::test_answer", "passed");
}

// spec-case: NEW-CORE-S4-TEST-4
test "providers preserve private parameter layouts of marked property tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", "module app\nimport dep\n\npublic def test_answer() -> bool:\n    return dep.answer()\n");
    const old = "module dep\n\nrecord Cell:\n    value: int\n\n@test\ndef property(x: Cell) -> bool:\n    return x.value == x.value\n\npublic def answer() -> bool:\n    return True\n";
    const changed = "module dep\n\nrecord Cell:\n    value: bool\n\n@test\ndef property(x: Cell) -> bool:\n    return x.value == x.value\n\npublic def answer() -> bool:\n    return True\n";
    try context.write("dep.my", old);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"dep::property" = .{ .providers = .{ .@"dep.my" = old } } }, .{}));
    try expectStatus(context, try context.run("app.my", &.{ "--filter", "dep::property" }), 0);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"dep::property" = .{ .providers = .{ .@"dep.my" = changed } } }, .{}));
    const refused = try context.run("app.my", &.{ "--filter", "dep::property" });
    try expectStatus(context, refused, 1);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "ProviderSignatureChanged") != null);
}

// spec-case: NEW-CORE-S4-PROJECT-1
test "nested standalone test entries use the configured project import root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("mylang.json", "{\"version\":1}");
    try context.write("dep.my", dependency_three);
    try context.write("tests/suite_test.my", "module tests.suite_test\nimport dep\n\npublic def test_dependency() -> bool:\n    return dep.value() == 3\n");
    const result = try context.run("tests/suite_test.my", &.{});
    try expectStatus(context, result, 0);
    try verdict(result.report, "tests.suite_test::test_dependency", "passed");
}

// spec-case: NEW-CORE-S4-PROJECT-1
test "copied migrated propagation project retains all nine passing tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    for (0..10) |index| {
        const name = if (index == 0) "propagation.my" else try std.fmt.allocPrint(a, "propagation_case_{d}.my", .{index});
        const source = try std.fs.path.join(a, &.{ tools.fixtures, "projects", "propagation", name });
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source, a, .limited(1 << 20));
        try context.write(name, bytes);
    }
    const result = try context.run("propagation.my", &.{});
    try expectStatus(context, result, 0);
    try std.testing.expectEqual(@as(u64, 9), v.number(v.get(result.report, "passed")));
}

// spec-case: NEW-CORE-S4-TEST-2
test "reserved embedded module names cannot account for an untested disk source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.my", "module app\nimport strings\n\npublic def test_ok() -> bool:\n    return True\n\ndef main() -> int:\n    return 0\n");
    try context.write("strings.my", "module strings\n\ndef test_hidden() -> bool:\n    return False\n");
    const result = try context.run(".", &.{});
    try expectStatus(context, result, 1);
    try std.testing.expect(v.number(v.get(result.report, "failed")) != 0);
}

// spec-case: NEW-CORE-S4-TEST-4
// spec-case: NEW-CORE-S4-TEST-3
test "runSelected and expectedResult malformed typed cases fail individually and never become cached successes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const fixtures = [_]InvalidCase{
        .{ .name = "answer", .body = "public def test_answer() -> bool:\n    return True\n", .settings = "{\"arguments\":{\"unused\":\"x\"}}" },
        .{ .name = "answer", .body = "public def test_answer() -> bool:\n    return True\n", .settings = "{\"expected\":\"true\"}" },
        .{ .name = "zero", .body = "public def test_zero() -> int:\n    return 0\n", .settings = "{\"expected\":\"18446744073709551616\"}" },
        .{ .name = "zero", .body = "public def test_zero() -> int:\n    return 0\n", .settings = "{\"expected\":\"00\"}" },
        .{ .name = "text", .body = "public def test_text() -> str:\n    return \"\"\n", .settings = "{\"expected\":7}" },
        .{ .name = "list", .body = "public def test_list() -> list[int]:\n    return []\n", .settings = "{\"expected\":null}" },
        .{ .name = "dict", .body = "public def test_dict() -> dict[int, int]:\n    return {1: 2}\n", .settings = "{\"expected\":[[\"1\"]]}" },
        .{ .name = "argument", .body = "public def test_argument(x: u8) -> bool:\n    return x == 0\n", .settings = "{\"arguments\":{\"x\":\"256\"}}" },
        .{ .name = "argument", .body = "public def test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"00\"}}" },
        .{ .name = "argument", .body = "public def test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"+0\"}}" },
        .{ .name = "argument", .body = "public def test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"-0\"}}" },
        .{ .name = "argument", .body = "public def test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"1_0\"}}" },
    };
    for (fixtures) |fixture| {
        const source = try std.fmt.allocPrint(a, "module app\n\n{s}\npublic def test_z_survivor() -> bool:\n    return True\n", .{fixture.body});
        const name = try std.fmt.allocPrint(a, "app::test_{s}", .{fixture.name});
        try context.write("app.my", source);
        try context.write("app.cases.json", try std.fmt.allocPrint(a, "{{\"{s}\":{s}}}", .{ name, fixture.settings }));
        const cold = try context.run("app.my", &.{});
        try expectStatus(context, cold, 1);
        try verdict(cold.report, name, "failed");
        try verdict(cold.report, "app::test_z_survivor", "passed");
        const warm = try context.run("app.my", &.{});
        try expectStatus(context, warm, 1);
        try verdict(warm.report, name, "failed");
        try verdict(warm.report, "app::test_z_survivor", "cached");
    }
}

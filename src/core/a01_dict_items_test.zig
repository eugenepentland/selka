//! Dictionary item destructuring borrows each projection through its iteration.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const source =
    \\func first_key(values: dict[str, str[]]) -> str:
    \\    for key, value in values.items():
    \\        return key.copy()
    \\    return "empty"
    \\func first_value(values: dict[str, str[]]) -> str[]:
    \\    for key, value in values.items():
    \\        return value.copy()
    \\    return []
    \\func main(out: Stream) -> int:
    \\    mut values = {"key-" + str(1): ["value-" + str(1)], "key-" + str(2): ["value-" + str(2)]}
    \\    mut keys: str[] = []
    \\    mut rows: str[][] = []
    \\    for key, value in values.items():
    \\        keys.append(key.copy())
    \\        rows.append(value.copy())
    \\    const early_key = first_key(values)
    \\    const early_value = first_value(values)
    \\    const lengths = {key.copy(): len(value[0]) for key, value in values.items()}
    \\    mut score = 0
    \\    for _, value in values.items():
    \\        score += len(value[0])
    \\    for key, _ in values.items():
    \\        score += len(key)
    \\    for _, _ in values.items():
    \\        score += 1
    \\    const entries = list(values.items())
    \\    for key, value in entries:
    \\        score += len(key) + len(value)
    \\    values.clear()
    \\    for key, value in values.items():
    \\        score += 1000 + len(key) + len(value)
    \\    assert keys == ["key-1", "key-2"]
    \\    assert rows[0][0] == "value-1" and rows[1][0] == "value-2"
    \\    assert early_key == "key-1" and early_value == ["value-1"]
    \\    assert lengths["key-1"] == 7 and lengths["key-2"] == 7
    \\    mut rebound = {"old-" + str(1): ["before-" + str(1)], "old-" + str(2): ["before-" + str(2)]}
    \\    mut old_keys: str[] = []
    \\    mut old_values: str[][] = []
    \\    for key, value in rebound.items():
    \\        rebound = {"new": ["replacement"]}
    \\        old_keys.append(key.copy())
    \\        old_values.append(value.copy())
    \\    rebound.clear()
    \\    assert old_keys == ["old-1", "old-2"]
    \\    assert old_values[0] == ["before-1"] and old_values[1] == ["before-2"]
    \\    assert score == 38
    \\    out.print("passed", score)
    \\    return 0
;

fn checked(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "dict-items.my", text);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |item| report("{s}: {s}\n", .{ item.code, item.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "dict-items-negative.my", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
        return;
    };
    var failure: contract.Failure = .{};
    contract.checkMode(arena.allocator(), unit.program.?, &failure, true) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        if (!std.mem.eql(u8, code, failure.code)) report("dict items refusal: {s}: {s}\n", .{ failure.code, failure.message });
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    report("dict items unexpectedly admitted:\n{s}\n", .{text});
    return error.TestExpectedError;
}

// spec-case: DICT-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC dictionary item destructuring rejects borrowed escape and invalidation" {
    try refuses(std.testing.allocator,
        \\func escape(values: dict[str, int]) -> str:
        \\    for key, value in values.items():
        \\        return key
        \\    return "empty"
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func escape(values: dict[str, str[]]) -> str[]:
        \\    for key, value in values.items():
        \\        return value
        \\    return []
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    const prefix = "func main() -> int:\n    mut values = {\"key\": [\"value\"]}\n    mut kept: str[][] = []\n    for key, value in values.items():\n";
    inline for (.{
        "        kept.append(value)\n",
        "        values.clear()\n",
        "        values[key.copy()] = []\n",
    }) |body| try refuses(std.testing.allocator, prefix ++ body ++ "    return len(kept)\n", "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator, prefix ++ "        value.append(\"changed\")\n    return len(kept)\n", "E_IMMUTABLE");
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

fn inspect(a: std.mem.Allocator, binary: []const u8, llvm_path: []const u8) !void {
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_COUNTERS", path);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("dict items run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("passed 38\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)), .{});
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks", "live_bytes_at_exit" }) |name|
        try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", name }));
    for ([_][]const u8{ "retain", "release", "unique_test" }) |name|
        try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "kinds", name, "count" }));
    try std.testing.expect(field(counts, &.{ "totals", "allocs" }) > 0);
    try std.testing.expect(field(counts, &.{ "kinds", "release_unique", "count" }) > 0);
    const llvm = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm_path, a, .limited(16 << 20));
    try std.testing.expect(zero.emittedClean(llvm));
    const symbols = try std.process.run(a, std.testing.io, .{ .argv = &.{ "nm", binary } });
    try std.testing.expect(symbols.term == .exited and symbols.term.exited == 0);
    for ([_][]const u8{ "myl_core_retain", "myl_core_release", "myl_core_share", "count_retain", "count_release", "count_is_unique" }) |legacy|
        try std.testing.expect(std.mem.indexOf(u8, symbols.stdout, legacy) == null);
}

// spec-case: DICT-VIEWS-1
// spec-case: D1-LIVE-PLACE
// spec-case: NEW-CORE-IR-3
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC dictionary item destructuring copies independent fields with exact cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: contract.Failure = .{};
    contract.checkMode(a, try checked(a, source), &failure, true) catch |err| {
        report("dict items ownership: {s}: {s} at {d}\n", .{ failure.code, failure.message, failure.span.start });
        return err;
    };
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "items.my", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "items.my" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/items-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", root, "--counters", "--experimental-zero-rc", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("dict items build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path);
    }
}

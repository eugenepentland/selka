//! Record replacements: managed keys across ownership and optimization modes.
const std = @import("std");
const language = @import("selka");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;
const options = @import("core_test_options");
const t = std.testing;
const release_flag = @import("e2e_test.zig").optimize_flag;

fn qualifiedRecords(source: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "record Inner:\n    text: str\n    data: bytes\nrecord Key:\n    inner: Inner\n");
    for (0..40) |i| try text.print(a, "    f{d}: u64\n", .{i});
    try text.appendSlice(a, "record Item:\n    position: int\n    rank: int\nfunc key(item: Item) -> Key:\n    return Key(inner=Inner(text=\"allocated-\" + str(item.rank % 2), data=b\"key\"), ");
    for (0..40) |i| {
        if (i != 0) try text.appendSlice(a, ", ");
        try text.print(a, "f{d}=", .{i});
        try text.appendSlice(a, if (i == 39) "u64(item.rank)" else "0u64");
    }
    try text.appendSlice(a,
        \\)
        \\func main() -> int:
        \\    mut items = [Item(position=0, rank=3), Item(position=1, rank=1), Item(position=2, rank=3)]
        \\    const forward = sorted(items, key=key)
        \\    sort(mut items, key=key, reverse=True)
        \\    assert forward[0].position == 1 and forward[1].position == 0 and forward[2].position == 2
        \\    assert items[0].position == 0 and items[1].position == 2 and items[2].position == 1
        \\    return 0
        \\
    );
    try directory.dir.writeFile(t.io, .{ .sub_path = "records.selka", .data = source orelse text.items });
    const input = try std.fs.path.join(a, &.{ root, "records.selka" });
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const modes = [_][]const []const u8{ &.{release_flag}, &.{ release_flag, "--verify-facts" }, &.{"--optimize-debug"} };
    for (modes, 0..) |mode, i| {
        const binary = try std.fmt.allocPrint(a, "{s}/record-{d}", .{ root, i });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, t.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("record key build: {s}{s}\n", .{ built.stdout, built.stderr });
        try t.expect(built.term == .exited and built.term.exited == 0);
        const ran = try std.process.run(a, t.io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("record key run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try t.expect(ran.term == .exited and ran.term.exited == 0);
        try t.expectEqualStrings("", ran.stderr);
    }
}

// spec-case: RECORD-KEY-1
test "A01 record keys preserve nested wide managed fields under core runtime modes" {
    try qualifiedRecords(null);
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "tuple-unpack-negative.selka", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        for (unit.diagnostics.items) |item| if (std.mem.eql(u8, code, item.code)) return;
        const found = unit.diagnostics.items[0].code;
        if (std.mem.startsWith(u8, code, "E_SINGLE_OWNER_") and std.mem.eql(u8, found, "E_TUPLE_REMOVED")) return;
        try std.testing.expectEqualStrings(code, found);
        return;
    };
    var failure: contract.Failure = .{};
    contract.check(arena.allocator(), unit.program.?, &failure) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        if (!std.mem.eql(u8, code, failure.code)) report("tuple unpack refusal: {s}: {s}\n", .{ failure.code, failure.message });
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    report("tuple unpack unexpectedly admitted:\n{s}\n", .{text});
    return error.TestExpectedError;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC complete tuple staging preserves move and Result obligations" {
    try refuses(std.testing.allocator,
        \\func borrowed(pair: tuple[str, str]) -> int:
        \\    const left, right = pair
        \\    return strings.char_count(left) + strings.char_count(right)
        \\func main() -> int:
        \\    return borrowed(("a" + str(1), "b" + str(2)))
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const whole = ("a" + str(1), "b" + str(2))
        \\    const left, right = whole
        \\    const duplicate = copy(whole)
        \\    _ = duplicate
        \\    return strings.char_count(left) + strings.char_count(right)
    , "E_SINGLE_OWNER_MOVED");
    // A field moved out of a record that is never read again is accepted (C3, field_borrow_test.zig).
    try refuses(std.testing.allocator,
        \\func results() -> tuple[Result[str, str], Result[str, str]]:
        \\    return Ok("a" + str(1)), Err("b" + str(2))
        \\func main() -> int:
        \\    const first, _ = results()
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try refuses(std.testing.allocator,
        \\func results() -> tuple[Result[str, str], Result[str, str]]:
        \\    return Ok("a" + str(1)), Err("b" + str(2))
        \\func main() -> int:
        \\    mut first, second = results()
        \\    first, second = results()
        \\    _ = first
        \\    _ = second
        \\    return 0
    , "E_RESULT_OVERWRITE");
    try refuses(std.testing.allocator,
        \\func results() -> tuple[Result[str, str], Result[str, str]]:
        \\    return Ok("a" + str(1)), Err("b" + str(2))
        \\func main() -> int:
        \\    const whole = results()
        \\    const first, second = copy(whole)
        \\    _ = first
        \\    _ = second
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try refuses(std.testing.allocator,
        \\func results() -> tuple[Result[str, str], Result[str, str]]:
        \\    return Ok("a" + str(1)), Err("b" + str(2))
        \\func main() -> int:
        \\    mut first: Result[str, str] = Ok("old")
        \\    _ = first
        \\    first, first = results()
        \\    _ = first
        \\    return 0
    , "E_RESULT_OVERWRITE");
}

const lifecycle_source =
    \\import strings
    \\import filesystem
    \\
    \\record Payload:
    \\    text: str
    \\    children: str[]
    \\
    \\func make_payload() -> Payload:
    \\    return Payload(text="owned-" + str(3), children=["child-" + str(4)])
    \\
    \\func early() -> str:
    \\    const payload = make_payload()
    \\    return copy(payload.text)
    \\
    \\func fallible() -> Payload fails str:
    \\    return make_payload()
    \\
    \\func fail_payload() -> Payload fails str:
    \\    const payload = make_payload()
    \\    fail copy(payload.text)
    \\
    \\func chosen_provider() -> Filesystem:
    \\    const ignored = filesystem.memory()
    \\    _ = ignored
    \\    return filesystem.memory()
    \\
    \\func main(out: Stream) -> int:
    \\    const original = make_payload()
    \\    mut duplicate = copy(original)
    \\    append(mut duplicate.children, "new")
    \\    assert original.children == ["child-4"]
    \\    assert duplicate.children == ["child-4", "new"]
    \\    assert early() == "owned-3"
    \\    match fallible():
    \\        case Ok(payload):
    \\            assert payload.text == "owned-3" and len(payload.children) == 1
    \\        case Err(_):
    \\            assert False
    \\    match fail_payload():
    \\        case Ok(_):
    \\            assert False
    \\        case Err(message):
    \\            assert message == "owned-3"
    \\    const ignored: Result[Payload, str] = Err("discarded")
    \\    _ = ignored
    \\    mut first = filesystem.memory()
    \\    mut second = chosen_provider()
    \\    _ = first.write_text("first", "first")
    \\    _ = second.write_text("second", "second")
    \\    const saved = own first
    \\    first = own second
    \\    second = own saved
    \\    assert first.exists("second") and second.exists("first")
    \\    mut checksum = 0
    \\    with first.open("second", "r") as one:
    \\        with second.open("first", "r") as two:
    \\            const first_text = one.read()
    \\            const second_text = two.read()
    \\            assert first_text == "second" and second_text == "first"
    \\            checksum = strings.char_count(first_text) * 10 + strings.char_count(second_text)
    \\    print(out, "record-lifecycle", checksum)
    \\    return 0
    \\
;

fn counterField(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

fn inspectLifecycle(a: std.mem.Allocator, binary: []const u8, llvm_path: []const u8) !void {
    const counter_path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_COUNTERS", counter_path);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, t.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("record lifecycle run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try t.expect(ran.term == .exited and ran.term.exited == 0);
    try t.expectEqualStrings("record-lifecycle 65\n", ran.stdout);
    try t.expectEqualStrings("", ran.stderr);
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.Io.Dir.cwd().readFileAlloc(t.io, counter_path, a, .limited(16 << 20)), .{});
    try t.expectEqual(@as(i64, 0), counterField(counts, &.{ "totals", "live_bytes_at_exit" }));
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
        try t.expect(counts.object.get("totals").?.object.get(name) == null);
    for ([_][]const u8{ "retain", "release", "release_unique", "unique_test" }) |name|
        try t.expect(counts.object.get("kinds").?.object.get(name) == null);
    try t.expect(counterField(counts, &.{ "totals", "allocs" }) > 0);
    try t.expect(counterField(counts, &.{ "totals", "frees" }) > 0);
    const llvm = try std.Io.Dir.cwd().readFileAlloc(t.io, llvm_path, a, .limited(16 << 20));
    try t.expect(zero.emittedClean(llvm));
    const symbols = try std.process.run(a, t.io, .{ .argv = &.{ "nm", binary } });
    try t.expect(symbols.term == .exited and symbols.term.exited == 0);
    for ([_][]const u8{ "myl_core_retain", "myl_core_release", "myl_core_share", "count_retain", "count_release", "count_is_unique" }) |legacy|
        try t.expect(std.mem.indexOf(u8, symbols.stdout, legacy) == null);
}

fn qualifiedLifecycle() !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    try directory.dir.writeFile(t.io, .{ .sub_path = "record_lifecycle.selka", .data = lifecycle_source });
    const input = try std.fs.path.join(a, &.{ root, "record_lifecycle.selka" });
    const modes = [_][]const []const u8{ &.{release_flag}, &.{ release_flag, "--verify-facts" }, &.{"--optimize-debug"}, &.{ release_flag, "--no-facts" } };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/record-lifecycle-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()), "--counters", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, t.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("record lifecycle build: {s}{s}\n", .{ built.stdout, built.stderr });
        try t.expect(built.term == .exited and built.term.exited == 0);
        try inspectLifecycle(a, binary, llvm_path);
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: TUPLE-REMOVED-1
test "A01 record counterparts preserve managed Result and provider lifecycle without RC" {
    try qualifiedLifecycle();
}

// spec-case: RECORD-KEY-1
test "A01 nested single numeric record key preserves stable sorting and hash equality" {
    // The nested record forces the descriptor path: one i64 leaf, offset 0, stride 8.
    try qualifiedRecords(
        \\import sets
        \\
        \\record Inner:
        \\    value: int
        \\record Key:
        \\    inner: Inner
        \\record Item:
        \\    position: int
        \\    rank: int
        \\func key(item: Item) -> Key:
        \\    return Key(inner=Inner(value=item.rank))
        \\func main() -> int:
        \\    mut items = [Item(position=0, rank=2), Item(position=1, rank=-3), Item(position=2, rank=2), Item(position=3, rank=-3)]
        \\    const forward = sorted(items, key=key)
        \\    assert forward[0].position == 1 and forward[1].position == 3 and forward[2].position == 0 and forward[3].position == 2
        \\    assert items[0].position == 0 and items[3].position == 3
        \\    sort(mut items, key=key, reverse=True)
        \\    assert items[0].position == 0 and items[1].position == 2 and items[2].position == 1 and items[3].position == 3
        \\    mut counts: dict[Key, int] = {}
        \\    counts[Key(inner=Inner(value=2))] = 7
        \\    counts[Key(inner=Inner(value=-3))] = 11
        \\    counts[Key(inner=Inner(value=2))] = 13
        \\    assert len(counts) == 2 and counts[Key(inner=Inner(value=2))] == 13 and counts[Key(inner=Inner(value=-3))] == 11
        \\    mut keys: set[Key] = set()
        \\    sets.add(mut keys, Key(inner=Inner(value=2)))
        \\    sets.add(mut keys, Key(inner=Inner(value=-3)))
        \\    sets.add(mut keys, Key(inner=Inner(value=2)))
        \\    assert len(keys) == 2 and Key(inner=Inner(value=-3)) in keys and Key(inner=Inner(value=5)) not in keys
        \\    return 0
    );
}

//! Complete tuple staging consumes owned fields before destination effects.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const source =
    \\import filesystem
    \\
    \\func evaluated_pair(mut events: int[]) -> tuple[str, str]:
    \\    events.append(1)
    \\    return "first-" + str(1), "second-" + str(2)
    \\func index(mut events: int[], value: int) -> int:
    \\    events.append(value)
    \\    return 0
    \\func owned() -> tuple[str, str[]]:
    \\    return "owned-" + str(3), ["child-" + str(4)]
    \\func clone(value: tuple[str, str[]]) -> tuple[str, str[]]:
    \\    const text, children = value.copy()
    \\    return text, children
    \\func optional(value: tuple[int, str]?) -> str:
    \\    if value is None:
    \\        return "missing"
    \\    const number, text = value.copy()
    \\    assert number == 7
    \\    return text
    \\func early() -> str:
    \\    const text, _ = owned()
    \\    return text
    \\func fallible() -> Result[str, str]:
    \\    const text, _ = owned()
    \\    return Err(text)
    \\func managed_test(out: Stream) -> int:
    \\    mut first = "first-" + str(1)
    \\    mut second = "second-" + str(2)
    \\    first, second = second, first
    \\    assert first == "second-2" and second == "first-1"
    \\    mut words = ["a" + str(1), "b" + str(2)]
    \\    words[0], words[1] = words[1].copy(), words[0].copy()
    \\    assert words == ["b2", "a1"]
    \\    mut events: int[] = []
    \\    words[index(mut events, 2)], words[index(mut events, 3)] = evaluated_pair(mut events)
    \\    assert events == [1, 2, 3] and words == ["second-2", "a1"]
    \\    const original = owned()
    \\    const duplicate = clone(original)
    \\    const original_text, original_rows = original
    \\    const copied_text, copied_rows = duplicate
    \\    assert original_text == copied_text and original_rows == copied_rows
    \\    const nested = (owned(), "sibling-" + str(5))
    \\    const child, sibling = nested
    \\    const child_text, child_rows = child
    \\    assert sibling == "sibling-5" and child_text == "owned-3" and child_rows == ["child-4"]
    \\    for i in range(16):
    \\        const _, rows = owned()
    \\        assert rows == ["child-4"]
    \\    assert early() == "owned-3"
    \\    match fallible():
    \\        case Ok(value):
    \\            assert False
    \\        case Err(error):
    \\            assert error == "owned-3"
    \\    assert optional(Some((7, "option-" + str(6)))) == "option-6"
    \\    assert optional(None) == "missing"
    \\    mut a = 3
    \\    mut b = 4
    \\    a, b = b, a
    \\    assert a == 4 and b == 3
    \\    out.print("tuple-unpack", len(events))
    \\    return 0
    \\
    \\func results() -> tuple[Result[str, str], Result[str, str]]:
    \\    return Ok("value-" + str(1)), Err("error-" + str(2))
    \\func consume(value: Result[str, str]) -> int:
    \\    match value:
    \\        case Ok(text):
    \\            return len(text)
    \\        case Err(text):
    \\            return len(text)
    \\func result_test(out: Stream) -> int:
    \\    const first, ignored = results()
    \\    _ = ignored
    \\    assert consume(first) == 7
    \\    const left, _ = results()
    \\    assert consume(left) == 7
    \\    const whole = results()
    \\    const duplicate = whole.copy()
    \\    const one, two = whole
    \\    const three, four = duplicate
    \\    assert consume(one) + consume(two) + consume(three) + consume(four) == 28
    \\    const _, _ = results()
    \\    out.print("tuple-results", 28)
    \\    return 0
    \\
    \\func providers() -> tuple[Filesystem, Filesystem]:
    \\    return (filesystem.memory(), filesystem.memory())
    \\
    \\func provider_test() -> int:
    \\    const pair = providers()
    \\    const moved = pair
    \\    const first_fs, second_fs = moved
    \\    _ = first_fs.write_text("note", "first")
    \\    _ = second_fs.write_text("note", "second")
    \\    mut checksum = 0
    \\    with first_fs.open("note", "r") as first:
    \\        with second_fs.open("note", "r") as second:
    \\            const first_text = first.read()
    \\            const second_text = second.read()
    \\            assert first_text == "first" and second_text == "second"
    \\            checksum = len(first_text) * 10 + len(second_text)
    \\    assert first_fs.exists("note") and second_fs.exists("note")
    \\    return checksum
    \\
    \\func chosen_provider() -> Filesystem:
    \\    const chosen, _ = providers()
    \\    return chosen
    \\func provider_extra() -> int:
    \\    const _, _ = providers()
    \\    const chosen = chosen_provider()
    \\    _ = chosen.write_text("chosen", "kept")
    \\    assert chosen.exists("chosen")
    \\    mut first, second = providers()
    \\    _ = first.write_text("first", "first")
    \\    _ = second.write_text("second", "second")
    \\    first, second = second, first
    \\    assert first.exists("second") and second.exists("first")
    \\    with first.open("second", "r") as one:
    \\        with second.open("first", "r") as two:
    \\            assert one.read() == "second" and two.read() == "first"
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    assert managed_test(out) == 0
    \\    assert result_test(out) == 0
    \\    const provider_checksum = provider_test()
    \\    assert provider_checksum == 56
    \\    assert provider_extra() == 0
    \\    out.print("tuple-providers", provider_checksum)
    \\    return 0
;

fn checked(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "tuple-unpack.my", text);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |item| report("{s}: {s}\n", .{ item.code, item.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "tuple-unpack-negative.my", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
        return;
    };
    var failure: contract.Failure = .{};
    contract.checkMode(arena.allocator(), unit.program.?, &failure, true) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        if (!std.mem.eql(u8, code, failure.code)) report("tuple unpack refusal: {s}: {s}\n", .{ failure.code, failure.message });
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    report("tuple unpack unexpectedly admitted:\n{s}\n", .{text});
    return error.TestExpectedError;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 complete tuple staging records exact fresh field slots and explicit ignores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try checked(arena.allocator(),
        \\func main() -> int:
        \\    const text, _ = ("value-" + str(1), ["ignored-" + str(2)])
        \\    return len(text)
    );
    const locals = program.functions[0].scope.locals;
    var markers: usize = 0;
    for (program.statements) |statement| {
        if (statement.data != .initialize) continue;
        const store = statement.data.initialize;
        const fields = store.unpack orelse continue;
        markers += 1;
        try std.testing.expect(!store.element);
        try std.testing.expectEqual(@as(usize, 2), fields.len);
        try std.testing.expect(fields[0] != null and fields[1] == null);
        try std.testing.expect(fields[0].? != store.slot);
        const original = locals[@backingInt(store.slot)];
        const field_local = locals[@backingInt(fields[0].?)];
        try std.testing.expect(original.usage.temporary and field_local.usage.temporary);
        try std.testing.expect(!original.ownership.transfer_available);
        try std.testing.expectEqual(original.ty, program.nodes[@backingInt(store.value)].ty);
    }
    try std.testing.expectEqual(@as(usize, 1), markers);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC complete tuple staging preserves move and Result obligations" {
    try refuses(std.testing.allocator,
        \\func borrowed(pair: tuple[str, str]) -> int:
        \\    const left, right = pair
        \\    return len(left) + len(right)
        \\func main() -> int:
        \\    return borrowed(("a" + str(1), "b" + str(2)))
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const whole = ("a" + str(1), "b" + str(2))
        \\    const left, right = whole
        \\    const duplicate = whole.copy()
        \\    _ = duplicate
        \\    return len(left) + len(right)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    left: str
        \\    right: str
        \\func main() -> int:
        \\    const whole = Cell(left="a" + str(1), right="b" + str(2))
        \\    const left = whole.left
        \\    return len(left)
    , "E_SINGLE_OWNER_BORROW");
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
        \\    const first, second = whole.copy()
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

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

fn inspect(a: std.mem.Allocator, binary: []const u8, llvm_path: []const u8, expected: []const u8) !void {
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_COUNTERS", path);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("tuple unpack run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(expected, ran.stdout);
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

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC complete tuple staging transfers managed and provider fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "tuple.my", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "tuple.my" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/tuple-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", root, "--counters", "--experimental-zero-rc", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("tuple unpack build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path, "tuple-unpack 3\ntuple-results 28\ntuple-providers 56\n");
    }
}

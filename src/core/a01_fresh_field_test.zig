//! Fresh whole results stay alive through immediate borrowed field receivers.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const source =
    \\record Cell:
    \\    name: str
    \\    rows: str[][]
    \\record Envelope:
    \\    cell: Cell
    \\    spare: str[]
    \\func fresh(mut calls: int, value: int) -> Cell:
    \\    calls += 1
    \\    return Cell(name="value-" + str(value), rows=[["row-" + str(value)], ["ignored-" + str(value)]])
    \\func envelope(mut calls: int, value: int) -> Envelope:
    \\    return Envelope(cell=fresh(mut calls, value), spare=["spare-" + str(value)])
    \\func maker(value: int) -> Cell:
    \\    return Cell(name="callback-" + str(value), rows=[["discarded"]])
    \\func early(mut calls: int) -> str:
    \\    return fresh(mut calls, 7).name.copy()
    \\func fail(mut calls: int) -> Result[int, str]:
    \\    const rows = fresh(mut calls, 8).rows.copy()
    \\    if len(rows) == 2:
    \\        return Err(rows[0][0].copy())
    \\    return Ok(0)
    \\func main(out: Stream) -> int:
    \\    mut calls = 0
    \\    mut names: str[] = []
    \\    for i in range(16):
    \\        names.append(fresh(mut calls, i).name.copy())
    \\    const nested = envelope(mut calls, 19).cell.name.copy()
    \\    mut rows = fresh(mut calls, 20).rows.copy()
    \\    const returned = early(mut calls)
    \\    match fail(mut calls):
    \\        case Ok(value):
    \\            assert False
    \\        case Err(error):
    \\            assert error == "row-8"
    \\    const function = maker
    \\    const invoked = function(25).name.copy()
    \\    assert fresh(mut calls, 26).name.startswith("value-")
    \\    const indexed = fresh(mut calls, 27).rows[0].copy()
    \\    assert len(fresh(mut calls, 28).rows) == 2
    \\    assert calls == 23
    \\    assert names[0] == "value-0" and names[15] == "value-15"
    \\    assert nested == "value-19" and returned == "value-7"
    \\    assert invoked == "callback-25" and indexed == ["row-27"]
    \\    rows[0] = ["changed"]
    \\    assert rows[1] == ["ignored-20"]
    \\    out.print("fresh-field", calls)
    \\    return 0
;

fn checked(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "fresh-field.my", text);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |item| report("{s}: {s}\n", .{ item.code, item.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "fresh-field-negative.my", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
        return;
    };
    var failure: contract.Failure = .{};
    contract.checkMode(arena.allocator(), unit.program.?, &failure, true) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        if (!std.mem.eql(u8, code, failure.code)) report("fresh field refusal: {s}: {s}\n", .{ failure.code, failure.message });
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    report("fresh field unexpectedly admitted:\n{s}\n", .{text});
    return error.TestExpectedError;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "A01 zero RC fresh field receivers retain partial move and escape refusals" {
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    const text = make().name
        \\    return len(text)
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    const view = make().name.borrow(0, 3)
        \\    return len(view)
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    make().rows.append(["changed"])
        \\    return 0
    , "E_ASSIGNMENT_TARGET");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    const row = make().rows[0]
        \\    return len(row)
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    mut whole = make()
        \\    const view = whole.name.borrow(0, 3)
        \\    whole = make()
        \\    return len(view)
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\record Pending:
        \\    name: str
        \\    outcome: Result[int, str]
        \\func pending() -> Pending:
        \\    return Pending(name="kept", outcome=Ok(1))
        \\func main() -> int:
        \\    const text = pending().name.copy()
        \\    return len(text)
    , "E_RESULT_OPERATION");
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
    if (ran.term != .exited or ran.term.exited != 0) report("fresh field run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("fresh-field 23\n", ran.stdout);
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
test "A01 zero RC fresh field receivers retain whole owner until independent copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: contract.Failure = .{};
    contract.checkMode(a, try checked(a, source), &failure, true) catch |err| {
        report("fresh field ownership: {s}: {s} at {d}\n", .{ failure.code, failure.message, failure.span.start });
        return err;
    };
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fresh.my", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "fresh.my" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/fresh-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", input, "-o", binary, "--cache-dir", root, "--counters", "--experimental-zero-rc", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("fresh field build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path);
    }
}

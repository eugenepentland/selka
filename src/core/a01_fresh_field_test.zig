//! Fresh whole results stay alive through immediate borrowed field receivers.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const support = @import("test_support.zig");
const language = @import("selka");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const source =
    \\import strings
    \\
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
    \\    return copy(fresh(mut calls, 7).name)
    \\func fail(mut calls: int) -> int fails str:
    \\    const rows = copy(fresh(mut calls, 8).rows)
    \\    if len(rows) == 2:
    \\        fail copy(rows[0][0])
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    mut calls = 0
    \\    mut names: str[] = []
    \\    for i in range(16):
    \\        append(mut names, copy(fresh(mut calls, i).name))
    \\    const nested = copy(envelope(mut calls, 19).cell.name)
    \\    mut rows = copy(fresh(mut calls, 20).rows)
    \\    const returned = early(mut calls)
    \\    match fail(mut calls):
    \\        case Ok(value):
    \\            assert False
    \\        case Err(error):
    \\            assert error == "row-8"
    \\    const function = maker
    \\    const invoked = copy(function(25).name)
    \\    assert strings.starts_with(fresh(mut calls, 26).name, "value-")
    \\    const indexed = copy(fresh(mut calls, 27).rows[0])
    \\    assert len(fresh(mut calls, 28).rows) == 2
    \\    assert calls == 23
    \\    assert names[0] == "value-0" and names[15] == "value-15"
    \\    assert nested == "value-19" and returned == "value-7"
    \\    assert invoked == "callback-25" and indexed == ["row-27"]
    \\    rows[0] = ["changed"]
    \\    assert rows[1] == ["ignored-20"]
    \\    print(out, "fresh-field", calls)
    \\    return 0
;

/// The entry module `source` serves to the project loader; the standard
/// modules come from the normal loader.
const ProjectEntry = struct {
    text: []const u8,

    /// Supply `main.selka`; any other path belongs to the standard loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
    }
};

fn checked(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    var entry: ProjectEntry = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    program.init(a, .{ .context = &entry, .read = ProjectEntry.read }) catch |err| {
        for (program.compilation.diagnostics.items.items) |issue| report("{s}: {s}\n", .{ issue.code, issue.message });
        return err;
    };
    return program.compilation.program.?;
}

fn refuses(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "fresh-field-negative.selka", text);
    unit.check() catch |err| {
        try std.testing.expectEqual(error.SourceError, err);
        try std.testing.expectEqualStrings(code, unit.diagnostics.items[0].code);
        return;
    };
    var failure: contract.Failure = .{};
    contract.check(arena.allocator(), unit.program.?, &failure) catch |err| {
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
        \\    return strings.char_count(text)
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\record Cell:
        \\    name: str
        \\    rows: str[][]
        \\func make() -> Cell:
        \\    return Cell(name="value-" + str(1), rows=[["ignored-" + str(1)]])
        \\func main() -> int:
        \\    append(mut make().rows, ["changed"])
        \\    return 0
    , "E_VALUE_TEMPORARY_WRITE");
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
        \\    const view = whole.name[0:3]
        \\    whole = make()
        \\    return len(view)
    , "E_SLICE_ESCAPES");
    try refuses(std.testing.allocator,
        \\record Pending:
        \\    name: str
        \\    outcome: Result[int, str]
        \\func pending() -> Pending:
        \\    return Pending(name="kept", outcome=Ok(1))
        \\func main() -> int:
        \\    const text = copy(pending().name)
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
    try environment.put("SELKA_COUNTERS", path);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("fresh field run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("fresh-field 23\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)), .{});
    try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", "live_bytes_at_exit" }));
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
        try std.testing.expect(counts.object.get("totals").?.object.get(name) == null);
    for ([_][]const u8{ "retain", "release", "release_unique", "unique_test" }) |name|
        try std.testing.expect(counts.object.get("kinds").?.object.get(name) == null);
    try std.testing.expect(field(counts, &.{ "totals", "allocs" }) > 0);
    try std.testing.expect(field(counts, &.{ "totals", "frees" }) > 0);
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
    contract.check(a, try checked(a, source), &failure) catch |err| {
        report("fresh field ownership: {s}: {s} at {d}\n", .{ failure.code, failure.message, failure.span.start });
        return err;
    };
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fresh.selka", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "fresh.selka" });
    const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } };
    for (modes, 0..) |flags, index| {
        try support.requireReleaseArgs(flags);
        const binary = try std.fmt.allocPrint(a, "{s}/fresh-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()), "--counters", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("fresh field build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path);
    }
}

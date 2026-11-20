//! Lending shared data to tasks costs no copy (E1c, the counter proof). One record of a large list is lent to every task of a
//! group and to every item of a `parallel.map`. Each program is built with `--counters` and run as its own process; the
//! runtime's counts show that no list is copied, at any record size or task count, and that the allocations do not grow with
//! the number of tasks.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;

/// The guest program: a record holding `nets` integers is lent to `tasks` group tasks and to `items` map items.
/// `main` prints the item count and the last mapped value, which is `items - 1 + nets`.
fn program(a: std.mem.Allocator, nets: usize, items: usize, tasks: usize) ![]u8 {
    return std.fmt.allocPrint(a,
        \\import parallel
        \\
        \\record Design:
        \\    name: str
        \\    nets: int[]
        \\
        \\func weigh(value: int, design: Design) -> int:
        \\    return value + len(design.nets)
        \\
        \\func touch(design: Design):
        \\    _ = len(design.nets)
        \\
        \\func main(out: Stream) -> int:
        \\    mut nets: int[] = []
        \\    for i in range({d}):
        \\        append(mut nets, i)
        \\    const design = Design(name="top", nets=own nets)
        \\    mut items: int[] = []
        \\    for i in range({d}):
        \\        append(mut items, i)
        \\    const mapped = parallel.map(items, weigh, design)
        \\    with parallel.group() as g:
        \\        for i in range({d}):
        \\            g.submit(touch, design)
        \\    print(out, len(mapped), mapped[{d}])
        \\    return 0
        \\
    , .{ nets, items, tasks, items - 1 });
}

/// The counts of one run: the parsed `selka-counters-v1` document, with the program's stdout checked.
fn measure(a: std.mem.Allocator, directory: []const u8, name: []const u8, source: []const u8, expected: []const u8) !std.json.Value {
    const input = try std.fmt.allocPrint(a, "{s}/{s}.selka", .{ directory, name });
    const binary = try std.fmt.allocPrint(a, "{s}/{s}", .{ directory, name });
    const counts_path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    const dir = try std.Io.Dir.cwd().openDir(std.testing.io, directory, .{});
    try dir.writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.selka", .{name}), .data = source });
    try support.requireRelease();
    const built = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()), "--counters", "--release" } });
    if (built.term != .exited or built.term.exited != 0) report("parallel lend build {s}: {s}{s}\n", .{ name, built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = std.process.Environ.Map.init(a);
    try environment.put("SELKA_COUNTERS", counts_path);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("parallel lend run {s}: {s}{s}\n", .{ name, ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(expected, ran.stdout);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, counts_path, a, .limited(16 << 20));
    return std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
}

/// One counter's total, or -1 when the document has none.
fn total(counts: std.json.Value, name: []const u8) i64 {
    const totals = counts.object.get("totals") orelse return -1;
    const value = totals.object.get(name) orelse return -1;
    return value.integer;
}

test "E1c counter proof: a record lent to every task and item is never copied, and allocation does not grow with the tasks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    // Small record, one task; large record, one task; large record, 256 tasks. Each maps 8 items.
    const small = try measure(a, root, "small", try program(a, 100, 8, 1), "8 107\n");
    const large = try measure(a, root, "large", try program(a, 100000, 8, 1), "8 100007\n");
    const many = try measure(a, root, "many", try program(a, 100000, 8, 256), "8 100007\n");
    report("E1c counter proof: list_copies small/large/many = {d}/{d}/{d}; list_copy_bytes = {d}/{d}/{d}\n", .{
        total(small, "list_copies"),     total(large, "list_copies"),     total(many, "list_copies"),
        total(small, "list_copy_bytes"), total(large, "list_copy_bytes"), total(many, "list_copy_bytes"),
    });
    report("E1c counter proof: peak_live_bytes small/large/many = {d}/{d}/{d}; reallocs large/many = {d}/{d}\n", .{
        total(small, "peak_live_bytes"), total(large, "peak_live_bytes"), total(many, "peak_live_bytes"),
        total(large, "reallocs"),        total(many, "reallocs"),
    });
    // The record is never copied: the copy counts do not depend on its size or on the task count.
    try std.testing.expectEqual(total(small, "list_copy_bytes"), total(large, "list_copy_bytes"));
    try std.testing.expectEqual(total(large, "list_copy_bytes"), total(many, "list_copy_bytes"));
    try std.testing.expectEqual(total(large, "list_copies"), total(many, "list_copies"));
    try std.testing.expectEqual(@as(i64, 0), total(many, "dict_copies"));
    try std.testing.expectEqual(@as(i64, 0), total(many, "buffer_copies"));
    // Peak live bytes count the record once: the 255 tasks added to the 256-task run hold small environments, not 255 copies
    // of the 800 KB record, which would add about 204 MB (the bound is 1 MB). Large list growth is counted by the realloc
    // counters, not by `allocs`, so it is the peak and the realloc growth that show the record's size.
    try std.testing.expect(total(many, "peak_live_bytes") - total(large, "peak_live_bytes") < 1 << 20);
    try std.testing.expect(total(large, "peak_live_bytes") > 1 << 20);
    try std.testing.expect(total(many, "allocs") - total(large, "allocs") < 255 * 8);
    try std.testing.expectEqual(@as(i64, 0), total(many, "live_bytes_at_exit"));
}

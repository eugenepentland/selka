//! The ownership certificates (docs/design/ownership-certificates.md, package C1): the exporter writes the
//! states, slots and calls of a program's final IR, the same bytes every run.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const ops = @import("ownership_ops.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const certificate = @import("ownership_certificate.zig");
const exporter = @import("ownership_export.zig");
const build = @import("build.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");

/// The certificate text of every function of `source` after the release passes.
fn certificateOf(arena: std.mem.Allocator, source: []const u8, counts: *exporter.Counts) ![]u8 {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena, source, &refusal);
    var sink: certificate.Sink = .{};
    var stopped: own.Refusal = .{ .certificates = &sink };
    _ = try (passes.Reporting{ .arena = arena, .backing = arena, .module = &module, .refusal = &stopped }).runWithScratch(.trusted);
    var problems: std.ArrayList(exporter.Problem) = .empty;
    const indices = try arena.alloc(u32, module.functions.items.len);
    for (indices, 0..) |*slot, i| slot.* = @intCast(i);
    const text = try exporter.render(arena, .{ .module = &module, .sink = &sink, .problems = &problems }, indices, counts);
    try std.testing.expectEqual(@as(usize, 0), problems.items.len);
    return text;
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const grow_source =
    \\record Row:
    \\    items: int[]
    \\    name: str
    \\
    \\func grow(own r: Row) -> Row:
    \\    mut rows = own r
    \\    append(mut rows.items, 3)
    \\    return rows
    \\
    \\func main(out: Stream) -> int:
    \\    const r = Row(items=[1, 2], name="x")
    \\    const g = grow(own r)
    \\    print(out, len(g.items), g.name)
    \\    return 0
;

test "a record field update takes the field and stores it back, and an emptied record is never consumed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(), grow_source, &counts);
    try std.testing.expect(std.mem.startsWith(u8, text, "ownership-certificate-v2\nclass param Parameter\n"));
    try std.testing.expect(contains(text, "function grow result owned from - unchecked -\nparam 0 %0 owned\n"));
    try std.testing.expect(contains(text, " record_get Project reads %0 consumes - state owned parents - slot f0\n"));
    try std.testing.expect(contains(text, " record_set Update reads - consumes %0,"));
    try std.testing.expect(contains(text, " state emptied parents - slot f0 slots f0,f1\n"));
    try std.testing.expectEqual(@as(u32, 0), counts.problems);
}

test "the certificate text is the same on every run" {
    var first_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer first_arena.deinit();
    var second_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer second_arena.deinit();
    var counts: exporter.Counts = .{};
    const first = try certificateOf(first_arena.allocator(), grow_source, &counts);
    const second = try certificateOf(second_arena.allocator(), grow_source, &counts);
    try std.testing.expectEqualStrings(first, second);
}

test "the class table lists every operation once, in enum order, with the canonical class spellings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(), grow_source, &counts);
    try std.testing.expect(contains(text, "class text_frame TextFrame\n"));
    try std.testing.expect(contains(text, "class phi Join\n"));
    try std.testing.expect(contains(text, "class unreachable Trap\n"));
    try std.testing.expect(contains(text, "class copy Forward\n"));
    var lines: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| lines += @intFromBool(std.mem.startsWith(u8, line, "class "));
    try std.testing.expectEqual(ops.count(), lines);
}

test "a borrowed parameter is borrowed from the caller and a stack list is not owned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(),
        \\func width(text: str) -> int:
        \\    return len(text)
        \\
        \\func main(out: Stream) -> int:
        \\    mut values: int[] = []
        \\    append(mut values, 1)
        \\    append(mut values, 2)
        \\    print(out, len(values), width("abc"))
        \\    return 0
    , &counts);
    try std.testing.expect(contains(text, "function width result scalar from - unchecked -\nparam 0 %0 borrowed\n"));
    try std.testing.expect(contains(text, "inst %0 param Parameter reads - consumes - state borrowed parents ^0\n"));
    try std.testing.expect(contains(text, " list_new Fresh reads"));
    try std.testing.expect(contains(text, " state stack parents -\n"));
}

test "a function that uses a task group is checked, and its lend names the group it is lent to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(),
        \\import parallel
        \\
        \\func weigh(values: int[]) -> int:
        \\    return len(values)
        \\
        \\func go() -> int:
        \\    const rows = [1, 2, 3]
        \\    mut answer = 0
        \\    with parallel.group() as g:
        \\        const a = g.submit(weigh, rows)
        \\        answer = a.result()
        \\    return answer
        \\
        \\func main() -> int:
        \\    return go()
    , &counts);
    try std.testing.expect(!contains(text, " unchecked task-group\n"));
    try std.testing.expect(contains(text, "function main::go result scalar from - unchecked -\n"));
    try std.testing.expect(contains(text, " box_make Construct reads "));
    try std.testing.expect(contains(text, " parents - lent %"));
    try std.testing.expectEqual(@as(u32, 0), counts.unchecked_task_group);
    try std.testing.expectEqual(@as(u32, 0), counts.problems);
}

fn here(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn internalCount(module: *const ir.Module) usize {
    var found: usize = 0;
    for (module.functions.items) |function| found += @intFromBool(function.signature.linkage == .internal);
    return found;
}

test "the units a build emits hold every internal function once, and a release build is one program unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, grow_source, &refusal);
    const context: u8 = 0;
    const options: emit_llvm.Options = .{ .locator = .{ .context = &context, .locate = here }, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} } };
    const whole = try emit_units.members(a, &module, options, true);
    try std.testing.expectEqual(@as(usize, 1), whole.len);
    try std.testing.expectEqualStrings("program", whole[0].name);
    try std.testing.expectEqual(internalCount(&module), whole[0].functions.len);
    const split = try emit_units.members(a, &module, options, false);
    var held: usize = 0;
    for (split) |member| held += member.functions.len;
    try std.testing.expectEqual(internalCount(&module), held);
    try std.testing.expect(std.mem.startsWith(u8, split[0].name, "module-"));
}

/// The problems `render` reports for the function `name` of `grow_source` when its table is `table` (or absent).
fn problemsWith(arena: std.mem.Allocator, name: []const u8, table: ?certificate.Capture) ![]const exporter.Problem {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena, grow_source, &refusal);
    var sink: certificate.Sink = .{};
    var stopped: own.Refusal = .{ .certificates = &sink };
    _ = try (passes.Reporting{ .arena = arena, .backing = arena, .module = &module, .refusal = &stopped }).runWithScratch(.trusted);
    var index: u32 = 0;
    for (module.functions.items, 0..) |function, i| {
        if (std.mem.eql(u8, function.name, name)) index = @intCast(i);
    }
    if (table) |replacement| try sink.put(arena, index, replacement) else _ = sink.functions.remove(index);
    var problems: std.ArrayList(exporter.Problem) = .empty;
    var counts: exporter.Counts = .{};
    _ = try exporter.render(arena, .{ .module = &module, .sink = &sink, .problems = &problems }, &.{index}, &counts);
    return problems.items;
}

test "a function the pass kept no table for is reported, not written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const problems = try problemsWith(arena.allocator(), "main", null);
    try std.testing.expectEqual(@as(usize, 1), problems.len);
    try std.testing.expectEqualStrings("main", problems[0].function);
    try std.testing.expect(contains(problems[0].reason, "did not run"));
}

/// The table of `main` with its first `list_new` marked as a stack list that promotion never saw.
fn mislabelled(arena: std.mem.Allocator) !certificate.Capture {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena, grow_source, &refusal);
    var sink: certificate.Sink = .{};
    var stopped: own.Refusal = .{ .certificates = &sink };
    _ = try (passes.Reporting{ .arena = arena, .backing = arena, .module = &module, .refusal = &stopped }).runWithScratch(.trusted);
    for (module.functions.items, 0..) |function, i| {
        if (!std.mem.eql(u8, function.name, "main")) continue;
        const table = sink.get(@intCast(i)).?;
        const states = try arena.dupe(certificate.State, table.states);
        for (function.insts.items, 0..) |inst, k| {
            if (inst.op == .list_new) states[k] = .stack;
        }
        const lists = try arena.alloc([]const ir.Ref, states.len);
        for (lists, 0..) |*list, k| list.* = table.parents(k);
        return certificate.capture(arena, states, lists);
    }
    unreachable;
}

test "a stack state that contradicts the list's own marker is reported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const problems = try problemsWith(arena.allocator(), "main", try mislabelled(arena.allocator()));
    try std.testing.expectEqual(@as(usize, 1), problems.len);
    try std.testing.expect(contains(problems[0].reason, "a stack list that promotion did not mark"));
}

test "a take whose result type cannot hold a view is exported with noloans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(),
        \\record Pair:
        \\    first: int[]
        \\    second: int[]
        \\
        \\func first(own pair: Pair) -> int[]:
        \\    return own pair.first
        \\
        \\func main(out: Stream) -> int:
        \\    const pair = Pair(first=[1], second=[2])
        \\    print(out, len(first(own pair)))
        \\    return 0
    , &counts);
    try std.testing.expect(contains(text, " record_take Take reads - consumes "));
    try std.testing.expect(contains(text, " state owned parents - noloans\n"));
}

test "an owner that a trap path leaves live is listed on the edge into the trap block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(),
        \\func checked(n: int) -> int:
        \\    mut rows: int[][] = []
        \\    for i in range(n):
        \\        mut row: int[] = [i]
        \\        assert len(row) == 1
        \\        append(mut rows, own row)
        \\    return len(rows)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, checked(3))
        \\    return 0
    , &counts);
    try std.testing.expect(contains(text, "\nabandon b"));
    try std.testing.expect(contains(text, "term unreachable\n"));
    try std.testing.expectEqual(@as(u32, 0), counts.problems);
}

test "a call names its callee in the function's table, as the callee's own certificate states it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var counts: exporter.Counts = .{};
    const text = try certificateOf(arena.allocator(),
        \\func depth(n: int) -> int:
        \\    if n <= 0:
        \\        return 0
        \\    return 1 + depth(n - 1)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, depth(3))
        \\    return 0
    , &counts);
    try std.testing.expect(contains(text, "function depth result scalar from - unchecked -\nparam 0 %0 scalar\ncallee 0 depth program read-scalar scalar -\nblock b- preds -\n"));
    try std.testing.expect(contains(text, "function main result scalar from - unchecked -\nparam 0 %0 scalar\ncallee 0 depth program read-scalar scalar -\n"));
    try std.testing.expect(contains(text, " from - callee 0\n"));
    try std.testing.expectEqual(@as(u32, 0), counts.problems);
}

//! F6 formatting reads retain lenders for the renderer's actual evaluation span.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const report = std.debug.print;

fn checked(a: std.mem.Allocator, text: []const u8) !support.Checked {
    const unit = try support.checkSource(a, text);
    if (!unit.passed) for (unit.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    try std.testing.expect(unit.passed);
    return unit;
}

fn refused(a: std.mem.Allocator, text: []const u8) !void {
    const unit = try checked(a, text);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.rule == .M5 or failure.rule == .R2);
}

fn accepted(a: std.mem.Allocator, text: []const u8) !void {
    const unit = try checked(a, text);
    var failure: ownership.Failure = .{};
    ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        report("{s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
}

const declarations =
    // migrate-embedded: skip shared prefix for intentional ownership refusal witnesses
    \\func change(mut text: str) -> str:
    \\    text = "new" + str(1)
    \\    return "x"
    \\func pick(text: str) -> str from text:
    \\    return text
    \\func choose(first: str, second: str, flag: bool) -> str from first, second:
    \\    if flag:
    \\        return first
    \\    return second
    \\func my_take(own text: str) -> str:
    \\    return text
    \\func two(first: str, second: str) -> int:
    \\    return len(first) + len(second)
    \\
;

test "F6 f-string Core refuses all five immutable review probes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        // e7.selka: the review input remains unchanged.
        \\func g(mut t: str[]) -> str:
        \\    for i in range(300):
        \\        append(mut t, "grow" + str(i))
        \\    t = ["new" + str(1)]
        \\    return "x"
        \\func gi(mut t: str[]) -> int:
        \\    t = ["new" + str(1)]
        \\    return 0
        \\func two(a: str, b: str) -> int:
        \\    return len(a) + len(b)
        \\func main(out: Stream) -> int:
        \\    mut t = ["abc" + str(1), "def"]
        \\    const s = f"{t[0]}{g(mut t)}"
        \\    print(out, s)
        \\    return 0
        \\
        ,
        // e7b.selka: the review input remains unchanged.
        \\func g(mut t: str[]) -> str:
        \\    for i in range(300):
        \\        append(mut t, "grow" + str(i))
        \\    t = ["new" + str(1)]
        \\    return "x"
        \\func big() -> str:
        \\    mut s = ""
        \\    for i in range(2000):
        \\        s += "a"
        \\    return s
        \\func main(out: Stream) -> int:
        \\    mut t = [big(), "def"]
        \\    const s = f"{t[0]}{g(mut t)}"
        \\    print(out, len(s), s[0:3], t[0])
        \\    return 0
        \\
        ,
        // e7c.selka: the review input remains unchanged.
        \\record R:
        \\    name: str
        \\func h(mut r: R) -> str:
        \\    r = R(name="new" + str(1))
        \\    return "x"
        \\func big() -> str:
        \\    mut s = ""
        \\    for i in range(2000):
        \\        s += "a"
        \\    return s
        \\func main(out: Stream) -> int:
        \\    mut r = R(name=big())
        \\    const s = f"{r.name}{h(mut r)}"
        \\    print(out, len(s), r.name)
        \\    return 0
        \\
        ,
        // e7d.selka: the review input remains unchanged.
        \\func h(mut r: str) -> str:
        \\    r = "new" + str(1)
        \\    return "x"
        \\func big() -> str:
        \\    mut s = ""
        \\    for i in range(2000):
        \\        s += "a"
        \\    return s
        \\func main(out: Stream) -> int:
        \\    mut r = big()
        \\    const s = f"{r}{h(mut r)}"
        \\    print(out, len(s), r)
        \\    return 0
        \\
        ,
        // e7e.selka: the review input remains unchanged.
        \\func h(mut r: str) -> str:
        \\    r = "new" + str(1)
        \\    return "x"
        \\func big() -> str:
        \\    mut s = ""
        \\    for i in range(2000):
        \\        s += "a"
        \\    return s
        \\func main(out: Stream) -> int:
        \\    mut r = big()
        \\    print(out, f"{r[0:5]}-{h(mut r)}", r)
        \\    return 0
        \\
        ,
    };
    for (cases) |text| try refused(arena.allocator(), text);
}

test "F6 f-string Core retains direct print holes through later args separators and terminators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", change(mut text))
        \\    return 0
        \\
        ,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", sep=change(mut text))
        \\    return 0
        \\
        ,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", end=change(mut text))
        \\    return 0
        \\
        ,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", f"{change(mut text)}!")
        \\    return 0
        \\
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{text:>8}-{change(mut text)}"
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{pick(text)}-{change(mut text)}"
        \\    return len(rendered)
        ,
        \\func go(flag: bool) -> int:
        \\    mut first = "old" + str(1)
        \\    mut second = "other" + str(2)
        \\    const rendered = f"{choose(first, second, flag)}-{change(mut second)}"
        \\    return len(rendered)
        \\func main() -> int:
        \\    return go(False)
        ,
        \\func main() -> int:
        \\    const text = "old" + str(1)
        \\    const rendered = f"{text}-{my_take(own text)}"
        \\    return len(rendered)
        ,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    const alias = text
        \\    print(out, f"{alias}-", change(mut text))
        \\    return 0
        \\
        ,
    };
    for (cases) |body| try refused(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ declarations, body }));
}

test "F6 f-string Core accepts materialized scalar copied and mutation-first values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{text}-"
        \\    print(out, rendered, change(mut text))
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    return two(f"{text}-", change(mut text))
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{len(text)}-{change(mut text)}"
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{text[0]}-{change(mut text)}"
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{copy(text)}-{change(mut text)}"
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{change(mut text)}-{text}"
        \\    return len(rendered)
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{text}-{text}"
        \\    _ = change(mut text)
        \\    return len(rendered)
        ,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, 1, sep=f"{text}-", end=change(mut text))
        \\    return 0
        \\
        ,
        \\func main() -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{f'{text}-'}{change(mut text)}"
        \\    return len(rendered)
        ,
    };
    for (cases) |body| try accepted(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ declarations, body }));
}

fn errorReportProgram(a: std.mem.Allocator, program: language.typed.Program) !language.typed.Program {
    const nodes = try a.dupe(language.typed.Node, program.nodes);
    var changed = false;
    for (nodes) |*node| {
        if (node.data != .print) continue;
        node.data.print.sink = .error_report;
        changed = true;
    }
    try std.testing.expect(changed);
    var result = program;
    result.nodes = nodes;
    return result;
}

test "F6 f-string Core error-report prints materialize before later arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try checked(a, try std.mem.concat(a, u8, &.{
        declarations,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", change(mut text))
        \\    return 0
    }));
    const program = try errorReportProgram(a, unit.program.?);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, program, unit.src.?, &failure);
    try std.testing.expectEqual(@as(usize, 0), failure.code.len);
}

test "F6 f-string Core error-report print options still delay direct holes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try checked(a, try std.mem.concat(a, u8, &.{
        declarations,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    print(out, f"{text}-", change(mut text), sep="|")
        \\    return 0
    }));
    const program = try errorReportProgram(a, unit.program.?);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, program, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(failure.rule == .M5);
}

/// One ownership check under the failing allocator `a`, of a program built afresh in an arena of its own over `backing`.
fn allocationFailure(backing: std.mem.Allocator, a: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const unit = try checked(arena.allocator(), text);
    var failure: ownership.Failure = .{};
    try ownership.check(a, unit.program.?, &failure);
}

/// Fail the k-th allocation of the check for k = 0, 1, ... until a run needs fewer than k+1: every failure must come back as
/// `OutOfMemory` with nothing leaked (`backing`, the testing allocator, reports a leak when the test ends). The standard
/// `checkAllAllocationFailures` counts the allocations of one run and insists every other run makes as many; this check makes
/// 15 to 17 depending on the addresses it is given (a pointer-keyed table), so that count is no property of the check (F38).
fn expectEveryFailureIsOutOfMemory(backing: std.mem.Allocator, text: []const u8) !void {
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        try std.testing.expect(fail_index < 200);
        var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = fail_index });
        if (allocationFailure(backing, failing.allocator(), text)) |_| {
            // The run finished without reaching the failing allocation: there are no more to fail.
            try std.testing.expect(!failing.has_induced_failure);
            return;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
        }
    }
}

test "F6 f-string Core allocation failures preserve formatting loan ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.mem.concat(a, u8, &.{
        declarations,
        \\func main(out: Stream) -> int:
        \\    mut text = "old" + str(1)
        \\    const rendered = f"{text}-"
        \\    print(out, rendered, change(mut text))
        \\    return len(rendered)
    });
    try expectEveryFailureIsOutOfMemory(std.testing.allocator, text);
}

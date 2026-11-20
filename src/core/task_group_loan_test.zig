//! K1 task loans follow the actual owner until the submitting group closes.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const report = std.debug.print;

const declarations =
    // migrate-embedded: skip shared prefix for intentionally refused Core ownership fixtures
    \\import parallel
    \\record Row:
    \\    g: int[]
    \\    other: int[]
    \\func total(values: int[]) -> int:
    \\    return len(values)
    \\func consume(own values: int[]) -> int:
    \\    return len(values)
    \\func pick(values: int[]) -> int[] from values:
    \\    return values
    \\func main() -> int:
    \\    return 0
    \\
;

fn checked(a: std.mem.Allocator, body: []const u8) !support.Checked {
    const source = try std.mem.concat(a, u8, &.{ declarations, body });
    const unit = try support.checkSource(a, source);
    if (!unit.passed) for (unit.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    try std.testing.expect(unit.passed);
    return unit;
}

fn refused(a: std.mem.Allocator, body: []const u8) !void {
    const unit = try checked(a, body);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_TASK_LOAN", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.K1, failure.rule.?);
}

fn accepted(a: std.mem.Allocator, body: []const u8) !void {
    const unit = try checked(a, body);
    var failure: ownership.Failure = .{};
    ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        report("{s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
}

test "F1 task group loans reject direct owner writes and moves even after result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, xs)
        \\        xs[0] = 9
        \\        return task.result()
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, xs)
        \\        const n = task.result()
        \\        append(mut xs, 9)
        \\        return n
        ,
        \\func go() -> int:
        \\    const xs = [1, 2]
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, xs)
        \\        const n = task.result()
        \\        return n + consume(own xs)
        ,
        \\func go() -> int:
        \\    mut r = Row(g=[1, 2], other=[3])
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, r.g)
        \\        const n = task.result()
        \\        r = Row(g=[9], other=[])
        \\        return n
        ,
        \\func go() -> int:
        \\    mut table = {"k": [1, 2]}
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, table["k"])
        \\        const n = task.result()
        \\        table["k"] = [9]
        \\        return n
        ,
    };
    for (cases) |body| try refused(arena.allocator(), body);
}

test "F1 tasks own fresh loop arguments instead of lending their staging locals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try accepted(arena.allocator(),
        \\func go(values: int[]) -> int:
        \\    mut answer = 0
        \\    with parallel.group() as g:
        \\        for value in values:
        \\            const task = g.submit(total, [value])
        \\            answer += task.result()
        \\    return answer
    );
}

const Alias = struct { setup: []const u8, place: []const u8, mutation: []const u8 };

fn aliasCase(a: std.mem.Allocator, alias: Alias, inside: bool) ![]const u8 {
    const before = if (inside) "" else try std.fmt.allocPrint(a, "    const first = {s}\n", .{alias.place});
    const within = if (inside) try std.fmt.allocPrint(a, "        const first = {s}\n", .{alias.place}) else "";
    return std.fmt.allocPrint(
        a,
        "func go() -> int:\n{s}{s}    with parallel.group() as g:\n{s}" ++
            "        const second = first\n        const task = g.submit(total, second)\n" ++
            "        const n = task.result()\n        {s}\n        return n\n",
        .{ alias.setup, before, within, alias.mutation },
    );
}

fn aliasCases(a: std.mem.Allocator, alias: Alias) !void {
    try refused(a, try aliasCase(a, alias, false));
    try refused(a, try aliasCase(a, alias, true));
}

test "F1 task group loans follow inside and outside alias chains to place owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_]Alias{
        .{ .setup = "    mut xs = [1, 2]\n", .place = "xs", .mutation = "xs = [9]" },
        .{ .setup = "    const xs = [1, 2]\n", .place = "xs", .mutation = "_ = consume(own xs)" },
        .{ .setup = "    mut xs = [1, 2]\n", .place = "pick(xs)", .mutation = "append(mut xs, 9)" },
        .{ .setup = "    mut xs = [[1, 2]]\n", .place = "xs[0]", .mutation = "xs = [[9]]" },
        .{ .setup = "    mut r = Row(g=[1, 2], other=[3])\n", .place = "r.g", .mutation = "r = Row(g=[9], other=[])" },
        .{ .setup = "    mut table = {\"k\": [1, 2]}\n", .place = "table[\"k\"]", .mutation = "table = {\"k\": [9]}" },
    };
    for (cases) |alias| try aliasCases(arena.allocator(), alias);
}

test "F1 task group loans end at their own group and snapshots do not lend the source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    const alias = xs
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, alias)
        \\        n = task.result() + len(alias)
        \\    append(mut xs, 9)
        \\    return n + len(xs)
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut ys = [3]
        \\    with parallel.group() as outer:
        \\        const a = outer.submit(total, xs)
        \\        mut n = a.result()
        \\        with parallel.group() as inner:
        \\            const b = inner.submit(total, ys)
        \\            n += b.result()
        \\        append(mut ys, 9)
        \\        return n + len(xs) + len(ys)
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        const task = g.submit(total, copy(xs))
        \\        append(mut xs, 9)
        \\        return task.result()
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    for i in range(2):
        \\        append(mut xs, i)
        \\        with parallel.group() as g:
        \\            const task = g.submit(total, xs)
        \\            const n = task.result()
        \\            assert n > 0
        \\    return len(xs)
        ,
    };
    for (cases) |body| try accepted(arena.allocator(), body);
}

test "F1 task group loans survive inner groups including submissions to the outer group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as outer:
        \\        const a = outer.submit(total, xs)
        \\        mut n = a.result()
        \\        with parallel.group() as inner:
        \\            const b = inner.submit(total, [3])
        \\            n += b.result()
        \\        append(mut xs, 9)
        \\        return n
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as outer:
        \\        mut n = 0
        \\        with parallel.group() as inner:
        \\            const task = outer.submit(total, xs)
        \\            n = task.result()
        \\        append(mut xs, 9)
        \\        return n
        ,
    };
    for (cases) |body| try refused(arena.allocator(), body);
}

test "F1 task group loans merge continuing branches and match arms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go(flag: bool) -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        if flag:
        \\            const task = g.submit(total, xs)
        \\            n = task.result()
        \\        append(mut xs, 9)
        \\        return n
        ,
        \\func go(flag: int?) -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        match flag:
        \\            case Some(value):
        \\                const task = g.submit(total, xs)
        \\                n = task.result() + value
        \\            case None:
        \\                n = 0
        \\        append(mut xs, 9)
        \\        return n
        ,
    };
    for (cases) |body| try refused(arena.allocator(), body);
}

test "F1 task group loans do not cross exclusive or returning branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go(flag: bool) -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        if flag:
        \\            const task = g.submit(total, xs)
        \\            n = task.result()
        \\        else:
        \\            append(mut xs, 9)
        \\            n = len(xs)
        \\    return n
        ,
        \\func go(flag: bool) -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        if flag:
        \\            const task = g.submit(total, xs)
        \\            return task.result()
        \\        append(mut xs, 9)
        \\        return len(xs)
        ,
        \\func go(flag: int?) -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        match flag:
        \\            case Some(value):
        \\                const task = g.submit(total, xs)
        \\                n = task.result() + value
        \\            case None:
        \\                append(mut xs, 9)
        \\                n = len(xs)
        \\    return n
        ,
    };
    for (cases) |body| try accepted(arena.allocator(), body);
}

test "F1 returning loop task loans do not reach the zero iteration continuation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go(repeat: bool) -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        while repeat:
        \\            const task = g.submit(total, xs)
        \\            return task.result()
        \\        append(mut xs, 9)
        \\    return len(xs)
        ,
        \\func go(count: int) -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        for i in range(count):
        \\            const task = g.submit(total, xs)
        \\            return task.result() + i
        \\        append(mut xs, 9)
        \\    return len(xs)
        ,
        \\func go(repeat: bool, flag: bool) -> int:
        \\    mut xs = [1, 2]
        \\    with parallel.group() as g:
        \\        while repeat:
        \\            const task = g.submit(total, xs)
        \\            const n = task.result()
        \\            if flag:
        \\                return n
        \\            else:
        \\                return n + 1
        \\        append(mut xs, 9)
        \\    return len(xs)
        ,
    };
    for (cases) |body| try accepted(arena.allocator(), body);
}

test "F1 task group loans survive loops break continue and the next iteration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_][]const u8{
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        for i in range(2):
        \\            const task = g.submit(total, xs)
        \\            n += task.result() + i
        \\        append(mut xs, 9)
        \\        return n
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut n = 0
        \\    with parallel.group() as g:
        \\        while n < 2:
        \\            const task = g.submit(total, xs)
        \\            n = task.result()
        \\            break
        \\        append(mut xs, 9)
        \\        return n
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut i = 0
        \\    with parallel.group() as g:
        \\        while i < 2:
        \\            const task = g.submit(total, xs)
        \\            const n = task.result()
        \\            assert n > 0
        \\            i += 1
        \\            continue
        \\        append(mut xs, 9)
        \\        return i
        ,
        \\func go() -> int:
        \\    mut xs = [1, 2]
        \\    mut i = 0
        \\    with parallel.group() as g:
        \\        while i < 2:
        \\            if i > 0:
        \\                append(mut xs, 9)
        \\            const task = g.submit(total, xs)
        \\            const n = task.result()
        \\            assert n > 0
        \\            i += 1
        \\        return i
        ,
    };
    for (cases) |body| try refused(arena.allocator(), body);
}

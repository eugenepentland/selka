//! Field effects (CE2-A): the per-parameter read and write summaries (`effects.zig`),
//! per-field interference of memory homes, dead and sunk element stores, and element
//! stores narrowed to the fields that changed.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const effects = @import("effects.zig");
const support = @import("test_support.zig");

/// The index of the function named `name` (its Core name ends with it).
fn functionIndex(module: *const ir.Module, name: []const u8) !usize {
    for (module.functions.items, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return i;
    }
    return error.TestUnexpectedResult;
}

/// The paths of `set` spelled `a.b,c` (`*` for the whole value, `-` for none), sorted.
fn spell(arena: std.mem.Allocator, set: *const effects.Paths) ![]const u8 {
    if (set.whole) return "*";
    if (set.items.items.len == 0) return "-";
    var parts: std.ArrayList([]const u8) = .empty;
    for (set.items.items) |path| {
        var text: std.ArrayList(u8) = .empty;
        for (path.slice(), 0..) |step, i| {
            if (i != 0) try text.append(arena, '.');
            try text.print(arena, "{d}", .{step});
        }
        try parts.append(arena, text.items);
    }
    std.mem.sort([]const u8, parts.items, {}, struct {
        fn less(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.less);
    return std.mem.join(arena, ",", parts.items);
}

const summaries_source =
    \\record Inner:
    \\    a: int
    \\    b: list[int]
    \\
    \\
    \\record State:
    \\    ip: int
    \\    inner: Inner
    \\    code: list[int]
    \\    count: int
    \\
    \\
    \\def bump(s: mut State) -> int:
    \\    s.ip = s.ip + 1
    \\    return s.ip
    \\
    \\
    \\def read_code(s: mut State) -> int:
    \\    return s.code[bump(mut s)]
    \\
    \\
    \\def deep(s: mut State):
    \\    s.inner.a = 5
    \\
    \\
    \\def grow(s: mut State, x: int):
    \\    s.inner.b.append(x)
    \\
    \\
    \\def replace(s: mut State, t: State):
    \\    s = t
    \\
    \\
    \\def countdown(s: mut State, n: int):
    \\    if n > 0:
    \\        s.count = s.count + 1
    \\        countdown(mut s, n - 1)
    \\
    \\
    \\def ping(s: mut State, n: int):
    \\    if n > 0:
    \\        pong(mut s, n - 1)
    \\
    \\
    \\def pong(s: mut State, n: int):
    \\    s.ip = s.ip + 2
    \\    ping(mut s, n)
    \\
    \\
    \\def check(s: mut State) -> bool:
    \\    if s.count > 3:
    \\        s.count = 0
    \\        return False
    \\    s.ip = s.ip + 1
    \\    return True
    \\
    \\
    \\def relay(s: mut State) -> bool:
    \\    return check(mut s)
    \\
    \\
    \\def length(s: State) -> int:
    \\    return len(s.code)
    \\
    \\
    \\def through(s: State, f: def(State) -> int) -> int:
    \\    return f(s)
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    s = State(ip=0, inner=Inner(a=1, b=[]), code=[1, 2, 3], count=0)
    \\    t = s
    \\    out.print(read_code(mut s), length(s), through(s, length))
    \\    deep(mut s)
    \\    grow(mut s, 4)
    \\    replace(mut s, t)
    \\    countdown(mut s, 3)
    \\    ping(mut s, 4)
    \\    out.print(check(mut s), relay(mut s), s.ip)
    \\    return 0
    \\
;

// spec: NEW-CORE-CE2-EFFECTS-1
test "a function's effect summary names the fields each parameter may be read and written in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, summaries_source, &refusal);
    const s = try effects.analyze(a, &module);
    const Expect = struct { name: []const u8, param: usize, reads: []const u8, writes: []const u8 };
    // `State` is ip (0), inner (1: a 1.0, b 1.1), code (2), count (3).
    const cases = [_]Expect{
        .{ .name = "bump", .param = 0, .reads = "0", .writes = "0" },
        // Through the callee: its writes and reads, plus the list read here.
        .{ .name = "read_code", .param = 0, .reads = "0,2", .writes = "0" },
        // A nested field, and a list updated inside a nested record.
        .{ .name = "deep", .param = 0, .reads = "-", .writes = "1.0" },
        .{ .name = "grow", .param = 0, .reads = "-", .writes = "1.1" },
        // A new value: everything.
        .{ .name = "replace", .param = 0, .reads = "-", .writes = "*" },
        .{ .name = "replace", .param = 1, .reads = "*", .writes = "-" },
        // Recursion, and mutual recursion: the least fixed point.
        .{ .name = "countdown", .param = 0, .reads = "3", .writes = "3" },
        .{ .name = "ping", .param = 0, .reads = "0", .writes = "0" },
        .{ .name = "pong", .param = 0, .reads = "0", .writes = "0" },
        // Reading the length reads the list's path; an indirect call reads everything.
        .{ .name = "length", .param = 0, .reads = "2", .writes = "-" },
        .{ .name = "through", .param = 0, .reads = "*", .writes = "-" },
        .{ .name = "check", .param = 0, .reads = "0,3", .writes = "0,3" },
    };
    for (cases) |case| {
        const effect = s.of(try functionIndex(&module, case.name), case.param);
        errdefer std.debug.print("{s} param {d}\n", .{ case.name, case.param });
        try std.testing.expectEqualStrings(case.reads, try spell(a, &effect.reads));
        try std.testing.expectEqualStrings(case.writes, try spell(a, &effect.writes));
    }
    // Conditional writes: `check` resets the count only when it answers False, and a
    // function returning a call's answer answers as it does.
    try expectAnswers(a, &module, &s, "check");
    try expectAnswers(a, &module, &s, "relay");
}

/// `name` writes field 0 when it answers True and field 3 when it answers False.
fn expectAnswers(a: std.mem.Allocator, module: *const ir.Module, s: *const effects.Summaries, name: []const u8) !void {
    const index = try functionIndex(module, name);
    try std.testing.expectEqualStrings("0", try spell(a, s.writes(index, 0, true)));
    try std.testing.expectEqualStrings("3", try spell(a, s.writes(index, 0, false)));
    try std.testing.expectEqual([2]bool{ true, true }, s.may[index]);
}

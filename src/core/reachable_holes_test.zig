//! F-RB-18: a release build refuses the typed holes `main` can reach and builds past the rest. The build keeps holes as traps and
//! lowers only what `main` reaches, so the holes left in the built functions are the reachable ones (`reachable_holes.zig`). The
//! command-line half, with its release builds, is in `test/integration.zig`. A `debug(...)` line's arguments are evaluated in every
//! build (W5), so a hole reached only through them is a reached hole in a build that drops debug output too.
const std = @import("std");
const language = @import("selka");
const build = @import("build.zig");
const reachable_holes = @import("reachable_holes.zig");

fn holesOf(backing: std.mem.Allocator, source: []const u8) !usize {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "test.selka", source);
    unit.checking = .{ .holes = .trap };
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildModule(a, unit.program.?, &refusal);
    return (try reachable_holes.find(a, &module)).len;
}

/// `holesOf` for a build with `drop_debug` set or not (a release build sets it, a debug build and a run do not).
fn holesWithDebug(backing: std.mem.Allocator, source: []const u8, drop_debug: bool) !usize {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "test.selka", source);
    unit.checking = .{ .holes = .trap };
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(a, .{ .program = unit.program.?, .source = unit.src, .drop_debug = drop_debug }, &refusal);
    return (try reachable_holes.find(a, &module)).len;
}

const only_through_debug =
    \\func unfinished() -> int:
    \\    return todo[int]()
    \\
    \\func main() -> int:
    \\    debug(unfinished())
    \\    return 0
    \\
;

test "a hole reached only through a debug argument is reached when the build drops debug output, as when it keeps it" {
    try std.testing.expectEqual(@as(usize, 1), try holesWithDebug(std.testing.allocator, only_through_debug, false));
    try std.testing.expectEqual(@as(usize, 1), try holesWithDebug(std.testing.allocator, only_through_debug, true));
}

test "a hole in a function no debug argument calls is not reached when the build drops debug output" {
    try std.testing.expectEqual(@as(usize, 0), try holesWithDebug(std.testing.allocator,
        \\func unfinished() -> int:
        \\    return todo[int]()
        \\
        \\func main() -> int:
        \\    debug("trace")
        \\    return 0
        \\
    , true));
}

test "a hole that main calls is found" {
    try std.testing.expectEqual(@as(usize, 1), try holesOf(std.testing.allocator,
        \\func unfinished() -> int:
        \\    return todo[int]()
        \\
        \\func main() -> int:
        \\    return unfinished()
        \\
    ));
}

test "a hole in a function main cannot reach is not built" {
    try std.testing.expectEqual(@as(usize, 0), try holesOf(std.testing.allocator,
        \\func unfinished() -> int:
        \\    return todo[int]()
        \\
        \\func later() -> int:
        \\    return unfinished() + 1
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ));
}

test "a hole reachable only through a function value counts as reached" {
    try std.testing.expectEqual(@as(usize, 1), try holesOf(std.testing.allocator,
        \\func unfinished(x: int) -> int:
        \\    return todo[int]()
        \\
        \\func apply(f: func(int) -> int, flag: bool) -> int:
        \\    if flag:
        \\        return f(1)
        \\    return 0
        \\
        \\func main() -> int:
        \\    return apply(unfinished, False)
        \\
    ));
}

test "a function value taken in a function main cannot reach does not reach its hole" {
    try std.testing.expectEqual(@as(usize, 0), try holesOf(std.testing.allocator,
        \\func unfinished(x: int) -> int:
        \\    return todo[int]()
        \\
        \\func apply(f: func(int) -> int) -> int:
        \\    return f(1)
        \\
        \\func later() -> int:
        \\    return apply(unfinished)
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ));
}

test "a generic hole built for two types is one hole" {
    try std.testing.expectEqual(@as(usize, 1), try holesOf(std.testing.allocator,
        \\func pick[T](value: T) -> T:
        \\    return todo[T]()
        \\
        \\func main() -> int:
        \\    const text = pick("a")
        \\    return pick(3) + len(text)
        \\
    ));
}

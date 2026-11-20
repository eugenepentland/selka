//! Programs `selka check` accepts that a Debug compiler's build used to refuse with an internal error (G3 fix 1b): the build
//! verifies the Core IR it makes and the linkage of its units, and two valid shapes failed those checks.
const std = @import("std");
const testing = std.testing;

/// The exit status of `selka run main.selka` over a project of `files` (path and text pairs).
fn exitStatus(files: []const [2][]const u8) !u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    for (files) |file| try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "run", "main.selka", "--cache-dir", "cache", "--zig=" ++ @import("test_options").zig_path },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
}

test "check/build: a function value of a mut-parameter function in another module links, because its adapter's unit calls the function" {
    const lib =
        \\func increment(mut value: int) -> Unit:
        \\    value += 1
        \\
        \\
        \\public func bumped() -> int:
        \\    const operation: func(mut value: int) -> Unit = increment
        \\    mut value = 2
        \\    operation(mut value)
        \\    return value
        \\
    ;
    const main =
        \\import lib
        \\
        \\
        \\func main() -> int:
        \\    return lib.bumped()
        \\
    ;
    try testing.expectEqual(@as(u8, 3), try exitStatus(&.{ .{ "lib.selka", lib }, .{ "main.selka", main } }));
}

test "check/build: a const alias of an optional list field is a local the IR verifier admits" {
    const main =
        \\record Saved:
        \\    name: str
        \\    poly: float[][]? = None
        \\
        \\
        \\func corners() -> float[][]:
        \\    return [[0.0, 0.0], [1.0, 0.0]]
        \\
        \\
        \\func points(saved: Saved) -> int:
        \\    mut poly = corners()
        \\    const alias = saved.poly
        \\    if alias is not None:
        \\        poly = copy(alias)
        \\    return len(poly)
        \\
        \\
        \\func main() -> int:
        \\    const filled = Saved(name="a", poly=Some([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]))
        \\    const empty = Saved(name="b")
        \\    return points(filled) * 10 + points(empty)
        \\
    ;
    try testing.expectEqual(@as(u8, 32), try exitStatus(&.{.{ "main.selka", main }}));
}

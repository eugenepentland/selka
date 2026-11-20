//! `selka check` judges the body of every generic function at its declaration (lane G, D-G-3; W3 step 2). A build checks only the instances a
//! program makes, so before this an ownership error in such a body passed `check` of its module and was reported first by the
//! build or test of a program that instantiates it. `check` now checks the body through a representative instance, and reports
//! the error with the code, location and repair that build reports.
const std = @import("std");
const testing = std.testing;

/// What one command printed, and how it ended.
const Outcome = struct { code: u8, stderr: []u8 };

/// `selka ARGS...` run in a fresh directory holding `files` (path and text pairs), with a private cache.
fn ran(files: []const [2][]const u8, args: []const []const u8) !Outcome {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    for (files) |file| try temporary.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    const paths_module = @import("test_paths");
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try paths_module.privateEnvironment(testing.allocator);
    defer environment.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    try argv.appendSlice(testing.allocator, &.{ "--cache-dir", "cache" });
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = argv.items,
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    testing.allocator.free(result.stdout);
    return .{ .code = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stderr = result.stderr };
}

/// The diagnostic `stderr` reports first: its location and code line, and the lines that follow it up to the next blank line.
fn firstError(stderr: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, stderr, ": error[") orelse return "";
    const line_start = if (std.mem.lastIndexOfScalar(u8, stderr[0..start], '\n')) |at| at + 1 else 0;
    const end = std.mem.indexOfPos(u8, stderr, start, "\n\n") orelse stderr.len;
    return stderr[line_start..end];
}

/// A generic walk whose body builds a record from a borrowed place and stores it: an ownership error whatever `S` is.
const walk =
    \\record Segment:
    \\    term: str
    \\    width: int
    \\
    \\
    \\public func walk[S](mut state: S, names: str[]) -> int:
    \\    mut kept: Segment[] = []
    \\    for i in range(len(names)):
    \\        const term = names[i]
    \\        append(mut kept, Segment(term=term, width=i))
    \\    return len(kept)
    \\
;

/// A program that instantiates the walk with a record, as a module's test does.
const user =
    \\import walker
    \\
    \\
    \\record Tally:
    \\    count: int
    \\
    \\
    \\func main() -> int:
    \\    mut tally = Tally(count=0)
    \\    return walker.walk[Tally](mut tally, ["a", "b"])
    \\
;

test "check: a generic body that build refuses in an instance is refused by check of its module, at the declaration (W3 step 2)" {
    const files = [_][2][]const u8{ .{ "walker.selka", walk }, .{ "user.selka", user } };
    const built = try ran(&files, &.{ "build", "user.selka", "-o", "user" });
    defer testing.allocator.free(built.stderr);
    const checked = try ran(&files, &.{ "check", "walker.selka" });
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(@as(u8, 1), built.code);
    try testing.expectEqual(@as(u8, 1), checked.code);
    // Both report the refusal once, at the template's declaration, with the place in the body as a note: the build names
    // the kind of its one instance (`Tally`, a record of scalars), and check every kind it tried.
    try testing.expect(std.mem.indexOf(u8, firstError(built.stderr), "walker.selka:6:13: error[E_OWN_MARKER]: the body of `walk` is refused when `S` is a scalar (or a record of scalars)") != null);
    try testing.expect(std.mem.indexOf(u8, firstError(checked.stderr), "walker.selka:6:13: error[E_OWN_MARKER]: the body of `walk` is refused when `S` is any kind of type, a scalar included") != null);
    try testing.expect(std.mem.indexOf(u8, firstError(checked.stderr), "note: walker.selka:10:39:") != null);
    try testing.expect(std.mem.indexOf(u8, firstError(built.stderr), "note: walker.selka:10:39:") != null);
}

// A body that is right for `int` and wrong for a managed type is refused by `check` at its declaration (W3 step 2), naming
// the kinds that refuse: before, `check` tried `int` alone and only a build of a `keep_first[str]` instance reported it.
test "check: a generic body right for int and wrong for a managed type is refused at its declaration, with the kinds named" {
    const clean =
        \\public func count[T](items: T[]) -> int:
        \\    mut total = 0
        \\    for _ in items:
        \\        total += 1
        \\    return total
        \\
        \\
        \\public func keep_first[T](items: T[], mut out: T[]):
        \\    append(mut out, items[0])
        \\
    ;
    const checked = try ran(&.{.{ "generic.selka", clean }}, &.{ "check", "generic.selka" });
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(@as(u8, 1), checked.code);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, checked.stderr, "error["));
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "generic.selka:8:13: error[E_SINGLE_OWNER_BORROW]: the body of `keep_first` is refused when `T` is a text, a record with a managed field or a list") != null);
}

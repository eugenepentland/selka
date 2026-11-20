//! Loop-invariant checked access (`loop_hoist.zig`): a loop caches a record field's pointer and a
//! list's count in its preheader only when the loop keeps them unchanged, and a check that reads
//! a cached count still traps at the same iteration with the same message.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The LLVM text of the function `name` (from its `define` line to the closing brace).
fn functionText(llvm: []const u8, name: []const u8) []const u8 {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, "define ")) |start| : (from = start + 1) {
        const line_end = std.mem.indexOfPos(u8, llvm, start, "\n").?;
        if (std.mem.indexOf(u8, llvm[start..line_end], name) == null) continue;
        return llvm[start..std.mem.indexOfPos(u8, llvm, start, "\n}\n").?];
    }
    unreachable;
}

/// Record `Level` with a list it writes back each iteration, and one it only reads.
const sweep =
    \\record Level:
    \\    scale: float[]
    \\    rise: float[]
    \\    omega: float
    \\
    \\
    \\func sweep(mut work: Level, n: int) -> float:
    \\    mut total = 0.0
    \\    for k in range(n):
    \\        const s = work.scale[k] * work.omega
    \\        work.rise[k] = s
    \\        total = total + work.rise[k]
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut r = Level(scale=[1.0, 2.0], rise=[0.0, 0.0], omega=2.0)
    \\    print(out, sweep(mut r, 2))
    \\    return 0
    \\
;

// The read-only list's count and pointer load once; the body's checks read the cached count, and
// the write-back's count is cached too, since an element write keeps the count.
test "a loop caches its record's list counts and read fields in the preheader; the body loads no header" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), sweep);
    const body = functionText(llvm, "@\"my.sweep\"");
    try std.testing.expect(contains(body, "%hoist.len"));
    try std.testing.expect(contains(body, "%hoist.field"));
    try std.testing.expect(!contains(body, "%lh."));
    try std.testing.expect(contains(body, "call void @myl_core_trap"));
}

// A `mut` call changes the list its loop reads: that list keeps its header load, and a control
// loop over an unchanged field still caches its count.
const mut_call =
    \\func grow(mut xs: int[]):
    \\    append(mut xs, 7)
    \\
    \\
    \\record Box:
    \\    xs: int[]
    \\    ys: int[]
    \\
    \\
    \\func changed(n: int) -> int:
    \\    mut xs: int[] = [1]
    \\    mut total = 0
    \\    for i in range(n):
    \\        grow(mut xs)
    \\        total = total + xs[i + 1]
    \\    return total
    \\
    \\
    \\func fixed(b: Box, n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total = total + b.ys[i]
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, changed(3), fixed(Box(xs=[1], ys=[4, 5]), 2))
    \\    return 0
    \\
;

test "a mut call in a loop keeps the count of the list it changes; an unchanged field's count is cached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), mut_call);
    const changed = functionText(llvm, "@\"my.changed\"");
    try std.testing.expect(!contains(changed, "%hoist."));
    try std.testing.expect(contains(changed, "%lh."));
    const fixed = functionText(llvm, "@\"my.fixed\"");
    try std.testing.expect(contains(fixed, "%hoist.len"));
}

// A field written with a list of another count is not cached, and its header loads stay; the
// other field, never written, is cached.
const field_write =
    \\record Box:
    \\    xs: int[]
    \\    ys: int[]
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut b = Box(xs=[1], ys=[1, 2, 3])
    \\    mut total = 0
    \\    for i in range(n):
    \\        total = total + b.xs[0] + b.ys[i]
    \\        b.xs = [1, 2, 3]
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run(3))
    \\    return 0
    \\
;

test "a field written with a new list keeps its own header loads; the field never written is cached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmText(arena.allocator(), field_write);
    const body = functionText(llvm, "@\"my.run\"");
    try std.testing.expect(contains(body, "%lh."));
    try std.testing.expect(contains(body, "%hoist.len"));
}

// The trap is at the same iteration with the same message as without the plan: the program prints
// each iteration before its read, so the output shows where the check fired.
const trap_program =
    \\record Box:
    \\    xs: int[]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut b = Box(xs=[10, 20, 30])
    \\    mut total = 0
    \\    for i in range(5):
    \\        print(out, i)
    \\        total = total + b.xs[i]
    \\    print(out, total)
    \\    return 0
    \\
;

test "a check that reads a cached count traps at the same iteration with the same message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectTrapAt(arena.allocator(), "trap_debug", trap_program, &.{}, "0\n1\n2\n3\n", "(index 3, length 3)");
    try expectTrapAt(arena.allocator(), "trap_release", trap_program, &.{"--release"}, "0\n1\n2\n3\n", "(index 3, length 3)");
}

// Pops before the loop shrink the list the record holds: the loop reads past the new end and must trap
// at that index with the new count, not the count the record was built with.
const shrink_program =
    \\import lists
    \\
    \\record Poses:
    \\    pos: int[]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut result = Poses(pos=[])
    \\    append(mut result.pos, 0)
    \\    append(mut result.pos, 1)
    \\    append(mut result.pos, 2)
    \\    _ = lists.pop(mut result.pos)
    \\    _ = lists.pop(mut result.pos)
    \\    for k in range(3):
    \\        print(out, k)
    \\        print(out, result.pos[k])
    \\    return 0
    \\
;

test "a list shrunk before the loop traps at the index past its new end, in debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectTrapAt(arena.allocator(), "shrink_debug", shrink_program, &.{}, "0\n0\n1\n", "(index 1, length 1)");
    try expectTrapAt(arena.allocator(), "shrink_release", shrink_program, &.{"--release"}, "0\n0\n1\n", "(index 1, length 1)");
}

/// Build `source` as `name.selka` with `flags`, run it, and check the stdout up to the trap and the message.
fn expectTrapAt(a: std.mem.Allocator, name: []const u8, source: []const u8, flags: []const []const u8, stdout: []const u8, message: []const u8) !void {
    try support.requireReleaseArgs(flags);
    const io = std.testing.io;
    var dir = @import("stable_dir.zig").tmpDir(a, @src());
    defer dir.cleanup();
    const file = try std.fmt.allocPrint(a, "{s}.selka", .{name});
    try dir.dir.writeFile(io, .{ .sub_path = file, .data = source });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, file });
    const binary = try std.fs.path.join(a, &.{ root, name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", path, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(a, io, .{ .argv = &.{binary} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expectEqualStrings(stdout, ran.stdout);
    try std.testing.expect(contains(ran.stderr, "error[R_LIST_BOUNDS]: native execution failed "));
    try std.testing.expect(contains(ran.stderr, message));
}

//! A large function costs work in proportion to its size (lane P, `experiments/large-function-20261111/`). A generated
//! protobuf decoder of 1,022 lines (one loop, an `elif` arm per field, a `try` and so a return in each arm) cost 52 CPU
//! seconds to build, against 2.4 for the same module split into parts:
//! - the backward walks of the effect summaries (`effects.zig`, `Walk`) started every return's walk afresh, and every
//!   return reaches every join of the loop: steps grew with the returns times the joins. The test counts the walk's steps
//!   at two sizes: twice the arms must cost about twice the steps, never four times;
//! - the ownership pass's merge of repeated field reads (`own.zig`, `mergeable`) asked `dominatesBlock`, a walk of the
//!   whole function, for every pair of reads of one field (`key.number` in every arm). It asks a dominator tree computed
//!   once instead (`own.Dominance`), whose answers the second test compares with `dominatesBlock` on every pair of blocks.
const std = @import("std");
const build = @import("build.zig");
const effects = @import("effects.zig");
const own = @import("own.zig");
const support = @import("test_support.zig");

/// A decoder of `arms` fields: a loop reading a key, one `elif` arm per field reading its value with `try`, and a
/// recursive arm, the shape of a generated protobuf `merge` function.
/// The text lives in `a`, an arena: nothing is freed on failure.
fn decoderSource(a: std.mem.Allocator, arms: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("record Msg:\n");
    for (0..arms) |i| try text.writer.print("    f{d}: int = 0\n", .{i});
    try text.writer.writeAll(
        \\    rest: int[] = []
        \\
        \\
        \\enum Problem:
        \\    short
        \\
        \\
        \\func next(data: int[], mut at: int) -> int fails Problem:
        \\    if at >= len(data):
        \\        fail Problem.short
        \\    const v = data[at]
        \\    at = at + 1
        \\    return v
        \\
        \\
        \\func merge(mut msg: Msg, data: int[], mut at: int) -> Unit fails Problem:
        \\    while at < len(data):
        \\        const key = try next(data, mut at)
        \\
    );
    for (0..arms) |i| try text.writer.print("        {s} key == {d}:\n            const v = try next(data, mut at)\n            msg.f{d} = v\n", .{ if (i == 0) "if" else "elif", i, i });
    try text.writer.writeAll(
        \\        else:
        \\            append(mut msg.rest, key)
        \\
        \\
        \\func run(data: int[]) -> int fails Problem:
        \\    mut msg = Msg()
        \\    mut at = 0
        \\    try merge(mut msg, data, mut at)
        \\    return msg.f0 + len(msg.rest)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    match run([0, 7, 1, 2]):
        \\        case Ok(v):
        \\            print(out, v)
        \\            return 0
        \\        case Err(e):
        \\            return 1
        \\
    );
    return text.toOwnedSlice();
}

/// The steps the effect walks take over the decoder of `arms` fields.
fn walkSteps(backing: std.mem.Allocator, arms: usize) !u64 {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, try decoderSource(a, arms), &refusal);
    var work: effects.Work = .{};
    _ = try effects.analyzeMeasured(a, &module, &.{}, &work);
    return work.walk_steps;
}

test "the effect walks of a decoder with a return per arm grow linearly with its arms" {
    const small = try walkSteps(std.testing.allocator, 40);
    const large = try walkSteps(std.testing.allocator, 80);
    // Twice the arms: about twice the steps when each join is walked once per summary (1,480 and 2,920 steps when this
    // test was written), about four times when every return walks them again (34,936 and 133,816 before the fix).
    try std.testing.expect(large < small * 3);
    // And a budget per arm: a few dozen steps per arm and summary, not one per arm and return.
    try std.testing.expect(large < 80 * 50);
}

/// A program whose functions have loops, early returns, traps and joins of many arms, for the dominance oracle.
const shapes =
    \\func scan(xs: int[], limit: int) -> int:
    \\    mut total = 0
    \\    for x in xs:
    \\        if x > limit:
    \\            return -1
    \\        elif x == 0:
    \\            continue
    \\        while total > 100:
    \\            total = total - 7
    \\            if total == 50:
    \\                break
    \\        total = total + xs[x % len(xs)]
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, scan([1, 2, 0, 3], 9))
    \\    return 0
    \\
;

/// Whether `Dominance` answers as `dominatesBlock` for every pair of blocks of every function of `module`; the number of
/// pairs compared.
fn compareDominance(a: std.mem.Allocator, module: *const @import("ir.zig").Module) !usize {
    var pairs: usize = 0;
    for (module.functions.items) |*f| {
        const dominance = try own.Dominance.of(a, f);
        const n: u32 = @intCast(f.blocks.items.len);
        for (0..n) |through| for (0..n) |target| {
            const walked = try own.dominatesBlock(a, f, @intCast(through), @intCast(target));
            try std.testing.expectEqual(walked, dominance.dominates(@intCast(through), @intCast(target)));
            pairs += 1;
        };
    }
    return pairs;
}

test "the dominator tree the read merge asks answers as the walk it replaces, for every pair of blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const decoder = try support.buildSource(a, try decoderSource(a, 12), &refusal);
    const loops = try support.buildSource(a, shapes, &refusal);
    try std.testing.expect(try compareDominance(a, &decoder) > 1000);
    try std.testing.expect(try compareDominance(a, &loops) > 100);
}

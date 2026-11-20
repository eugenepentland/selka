//! Fault injection over fact certificates (plan C7.4): every mutant of every class is rejected by the validator, in the
//! function it edited, and every class makes at least one mutant on the fixture programs.
const std = @import("std");
const support = @import("test_support.zig");
const text = @import("fact_text.zig");
const export_ = @import("fact_export.zig");
const validate = @import("validate_facts.zig");
const mutants = @import("fact_mutants.zig");

const programs = [_][]const u8{
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\func get(xs: int[], i: int) -> int:
    \\    if i >= 0:
    \\        if i < len(xs):
    \\            return xs[i]
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    const xs = [1, 2, 3]
    \\    print(out, total(10) + get(xs, 1))
    \\    return 0
    \\
    ,
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 7) % 1009)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += values[j] // 3
    \\    print(out, total)
    \\    return 0
    \\
    ,
    \\func bounded(x: int) -> int:
    \\    if x < 100:
    \\        if x >= 0:
    \\            return x * 2 + 1
    \\    return 0
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, bounded(len(args) * 5))
    \\    return 0
    \\
    ,
    \\func total(values: int[], n: int) -> int:
    \\    mut acc = 0
    \\    for j in range(n):
    \\        acc += values[j]
    \\    return acc
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, total([1, 2, 3], len(args)))
    \\    return 0
    \\
};

/// The certificate of `source` after the release passes.
fn certificateOf(a: std.mem.Allocator, source: []const u8) !@import("fact_function.zig").Module {
    var refusal = @import("build.zig").Refusal{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const described = try export_.describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try text.write(a, &out, described);
    var problem: text.Problem = .{};
    return text.parse(a, out.items, &problem);
}

const Tally = struct {
    made: [std.enums.values(mutants.Class).len]usize = @splat(0),
    accepted: usize = 0,
    misplaced: usize = 0,
    /// The class and function of the first mutant a validator accepted.
    first_accepted: []const u8 = "",
};

/// Mutate every class of every program and validate each mutant.
fn sweep(a: std.mem.Allocator, backing: std.mem.Allocator) !Tally {
    var tally: Tally = .{};
    for (programs) |source| {
        const module = try certificateOf(a, source);
        const verdicts = try validate.validate(a, backing, module, null);
        const accepted = try a.alloc(bool, verdicts.len);
        for (verdicts, accepted) |verdict, *flag| flag.* = verdict == .accepted;
        for (std.enums.values(mutants.Class)) |class| {
            var made: mutants.Mutants = .empty;
            try mutants.mutate(a, backing, module, .{ .class = class, .accepted = accepted, .limit = 4 }, &made);
            for (made.items) |mutant| {
                tally.made[@backingInt(class)] += 1;
                const judged = try validate.validate(a, backing, mutant.module, null);
                switch (judged[mutant.function]) {
                    .accepted => {
                        tally.accepted += 1;
                        if (tally.first_accepted.len == 0) tally.first_accepted = try std.fmt.allocPrint(a, "{s} in {s}", .{ @tagName(class), module.functions[mutant.function].header.name });
                    },
                    .rejected => {},
                }
                for (judged, 0..) |verdict, k| {
                    if (verdict == .rejected and k != mutant.function) tally.misplaced += 1;
                }
            }
        }
    }
    return tally;
}

test "every fault mutant is rejected in the function it edits, and no other function is" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const tally = try sweep(arena.allocator(), std.testing.allocator);
    try std.testing.expectEqualStrings("", tally.first_accepted);
    try std.testing.expectEqual(@as(usize, 0), tally.misplaced);
}

test "every class of fault makes at least one mutant of the fixture programs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const tally = try sweep(arena.allocator(), std.testing.allocator);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.narrow_range)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.widen_operand)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.drop_refinement)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.missing_site)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.unjustified_proven)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.wrong_range)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.loop_range)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.dead_block)] > 0);
    try std.testing.expect(tally.made[@backingInt(mutants.Class.narrow_return)] > 0);
}

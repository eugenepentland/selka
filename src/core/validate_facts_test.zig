//! The fact validator (docs/design/fact-certificates.md §6): certificates written in the format, and certificates the
//! exporter makes of compiled programs.
const std = @import("std");
const support = @import("test_support.zig");
const text = @import("fact_text.zig");
const export_ = @import("fact_export.zig");
const form = @import("fact_function.zig");
const validate = @import("validate_facts.zig");

/// Parse `source` and check every function; the label of the first rejection, else "accepted".
fn judge(a: std.mem.Allocator, backing: std.mem.Allocator, source: []const u8) ![]const u8 {
    var problem: text.Problem = .{};
    const module = text.parse(a, source, &problem) catch {
        const failed = try std.fmt.allocPrint(a, "parse failed at line {d}: {s}", .{ problem.line, problem.reason });
        return failed;
    };
    const verdicts = try validate.validate(a, backing, module, null);
    for (verdicts) |verdict| switch (verdict) {
        .accepted => {},
        .rejected => |failure| {
            const reported = try std.fmt.allocPrint(a, "{s} {s}", .{ failure.check.label(), failure.detail });
            return reported;
        },
    };
    return "accepted";
}

const head = "fact-certificate-v1\nfunction f linkage internal addr 0 params i64 ret i64\nparam 0 0 9\nreturns 0 100\nblock b- reach preds -\n" ++
    "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 9\n" ++
    "inst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
    "block b0 reach preds -\n";

fn adding(comptime range: []const u8, comptime check: []const u8, comptime site: []const u8) []const u8 {
    return head ++ "inst %2 add i64 " ++ check ++ " a %0 b %1 x - imm 0 aux 0 range " ++ range ++ "\nterm ret %2\n" ++ site ++ "end\n";
}

test "a sum of a bounded parameter and one, proven with its site, is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("accepted", try judge(arena.allocator(), std.testing.allocator, adding("1 10", "proven", "site %2 0:9 1:1\n")));
}

test "a range that does not contain what the operands give is F2, wider is fine" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const narrow = try judge(a, std.testing.allocator, adding("1 9", "exact", ""));
    try std.testing.expect(std.mem.startsWith(u8, narrow, "F2 "));
    // a narrower return interval is F6, a wider range is only loose
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, adding("0 100", "exact", "")));
}

test "a proven check whose site is missing, too narrow or too wide is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // no site: the check states no reason, which is a rejection
    const missing = try judge(a, std.testing.allocator, adding("1 10", "proven", ""));
    try std.testing.expect(std.mem.startsWith(u8, missing, "F7 "));
    // a site narrower than what the operands give claims a refinement nothing justifies
    const narrow = try judge(a, std.testing.allocator, adding("1 10", "proven", "site %2 0:5 1:1\n"));
    try std.testing.expect(std.mem.startsWith(u8, narrow, "F7 "));
    // a site that does not rule out the overflow
    const wide = "fact-certificate-v1\nfunction f linkage other addr 0 params i64 ret i64\nparam 0 -\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 param i64 none a - b - x - imm 0 aux 0 range -\n" ++
        "inst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
        "block b0 reach preds -\n" ++
        "inst %2 add i64 proven a %0 b %1 x - imm 0 aux 0 range -\n" ++
        "term ret %2\nsite %2 -9223372036854775808:9223372036854775807 1:1\nend\n";
    const overflow = try judge(a, std.testing.allocator, wide);
    try std.testing.expect(std.mem.startsWith(u8, overflow, "F7 "));
}

test "a parameter interval is checked against every call of the function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const callee = "function g linkage internal addr 0 params i64 ret i64\nparam 0 0 9\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 9\nblock b0 reach preds -\nterm ret %0\nend\n";
    const caller = "function f linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 iconst i64 none a - b - x - imm {d} aux 0 range -\nblock b0 reach preds -\n" ++
        "inst %1 call i64 none a #0 b - x %0 imm 0 aux 0 range -\nterm ret %1\nend\n";
    const inside = try std.fmt.allocPrint(a, "fact-certificate-v1\n" ++ callee ++ caller, .{7});
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, inside));
    const outside = try std.fmt.allocPrint(a, "fact-certificate-v1\n" ++ callee ++ caller, .{10});
    const refused = try judge(a, std.testing.allocator, outside);
    try std.testing.expect(std.mem.startsWith(u8, refused, "F6 "));
}

test "a block stated dead must have no live edge into it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = "fact-certificate-v1\nfunction f linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 iconst bool none a - b - x - imm {d} aux 0 range -\ninst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
        "block b0 reach preds -\nterm branch %0 b1 b2\nblock b1 reach preds b0\nterm ret %1\nblock b2 dead preds b0\nterm ret %1\nend\n";
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, program, .{1})));
    const live = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, program, .{0}));
    try std.testing.expect(std.mem.startsWith(u8, live, "F5 ") or std.mem.startsWith(u8, live, "F1 "));
}

test "an edge refines a value for the blocks it dominates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // %0 is a parameter; on the taken edge of `%0 < 10` the sum with 1 is at most 10
    const program = "fact-certificate-v1\nfunction f linkage other addr 0 params i64 ret i64\nparam 0 -\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 param i64 none a - b - x - imm 0 aux 0 range -\ninst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\ninst %2 iconst i64 none a - b - x - imm 10 aux 0 range -\n" ++
        "inst %3 iconst i64 none a - b - x - imm 0 aux 0 range -\ninst %7 iconst i64 none a - b - x - imm 0 aux 0 range -\n" ++
        "block b0 reach preds -\ninst %4 cmp bool none a %0 b %2 x - imm 2 aux 0 range -\nterm branch %4 b1 b2\n" ++
        "block b1 reach preds b0\ninst %5 add i64 proven a %0 b %1 x - imm 0 aux 0 range {s}\nterm ret %5\n" ++
        "block b2 reach preds b0\nterm ret %7\n" ++
        "{s}end\n";
    // with the refinement: %0 <= 9 on the edge, so %0 + 1 cannot overflow only if %0 >= minimum; the lower bound is open
    const refused = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, program, .{ "-", "site %5 -9223372036854775808:9 1:1\n" }));
    try std.testing.expectEqualStrings("accepted", refused);
    // the site claims more than the edge gives
    const too_narrow = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, program, .{ "-", "site %5 -9223372036854775808:5 1:1\n" }));
    try std.testing.expect(std.mem.startsWith(u8, too_narrow, "F7 "));
}

test "the entry block with a predecessor is a shape fault, since a refinement would hold for the first entry too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const looping = "fact-certificate-v1\nfunction f linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 iconst bool none a - b - x - imm 1 aux 0 range -\ninst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
        "block b0 reach preds b1\nterm branch %0 b1 b2\nblock b1 reach preds b0\nterm jump b0\nblock b2 reach preds b0\nterm ret %1\nend\n";
    const verdict = try judge(arena.allocator(), std.testing.allocator, looping);
    try std.testing.expect(std.mem.startsWith(u8, verdict, "F1 "));
    try std.testing.expect(std.mem.indexOf(u8, verdict, "entry block b0") != null);
}

const counted_head = "fact-certificate-v1\nfunction f linkage internal addr 0 params i64,bool ret i64\nparam 0 0 10\nparam 1 -\nreturns -\nblock b- reach preds -\n" ++
    "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 10\ninst %6 param bool none a - b - x - imm 1 aux 0 range -\n" ++
    "inst %1 iconst i64 none a - b - x - imm 0 aux 0 range -\ninst %2 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
    "block b0 reach preds -\nterm jump b1\nblock b1 reach preds b0,b3\nphi %3 i64 edges b0:%1,b3:%5 range 0 10\n" ++
    "inst %4 cmp bool none a %3 b %0 x - imm 2 aux 0 range 0 1\n";
const counted_tail = "inst %5 add i64 exact a %3 b %2 x - imm 0 aux 0 range 1 11\nterm jump b1\n";

test "a counter is bounded by its bound only when the body guards the latch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // the header's `else` leaves the loop: every path to the latch passes through the body, where `counter < bound` holds
    const guarded = counted_head ++ "term branch %4 b2 b4\nblock b2 reach preds b1\nterm jump b3\nblock b3 reach preds b2\n" ++ counted_tail ++
        "block b4 reach preds b1\nterm ret %3\nloop header b1 body b2 latch b3 exit b4\nend\n";
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, guarded));
    // the header's `else` reaches the latch without the body: the back edge is unguarded and the counter grows past the bound
    const unguarded = counted_head ++ "term branch %4 b2 b3\nblock b2 reach preds b1\nterm branch %6 b3 b4\nblock b3 reach preds b1,b2\n" ++ counted_tail ++
        "block b4 reach preds b2\nterm ret %3\nloop header b1 body b2 latch b3 exit b4\nend\n";
    const refused = try judge(a, std.testing.allocator, unguarded);
    try std.testing.expect(std.mem.startsWith(u8, refused, "F3 "));
}

/// A one-block function with the given leaf lines before `block b0` and the given instruction lines in it; it returns `%2`.
fn leafProgram(comptime leaves: []const u8, comptime insts: []const u8) []const u8 {
    return "fact-certificate-v1\nfunction f linkage other addr 0 params i64 ret i64\nparam 0 -\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 param i64 none a - b - x - imm 0 aux 0 range -\n" ++ leaves ++ "block b0 reach preds -\n" ++ insts ++ "term ret %2\nend\n";
}

test "what the rules read of the leaves is held to the form: operands, parameter types, constants and operand types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = "inst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n";
    const sum = "inst %2 add i64 exact a %0 b %1 x - imm 0 aux 0 range -\n";
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, leafProgram(one, sum)));
    // a value defined outside every block reads nothing
    const reading = try judge(a, std.testing.allocator, leafProgram(one ++ "inst %3 add i64 none a %0 b %1 x - imm 0 aux 0 range -\n", sum));
    try std.testing.expect(std.mem.startsWith(u8, reading, "F1 ") and std.mem.indexOf(u8, reading, "has operands") != null);
    // a parameter has the type its header gives
    const retyped = try judge(a, std.testing.allocator, leafProgram(one ++ "inst %3 param i32 none a - b - x - imm 0 aux 0 range -\n", sum));
    try std.testing.expect(std.mem.startsWith(u8, retyped, "F1 ") and std.mem.indexOf(u8, retyped, "header gives parameter") != null);
    // a constant fits its type
    const wide = try judge(a, std.testing.allocator, leafProgram("inst %1 iconst u8 none a - b - x - imm 300 aux 0 range -\n", "inst %2 add u8 none a %1 b %1 x - imm 0 aux 0 range -\n"));
    try std.testing.expect(std.mem.startsWith(u8, wide, "F1 ") and std.mem.indexOf(u8, wide, "does not fit") != null);
    // an integer rule reads operands of the result's type
    const mixed = try judge(a, std.testing.allocator, leafProgram("inst %1 iconst i32 none a - b - x - imm 1 aux 0 range -\n", sum));
    try std.testing.expect(std.mem.startsWith(u8, mixed, "F1 ") and std.mem.indexOf(u8, mixed, "type of the result") != null);
}

test "a shift reads a left operand of the result's type, whatever the type of its count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text_of = "fact-certificate-v1\nfunction f linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 iconst {s} none a - b - x - imm 1 aux 0 range -\ninst %1 iconst {s} none a - b - x - imm 3 aux 0 range -\n" ++
        "block b0 reach preds -\ninst %2 shift_left i64 none a %0 b %1 x - imm 0 aux 0 range -\nterm ret %2\nend\n";
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{ "i64", "i32" })));
    const refused = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{ "i32", "i64" }));
    try std.testing.expect(std.mem.startsWith(u8, refused, "F1 ") and std.mem.indexOf(u8, refused, "type of the result") != null);
}

test "a phi reads operands of its own type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text_of = "fact-certificate-v1\nfunction f linkage other addr 0 params - ret i64\nreturns -\nblock b- reach preds -\n" ++
        "inst %1 iconst {s} none a - b - x - imm 1 aux 0 range -\n" ++
        "block b0 reach preds -\nterm jump b1\nblock b1 reach preds b0\nphi %2 i64 edges b0:%1 range -\nterm ret %2\nend\n";
    const a = arena.allocator();
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{"i64"})));
    const refused = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{"i32"}));
    try std.testing.expect(std.mem.startsWith(u8, refused, "F1 ") and std.mem.indexOf(u8, refused, "another type") != null);
}

test "an operation that always traps states an empty interval, and what reads it is vacuous" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text_of = "fact-certificate-v1\nfunction f linkage internal addr 0 params i64 ret i64\nparam 0 0 9\nreturns -\nblock b- reach preds -\n" ++
        "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 9\ninst %1 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
        "inst %5 iconst i64 none a - b - x - imm 9223372036854775807 aux 0 range -\n" ++
        "block b0 reach preds -\ninst %2 add i64 exact a {s} b %1 x - imm 0 aux 0 range {s}\n" ++
        "inst %3 add i64 exact a %2 b %1 x - imm 0 aux 0 range 0 0\nterm ret %3\nend\n";
    // the largest i64 plus one never completes: the interval is empty, whichever empty interval is stated
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{ "%5", "9223372036854775808 9223372036854775807" })));
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{ "%5", "1 0" })));
    // a parameter in [0, 9] plus one completes: an empty interval is a false claim
    const false_claim = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, text_of, .{ "%0", "1 0" }));
    try std.testing.expect(std.mem.startsWith(u8, false_claim, "F2 "));
}

/// The statistics of the first function of `source`, which the validator must accept.
fn statsOf(a: std.mem.Allocator, backing: std.mem.Allocator, source: []const u8) !validate.Stats {
    var problem: text.Problem = .{};
    const module = try text.parse(a, source, &problem);
    const verdicts = try validate.validate(a, backing, module, null);
    return switch (verdicts[0]) {
        .accepted => |stats| stats,
        .rejected => error.Rejected,
    };
}

const edge_head = "fact-certificate-v1\nfunction f linkage other addr 0 params i64,bool ret i64\nparam 0 -\nparam 1 -\nreturns -\nblock b- reach preds -\n" ++
    "inst %0 param i64 none a - b - x - imm 0 aux 0 range -\ninst %1 param bool none a - b - x - imm 1 aux 0 range -\ninst %2 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
    "block b0 reach preds -\ninst %3 sub i64 exact a %0 b %2 x - imm 0 aux 0 range -\nterm jump b1\n" ++
    "block b1 reach preds b0,b2\nphi %4 i64 edges b0:%0,b2:%7 range -\ninst %5 sub i64 proven a %4 b %2 x - imm 0 aux 0 range -\nterm branch %1 b2 b3\n" ++
    "block b2 reach preds b1\ninst %7 add i64 exact a %5 b %2 x - imm 0 aux 0 range -\n";
const edge_tail = "term jump b1\nblock b3 reach preds b1\nterm ret %5\nsite %5 -9223372036854775808:9223372036854775807 1:1\nend\n";

test "a constant subtraction proven by the checks on every edge into its phi's block is counted, not validated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // the entry edge checks `%0 - 1` and the back edge `%7 - 1`, the value the phi takes from each
    const checked = edge_head ++ "inst %8 sub i64 exact a %7 b %2 x - imm 0 aux 0 range -\n" ++ edge_tail;
    const stats = try statsOf(a, std.testing.allocator, checked);
    try std.testing.expectEqual(@as(u32, 1), stats.unchecked[@backingInt(validate.Unchecked.edge_checked)]);
    // without the check on the back edge nothing shows the subtraction cannot overflow
    const missing = try judge(a, std.testing.allocator, edge_head ++ "inst %8 add i64 exact a %7 b %2 x - imm 0 aux 0 range -\n" ++ edge_tail);
    try std.testing.expect(std.mem.startsWith(u8, missing, "F7 "));
}

test "the validator imports only the form and the operation names" {
    const sources = [_][]const u8{ @embedFile("validate_facts.zig"), @embedFile("fact_function.zig") };
    const allowed = [_][]const u8{ "std", "builtin", "ir.zig", "fact_function.zig" };
    try std.testing.expectEqual(@as(?[]const u8, null), foreignImport(&sources, &allowed));
}

test "the form states the same list-length bound as the target" {
    try std.testing.expectEqual(@import("target.zig").host.maxListLength(), form.max_list_length);
}

/// The first `@import` of any source that is not in `allowed`, or null.
fn foreignImport(sources: []const []const u8, allowed: []const []const u8) ?[]const u8 {
    for (sources) |source| {
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, source, at, "@import(\"")) |found| {
            const start = found + "@import(\"".len;
            const end = std.mem.indexOfScalarPos(u8, source, start, '"') orelse return source[found..];
            const name = source[start..end];
            at = end;
            var ok = false;
            for (allowed) |known| ok = ok or std.mem.eql(u8, known, name);
            if (!ok) return name;
        }
    }
    return null;
}

/// The certificate of `source` after the release passes, as text.
fn certificateOf(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    var refusal = @import("build.zig").Refusal{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const described = try export_.describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try text.write(a, &out, described);
    return out.items;
}

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
    // A reduction whose step is bounded by a guard on one side only: its bound leaves the type on the other (F3, F4).
    \\public func guarded(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value <= 100:
    \\            total += value
    \\    return total
    \\
    \\public func skipped(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value > 100:
    \\            continue
    \\        total += value
    \\    return total
    \\
    \\public func stopped(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        if value < -100:
    \\            break
    \\        total -= value
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, guarded([1, 200]) + skipped([2, 300]) + stopped([3, -300]))
    \\    print(out, guarded([4]) + skipped([5]) + stopped([6]))
    \\    return 0
    \\
};

test "the certificate of a compiled program prints, reads back byte for byte, and is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("accepted", try roundTripAll(arena.allocator(), std.testing.allocator));
}

/// "accepted" when every program's certificate reads back unchanged and is accepted, else what went wrong and the certificate.
fn roundTripAll(a: std.mem.Allocator, backing: std.mem.Allocator) ![]const u8 {
    for (programs) |source| {
        const first = try certificateOf(a, source);
        var problem: text.Problem = .{};
        const module = try text.parse(a, first, &problem);
        var again: std.ArrayList(u8) = .empty;
        try text.write(a, &again, module);
        if (!std.mem.eql(u8, first, again.items)) {
            const changed = try std.fmt.allocPrint(a, "the text does not read back unchanged:\n{s}", .{first});
            return changed;
        }
        const verdict = try judge(a, backing, first);
        if (!std.mem.eql(u8, verdict, "accepted")) {
            const refused = try std.fmt.allocPrint(a, "{s}\n{s}", .{ verdict, first });
            return refused;
        }
    }
    return "accepted";
}

/// A counted loop from `%7` to `%0` (both in [0, 10]) entered only when `%7 >= 2`: the hull of the counter's operands is
/// [2, 11] (the entry edge refines `%7`), its counter bound [0, 10] (the base of `%7`); the counter phi states `{s}`.
const counter_meet = "fact-certificate-v1\nfunction f linkage internal addr 0 params i64,i64 ret i64\nparam 0 0 10\nparam 1 0 10\nreturns -\n" ++
    "block b- reach preds -\ninst %0 param i64 none a - b - x - imm 0 aux 0 range 0 10\ninst %7 param i64 none a - b - x - imm 1 aux 0 range 0 10\n" ++
    "inst %1 iconst i64 none a - b - x - imm 2 aux 0 range -\ninst %2 iconst i64 none a - b - x - imm 1 aux 0 range -\n" ++
    "block b0 reach preds -\ninst %8 cmp bool none a %7 b %1 x - imm 5 aux 0 range 0 1\nterm branch %8 b1 b5\n" ++
    "block b1 reach preds b0\nterm jump b2\nblock b2 reach preds b1,b4\nphi %3 i64 edges b1:%7,b4:%5 range {s}\n" ++
    "inst %4 cmp bool none a %3 b %0 x - imm 2 aux 0 range 0 1\nterm branch %4 b3 b5\nblock b3 reach preds b2\nterm jump b4\n" ++
    "block b4 reach preds b3\ninst %5 add i64 exact a %3 b %2 x - imm 0 aux 0 range 3 11\nterm jump b2\n" ++
    "block b5 reach preds b0,b2\nterm ret %7\nloop header b2 body b3 latch b4 exit b5\nend\n";

test "a counter phi is accepted within the meet of its operand hull and its counter bound, and no tighter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // the hull [2, 11] alone and the counter bound [0, 10] alone both exceed [2, 10]; their meet is [2, 10]
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, counter_meet, .{"2 10"})));
    const low = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, counter_meet, .{"3 10"}));
    try std.testing.expect(std.mem.startsWith(u8, low, "F3 "));
    const high = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, counter_meet, .{"2 9"}));
    try std.testing.expect(std.mem.startsWith(u8, high, "F3 "));
}

/// A counted loop of at most 10 trips whose accumulator `%9` grows by 3 and wraps by 5 (`phase += 3; if phase >= 5: phase -= 5`):
/// its operand hull is [-11, 33] and its reduction bound [-20, 30]; the accumulator phi states `{s}`.
const reduction_meet = "fact-certificate-v1\nfunction f linkage internal addr 0 params i64 ret i64\nparam 0 0 10\nreturns -\nblock b- reach preds -\n" ++
    "inst %0 param i64 none a - b - x - imm 0 aux 0 range 0 10\ninst %1 iconst i64 none a - b - x - imm 0 aux 0 range -\n" ++
    "inst %2 iconst i64 none a - b - x - imm 1 aux 0 range -\ninst %20 iconst i64 none a - b - x - imm 3 aux 0 range -\n" ++
    "inst %21 iconst i64 none a - b - x - imm 5 aux 0 range -\nblock b0 reach preds -\nterm jump b1\nblock b1 reach preds b0,b3\n" ++
    "phi %3 i64 edges b0:%1,b3:%5 range 0 10\nphi %9 i64 edges b0:%1,b3:%12 range {s}\n" ++
    "inst %4 cmp bool none a %3 b %0 x - imm 2 aux 0 range 0 1\nterm branch %4 b2 b4\nblock b2 reach preds b1\n" ++
    "inst %10 add i64 exact a %9 b %20 x - imm 0 aux 0 range -11 33\ninst %11 cmp bool none a %10 b %21 x - imm 5 aux 0 range 0 1\n" ++
    "term branch %11 b5 b6\nblock b3 reach preds b6\ninst %5 add i64 exact a %3 b %2 x - imm 0 aux 0 range 1 10\nterm jump b1\n" ++
    "block b4 reach preds b1\nterm ret %9\nblock b5 reach preds b2\ninst %13 sub i64 exact a %10 b %21 x - imm 0 aux 0 range 0 28\nterm jump b6\n" ++
    "block b6 reach preds b2,b5\nphi %12 i64 edges b2:%10,b5:%13 range -11 33\nterm jump b3\nloop header b1 body b2 latch b3 exit b4\nend\n";

test "a reduction phi is accepted within the meet of its operand hull and its reduction bound, and no tighter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // the hull [-11, 33] alone and the reduction bound [-20, 30] alone both exceed [-14, 30]; their meet [-11, 30] does not
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, reduction_meet, .{"-14 30"})));
    try std.testing.expectEqualStrings("accepted", try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, reduction_meet, .{"-11 30"})));
    const low = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, reduction_meet, .{"-10 30"}));
    try std.testing.expect(std.mem.startsWith(u8, low, "F3 "));
    const high = try judge(a, std.testing.allocator, try std.fmt.allocPrint(a, reduction_meet, .{"-14 29"}));
    try std.testing.expect(std.mem.startsWith(u8, high, "F3 "));
}

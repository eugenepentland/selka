//! FX5: an operation whose operand always traps. A checked operation that always traps has the empty interval (the value is
//! never produced, lane FX3), and three transfer rules of the fact pass read such an operand's bounds as if it had values: a
//! shift's count was cast to a shift amount (`integer does not fit`), a divisor's empty interval passed the positive-divisor
//! test and divided by zero, and an exclusive-or's upper bound was cast to an unsigned integer. A Debug compiler panicked in
//! every build that runs the fact pass. An instruction that reads an empty operand never executes, so the pass now gives it the
//! empty interval in one place (`facts.transfer`), as the fact validator's rules derive it, and its edge, phi and loop rules
//! read an empty operand as the validator does. These tests lower each shape, check that the certificate of the release passes
//! is accepted, run the release passes' code (linked unoptimized, so they run in every gate) and the debug pipeline's, which
//! must both trap, and run `selka test` on the shapes, which reports the trap and not a build error.
const std = @import("std");
const support = @import("test_support.zig");
const export_ = @import("fact_export.zig");
const text = @import("fact_text.zig");
const validate = @import("validate_facts.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");

/// The body of a `build() -> int` that reads a value whose checked arithmetic always traps, one per shape: the three
/// generator programs, then every rule that reads an operand, in each width, through a `const`, a call and a `fails`
/// function, as a loop bound, an index and a condition.
const shapes = [_][]const u8{
    // The generator's three programs (lane GEN's hunt).
    "func build() -> int:\n    const c: u32 = 14u32 - 31u32\n    return int(shift_right(7u32, c))\n",
    "func build() -> int:\n    const c: u32 = 14u32 - 31u32\n    return int(bit_xor(c, c))\n",
    "func build() -> int:\n    const d: u32 = saturating_add(14u32 - 31u32, 1u32)\n    return int(7u32 // d)\n",
    // Shifts: the count and the shifted value, signed and unsigned, direct and through a call.
    "func build() -> int:\n    const c: i8 = 127i8 + 1i8\n    return int(shift_right(64i8, c))\n",
    "func build() -> int:\n    const c: u64 = 1u64 - 2u64\n    return int(shift_left(1u64, c) % 7u64)\n",
    "func build() -> int:\n    const c: int = 9223372036854775807 + 1\n    return shift_right(c, 3)\n",
    "func boom() -> u16:\n    return 1u16 - 2u16\n\nfunc build() -> int:\n    return int(shift_right(9u16, boom()))\n",
    // Division and remainder by an empty divisor, and of an empty dividend.
    "func build() -> int:\n    const d: i32 = 2147483647i32 + 1i32\n    return int(100i32 // d)\n",
    "func build() -> int:\n    const d: u8 = 3u8 - 4u8\n    return int(200u8 % d)\n",
    "func build() -> int:\n    const x: i16 = -32768i16 - 1i16\n    return int(x // 3i16) + int(x % 3i16)\n",
    // Bit operations, saturating and wrapping forms, negation and conversions.
    "func build() -> int:\n    const c: i64 = -9223372036854775807 - 2\n    return bit_xor(c, 5) + bit_and(c, 3) + bit_or(c, 1)\n",
    "func build() -> int:\n    const c: u32 = 14u32 - 31u32\n    return int(bit_not(c)) + int(saturating_sub(c, 1u32)) + int(wrapping_mul(c, 3u32))\n",
    "func build() -> int:\n    const c: i8 = -128i8 - 1i8\n    return int(-c) + int(u8(c)) + int(float(c))\n",
    // Comparisons, in a condition and as a value.
    "func build() -> int:\n    const c: u32 = 14u32 - 31u32\n    if c < 3u32:\n        return 1\n    return 2\n",
    "func build() -> int:\n    const c: i32 = 2147483647i32 + 1i32\n    mut x: i32 = 5i32\n    if x > c:\n        x = shift_right(x, c)\n    return int(x)\n",
    "func build() -> int:\n    const c: u8 = 1u8 - 9u8\n    return len(str(c == 3u8))\n",
    // Loop bounds: a counted loop, a `while`, and a loop whose body reads the bound.
    "func build() -> int:\n    const c: int = 9223372036854775807 + 1\n    mut n = 0\n    for i in range(c):\n        n = n + i\n    return n\n",
    "func build() -> int:\n    const c: u32 = 14u32 - 31u32\n    mut n: u32 = 0u32\n    mut i: u32 = 0u32\n    while i < c:\n        n = n + shift_right(7u32, i)\n        i = i + 1u32\n    return int(n)\n",
    "func build() -> int:\n    const c: u16 = 2u16 - 3u16\n    mut n = 0\n    for i in range(int(c)):\n        n = n + int(7u16 // c)\n    return n\n",
    // An index, a phi of the empty value, an inner block, and a `fails` function.
    "func build() -> int:\n    const c: int = -9223372036854775807 - 2\n    const xs: int[] = [5, 6, 7]\n    return xs[c]\n",
    "func flag() -> bool:\n    return len([1]) == 1\n\nfunc build() -> int:\n    mut v: u32 = 2u32\n    if flag():\n        v = 1u32 - 5u32\n    return int(shift_right(64u32, v))\n",
    "func flag() -> bool:\n    return len([1]) == 1\n\nfunc build() -> int:\n    mut n = 0\n    if flag():\n        const d: u64 = 0u64 - 1u64\n        n = int(9u64 // d)\n    return n\n",
    "func inner(k: u32) -> int fails str:\n    if k == 0u32:\n        fail \"zero\"\n    const c: u32 = k - 31u32\n    return int(shift_right(7u32, c))\n\n" ++
        "func build() -> int:\n    match inner(14u32):\n        case Ok(n):\n            return n\n        case Err(_):\n            return 0\n",
    // A parameter that every call passes an empty value: the callee reads it as never produced.
    "func shifted(count: u32) -> u32:\n    return shift_right(7u32, count) + 7u32 // count\n\nfunc build() -> int:\n    return int(shifted(14u32 - 31u32))\n",
};

const main_text = "\nfunc main(out: Stream) -> int:\n    print(out, build())\n    return 0\n";

fn program(a: std.mem.Allocator, shape: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ shape, main_text });
}

/// "accepted" when the release passes' certificate of every shape, in `mode`, is accepted by the fact validator, else the
/// shape and the validator's reason.
fn certificatesAccepted(a: std.mem.Allocator, backing: std.mem.Allocator, mode: passes.Mode) ![]const u8 {
    for (shapes, 0..) |shape, index| {
        var refusal: build.Refusal = .{};
        var module = try support.buildSource(a, try program(a, shape), &refusal);
        const result = try support.runPasses(a, &module, mode);
        const described = try export_.describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
        const verdicts = try validate.validate(a, backing, described, null);
        for (verdicts, described.functions) |verdict, function| switch (verdict) {
            .accepted => {},
            .rejected => |failure| return std.fmt.allocPrint(a, "shape {d}: {s}\n{s}", .{ index, try validate.describe(a, function.header.name, failure), shape }),
        };
    }
    return "accepted";
}

/// "trapped" when every shape, through the release passes (`optimized`) or the debug pipeline, ends with `R_OVERFLOW` and
/// prints nothing, else the shape and what it did.
fn everyShapeTraps(a: std.mem.Allocator, optimized: bool) ![]const u8 {
    for (shapes, 0..) |shape, index| {
        var refusal: build.Refusal = .{};
        var module = try support.buildSource(a, try program(a, shape), &refusal);
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        try support.verified(a, &module, result.plans);
        const run = try support.runOwned(a, &module, .{ .own = false, .verify = optimized, .analysis = support.analysis(&result) });
        const trapped = run.status == 1 and run.stdout.len == 0 and std.mem.indexOf(u8, run.stderr, "R_OVERFLOW") != null;
        if (!trapped) return std.fmt.allocPrint(a, "shape {d} exited {d}: {s}{s}\n{s}", .{ index, run.status, run.stdout, run.stderr, shape });
    }
    return "trapped";
}

test "trapping operand: the shift of a never-produced count states the empty interval, which the validator derives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, try program(a, shapes[0]), &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const described = try export_.describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try text.write(a, &out, described);
    // The subtraction never completes, so the shift that reads it and the conversion of the shift never execute: both
    // state the empty interval, and so does the call of `build` in `main`, which never returns.
    try std.testing.expect(std.mem.endsWith(u8, lineOf(out.items, " sub u32 exact "), " range 0 -17"));
    try std.testing.expect(std.mem.endsWith(u8, lineOf(out.items, " shift_right u32 "), " range 1 0"));
    try std.testing.expect(std.mem.endsWith(u8, lineOf(out.items, " convert i64 "), " range 1 0"));
}

/// The first line of `listing` that contains `needle`, or "" when none does.
fn lineOf(listing: []const u8, needle: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, needle) != null) return line;
    }
    return "";
}

test "trapping operand: every shape of an operation on a never-produced value has a certificate the fact validator accepts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("accepted", try certificatesAccepted(arena.allocator(), std.testing.allocator, .trusted));
    try std.testing.expectEqualStrings("accepted", try certificatesAccepted(arena.allocator(), std.testing.allocator, .verify));
}

test "trapping operand: every shape of an operation on a never-produced value traps R_OVERFLOW through the debug and the release passes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("trapped", try everyShapeTraps(arena.allocator(), false));
    try std.testing.expectEqualStrings("trapped", try everyShapeTraps(arena.allocator(), true));
}

/// The shapes as one test file: `test_shape_K` calls the K-th shape's `build`, renamed `build_K`.
fn testFile(a: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (shapes, 0..) |shape, index| {
        var renamed = shape;
        for ([_][]const u8{ "build", "flag", "boom", "inner", "shifted" }) |name| {
            const from = try std.fmt.allocPrint(a, "{s}(", .{name});
            const to = try std.fmt.allocPrint(a, "{s}_{d}(", .{ name, index });
            renamed = try std.mem.replaceOwned(u8, a, renamed, from, to);
        }
        try out.print(a, "{s}\npublic func test_shape_{d}() -> bool:\n    return build_{d}() >= 0\n\n", .{ renamed, index, index });
    }
    return out.items;
}

/// How many of the report's tests failed on an `R_OVERFLOW` trap.
fn overflowVerdicts(parsed: std.json.Value) usize {
    var count: usize = 0;
    for (parsed.object.get("tests").?.array.items) |item| {
        const failed = std.mem.eql(u8, item.object.get("status").?.string, "failed");
        if (failed and std.mem.startsWith(u8, item.object.get("reason").?.string, "R_OVERFLOW")) count += 1;
    }
    return count;
}

test "trapping operand: selka test reports each shape's overflow as the test's trap, not as a build error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "operands.selka", .data = try testFile(a) });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "operands.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try options.privateEnvironment(a);
    const result = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "test", source, "--json", "--cache-dir", cache }, .environ_map = &environment });
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "E_FACT_VALIDATION") == null);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try std.testing.expectEqual(shapes.len, overflowVerdicts(parsed));
}

/// A reduction the vectorizer lowers to 16-bit lanes (the kernel of `vector_test.zig`), plus the division of a value
/// defined before the loop whose subtraction always overflows. The division is a lane operation, and its dividend's empty
/// interval `[0, -17]` reached the multiply-high reciprocal, which cast its bounds to `u32` and crashed the compiler.
const empty_lane =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 100
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, (j * 37 + 5) % 1009)
    \\    const c: u8 = 14u8 - 31u8
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += ((values[j] + 3) * 17 + 23) // 7 % 1009 + int(c // 7u8)
    \\    print(out, total)
    \\    return 0
    \\
;

test "trapping operand: a loop whose lane value is never produced stays scalar instead of crashing the vectorizer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try support.releaseLlvmTextFor(arena.allocator(), empty_lane, @import("target.zig").x86_64_linux_avx2);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.x86.avx2.pmulhu.w") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "define ") != null);
}

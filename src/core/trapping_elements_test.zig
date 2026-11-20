//! FX3: a list element whose checked arithmetic always traps. The fact pass gives such an operation an empty interval (the
//! value is never produced), and it used to hull that empty interval into the element fact of the list that holds it, so
//! `[1, 9223372036854775807 + 1]` stated elements `[1, 9223372036854775807]`. The fact validator's transfer rule reads a
//! never-produced operand as its type's range and refused the build (`E_FACT_VALIDATION`) in `--release` and `selka test`,
//! where the plain build traps `R_OVERFLOW` as the language says. The pass now states what the rule derives
//! (`facts.elementRange`). These tests lower each shape of the class, check that the certificate of the release passes is
//! accepted, and run the release passes' code (linked unoptimized, so they run in every gate) and the debug pipeline's, which
//! must both trap. The last test runs `selka test` on the shapes, which reports the trap and not a build error.
const std = @import("std");
const support = @import("test_support.zig");
const export_ = @import("fact_export.zig");
const text = @import("fact_text.zig");
const validate = @import("validate_facts.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");

/// The body of a `build() -> int` whose list holds an element that always overflows, one per shape: operations, widths,
/// holders and positions. Each is a whole program with `main`, which prints `build()` and so never returns normally.
const shapes = [_][]const u8{
    // The reduced program of lane W19a.
    "func build() -> int:\n    const xs: int[] = [1, 9223372036854775807 + 1]\n    return len(xs)\n",
    "func build() -> int:\n    const xs: int[] = [1, -9223372036854775807 - 2]\n    return len(xs)\n",
    "func build() -> int:\n    const xs: int[] = [1, 9223372036854775807 * 2]\n    return len(xs)\n",
    "func build() -> int:\n    const xs: int[] = [1, (9223372036854775807 + 1) * 2]\n    return len(xs)\n",
    "func build() -> int:\n    const a: i32 = 2147483647i32\n    const xs: i32[] = [1i32, a + 1i32]\n    return len(xs)\n",
    "func build() -> int:\n    const a: i8 = 100i8\n    const xs: i8[] = [1i8, a * 2i8]\n    return len(xs)\n",
    "func build() -> int:\n    const xs: u8[] = [1u8, 0u8 - 1u8]\n    return len(xs)\n",
    "func build() -> int:\n    const xs: u64[] = [1u64, 18446744073709551615u64 + 1u64]\n    return len(xs)\n",
    // Checked conversions out of the target's range.
    "func build() -> int:\n    const v: int = 300\n    const xs: u8[] = [1u8, u8(v)]\n    return len(xs)\n",
    "func build() -> int:\n    const v: int = -1\n    const xs: u16[] = [1u16, u16(v)]\n    return len(xs)\n",
    // Appends, to an empty and to a held list, in a `for` and a `while`.
    "func build() -> int:\n    mut xs: int[] = []\n    append(mut xs, 9223372036854775807 + 1)\n    return len(xs) + 1\n",
    "func build() -> int:\n    mut xs: int[] = [1]\n    append(mut xs, 9223372036854775807 + 1)\n    return len(xs)\n",
    "func build() -> int:\n    mut xs: int[] = [1]\n    for i in range(3):\n        append(mut xs, 9223372036854775807 + i + 1)\n    return len(xs) - 2\n",
    "func build() -> int:\n    mut xs: int[] = [1]\n    mut i = 0\n    while i < 1:\n        append(mut xs, 9223372036854775807 + 1)\n        i = i + 1\n    return len(xs)\n",
    // A counted fill loop from an empty list, whose element facts come from the loop's one push.
    "func build() -> int:\n    mut xs: int[] = []\n    for i in range(3):\n        append(mut xs, 9223372036854775807 + i + 1)\n    return len(xs) - 1\n",
    // Other holders: a fixed array, a nested list, a record's list field.
    "func build() -> int:\n    const xs = FixedArray[int, 2]([1, 9223372036854775807 + 1])\n    return len(xs)\n",
    "func build() -> int:\n    const xs: int[][] = [[1, 9223372036854775807 + 1], [2]]\n    return len(xs)\n",
    "record P:\n    a: int\n    b: int[]\n\nfunc build() -> int:\n    const p = P(a=1, b=[1, 9223372036854775807 + 1])\n    return len(p.b)\n",
    // Other positions: an inner block, a phi of the element, a phi of lists, a callee that always traps, a returned list,
    // a list argument, a generic body, a `fails` function.
    "func flag() -> bool:\n    return len([1]) == 1\n\nfunc build() -> int:\n    mut n = 0\n    if flag():\n        const xs: int[] = [1, 9223372036854775807 + 1]\n        n = len(xs)\n    return n\n",
    "func flag() -> bool:\n    return len([1]) == 1\n\nfunc build() -> int:\n    mut v = 1\n    if flag():\n        v = 9223372036854775807 + 1\n    const xs: int[] = [1, v]\n    return len(xs)\n",
    "func flag() -> bool:\n    return len([1]) == 1\n\nfunc build() -> int:\n    mut xs: int[] = [1]\n    if flag():\n        xs = [2, 9223372036854775807 + 1]\n    return len(xs)\n",
    "func boom() -> int:\n    return 9223372036854775807 + 1\n\nfunc build() -> int:\n    const xs: int[] = [1, boom()]\n    return len(xs)\n",
    "func make() -> int[]:\n    return [1, 9223372036854775807 + 1]\n\nfunc build() -> int:\n    return len(make())\n",
    "func count(xs: int[]) -> int:\n    return len(xs)\n\nfunc build() -> int:\n    return count([1, 9223372036854775807 + 1])\n",
    "func two[T](a: T, b: T) -> int:\n    const xs: T[] = [copy(a), copy(b)]\n    return len(xs)\n\nfunc build() -> int:\n    return two(1, 9223372036854775807 + 1)\n",
    "func inner(flag: bool) -> int fails str:\n    if flag:\n        fail \"no\"\n    const xs: int[] = [1, 9223372036854775807 + 1]\n    return len(xs)\n\n" ++
        "func build() -> int:\n    match inner(len([1]) == 0):\n        case Ok(n):\n            return n\n        case Err(_):\n            return 0\n",
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

test "trapping element: the reduced program states its list's elements as the type's range, which the validator derives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, try program(a, shapes[0]), &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const described = try export_.describe(a, a, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try text.write(a, &out, described);
    // The addition never completes: its own interval is empty, and the list that would hold it has the type's range.
    try std.testing.expect(std.mem.indexOf(u8, out.items, " aux 0 range 9223372036854775808 9223372036854775807\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "len 2 2 elems -9223372036854775808 9223372036854775807 length") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "elems 1 9223372036854775807") == null);
}

test "trapping element: every shape of a list element that always overflows has a certificate the fact validator accepts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("accepted", try certificatesAccepted(arena.allocator(), std.testing.allocator, .trusted));
    try std.testing.expectEqualStrings("accepted", try certificatesAccepted(arena.allocator(), std.testing.allocator, .verify));
}

test "trapping element: every shape of a list element that always overflows traps R_OVERFLOW through the debug and the release passes" {
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
        for ([_][]const u8{ "build", "flag", "boom", "make", "count", "two", "inner", "P" }) |name| {
            for ([_][]const u8{ "(", "[" }) |opening| {
                const from = try std.fmt.allocPrint(a, "{s}{s}", .{ name, opening });
                const to = try std.fmt.allocPrint(a, "{s}_{d}{s}", .{ name, index, opening });
                renamed = try std.mem.replaceOwned(u8, a, renamed, from, to);
            }
            const declared = try std.fmt.allocPrint(a, "record {s}:", .{name});
            renamed = try std.mem.replaceOwned(u8, a, renamed, declared, try std.fmt.allocPrint(a, "record {s}_{d}:", .{ name, index }));
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

test "trapping element: selka test reports each shape's overflow as the test's trap, not as a build error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "elements.selka", .data = try testFile(a) });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "elements.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try options.privateEnvironment(a);
    const result = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "test", source, "--json", "--cache-dir", cache }, .environ_map = &environment });
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "E_FACT_VALIDATION") == null);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try std.testing.expectEqual(shapes.len, overflowVerdicts(parsed));
}

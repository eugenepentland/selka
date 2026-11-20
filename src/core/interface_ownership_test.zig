//! The Core half of the interface oracle (W9, goal G7): a module checked against its imports' interfaces must get the
//! refusals of Core it gets in the whole program. A mutant that makes a caller's verdict read a callee's body shows the
//! comparison sees such a dependence, which the front-end half of the oracle does not; the known exceptions of goal G7
//! are named, not failed.
const std = @import("std");
const t = std.testing;
const language = @import("selka");
const oracle = language.module_interface_oracle;
const iface = language.module_interface;
const core = @import("interface_ownership.zig");

const lib_source =
    \\public func helper(x: int) -> int:
    \\    const scratch = x + 1
    \\    return scratch
    \\
    \\
    \\public func twice(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func grow(x: int) -> int:
    \\    const cells = [x, x]
    \\    return cells[0]
    \\
    \\
    \\public func first[T](xs: T[]) -> T:
    \\    const item = xs[0]
    \\    return item
    \\
    \\
    \\func steps(n: int) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total += k
    \\    return total
    \\
    \\
    \\public const TOTAL: int = steps(3)
    \\
;

const main_source =
    \\import lib
    \\
    \\
    \\@noalloc
    \\func hot(x: int) -> int:
    \\    return lib.grow(x)
    \\
    \\
    \\func main() -> int:
    \\    return lib.helper(1) + lib.twice(2) + hot(3) + lib.first([4]) + lib.TOTAL
    \\
;

/// One oracle run of the two-module project: the front end's mismatches and the differences in Core's refusals.
const Run = struct {
    /// Every front-end mismatch of the module checks, and the whole-program diagnostics no module check reported.
    front_end: usize,
    /// Core refusals the module checks made that the whole program did not.
    extra: []const oracle.Refusal,
    /// Core refusals of the whole program no module check made.
    missing: []const oracle.Refusal,
    whole: *oracle.Whole,
    set: language.module_interface_build.Set,
};

/// Run the oracle, both halves, over the project with Core's `mutant`, the way `selka interfaces oracle` does.
fn runOracle(arena: std.mem.Allocator, mutant: core.Mutant) !Run {
    const modules = [_]oracle.Override{.{ .path = "lib.selka", .bytes = lib_source }};
    var whole: *oracle.Whole = undefined;
    oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = main_source, .modules = &modules }, &whole) catch |err| {
        if (err != error.OutOfMemory) whole.deinit();
        return err;
    };
    errdefer whole.deinit();
    const reference = try whole.result(arena);
    const set = try whole.buildInterfaces();
    const list = try arena.alloc(iface.Interface, set.interfaces.len);
    for (set.interfaces, list) |interface, *decoded| decoded.* = iface.decode(arena, try iface.encode(arena, interface)) orelse return error.TestUnexpectedResult;
    var library = try oracle.Library.of(arena, list);
    const whole_refusals = try core.refusals(arena, t.allocator, .{ .program = whole.compilation.program.?, .locator = whole.locator(), .judged = try whole.judged(arena), .mutant = mutant });
    var comparisons: std.ArrayList(oracle.Comparison) = .empty;
    var singles: std.ArrayList([]const oracle.Refusal) = .empty;
    var extra: std.ArrayList(oracle.Refusal) = .empty;
    var front_end: usize = 0;
    for ([_][]const u8{ "main", "lib" }, [_][]const u8{ main_source, lib_source }) |module, bytes| {
        var single: *oracle.Single = undefined;
        try oracle.Single.open(t.allocator, .{ .module = module, .bytes = bytes, .is_entry = std.mem.eql(u8, module, "main"), .library = &library }, &single);
        defer single.deinit();
        const comparison = try oracle.compare(arena, reference, try single.result(arena, &library, module), module);
        front_end += comparison.mismatches();
        try comparisons.append(arena, comparison);
        const refusals = try core.refusals(arena, t.allocator, .{ .program = single.compilation.program.?, .locator = single.locator(&library, module), .judged = try single.judged(arena, &library, module), .mutant = mutant });
        try singles.append(arena, refusals);
        try extra.appendSlice(arena, try oracle.extraRefusals(arena, whole_refusals, refusals));
    }
    front_end += (try oracle.missingDiagnostics(arena, reference, comparisons.items)).len;
    return .{ .front_end = front_end, .extra = extra.items, .missing = try oracle.missingRefusals(arena, whole_refusals, singles.items), .whole = whole, .set = set };
}

/// The texts of `refusals` that `knownException` does not name, joined by newlines.
fn unknown(arena: std.mem.Allocator, run: Run, refusals: []const oracle.Refusal) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (refusals) |refusal| if (oracle.knownException(run.whole, run.set, refusal) == null) {
        try out.appendSlice(arena, refusal.text);
        try out.append(arena, '\n');
    };
    return out.items;
}

/// The refusal `refusals` makes with `code`, or null.
fn withCode(refusals: []const oracle.Refusal, code: []const u8) ?oracle.Refusal {
    for (refusals) |refusal| if (std.mem.eql(u8, refusal.code, code)) return refusal;
    return null;
}

/// A refusal at the first `needle` of `module`'s `text`, as `knownException` reads one.
fn refusalIn(module: []const u8, text: []const u8, needle: []const u8) oracle.Refusal {
    const start: u32 = @intCast(std.mem.indexOf(u8, text, needle).?);
    return .{ .module = module, .span = .{ .start = start, .end = start + @as(u32, @intCast(needle.len)) }, .code = "E_SINGLE_OWNER_BORROW", .text = needle };
}

// W9: locality is a tested property (goal G7).
test "W9 Core refuses a caller the same whether its callees are interfaces or sources; @noalloc is the known exception" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const run = try runOracle(arena.allocator(), .none);
    defer run.whole.deinit();
    try t.expectEqual(@as(usize, 0), run.front_end);
    // `hot`'s promise is judged over `lib.grow`'s body in the whole program, and over its interface (`pass`) when `main`
    // is checked alone: both differences are the known exception, and nothing else differs.
    try t.expectEqual(oracle.Known.noalloc, oracle.knownException(run.whole, run.set, withCode(run.missing, "E_NOALLOC_ALLOCATES").?).?);
    try t.expectEqual(oracle.Known.noalloc, oracle.knownException(run.whole, run.set, withCode(run.extra, "E_NOALLOC_ALLOCATES").?).?);
    try t.expectEqualStrings("", try unknown(arena.allocator(), run, run.missing));
    try t.expectEqualStrings("", try unknown(arena.allocator(), run, run.extra));
}

test "W9 the mutant that makes a caller's verdict read a callee's body fails the Core comparison and not the front end's" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const run = try runOracle(arena.allocator(), .callee_locals);
    defer run.whole.deinit();
    // The front-end half of the oracle sees nothing: it never runs Core.
    try t.expectEqual(@as(usize, 0), run.front_end);
    // The whole program refuses the calls of `helper` and `grow`, whose bodies declare locals; `main` checked against
    // `lib`'s interface sees `pass` there and does not. The template's and the evaluated function's bodies are kept in
    // the interface, so the mutant reads them in both checks and nothing differs there.
    const call = std.mem.indexOf(u8, main_source, "lib.helper(1)").?;
    const expected = try std.fmt.allocPrint(arena.allocator(), "main:{d}-{d} w9-mutant the call reads the body of lib::helper (W9 mutant)\n", .{ call, call + "lib.helper(1)".len });
    try t.expect(std.mem.indexOf(u8, try unknown(arena.allocator(), run, run.missing), expected) != null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, try unknown(arena.allocator(), run, run.missing), "w9-mutant"));
    try t.expectEqualStrings("", try unknown(arena.allocator(), run, run.extra));
}

test "W9 a difference inside a template, a constant or a function a constant evaluates is a known exception of G7" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const run = try runOracle(arena.allocator(), .none);
    defer run.whole.deinit();
    try t.expectEqual(oracle.Known.template, oracle.knownException(run.whole, run.set, refusalIn("lib", lib_source, "return item")).?);
    try t.expectEqual(oracle.Known.evaluated, oracle.knownException(run.whole, run.set, refusalIn("lib", lib_source, "total += k")).?);
    try t.expectEqual(oracle.Known.evaluated, oracle.knownException(run.whole, run.set, refusalIn("lib", lib_source, "steps(3)")).?);
    // Inside an ordinary body, or in another module at the same offset, a difference is new.
    try t.expectEqual(@as(?oracle.Known, null), oracle.knownException(run.whole, run.set, refusalIn("lib", lib_source, "x * 2")));
    try t.expectEqual(@as(?oracle.Known, null), oracle.knownException(run.whole, run.set, refusalIn("main", main_source, "lib.helper(1)")));
    try t.expect(std.mem.indexOf(u8, oracle.Known.noalloc.note(), "G7") != null);
}

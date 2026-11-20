//! Source ownership, direct cleanup, and rejection boundaries for zero-RC stage 1.
const std = @import("std");
const language = @import("selka");
const contract = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 comprehensions borrow managed elements and preserve sources" {
    try executes(std.testing.allocator,
        \\func lengths(values: bytes[]) -> int[]:
        \\    mut gather_result_51: int[] = []
        \\    for value in values:
        \\        const gather_value_51: int = len(value)
        \\        append(mut gather_result_51, gather_value_51)
        \\    return gather_result_51
        \\func nested(values: bytes[][]) -> int[][]:
        \\    mut gather_result_144: int[][] = []
        \\    for row in values:
        \\        mut gather_result_373: int[] = []
        \\        for value in row:
        \\            const gather_value_373: int = len(value)
        \\            append(mut gather_result_373, gather_value_373)
        \\        const gather_value_144: int[] = own gather_result_373
        \\        append(mut gather_result_144, own gather_value_144)
        \\    return gather_result_144
        \\func main(out: Stream) -> int:
        \\    const values = [b"a", b"bc", b""]
        \\    const sizes = lengths(values)
        \\    const rows = nested([[b"abcd"], [b"ef", b"g"]])
        \\    const keys = {"one": 1, "three": 3}
        \\    mut gather_result_420: int[] = []
        \\    for key in keys:
        \\        const gather_value_420: int = strings.char_count(key)
        \\        append(mut gather_result_420, gather_value_420)
        \\    const widths = gather_result_420
        \\    print(out, sizes[0], sizes[1], sizes[2], values[1][0])
        \\    print(out, rows[0][0], rows[1][1], widths[0] + widths[1])
        \\    return 0
    , "1 2 0 98\n4 1 8\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 comprehension copies and fresh results outlive inputs" {
    try executes(std.testing.allocator,
        \\import lists
        \\import strings
        \\
        \\func fresh() -> str[]:
        \\    return ["small-" + str(1), "large-" + str(22)]
        \\func main(out: Stream) -> int:
        \\    mut values = fresh()
        \\    mut gather_result_148: str[] = []
        \\    for value in values:
        \\        const gather_value_148: str = copy(value)
        \\        append(mut gather_result_148, own gather_value_148)
        \\    const saved = gather_result_148
        \\    mut gather_result_210: str[] = []
        \\    for value in values:
        \\        if strings.char_count(value) > 7:
        \\            const gather_value_210: str = copy(value)
        \\            append(mut gather_result_210, own gather_value_210)
        \\    const filtered = gather_result_210
        \\    mut gather_result_287: int[] = []
        \\    for value in fresh():
        \\        const gather_value_287: int = strings.char_count(value)
        \\        append(mut gather_result_287, gather_value_287)
        \\    const sizes = gather_result_287
        \\    const empty: str[] = []
        \\    mut gather_result_380: str[] = []
        \\    for value in empty:
        \\        const gather_value_380: str = copy(value)
        \\        append(mut gather_result_380, own gather_value_380)
        \\    const copied_empty = gather_result_380
        \\    lists.clear(mut values)
        \\    print(out, saved[0], filtered[0], sizes[1], len(copied_empty))
        \\    return 0
    , "small-1 large-22 8 0\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 comprehension element cannot escape or invalidate owner" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\func main() -> int:
        \\    const values = [b"a", b"bc"]
        \\    const escaped = [for value in values yield value]
        \\    return len(escaped)
    , "E_COMPREHENSION_REMOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = [b"a", b"bc"]
        \\    mut escaped: bytes[] = []
        \\    for value in values:
        \\        append(mut escaped, value)
        \\    append(mut escaped, b"fresh" + b"!")
        \\    return len(escaped)
    , "E_SINGLE_OWNER_OVERLAP");
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\import lists
        \\func clear(mut values: bytes[]) -> int:
        \\    lists.clear(mut values)
        \\    return 0
        \\func main() -> int:
        \\    mut values = [b"a", b"bc"]
        \\    const sizes = [for value in values yield clear(mut values) + len(value)]
        \\    return len(sizes)
    , "E_COMPREHENSION_REMOVED");
    try refuses(std.testing.allocator,
        \\import lists
        \\func clear(mut values: bytes[]) -> int:
        \\    lists.clear(mut values)
        \\    return 0
        \\func main() -> int:
        \\    mut values = [b"a", b"bc"]
        \\    mut sizes: int[] = []
        \\    for value in values:
        \\        append(mut sizes, clear(mut values) + len(value))
        \\    return len(sizes)
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 sorted and list copies own managed children" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\func main(out: Stream) -> int:
        \\    mut values = [b"bb", b"a", b"bb"]
        \\    const ordered = sorted(values)
        \\    const descending = sorted(values, reverse=True)
        \\    const copied = list(values)
        \\    values[0] = b"changed"
        \\    lists.clear(mut values)
        \\    const empty: bytes[] = []
        \\    const empty_sorted = sorted(empty)
        \\    const single = sorted(["single-" + str(1)])
        \\    print(out, ordered[0][0], ordered[1][0], descending[0][0], copied[0][0])
        \\    print(out, len(empty_sorted), single[0])
        \\    return 0
    , "97 98 98 98\n0 single-1\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 stable keyed sorting borrows callbacks and owns nested output" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\record Item:
        \\    rank: int
        \\    payload: str[]
        \\func rank(item: Item) -> int:
        \\    return item.rank
        \\func text(item: Item) -> str:
        \\    return copy(item.payload[0])
        \\func main(out: Stream) -> int:
        \\    mut values = [Item(rank=2, payload=["two"]), Item(rank=1, payload=["one"]), Item(rank=1, payload=["also"])]
        \\    const ordered = sorted(values, key=rank)
        \\    const descending = sorted(values, key=rank, reverse=True)
        \\    const by_text = sorted(values, key=text)
        \\    const copied = list(values)
        \\    values[1].payload[0] = "changed"
        \\    lists.clear(mut values)
        \\    print(out, ordered[0].payload[0], ordered[1].payload[0], descending[0].payload[0])
        \\    print(out, by_text[0].payload[0], copied[1].payload[0])
        \\    return 0
    , "one also two\nalso one\n");
}

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    return support.checkedProgram(a, source);
}

fn retiredSource(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const checked_source = try support.checkSource(arena.allocator(), source);
    try std.testing.expect(!checked_source.passed);
    try std.testing.expect(checked_source.diagnostics.len > 0);
    for (checked_source.diagnostics) |item| try std.testing.expectEqualStrings(code, item.code);
}

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(arena.allocator(), try checked(arena.allocator(), source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: contract.Failure = .{};
    contract.check(a, program, &failure) catch |err| {
        report("zero-RC source: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    const main_fn = program.functions[@backingInt(program.main)];
    const parameter_names = try a.alloc([]const u8, main_fn.signature.parameter_count);
    const capabilities = try a.alloc(u8, parameter_names.len);
    for (parameter_names, capabilities, main_fn.scope.locals[0..parameter_names.len]) |*name, *cap, local| {
        name.* = local.name;
        cap.* = local.ty.capabilityIndex() orelse 255;
    }
    inline for (.{ false, true }) |optimized| {
        if (optimized) try support.requireRelease();
        var refusal: build.Refusal = .{};
        var module = build.buildExecutable(a, .{ .program = program }, &refusal) catch |err| {
            report("zero-RC builder: {s}\n", .{refusal.reason});
            return err;
        };
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);

        const run = support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result), .main = .{ .parameters = parameter_names, .capabilities = capabilities } }) catch |err| {
            report("zero-RC execution (optimized={}):\n{s}\n", .{ optimized, try @import("print.zig").module(a, &module) });
            return err;
        };
        if (run.status != 0) report("zero-RC run:\n{s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(zero.emittedClean(run.llvm));
    }
}

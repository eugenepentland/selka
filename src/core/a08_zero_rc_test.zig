//! Source ownership, direct cleanup, and rejection boundaries for zero-RC stage 1.
const std = @import("std");
const language = @import("mylang");
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
        \\    return [for value in values yield len(value)]
        \\func nested(values: bytes[][]) -> int[][]:
        \\    return [for row in values yield [for value in row yield len(value)]]
        \\func main(out: Stream) -> int:
        \\    const values = [b"a", b"bc", b""]
        \\    const sizes = lengths(values)
        \\    const rows = nested([[b"abcd"], [b"ef", b"g"]])
        \\    const keys = {"one": 1, "three": 3}
        \\    const widths = [for key in keys yield len(key)]
        \\    out.print(sizes[0], sizes[1], sizes[2], values[1][0])
        \\    out.print(rows[0][0], rows[1][1], widths[0] + widths[1])
        \\    return 0
    , "1 2 0 98\n4 1 8\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 comprehension copies and fresh results outlive inputs" {
    try executes(std.testing.allocator,
        \\func fresh() -> str[]:
        \\    return ["small-" + str(1), "large-" + str(22)]
        \\func main(out: Stream) -> int:
        \\    mut values = fresh()
        \\    const saved = [for value in values yield value.copy()]
        \\    const filtered = [for value in values if len(value) > 7 yield value.copy()]
        \\    const sizes = [for value in fresh() yield len(value)]
        \\    const empty: str[] = []
        \\    const copied_empty = [for value in empty yield value.copy()]
        \\    values.clear()
        \\    out.print(saved[0], filtered[0], sizes[1], len(copied_empty))
        \\    return 0
    , "small-1 large-22 8 0\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 comprehension element cannot escape or invalidate owner" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = [b"a", b"bc"]
        \\    const escaped = [for value in values yield value]
        \\    return len(escaped)
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func clear(mut values: bytes[]) -> int:
        \\    values.clear()
        \\    return 0
        \\func main() -> int:
        \\    mut values = [b"a", b"bc"]
        \\    const sizes = [for value in values yield clear(mut values) + len(value)]
        \\    return len(sizes)
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 sorted and list copies own managed children" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut values = [b"bb", b"a", b"bb"]
        \\    const ordered = sorted(values)
        \\    const descending = sorted(values, reverse=True)
        \\    const copied = list(values)
        \\    values[0] = b"changed"
        \\    values.clear()
        \\    const empty: bytes[] = []
        \\    const empty_sorted = sorted(empty)
        \\    const single = sorted(["single-" + str(1)])
        \\    out.print(ordered[0][0], ordered[1][0], descending[0][0], copied[0][0])
        \\    out.print(len(empty_sorted), single[0])
        \\    return 0
    , "97 98 98 98\n0 single-1\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC A08 stable keyed sorting borrows callbacks and owns nested output" {
    try executes(std.testing.allocator,
        \\record Item:
        \\    rank: int
        \\    payload: str[]
        \\func rank(item: Item) -> int:
        \\    return item.rank
        \\func text(item: Item) -> str:
        \\    return item.payload[0].copy()
        \\func main(out: Stream) -> int:
        \\    mut values = [Item(rank=2, payload=["two"]), Item(rank=1, payload=["one"]), Item(rank=1, payload=["also"])]
        \\    const ordered = sorted(values, key=rank)
        \\    const descending = sorted(values, key=rank, reverse=True)
        \\    const by_text = sorted(values, key=text)
        \\    const copied = list(values)
        \\    values[1].payload[0] = "changed"
        \\    values.clear()
        \\    out.print(ordered[0].payload[0], ordered[1].payload[0], descending[0].payload[0])
        \\    out.print(by_text[0].payload[0], copied[1].payload[0])
        \\    return 0
    , "one also two\nalso one\n");
}

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "zero-rc.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s} at {d}: {s}\n", .{ diagnostic.code, diagnostic.span.start, diagnostic.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkMode(arena.allocator(), try checked(arena.allocator(), source), &failure, true));
    try std.testing.expectEqualStrings(code, failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: contract.Failure = .{};
    contract.checkMode(a, program, &failure, true) catch |err| {
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
        var refusal: build.Refusal = .{};
        var module = build.buildExecutable(a, .{ .program = program, .single_owner = true, .zero_rc = true }, &refusal) catch |err| {
            report("zero-RC builder: {s}\n", .{refusal.reason});
            return err;
        };
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        contract.verifyLowered(&module, &failure) catch |err| {
            report("zero-RC lowering: {s} at {d}\n{s}\n", .{ failure.message, failure.span.start, try @import("print.zig").module(a, &module) });
            return err;
        };
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

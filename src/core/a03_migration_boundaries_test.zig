//! Migration boundaries retain invalidating-borrow refusals and execute explicit
//! snapshots with source-order selection, mutation, and owned writeback.
const std = @import("std");
const language = @import("mylang");
const ownership = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "a03-migration.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}: {s}\n", .{ diagnostic.code, diagnostic.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(parent: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkMode(a, try checked(a, source), &failure, true));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: ownership.Failure = .{};
    try ownership.checkMode(a, program, &failure, true);
    const main_fn = program.functions[@backingInt(program.main)];
    const capabilities = [_]u8{main_fn.scope.locals[0].ty.capabilityIndex() orelse 255};
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = program, .single_owner = true, .zero_rc = true }, &refusal);
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        try ownership.verifyLowered(&module, &failure);
        const run = try support.runOwned(a, &module, .{
            .own = false,
            .release = optimized,
            .verify = optimized,
            .analysis = support.analysis(&result),
            .main = .{ .parameters = &.{"out"}, .capabilities = &capabilities },
        });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(zero.emittedClean(run.llvm));
    }
}

// The migrated guest tests take explicit snapshots before these writes. Their
// outputs alone cannot prove rejection of the old overlapping call windows.
// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration rejects direct child borrow and root replacement" {
    try refuses(std.testing.allocator,
        \\func hold(child: int[], mut rows: int[][]) -> int:
        \\    rows = [[9]]
        \\    return child[0]
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    return hold(rows[0], mut rows)
    );
    try refuses(std.testing.allocator,
        \\func hold(mut rows: int[][], child: int[]) -> int:
        \\    rows = [[9]]
        \\    return child[0]
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    return hold(mut rows, rows[0])
    );
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration rejects indirect child borrow and root replacement" {
    try refuses(std.testing.allocator,
        \\func replace(mut rows: int[][]) -> int:
        \\    rows = [[9]]
        \\    return 2
        \\func observe(child: int[], value: int) -> int:
        \\    return child[0] + value
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    return observe(rows[0], replace(mut rows))
    );
    try refuses(std.testing.allocator,
        \\func replace(mut rows: int[][]) -> int:
        \\    rows = [[9]]
        \\    return 2
        \\func change(mut child: int[], value: int) -> int:
        \\    child.append(value)
        \\    return child[0]
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    return change(mut rows[0], replace(mut rows))
    );
    try refuses(std.testing.allocator,
        \\func count(mut values: int[]) -> int:
        \\    values[0] += 1
        \\    return len(values)
        \\func append(mut values: int[], counted: int) -> int:
        \\    values.append(counted)
        \\    return len(values)
        \\func main() -> int:
        \\    mut values = [1]
        \\    return append(mut values, count(mut values))
    );
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration rejects direct and indirect record field invalidation" {
    try refuses(std.testing.allocator,
        \\record State:
        \\    names: int[]
        \\func hold(names: int[], mut state: State) -> int:
        \\    state.names = [9]
        \\    return names[0]
        \\func main() -> int:
        \\    mut state = State(names=[1])
        \\    return hold(state.names, mut state)
    );
    try refuses(std.testing.allocator,
        \\record State:
        \\    names: int[]
        \\func replace(mut state: State) -> int:
        \\    state = State(names=[9])
        \\    return 2
        \\func observe(names: int[], value: int) -> int:
        \\    return names[0] + value
        \\func main() -> int:
        \\    mut state = State(names=[1])
        \\    return observe(state.names, replace(mut state))
    );
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration rejects indirect dictionary entry invalidation" {
    try refuses(std.testing.allocator,
        \\func replace(mut mapping: dict[int, int[]]) -> int:
        \\    mapping[0] = [9]
        \\    return 2
        \\func observe(child: int[], value: int) -> int:
        \\    return child[0] + value
        \\func main() -> int:
        \\    mut mapping = {0: [1]}
        \\    return observe(mapping[0], replace(mut mapping))
    );
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut mapping = {1: 7, 2: 8}
        \\    mut total = 0
        \\    for key in mapping:
        \\        mapping[key] += 1
        \\        total += mapping[key]
        \\    return total
    );
}

// The copy is sequenced before replacement. A saved index also makes selection
// order explicit; the migrated call intentionally mutates independent storage.
// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration executes explicit snapshots before owner replacement" {
    try executes(std.testing.allocator,
        \\record State:
        \\    names: int[]
        \\func replace(mut rows: int[][]) -> int:
        \\    rows = [[9]]
        \\    return 2
        \\func change(mut child: int[], value: int) -> int:
        \\    child.append(value)
        \\    return child[0] * 100 + len(child)
        \\func replace_state(mut state: State) -> int:
        \\    state = State(names=[8])
        \\    return 3
        \\func observe(names: int[], value: int) -> int:
        \\    return names[0] * 100 + value
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1]]
        \\    const selected_index = 0
        \\    mut selected = rows[selected_index].copy()
        \\    const replacement = replace(mut rows)
        \\    out.print(change(mut selected, replacement))
        \\    out.print(rows[0][0])
        \\    mut state = State(names=[4])
        \\    const saved = state.names.copy()
        \\    out.print(observe(saved, replace_state(mut state)))
        \\    out.print(state.names[0])
        \\    return 0
    , "102\n9\n403\n8\n");
}

// Same-root mutable child loans remain conservatively exclusive. The source
// migration uses independent owners, not a general path-disjointness waiver.
// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration rejects multiple mutable children of one root" {
    try refuses(std.testing.allocator,
        \\func change(mut first: int[], mut second: int[]) -> Unit:
        \\    first.append(3)
        \\    second.append(4)
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    change(mut rows[0], mut rows[1])
        \\    return rows[0][1] + rows[1][1]
    );
    try refuses(std.testing.allocator,
        \\func change(mut first: dict[int, int], mut second: dict[int, int]) -> Unit:
        \\    first[1] = 13
        \\    second[1] = 17
        \\func main() -> int:
        \\    mut mapping = {0: {1: 7}, 2: {1: 8}}
        \\    change(second=mut mapping[2], first=mut mapping[0])
        \\    return mapping[0][1] + mapping[2][1]
    );
}

// Select each index once, copy in source argument order, and write back in the
// same order. This case has distinct indices and the callee cannot see the root.
// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration preserves indexed named argument order through child copies" {
    try executes(std.testing.allocator,
        \\func select(mut order: int[], index: int) -> int:
        \\    order.append(index)
        \\    return index
        \\func change(mut first: int[], mut second: int[]) -> int:
        \\    first.append(3)
        \\    second.append(4)
        \\    return first[0] * 10 + second[0]
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1], [2]]
        \\    const saved = rows.copy()
        \\    mut order: int[] = []
        \\    const second_index = select(mut order, 1)
        \\    mut second = rows[second_index].copy()
        \\    const first_index = select(mut order, 0)
        \\    mut first = rows[first_index].copy()
        \\    const observed = change(second=mut second, first=mut first)
        \\    rows[second_index] = second
        \\    rows[first_index] = first
        \\    out.print(observed, order[0], order[1], len(order))
        \\    out.print(rows[0][1], rows[1][1], len(saved[0]), len(saved[1]))
        \\    return 0
    , "12 1 0 2\n3 4 1 1\n");
}

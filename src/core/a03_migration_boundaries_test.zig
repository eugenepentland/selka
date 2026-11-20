//! Migration boundaries retain invalidating-borrow refusals and execute explicit
//! snapshots with source-order selection, mutation, and owned writeback.
const std = @import("std");
const language = @import("selka");
const ownership = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    var unit = try language.Compilation.init(a, "a03-migration.selka", source);
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
    try std.testing.expectError(error.Rejected, ownership.check(a, try checked(a, source), &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: ownership.Failure = .{};
    try ownership.check(a, program, &failure);
    const main_fn = program.functions[@backingInt(program.main)];
    const capabilities = [_]u8{main_fn.scope.locals[0].ty.capabilityIndex() orelse 255};
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{
            .program = program,
        }, &refusal);
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
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
        \\    append(mut child, value)
        \\    return child[0]
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    return change(mut rows[0], replace(mut rows))
    );
    try refuses(std.testing.allocator,
        \\func count(mut values: int[]) -> int:
        \\    values[0] += 1
        \\    return len(values)
        \\func grow(mut values: int[], counted: int) -> int:
        \\    append(mut values, counted)
        \\    return len(values)
        \\func main() -> int:
        \\    mut values = [1]
        \\    return grow(mut values, count(mut values))
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
        \\    append(mut child, value)
        \\    return child[0] * 100 + len(child)
        \\func replace_state(mut state: State) -> int:
        \\    state = State(names=[8])
        \\    return 3
        \\func observe(names: int[], value: int) -> int:
        \\    return names[0] * 100 + value
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1]]
        \\    const selected_index = 0
        \\    mut selected = copy(rows[selected_index])
        \\    const replacement = replace(mut rows)
        \\    print(out, change(mut selected, replacement))
        \\    print(out, rows[0][0])
        \\    mut state = State(names=[4])
        \\    const saved = copy(state.names)
        \\    print(out, observe(saved, replace_state(mut state)))
        \\    print(out, state.names[0])
        \\    return 0
    , "102\n9\n403\n8\n");
}

// Literal list slots have disjoint owned writeback; dynamic paths and
// dictionary receivers retain the conservative root-loan boundary.
// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC migration admits literal list children and refuses unproved paths" {
    try executes(std.testing.allocator,
        \\func change(mut first: int[], mut second: int[]) -> Unit:
        \\    append(mut first, 3)
        \\    append(mut second, 4)
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1], [2]]
        \\    change(mut rows[0], mut rows[1])
        \\    print(out, rows[0][1] + rows[1][1])
        \\    return 0
    , "7\n");
    try refuses(std.testing.allocator,
        \\func change(mut first: int[], mut second: int[]) -> Unit:
        \\    append(mut first, 3)
        \\    append(mut second, 4)
        \\func identity(index: int) -> int:
        \\    return index
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    change(mut rows[0], mut rows[identity(1)])
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
        \\    append(mut order, index)
        \\    return index
        \\func change(mut first: int[], mut second: int[]) -> int:
        \\    append(mut first, 3)
        \\    append(mut second, 4)
        \\    return first[0] * 10 + second[0]
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1], [2]]
        \\    const saved = copy(rows)
        \\    mut order: int[] = []
        \\    const second_index = select(mut order, 1)
        \\    mut second = copy(rows[second_index])
        \\    const first_index = select(mut order, 0)
        \\    mut first = copy(rows[first_index])
        \\    const observed = change(second=mut second, first=mut first)
        \\    rows[second_index] = own second
        \\    rows[first_index] = own first
        \\    print(out, observed, order[0], order[1], len(order))
        \\    print(out, rows[0][1], rows[1][1], len(saved[0]), len(saved[1]))
        \\    return 0
    , "12 1 0 2\n3 4 1 1\n");
}

//! Region allocation of ordinary managed objects: `with arena() as name:` scopes,
//! dynamic allocation redirection, the store barrier, copy-out through `escape`,
//! bulk release accounting, and the static escape rejections.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const gc = @import("gc_heap.zig");
const regions = @import("gc_regions.zig");
const values = @import("runtime_values.zig");

const list_type: values.Type = @fromBackingInt(@intCast(32));
const record_type: values.Type = @fromBackingInt(@intCast(33));
const module = "arena-managed.my";

fn run(text: []const u8, statistics: *language.vm.GcStatistics, stress: bool) !language.vm.Result {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    return compilation.executeWithOptions(t.allocator, .{
        .memory = .{ .gc = .{ .stress = stress, .statistics = statistics } },
    }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
}

fn value(text: []const u8, statistics: *language.vm.GcStatistics) !i64 {
    const outcome = try run(text, statistics, false);
    if (outcome == .trap) try t.expectEqualStrings("", outcome.trap.code);
    return outcome.value;
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const build =
    \\def build(limit: int) -> list[int]:
    \\    items: list[int] = []
    \\    for index in range(limit):
    \\        items.append(index)
    \\    return items
    \\
;

// spec: ARENA-MANAGED-1
test "ARENA-MANAGED-1 nested arenas redirect helper allocation and release each scope in bulk" {
    const source = build ++
        \\def main() -> int:
        \\    total = 0
        \\    with arena() as outer:
        \\        first = build(3)
        \\        with arena() as inner:
        \\            second = build(4)
        \\            total = total + len(second)
        \\        total = total + len(first)
        \\    return total
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 7), try value(source, &statistics));
}

// spec-case: ARENA-MANAGED-1
test "ARENA-MANAGED-1 an anonymous arena scope still bulk releases its allocations" {
    const source = build ++
        \\def main() -> int:
        \\    total = 0
        \\    with arena():
        \\        total = len(build(5))
        \\    return total
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 5), try value(source, &statistics));
}

// spec: ARENA-MANAGED-2
test "ARENA-MANAGED-2 escape copies a shared subgraph once into the enclosing region" {
    const source =
        \\def main() -> int:
        \\    kept: list[list[int]] = []
        \\    with arena() as scratch:
        \\        shared: list[int] = [7]
        \\        holder: list[list[int]] = [shared, shared]
        \\        kept = scratch.escape(holder)
        \\    return len(kept) * 10 + kept[0][0] + kept[1][0]
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 34), try value(source, &statistics));
}

// spec-case: ARENA-MANAGED-2
test "ARENA-MANAGED-2 escape preserves a cycle through a record field" {
    const source =
        \\class Node:
        \\    value: int
        \\    links: list[Node]
        \\
        \\def main() -> int:
        \\    kept: list[Node] = []
        \\    with arena() as scratch:
        \\        nodes: list[Node] = []
        \\        nodes.append(Node(value=5, links=nodes))
        \\        kept = scratch.escape(nodes)
        \\    return kept[0].value + len(kept[0].links)
    ;
    var statistics: language.vm.GcStatistics = .{};
    const outcome = try run(source, &statistics, true);
    try t.expectEqual(@as(i64, 6), outcome.value);
}

// spec-case: ARENA-MANAGED-2
test "ARENA-MANAGED-2 an escaped copy may be returned from the outermost arena scope" {
    const source = build ++
        \\def solve(limit: int) -> list[int]:
        \\    with arena() as scratch:
        \\        working = build(limit)
        \\        return scratch.escape(working)
        \\
        \\def main() -> int:
        \\    kept = solve(6)
        \\    return len(kept) * 10 + kept[5]
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 65), try value(source, &statistics));
}

// spec-case: ARENA-MANAGED-2
test "ARENA-MANAGED-2 escape shares objects that already live in the enclosing region" {
    const source =
        \\def main() -> int:
        \\    older: list[int] = [4]
        \\    kept: list[list[int]] = []
        \\    with arena() as scratch:
        \\        holder: list[list[int]] = [older]
        \\        kept = scratch.escape(holder)
        \\    older.append(5)
        \\    return len(kept[0]) * 10 + kept[0][1]
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 25), try value(source, &statistics));
}

// spec: ARENA-MANAGED-3
test "ARENA-MANAGED-3 the store barrier traps when a helper stores arena storage outward" {
    const source =
        \\def stash(outer: list[list[int]], inner: list[int]) -> None:
        \\    outer.append(inner)
        \\
        \\def main() -> int:
        \\    keeper: list[list[int]] = []
        \\    with arena() as scratch:
        \\        temp: list[int] = [1]
        \\        stash(keeper, temp)
        \\    return len(keeper)
    ;
    var statistics: language.vm.GcStatistics = .{};
    const outcome = try run(source, &statistics, false);
    try t.expectEqualStrings("R_ARENA_ESCAPE", outcome.trap.code);
}

// spec-case: ARENA-MANAGED-3
test "ARENA-MANAGED-3 the store barrier covers dictionary values written through a helper" {
    const source =
        \\def stash(outer: dict[int, list[int]], inner: list[int]) -> None:
        \\    outer[1] = inner
        \\
        \\def main() -> int:
        \\    keeper: dict[int, list[int]] = {}
        \\    with arena() as scratch:
        \\        stash(keeper, [3])
        \\    return 0
    ;
    var statistics: language.vm.GcStatistics = .{};
    const outcome = try run(source, &statistics, false);
    try t.expectEqualStrings("R_ARENA_ESCAPE", outcome.trap.code);
}

// spec: ARENA-MANAGED-4
test "ARENA-MANAGED-4 static rejections name the escaping expression the arena and the binding" {
    try reject(
        \\def main() -> int:
        \\    keeper: list[int] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    , "E_ARENA_ESCAPE");
    try reject(
        \\def solve() -> list[int]:
        \\    with arena() as scratch:
        \\        return [1, 2]
        \\
        \\def main() -> int:
        \\    return len(solve())
    , "E_ARENA_ESCAPE");
    try reject(
        \\def main() -> int:
        \\    keeper: list[list[int]] = []
        \\    with arena() as scratch:
        \\        keeper.append([1])
        \\    return 0
    , "E_ARENA_ESCAPE");
    try reject(
        \\def main() -> int:
        \\    keeper: list[list[int]] = [[0]]
        \\    with arena() as scratch:
        \\        keeper[0] = [1]
        \\    return 0
    , "E_ARENA_ESCAPE");
    try reject(
        \\def main() -> int:
        \\    counts: dict[int, list[int]] = {}
        \\    with arena() as scratch:
        \\        counts[1] = [1]
        \\    return 0
    , "E_ARENA_ESCAPE");
    try reject(
        \\class Box:
        \\    items: list[int]
        \\
        \\def main() -> int:
        \\    box = Box(items=[])
        \\    with arena() as scratch:
        \\        box.items = [1]
        \\    return 0
    , "E_ARENA_ESCAPE");
}

// spec-case: ARENA-MANAGED-4
test "ARENA-MANAGED-4 an arena binding is opaque and cannot be stored passed or renamed" {
    try reject(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        alias = scratch
        \\    return 0
    , "E_ARENA_BINDING");
    try reject(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        scratch.reset()
        \\    return 0
    , "E_ARENA_BINDING");
    try reject(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        scratch = 1
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        with arena() as inner:
        \\            keep = scratch.escape([1])
        \\    return 0
    , "E_ARENA_ESCAPE");
}

// spec-case: ARENA-MANAGED-4
test "ARENA-MANAGED-4 the escape rejection renders complete JSON provenance" {
    const source =
        \\def main() -> int:
        \\    keeper: list[int] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    ;
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const json = try language.diagnostic_output.render(t.allocator, compilation.diagnostics.items[0], compilation.src, .json);
    defer t.allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, json, .{});
    defer parsed.deinit();
    const data = parsed.value.object.get("diagnostic").?;
    try t.expectEqualStrings("E_ARENA_ESCAPE", data.object.get("code").?.string);
    try t.expectEqualStrings(
        "`[1, 2]` is assigned to `keeper`, which outlives arena `scratch`; assign `scratch.escape(...)` instead",
        data.object.get("message").?.string,
    );
    const notes = data.object.get("notes").?.array.items;
    try t.expectEqual(@as(usize, 2), notes.len);
    try t.expectEqualStrings("arena scope opened here", notes[0].object.get("message").?.string);
    try t.expectEqualStrings("value declared here", notes[1].object.get("message").?.string);
}

// spec: ARENA-MANAGED-5
test "ARENA-MANAGED-5 result propagation out of an arena releases its storage in bulk" {
    const source =
        \\def risky(flag: int) -> Result[int, int]:
        \\    if flag == 0:
        \\        return Err(7)
        \\    return Ok(flag)
        \\
        \\def solve(flag: int) -> Result[int, int]:
        \\    with arena() as scratch:
        \\        items: list[int] = [1, 2, 3]
        \\        checked = risky(flag)?
        \\        return Ok(checked + len(items))
        \\
        \\def main() -> int:
        \\    match solve(0):
        \\        case Ok(found):
        \\            return found
        \\        case Err(code):
        \\            return code
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 7), try value(source, &statistics));
}

// spec-case: ARENA-MANAGED-5
test "ARENA-MANAGED-5 a trap inside an arena releases its storage before execution teardown" {
    const source =
        \\def divide(left: int, right: int) -> int:
        \\    return left // right
        \\
        \\def main() -> int:
        \\    with arena() as scratch:
        \\        items: list[int] = [1, 2]
        \\        return divide(len(items), 0)
    ;
    var statistics: language.vm.GcStatistics = .{};
    const outcome = try run(source, &statistics, false);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
}

// spec-case: ARENA-MANAGED-5
test "ARENA-MANAGED-5 break and continue out of an arena close the scope exactly once" {
    const source = build ++
        \\def main() -> int:
        \\    total = 0
        \\    for round in range(4):
        \\        with arena() as scratch:
        \\            total = total + len(build(2))
        \\            if round == 0:
        \\                continue
        \\            if round == 2:
        \\                break
        \\    return total
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 6), try value(source, &statistics));
}

// spec: ARENA-MANAGED-6
test "ARENA-MANAGED-6 stress collection inside an arena sweeps unreachable arena objects" {
    const source =
        \\def waste() -> int:
        \\    temp: list[int] = [1, 2, 3]
        \\    return len(temp)
        \\
        \\def main() -> int:
        \\    total = 0
        \\    with arena() as scratch:
        \\        total = waste()
        \\        total = total + waste()
        \\    return total
    ;
    var statistics: language.vm.GcStatistics = .{};
    const outcome = try run(source, &statistics, true);
    try t.expectEqual(@as(i64, 6), outcome.value);
}

fn escapeScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\class Node:
        \\    value: int
        \\    links: list[Node]
        \\
        \\def grow(count: int) -> list[Node]:
        \\    nodes: list[Node] = []
        \\    for index in range(count):
        \\        nodes.append(Node(value=index, links=nodes))
        \\    return nodes
        \\
        \\def main() -> int:
        \\    kept: list[Node] = []
        \\    with arena() as scratch:
        \\        kept = scratch.escape(grow(4))
        \\    return len(kept) + kept[3].value
    ;
    var compilation = try language.Compilation.init(allocator, module, source);
    defer compilation.deinit();
    var statistics: language.vm.GcStatistics = .{};
    const outcome = compilation.executeWithOptions(allocator, .{
        .memory = .{ .gc = .{ .statistics = &statistics } },
    }) catch |err| return err;
    try t.expectEqual(@as(i64, 7), outcome.value);
}

// spec: ARENA-MANAGED-7
test "ARENA-MANAGED-7 arena scopes and escape copies unwind on every allocation failure" {
    try escapeScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), escapeScenario, .{});
}

// spec: ARENA-MANAGED-8
test "ARENA-MANAGED-8 the native backend lowers arena scopes, the barrier and escape" {
    const source =
        \\def stash(outer: list[list[int]], inner: list[int]) -> None:
        \\    outer.append(inner)
        \\
        \\def main() -> int:
        \\    kept: list[int] = []
        \\    with arena() as scratch:
        \\        inner: list[int] = [7]
        \\        holder: list[list[int]] = [inner, inner]
        \\        stash(holder, inner)
        \\        kept = scratch.escape(holder[0])
        \\    return kept[0]
    ;
    var qbe = try language.Compilation.init(t.allocator, module, source);
    defer qbe.deinit();
    const manifest = try qbe.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    for ([_][]const u8{ "myl_qbe_region_begin", "myl_qbe_region_end", "myl_qbe_region_escape", "myl_qbe_region_check", "myl_qbe_region_retains", "myl_qbe_region_restore" }) |symbol| {
        try t.expect(std.mem.indexOf(u8, manifest, symbol) != null);
    }
}

// spec-case: ARENA-MANAGED-8
test "ARENA-MANAGED-8 an arena-free program emits neither the barrier nor depth bookkeeping" {
    var qbe = try language.Compilation.init(t.allocator, module,
        \\def main() -> int:
        \\    values: list[list[int]] = []
        \\    values.append([1, 2])
        \\    return len(values)
    );
    defer qbe.deinit();
    const manifest = try qbe.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_qbe_region_check") == null);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_qbe_region_mark") == null);
}

test "arena source formatting preserves the with statement" {
    const source =
        \\def main() -> int:
        \\    total = 0
        \\    with arena() as scratch:
        \\        items: list[int] = [1, 2]
        \\        total = len(items)
        \\    return total
        \\
    ;
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source, formatted);
}

test "region depth tracks nesting and bulk release frees exactly one depth" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const outer = try heap.create(list_type, .i64, 0);
    defer outer.release(t.allocator);
    regions.begin(&heap);
    const first = try heap.create(list_type, .i64, 0);
    try t.expectEqual(@as(u32, 1), first.managed.trace.region);
    regions.begin(&heap);
    const second = try heap.create(list_type, .i64, 0);
    try t.expectEqual(@as(u32, 2), second.managed.trace.region);
    second.release(t.allocator);
    regions.end(&heap);
    try t.expectEqual(@as(u32, 1), heap.regions.depth);
    first.release(t.allocator);
    regions.end(&heap);
}

test "the store barrier rejects younger arena references and allows older ones" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const older = try heap.create(list_type, list_type, 0);
    defer older.release(t.allocator);
    const records = try heap.create(list_type, record_type, 0);
    defer records.release(t.allocator);
    regions.begin(&heap);
    const younger = try heap.create(list_type, list_type, 0);
    try t.expectError(error.ArenaEscape, heap.append(older, younger));
    try heap.append(younger, older);
    const wrapper = try values.Value.create(t.allocator, record_type, &.{younger});
    try t.expectError(error.ArenaEscape, heap.append(records, wrapper));
    try t.expect(try regions.retains(&heap, wrapper));
    try t.expect(!try regions.retains(&heap, older));
    wrapper.release(t.allocator);
    younger.release(t.allocator);
    regions.end(&heap);
}

test "escape copies arena objects once and shares older objects" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const older = try heap.create(list_type, .i64, 0);
    defer older.release(t.allocator);
    try heap.append(older, .{ .i64 = 1 });
    regions.begin(&heap);
    const holder = try heap.create(list_type, list_type, 0);
    const shared = try heap.create(list_type, list_type, 0);
    try heap.append(holder, shared);
    try heap.append(holder, shared);
    try heap.append(holder, older);
    try heap.append(shared, holder);
    const copied = try regions.escape(&heap, holder);
    defer copied.release(t.allocator);
    try t.expectEqual(@as(u32, 0), copied.managed.trace.region);
    try t.expect(copied.managed != holder.managed);
    const left = try heap.read(copied, 0);
    defer left.release(t.allocator);
    const right = try heap.read(copied, 1);
    defer right.release(t.allocator);
    try t.expect(left.managed == right.managed);
    try t.expect(left.managed != shared.managed);
    const kept = try heap.read(copied, 2);
    defer kept.release(t.allocator);
    try t.expect(kept.managed == older.managed);
    const cycle = try heap.read(left, 0);
    defer cycle.release(t.allocator);
    try t.expect(cycle.managed == copied.managed);
    holder.release(t.allocator);
    shared.release(t.allocator);
    regions.end(&heap);
}

// spec-case: ARENA-MANAGED-6
test "ARENA-MANAGED-6 noalloc still rejects arena allocation while entering a scope is free" {
    try reject(
        \\def grow() -> int:
        \\    items: list[int] = []
        \\    items.append(1)
        \\    return len(items)
        \\
        \\def constrained() -> int noalloc:
        \\    with arena() as scratch:
        \\        return grow()
        \\
        \\def main() -> int:
        \\    return constrained()
    , "E_EFFECT_BOUND");
    const source =
        \\def empty() -> int noalloc:
        \\    with arena() as scratch:
        \\        return 7
        \\
        \\def main() -> int:
        \\    return empty()
    ;
    var statistics: language.vm.GcStatistics = .{};
    try t.expectEqual(@as(i64, 7), try value(source, &statistics));
    try t.expectEqual(@as(u64, 1), statistics.arena.scopes);
}

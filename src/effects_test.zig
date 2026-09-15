//! Focused effect-inference regressions, including M1 mutation footprints and ceilings.
const fixture_path = "effects.my";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const sets = @import("effect_set.zig");
const typed = @import("typed.zig");
const callables = @import("callables.zig");
const lower = @import("lower.zig");
const bytecode_model = @import("bytecode_model.zig");
const effect_engine = @import("effects.zig");
fn reject(source: []const u8, code: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, text) != null);
    if (std.mem.eql(u8, code, "E_EFFECT_BOUND")) try t.expect(c.diagnostics.items[0].related != null);
}
fn result(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

const allocate_body = "def allocate() -> int:\n    items: list[int] = []\n    return len(items)\n\n";
// spec: OWN-11
test "direct and transitive allocation violate explicit bounds with witness paths" {
    try reject("def main() -> int noalloc:\n    items: list[int] = []\n    return len(items)\n", "E_EFFECT_BOUND", "main");
    try reject(allocate_body ++ "def helper() -> int:\n    return allocate()\n\n" ++
        "def main() -> int noalloc:\n    return helper()\n", "E_EFFECT_BOUND", "main -> helper -> allocate");
    try reject("def unused() -> int effects():\n    items: list[int] = []\n    return len(items)\n\n" ++
        "def main() -> int:\n    return 0\n", "E_EFFECT_BOUND", "unused");
}

const recursive_a = "def a(n: int) -> int:\n    if n == 0:\n        items: list[int] = []\n        return len(items)\n    return b(n - 1)\n\n";
const recursive_b = "def b(n: int) -> int:\n    return a(n)\n\n";
const recursive_main = "def main() -> int noalloc:\n    return b(0)\n";
test "recursive effect summaries reach fixed points independent of declaration order" {
    try reject(recursive_a ++ recursive_b ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try reject(recursive_b ++ recursive_a ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try result("def a(n: int) -> int noalloc:\n    if n == 0:\n        return 7\n    return b(n - 1)\n\n" ++
        "def b(n: int) -> int effects():\n    return a(n)\n\n" ++
        "def main() -> int noalloc:\n    return b(3)\n", 7);
}

test "effect scanning includes untaken branches and short circuit operands" {
    try reject("def main() -> int noalloc:\n    if False:\n        items: list[int] = []\n        return len(items)\n    return 0\n", "E_EFFECT_BOUND", "main");
    try reject("def allocate() -> bool:\n    items: list[int] = []\n    return len(items) == 0\n\n" ++
        "def main() -> int noalloc:\n    _ = False and allocate()\n    return 0\n", "E_EFFECT_BOUND", "main -> allocate");
}

test "effect bounds reject unknown and duplicate names and noio permits allocation" {
    try reject("def main() -> i64 effects(magic):\n    return 0\n", "E_UNKNOWN_EFFECT", "unknown effect");
    try reject("def main() -> i64 effects(clock, clock):\n    return 0\n", "E_DUPLICATE_EFFECT", "more than once");
    try result("def main() -> int noio:\n    items: list[int] = []\n    items.append(9)\n    return items[0]\n", 9);
    try result(
        \\def main() -> i64 effects(filesystem, network, clock, random, environment):
        \\    x = 1
        \\    x += 2
        \\    return x
    , 3);
    try result(
        \\def noalloc() -> i64:
        \\    effects = 2
        \\    noio = 3
        \\    return effects + noio
        \\
        \\
        \\def main() -> i64:
        \\    return noalloc()
    , 5);
}

const accepted = "def edit(n: int) -> int noalloc:\n    return n + 11\n\n" ++
    "def release(n: int) -> int effects():\n    _ = n\n    return 3\n\n" ++
    "def main() -> int effects(managed_allocation):\n    items: list[int] = []\n" ++
    "    items.append(edit(0))\n    return items[0] + release(items[0])\n";
test "noalloc permits scalar edits while the managed caller declares its allocation" {
    try result(accepted, 14);
    var c = try language.Compilation.init(t.allocator, fixture_path, accepted);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(@as(sets.Mask, 0), c.program.?.functions[0].policy.effects);
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
    const dump = try c.dump(t.allocator);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "effects {managed_allocation} allowed {managed_allocation}") != null);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, accepted);
    defer c.deinit();
    try c.emit();
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    var found = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, allocate_body ++
        "def main() -> int noalloc:\n    return allocate()\n");
    defer c.deinit();
    c.check() catch |err| switch (err) {
        error.SourceError => {
            const rendered = try c.diagnostics.items[0].render(allocator, c.src);
            defer allocator.free(rendered);
            return;
        },
        else => return err,
    };
    return error.TestUnexpectedResult;
}
test "effect graph inference witnesses emission and rendering release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    try t.checkAllAllocationFailures(no_resize.allocator(), rejectionScenario, .{});
}

test "duplicate discovery retains normalized declared effect contracts" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def a(n: i64) -> i64 effects(clock, random):
        \\    return n + 1
        \\
        \\
        \\def b(x: i64) -> i64 effects(random, clock):
        \\    return x + 1
        \\
        \\
        \\def different(n: i64) -> i64 noalloc:
        \\    return n + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
}

test "effect rendering propagates a full writer failure" {
    var storage: [0]u8 = .{};
    var writer: std.Io.Writer = .fixed(&storage);
    try t.expectError(error.WriteFailed, sets.write(&writer, sets.bit(.managed_allocation)));
}

// spec-case: EFFECT-CEILING-1
test "declared ceilings reject hidden effects through generic and callback calls" {
    // A generic body that hides an allocating call behind an empty ceiling rejects
    // once it is instantiated, exactly like an ordinary direct call.
    try reject(
        \\def allocate() -> i64:
        \\    items: list[i64] = []
        \\    return len(items)
        \\
        \\
        \\def wrapper[T](x: T) -> i64 effects():
        \\    _ = x
        \\    return allocate()
        \\
        \\
        \\def main() -> i64 noalloc:
        \\    return wrapper[i64](1)
    , "E_EFFECT_BOUND", "exceeds declared bound");

    // Invoking a callback uses the destination contract's ceiling, so a caller
    // that promises less than the callback's declared effects rejects.
    try reject(
        \\def tick(x: i64) -> i64 effects(clock):
        \\    _ = x
        \\    return 0
        \\
        \\
        \\def call(f: def(i64) -> i64 effects(clock)) -> i64 effects():
        \\    return f(1)
        \\
        \\
        \\def main() -> i64:
        \\    return call(tick)
    , "E_EFFECT_BOUND", "exceeds declared bound");
}

// spec: MUTATION-METADATA-1
test "M1 direct input writes carry mutation facts while reads do not" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(values: list[int]) -> None effects():
        \\    values[0] = 1
        \\
        \\
        \\def peek(values: list[int]) -> int effects():
        \\    return values[0]
        \\
        \\
        \\def main() -> int effects(managed_allocation):
        \\    values = [7]
        \\    touch(values)
        \\    return peek(values)
    );
    defer c.deinit();
    try c.check();
    var touch_found = false;
    var peek_found = false;
    for (c.program.?.functions) |function| {
        if (std.mem.eql(u8, function.name, "touch")) {
            touch_found = true;
            try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
            try t.expect(function.signature.mutation_facts.writes);
        } else if (std.mem.eql(u8, function.name, "peek")) {
            peek_found = true;
            try t.expectEqual(@as(usize, 0), function.signature.mutates.len);
            try t.expect(!function.signature.mutation_facts.writes);
        }
    }
    try t.expect(touch_found and peek_found);
}

test "M1 mutates clause parses normalizes and publishes checked metadata" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(values: list[int]) -> None effects(mutation) mutates(values):
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    try c.emit();
    var found = false;
    for (c.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "touch")) continue;
        found = true;
        try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        try t.expectEqualSlices(u16, &.{0}, function.signature.declared_mutates);
        try t.expect(function.signature.mutation_facts.writes);
        try t.expect((function.policy.effect_bound.?.allowed & sets.bit(.mutation)) != 0);
    }
    try t.expect(found);
}

test "M1 mutates errors are declaration-site diagnostics" {
    try reject(
        \\def touch(values: list[int]) -> None effects(mutation) mutates(missing):
        \\    values.append(1)
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    , "E_UNKNOWN_MUTATES", "binder");
    try reject(
        \\def touch(values: list[int]) -> None effects() mutates(values):
        \\    _ = values
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    , "E_MUTATES_EFFECT", "mutation effect");
}

test "M1 definitely fresh local construction does not require mutation permission" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def main() -> int effects(managed_allocation):
        \\    values = [7]
        \\    values.append(8)
        \\    return values[0]
    );
    defer c.deinit();
    try c.check();
    try c.emit();
    try t.expectEqual(@as(usize, 0), c.program.?.functions[0].signature.mutates.len);
    try t.expect((c.program.?.functions[0].policy.effects & sets.bit(.mutation)) == 0);
}

test "M1 unused generic body accepts a direct mutation fact without enforcing M2" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch[T](values: list[T], item: T) -> None effects():
        \\    values[0] = item
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.syntax.?.functions) |function| {
        if (!std.mem.eql(u8, c.src.text(function.name), "touch")) continue;
        found = true;
        try t.expect(function.signature.inferred_mutation_writes);
        try t.expectEqualSlices(u16, &.{0}, function.signature.inferred_mutates);
    }
    try t.expect(found);
    try c.emit();
}

test "M1 callback body carries its direct mutation fact" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def apply(f: def(values: list[int]) -> None effects()) -> None effects():
        \\    _ = f
        \\
        \\
        \\def main() -> int effects(managed_allocation):
        \\    apply(lambda values: values.clear())
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.program.?.functions) |function| {
        if (!std.mem.startsWith(u8, function.name, "lambda@")) continue;
        found = true;
        try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        try t.expect(function.signature.mutation_facts.writes);
    }
    try t.expect(found);
}

test "M1 callable assignability accepts narrower mutation footprints and return origins" {
    const parameters = [_]typed.Type{.i64};
    const destination = typed.Callable{
        .parameters = &parameters,
        .return_type = .i64,
        .effects = sets.bit(.mutation) | sets.bit(.clock),
        .mutates = &[_]u16{ 0, 1 },
        .return_origin = .{ .params = &[_]u16{ 0, 1 } },
    };
    const implementation = typed.Callable{
        .parameters = &parameters,
        .return_type = .i64,
        .effects = 0,
        .mutates = &[_]u16{1},
        .return_origin = .{ .params = &[_]u16{0} },
    };
    try t.expect(callables.assignable(implementation, destination));
    try t.expect(!callables.assignable(.{
        .parameters = &parameters,
        .return_type = .i64,
        .effects = 0,
        .mutates = &[_]u16{1},
        .return_origin = .unknown,
    }, destination));
    try t.expect(callables.originSubset(.fresh, destination.return_origin));
}

test "M1 forged or missing IR mutation summaries reject" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(values: list[int]) -> None effects():
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int effects(managed_allocation):
        \\    values = [7]
        \\    touch(values)
        \\    return values[0]
    );
    defer c.deinit();
    try c.check();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try lower.lower(arena.allocator(), c.program.?);
    var forged = false;
    for (@constCast(program.functions)) |*function| {
        if (!std.mem.eql(u8, function.name, "touch")) continue;
        function.signature.mutation_facts = .{};
        function.signature.mutates = &.{};
        forged = true;
    }
    try t.expect(forged);
    try t.expectError(error.InternalError, effect_engine.validate(t.allocator, program));
}

test "M1 callback mutates metadata survives source checking and callable interning" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def apply(f: def(values: list[int]) -> None effects(mutation) mutates(values)) -> None effects():
        \\    _ = f
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.program.?.records) |record| {
        const contract = record.contract.callback orelse continue;
        if (contract.mutates.len == 1 and contract.mutates[0] == 0) found = true;
    }
    try t.expect(found);
}

test "M1 mutates metadata survives AST copy and relocation" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def apply(f: def(values: list[int]) -> None effects(mutation) mutates(values)) -> None effects():
        \\    _ = f
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const copied = try @import("ast_copy.zig").clone(arena.allocator(), c.syntax.?);
    try t.expectEqual(@as(usize, 1), copied.types.expressions.callbacks.len);
    const callback = copied.types.expressions.callbacks[0];
    try t.expectEqualSlices(u16, &.{0}, callback.mutates);
    try t.expectEqual(@as(usize, 1), callback.parameter_names.len);
    try t.expect(callback.parameter_names[0] != null);
}

test "M1 effect enum appends mutation without moving existing bits" {
    try t.expectEqual(@as(sets.Mask, 0x1ff), sets.all);
    try t.expectEqual(@as(usize, 9), std.meta.tags(sets.Effect).len);
    try t.expectEqual(@as(sets.Mask, 1 << 7), sets.bit(.output));
    try t.expectEqual(@as(sets.Mask, 1 << 8), sets.bit(.mutation));
}

const mutation_forms =
    \\def slot(values: list[int]) -> None effects():
    \\    values[0] = 1
    \\
    \\
    \\def augment(values: list[int]) -> None effects():
    \\    values[0] += 1
    \\
    \\
    \\def append(values: list[int]) -> None effects(managed_allocation):
    \\    values.append(1)
    \\
    \\
    \\def extend(values: list[int], other: list[int]) -> None effects(managed_allocation):
    \\    values.extend(other)
    \\
    \\
    \\def insert(values: list[int]) -> None effects(managed_allocation):
    \\    values.insert(0, 1)
    \\
    \\
    \\def remove(values: list[int]) -> None effects():
    \\    values.remove(1)
    \\
    \\
    \\def pop(values: list[int]) -> None effects():
    \\    _ = values.pop()
    \\
    \\
    \\def clear(values: list[int]) -> None effects():
    \\    values.clear()
    \\
    \\
    \\def reverse(values: list[int]) -> None effects():
    \\    values.reverse()
    \\
    \\
    \\def sort(values: list[int]) -> None effects():
    \\    values.sort()
    \\
    \\
    \\def update(mapping: dict[str, int]) -> None effects(managed_allocation):
    \\    mapping["answer"] = 1
    \\
    \\
    \\def delete(mapping: dict[str, int]) -> None effects(managed_allocation):
    \\    _ = mapping.pop("answer")
    \\
    \\
    \\def set_cell(cell: Cell[int]) -> None effects():
    \\    cell.value = 1
    \\
    \\
    \\def main() -> int effects():
    \\    return 0
;

test "M1 every managed write form contributes a mutation fact" {
    var c = try language.Compilation.init(t.allocator, fixture_path, mutation_forms);
    defer c.deinit();
    try c.check();
    const expected = [_][]const u8{ "slot", "augment", "append", "extend", "insert", "remove", "pop", "clear", "reverse", "sort", "update", "delete", "set_cell" };
    for (expected) |name| {
        var found = false;
        for (c.program.?.functions) |function| {
            if (!std.mem.eql(u8, function.name, name)) continue;
            found = true;
            try t.expect(function.signature.mutation_facts.writes);
            try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        }
        try t.expect(found);
    }
}

test "M1 mutates clause normalizes duplicate names to sorted positions" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(a: list[int], b: list[int]) -> None effects(mutation) mutates(b, a, b):
        \\    a[0] = 1
        \\    b[0] = 2
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    for (c.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "touch")) continue;
        try t.expectEqualSlices(u16, &.{ 0, 1 }, function.signature.declared_mutates);
        try t.expectEqualSlices(u16, &.{ 0, 1 }, function.signature.mutates);
    }
}

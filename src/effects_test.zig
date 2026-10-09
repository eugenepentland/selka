//! Focused effect-inference regressions, including M1 mutation footprints and ceilings.
const fixture_path = "effects.my";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const sets = @import("effect_set.zig");
const typed = @import("typed.zig");
const callables = @import("callables.zig");
const effect_engine = @import("effects.zig");
/// Stable code for the call-site `&` marker diagnostic exercised below.
const marker_code = "E_MUTATION_MARKER";
fn firstError(items: []const language.diagnostic.Diagnostic) ?language.diagnostic.Diagnostic {
    for (items) |item| if (item.severity == .err) return item;
    return null;
}
fn reject(source: []const u8, code: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const diag = firstError(c.diagnostics.items) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, text) != null);
    if (std.mem.eql(u8, code, "E_EFFECT_BOUND")) try t.expect(diag.related != null);
}
fn result(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}
fn accept(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try c.check();
}
/// Check one source and return its first error. The message is copied out
/// because the compilation arena is released with the compilation.
fn markerError(source: []const u8) !struct { code: []const u8, message: []u8 } {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const diag = firstError(c.diagnostics.items) orelse return error.TestUnexpectedResult;
    return .{ .code = diag.code, .message = try t.allocator.dupe(u8, diag.message) };
}

const allocate_body = "func allocate() -> int:\n    mut items: int[] = []\n    return len(items)\n\n";
// spec: OWN-11
test "direct and transitive allocation violate explicit bounds with witness paths" {
    try reject("func main() -> int effects():\n    mut items: int[] = []\n    return len(items)\n", "E_EFFECT_BOUND", "main");
    try reject(allocate_body ++ "func helper() -> int:\n    return allocate()\n\n" ++
        "func main() -> int effects():\n    return helper()\n", "E_EFFECT_BOUND", "main -> helper -> allocate");
    try reject("func unused() -> int effects():\n    mut items: int[] = []\n    return len(items)\n\n" ++
        "func main() -> int:\n    return 0\n", "E_EFFECT_BOUND", "unused");
}

const recursive_a = "func a(n: int) -> int:\n    if n == 0:\n        mut items: int[] = []\n        return len(items)\n    return b(n - 1)\n\n";
const recursive_b = "func b(n: int) -> int:\n    return a(n)\n\n";
const recursive_main = "func main() -> int effects():\n    return b(0)\n";
test "recursive effect summaries reach fixed points independent of declaration order" {
    try reject(recursive_a ++ recursive_b ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try reject(recursive_b ++ recursive_a ++ recursive_main, "E_EFFECT_BOUND", "main -> b -> a");
    try result("func a(n: int) -> int noalloc:\n    if n == 0:\n        return 7\n    return b(n - 1)\n\n" ++
        "func b(n: int) -> int effects():\n    return a(n)\n\n" ++
        "func main() -> int noalloc:\n    return b(3)\n", 7);
}

test "effect scanning includes untaken branches and short circuit operands" {
    try reject("func main() -> int effects():\n    if False:\n        mut items: int[] = []\n        return len(items)\n    return 0\n", "E_EFFECT_BOUND", "main");
    try reject("func allocate() -> bool:\n    mut items: int[] = []\n    return len(items) == 0\n\n" ++
        "func main() -> int effects():\n    _ = False and allocate()\n    return 0\n", "E_EFFECT_BOUND", "main -> allocate");
}

test "effect bounds reject unknown and duplicate names and noio permits allocation" {
    try reject("func main() -> int effects(magic):\n    return 0\n", "E_UNKNOWN_EFFECT", "unknown effect");
    try reject("func main() -> int effects(clock, clock):\n    return 0\n", "E_DUPLICATE_EFFECT", "more than once");
    try result("func main() -> int noio:\n    mut items: int[] = []\n    items.append(9)\n    return items[0]\n", 9);
    try result(
        \\func main() -> i64:
        \\    mut x = 1
        \\    x += 2
        \\    return x
    , 3);
    try result(
        \\func noalloc() -> i64:
        \\    mut effects = 2
        \\    mut noio = 3
        \\    return effects + noio
        \\
        \\
        \\func main() -> i64:
        \\    return noalloc()
    , 5);
}

const accepted = "func edit(n: int) -> int noalloc:\n    return n + 11\n\n" ++
    "func release(n: int) -> int effects():\n    _ = n\n    return 3\n\n" ++
    "func main() -> int effects(managed_allocation):\n    mut items: int[] = []\n" ++
    "    items.append(edit(0))\n    return items[0] + release(items[0])\n";
test "noalloc permits scalar edits while the managed caller declares its allocation" {
    try result(accepted, 14);
    var c = try language.Compilation.init(t.allocator, fixture_path, accepted);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(sets.Mask, 0), c.program.?.functions[0].policy.effects);
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, accepted);
    defer c.deinit();
    try c.check();
    try t.expectEqual(sets.bit(.managed_allocation), c.program.?.functions[2].policy.effects);
    var found = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, allocate_body ++
        "func main() -> int effects():\n    return allocate()\n");
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
        \\func a(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\func b(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\func different(n: i64) -> i64 noalloc:
        \\    return n + 1
        \\
        \\
        \\func main() -> i64:
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

// spec: EFFECT-CEILING-1
test "declared ceilings reject hidden effects through generic and callback calls" {
    // A generic body that hides an allocating call behind an empty ceiling rejects
    // once it is instantiated, exactly like an ordinary direct call.
    try reject(
        \\func allocate() -> i64:
        \\    mut items: i64[] = []
        \\    return len(items)
        \\
        \\
        \\func wrapper[T](x: T) -> i64 effects():
        \\    _ = x
        \\    return allocate()
        \\
        \\
        \\func main() -> i64 effects():
        \\    return wrapper[i64](1)
    , "E_EFFECT_BOUND", "exceeds declared bound");

    // Invoking a callback uses the destination contract's ceiling, so a caller
    // that promises less than the callback's declared effects rejects.
    try reject(
        \\func call(f: func(i64) -> i64 effects(clock)) -> i64 effects():
        \\    return f(1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_EFFECT_BOUND", "exceeds declared bound");
}

// spec: MUTATION-METADATA-1
test "M1 direct input writes carry mutation facts while reads do not" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func peek(values: int[]) -> int effects():
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [7]
        \\    touch(mut values)
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
            try t.expect(function.signature.inferred.writes);
        } else if (std.mem.eql(u8, function.name, "peek")) {
            peek_found = true;
            try t.expectEqual(@as(usize, 0), function.signature.mutates.len);
            try t.expect(!function.signature.inferred.writes);
        }
    }
    try t.expect(touch_found and peek_found);
}

test "M1 mutates clause parses normalizes and publishes checked metadata" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch(mut values: int[]) -> Unit effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "touch")) continue;
        found = true;
        try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        try t.expectEqualSlices(u16, &.{0}, function.signature.declared_mutates);
        try t.expect(function.signature.inferred.writes);
        try t.expect((function.policy.effect_bound.?.allowed & sets.bit(.mutation)) != 0);
    }
    try t.expect(found);
}

// spec: MUT-PARAM-5
test "M1 the mutates clause is a removed spelling naming mut" {
    try reject(
        \\def touch(values: list[int]) -> None effects(mutation) mutates(values):
        \\    values.append(1)
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    , "E_REMOVED_SPELLING", "mark each written parameter `name: mut T`");
}

// spec-case: MUT-PARAM-5
test "M1 the ampersand argument marker is a removed spelling naming mut" {
    try reject(
        \\def touch(values: mut list[int]) -> None effects(mutation):
        \\    values.append(1)
        \\
        \\
        \\def main() -> int effects():
        \\    values = [1]
        \\    touch(&values)
        \\    return 0
    , "E_REMOVED_SPELLING", "write `mut value`");
}

const marker_direct_valid =
    \\func touch(mut values: int[]) -> Unit effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(mut values)
    \\    return values[0]
;

const marker_keyword_valid =
    \\func touch(mut values: int[], item: int) -> Unit effects(mutation):
    \\    values[0] = item
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(item=1, values=mut values)
    \\    return 0
;

const marker_missing =
    \\func touch(values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(values)
    \\    return 0
;

const marker_multi_missing =
    \\func touch(mut values: int[], item: int) -> Unit effects(mutation):
    \\    values[0] = item
    \\
    \\
    \\func main() -> int effects(managed_allocation):
    \\    mut values = [7]
    \\    touch(values, 1)
    \\    return 0
;

const marker_extra =
    \\func peek(values: int[]) -> int effects():
    \\    return values[0]
    \\
    \\
    \\func main() -> int effects(managed_allocation):
    \\    mut values = [7]
    \\    return peek(mut values)
;

const marker_non_lvalue =
    \\func touch(mut values: int[]) -> Unit effects(mutation, managed_allocation):
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int effects(managed_allocation):
    \\    touch(mut [1, 2, 3])
    \\    return 0
;

const marker_unused =
    \\func touch(mut values: int[]) -> Unit effects():
    \\    return
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(mut values)
    \\    return 0
;

const marker_indirect_valid =
    \\func touch(mut values: int[]) -> Unit effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\func apply(f: func(mut values: int[]) -> Unit effects(mutation), mut values: int[]) -> Unit effects(mutation):
    \\    f(mut values)
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    apply(touch, mut values)
    \\    return 0
;

const marker_indirect_missing =
    \\func touch(mut values: int[]) -> Unit effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\func apply(f: func(mut values: int[]) -> Unit effects(mutation), mut values: int[]) -> Unit effects(mutation):
    \\    f(values)
    \\
    \\
    \\func main() -> int effects(managed_allocation):
    \\    mut values = [7]
    \\    apply(touch, mut values)
    \\    return 0
;

// spec-case: MUT-PARAM-1
test "M4 the missing-marker paste is the whole call with only that argument marked" {
    const diag = try markerError(marker_multi_missing);
    defer t.allocator.free(diag.message);
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "write `(mut values, 1)`") != null);
}

// spec-case: MUT-PARAM-1
test "M4 the unneeded-marker paste is the call without the marker and names the argument" {
    const diag = try markerError(marker_extra);
    defer t.allocator.free(diag.message);
    try t.expect(std.mem.indexOf(u8, diag.message, "remove `mut`: `(values)`") != null);
}

// spec: MUT-PARAM-1
test "M4 a call-site mut marker on a declared mut position is accepted" {
    try accept(marker_direct_valid);
    try accept(marker_keyword_valid);
}

// spec-case: MUT-PARAM-1
test "M4 ordinary parameters reject writes as readonly snapshots" {
    try reject(marker_missing, "E_IMMUTABLE", "read-only");
}

// spec-case: MUT-PARAM-1
test "M4 a mut marker on a position the callee does not write is rejected" {
    const diag = try markerError(marker_extra);
    defer t.allocator.free(diag.message);
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "`peek` does not write `values`; remove `mut`") != null);
}

// spec-case: MUT-PARAM-1
test "M4 a mut marker on a non-lvalue is rejected" {
    const diag = try markerError(marker_non_lvalue);
    defer t.allocator.free(diag.message);
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "assignable") != null);
}

// spec-case: MUT-PARAM-1
test "M4 a callable-value call enforces the callback mut parameter set" {
    try accept(marker_indirect_valid);
    const missing = try markerError(marker_indirect_missing);
    defer t.allocator.free(missing.message);
    try t.expectEqualStrings(marker_code, missing.code);
}

// spec-case: MUT-PARAM-2
test "M4 a declared mut capability may be unused" {
    try accept(marker_unused);
}

test "M1 definitely fresh local construction does not require mutation permission" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func main() -> int:
        \\    mut values = [7]
        \\    values.append(8)
        \\    return values[0]
    );
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(usize, 0), c.program.?.functions[0].signature.mutates.len);
    try t.expect((c.program.?.functions[0].policy.effects & sets.bit(.mutation)) == 0);
}

// spec-case: MUTATION-METADATA-1
test "M2 unused generic body enforces its declared mutation contract" {
    try reject(
        \\func touch[T](mut values: T[], item: T) -> Unit effects():
        \\    values[0] = item
        \\
        \\
        \\func main() -> int effects():
        \\    return 0
    , "E_MUTATION_PERMISSION", "generic");
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch[T](mut values: T[], item: T) -> Unit effects(mutation):
        \\    values[0] = item
        \\
        \\
        \\func main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.syntax.?.functions) |function| {
        if (!std.mem.eql(u8, c.src.text(function.name), "touch")) continue;
        found = true;
        try t.expect(function.signature.inferred.mutation_writes);
        try t.expectEqualSlices(u16, &.{0}, function.signature.inferred.mutates);
    }
    try t.expect(found);
}

test "M1 callback body carries its direct mutation fact" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func apply(f: func(mut values: int[]) -> Unit effects(mutation)) -> Unit effects():
        \\    _ = f
        \\
        \\
        \\func main() -> int:
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
        try t.expect(function.signature.inferred.writes);
    }
    try t.expect(found);
}

test "M1 callable assignability requires exact mut positions and permits narrower effects" {
    const parameters = [_]typed.Type{ .i64, .i64 };
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
        .mutates = &[_]u16{ 0, 1 },
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

test "M1 callback mutates metadata survives source checking and callable interning" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func apply(f: func(mut values: int[]) -> Unit effects(mutation)) -> Unit effects():
        \\    _ = f
        \\
        \\
        \\func main() -> int effects():
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
        \\func apply(f: func(mut values: int[]) -> Unit effects(mutation)) -> Unit effects():
        \\    _ = f
        \\
        \\
        \\func main() -> int effects():
        \\    return 0
    );
    defer c.deinit();
    try c.parse();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const copied = try @import("ast_copy.zig").clone(arena.allocator(), c.syntax.?);
    try t.expectEqual(@as(usize, 1), copied.types.expressions.callbacks.len);
    const callback = copied.types.expressions.callbacks[0];
    try t.expectEqual(@as(usize, 1), callback.parameter_modes.mut.len);
    try t.expect(callback.parameter_modes.mut[0]);
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
    \\func slot(mut values: int[]) -> Unit effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\func augment(mut values: int[]) -> Unit effects(mutation):
    \\    values[0] += 1
    \\
    \\
    \\func append(mut values: int[]) -> Unit:
    \\    values.append(1)
    \\
    \\
    \\func extend(mut values: int[], other: int[]) -> Unit:
    \\    values.extend(other)
    \\
    \\
    \\func insert(mut values: int[]) -> Unit:
    \\    values.insert(0, 1)
    \\
    \\
    \\func remove(mut values: int[]) -> Unit effects(mutation):
    \\    values.remove(1)
    \\
    \\
    \\func pop(mut values: int[]) -> Unit effects(mutation):
    \\    _ = values.pop()
    \\
    \\
    \\func clear(mut values: int[]) -> Unit effects(mutation):
    \\    values.clear()
    \\
    \\
    \\func reverse(mut values: int[]) -> Unit effects(mutation):
    \\    values.reverse()
    \\
    \\
    \\func sort(mut values: int[]) -> Unit effects(mutation):
    \\    values.sort()
    \\
    \\
    \\func update(mut mapping: dict[str, int]) -> Unit:
    \\    mapping["answer"] = 1
    \\
    \\
    \\func delete(mut mapping: dict[str, int]) -> Unit:
    \\    _ = mapping.pop("answer")
    \\
    \\
    \\func set_cell(mut cell: Cell[int]) -> Unit effects(mutation):
    \\    cell.value = 1
    \\
    \\
    \\func main() -> int effects():
    \\    return 0
;

test "M1 mutates clause normalizes duplicate names to sorted positions" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch(mut a: int[], mut b: int[]) -> Unit:
        \\    a[0] = 1
        \\    b[0] = 2
        \\
        \\
        \\func main() -> int effects():
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

// spec: MUT-PARAM-4
test "M2 a mut parameter with no mutation ceiling still exceeds its contract" {
    try reject(
        \\func touch(mut values: int[]) -> Unit effects(managed_allocation):
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUT-PARAM-4
test "M2 a mut footprint accepts an independent read-only snapshot" {
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit effects(mutation):
        \\    dst[0] = src[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values, values)
        \\    return 0
    );
    // Each read-only argument is an independent snapshot, including a
    // second local copied from the same source.
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit effects(mutation):
        \\    dst[0] = src[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut alias = values
        \\    touch(mut values, alias)
        \\    return 0
    );
    try result(
        \\func touch(mut dst: int[], src: int[]) -> Unit effects(mutation):
        \\    dst[0] = src[0] + 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut snapshot = values.copy()
        \\    touch(mut values, snapshot)
        \\    return values[0]
    , 2);
}

/// Two families of mutually recursive classes, `Expr` over three node classes
/// and `Heap` over three object classes with four fields each, up to the last
/// field of `Obj2`; `recursive_graphs_tail` closes them with a
/// `count(state: mut State, e: Expr)` that makes the overlap proof walk both.
const recursive_graphs_head =
    \\class Node0:
    \\    left: Expr
    \\    right: Expr
    \\    items: Expr[]
    \\    extra: Expr[]
    \\
    \\class Node1:
    \\    left: Expr
    \\    right: Expr
    \\    items: Expr[]
    \\    extra: Expr[]
    \\
    \\class Node2:
    \\    left: Expr
    \\    right: Expr
    \\    items: Expr[]
    \\    extra: Expr[]
    \\
    \\enum Expr:
    \\    leaf(value: int)
    \\    n0(value: Node0)
    \\    n1(value: Node1)
    \\    n2(value: Node2)
    \\
    \\class Obj0:
    \\    next: Heap
    \\    values: float[]
    \\    more: Heap[]
    \\    extra: Heap[]
    \\
    \\class Obj1:
    \\    next: Heap
    \\    values: float[]
    \\    more: Heap[]
    \\    extra: Heap[]
    \\
    \\class Obj2:
    \\    next: Heap
    \\    values: float[]
    \\    more: Heap[]
    \\
;
/// The rest of the recursive-graph program after the last field of `Obj2`.
const recursive_graphs_tail =
    \\
    \\enum Heap:
    \\    empty(value: int)
    \\    o0(value: Obj0)
    \\    o1(value: Obj1)
    \\    o2(value: Obj2)
    \\
    \\class State:
    \\    objects: Heap[]
    \\    depth: int
    \\
    \\func count(mut state: State, e: Expr) -> int:
    \\    state.depth = state.depth + 1
    \\    match e:
    \\        case Expr.leaf(v):
    \\            return v
    \\        case _:
    \\            return 0
    \\
    \\func walk(mut state: State, e: Expr) -> int:
    \\    return count(mut state, e)
    \\
    \\func main() -> int:
    \\    mut s = State(objects=[], depth=0)
    \\    return walk(mut s, Expr.leaf(3))
    \\
;

/// A runtime whose object table holds classes behind a union, as the Lox VM's
/// does; `close` writes an upvalue it takes out of the table with `match`.
fn upvalueProgram(comptime parameter: []const u8, comptime argument: []const u8) []const u8 {
    return std.fmt.comptimePrint(
        \\class Upvalue:
        \\    closed: int
        \\
        \\union Obj:
        \\    empty,
        \\    up: Upvalue
        \\
        \\class Runtime:
        \\    objects: list[Obj]
        \\
        \\def close({s}, i: int):
        \\    match rt.objects[i]:
        \\        case Obj.up(u):
        \\            target = u
        \\            target.closed = 1
        \\        case _:
        \\            return
        \\
        \\def main() -> int:
        \\    rt = Runtime(objects=[Obj.up(Upvalue(closed=0))])
        \\    close({s}, 0)
        \\    return 0
        \\
    , .{ parameter, argument });
}

// spec-case: MUT-PARAM-4
test "M2 forwarding mut x where x is the caller's own parameter needs that parameter mut" {
    try reject(
        \\func touch(mut values: int[]) -> Unit effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\func forward(values: int[]) -> Unit:
        \\    touch(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    forward(values)
        \\    return 0
    , "E_IMMUTABLE", "read-only");
}

// spec-case: MUTATION-METADATA-1
test "M2 a copied record field is independent of its input" {
    try accept(
        \\record Box:
        \\    values: int[]
        \\
        \\
        \\func change(box: Box) -> Unit effects():
        \\    mut alias = box.values
        \\    alias[0] = 42
        \\
        \\
        \\func main() -> int:
        \\    mut box = Box(values=[1])
        \\    change(box)
        \\    return 0
    );
    try result(
        \\record Box:
        \\    values: int[]
        \\
        \\
        \\func change(box: Box) -> Unit:
        \\    mut alias = box.values
        \\    alias[0] = 42
        \\
        \\
        \\func main() -> int:
        \\    mut box = Box(values=[1])
        \\    change(box)
        \\    if box.values[0] != 1:
        \\        return 1
        \\    return 0
    , 0);
}

// spec-case: MUTATION-METADATA-1
test "M2 copied collections keep nested mutable values independent" {
    try result(
        \\func edit(values: int[]) -> Unit:
        \\    mut copy = values.copy()
        \\    copy[0] = 99
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    edit(values)
        \\    if values[0] != 1:
        \\        return 1
        \\    return 0
    , 0);
    try result(
        \\func edit(values: int[][]) -> Unit effects(managed_allocation):
        \\    mut copy = values.copy()
        \\    copy[0][0] = 99
        \\
        \\
        \\func main() -> int:
        \\    mut inner = [1]
        \\    mut values = [inner]
        \\    edit(values)
        \\    return values[0][0]
    , 1);
}

// spec-case: MUTATION-METADATA-1
test "M2 identity-returning helpers return independent values" {
    try accept(
        \\func identity(values: int[]) -> int[] effects():
        \\    return values
        \\
        \\
        \\func overwrite(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func launder(values: int[]) -> Unit effects():
        \\    mut alias = identity(values)
        \\    overwrite(mut alias)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    launder(values)
        \\    return 0
    );
    try result(
        \\func identity(values: int[]) -> int[] effects():
        \\    return values
        \\
        \\
        \\func overwrite(mut values: int[]) -> Unit:
        \\    values[0] = 42
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut alias = identity(values)
        \\    overwrite(mut alias)
        \\    if values[0] != 1:
        \\        return 1
        \\    return 0
    , 0);
}

// spec-case: MUTATION-METADATA-1
test "M2 return wrappers copy their mutable descendants" {
    try accept(
        \\record Box:
        \\    values: int[]
        \\
        \\
        \\func boxed(values: int[]) -> Box effects():
        \\    return Box(values=values)
        \\
        \\
        \\func overwrite(mut box: Box) -> Unit:
        \\    box.values[0] = 1
        \\
        \\
        \\func launder(values: int[]) -> Unit effects():
        \\    mut box = boxed(values)
        \\    overwrite(mut box)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    launder(values)
        \\    return 0
    );
}

// spec-case: MUTATION-METADATA-1
test "M2 branches and loops attribute writes to the receiver origin" {
    try result(
        \\func fill(mut values: int[], count: int) -> Unit:
        \\    mut index = 0
        \\    while index < count:
        \\        if index % 2 == 0:
        \\            values[index] = index
        \\        else:
        \\            values[index] = 0 - index
        \\        index += 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0, 0]
        \\    fill(mut values, 2)
        \\    return values[0] + values[1]
    , -1);
    try reject(
        \\func fill(mut values: int[], count: int) -> Unit effects():
        \\    mut index = 0
        \\    while index < count:
        \\        values[index] = index
        \\        index += 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0, 0]
        \\    fill(mut values, 2)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 recursive helpers propagate mutation footprints to a fixed point" {
    try result(
        \\func touch(mut values: int[], depth: int) -> Unit:
        \\    if depth == 0:
        \\        return
        \\    touch(mut values, depth - 1)
        \\    values[0] = 7
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values, 2)
        \\    if values[0] != 7:
        \\        return 1
        \\    return 0
    , 0);
    try reject(
        \\func touch(mut values: int[], depth: int) -> Unit effects():
        \\    if depth == 0:
        \\        return
        \\    touch(mut values, depth - 1)
        \\    values[0] = 7
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values, 2)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 indirect callbacks obey mutation contracts" {
    try result(
        \\func apply(f: func(mut values: int[]) -> Unit effects(mutation), mut values: int[]) -> Unit effects(mutation):
        \\    f(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    apply(lambda values: values.clear(), mut values)
        \\    if len(values) != 0:
        \\        return 1
        \\    return 0
    , 0);
    try reject(
        \\func apply(f: func(mut values: int[]) -> Unit effects(), mut values: int[]) -> Unit effects():
        \\    f(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    apply(lambda values: values.clear(), mut values)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 writable and read-only arguments have independent values" {
    try accept(
        \\func touch(mut x: int[], y: int[]) -> Unit:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\func use(mut values: int[]) -> Unit:
        \\    touch(mut values, values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    use(mut values)
        \\    return 0
    );
    try accept(
        \\func touch(mut x: int[], y: int[]) -> Unit:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\func use(mut a: int[], b: int[]) -> Unit:
        \\    touch(mut a, b)
        \\
        \\
        \\func main() -> int:
        \\    mut a = [1]
        \\    mut b = [2]
        \\    use(mut a, b)
        \\    return 0
    );
    try result(
        \\func touch(mut x: int[], y: int[]) -> Unit:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\func main() -> int:
        \\    mut a = [1]
        \\    mut b = a.copy()
        \\    touch(mut a, b)
        \\    return 0
    , 0);
}

// spec-case: MUTATION-METADATA-1
test "M2 cached callers are revalidated when a callee gains a mutation" {
    const Cache = language.semantic_cache.Cache;
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const before =
        \\func helper(values: int[]) -> int effects():
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0]
        \\    return helper(values)
    ;
    var first = try language.Compilation.init(t.allocator, "edited.my", before);
    defer first.deinit();
    try first.checkWithCache(&cache);
    try t.expectEqual(@as(i64, 0), (try native.run(&first)).value);
    const after =
        \\func helper(values: int[]) -> int effects():
        \\    values[0] = 1
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0]
        \\    return helper(values)
    ;
    var second = try language.Compilation.init(t.allocator, "edited.my", after);
    defer second.deinit();
    try t.expectError(error.SourceError, second.checkWithCache(&cache));
}

// spec: EFFECT-LITERAL-1
test "compile-time str literals contribute no managed allocation while computed strings and collections do" {
    try accept(
        \\func f(out: Stream) -> Unit effects(output):
        \\    out.print("hi")
        \\
        \\
        \\func main() -> int noalloc:
        \\    return len("abc")
    );
    try result(
        \\func g() -> str effects():
        \\    return "x"
        \\
        \\
        \\func main() -> int noalloc:
        \\    return len(g())
    , 1);
    try reject(
        \\func main() -> int effects():
        \\    return len("a" + "b")
    , "E_EFFECT_BOUND", "main");
    try reject(
        \\func main() -> int effects():
        \\    mut data: bytes = b"ab"
        \\    return len(data)
    , "E_EFFECT_BOUND", "main");
    try reject(
        \\func main() -> int effects():
        \\    mut items: int[] = []
        \\    return len(items)
    , "E_EFFECT_BOUND", "main");
}

// spec: EFFECT-INDEX-1
test "an element read allocates only from a str receiver so whole-program lowering agrees with the checked effects" {
    // `emit` lowers the whole program and re-derives every function's effects
    // from its bytecode; a checked mask that charged these reads failed there.
    try accept(
        \\func first(names: FixedArray[str, 3]) -> bool:
        \\    return names[0] == "alpha"
        \\
        \\
        \\func lookup(names: dict[int, str]) -> bool:
        \\    return names[1] == "alpha"
        \\
        \\
        \\func main() -> int:
        \\    mut names: FixedArray[str, 3] = FixedArray[str, 3](["alpha", "beta", "gamma"])
        \\    names = replace(names, 1, "delta")
        \\    return len(names[1])
    );
    try accept(
        \\func first(names: FixedArray[str, 3]) -> bool noalloc:
        \\    return names[-1] == "gamma"
        \\
        \\
        \\func lookup(names: dict[int, str]) -> bool noalloc:
        \\    return names[1] == "alpha"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    try result(
        \\func main() -> int:
        \\    mut names: FixedArray[str, 3] = FixedArray[str, 3](["alpha", "beta", "gamma"])
        \\    names = replace(names, 1, "delta")
        \\    return len(names[1]) + len(names[-1])
    , 10);
    try reject(
        \\func initial(name: str) -> bool effects():
        \\    return name[0] == "a"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_EFFECT_BOUND", "initial");
}

// spec: MUTATION-OVERLAP-1
test "unannotated and mutating helpers accept independent read-only collection arguments" {
    try accept(
        \\func total(first: int[], second: int[]) -> int:
        \\    return first[0] + second[0]
        \\
        \\
        \\func combine(a: int[]) -> int:
        \\    return total(a, a)
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit:
        \\    dst[0] = src[0]
        \\
        \\
        \\func combine(mut a: int[], b: int[]) -> Unit:
        \\    touch(mut a, b)
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
}

const unbounded_writer =
    \\func touch(values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int:
    \\    mut values = [1]
    \\    touch(values)
    \\    return 0
;

// spec: MUT-PARAM-2
test "M1 an ordinary parameter write is rejected at its readonly root" {
    try reject(
        \\func write_both(first: int[], second: int[]) -> Unit:
        \\    first[0] = 1
        \\    second[0] = 2
        \\func main() -> int:
        \\    return 0
    , "E_IMMUTABLE", "read-only");
}

// spec-case: MUT-PARAM-2
test "M1 writing only fresh local storage needs no mut parameter" {
    try accept(
        \\func local_edit() -> int:
        \\    mut values = [1]
        \\    values[0] = 2
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    return local_edit() - 2
    );
}

// spec-case: MUT-PARAM-2
test "M1 forwarding a mut parameter to another call counts as a write" {
    try accept(
        \\func touch(mut values: int[]) -> Unit effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\func forward(mut values: int[]) -> Unit effects(mutation):
        \\    touch(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0]
        \\    forward(mut values)
        \\    return values[0] - 1
    );
}

// spec: MUT-PARAM-3
test "M1 scalar str and bytes parameters may declare mut capabilities" {
    try accept(
        \\func scale(mut count: int, mut text: str, mut data: bytes) -> Unit:
        \\    return
        \\func main() -> int:
        \\    return 0
    );
}

// spec-case: MUTATION-OVERLAP-1
test "a declared footprint without a ceiling accepts a read-only snapshot" {
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit:
        \\    dst[0] = src[0]
        \\
        \\
        \\func forward(mut first: int[], second: int[]) -> Unit:
        \\    touch(mut first, second)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    forward(mut values, values)
        \\    return 0
    );
}

/// The first warning one accepted compilation produced, with the source text its
/// span covers. Both are copied out because the compilation arena is released
/// with the compilation.
fn warningOf(source: []const u8) !struct { code: []const u8, span_text: []u8 } {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try c.check();
    for (c.diagnostics.items) |item| {
        if (item.severity != .warning) continue;
        return .{ .code = item.code, .span_text = try t.allocator.dupe(u8, c.src.text(item.span)) };
    }
    return error.TestUnexpectedResult;
}

// spec: DERIVED-EFFECTS-1
test "a body that exceeds the ceiling its own signature implies names the parameter to add" {
    // An `extern def` clause grants the authority the C side declares. A relay
    // whose own signature supplies no such parameter exceeds its ceiling, and the
    // rejection names the parameter that would supply it.
    const relay = "extern func put(host: Host, value: u8) -> int effects(host, filesystem)\n\n" ++
        "func relay(host: Host) -> int:\n    return put(host, 1u8)\n\n" ++
        "func main(host: Host) -> int:\n    return relay(host)\n";
    try reject(relay, "E_EFFECT_BOUND", "add `fs: Filesystem` to the parameters");
    // The same bodies are accepted once every signature on the path supplies it.
    try accept("extern func put(host: Host, value: u8) -> int effects(host, filesystem)\n\n" ++
        "func relay(host: Host, fs: Filesystem) -> int:\n    _ = fs\n    return put(host, 1u8)\n\n" ++
        "func main(host: Host, fs: Filesystem) -> int:\n    return relay(host, fs)\n");
    // A capability parameter is what permits its effect, and a `mut` parameter
    // what permits `mutation`; neither can be replaced by a clause.
    try reject("func load(fs: Filesystem) -> int:\n    return 0\n\n" ++
        "func main() -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", "`fs` is never used");
    try accept("func write(mut values: int[]) -> Unit:\n    values.append(1)\n\n" ++
        "func main() -> int:\n    mut values = [0]\n    write(mut values)\n    return values[0]\n");
}

// spec-case: DERIVED-EFFECTS-1
test "a recursive record and union signature derives its ceiling without expanding every path" {
    try result("record Binary:\n" ++
        "    left: Expr\n" ++
        "    right: Expr\n" ++
        "\n" ++
        "\n" ++
        "enum Expr:\n" ++
        "    number(value: int)\n" ++
        "    binary(value: Binary)\n" ++
        "\n" ++
        "\n" ++
        "func total(expr: Expr) -> int:\n" ++
        "    match expr:\n" ++
        "        case Expr.number(value=n):\n" ++
        "            return n\n" ++
        "        case Expr.binary(value=node):\n" ++
        "            return total(node.left) + total(node.right)\n" ++
        "\n" ++
        "\n" ++
        "func main() -> int:\n" ++
        "    return total(Expr.binary(value=Binary(left=Expr.number(value=20), right=Expr.number(value=22))))\n", 42);
}

// spec-case: DERIVED-EFFECTS-1
test "a record that holds a capability permits that capability's effect" {
    try accept("record Authority:\n    env: Environment\n\n\n" ++
        "func lookup(auth: Authority) -> int effects(environment):\n    _ = auth.env\n    return 0\n\n\n" ++
        "func main(env: Environment) -> int:\n    return lookup(Authority(env=env))\n");
    // The same shape without the capability in the record is an over-claim.
    try reject("record Holder:\n    value: int\n\n\n" ++
        "func lookup(held: Holder) -> int effects(environment):\n    _ = held\n    return 0\n\n\n" ++
        "func main() -> int:\n    return 0\n", "E_DERIVED_EFFECTS", "add `env: Environment` to the parameters or drop the clause");
}

// spec: DERIVED-EFFECTS-2
test "an effect clause that restates the derived ceiling warns and a narrowing stays" {
    const restating = try warningOf("extern func probe(host: Host) -> int effects(host)\n\n" ++
        "func helper(host: Host) -> int effects(host, managed_allocation):\n    return probe(host)\n\n" ++
        "func main(host: Host) -> int:\n    return helper(host)\n");
    defer t.allocator.free(restating.span_text);
    try t.expectEqualStrings("W_DERIVED_EFFECTS", restating.code);
    try t.expectEqualStrings("effects(host, managed_allocation)", restating.span_text);
    // A clause that withholds what the parameters imply is a real narrowing.
    try accept("extern func probe(host: Host) -> int effects(host)\n\n" ++
        "func helper(host: Host, fs: Filesystem) -> int effects(host, filesystem):\n    _ = fs\n    return probe(host)\n\n" ++
        "func main(host: Host, fs: Filesystem) -> int:\n    return helper(host, fs)\n");
    try accept("func helper(count: int) -> int noalloc:\n    return count + 1\n\n" ++
        "func main() -> int:\n    return helper(1)\n");
    // `noio` on a body with no io-capable parameter withholds nothing.
    const noio = try warningOf("func helper(count: int) -> int noio:\n    return count + 1\n\n" ++
        "func main() -> int:\n    return helper(1)\n");
    defer t.allocator.free(noio.span_text);
    try t.expectEqualStrings("W_DERIVED_EFFECTS", noio.code);
    try t.expectEqualStrings("noio", noio.span_text);
}

// spec: DERIVED-EFFECTS-3
test "a clause naming an effect no parameter supplies is rejected with the paste" {
    try reject("func helper(count: int) -> int effects(filesystem):\n    return count + 1\n\n" ++
        "func main() -> int:\n    return helper(1)\n", "E_DERIVED_EFFECTS", "add `fs: Filesystem` to the parameters or drop the clause");
    try reject("func helper(count: int) -> int effects(clock):\n    return count + 1\n\n" ++
        "func main() -> int:\n    return helper(1)\n", "E_DERIVED_EFFECTS", "`effects(clock)` names `clock`");
    // A clause may still narrow a derived set, and an `extern def` clause is the
    // declaration's own authority rather than a summary of its parameters.
    try accept("func helper(out: Stream) -> Unit effects(output):\n    out.print(\"x\")\n\n" ++
        "func main(out: Stream) -> int:\n    helper(out)\n    return 0\n");
    try accept("extern func put(host: Host) -> int effects(host, managed_allocation)\n\n" ++
        "func main(host: Host) -> int:\n    return put(host)\n");
}

// spec: UNUSED-CAPABILITY-1
test "a capability parameter the body never reads is rejected and a passed-on one is not" {
    try reject("public func equal(host: Host, a: int, b: int) -> bool:\n    return a == b\n\n" ++
        "func main(host: Host) -> int:\n    if equal(host, 1, 1):\n        return 0\n    return 1\n", "E_UNUSED_CAPABILITY", "`host` is never used");
    try reject("func main(out: Stream) -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", "`out` is never used");
    // Handing the capability to another function is a read, so a frame that
    // never calls a host operation itself still uses its authority.
    try accept("extern func inner(host: Host) -> int effects(host)\n\n" ++
        "func outer(host: Host) -> int:\n    return inner(host)\n\n" ++
        "func main(host: Host) -> int:\n    return outer(host)\n");
}

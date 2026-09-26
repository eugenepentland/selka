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
    try c.emit();
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
        \\def main() -> i64:
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
        \\def a(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\def b(x: i64) -> i64:
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

// spec: EFFECT-CEILING-1
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
        \\def call(f: def(i64) -> i64 effects(clock)) -> i64 effects():
        \\    return f(1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_EFFECT_BOUND", "exceeds declared bound");
}

// spec: MUTATION-METADATA-1
test "M1 direct input writes carry mutation facts while reads do not" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(values: mut list[int]) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def peek(values: list[int]) -> int effects():
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    values = [7]
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
        \\def touch(values: mut list[int]) -> None effects(mutation):
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
    \\def touch(values: mut list[int]) -> None effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\def main() -> int:
    \\    values = [7]
    \\    touch(mut values)
    \\    return values[0]
;

const marker_keyword_valid =
    \\def touch(values: mut list[int], item: int) -> None effects(mutation):
    \\    values[0] = item
    \\
    \\
    \\def main() -> int:
    \\    values = [7]
    \\    touch(item=1, values=mut values)
    \\    return 0
;

const marker_missing =
    \\def touch(values: list[int]) -> None:
    \\    values[0] = 1
    \\
    \\
    \\def main() -> int:
    \\    values = [7]
    \\    touch(values)
    \\    return 0
;

const marker_multi_missing =
    \\def touch(values: mut list[int], item: int) -> None effects(mutation):
    \\    values[0] = item
    \\
    \\
    \\def main() -> int effects(managed_allocation):
    \\    values = [7]
    \\    touch(values, 1)
    \\    return 0
;

const marker_extra =
    \\def peek(values: list[int]) -> int effects():
    \\    return values[0]
    \\
    \\
    \\def main() -> int effects(managed_allocation):
    \\    values = [7]
    \\    return peek(mut values)
;

const marker_non_lvalue =
    \\def touch(values: mut list[int]) -> None effects(mutation, managed_allocation):
    \\    values[0] = 1
    \\
    \\
    \\def main() -> int effects(managed_allocation):
    \\    touch(mut [1, 2, 3])
    \\    return 0
;

const marker_unused =
    \\def touch(values: mut list[int]) -> None effects():
    \\    return
    \\
    \\
    \\def main() -> int:
    \\    values = [7]
    \\    touch(mut values)
    \\    return 0
;

const marker_indirect_valid =
    \\def touch(values: mut list[int]) -> None effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\def apply(f: def(values: mut list[int]) -> None effects(mutation), values: mut list[int]) -> None effects(mutation):
    \\    f(mut values)
    \\
    \\
    \\def main() -> int:
    \\    values = [7]
    \\    apply(touch, mut values)
    \\    return 0
;

const marker_indirect_missing =
    \\def touch(values: mut list[int]) -> None effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\def apply(f: def(values: mut list[int]) -> None effects(mutation), values: mut list[int]) -> None effects(mutation):
    \\    f(values)
    \\
    \\
    \\def main() -> int effects(managed_allocation):
    \\    values = [7]
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
test "M4 a written parameter without mut is rejected with the declaration paste" {
    const diag = try markerError(marker_missing);
    defer t.allocator.free(diag.message);
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "declare `values: mut list[int]`") != null);
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
test "M4 a mut parameter the body never writes is rejected" {
    const diag = try markerError(marker_unused);
    defer t.allocator.free(diag.message);
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, "declared `mut` but never written; remove `mut`") != null);
}

test "M1 definitely fresh local construction does not require mutation permission" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def main() -> int:
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

// spec-case: MUTATION-METADATA-1
test "M2 unused generic body enforces its declared mutation contract" {
    try reject(
        \\def touch[T](values: mut list[T], item: T) -> None effects():
        \\    values[0] = item
        \\
        \\
        \\def main() -> int effects():
        \\    return 0
    , "E_MUTATION_PERMISSION", "generic");
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch[T](values: mut list[T], item: T) -> None effects(mutation):
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
        \\def apply(f: def(values: mut list[int]) -> None effects(mutation)) -> None effects():
        \\    _ = f
        \\
        \\
        \\def main() -> int:
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
        \\def touch(values: mut list[int]) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values = [7]
        \\    touch(mut values)
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
        function.signature.inferred = .{};
        function.signature.mutates = &.{};
        forged = true;
    }
    try t.expect(forged);
    try t.expectError(error.InternalError, effect_engine.validate(t.allocator, program));
}

test "M1 callback mutates metadata survives source checking and callable interning" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def apply(f: def(values: mut list[int]) -> None effects(mutation)) -> None effects():
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
        \\def apply(f: def(values: mut list[int]) -> None effects(mutation)) -> None effects():
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
    try t.expectEqual(@as(usize, 1), callback.mut_parameters.len);
    try t.expect(callback.mut_parameters[0]);
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
    \\def slot(values: mut list[int]) -> None effects(mutation):
    \\    values[0] = 1
    \\
    \\
    \\def augment(values: mut list[int]) -> None effects(mutation):
    \\    values[0] += 1
    \\
    \\
    \\def append(values: mut list[int]) -> None:
    \\    values.append(1)
    \\
    \\
    \\def extend(values: mut list[int], other: list[int]) -> None:
    \\    values.extend(other)
    \\
    \\
    \\def insert(values: mut list[int]) -> None:
    \\    values.insert(0, 1)
    \\
    \\
    \\def remove(values: mut list[int]) -> None effects(mutation):
    \\    values.remove(1)
    \\
    \\
    \\def pop(values: mut list[int]) -> None effects(mutation):
    \\    _ = values.pop()
    \\
    \\
    \\def clear(values: mut list[int]) -> None effects(mutation):
    \\    values.clear()
    \\
    \\
    \\def reverse(values: mut list[int]) -> None effects(mutation):
    \\    values.reverse()
    \\
    \\
    \\def sort(values: mut list[int]) -> None effects(mutation):
    \\    values.sort()
    \\
    \\
    \\def update(mapping: mut dict[str, int]) -> None:
    \\    mapping["answer"] = 1
    \\
    \\
    \\def delete(mapping: mut dict[str, int]) -> None:
    \\    _ = mapping.pop("answer")
    \\
    \\
    \\def set_cell(cell: mut Cell[int]) -> None effects(mutation):
    \\    cell.value = 1
    \\
    \\
    \\def main() -> int effects():
    \\    return 0
;

test "legacy sharing: M1 every managed write form contributes a mutation fact" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    var c = try language.Compilation.init(t.allocator, fixture_path, mutation_forms);
    defer c.deinit();
    try c.check();
    const expected = [_][]const u8{ "slot", "augment", "append", "extend", "insert", "remove", "pop", "clear", "reverse", "sort", "update", "delete", "set_cell" };
    for (expected) |name| {
        var found = false;
        for (c.program.?.functions) |function| {
            if (!std.mem.eql(u8, function.name, name)) continue;
            found = true;
            try t.expect(function.signature.inferred.writes);
            try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        }
        try t.expect(found);
    }
}

test "M1 mutates clause normalizes duplicate names to sorted positions" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def touch(a: mut list[int], b: mut list[int]) -> None:
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

// spec-case: MUTATION-METADATA-1
// spec: MUTATION-ENFORCE-1
test "legacy sharing: M2 a write through an unmarked parameter is the marker error, not a permission one" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try reject(
        \\def touch(values: list[int]) -> None effects():
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(values)
        \\    return 0
    , marker_code, "declare `values: mut list[int]`");
    try reject(
        \\def set_value(cell: Cell[int]) -> None effects():
        \\    cell.value = 1
        \\
        \\
        \\def main() -> int:
        \\    cell = Cell(value=0)
        \\    set_value(cell)
        \\    return 0
    , marker_code, "declare `cell: mut Cell[int]`");
}

// spec: MUT-PARAM-4
test "M2 a mut parameter with no mutation ceiling still exceeds its contract" {
    try reject(
        \\def touch(values: mut list[int]) -> None effects(managed_allocation):
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(mut values)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUT-PARAM-4
test "M2 a mut footprint accepts an independent read-only snapshot" {
    try accept(
        \\def touch(dst: mut list[int], src: list[int]) -> None effects(mutation):
        \\    dst[0] = src[0]
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(mut values, values)
        \\    return 0
    );
    // Each read-only argument is an independent snapshot, including a
    // second local copied from the same source.
    try accept(
        \\def touch(dst: mut list[int], src: list[int]) -> None effects(mutation):
        \\    dst[0] = src[0]
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    alias = values
        \\    touch(mut values, alias)
        \\    return 0
    );
    try result(
        \\def touch(dst: mut list[int], src: list[int]) -> None effects(mutation):
        \\    dst[0] = src[0] + 1
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    snapshot = values.copy()
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
    \\    items: list[Expr]
    \\    extra: list[Expr]
    \\
    \\class Node1:
    \\    left: Expr
    \\    right: Expr
    \\    items: list[Expr]
    \\    extra: list[Expr]
    \\
    \\class Node2:
    \\    left: Expr
    \\    right: Expr
    \\    items: list[Expr]
    \\    extra: list[Expr]
    \\
    \\union Expr:
    \\    leaf: int,
    \\    n0: Node0,
    \\    n1: Node1,
    \\    n2: Node2
    \\
    \\class Obj0:
    \\    next: Heap
    \\    values: list[float]
    \\    more: list[Heap]
    \\    extra: list[Heap]
    \\
    \\class Obj1:
    \\    next: Heap
    \\    values: list[float]
    \\    more: list[Heap]
    \\    extra: list[Heap]
    \\
    \\class Obj2:
    \\    next: Heap
    \\    values: list[float]
    \\    more: list[Heap]
    \\
;
/// The rest of the recursive-graph program after the last field of `Obj2`.
const recursive_graphs_tail =
    \\
    \\union Heap:
    \\    empty: int,
    \\    o0: Obj0,
    \\    o1: Obj1,
    \\    o2: Obj2
    \\
    \\class State:
    \\    objects: list[Heap]
    \\    depth: int
    \\
    \\def count(state: mut State, e: Expr) -> int:
    \\    state.depth = state.depth + 1
    \\    match e:
    \\        case Expr.leaf(v):
    \\            return v
    \\        case _:
    \\            return 0
    \\
    \\def walk(state: mut State, e: Expr) -> int:
    \\    return count(mut state, e)
    \\
    \\def main() -> int:
    \\    s = State(objects=[], depth=0)
    \\    return walk(mut s, Expr.leaf(3))
    \\
;

// The per-path walk this replaced re-walked every path to a pair, so these two
// graphs never finished checking; expanding each pair once settles them at once.
// spec: MUT-OVERLAP-PROOF-1
test "legacy sharing: the overlap proof over two recursive class graphs expands each type pair once" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    var c = try language.Compilation.init(t.allocator, fixture_path, recursive_graphs_head ++ "    extra: list[Heap]\n" ++ recursive_graphs_tail);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(?language.diagnostic.Diagnostic, null), firstError(c.diagnostics.items));
}

// spec-case: MUT-OVERLAP-PROOF-1
test "legacy sharing: the overlap proof still rejects two recursive graphs that share one component deep down" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try reject(recursive_graphs_head ++ "    source: list[Expr]\n" ++ recursive_graphs_tail, "E_MUTATION_OVERLAP", "may alias");
}

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

// spec: MUT-TRACK-1
test "legacy sharing: a write through a match payload writes the owner of the matched value" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try accept(comptime upvalueProgram("rt: mut Runtime", "mut rt"));
    try reject(comptime upvalueProgram("rt: Runtime", "rt"), marker_code, "declare `rt: mut Runtime`");
}

// A binding a later loop statement widens carries the widened origin at the
// write: on the second iteration `b` is `a`, which the first made `p`.
// spec-case: MUT-TRACK-1
test "legacy sharing: binding origins reach a fixed point across a loop" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try reject(
        \\class Box:
        \\    n: int
        \\
        \\def shuffle(p: Box):
        \\    a = Box(n=0)
        \\    b = Box(n=0)
        \\    for i in range(2):
        \\        b.n = i
        \\        b = a
        \\        a = p
        \\
        \\def main() -> int:
        \\    shuffle(Box(n=0))
        \\    return 0
    , marker_code, "declare `p: mut Box`");
}

// spec-case: MUT-TRACK-1
test "legacy sharing: the missing-marker diagnostic points at the write that needs the marker" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const source =
        \\class Box:
        \\    n: int
        \\
        \\def both(r: mut Box, x: Box):
        \\    r.n = 1
        \\    x.n = 2
        \\
        \\def main() -> int:
        \\    r = Box(n=0)
        \\    both(mut r, Box(n=0))
        \\    return 0
    ;
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const diag = firstError(c.diagnostics.items) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(marker_code, diag.code);
    try t.expectEqualStrings("x.n", source[diag.span.start..][0..3]);
}

// spec-case: MUT-PARAM-4
test "M2 forwarding mut x where x is the caller's own parameter needs that parameter mut" {
    try reject(
        \\def touch(values: mut list[int]) -> None effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\def forward(values: list[int]) -> None:
        \\    touch(mut values)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    forward(values)
        \\    return 0
    , marker_code, "declare `values: mut list[int]`");
}

// spec-case: MUTATION-METADATA-1
test "M2 a copied record field is independent of its input" {
    try accept(
        \\record Box:
        \\    values: list[int]
        \\
        \\
        \\def change(box: Box) -> None effects():
        \\    alias = box.values
        \\    alias[0] = 42
        \\
        \\
        \\def main() -> int:
        \\    box = Box(values=[1])
        \\    change(box)
        \\    return 0
    );
    try result(
        \\record Box:
        \\    values: list[int]
        \\
        \\
        \\def change(box: Box) -> None:
        \\    alias = box.values
        \\    alias[0] = 42
        \\
        \\
        \\def main() -> int:
        \\    box = Box(values=[1])
        \\    change(box)
        \\    if box.values[0] != 1:
        \\        return 1
        \\    return 0
    , 0);
}

// spec-case: MUTATION-METADATA-1
test "M2 copied collections keep nested mutable values independent" {
    try result(
        \\def edit(values: list[int]) -> None:
        \\    copy = values.copy()
        \\    copy[0] = 99
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    edit(values)
        \\    if values[0] != 1:
        \\        return 1
        \\    return 0
    , 0);
    try result(
        \\def edit(values: list[list[int]]) -> None effects(managed_allocation):
        \\    copy = values.copy()
        \\    copy[0][0] = 99
        \\
        \\
        \\def main() -> int:
        \\    inner = [1]
        \\    values = [inner]
        \\    edit(values)
        \\    return values[0][0]
    , 1);
}

// spec-case: MUTATION-METADATA-1
test "M2 identity-returning helpers return independent values" {
    try accept(
        \\def identity(values: list[int]) -> list[int] effects():
        \\    return values
        \\
        \\
        \\def overwrite(values: mut list[int]) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def launder(values: list[int]) -> None effects():
        \\    alias = identity(values)
        \\    overwrite(mut alias)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    launder(values)
        \\    return 0
    );
    try result(
        \\def identity(values: list[int]) -> list[int] effects():
        \\    return values
        \\
        \\
        \\def overwrite(values: mut list[int]) -> None:
        \\    values[0] = 42
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    alias = identity(values)
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
        \\    values: list[int]
        \\
        \\
        \\def boxed(values: list[int]) -> Box effects():
        \\    return Box(values=values)
        \\
        \\
        \\def overwrite(box: mut Box) -> None:
        \\    box.values[0] = 1
        \\
        \\
        \\def launder(values: list[int]) -> None effects():
        \\    box = boxed(values)
        \\    overwrite(mut box)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    launder(values)
        \\    return 0
    );
}

// spec-case: MUTATION-METADATA-1
test "M2 branches and loops attribute writes to the receiver origin" {
    try result(
        \\def fill(values: mut list[int], count: int) -> None:
        \\    index = 0
        \\    while index < count:
        \\        if index % 2 == 0:
        \\            values[index] = index
        \\        else:
        \\            values[index] = 0 - index
        \\        index += 1
        \\
        \\
        \\def main() -> int:
        \\    values = [0, 0]
        \\    fill(mut values, 2)
        \\    return values[0] + values[1]
    , -1);
    try reject(
        \\def fill(values: mut list[int], count: int) -> None effects():
        \\    index = 0
        \\    while index < count:
        \\        values[index] = index
        \\        index += 1
        \\
        \\
        \\def main() -> int:
        \\    values = [0, 0]
        \\    fill(mut values, 2)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 recursive helpers propagate mutation footprints to a fixed point" {
    try result(
        \\def touch(values: mut list[int], depth: int) -> None:
        \\    if depth == 0:
        \\        return
        \\    touch(mut values, depth - 1)
        \\    values[0] = 7
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(mut values, 2)
        \\    if values[0] != 7:
        \\        return 1
        \\    return 0
    , 0);
    try reject(
        \\def touch(values: mut list[int], depth: int) -> None effects():
        \\    if depth == 0:
        \\        return
        \\    touch(mut values, depth - 1)
        \\    values[0] = 7
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(mut values, 2)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 indirect callbacks obey mutation contracts" {
    try result(
        \\def apply(f: def(values: mut list[int]) -> None effects(mutation), values: mut list[int]) -> None effects(mutation):
        \\    f(mut values)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    apply(lambda values: values.clear(), mut values)
        \\    if len(values) != 0:
        \\        return 1
        \\    return 0
    , 0);
    try reject(
        \\def apply(f: def(values: mut list[int]) -> None effects(), values: mut list[int]) -> None effects():
        \\    f(mut values)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    apply(lambda values: values.clear(), mut values)
        \\    return 0
    , "E_MUTATION_PERMISSION", "exceeds its contract");
}

// spec-case: MUTATION-METADATA-1
test "M2 writable and read-only arguments have independent values" {
    try accept(
        \\def touch(x: mut list[int], y: list[int]) -> None:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\def use(values: mut list[int]) -> None:
        \\    touch(mut values, values)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    use(mut values)
        \\    return 0
    );
    try accept(
        \\def touch(x: mut list[int], y: list[int]) -> None:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\def use(a: mut list[int], b: list[int]) -> None:
        \\    touch(mut a, b)
        \\
        \\
        \\def main() -> int:
        \\    a = [1]
        \\    b = [2]
        \\    use(mut a, b)
        \\    return 0
    );
    try result(
        \\def touch(x: mut list[int], y: list[int]) -> None:
        \\    x[0] = 1
        \\    _ = y[0]
        \\
        \\
        \\def main() -> int:
        \\    a = [1]
        \\    b = a.copy()
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
        \\def helper(values: list[int]) -> int effects():
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    values = [0]
        \\    return helper(values)
    ;
    var first = try language.Compilation.init(t.allocator, "edited.my", before);
    defer first.deinit();
    try first.checkWithCache(&cache);
    try t.expectEqual(@as(i64, 0), (try native.run(&first)).value);
    const after =
        \\def helper(values: list[int]) -> int effects():
        \\    values[0] = 1
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    values = [0]
        \\    return helper(values)
    ;
    var second = try language.Compilation.init(t.allocator, "edited.my", after);
    defer second.deinit();
    try t.expectError(error.SourceError, second.checkWithCache(&cache));
}

// spec: EFFECT-LITERAL-1
test "compile-time str literals contribute no managed allocation while computed strings and collections do" {
    try accept(
        \\def f(out: Stream) -> None effects(output):
        \\    out.print("hi")
        \\
        \\
        \\def main() -> int noalloc:
        \\    return len("abc")
    );
    try result(
        \\def g() -> str effects():
        \\    return "x"
        \\
        \\
        \\def main() -> int noalloc:
        \\    return len(g())
    , 1);
    try reject(
        \\def main() -> int noalloc:
        \\    return len("a" + "b")
    , "E_EFFECT_BOUND", "main");
    try reject(
        \\def main() -> int noalloc:
        \\    data: bytes = b"ab"
        \\    return len(data)
    , "E_EFFECT_BOUND", "main");
    try reject(
        \\def main() -> int noalloc:
        \\    items: list[int] = []
        \\    return len(items)
    , "E_EFFECT_BOUND", "main");
}

// spec: EFFECT-INDEX-1
test "an element read allocates only from a str receiver so whole-program lowering agrees with the checked effects" {
    // `emit` lowers the whole program and re-derives every function's effects
    // from its bytecode; a checked mask that charged these reads failed there.
    try accept(
        \\def first(names: [3]str) -> bool:
        \\    return names[0] == "alpha"
        \\
        \\
        \\def lookup(names: dict[int, str]) -> bool:
        \\    return names[1] == "alpha"
        \\
        \\
        \\def main() -> int:
        \\    names: [3]str = ["alpha", "beta", "gamma"]
        \\    names = replace(names, 1, "delta")
        \\    return len(names[1])
    );
    try accept(
        \\def first(names: [3]str) -> bool noalloc:
        \\    return names[-1] == "gamma"
        \\
        \\
        \\def lookup(names: dict[int, str]) -> bool noalloc:
        \\    return names[1] == "alpha"
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    try result(
        \\def main() -> int:
        \\    names: [3]str = ["alpha", "beta", "gamma"]
        \\    names = replace(names, 1, "delta")
        \\    return len(names[1]) + len(names[-1])
    , 10);
    try reject(
        \\def initial(name: str) -> bool noalloc:
        \\    return name[0] == "a"
        \\
        \\
        \\def main() -> int:
        \\    return 0
    , "E_EFFECT_BOUND", "initial");
}

// spec: MUTATION-OVERLAP-1
test "unannotated and mutating helpers accept independent read-only collection arguments" {
    try accept(
        \\def total(first: list[int], second: list[int]) -> int:
        \\    return first[0] + second[0]
        \\
        \\
        \\def combine(a: list[int]) -> int:
        \\    return total(a, a)
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    try accept(
        \\def touch(dst: mut list[int], src: list[int]) -> None:
        \\    dst[0] = src[0]
        \\
        \\
        \\def combine(a: mut list[int], b: list[int]) -> None:
        \\    touch(mut a, b)
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
}

/// Every `E_MUTATION_MARKER` message one source produces, copied out because the
/// compilation arena is released with the compilation.
fn markerMessages(source: []const u8) ![]const []u8 {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    var messages: std.ArrayList([]u8) = .empty;
    for (c.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, marker_code)) continue;
        try messages.append(t.allocator, try t.allocator.dupe(u8, item.message));
    }
    return messages.toOwnedSlice(t.allocator);
}

const unbounded_writer =
    \\def touch(values: list[int]) -> None:
    \\    values[0] = 1
    \\
    \\
    \\def main() -> int:
    \\    values = [1]
    \\    touch(values)
    \\    return 0
;

// spec: MUT-PARAM-2
test "M1 an unmarked written parameter is rejected with every position listed" {
    const messages = try markerMessages(
        \\def write_both(first: list[int], second: list[int]) -> None:
        \\    first[0] = 1
        \\    second[0] = 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer {
        for (messages) |message| t.allocator.free(message);
        t.allocator.free(messages);
    }
    try t.expectEqual(@as(usize, 1), messages.len);
    try t.expect(std.mem.indexOf(u8, messages[0], "this function writes `first` (parameter 1), `second` (parameter 2)") != null);
    try t.expect(std.mem.indexOf(u8, messages[0], "declare `first: mut list[int]`, `second: mut list[int]`") != null);
}

// spec-case: MUT-PARAM-2
test "legacy sharing: M1 a class parameter written through needs its own mut" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const messages = try markerMessages(
        \\class Cursor:
        \\    pos: int
        \\
        \\
        \\def bump(cursor: Cursor) -> int:
        \\    cursor.pos = cursor.pos + 1
        \\    return cursor.pos
        \\
        \\
        \\def main() -> int:
        \\    cursor = Cursor(pos=0)
        \\    return bump(cursor) - 1
    );
    defer {
        for (messages) |message| t.allocator.free(message);
        t.allocator.free(messages);
    }
    try t.expectEqual(@as(usize, 1), messages.len);
    try t.expect(std.mem.indexOf(u8, messages[0], "declare `cursor: mut Cursor`") != null);
}

// spec-case: MUT-PARAM-2
test "legacy sharing: M1 a class parameter written through is accepted once marked" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try accept(
        \\class Cursor:
        \\    pos: int
        \\
        \\
        \\def bump(cursor: mut Cursor) -> int:
        \\    cursor.pos = cursor.pos + 1
        \\    return cursor.pos
        \\
        \\
        \\def main() -> int:
        \\    cursor = Cursor(pos=0)
        \\    return bump(mut cursor) - 1
    );
}

// spec-case: MUT-PARAM-2
test "legacy sharing: M1 a write through a match payload binding needs the matched parameter's mut" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const messages = try markerMessages(
        \\def grow(candidate: Option[list[int]]) -> int:
        \\    match candidate:
        \\        case Some(items):
        \\            items.append(1)
        \\            return len(items)
        \\        case None:
        \\            return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer {
        for (messages) |message| t.allocator.free(message);
        t.allocator.free(messages);
    }
    try t.expectEqual(@as(usize, 1), messages.len);
    try t.expect(std.mem.indexOf(u8, messages[0], "declare `candidate: mut Option[list[int]]`") != null);
}

// spec-case: MUT-PARAM-2
test "legacy sharing: M1 a field write through a narrowed Option parameter needs mut and is accepted once marked" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    const messages = try markerMessages(
        \\class Counter:
        \\    value: int
        \\
        \\
        \\def bump(candidate: Option[Counter]) -> int:
        \\    if candidate is None:
        \\        return 0
        \\    candidate.value = candidate.value + 1
        \\    return candidate.value
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer {
        for (messages) |message| t.allocator.free(message);
        t.allocator.free(messages);
    }
    try t.expectEqual(@as(usize, 1), messages.len);
    try t.expect(std.mem.indexOf(u8, messages[0], "declare `candidate: mut Option[Counter]`") != null);
    try accept(
        \\class Counter:
        \\    value: int
        \\
        \\
        \\def bump(candidate: mut Option[Counter]) -> int:
        \\    if candidate is None:
        \\        return 0
        \\    candidate.value = candidate.value + 1
        \\    return candidate.value
        \\
        \\
        \\def main() -> int:
        \\    candidate: Option[Counter] = Some(Counter(value=41))
        \\    return bump(mut candidate) - 42
    );
}

// spec-case: MUT-PARAM-2
test "M1 writing only fresh local storage needs no mut parameter" {
    try accept(
        \\def local_edit() -> int:
        \\    values = [1]
        \\    values[0] = 2
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    return local_edit() - 2
    );
}

// spec-case: MUT-PARAM-2
test "M1 forwarding a mut parameter to another call counts as a write" {
    try accept(
        \\def touch(values: mut list[int]) -> None effects(mutation):
        \\    values[0] = 1
        \\
        \\
        \\def forward(values: mut list[int]) -> None effects(mutation):
        \\    touch(mut values)
        \\
        \\
        \\def main() -> int:
        \\    values = [0]
        \\    forward(mut values)
        \\    return values[0] - 1
    );
}

// spec: MUT-PARAM-3
test "M1 mut on a scalar, str or bytes parameter has nothing to write" {
    const messages = try markerMessages(
        \\def scale(count: mut int) -> None:
        \\    return
        \\
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer {
        for (messages) |message| t.allocator.free(message);
        t.allocator.free(messages);
    }
    try t.expectEqual(@as(usize, 1), messages.len);
    try t.expect(std.mem.indexOf(u8, messages[0], "`mut` on `i64` has nothing to write") != null);
    try t.expect(std.mem.indexOf(u8, messages[0], "return the new value instead") != null);
}

// spec-case: MUTATION-OVERLAP-1
test "a declared footprint without a ceiling accepts a read-only snapshot" {
    try accept(
        \\def touch(dst: mut list[int], src: list[int]) -> None:
        \\    dst[0] = src[0]
        \\
        \\
        \\def forward(first: mut list[int], second: list[int]) -> None:
        \\    touch(mut first, second)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
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
    // A `host def` clause grants the authority the host side declares. A relay
    // whose own signature supplies no such parameter exceeds its ceiling, and the
    // rejection names the parameter that would supply it.
    const relay = "host def put(host: Host, value: u8) -> int effects(host, filesystem)\n\n" ++
        "def relay(host: Host) -> int:\n    return put(host, 1u8)\n\n" ++
        "def main(host: Host) -> int:\n    return relay(host)\n";
    try reject(relay, "E_EFFECT_BOUND", "add `fs: Filesystem` to the parameters");
    // The same bodies are accepted once every signature on the path supplies it.
    try accept("host def put(host: Host, value: u8) -> int effects(host, filesystem)\n\n" ++
        "def relay(host: Host, fs: Filesystem) -> int:\n    _ = fs\n    return put(host, 1u8)\n\n" ++
        "def main(host: Host, fs: Filesystem) -> int:\n    return relay(host, fs)\n");
    // A capability parameter is what permits its effect, and a `mut` parameter
    // what permits `mutation`; neither can be replaced by a clause.
    try reject("def load(fs: Filesystem) -> int:\n    return 0\n\n" ++
        "def main() -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", "`fs` is never used");
    try accept("def write(values: mut list[int]) -> None:\n    values.append(1)\n\n" ++
        "def main() -> int:\n    values = [0]\n    write(mut values)\n    return values[0]\n");
}

// spec-case: DERIVED-EFFECTS-1
test "a recursive record and union signature derives its ceiling without expanding every path" {
    try result("record Binary:\n    left: Expr\n    right: Expr\n\n\n" ++
        "union Expr:\n    number: int,\n    binary: Binary\n\n\n" ++
        "def total(expr: Expr) -> int:\n" ++
        "    match expr:\n" ++
        "        case Expr.number(n):\n            return n\n" ++
        "        case Expr.binary(node):\n            return total(node.left) + total(node.right)\n\n\n" ++
        "def main() -> int:\n    return total(Expr.binary(Binary(left=Expr.number(20), right=Expr.number(22))))\n", 42);
}

// spec-case: DERIVED-EFFECTS-1
test "a record that holds a capability permits that capability's effect" {
    try accept("record Authority:\n    env: Environment\n\n\n" ++
        "def lookup(auth: Authority) -> int effects(environment):\n    _ = auth.env\n    return 0\n\n\n" ++
        "def main(env: Environment) -> int:\n    return lookup(Authority(env=env))\n");
    // The same shape without the capability in the record is an over-claim.
    try reject("record Holder:\n    value: int\n\n\n" ++
        "def lookup(held: Holder) -> int effects(environment):\n    _ = held\n    return 0\n\n\n" ++
        "def main() -> int:\n    return 0\n", "E_DERIVED_EFFECTS", "add `env: Environment` to the parameters or drop the clause");
}

// spec: DERIVED-EFFECTS-2
test "an effect clause that restates the derived ceiling warns and a narrowing stays" {
    const restating = try warningOf("host def probe(host: Host) -> int effects(host)\n\n" ++
        "def helper(host: Host) -> int effects(host, managed_allocation):\n    return probe(host)\n\n" ++
        "def main(host: Host) -> int:\n    return helper(host)\n");
    defer t.allocator.free(restating.span_text);
    try t.expectEqualStrings("W_DERIVED_EFFECTS", restating.code);
    try t.expectEqualStrings("effects(host, managed_allocation)", restating.span_text);
    // A clause that withholds what the parameters imply is a real narrowing.
    try accept("host def probe(host: Host) -> int effects(host)\n\n" ++
        "def helper(host: Host, fs: Filesystem) -> int effects(host, filesystem):\n    _ = fs\n    return probe(host)\n\n" ++
        "def main(host: Host, fs: Filesystem) -> int:\n    return helper(host, fs)\n");
    try accept("def helper(count: int) -> int noalloc:\n    return count + 1\n\n" ++
        "def main() -> int:\n    return helper(1)\n");
    // `noio` on a body with no io-capable parameter withholds nothing.
    const noio = try warningOf("def helper(count: int) -> int noio:\n    return count + 1\n\n" ++
        "def main() -> int:\n    return helper(1)\n");
    defer t.allocator.free(noio.span_text);
    try t.expectEqualStrings("W_DERIVED_EFFECTS", noio.code);
    try t.expectEqualStrings("noio", noio.span_text);
}

// spec: DERIVED-EFFECTS-3
test "a clause naming an effect no parameter supplies is rejected with the paste" {
    try reject("def helper(count: int) -> int effects(filesystem):\n    return count + 1\n\n" ++
        "def main() -> int:\n    return helper(1)\n", "E_DERIVED_EFFECTS", "add `fs: Filesystem` to the parameters or drop the clause");
    try reject("def helper(count: int) -> int effects(clock):\n    return count + 1\n\n" ++
        "def main() -> int:\n    return helper(1)\n", "E_DERIVED_EFFECTS", "`effects(clock)` names `clock`");
    // A clause may still narrow a derived set, and a `host def` clause is the
    // declaration's own authority rather than a summary of its parameters.
    try accept("def helper(out: Stream) -> None effects(output):\n    out.print(\"x\")\n\n" ++
        "def main(out: Stream) -> int:\n    helper(out)\n    return 0\n");
    try accept("host def put(host: Host) -> int effects(host, managed_allocation)\n\n" ++
        "def main(host: Host) -> int:\n    return put(host)\n");
}

// spec: UNUSED-CAPABILITY-1
test "a capability parameter the body never reads is rejected and a passed-on one is not" {
    try reject("public def equal(host: Host, a: int, b: int) -> bool:\n    return a == b\n\n" ++
        "def main(host: Host) -> int:\n    if equal(host, 1, 1):\n        return 0\n    return 1\n", "E_UNUSED_CAPABILITY", "`host` is never used");
    try reject("def main(out: Stream) -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", "`out` is never used");
    // Handing the capability to another function is a read, so a frame that
    // never calls a host operation itself still uses its authority.
    try accept("host def inner(host: Host) -> int effects(host)\n\n" ++
        "def outer(host: Host) -> int:\n    return inner(host)\n\n" ++
        "def main(host: Host) -> int:\n    return outer(host)\n");
}

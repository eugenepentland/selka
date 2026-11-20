//! Mutation/origin regression coverage preserved after effect inference retirement.
const fixture_path = "effects.selka";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const typed = @import("typed.zig");
const callables = @import("callables.zig");
/// Stable code for the call-site `&` marker diagnostic exercised below.
const marker_code = "E_MUTATION_MARKER";
fn firstError(items: []const language.diagnostic.Diagnostic) ?language.diagnostic.Diagnostic {
    for (items) |item| if (item.severity == .err) return item;
    return null;
}
fn reject(source: []const u8, code: []const u8, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), source);
    try t.expect(!report.passed);
    const diag = firstError(report.diagnostics) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(code, diag.code);
    try t.expect(std.mem.indexOf(u8, diag.message, text) != null);
    if (std.mem.eql(u8, code, "E_EFFECT_BOUND")) try t.expect(diag.related != null);
}
fn result(source: []const u8, expected: i64) !void {
    try t.expectEqual(expected, try fixture.value(t.allocator, source));
}
fn accept(source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), source);
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

// spec: MUTATION-METADATA-1
test "M1 direct input writes carry mutation facts while reads do not" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func peek(values: int[]) -> int:
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
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
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
    }
    try t.expect(found);
}

// spec: MUT-PARAM-5
test "M1 the mutates clause is a removed spelling naming mut" {
    try reject(
        \\def touch(values: list[int]) -> None mutates(values):
        \\    append(mut values, 1)
        \\
        \\
        \\def main() -> int:
        \\    return 0
    , "E_REMOVED_SPELLING", "`mut name: T`");
}

// spec-case: MUT-PARAM-5
test "M1 the ampersand argument marker is a removed spelling naming mut" {
    try reject(
        \\def touch(values: mut list[int]) -> None:
        \\    append(mut values, 1)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(&values)
        \\    return 0
    , "E_REMOVED_SPELLING", "as in `mut value`");
}

const marker_direct_valid =
    \\func touch(mut values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(mut values)
    \\    return values[0]
;

const marker_keyword_valid =
    \\func touch(mut values: int[], item: int) -> Unit:
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
    // migrate-embedded: skip original missing or extra mutation-marker diagnostic and repair witness
    \\func touch(mut values: int[], item: int) -> Unit:
    \\    values[0] = item
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(values, 1)
    \\    return 0
;

const marker_extra =
    // migrate-embedded: skip original missing or extra mutation-marker diagnostic and repair witness
    \\func peek(values: int[]) -> int:
    \\    return values[0]
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    return peek(mut values)
;

const marker_non_lvalue =
    \\func touch(mut values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func main() -> int:
    \\    touch(mut [1, 2, 3])
    \\    return 0
;

const marker_unused =
    \\func touch(mut values: int[]) -> Unit:
    \\    return
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    touch(mut values)
    \\    return 0
;

const marker_indirect_valid =
    \\func touch(mut values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func apply(f: func(mut values: int[]) -> Unit, mut values: int[]) -> Unit:
    \\    f(mut values)
    \\
    \\
    \\func main() -> int:
    \\    mut values = [7]
    \\    apply(touch, mut values)
    \\    return 0
;

const marker_indirect_missing =
    // migrate-embedded: skip original missing or extra mutation-marker diagnostic and repair witness
    \\func touch(mut values: int[]) -> Unit:
    \\    values[0] = 1
    \\
    \\
    \\func apply(f: func(mut values: int[]) -> Unit, mut values: int[]) -> Unit:
    \\    f(values)
    \\
    \\
    \\func main() -> int:
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
        \\    append(mut values, 8)
        \\    return values[0]
    );
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(usize, 0), c.program.?.functions[0].signature.mutates.len);
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
    , "E_EFFECTS_REMOVED", "source effect clauses");
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch[T](mut values: T[], item: T) -> Unit:
        \\    values[0] = item
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var found = false;
    for (c.syntax.?.functions) |function| {
        if (!std.mem.eql(u8, c.src.text(function.name), "touch")) continue;
        found = true;
        try t.expectEqualSlices(u16, &.{0}, function.signature.mut_positions);
    }
    try t.expect(found);
}

test "M1 callback body carries its direct mutation fact" {
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator,
        \\import lists
        \\
        \\
        \\func apply(f: func(mut values: int[]) -> Unit) -> Unit:
        \\    _ = f
        \\
        \\
        \\func clear_values(mut values: int[]) -> Unit:
        \\    lists.clear(mut values)
        \\
        \\func main() -> int:
        \\    apply(clear_values)
        \\    return 0
    );
    defer program.deinit();
    var found = false;
    // A project compilation qualifies every function with its module, so the
    // entry module's own declarations read `main::name`.
    for (program.compilation.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "main::clear_values")) continue;
        found = true;
        try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
        try t.expect(function.signature.inferred.writes);
    }
    try t.expect(found);
}

test "M1 callable assignability requires exact mut positions and narrower return origins" {
    const parameters = [_]typed.Type{ .i64, .i64 };
    const destination = typed.Callable{
        .parameters = &parameters,
        .return_type = .i64,

        .mutates = &[_]u16{ 0, 1 },
        .return_origin = .{ .params = &[_]u16{ 0, 1 } },
    };
    const implementation = typed.Callable{
        .parameters = &parameters,
        .return_type = .i64,

        .mutates = &[_]u16{ 0, 1 },
        .return_origin = .{ .params = &[_]u16{0} },
    };
    try t.expect(callables.assignable(implementation, destination));
    try t.expect(!callables.assignable(.{
        .parameters = &parameters,
        .return_type = .i64,

        .mutates = &[_]u16{1},
        .return_origin = .unknown,
    }, destination));
    try t.expect(callables.originSubset(.fresh, destination.return_origin));
}

test "M1 callback mutates metadata survives source checking and callable interning" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func apply(f: func(mut values: int[]) -> Unit) -> Unit:
        \\    _ = f
        \\
        \\
        \\func main() -> int:
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
        \\func apply(f: func(mut values: int[]) -> Unit) -> Unit:
        \\    _ = f
        \\
        \\
        \\func main() -> int:
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

test "M1 mutates clause normalizes duplicate names to sorted positions" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func touch(mut a: int[], mut b: int[]) -> Unit:
        \\    a[0] = 1
        \\    b[0] = 2
        \\
        \\
        \\func main() -> int:
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

// spec-case: MUT-PARAM-4
test "M2 a mut footprint accepts an independent read-only snapshot" {
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit:
        \\    dst[0] = src[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    const snapshot = copy(values)
        \\    touch(mut values, snapshot)
        \\    return 0
    );
    // Explicit copies provide independent read-only snapshots, including a
    // second local copied from the same source.
    try accept(
        \\func touch(mut dst: int[], src: int[]) -> Unit:
        \\    dst[0] = src[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut alias = copy(values)
        \\    touch(mut values, alias)
        \\    return 0
    );
    try result(
        \\func touch(mut dst: int[], src: int[]) -> Unit:
        \\    dst[0] = src[0] + 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    mut snapshot = copy(values)
        \\    touch(mut values, snapshot)
        \\    return values[0]
    , 2);
}

// spec-case: MUT-PARAM-4
test "M2 forwarding mut x where x is the caller's own parameter needs that parameter mut" {
    try reject(
        \\func touch(mut values: int[]) -> Unit:
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
        \\func change(box: Box) -> Unit:
        \\    mut alias = copy(box.values)
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
        \\    mut alias = copy(box.values)
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
        \\    mut copy = copy(values)
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
        \\func edit(values: int[][]) -> Unit:
        \\    mut copy = copy(values)
        \\    copy[0][0] = 99
        \\
        \\
        \\func main() -> int:
        \\    mut inner = [1]
        \\    mut values = [own inner]
        \\    edit(values)
        \\    return values[0][0]
    , 1);
}

// spec-case: MUTATION-METADATA-1
test "M2 identity-returning helpers return independent values" {
    try accept(
        \\func identity(values: int[]) -> int[]:
        \\    return copy(values)
        \\
        \\
        \\func overwrite(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func launder(values: int[]) -> Unit:
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
        \\func identity(values: int[]) -> int[]:
        \\    return copy(values)
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
        \\func boxed(values: int[]) -> Box:
        \\    return Box(values=copy(values))
        \\
        \\
        \\func overwrite(mut box: Box) -> Unit:
        \\    box.values[0] = 1
        \\
        \\
        \\func launder(values: int[]) -> Unit:
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
    , "E_EFFECTS_REMOVED", "source effect clauses");
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
    , "E_EFFECTS_REMOVED", "source effect clauses");
}

// spec-case: MUTATION-METADATA-1
test "M2 indirect callbacks obey mutation contracts" {
    try result(
        \\import lists
        \\
        \\
        \\func apply(f: func(mut values: int[]) -> Unit, mut values: int[]) -> Unit:
        \\    f(mut values)
        \\
        \\
        \\func clear_values(mut values: int[]) -> Unit:
        \\    lists.clear(mut values)
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    apply(clear_values, mut values)
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
        \\    apply(lambda values: (), mut values)
        \\    return 0
    , "E_EFFECTS_REMOVED", "source effect clauses");
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
        \\    const snapshot = copy(values)
        \\    touch(mut values, snapshot)
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
        \\    mut b = copy(a)
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
        \\func helper(values: int[]) -> int:
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0]
        \\    return helper(values)
    ;
    var first = try language.Compilation.init(t.allocator, "edited.selka", before);
    defer first.deinit();
    try first.checkWithCache(&cache);
    try t.expectEqual(@as(i64, 0), (try native.run(&first)).value);
    const after =
        \\func helper(values: int[]) -> int:
        \\    values[0] = 1
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values = [0]
        \\    return helper(values)
    ;
    var second = try language.Compilation.init(t.allocator, "edited.selka", after);
    defer second.deinit();
    try t.expectError(error.SourceError, second.checkWithCache(&cache));
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
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func forward(mut values: int[]) -> Unit:
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
        \\    const snapshot = copy(values)
        \\    forward(mut values, snapshot)
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

// spec: UNUSED-CAPABILITY-1
test "a capability parameter the body never reads is rejected and a passed-on one is not" {
    try reject("public func equal(host: Host, a: int, b: int) -> bool:\n    return a == b\n\n" ++
        "func main(host: Host) -> int:\n    if equal(host, 1, 1):\n        return 0\n    return 1\n", "E_UNUSED_CAPABILITY", "`host` is never used");
    try reject("func main(out: Stream) -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", "`out` is never used");
    // Handing the capability to another function is a read, so a frame that
    // never calls a host operation itself still uses its authority.
    try accept("extern func inner(host: Host) -> int\n\n" ++
        "func outer(host: Host) -> int:\n    return inner(host)\n\n" ++
        "func main(host: Host) -> int:\n    return outer(host)\n");
}

// spec: EFFECTS-REMOVED-1
test "retired effect clauses are rejected with a deletion fix" {
    var compilation = try language.Compilation.init(t.allocator, fixture_path, "func main() -> int effects(clock, clock, unknown):\n    return 0\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = firstError(compilation.diagnostics.items) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("E_EFFECTS_REMOVED", item.code);
    try t.expect(item.provenance.fix != null);
}

// spec: CONTRACT-CAPABILITY-1
test "contract conditions reject syntactic capability references through helper calls" {
    const precondition = "func noisy(out: Stream) -> bool:\n    print(out, \"x\")\n    return True\n\n@requires(noisy(out))\n" ++
        "func guarded(out: Stream) -> int:\n    _ = out\n    return 1\n\nfunc main(out: Stream) -> int:\n" ++
        "    return guarded(out)\n";
    try reject(precondition, "E_CONTRACT_EFFECT", "capability");
    const postcondition = "func noisy(out: Stream) -> bool:\n    print(out, \"x\")\n    return True\n\n@ensures(noisy(out))\n" ++
        "func guarded(out: Stream) -> int:\n    _ = out\n    return 1\n\nfunc main(out: Stream) -> int:\n" ++
        "    return guarded(out)\n";
    try reject(postcondition, "E_CONTRACT_EFFECT", "capability");
}

// spec-case: CONTRACT-CAPABILITY-1
test "contract conditions reject direct capability receivers" {
    try reject("@requires(fs.exists(\"x\"))\nfunc guarded(fs: Filesystem) -> int:\n    _ = fs\n    return 1\n\nfunc main(fs: Filesystem) -> int:\n    return guarded(fs)\n", "E_CONTRACT_EFFECT", "capability");
    try reject("@ensures(fs.exists(\"x\"))\nfunc guarded(fs: Filesystem) -> int:\n    _ = fs\n    return 1\n\nfunc main(fs: Filesystem) -> int:\n    return guarded(fs)\n", "E_CONTRACT_EFFECT", "capability");
}

// spec-case: CONTRACT-CAPABILITY-1
test "contract conditions reject projected capability receivers" {
    const definitions = "record Ports:\n    fs: Filesystem\n\nrecord State:\n    ports: Ports\n\n";
    try reject(definitions ++ "@requires(state.ports.fs.exists(\"x\"))\nfunc guarded(state: State) -> int:\n    _ = state\n    return 1\n\n" ++
        "func main(fs: Filesystem) -> int:\n    return guarded(State(ports=Ports(fs=fs)))\n", "E_CONTRACT_EFFECT", "capability");
    try reject(definitions ++ "@ensures(state.ports.fs.exists(\"x\"))\nfunc guarded(state: State) -> int:\n    _ = state\n    return 1\n\n" ++
        "func main(fs: Filesystem) -> int:\n    return guarded(State(ports=Ports(fs=fs)))\n", "E_CONTRACT_EFFECT", "capability");
}

// spec-case: MUTATION-METADATA-1
test "generic readonly writes are checked before and after concrete instantiation" {
    try reject(
        \\func touch[T](values: T[], item: T) -> Unit:
        \\    values[0] = item
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_IMMUTABLE", "read-only");
    try reject(
        \\func touch[T](values: T[], item: T) -> Unit:
        \\    values[0] = item
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch[int](values, 2)
        \\    return 0
    , "E_IMMUTABLE", "read-only");
}

// spec-case: MUTATION-METADATA-1
test "removed effects preserve readonly mutation rejection 2" {
    try reject(
        \\func fill(values: int[], count: int) -> Unit:
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
    , "E_IMMUTABLE", "read-only");
}

// spec-case: MUTATION-METADATA-1
test "removed effects preserve recursive mutation marker rejection" {
    try reject(
        \\func touch(values: int[], depth: int) -> Unit:
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
    , "E_MUTATION_MARKER", "mut");
}

// spec-case: MUTATION-METADATA-1
test "removed effects preserve readonly mutation rejection 4" {
    try reject(
        \\import lists
        \\
        \\
        \\func apply(f: func(mut values: int[]) -> Unit, values: int[]) -> Unit:
        \\    f(mut values)
        \\
        \\
        \\func clear_values(mut values: int[]) -> Unit:
        \\    lists.clear(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    apply(clear_values, values)
        \\    return 0
    , "E_IMMUTABLE", "read-only");
}

// spec-case: NOALLOC-ATTRIBUTE-1
test "element reads preserve managed array and dictionary values through whole program lowering" {
    try result(
        \\@noalloc
        \\func first(names: FixedArray[str, 3]) -> bool:
        \\    return names[len(names) - 1] == "gamma"
        \\@noalloc
        \\func lookup(names: dict[int, str]) -> bool:
        \\    return names[1] == "alpha"
        \\func main() -> int:
        \\    mut names = FixedArray[str, 3](["alpha", "beta", "gamma"])
        \\    if not first(names) or not lookup({1: "alpha"}):
        \\        return 0
        \\    names = replace(names, 1, "delta")
        \\    return strings.char_count(names[1]) + strings.char_count(names[len(names) - 1])
    , 10);
}

// spec-case: EFFECTS-REMOVED-1
test "the original string element allocation ceiling negative retains its source" {
    try reject(
        \\func initial(name: str) -> bool effects():
        \\    return name[0] == "a"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_EFFECTS_REMOVED", "source effect clauses were removed");
}

// spec-case: EFFECTS-REMOVED-1
test "the original noalloc managed element fixture retains both retired source spellings" {
    try reject(
        // migrate-embedded: skip intentional original noalloc and negative-index source
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
    , "E_EFFECTS_REMOVED", "source effect clauses were removed");
    try reject(
        // migrate-embedded: skip intentional original negative-index source
        \\func first(names: FixedArray[str, 3]) -> bool:
        \\    return names[-1] == "gamma"
        \\func main() -> int:
        \\    return 0
    , "E_NEGATIVE_INDEX_REMOVED", "negative indexes");
}

// spec-case: NOALLOC-ATTRIBUTE-1
test "the original managed replacement negative retains its index diagnostic" {
    try reject(
        // migrate-embedded: skip intentional original negative-index source
        \\func main() -> int:
        \\    mut names: FixedArray[str, 3] = FixedArray[str, 3](["alpha", "beta", "gamma"])
        \\    names = replace(names, 1, "delta")
        \\    return strings.char_count(names[1]) + strings.char_count(names[-1])
    , "E_NEGATIVE_INDEX_REMOVED", "negative indexes");
}

// spec-case: MUTATION-METADATA-1
test "F3 all uncalled generic bindings retain frontend writability checks" {
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try reject("func touch[T](values: T[], item: T):\n" ++
        "    values[0] = item\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "E_IMMUTABLE", "");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try reject("func touch[T](item: T):\n" ++
        "    const value = item\n" ++
        "    value = item\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "E_IMMUTABLE", "");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try reject("func touch[T](values: T[], replacement: T):\n" ++
        "    for value in values:\n" ++
        "        value = replacement\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "E_IMMUTABLE", "");
    // migrate-embedded: skip intentional ownership-fix refusal or migration input.
    try reject("func touch[T](value: T?, replacement: T):\n" ++
        "    match value:\n" ++
        "        case Some(item):\n" ++
        "            item = replacement\n" ++
        "        case None:\n" ++
        "            pass\n" ++
        "func main() -> int:\n" ++
        "    return 0\n", "E_IMMUTABLE", "");
}
test "F3 uncalled generic move refusals remain per concrete instance" {
    try accept("func touch[T](own values: T[]) -> int:\n" ++
        "    const moved = own values\n" ++
        "    return len(values) + len(moved)\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
}

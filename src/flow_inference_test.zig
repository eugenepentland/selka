//! Rejection and allocation coverage for Option flow facts and contextual generic calls.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "flow.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: OPTION-FLOW-3
test "flow inference forgets reassigned and branch-dependent Option facts" {
    try reject(
        \\func main() -> int:
        \\    mut value: int? = Some(42)
        \\    if value is None:
        \\        return 0
        \\    value = None
        \\    return value
    , "E_TYPE");
    try reject(
        \\func get(value: int?, flag: bool) -> int:
        \\    if flag:
        \\        if value is None:
        \\            return 0
        \\    return value
        \\func main() -> int:
        \\    return get(None, False)
    , "E_TYPE");
}

// spec-case: OPTION-FLOW-3
test "flow inference rejects stale loop-carried and zero-iteration facts" {
    try reject(
        \\func get(value: int?, flag: bool) -> int:
        \\    if value is None:
        \\        return 0
        \\    while flag:
        \\        _ = value + 1
        \\        value = None
        \\    return 0
        \\func main() -> int:
        \\    return get(Some(1), False)
    , "E_TYPE");
    try reject(
        \\func get(value: int?) -> int:
        \\    for i in range(0):
        \\        _ = i
        \\        if value is None:
        \\            return 0
        \\    return value
        \\func main() -> int:
        \\    return get(None)
    , "E_TYPE");
}

// spec-case: OPTION-FLOW-2
test "flow inference does not infer presence from an unsafe Boolean alternative" {
    try reject(
        \\func get(value: int?, flag: bool) -> int:
        \\    if value is not None or flag:
        \\        return value
        \\    return 0
        \\func main() -> int:
        \\    return get(None, True)
    , "E_TYPE");
}

// spec-case: OPTION-FLOW-3
test "flow inference rejects unsafe uninstantiated template paths" {
    try reject(
        \\func unsafe[T: copy + storable](input: T?, other: T) -> T:
        \\    mut value = input
        \\    if value is None:
        \\        return other
        \\    value = None
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_TYPE");
}

// spec-case: OPTION-FLOW-1
// spec-case: GENERIC-EXPECTED-1
test "flow inference formatter preserves guards and inferred specialization reuse" {
    var compilation = try language.Compilation.init(t.allocator, "format.selka", checked_source);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "is not None") != null);
    var reparsed = try language.Compilation.init(t.allocator, "format.selka", formatted);
    defer reparsed.deinit();
    try reparsed.check();
    try t.expectEqual(@as(usize, 3), reparsed.program.?.functions.len);
}

// spec: GENERIC-EXPECTED-3
test "flow inference rejects conflicting missing and unsatisfied contextual arguments" {
    try reject(
        \\func identity[T](value: T) -> T:
        \\    return value
        \\func main() -> int:
        \\    mut value: int = identity(1u8)
        \\    return value
    , "E_GENERIC_INFERENCE");
    try reject(
        \\func zero[T: integer]() -> T:
        \\    return T(0)
        \\func main() -> int:
        \\    mut value = zero()
        \\    return value
    , "E_GENERIC_INFERENCE");
    try reject(
        \\func zero[T: integer]() -> T:
        \\    return T(0)
        \\func main() -> int:
        \\    mut value: bool = zero()
        \\    if value:
        \\        return 0
        \\    return 1
    , "E_GENERIC_ARGUMENT");
}

// spec-case: GENERIC-EXPECTED-2
test "flow inference retains symbolic conflicts in uninstantiated templates" {
    try reject(
        \\func identity[T](value: T) -> T:
        \\    return value
        \\func conflict[U](value: U) -> int:
        \\    return identity(value)
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_INFERENCE");
}

const checked_source =
    \\func zero[T: integer]() -> T:
    \\    return T(0)
    \\func fallback[T: copy + storable](value: T?, other: T) -> T:
    \\    if value is None:
    \\        return other
    \\    return value
    \\func main() -> int:
    \\    mut optional: int? = Some(42)
    \\    mut value: int = fallback(optional, zero())
    \\    if optional is not None and optional > 0:
    \\        return value + optional
    \\    return zero[int]()
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "flow.selka", checked_source);
    defer compilation.deinit();
    try compilation.check();
    try t.expect(compilation.program != null);
}

// spec-case: OPTION-FLOW-1
// spec-case: GENERIC-EXPECTED-1
test "flow inference allocation failures release conditional facts and substitutions" {
    try allocationScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

//! Rejection and allocation coverage for Option flow facts and contextual generic calls.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "flow.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: OPTION-FLOW-3
test "flow inference forgets reassigned and branch-dependent Option facts" {
    try reject(
        \\def main() -> int:
        \\    value: Option[int] = Some(42)
        \\    if value is None:
        \\        return 0
        \\    value = None
        \\    return value
    , "E_TYPE");
    try reject(
        \\def get(value: Option[int], flag: bool) -> int:
        \\    if flag:
        \\        if value is None:
        \\            return 0
        \\    return value
        \\def main() -> int:
        \\    return get(None, False)
    , "E_TYPE");
}

// spec-case: OPTION-FLOW-3
test "flow inference rejects stale loop-carried and zero-iteration facts" {
    try reject(
        \\def get(value: Option[int], flag: bool) -> int:
        \\    if value is None:
        \\        return 0
        \\    while flag:
        \\        _ = value + 1
        \\        value = None
        \\    return 0
        \\def main() -> int:
        \\    return get(Some(1), False)
    , "E_TYPE");
    try reject(
        \\def get(value: Option[int]) -> int:
        \\    for i in range(0):
        \\        _ = i
        \\        if value is None:
        \\            return 0
        \\    return value
        \\def main() -> int:
        \\    return get(None)
    , "E_TYPE");
}

// spec-case: OPTION-FLOW-2
test "flow inference does not infer presence from an unsafe Boolean alternative" {
    try reject(
        \\def get(value: Option[int], flag: bool) -> int:
        \\    if value is not None or flag:
        \\        return value
        \\    return 0
        \\def main() -> int:
        \\    return get(None, True)
    , "E_TYPE");
}

// spec: OPTION-FLOW-4
test "flow inference keeps heap fields and checked payloads explicit" {
    try reject(
        \\class Box:
        \\    item: Option[int]
        \\def get(box: Box) -> int:
        \\    if box.item is None:
        \\        return 0
        \\    return box.item
        \\def main() -> int:
        \\    return get(Box(item=None))
    , "E_TYPE");
    try reject(
        \\union CheckedMaybe:
        \\    some: Result[int, int],
        \\    none
        \\def main() -> int:
        \\    value: CheckedMaybe = CheckedMaybe.some(Ok(42))
        \\    if value is None:
        \\        return 0
        \\    return 1
    , "E_OPTION_TEST");
    try reject(
        \\def main() -> int:
        \\    if 42 is None:
        \\        return 0
        \\    return 1
    , "E_OPTION_TEST");
    try reject(
        \\const VALUE: bool = 42 is None
        \\def main() -> int:
        \\    return 0
    , "E_OPTION_TEST");
}

// spec-case: OPTION-FLOW-3
test "flow inference rejects unsafe uninstantiated template paths" {
    try reject(
        \\def unsafe[T: copy + storable](value: Option[T], other: T) -> T:
        \\    if value is None:
        \\        return other
        \\    value = None
        \\    return value
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_TYPE");
}

// spec-case: OPTION-FLOW-1
// spec-case: GENERIC-EXPECTED-1
test "flow inference formatter preserves guards and inferred specialization reuse" {
    var compilation = try language.Compilation.init(t.allocator, "format.my", checked_source);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "is not None") != null);
    var reparsed = try language.Compilation.init(t.allocator, "format.my", formatted);
    defer reparsed.deinit();
    try reparsed.check();
    try t.expectEqual(@as(usize, 3), reparsed.program.?.functions.len);
}

// spec: GENERIC-EXPECTED-3
test "flow inference rejects conflicting missing and unsatisfied contextual arguments" {
    try reject(
        \\def identity[T](value: T) -> T:
        \\    return value
        \\def main() -> int:
        \\    value: int = identity(1u8)
        \\    return value
    , "E_GENERIC_INFERENCE");
    try reject(
        \\def zero[T: integer]() -> T:
        \\    return T(0)
        \\def main() -> int:
        \\    value = zero()
        \\    return value
    , "E_GENERIC_INFERENCE");
    try reject(
        \\def zero[T: integer]() -> T:
        \\    return T(0)
        \\def main() -> int:
        \\    value: bool = zero()
        \\    if value:
        \\        return 0
        \\    return 1
    , "E_GENERIC_ARGUMENT");
}

// spec-case: GENERIC-EXPECTED-2
test "flow inference retains symbolic conflicts in uninstantiated templates" {
    try reject(
        \\def identity[T](value: T) -> T:
        \\    return value
        \\def conflict[U](value: U) -> int:
        \\    return identity(value)
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_INFERENCE");
}

const checked_source =
    \\def zero[T: integer]() -> T:
    \\    return T(0)
    \\def fallback[T: copy + storable](value: Option[T], other: T) -> T:
    \\    if value is None:
    \\        return other
    \\    return value
    \\def main() -> int:
    \\    optional: Option[int] = Some(42)
    \\    value: int = fallback(optional, zero())
    \\    if optional is not None and optional > 0:
    \\        return value + optional
    \\    return zero[int]()
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "flow.my", checked_source);
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

//! Concrete schemas remain nominal while unrelated generic arguments stay symbolic.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const schema =
    \\class Sample:
    \\    values: [2]i64
    \\    tag: u8
    \\
    \\
    \\
;
const program = schema ++
    \\def make[T: integer](x: T) -> Sample:
    \\    return Sample(values=[i64(x), i64(x) + 1], tag=7u8)
    \\
    \\
    \\def total[T](x: T, s: Sample) -> i64:
    \\    _ = x
    \\    return s.values[0] + s.values[1] + i64(len(s.values))
    \\
    \\
    \\def choose[T](x: T, a: Sample, b: Sample) -> Sample:
    \\    _ = x
    \\    if a.tag == b.tag:
    \\        return a
    \\    return b
    \\
    \\
    \\def main() -> i64:
    \\    p = make[u8](7u8)
    \\    return total[bool](True, choose[i64](0, p, p))
;
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "concrete.my", program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 17), (try native.run(&c)).value);
}
// spec: GENERIC-CONCRETE-1
test "generic concrete records and arrays retain checked shapes under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(bytes: []const u8, expected: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(expected, c.diagnostics.items[0].code);
}
const updates =
    \\record Pair:
    \\    values: [2]i64
    \\    flag: bool
    \\
    \\
    \\def change[T: integer](p: Pair, index: T, value: i64) -> Pair:
    \\    q = p
    \\    q.values = replace(p.values, index, value)
    \\    return q
    \\
    \\
    \\def main() -> i64:
    \\    original = Pair(values=[7, 8], flag=True)
    \\    changed = change[u8](original, 0u8, 20)
    \\    if changed.flag:
    \\        return original.values[0] + changed.values[0] + changed.values[1]
    \\    return 0
;
fn updateScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "updates.my", updates);
    defer c.deinit();
    try t.expectEqual(@as(i64, 35), (try native.run(&c)).value);
    var table = try language.Compilation.init(allocator, "table-update.my",
        \\enum Key:
        \\    first,
        \\    second
        \\
        \\
        \\def put[T: integer](p: [Key]i64, key: Key, value: T) -> [Key]i64:
        \\    return replace(p, key, i64(value))
        \\
        \\
        \\def main() -> i64:
        \\    old: [Key]i64 = {Key.first: 1, Key.second: 2}
        \\    changed = put[u8](old, Key.first, 8u8)
        \\    return old[Key.first] + changed[Key.first]
    );
    defer table.deinit();
    try t.expectEqual(@as(i64, 9), (try native.run(&table)).value);
}
// spec: GENERIC-UPDATE-1
test "generic record updates and array replacement preserve snapshots under allocation failures" {
    try updateScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), updateScenario, .{});
}
const variants =
    \\class Payload:
    \\    n: i64
    \\
    \\
    \\enum Color:
    \\    red,
    \\    blue
    \\
    \\
    \\union Choice:
    \\    none,
    \\    value: Payload
    \\
    \\
    \\def make[T: integer](x: T) -> Choice:
    \\    return Choice.value(Payload(n=i64(x)))
    \\
    \\
    \\def score[T](context: T, x: Choice) -> i64:
    \\    _ = context
    \\    match x:
    \\        case Choice.none:
    \\            return 0
    \\        case Choice.value(p):
    \\            return p.n
    \\
    \\
    \\def color[T](context: T) -> Color:
    \\    _ = context
    \\    return Color.blue
    \\
    \\
    \\def mapping[T: integer](x: T) -> [Color]i64:
    \\    return {Color.red: i64(x), Color.blue: 0}
    \\
    \\
    \\def main() -> i64:
    \\    match color[bool](True):
    \\        case Color.red:
    \\            return 0
    \\        case Color.blue:
    \\            return score[i64](0, make[u8](7u8)) + mapping[u8](2u8)[Color.red]
;
fn variantScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "variants.my", variants);
    defer c.deinit();
    try t.expectEqual(@as(i64, 9), (try native.run(&c)).value);
}
// spec: GENERIC-VARIANT-1
test "generic concrete variants construct and match with scoped payloads under allocation failures" {
    try variantScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), variantScenario, .{});
}

test "generic concrete shapes reject mismatched nominal values and malformed constructors before instantiation" {
    try reject(
        \\class A:
        \\    n: i64
        \\
        \\
        \\class B:
        \\    n: i64
        \\
        \\
        \\def f[T](x: A) -> B:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(
        \\class A:
        \\    n: i64
        \\
        \\
        \\def f[T](x: T) -> A:
        \\    _ = x
        \\    return A()
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_MISSING_FIELD");
    try reject(
        \\class A:
        \\    n: i64
        \\    m: i64
        \\
        \\
        \\def f[T](x: T) -> A:
        \\    _ = x
        \\    return A(n=1, n=2)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_FIELD");
    try reject(
        \\class A:
        \\    n: i64
        \\
        \\
        \\def f[T](x: A) -> i64:
        \\    return x.other
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FIELD");
    try reject(
        \\def f[T](x: T) -> [2]i64:
        \\    _ = x
        \\    return [1]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_ARRAY_LENGTH");
    try reject(
        \\def f[T](x: [2]i64) -> i64:
        \\    return x[True]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_OPERATION");
    try reject(
        \\def f[T](x: T) -> i64:
        \\    return x.n
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}

test "generic concrete variants reject incomplete duplicate and malformed uncalled matches" {
    try reject(
        \\enum E:
        \\    a,
        \\    b
        \\
        \\
        \\def f[T](x: E) -> i64:
        \\    match x:
        \\        case E.a:
        \\            return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_MATCH");
    try reject(
        \\enum E:
        \\    a
        \\
        \\
        \\def f[T](x: E) -> i64:
        \\    match x:
        \\        case E.a:
        \\            return 1
        \\        case E.a:
        \\            return 2
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_ARM");
    try reject(
        \\union E:
        \\    a: i64
        \\
        \\
        \\def f[T](x: E) -> i64:
        \\    match x:
        \\        case E.a:
        \\            return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_PATTERN_PAYLOAD");
    try reject(
        \\enum E:
        \\    a
        \\
        \\
        \\def f[T](x: E) -> i64:
        \\    match x:
        \\        case E.a(p):
        \\            return p
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_PATTERN_PAYLOAD");
    try reject(
        \\union E:
        \\    a: i64
        \\
        \\
        \\def f[T](x: T) -> E:
        \\    _ = x
        \\    return E.a(True)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(
        \\union E:
        \\    a: i64
        \\
        \\
        \\def f[T](x: T) -> E:
        \\    _ = x
        \\    return E.a
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_VARIANT_PAYLOAD");
    try reject(
        \\enum E:
        \\    a
        \\
        \\
        \\enum F:
        \\    a
        \\
        \\
        \\def f[T](x: E) -> i64:
        \\    match x:
        \\        case F.a:
        \\            return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
}

test "generic match payload scopes and fallthrough preserve independent arm checking" {
    var c = try language.Compilation.init(t.allocator, "arms.my",
        \\union U:
        \\    left: i64,
        \\    right: i64
        \\
        \\
        \\def f[T](x: T, u: U) -> i64:
        \\    _ = x
        \\    out = 0
        \\    match u:
        \\        case U.left(p):
        \\            out = p
        \\        case U.right(p):
        \\            out = p + 1
        \\    return out
        \\
        \\
        \\def main() -> i64:
        \\    return f[bool](True, U.left(7)) + f[bool](False, U.right(8))
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 16), (try native.run(&c)).value);
    try reject(
        \\union U:
        \\    a: i64
        \\
        \\
        \\def f[T](u: U) -> i64:
        \\    match u:
        \\        case U.a(p):
        \\            _ = p
        \\    return p
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_NAME");
    try reject(
        \\enum U:
        \\    a,
        \\    b
        \\
        \\
        \\def f[T](u: U) -> i64:
        \\    match u:
        \\        case U.a:
        \\            pass
        \\        case U.b:
        \\            return True
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(
        \\enum U:
        \\    a,
        \\    b
        \\
        \\
        \\def f[T](u: U) -> i64:
        \\    match u:
        \\        case U.a:
        \\            pass
        \\        case U.b:
        \\            return 1
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_MISSING_RETURN");
}

test "generic concrete enum tables require complete unique nominal keys" {
    var c = try language.Compilation.init(t.allocator, "table.my",
        \\enum K:
        \\    a,
        \\    b
        \\
        \\
        \\def table[T: integer](x: T) -> [K]i64:
        \\    return {K.a: i64(x), K.b: 2}
        \\
        \\
        \\def main() -> i64:
        \\    return table[u8](7u8)[K.a]
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&c)).value);
    try reject(
        \\enum K:
        \\    a,
        \\    b
        \\
        \\
        \\def f[T](x: T) -> [K]i64:
        \\    _ = x
        \\    return {K.a: 1}
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_TABLE");
    try reject(
        \\enum K:
        \\    a
        \\
        \\
        \\def f[T](x: T) -> [K]i64:
        \\    _ = x
        \\    return {K.a: 1, K.a: 2}
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_DUPLICATE_KEY");
}

const semantic_key = @import("semantic_key.zig");

// spec-case: SEMANTIC-CACHE-12
test "canonical specialization keys distinguish every keyed dimension and argument order" {
    const allocator = t.allocator;
    const base = try semantic_key.specializationFingerprint(allocator, .{
        .template_identity = "pkg::render",
        .arguments = &.{ "T:i64", "L:3" },
        .provider = "provider-a",
        .constraints = "constraints-a",
        .contracts = "contracts-a",
        .build = "build-a",
    });
    defer allocator.free(base);
    const same = try semantic_key.specializationFingerprint(allocator, .{
        .template_identity = "pkg::render",
        .arguments = &.{ "T:i64", "L:3" },
        .provider = "provider-a",
        .constraints = "constraints-a",
        .contracts = "contracts-a",
        .build = "build-a",
    });
    defer allocator.free(same);
    try t.expectEqualStrings(base, same);

    const changed_inputs = [_]semantic_key.SpecializationInputs{
        .{ .template_identity = "pkg::other", .arguments = &.{ "T:i64", "L:3" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:u8", "L:3" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:i64", "L:4" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "L:3", "T:i64" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:i64", "L:3" }, .provider = "provider-b", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:i64", "L:3" }, .provider = "provider-a", .constraints = "constraints-b", .contracts = "contracts-a", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:i64", "L:3" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-b", .build = "build-a" },
        .{ .template_identity = "pkg::render", .arguments = &.{ "T:i64", "L:3" }, .provider = "provider-a", .constraints = "constraints-a", .contracts = "contracts-a", .build = "build-b" },
    };
    for (changed_inputs) |variant| {
        const changed = try semantic_key.specializationFingerprint(allocator, variant);
        defer allocator.free(changed);
        try t.expect(!std.mem.eql(u8, base, changed));
    }

    const length_descriptor = try semantic_key.argumentDescriptor(allocator, .u64, 3, &.{});
    defer allocator.free(length_descriptor);
    try t.expectEqualStrings("L:3", length_descriptor);
    const type_descriptor = try semantic_key.argumentDescriptor(allocator, .i64, null, &.{});
    defer allocator.free(type_descriptor);
    try t.expectEqualStrings("T:i64", type_descriptor);

    const bound = @import("effect_set.zig").Bound{ .span = .{ .start = 0, .end = 1 }, .allowed = 0 };
    const digest_a = semantic_key.declaredContractDigest(bound, &.{});
    const digest_b = semantic_key.declaredContractDigest(bound, &.{1});
    try t.expect(!std.mem.eql(u8, &digest_a, &digest_b));
}

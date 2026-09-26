//! Structural contracts are checked independently of specialization.
const std = @import("std");
const t = std.testing;
const print = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn run(bytes: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "structural.my", bytes);
    defer c.deinit();
    const result = native.run(&c) catch |err| {
        for (c.diagnostics.items) |diag| print("{s}: {s} ({s})\n", .{ diag.code, diag.message, c.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "structural-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
// spec: STRUCTURAL-LIMIT-1
test "structural declarations reject uncalled invalid access and incomplete construction" {
    try reject(
        \\def f[T: copy + field(value: i64)](v: T) -> bool:
        \\    return v.value
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    // A type parameter has no construction spelling: `T(...)` reads as a call.
    try reject(
        \\def f[T: copy + field(value: i64)]() -> T:
        \\    return T(value=1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FUNCTION");
    try reject(
        \\def f[T](v: T) -> i64:
        \\    return T.score(v)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "structural fields reject incomplete forwarding unknown fields and hidden obligations" {
    try reject(
        \\def get[T: copy + field(value: i64)](v: T) -> i64:
        \\    return v.value
        \\
        \\
        \\def forward[U](v: U) -> i64:
        \\    return get[U](v)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
    try reject(
        \\def get[T: copy + field(value: i64)](v: T) -> i64:
        \\    return v.hidden
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FIELD");
    try reject(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def get[T: copy + field(value: R)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\record Box[T: copy + field(value: i64)]:
        \\    item: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\def f[T: copy + field(value: i64) + field(value: i64)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\def f[T: copy + op(score(v: T) -> i64)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}
const domain =
    \\domain D: i64:
    \\    def make(n: i64) -> D:
    \\        return wrap[D](n)
    \\
    \\    def score(v: D) -> i64 effects():
    \\        return unwrap(v)
    \\
    \\
    \\
;
const operation =
    \\def apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64:
    \\    return T.score(v)
    \\
    \\
    \\
;
test "structural operation forwarding retains type identity and public contracts" {
    try run(domain ++ operation ++
        \\def forward[U: copy + op(score(v: U) -> i64 effects())](v: U) -> i64:
        \\    return apply[U](v)
        \\
        \\
        \\def main() -> i64:
        \\    return forward[D](D.make(11))
    , 11);
    try reject(operation ++
        \\def forward[U](v: U) -> i64:
        \\    return apply[U](v)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_ARGUMENT");
    try reject(
        \\def f[T: copy + op(score(v: T) -> bool effects())](v: T) -> i64:
        \\    return T.score(v)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(
        \\def f[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64:
        \\    return T.score(True)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
}
test "structural concrete operations reject private absent wrong typed and excessive effect methods" {
    try reject(
        \\domain D: i64:
        \\    def make() -> D:
        \\        return wrap[D](1)
        \\
        \\    private def score(v: D) -> i64 effects():
        \\        return unwrap(v)
        \\
        \\
        \\
    ++ operation ++
        \\def main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        \\domain D: i64:
        \\    def make() -> D:
        \\        return wrap[D](1)
        \\
        \\
        \\
    ++ operation ++
        \\def main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        \\domain D: i64:
        \\    def make() -> D:
        \\        return wrap[D](1)
        \\
        \\    def score(v: D) -> bool effects():
        \\        return True
        \\
        \\
        \\
    ++ operation ++
        \\def main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        \\domain D: i64:
        \\    def make() -> D:
        \\        return wrap[D](1)
        \\
        \\    def score(v: D) -> i64 effects(host):
        \\        return unwrap(v)
        \\
        \\
        \\
    ++ operation ++
        \\def main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        \\def f[T: copy + op(score(v: T) -> i64 effects(host))](v: T) -> i64 effects():
        \\    return T.score(v)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_EFFECT_BOUND");
}
const example = domain ++ operation ++
    \\record A:
    \\    value: i64
    \\
    \\
    \\def get[T: copy + field(value: i64)](v: T) -> i64:
    \\    return v.value
    \\
    \\
    \\def main() -> i64:
    \\    return get[A](A(value=5)) + apply[D](D.make(7))
;
fn lifecycle(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "structural.my", example);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    const again = try copy.format(allocator);
    defer allocator.free(again);
    try t.expectEqualStrings(formatted, again);
    try t.expectEqual(@as(i64, 12), (try native.run(&copy)).value);
}
test "structural formatter lifecycle round trips and releases storage under allocation failure" {
    try lifecycle(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), lifecycle, .{});
}
const module_files = [_]language.embedded_project.File{
    .{ .path = "main.my", .bytes =
    \\module main
    \\import api
    \\
    \\
    \\def main() -> i64:
    \\    return api.apply[api.D](api.D.make(13))
    },
    .{ .path = "api.my", .bytes =
    \\module api
    \\
    \\
    \\public domain D: i64:
    \\    def make(n: i64) -> D effects():
    \\        return wrap[D](n)
    \\
    \\    def score(v: D) -> i64 effects():
    \\        return unwrap(v)
    \\
    \\
    \\public def apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64 effects():
    \\    return T.score(v)
    },
};
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    return language.embedded_project.read(allocator, &module_files, path, limit);
}
test "structural imported operation dispatch survives AST source relocation" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 13), (try native.run(&program.compilation)).value);
}

// spec: STRUCTURAL-COMPOSITE-1
test "structural composite fields substitute arrays and nominal applications" {
    try run(
        \\record Box[U]:
        \\    value: U
        \\
        \\
        \\record A:
        \\    items: [2]i64
        \\    box: Box[i64]
        \\
        \\
        \\def get[T: copy + field(items: [2]U) + field(box: Box[U]), U](v: T) -> U:
        \\    return v.box.value
        \\
        \\
        \\def main() -> i64:
        \\    return get[A, i64](A(items=[1, 2], box=Box[i64](value=7)))
    , 7);
    try reject(
        \\def f[T: copy + field(items: [2]U), U](v: T) -> U:
        \\    return v.items[True]
    , "E_GENERIC_OPERATION");
}

const composite =
    \\record Box[U]:
    \\    value: U
    \\
    \\
    \\record A:
    \\    items: [2]i64
    \\    box: Box[i64]
    \\
    \\
    \\record B:
    \\    items: [2]bool
    \\    box: Box[bool]
    \\
    \\
    \\def get[T: copy + field(items: [2]U) + field(box: Box[U]), U](v: T) -> U:
    \\    return v.box.value
    \\
    \\
    \\def forward[V: copy + field(items: [2]W) + field(box: Box[W]), W](v: V) -> W:
    \\    return get[V, W](v)
    \\
    \\
    \\def main() -> i64:
    \\    flag = forward[B, bool](B(items=[True, False], box=Box[bool](value=True)))
    \\    if flag:
    \\        return forward[A, i64](A(items=[1, 2], box=Box[i64](value=7)))
    \\    return 0
;
fn compositeLifecycle(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "composite.my", composite);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&copy)).value);
}

// Confirm the shared contract executes, forwards, and interchanges with its inline equivalent.
// The subject substitutes by identity inside a composite requirement signature.
// All declared effects stay inside the required ceiling; exceeding it rejects conformance.
// spec: NAMED-CONSTRAINT-SEMANTICS-3
test "named constraint operation ceilings accept subsets and reject excess" {
    try run(
        \\constraint Priced[P] = copy + op(price(policy: P) -> int effects())
        \\
        \\domain D: int:
        \\    def make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    def price(policy: D) -> int effects():
        \\        return unwrap(policy)
        \\
        \\def total[P: Priced](policy: P) -> int effects():
        \\    return P.price(policy)
        \\
        \\def main() -> int:
        \\    return total[D](D.make(4))
    , 4);
    try reject(
        \\constraint Priced[P] = copy + op(price(policy: P, out: Stream) -> int effects())
        \\
        \\domain D: int:
        \\    def make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    def price(policy: D, out: Stream) -> int effects(output):
        \\        out.print("x")
        \\        return unwrap(policy)
        \\
        \\def total[P: Priced](policy: P, out: Stream) -> int effects():
        \\    return P.price(policy, out)
        \\
        \\def main(out: Stream) -> int:
        \\    return total[D](D.make(4), out)
    , "E_GENERIC_ARGUMENT");
}
// A weaker bound may not forward to a stronger one, even when the function is never called.
// spec: NAMED-CONSTRAINT-SEMANTICS-4
test "named constraints reject weaker to stronger forwarding universally" {
    try reject(
        \\constraint HasValue[T] = copy + field(value: int)
        \\
        \\def read[T: HasValue](v: T) -> int:
        \\    return v.value
        \\
        \\def forward[U: copy](v: U) -> int:
        \\    return read[U](v)
        \\
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
    try reject(
        \\def read[T: copy + field(value: int)](v: T) -> int:
        \\    return v.value
        \\
        \\def forward[U: copy](v: U) -> int:
        \\    return read[U](v)
        \\
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}
// Expansion counts unique explicit requirements, including those added by a named bundle.
// spec: NAMED-CONSTRAINT-SEMANTICS-5
test "named constraint expansion enforces the requirement limit" {
    try reject(
        \\constraint Wide[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int) + field(f8: int) + field(f9: int) + field(f10: int) + field(f11: int) + field(f12: int) + field(f13: int) + field(f14: int)
        \\
        \\def f[T: Wide + codec](v: T) -> int:
        \\    _ = v
        \\    return 0
        \\
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_LIMIT");
}
// Identical bundles coalesce; the same member with a different type rejects.
// spec: NAMED-CONSTRAINT-SEMANTICS-6
test "named constraints coalesce identical members and reject conflicts" {
    try run(
        \\constraint A[T] = copy + field(value: int)
        \\constraint B[T] = copy + field(value: int)
        \\
        \\record Box:
        \\    value: int
        \\
        \\def f[T: A + B](v: T) -> int:
        \\    return v.value
        \\
        \\def main() -> int:
        \\    return f[Box](Box(value=3))
    , 3);
    try reject(
        \\constraint A[T] = copy + field(value: int)
        \\constraint B[T] = copy + field(value: bool)
        \\
        \\def f[T: A + B](v: T) -> int:
        \\    return v.value
        \\
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}
// Unused invalid constraint declarations still reject their names, signatures, and rules.
// spec: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject unused invalid definitions" {
    try reject(
        \\constraint Bad[P] = field(x: int)
        \\
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\constraint Bad[P] = copy + field(x: Bogus)
        \\
        \\def main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
    try reject(
        \\constraint Bad[P] = copy + op(go(v: P) -> Bogus effects())
        \\
        \\def main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

// Equivalent named and inline operation contracts coalesce across binder spellings.
// Unused declarations still reject result-bearing and identity-conflicting members.
// spec-case: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject unused result-bearing fields" {
    try reject(
        \\constraint Bad[T] = copy + field(value: Result[int, int])
        \\def main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\constraint Bad[T] = copy + field(value: Donations)
        \\def main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

// Exercise the identity normalization and key construction used by merging.
// spec-case: NAMED-CONSTRAINT-CALLBACK-1
test "named constraints reject conflicting callback parameters results and effects" {
    try reject(
        \\constraint A[P] = copy + op(run(p: P, fn: def(P) -> int effects()) -> int effects())
        \\constraint B[Q] = copy + op(run(p: Q, fn: def(int) -> int effects()) -> int effects())
        \\def use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\constraint A[P] = copy + op(run(p: P) -> def(P) -> P effects() effects())
        \\constraint B[Q] = copy + op(run(p: Q) -> def(Q) -> int effects() effects())
        \\def use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\constraint A[P] = copy + op(run(p: P, fn: def(P) -> int effects()) -> int effects())
        \\constraint B[Q] = copy + op(run(p: Q, fn: def(Q) -> int effects(output)) -> int effects())
        \\def use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

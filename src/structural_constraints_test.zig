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
// spec: STRUCTURAL-FIELD-1
test "structural fields execute multiple nominal record shapes and forwarding" {
    try run(
        \\class A:
        \\    value: i64
        \\
        \\
        \\class B:
        \\    tag: bool
        \\    value: i64
        \\
        \\
        \\def get[T: copy + field(value: i64)](v: T) -> i64:
        \\    return v.value
        \\
        \\
        \\def forward[U: copy + field(value: i64)](v: U) -> i64:
        \\    return get[U](v)
        \\
        \\
        \\def main() -> i64:
        \\    return get[A](A(value=2)) + forward[B](B(tag=True, value=3))
    , 5);
}
// spec: STRUCTURAL-OP-1
test "structural public domain operations execute with explicit type owned dispatch" {
    try run(
        \\domain D: i64:
        \\    def make(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\    def score(v: D) -> i64 effects():
        \\        return unwrap(v)
        \\
        \\
        \\def apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64:
        \\    return T.score(v)
        \\
        \\
        \\def main() -> i64:
        \\    return apply[D](D.make(7))
    , 7);
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
        \\class Box[T: copy + field(value: i64)]:
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
    \\class A:
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
    \\export D
    \\export apply
    \\
    \\
    \\domain D: i64:
    \\    def make(n: i64) -> D effects():
    \\        return wrap[D](n)
    \\
    \\    def score(v: D) -> i64 effects():
    \\        return unwrap(v)
    \\
    \\
    \\def apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64 effects():
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
        \\class Box[U]:
        \\    value: U
        \\
        \\
        \\class A:
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
    \\class Box[U]:
    \\    value: U
    \\
    \\
    \\class A:
    \\    items: [2]i64
    \\    box: Box[i64]
    \\
    \\
    \\class B:
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
// spec: NAMED-CONSTRAINT-SEMANTICS-1
test "named constraints execute forward and interchange with inline bounds" {
    try run(
        \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\def checkout[P: Prices](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal) + 500
        \\
        \\def forward[Q: Prices](policy: Q, subtotal: int) -> int effects():
        \\    return checkout[Q](policy, subtotal)
        \\
        \\def inline_checkout[P: copy + op(price(policy: P, subtotal: int) -> int effects())](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal) + 500
        \\
        \\def named_to_inline[P: Prices](policy: P, subtotal: int) -> int effects():
        \\    return inline_checkout[P](policy, subtotal)
        \\
        \\def inline_to_named[P: copy + op(price(policy: P, subtotal: int) -> int effects())](policy: P, subtotal: int) -> int effects():
        \\    return forward[P](policy, subtotal)
        \\
        \\domain DiscountPrices: int:
        \\    def make(discount: int) -> DiscountPrices:
        \\        return wrap[DiscountPrices](discount)
        \\
        \\    def price(policy: DiscountPrices, subtotal: int) -> int effects():
        \\        return subtotal - unwrap(policy)
        \\
        \\domain FixedPrices: int:
        \\    def make(amount: int) -> FixedPrices:
        \\        return wrap[FixedPrices](amount)
        \\
        \\    def price(policy: FixedPrices, subtotal: int) -> int effects():
        \\        _ = subtotal
        \\        return unwrap(policy)
        \\
        \\def main() -> int:
        \\    real = DiscountPrices.make(250)
        \\    fake = FixedPrices.make(1750)
        \\    assert forward(real, 2000) == 2250
        \\    assert named_to_inline(fake, 2000) == 2250
        \\    assert inline_to_named(real, 2000) == 2250
        \\    return 9
    , 9);
}
// The subject substitutes by identity inside a composite requirement signature.
// spec: NAMED-CONSTRAINT-SEMANTICS-2
test "named constraints substitute the subject through composite signatures" {
    try run(
        \\constraint Render[P] = copy + op(render(p: P, extra: list[P]) -> int effects())
        \\
        \\domain D: int:
        \\    def make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    def render(p: D, extra: list[D]) -> int effects():
        \\        _ = p
        \\        return len(extra)
        \\
        \\def count[P: Render](p: P, extra: list[P]) -> int effects():
        \\    return P.render(p, extra)
        \\
        \\def main() -> int:
        \\    d = D.make(1)
        \\    return count[D](d, [d, d]) + 1
    , 3);
}
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
        \\constraint Priced[P] = copy + op(price(policy: P) -> int effects())
        \\
        \\domain D: int:
        \\    def make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    def price(policy: D) -> int effects(output):
        \\        print("x")
        \\        return unwrap(policy)
        \\
        \\def total[P: Priced](policy: P) -> int effects():
        \\    return P.price(policy)
        \\
        \\def main() -> int:
        \\    return total[D](D.make(4))
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
// spec-case: NAMED-CONSTRAINT-SEMANTICS-6
test "named constraints coalesce alpha-renamed subject overlaps" {
    try run(
        \\constraint Id[P] = copy + op(identity(x: P) -> P effects())
        \\def forward[T: Id + op(identity(x: T) -> T effects())](x: T) -> T effects():
        \\    return T.identity(x)
        \\def main() -> int:
        \\    return 0
    , 0);
    try run(
        \\constraint A[P] = copy + op(identity(x: list[P]) -> int effects())
        \\constraint B[Q] = copy + op(identity(x: list[Q]) -> int effects())
        \\def use[T: A + B](x: T) -> int:
        \\    return 0
        \\def main() -> int:
        \\    return 0
    , 0);
    try run(
        \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
        \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
        \\def f[T: A + B](x: T) -> int:
        \\    return 0
        \\def main() -> int:
        \\    return 0
    , 0);
}
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
// spec-case: NAMED-CONSTRAINT-SEMANTICS-6
test "named constraints normalizeOne and canonicalOperation coalesce valid declarations" {
    try run(
        \\constraint A[P] = copy + field(value: int)
        \\constraint B[Q] = copy + field(value: int)
        \\record Box:
        \\    value: int
        \\def f[T: A + B](v: T) -> int:
        \\    return v.value
        \\def main() -> int:
        \\    return f[Box](Box(value=3))
    , 3);
}

// spec: NAMED-CONSTRAINT-CALLBACK-1
test "named constraints normalize callbacks and forward to inline operations natively" {
    try run(
        \\constraint Run[P] = copy + op(apply(worker: P, callback: def(P) -> int effects()) -> int effects())
        \\domain Worker: int:
        \\    def make() -> Worker:
        \\        return wrap[Worker](42)
        \\    def apply(worker: Worker, callback: def(Worker) -> int effects()) -> int effects():
        \\        return callback(worker)
        \\    def read(worker: Worker) -> int effects():
        \\        return unwrap(worker)
        \\def get[P: copy + op(apply(worker: P, callback: def(P) -> int effects()) -> int effects())](worker: P, callback: def(P) -> int effects()) -> int effects():
        \\    return P.apply(worker, callback)
        \\def forward[Q: Run](worker: Q, callback: def(Q) -> int effects()) -> int effects():
        \\    return get(worker, callback)
        \\def read_worker(worker: Worker) -> int effects():
        \\    return Worker.read(worker)
        \\def main() -> int:
        \\    return forward(Worker.make(), read_worker)
    , 42);
}

// spec-case: NAMED-CONSTRAINT-CALLBACK-1
test "named constraints coalesce nested callbacks results and concrete callback aliases" {
    try run(
        \\type Reader = def(int) -> int effects()
        \\constraint A[P] = copy + op(make(p: P, callback: def([2]P) -> list[P] effects()) -> def(P) -> P effects(output) effects())
        \\constraint B[Q] = copy + op(make(p: Q, callback: def([2]Q) -> list[Q] effects()) -> def(Q) -> Q effects(output) effects())
        \\constraint C[T] = copy + op(read(p: T, reader: Reader) -> int effects())
        \\constraint D[T] = copy + op(read(p: T, reader: def(int) -> int effects()) -> int effects())
        \\def unused[T: A + B + op(make(p: T, callback: def([2]T) -> list[T] effects()) -> def(T) -> T effects(output) effects())](p: T) -> int:
        \\    return 0
        \\def concrete[T: C + D](p: T) -> int:
        \\    return 0
        \\def main() -> int:
        \\    return 0
    , 0);
}

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

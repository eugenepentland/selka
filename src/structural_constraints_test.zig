//! Structural contracts are checked independently of specialization.
const std = @import("std");
const t = std.testing;
const print = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn run(bytes: []const u8, expected: i64) !void {
    const modern = try effectErasedWitness(t.allocator, bytes);
    defer t.allocator.free(modern);
    var c = try language.Compilation.init(t.allocator, "structural.selka", modern);
    defer c.deinit();
    if (std.mem.indexOf(u8, bytes, "domain ") != null or std.mem.indexOf(u8, bytes, "constraint ") != null or std.mem.indexOf(u8, bytes, "op(") != null) {
        try expectSourceError(c.check());
        try t.expect(hasCode(c.diagnostics.items, "E_DOMAIN_REMOVED"));
        return;
    }
    const result = native.run(&c) catch |err| {
        for (c.diagnostics.items) |diag| print("{s}: {s} ({s})\n", .{ diag.code, diag.message, c.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}
fn reject(bytes: []const u8, code: []const u8) !void {
    const modern = try effectErasedWitness(t.allocator, bytes);
    defer t.allocator.free(modern);
    var c = try language.Compilation.init(t.allocator, "structural-invalid.selka", modern);
    defer c.deinit();
    try expectSourceError(c.check());
    try t.expect(hasCode(c.diagnostics.items, code));
}
// spec: STRUCTURAL-LIMIT-1
test "structural declarations reject uncalled invalid access and incomplete construction" {
    try reject(
        \\func f[T: copy + field(value: i64)](v: T) -> bool:
        \\    return v.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    // A type parameter has no construction spelling: `T(...)` reads as a call.
    try reject(
        \\func f[T: copy + field(value: i64)]() -> T:
        \\    return T(value=1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FUNCTION");
    try reject(
        \\func f[T](v: T) -> i64:
        \\    return T.score(v)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "structural fields reject incomplete forwarding unknown fields and hidden obligations" {
    try reject(
        \\func get[T: copy + field(value: i64)](v: T) -> i64:
        \\    return v.value
        \\
        \\
        \\func forward[U](v: U) -> i64:
        \\    return get[U](v)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
    try reject(
        \\func get[T: copy + field(value: i64)](v: T) -> i64:
        \\    return v.hidden
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FIELD");
    try reject(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func get[T: copy + field(value: R)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\record Box[T: copy + field(value: i64)]:
        \\    item: T
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\func f[T: copy + field(value: i64) + field(value: i64)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    const historical_operation =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\def f[T: copy + op(score(v: T) -> i64)](v: T) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    try reject(historical_operation, "E_FRONTEND_SYNTAX");
    const native_operation = try std.mem.replaceOwned(u8, t.allocator, historical_operation, "def ", "func ");
    defer t.allocator.free(native_operation);
    try reject(native_operation, "E_DOMAIN_REMOVED");
    const unknown_result = try std.mem.replaceOwned(u8, t.allocator, native_operation, "score(v: T) -> i64", "score(v: T) -> Bogus");
    defer t.allocator.free(unknown_result);
    try reject(unknown_result, "E_UNKNOWN_TYPE");
}
const domain =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\domain D: i64:
    \\    func make(n: i64) -> D:
    \\        return wrap[D](n)
    \\
    \\    func score(v: D) -> i64 effects():
    \\        return unwrap(v)
    \\
    \\
    \\
;
const operation =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\func apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64:
    \\    return T.score(v)
    \\
    \\
    \\
;
test "structural operation forwarding retains type identity and public contracts" {
    try run(domain ++ operation ++
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func forward[U: copy + op(score(v: U) -> i64 effects())](v: U) -> i64:
        \\    return apply[U](v)
        \\
        \\
        \\func main() -> i64:
        \\    return forward[D](D.make(11))
    , 11);
    try reject(operation ++
        \\func forward[U](v: U) -> i64:
        \\    return apply[U](v)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_ARGUMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func f[T: copy + op(score(v: T) -> bool effects())](v: T) -> i64:
        \\    return T.score(v)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func f[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64:
        \\    return T.score(True)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_TYPE");
}
test "structural concrete operations reject private absent wrong typed and excessive effect methods" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: i64:
        \\    func make() -> D:
        \\        return wrap[D](1)
        \\
        \\    private func score(v: D) -> i64 effects():
        \\        return unwrap(v)
        \\
        \\
        \\
    ++ operation ++
        \\func main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: i64:
        \\    func make() -> D:
        \\        return wrap[D](1)
        \\
        \\
        \\
    ++ operation ++
        \\func main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: i64:
        \\    func make() -> D:
        \\        return wrap[D](1)
        \\
        \\    func score(v: D) -> bool effects():
        \\        return True
        \\
        \\
        \\
    ++ operation ++
        \\func main() -> i64:
        \\    return apply[D](D.make())
    , "E_GENERIC_ARGUMENT");
    try run(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: i64:
        \\    func make() -> D:
        \\        return wrap[D](1)
        \\
        \\    func score(v: D) -> i64 effects(host):
        \\        return unwrap(v)
        \\
        \\
        \\
    ++ operation ++
        \\func main() -> i64:
        \\    return apply[D](D.make())
    , 1);
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func f[T: copy + op(score(v: T) -> i64 effects(host))](v: T) -> i64 effects():
        \\    return T.score(v)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_DOMAIN_REMOVED");
}
const example = domain ++ operation ++
    \\record A:
    \\    value: i64
    \\
    \\
    \\func get[T: copy + field(value: i64)](v: T) -> i64:
    \\    return v.value
    \\
    \\
    \\func main() -> i64:
    \\    return get[A](A(value=5)) + apply[D](D.make(7))
;
fn lifecycle(allocator: std.mem.Allocator) !void {
    const modern = try effectErasedWitness(allocator, example);
    defer allocator.free(modern);
    var c = try language.Compilation.init(allocator, "structural.selka", modern);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer copy.deinit();
    const again = try copy.format(allocator);
    defer allocator.free(again);
    try t.expectEqualStrings(formatted, again);
    try expectSourceError(copy.check());
    try t.expect(hasCode(copy.diagnostics.items, "E_DOMAIN_REMOVED"));
}
test "structural formatter lifecycle round trips and releases storage under allocation failure" {
    try lifecycle(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), lifecycle, .{});
}
const module_files = [_]language.embedded_project.File{
    .{ .path = "main.selka", .bytes =
    \\import api
    \\
    \\
    \\func main() -> i64:
    \\    return api.apply[api.D](api.D.make(13))
    },
    .{
        .path = "api.selka",
        .bytes =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\
        \\
        \\public domain D: i64:
        \\    func make(n: i64) -> D effects():
        \\        return wrap[D](n)
        \\
        \\    func score(v: D) -> i64 effects():
        \\        return unwrap(v)
        \\
        \\
        \\public func apply[T: copy + op(score(v: T) -> i64 effects())](v: T) -> i64 effects():
        \\    return T.score(v)
    },
};
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const original = try language.embedded_project.read(allocator, &module_files, path, limit);
    defer allocator.free(original);
    return eraseEffectClauses(allocator, original);
}
test "structural imported operation dispatch survives AST source relocation" {
    const recognized = try effectErasedWitness(t.allocator, module_files[1].bytes);
    defer t.allocator.free(recognized);
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(.{ .context = null, .read = moduleRead }, "main", .{});
    var index = try language.interfaces.build(&loaded);
    var compilation = try language.project_compile.Compilation.init(&index);
    try expectSourceError(compilation.check());
    try t.expect(hasCode(compilation.diagnostics.items.items, "E_DOMAIN_REMOVED"));
}

// spec: STRUCTURAL-COMPOSITE-1
test "structural composite fields substitute arrays and nominal applications" {
    try run(
        \\record Box[U]:
        \\    value: U
        \\
        \\
        \\record A:
        \\    items: FixedArray[i64, 2]
        \\    box: Box[i64]
        \\
        \\
        \\func get[T: copy + field(items: FixedArray[U, 2]) + field(box: Box[U]), U](v: T) -> U:
        \\    return v.box.value
        \\
        \\
        \\func main() -> i64:
        \\    return get[A, i64](A(items=FixedArray[int, 2]([1, 2]), box=Box[i64](value=7)))
    , 7);
    try reject(
        \\func f[T: copy + field(items: FixedArray[U, 2]), U](v: T) -> U:
        \\    return v.items[True]
    , "E_GENERIC_OPERATION");
}

const composite =
    \\record Box[U]:
    \\    value: U
    \\
    \\
    \\record A:
    \\    items: FixedArray[i64, 2]
    \\    box: Box[i64]
    \\
    \\
    \\record B:
    \\    items: FixedArray[bool, 2]
    \\    box: Box[bool]
    \\
    \\
    \\func get[T: copy + field(items: FixedArray[U, 2]) + field(box: Box[U]), U](v: T) -> U:
    \\    return v.box.value
    \\
    \\
    \\func forward[V: copy + field(items: FixedArray[W, 2]) + field(box: Box[W]), W](v: V) -> W:
    \\    return get[V, W](v)
    \\
    \\
    \\func main() -> i64:
    \\    mut flag = forward[B, bool](B(items=FixedArray[bool, 2]([True, False]), box=Box[bool](value=True)))
    \\    if flag:
    \\        return forward[A, i64](A(items=FixedArray[int, 2]([1, 2]), box=Box[i64](value=7)))
    \\    return 0
;
fn compositeLifecycle(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "composite.selka", composite);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&copy)).value);
}

// Confirm the shared contract executes, forwards, and interchanges with its inline equivalent.
// The subject substitutes by identity inside a composite requirement signature.
// All declared effects stay inside the required ceiling; exceeding it rejects conformance.
// spec: NAMED-CONSTRAINT-SEMANTICS-3
test "named constraint operation ceilings accept subsets and reject excess" {
    try run(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Priced[P] = copy + op(price(policy: P) -> int effects())
        \\
        \\domain D: int:
        \\    func make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    func price(policy: D) -> int effects():
        \\        return unwrap(policy)
        \\
        \\func total[P: Priced](policy: P) -> int effects():
        \\    return P.price(policy)
        \\
        \\func main() -> int:
        \\    return total[D](D.make(4))
    , 4);
    try run(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Priced[P] = copy + op(price(policy: P, out: Stream) -> int effects())
        \\
        \\domain D: int:
        \\    func make(n: int) -> D:
        \\        return wrap[D](n)
        \\
        \\    func price(policy: D, out: Stream) -> int effects(output):
        \\        print(out, "x")
        \\        return unwrap(policy)
        \\
        \\func total[P: Priced](policy: P, out: Stream) -> int effects():
        \\    return P.price(policy, out)
        \\
        \\func main(out: Stream) -> int:
        \\    return total[D](D.make(4), out)
    , 4);
}
// A weaker bound may not forward to a stronger one, even when the function is never called.
// spec: NAMED-CONSTRAINT-SEMANTICS-4
test "named constraints reject weaker to stronger forwarding universally" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint HasValue[T] = copy + field(value: int)
        \\
        \\func read[T: HasValue](v: T) -> int:
        \\    return v.value
        \\
        \\func forward[U: copy](v: U) -> int:
        \\    return read[U](v)
        \\
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
    try reject(
        \\func read[T: copy + field(value: int)](v: T) -> int:
        \\    return v.value
        \\
        \\func forward[U: copy](v: U) -> int:
        \\    return read[U](v)
        \\
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}
// Expansion counts unique explicit requirements, including those added by a named bundle.
// spec: NAMED-CONSTRAINT-SEMANTICS-5
test "named constraint expansion enforces the requirement limit" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Wide[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int) + field(f8: int) + field(f9: int) + field(f10: int) + field(f11: int) + field(f12: int) + field(f13: int) + field(f14: int)
        \\
        \\func f[T: Wide + codec](v: T) -> int:
        \\    _ = v
        \\    return 0
        \\
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_LIMIT");
}
// Identical bundles coalesce; the same member with a different type rejects.
// spec: NAMED-CONSTRAINT-SEMANTICS-6
test "named constraints coalesce identical members and reject conflicts" {
    try run(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[T] = copy + field(value: int)
        \\constraint B[T] = copy + field(value: int)
        \\
        \\record Box:
        \\    value: int
        \\
        \\func f[T: A + B](v: T) -> int:
        \\    return v.value
        \\
        \\func main() -> int:
        \\    return f[Box](Box(value=3))
    , 3);
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[T] = copy + field(value: int)
        \\constraint B[T] = copy + field(value: bool)
        \\
        \\func f[T: A + B](v: T) -> int:
        \\    return v.value
        \\
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}
// Unused invalid constraint declarations still reject their names, signatures, and rules.
// spec: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject unused invalid definitions" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Bad[P] = field(x: int)
        \\
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Bad[P] = copy + field(x: Bogus)
        \\
        \\func main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Bad[P] = copy + op(go(v: P) -> Bogus effects())
        \\
        \\func main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

// Equivalent named and inline operation contracts coalesce across binder spellings.
// Unused declarations still reject result-bearing and identity-conflicting members.
// spec-case: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject unused result-bearing fields" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Bad[T] = copy + field(value: Result[int, int])
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint Bad[T] = copy + field(value: Donations)
        \\func main() -> int:
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

// Exercise the identity normalization and key construction used by merging.
// spec-case: NAMED-CONSTRAINT-CALLBACK-1
test "named constraints reject conflicting callback parameters results and effects" {
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[P] = copy + op(run(p: P, fn: func(P) -> int effects()) -> int effects())
        \\constraint B[Q] = copy + op(run(p: Q, fn: func(int) -> int effects()) -> int effects())
        \\func use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[P] = copy + op(run(p: P) -> func(P) -> P effects() effects())
        \\constraint B[Q] = copy + op(run(p: Q) -> func(Q) -> int effects() effects())
        \\func use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[P] = copy + op(run(p: P, fn: func(P) -> int effects()) -> int effects())
        \\constraint B[Q] = copy + op(run(p: Q, fn: func(Q) -> int effects(output)) -> int effects())
        \\func use[T: A + B](p: T) -> int:
        \\    return 0
    , "E_DOMAIN_REMOVED");
}

fn hasCode(items: anytype, code: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

fn expectSourceError(outcome: anyerror!void) anyerror!void {
    outcome catch |err| {
        if (err == error.SourceError) return;
        return err;
    };
    return error.TestExpectedError;
}

// Check exact historical parser retirement before validating the clause-free
// domain recognizer. No old ceiling policy is reinstated.
fn effectErasedWitness(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, bytes, " effects(") != null) {
        var original = try language.Compilation.init(allocator, "original-effect.selka", bytes);
        defer original.deinit();
        try expectSourceError(original.check());
        try t.expect(hasCode(original.diagnostics.items, "E_EFFECTS_REMOVED"));
    }
    return eraseEffectClauses(allocator, bytes);
}
fn eraseEffectClauses(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var result = try allocator.dupe(u8, bytes);
    errdefer allocator.free(result);
    for ([_][]const u8{ " effects()", " effects(host)", " effects(output)" }) |clause| {
        const next = try std.mem.replaceOwned(u8, allocator, result, clause, "");
        allocator.free(result);
        result = next;
    }
    return result;
}

// spec-case: EFFECTS-REMOVED-1
test "eraseEffectClauses releases each intermediate allocation on failure" {
    try t.checkAllAllocationFailures(t.allocator, erasedEffectsLifecycle, .{});
}
fn erasedEffectsLifecycle(allocator: std.mem.Allocator) !void {
    const modern = try eraseEffectClauses(allocator, "a effects() b effects(host) c effects(output)");
    defer allocator.free(modern);
    try t.expectEqualStrings("a b c", modern);
}

// Retired ceiling subsets/excess have no live policy equivalent. Ordinary
// callback ABIs and explicit capability authority retain their own boundaries.
// spec-case: CALLBACK-SLOT-1
test "modern operation callbacks retain result parameter and mutation ABI validation" {
    const program =
        \\record D:
        \\    value: int
        \\func score(v: D) -> int:
        \\    return v.value
        \\func apply(v: D, callback: func(D) -> int) -> int:
        \\    return callback(v)
        \\func main() -> int:
        \\    return apply(D(value=11), score)
    ;
    try run(program, 11);
    const wrong_parameter = try std.mem.replaceOwned(u8, t.allocator, program, "func(D) -> int", "func(int) -> int");
    defer t.allocator.free(wrong_parameter);
    try reject(wrong_parameter, "E_TYPE");
    const wrong_result = try std.mem.replaceOwned(u8, t.allocator, program, "func(D) -> int", "func(D) -> bool");
    defer t.allocator.free(wrong_result);
    try reject(wrong_result, "E_TYPE");
    const wrong_mutation = try std.mem.replaceOwned(u8, t.allocator, program, "func score(v: D)", "func score(mut v: D)");
    defer t.allocator.free(wrong_mutation);
    try reject(wrong_mutation, "E_TYPE");
}

const modern_operation_modules = [_]language.embedded_project.File{
    .{ .path = "main.selka", .bytes =
    \\import api
    \\func main() -> int:
    \\    return api.apply(api.D(value=13), api.score)
    },
    .{ .path = "api.selka", .bytes =
    \\public record D:
    \\    value: int
    \\public func score(v: D) -> int:
    \\    return v.value
    \\public func apply[T](v: T, callback: func(T) -> int) -> int:
    \\    return callback(v)
    },
};
fn modernOperationRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    return language.embedded_project.read(allocator, &modern_operation_modules, path, limit);
}
// spec-case: PROJ-3
test "modern imported operation callbacks preserve module identity and public contracts" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = modernOperationRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 13), (try native.run(&program.compilation)).value);
}

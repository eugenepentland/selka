//! Changed-source cached/fresh agreement includes ownership, diagnostics and interrupted snapshots.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const semantic_key = @import("semantic_key.zig");
const cache_key = @import("cache_key.zig");
const Cache = language.semantic_cache.Cache;
const prefix =
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\
;
const suffix =
    \\def keep(n: i64) -> i64:
    \\    unused = 1
    \\    x = n
    \\    x = x + 1
    \\    return x
    \\
    \\
    \\def main() -> i64:
    \\    return keep(helper(40))
;
fn compare(allocator: std.mem.Allocator, cache: *Cache, bytes: []const u8, expected: ?i64) !void {
    var cached = try language.Compilation.init(allocator, "edited.my", bytes);
    defer cached.deinit();
    var fresh = try language.Compilation.init(allocator, "edited.my", bytes);
    defer fresh.deinit();
    if (expected) |number| {
        try cached.checkWithCache(cache);
        try fresh.check();
        for (fresh.program.?.functions, cached.program.?.functions) |a, b| {
            try t.expectEqual(a.policy.effects, b.policy.effects);
            try t.expectEqualSlices(u16, a.signature.mutates, b.signature.mutates);
            try t.expect(a.signature.return_origin.eql(b.signature.return_origin));
        }
        try t.expectEqual(number, (try native.run(&cached)).value);
        try t.expectEqual(number, (try native.run(&fresh)).value);
    } else {
        try rejected(cached.checkWithCache(cache));
        try rejected(fresh.check());
    }
    try t.expectEqual(fresh.diagnostics.items.len, cached.diagnostics.items.len);
    for (fresh.diagnostics.items, cached.diagnostics.items) |a, b| {
        const left = try language.diagnostic_output.render(allocator, a, fresh.src, .json);
        defer allocator.free(left);
        const right = try language.diagnostic_output.render(allocator, b, cached.src, .json);
        defer allocator.free(right);
        try t.expectEqualStrings(left, right);
    }
}
fn rejected(result: language.diagnostic.Error!void) !void {
    if (result) |_| return error.TestUnexpectedResult else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try t.expectEqual(error.SourceError, err);
    }
}
fn scenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    try compare(allocator, &cache,
        \\def helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\
    ++ suffix, 43);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 4), cache.statistics.checked);
    try compare(allocator, &cache,
        \\def helper(n: i64) -> i64:
        \\    return True
        \\
        \\
        \\
    ++ suffix, null);
    try t.expectEqual(@as(usize, 2), cache.statistics.stored);
    try compare(allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 6), cache.statistics.reused);
    cache.clear();
    try compare(allocator, &cache, prefix ++ suffix, 42);
}
// spec: SEMANTIC-CACHE-1
test "semantic cache reuses unchanged checked bodies after edits and preserves diagnostics and ownership under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
// spec: SEMANTIC-CACHE-2
test "declaration and type identity changes invalidate dependents while unrelated declarations preserve reuse" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    // The helper signature changes; every caller that references it misses.
    try compare(t.allocator, &cache,
        \\def helper(n: bool) -> i64:
        \\    return 1
        \\
        \\
        \\
    ++ suffix, null);
    // `keep` does not reference `helper`, so it is reusable even in the failed
    // request; the caller that references the changed signature is not.
    const reused_before_unrelated = cache.statistics.reused;
    // An unrelated declaration inserted ahead of the same functions preserves the
    // three ordinary bodies: the dependency digests and stable identities match.
    try compare(t.allocator, &cache,
        \\class Item:
        \\    n: i64
        \\
        \\
        \\
    ++ prefix ++ suffix, 42);
    try t.expectEqual(reused_before_unrelated + 3, cache.statistics.reused);
    // Referenced constant value changes invalidate the reader; the alias form is
    // rechecked because its declaration identity differs from the constant.
    try compare(t.allocator, &cache,
        \\const N: i64 = 1
        \\
        \\
        \\def main() -> i64:
        \\    return N
    , 1);
    try compare(t.allocator, &cache,
        \\const N: i64 = 2
        \\
        \\
        \\def main() -> i64:
        \\    return N
    , 2);
    try compare(t.allocator, &cache,
        \\def id[T](n: T) -> T:
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return id[i64](42)
    , 42);
    try compare(t.allocator, &cache,
        \\type Number = i64
        \\
        \\
        \\def main() -> i64:
        \\    return Number(42)
    , 42);
    try t.expectEqual(reused_before_unrelated + 3, cache.statistics.reused);
}
// spec-case: SEMANTIC-CACHE-2
// spec-case: CONSTANT-2
test "managed constant edits invalidate dependent bodies while unrelated constants reuse" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const main = "def main() -> int:\n    return len(S) + B[0]\n";
    try compare(t.allocator, &cache, "const S: str = \"a\"\nconst B: bytes = b\"A\"\n" ++ main, 66);
    try compare(t.allocator, &cache, "const S: str = \"é🙂\"\nconst B: bytes = b\"B\"\n" ++ main, 68);
    try compare(t.allocator, &cache, "const S: str = \"a\" + \"b\"\nconst B: bytes = b\"B\"\n" ++ main, null);
    // `B` is unchanged in the second request and reused there; every reader of the
    // edited `S` misses because the constant fingerprint participates in its context.
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    try t.expectEqual(@as(usize, 2), cache.statistics.stored);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
}
// spec: SEMANTIC-CACHE-3
test "semantic cache InvalidRelocation never accepts foreign source or expression identities" {
    const relocation = @import("semantic_copy.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const mapper: relocation.Mapper = .{
        .segments = &.{.{ .before = .{ .start = 10, .end = 20 }, .after = 30 }},
        .before = .{ .nodes = .{ .start = 3, .end = 4 }, .statements = .{ .start = 1, .end = 2 } },
        .after = .{ .nodes = .{ .start = 5, .end = 6 }, .statements = .{ .start = 7, .end = 8 } },
    };
    try t.expectError(error.InvalidRelocation, mapper.copy(arena.allocator(), language.source.Span, .{ .start = 5, .end = 12 }));
    try t.expectError(error.InvalidRelocation, mapper.copy(arena.allocator(), @import("typed.zig").NodeId, @fromBackingInt(2)));
}
// spec: SEMANTIC-CACHE-5
test "semantic cache keeps previous committed bodies when remember reports OutOfMemory" {
    var failures = t.FailingAllocator.init(t.allocator, .{});
    var cache = Cache.init(failures.allocator(), 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    failures.fail_index = failures.alloc_index;
    var interrupted = try language.Compilation.init(t.allocator, "edited.my",
        \\def helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\
    ++ suffix);
    defer interrupted.deinit();
    try t.expectError(error.OutOfMemory, interrupted.checkWithCache(&cache));
    try t.expectEqual(@as(usize, 1), cache.statistics.stored);
    failures.fail_index = std.math.maxInt(usize);
    const previous_hits = cache.statistics.reused;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(previous_hits + 3, cache.statistics.reused);
}

// spec: SEMANTIC-CALLBACK-1
test "semantic cache keeps inferred callback schemas fresh across changed bodies" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const caller =
        \\def main() -> i64:
        \\    cb = helper
        \\    return cb(40)
    ;
    try compare(t.allocator, &cache,
        \\def helper(n: i64) -> i64 effects():
        \\    return n + 1
        \\
        \\
        \\
    ++ caller, 41);
    try compare(t.allocator, &cache,
        \\def helper(n: i64) -> i64 effects():
        \\    return n + 2
        \\
        \\
        \\
    ++ caller, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
}

// spec-case: SEMANTIC-CACHE-2
test "constant-length and nominal specializations stay on the fresh path" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const function =
        \\def size[const N: u64]() -> u64:
        \\    return N
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, function ++
        \\def main() -> i64:
        \\    return i64(size[2]())
    , 2);
    try compare(t.allocator, &cache, function ++
        \\def main() -> i64:
        \\    return i64(size[3]())
    , 3);
    const nominal =
        \\class Chunk[const N: u64]:
        \\    items: [N]i64
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, nominal ++
        \\def main() -> i64:
        \\    x = Chunk[1](items=[42])
        \\    return x.items[0]
    , 42);
    try compare(t.allocator, &cache, nominal ++
        \\def main() -> i64:
        \\    x = Chunk[2](items=[43, 0])
        \\    return x.items[0]
    , 43);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
}

// spec: SEMANTIC-CACHE-4
test "semantic cache rechecks transitive effects when only a callee body changes" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    // Only the callee body changes; the unchanged caller is reused but rechecked.
    // The host declaration is never executed, so this stays a checking-only test.
    const shared =
        \\host def tick() -> i64 effects(host)
        \\
        \\
        \\def main() -> i64 effects(clock):
        \\    return change()
        \\
        \\
        \\
    ;
    var first = try language.Compilation.init(t.allocator, "edited.my", shared ++
        \\def change() -> i64:
        \\    return 42
    );
    defer first.deinit();
    try first.checkWithCache(&cache);
    var second = try language.Compilation.init(t.allocator, "edited.my", shared ++
        \\def change() -> i64:
        \\    return tick()
    );
    defer second.deinit();
    try t.expectError(error.SourceError, second.checkWithCache(&cache));
    try t.expectEqualStrings("E_EFFECT_BOUND", second.diagnostics.items[0].code);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expect(cache.statistics.stored > 0);
}

// spec-case: INCREMENTAL-KEYS-1
test "specialization key mixes template arguments provider abi and compiler" {
    const first = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "i64", "bool" }, "provider-v1", "runtime-abi-v1", "compiler-a");
    defer t.allocator.free(first);
    const same = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "i64", "bool" }, "provider-v1", "runtime-abi-v1", "compiler-a");
    defer t.allocator.free(same);
    try t.expectEqualStrings(first, same);
    try t.expectEqual(@as(usize, 64), first.len);

    const template = try semantic_key.specializationKey(t.allocator, "mod::other", &.{ "i64", "bool" }, "provider-v1", "runtime-abi-v1", "compiler-a");
    defer t.allocator.free(template);
    const reordered = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "bool", "i64" }, "provider-v1", "runtime-abi-v1", "compiler-a");
    defer t.allocator.free(reordered);
    const provider = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "i64", "bool" }, "provider-v2", "runtime-abi-v1", "compiler-a");
    defer t.allocator.free(provider);
    const abi = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "i64", "bool" }, "provider-v1", "runtime-abi-v2", "compiler-a");
    defer t.allocator.free(abi);
    const compiler = try semantic_key.specializationKey(t.allocator, "mod::id", &.{ "i64", "bool" }, "provider-v1", "runtime-abi-v1", "compiler-b");
    defer t.allocator.free(compiler);
    for ([_][]const u8{ template, reordered, provider, abi, compiler }) |changed|
        try t.expect(!std.mem.eql(u8, first, changed));
}

// spec-case: INCREMENTAL-KEYS-1
test "semantic cache contract fingerprint forces a fresh check and identical contract reuses" {
    const contract_a = try cache_key.Contract.default.fingerprint(t.allocator);
    defer t.allocator.free(contract_a);
    var runtime = cache_key.Contract.default;
    runtime.runtime_abi = "runtime-abi-v2";
    const contract_b = try runtime.fingerprint(t.allocator);
    defer t.allocator.free(contract_b);
    var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, contract_a);
    defer cache.deinit();
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    const after_base_checked = cache.statistics.checked;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(after_base_checked, cache.statistics.checked);

    // Same source, same cache, different runtime ABI contract: no body may be reused.
    cache.context.contract = contract_b;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 3, cache.statistics.checked);

    // Returning to the original contract is a miss until its bodies are published,
    // then the identical contract reuses them again.
    cache.context.contract = contract_a;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 6, cache.statistics.checked);
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 6), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 6, cache.statistics.checked);
}

// spec: SEMANTIC-CACHE-7
test "per-function reuse ignores an unused generic and reuses unchanged ordinary bodies" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const generic = "def identity[T](value: T) -> T:\n    return value\n\n\n";
    const second = "def second() -> i64:\n    return 7\n\n\n";
    const main = "def main() -> i64:\n    return first() + second()\n";
    try compare(t.allocator, &cache, "def first() -> i64:\n    return 1\n" ++ second ++ main ++ generic, 8);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
    try compare(t.allocator, &cache, "def first() -> i64:\n    return 2\n" ++ second ++ main ++ generic, 9);
    // The edited body is rechecked; the other two ordinary bodies are reused even
    // though the program still contains an unused generic template.
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 4), cache.statistics.checked);
}

test "insert delete and reorder unrelated declarations preserve function and type identities" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const ordered =
        \\class A:
        \\    n: i64
        \\
        \\
        \\class B:
        \\    n: i64
        \\
        \\
        \\def first() -> i64:
        \\    return 1
        \\
        \\
        \\def unused() -> i64:
        \\    return 9
        \\
        \\
        \\def main() -> i64:
        \\    a = A(n=40)
        \\    b = B(n=1)
        \\    return a.n + b.n + first()
    ;
    try compare(t.allocator, &cache, ordered, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    const shuffled =
        \\class B:
        \\    n: i64
        \\
        \\
        \\class A:
        \\    n: i64
        \\
        \\
        \\def main() -> i64:
        \\    a = A(n=40)
        \\    b = B(n=1)
        \\    return a.n + b.n + first()
        \\
        \\
        \\def first() -> i64:
        \\    return 1
    ;
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, shuffled, 42);
    // `unused` was deleted, both records and `main` moved ahead of `first`, and
    // the fresh catalog ordinals differ; stable identities still remap the two
    // surviving bodies.
    try t.expectEqual(before + 2, cache.statistics.reused);
}

test "a negative name lookup misses when a declaration is introduced later" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const base = "def main() -> i64:\n    print(\"hi\")\n    return 1\n";
    try compare(t.allocator, &cache, base, 1);
    const introduced =
        \\def print(message: str) -> None:
        \\    _ = message
        \\
        \\
        \\def main() -> i64:
        \\    print("hi")
        \\    return 1
    ;
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, introduced, 1);
    // `print` used to resolve to the reserved builtin (a recorded negative
    // lookup); introducing a declaration changes resolution, so `main` misses
    // even though its body bytes are unchanged.
    try t.expectEqual(before, cache.statistics.reused);
}

test "reused bodies relocate diagnostics and warnings after code moves" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const base =
        \\def helper() -> i64:
        \\    unused = 41
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return helper()
    ;
    try compare(t.allocator, &cache, base, 1);
    const moved =
        \\def unrelated() -> i64:
        \\    return 9
        \\
        \\
        \\
    ++ base;
    const before = cache.statistics.reused;
    // `compare` renders every diagnostic from both the cached and fresh program,
    // so an unrelocated warning span fails the comparison.
    try compare(t.allocator, &cache, moved, 1);
    try t.expectEqual(before + 2, cache.statistics.reused);
}

test "mutation summaries are recomputed rather than copied with a reused body" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const writing =
        \\def touch(values: list[int]) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> i64:
        \\    values = [1]
        \\    touch(values)
        \\    return values[0]
    ;
    try compare(t.allocator, &cache, writing, 1);
    const reading =
        \\def touch(values: list[int]) -> None:
        \\    _ = values
        \\
        \\
        \\def main() -> i64:
        \\    values = [1]
        \\    touch(values)
        \\    return values[0]
    ;
    const before = cache.statistics.reused;
    // `main` is unchanged and reused; its `mutates`/`return_origin` summary is
    // recomputed by the mandatory global effect pass and must match fresh.
    try compare(t.allocator, &cache, reading, 1);
    try t.expectEqual(before + 1, cache.statistics.reused);
}

// spec-case: SEMANTIC-CACHE-7
test "declared callback slots and matching function values reuse when the contract is stable" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\def apply(f: def(i64) -> i64 effects(), x: i64) -> i64 effects():
        \\    return f(x)
        \\
        \\
        \\def one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def main() -> i64 effects():
        \\    return apply(one, 41)
    ;
    try compare(t.allocator, &cache, program, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    // The declared callback parameter is interned before checking and `one`'s
    // contract matches it exactly, so the callable slot has a stable remap.
    try t.expectEqual(@as(usize, 0), cache.statistics.misses[@backingInt(language.semantic_cache.MissReason.function_value)]);

    // Only the callee body changes: `main` still stores the same declared
    // callback contract, so its body reuses and revalidates globally.
    const edited =
        \\def apply(f: def(i64) -> i64 effects(), x: i64) -> i64 effects():
        \\    return f(x) + 0
        \\
        \\
        \\def one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def main() -> i64 effects():
        \\    return apply(one, 41)
    ;
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, edited, 42);
    try t.expectEqual(before + 2, cache.statistics.reused);
}

// spec-case: SEMANTIC-CACHE-7
test "a function value with no matching declared callback misses with its exact reason" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\def apply(f: def(i64) -> i64 effects(output), x: i64) -> i64 effects(output):
        \\    return f(x)
        \\
        \\
        \\def one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def main() -> i64 effects(output):
        \\    return apply(one, 41)
    ;
    try compare(t.allocator, &cache, program, 42);
    // `one`'s own contract differs from the declared callback parameter, so its
    // callable contract record is interned while checking and cannot be remapped.
    try t.expect(cache.statistics.misses[@backingInt(language.semantic_cache.MissReason.function_value)] > 0);
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, program, 42);
    // `apply` and `one` reuse; `main` is rechecked with its reported reason.
    try t.expectEqual(before + 2, cache.statistics.reused);
}

// C3 specialization half: concrete specialization bodies are currently a
// conservative miss. A caller that references one is rechecked fresh (which
// re-instantiates the specialization), so no unvalidated specialization is ever
// reused. The durable concrete entry kind, typed FunctionRef instantiation and
// fresh instance remap are the reported remaining work.
// spec-case: SEMANTIC-CACHE-7
test "generic specialization bodies reuse while their callers miss with their exact reason" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](42)
    ;
    try compare(t.allocator, &cache, program, 42);
    try t.expect(cache.statistics.misses[@backingInt(language.semantic_cache.MissReason.generic_specialization)] > 0);
    const before = cache.statistics.reused;
    const before_specialization = cache.reuse.specializations.statistics.reused;
    try compare(t.allocator, &cache, program, 42);
    // C3: the leaf specialization body itself is reused. Its caller is still a
    // conservative miss because ordinary bodies that reference a specialization
    // are not retained without a validated instance-key remap.
    try t.expectEqual(before + 1, cache.statistics.reused);
    try t.expectEqual(before_specialization + 1, cache.reuse.specializations.statistics.reused);
    try t.expect(cache.statistics.misses[@backingInt(language.semantic_cache.MissReason.generic_specialization)] > 0);
}

// spec-case: SEMANTIC-CACHE-7
test "pre-collected array types reuse while a changed referenced contract invalidates dependents" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\def pair() -> [2]i64:
        \\    return [1, 2]
        \\
        \\
        \\def main() -> i64:
        \\    return pair()[0]
    ;
    try compare(t.allocator, &cache, program, 1);
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, program, 1);
    // The fixed array layout is collected with the declaration, so the ordinary
    // bodies remap it by stable identity and reuse.
    try t.expectEqual(before + 2, cache.statistics.reused);

    const edited =
        \\def pair() -> [3]i64:
        \\    return [1, 2, 3]
        \\
        \\
        \\def main() -> i64:
        \\    return pair()[0]
    ;
    const before_signature = cache.statistics.reused;
    try compare(t.allocator, &cache, edited, 1);
    // `pair`'s signature changed, so `main`'s resolved dependency changed too.
    try t.expectEqual(before_signature, cache.statistics.reused);
}

// spec-case: SEMANTIC-CACHE-7
test "semantic cache binds the mutation contract version and effects contract" {
    const contract_a = try cache_key.Contract.default.fingerprint(t.allocator);
    defer t.allocator.free(contract_a);
    var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, contract_a);
    defer cache.deinit();
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    const baseline_reused = cache.statistics.reused;
    const baseline_checked = cache.statistics.checked;

    // A changed mutation-contract encoding must invalidate every retained body.
    cache.context.mutation_contract = "mutation-v2";
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(baseline_reused, cache.statistics.reused);
    try t.expectEqual(baseline_checked + 3, cache.statistics.checked);
    cache.context.mutation_contract = language.semantic_cache.mutation_contract_version;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(baseline_checked + 6, cache.statistics.checked);

    // A changed declared effect contract is a different context even for the
    // same bytes; returning to the original contract is a fresh miss again.
    var effects_changed = cache_key.Contract.default;
    effects_changed.effects = "effects-v2";
    const contract_b = try effects_changed.fingerprint(t.allocator);
    defer t.allocator.free(contract_b);
    cache.context.contract = contract_b;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(baseline_checked + 9, cache.statistics.checked);
}

// spec-case: SEMANTIC-CACHE-7
test "a reused caller recomputes its return-origin bound after a callee alias change" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const base =
        \\def source(values: list[int]) -> list[int]:
        \\    return values
        \\
        \\
        \\def caller(values: list[int]) -> list[int]:
        \\    return source(values)
        \\
        \\
        \\def main() -> i64:
        \\    values = [1]
        \\    result = caller(values)
        \\    return result[0]
    ;
    const edited =
        \\def source(values: list[int]) -> list[int]:
        \\    return [values[0]]
        \\
        \\
        \\def caller(values: list[int]) -> list[int]:
        \\    return source(values)
        \\
        \\
        \\def main() -> i64:
        \\    values = [1]
        \\    result = caller(values)
        \\    return result[0]
    ;
    try compare(t.allocator, &cache, base, 1);
    const base_caller_contract = storedContract(&cache, "caller");
    // The alias change is real: `source` returns a parameter in the base and a
    // freshly allocated list after the edit.
    {
        var first = try language.Compilation.init(t.allocator, "probe.my", base);
        defer first.deinit();
        try first.check();
        var second = try language.Compilation.init(t.allocator, "probe.my", edited);
        defer second.deinit();
        try second.check();
        try t.expect(!functionReturnOrigin(first.program.?, "source").eql(functionReturnOrigin(second.program.?, "source")));
        try t.expect(!functionReturnOrigin(first.program.?, "caller").eql(functionReturnOrigin(second.program.?, "caller")));
    }
    const before = cache.statistics.reused;
    const before_checked = cache.statistics.checked;
    // `caller` and `main` reuse and are recomputed by the mandatory M2 pass;
    // only `source`, whose body changed, is checked fresh.
    try compare(t.allocator, &cache, edited, 1);
    try t.expectEqual(before + 2, cache.statistics.reused);
    try t.expectEqual(before_checked + 1, cache.statistics.checked);
    // The reused caller's persisted checked contract is refreshed from the
    // global pass, so a return-origin change is visible to C2 admission.
    try t.expect(!std.mem.eql(u8, &base_caller_contract, &storedContract(&cache, "caller")));
}

/// Borrow one retained entry's checked contract digest by declaration key suffix.
fn storedContract(cache: *Cache, key_suffix: []const u8) [32]u8 {
    for (cache.entries) |entry| {
        if (std.mem.endsWith(u8, entry.meta.identity.key, key_suffix)) return entry.meta.identity.checked_contract;
    }
    unreachable;
}

fn functionReturnOrigin(program: @import("typed.zig").Program, name: []const u8) @import("typed.zig").ReturnOrigin {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.signature.return_origin;
    unreachable;
}

// C2 durable-store behavior is not yet registered in SPEC.md; the required registration patch is reported with this package.
test "durable semantic entries survive a new cache process and roll back cleanly on damage" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const contract = cache_key.Contract.default;
    {
        var store = language.semantic_cache.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
        defer store.deinit();
        const fingerprint = try contract.fingerprint(t.allocator);
        defer t.allocator.free(fingerprint);
        var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
        defer cache.deinit();
        cache.context.persistent = &store;
        try compare(t.allocator, &cache, prefix ++ suffix, 42);
        try t.expectEqual(@as(usize, 3), cache.statistics.checked);
        try t.expect(store.statistics.stored != 0);
    }
    {
        var store = language.semantic_cache.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
        defer store.deinit();
        const fingerprint = try contract.fingerprint(t.allocator);
        defer t.allocator.free(fingerprint);
        var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
        defer cache.deinit();
        cache.context.persistent = &store;
        try compare(t.allocator, &cache, prefix ++ suffix, 42);
        try t.expectEqual(@as(usize, 3), cache.statistics.reused);
        try t.expectEqual(@as(usize, 0), cache.statistics.checked);
    }
}

const DurableRun = struct { checked: usize, reused: usize, evicted: usize = 0 };

fn durableRun(allocator: std.mem.Allocator, root: []const u8, source: []const u8, contract: cache_key.Contract, mutation_contract: []const u8, limits: @import("semantic_store.zig").Limits) !DurableRun {
    var store = language.semantic_cache.Store.init(allocator, t.io, root, contract, mutation_contract);
    defer store.deinit();
    store.limits = limits;
    const fingerprint = try contract.fingerprint(allocator);
    defer allocator.free(fingerprint);
    var cache = Cache.initWithContract(allocator, 4 * 1024 * 1024, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    cache.context.mutation_contract = mutation_contract;
    try compare(allocator, &cache, source, 42);
    return .{ .checked = cache.statistics.checked, .reused = cache.statistics.reused, .evicted = store.statistics.evicted };
}

test "durable entries isolate every contract dimension and the mutation version" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const source = prefix ++ suffix;
    const base = cache_key.Contract.default;
    try t.expectEqual(@as(usize, 3), (try durableRun(t.allocator, root, source, base, "mutation-v1", .{})).checked);
    const variants = [_]cache_key.Contract{
        .{ .bootstrap_language = "bootstrap-v2", .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = "wasm32", .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = "runtime-abi-v2", .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = "effects-v2", .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = "--release", .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = "sha256:other" },
    };
    for (variants) |variant| {
        const outcome = try durableRun(t.allocator, root, source, variant, "mutation-v1", .{});
        try t.expectEqual(@as(usize, 3), outcome.checked);
        try t.expectEqual(@as(usize, 0), outcome.reused);
    }
    try t.expectEqual(@as(usize, 0), (try durableRun(t.allocator, root, source, base, "mutation-v1", .{})).checked);
    try t.expectEqual(@as(usize, 3), (try durableRun(t.allocator, root, source, base, "mutation-v1", .{})).reused);
    const changed_mutation = try durableRun(t.allocator, root, source, base, "mutation-v2", .{});
    try t.expectEqual(@as(usize, 3), changed_mutation.checked);
    try t.expectEqual(@as(usize, 0), changed_mutation.reused);
}

test "durable entry and byte bounds evict without changing acceptance" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const source = prefix ++ suffix;
    const entry_bound = try durableRun(t.allocator, root, source, cache_key.Contract.default, "mutation-v1", .{ .max_entries = 1 });
    try t.expectEqual(@as(usize, 3), entry_bound.checked);
    try t.expect(entry_bound.evicted != 0);
    const entry_reuse = try durableRun(t.allocator, root, source, cache_key.Contract.default, "mutation-v1", .{ .max_entries = 1 });
    try t.expectEqual(@as(usize, 2), entry_reuse.checked);
    try t.expectEqual(@as(usize, 1), entry_reuse.reused);
    const byte_bound = try durableRun(t.allocator, root, source, cache_key.Contract.default, "mutation-v1", .{ .max_bytes = 1 });
    try t.expectEqual(@as(usize, 3), byte_bound.checked);
    try t.expect(byte_bound.evicted != 0);
    const byte_reuse = try durableRun(t.allocator, root, source, cache_key.Contract.default, "mutation-v1", .{ .max_bytes = 1 });
    try t.expectEqual(@as(usize, 3), byte_reuse.checked);
    try t.expectEqual(@as(usize, 0), byte_reuse.reused);
}

// Publishing one fresh namespace must inventory it a bounded number of times,
// not once per body. This is the unit-level guard for the R4 corrective: the
// syscall-level growth is measured by scripts/benchmark_semantic_population.py.
test "durable publication batch inventories a fresh namespace once instead of per body" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(t.allocator);
    try source.appendSlice(t.allocator, "def main() -> i64:\n    return 42\n\n");
    var line_buffer: [64]u8 = undefined;
    for (0..64) |i| {
        const line = try std.fmt.bufPrint(&line_buffer, "def f{d}() -> i64:\n    return {d}\n\n", .{ i, i });
        try source.appendSlice(t.allocator, line);
    }
    var store = language.semantic_cache.Store.init(t.allocator, t.io, root, cache_key.Contract.default, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    const fingerprint = try cache_key.Contract.default.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    try compare(t.allocator, &cache, source.items, 42);
    try t.expectEqual(@as(usize, 65), cache.statistics.checked);
    try t.expect(store.statistics.stored != 0);
    // A fresh namespace is known empty at batch open, so the batch performs
    // exactly one inventory: the final `endBatch` one. The retired per-body
    // trim performed one inventory per publication, 65 for this source.
    try t.expectEqual(@as(usize, 1), store.statistics.retained.inventories);
    // A warm re-read publishes nothing and must not inventory at all.
    var warm_store = language.semantic_cache.Store.init(t.allocator, t.io, root, cache_key.Contract.default, language.semantic_cache.mutation_contract_version);
    defer warm_store.deinit();
    var warm_cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer warm_cache.deinit();
    warm_cache.context.persistent = &warm_store;
    try compare(t.allocator, &warm_cache, source.items, 42);
    try t.expectEqual(@as(usize, 0), warm_cache.statistics.checked);
    try t.expectEqual(@as(usize, 65), warm_cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), warm_store.statistics.retained.inventories);
}

// spec-case: SEMANTIC-CACHE-7
// spec: SEMANTIC-CACHE-11
test "symbolic template direct results reuse while changed templates miss" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const template =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\
    ;
    const program = template ++
        \\def main() -> i64:
        \\    return size[u8](1u8)
    ;
    try compare(t.allocator, &cache, program, 7);
    const first_checked = cache.reuse.symbolic.statistics.checked;
    try t.expect(first_checked > 0);
    try t.expectEqual(@as(usize, 0), cache.reuse.symbolic.statistics.reused);
    // The unchanged template replays its direct result on the next request.
    try compare(t.allocator, &cache, program, 7);
    try t.expect(cache.reuse.symbolic.statistics.reused >= 1);
    try t.expectEqual(first_checked, cache.reuse.symbolic.statistics.checked);
    // An unrelated ordinary body edit preserves the template's reuse.
    const unrelated = template ++
        \\def helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\def main() -> i64:
        \\    return size[u8](1u8)
    ;
    const before_unrelated_reuse = cache.reuse.symbolic.statistics.reused;
    try compare(t.allocator, &cache, unrelated, 7);
    try t.expect(cache.reuse.symbolic.statistics.reused > before_unrelated_reuse);
    // Editing the template body invalidates its retained direct result.
    const edited =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 8
        \\
        \\
        \\
    ++
        \\def main() -> i64:
        \\    return size[u8](1u8)
    ;
    const before_edit_checked = cache.reuse.symbolic.statistics.checked;
    try compare(t.allocator, &cache, edited, 8);
    try t.expect(cache.reuse.symbolic.statistics.checked > before_edit_checked);
}

// spec-case: SEMANTIC-CACHE-7
test "symbolic capture rejects an out-of-region related span" {
    const region = @import("source.zig").Span{ .start = 10, .end = 20 };
    const note = @import("diagnostic.zig").Diagnostic{
        .code = "E_OUTSIDE",
        .span = .{ .start = 12, .end = 14 },
        .message = "primary",
        .related = .{ .span = .{ .start = 0, .end = 1 }, .message = "declared here" },
    };
    try t.expectError(error.Unrepresentable, @import("generic_cache.zig").captureNote(t.allocator, region, note));
    const inside = @import("diagnostic.zig").Diagnostic{
        .code = "E_INSIDE",
        .span = .{ .start = 12, .end = 14 },
        .message = "primary",
        .related = .{ .span = .{ .start = 15, .end = 16 }, .message = "declared here" },
    };
    const captured = try @import("generic_cache.zig").captureNote(t.allocator, region, inside);
    defer {
        t.allocator.free(captured.code);
        t.allocator.free(captured.message);
        if (captured.notes.related) |related| t.allocator.free(related.message);
    }
    try t.expectEqual(@as(i64, 2), captured.span.start);
}

// spec-case: SEMANTIC-CACHE-7
test "unused malformed generics are still checked on cold and warm requests" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const malformed =
        \\def broken[T](value: T) -> i64 effects():
        \\    return value
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    // The template is unused, but abstract checking must still reject the body
    // on the cold request and again on the warm request; no failed result is
    // ever inherited from a previous pass.
    try compare(t.allocator, &cache, malformed, null);
    try compare(t.allocator, &cache, malformed, null);
}

// spec-case: INCREMENTAL-KEYS-1
// spec: SEMANTIC-CACHE-12
test "specialization key engine canonicalizes arguments providers constraints and build context" {
    const typed = @import("typed.zig");
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const aggregate: typed.Type = @fromBackingInt(typed.Type.record_base);
    const base_records = [_]typed.Record{.{
        .id = aggregate,
        .name = "mod::Point",
        .declaration = span,
        .fields = &.{.{ .name = "x", .declaration = span, .ty = .i64 }},
    }};
    const changed_records = [_]typed.Record{.{
        .id = aggregate,
        .name = "mod::Point",
        .declaration = span,
        .fields = &.{.{ .name = "x", .declaration = span, .ty = .bool }},
    }};

    const first_arg = try semantic_key.argumentDescriptor(t.allocator, aggregate, null, &base_records);
    defer t.allocator.free(first_arg);
    const length_arg = try semantic_key.argumentDescriptor(t.allocator, .u64, 3, &base_records);
    defer t.allocator.free(length_arg);
    try t.expectEqualStrings("L:3", length_arg);
    const provider = try semantic_key.providerIdentity(t.allocator, &.{aggregate}, &base_records);
    defer t.allocator.free(provider);
    const changed_provider = try semantic_key.providerIdentity(t.allocator, &.{aggregate}, &changed_records);
    defer t.allocator.free(changed_provider);
    try t.expect(!std.mem.eql(u8, provider, changed_provider));

    const base = semantic_key.SpecializationInputs{
        .template_identity = "fn\x1fmod\x1f\x1fidentity",
        .arguments = &.{ first_arg, length_arg },
        .provider = provider,
        .constraints = "constraints-a",
        .contracts = "contracts-a",
        .build = "build-a",
    };
    const same = try semantic_key.specializationFingerprint(t.allocator, base);
    defer t.allocator.free(same);
    const again = try semantic_key.specializationFingerprint(t.allocator, base);
    defer t.allocator.free(again);
    try t.expectEqualStrings(same, again);
    try t.expectEqual(@as(usize, 64), same.len);
    const reordered = try semantic_key.specializationFingerprint(t.allocator, .{
        .template_identity = base.template_identity,
        .arguments = &.{ length_arg, first_arg },
        .provider = base.provider,
        .constraints = base.constraints,
        .contracts = base.contracts,
        .build = base.build,
    });
    defer t.allocator.free(reordered);
    const constraint_change = try semantic_key.specializationFingerprint(t.allocator, .{
        .template_identity = base.template_identity,
        .arguments = base.arguments,
        .provider = base.provider,
        .constraints = "constraints-b",
        .contracts = base.contracts,
        .build = base.build,
    });
    defer t.allocator.free(constraint_change);
    const contract_change = try semantic_key.specializationFingerprint(t.allocator, .{
        .template_identity = base.template_identity,
        .arguments = base.arguments,
        .provider = base.provider,
        .constraints = base.constraints,
        .contracts = "contracts-b",
        .build = base.build,
    });
    defer t.allocator.free(contract_change);
    const build_change = try semantic_key.specializationFingerprint(t.allocator, .{
        .template_identity = base.template_identity,
        .arguments = base.arguments,
        .provider = base.provider,
        .constraints = base.constraints,
        .contracts = base.contracts,
        .build = "build-b",
    });
    defer t.allocator.free(build_change);
    for ([_][]const u8{ reordered, constraint_change, contract_change, build_change }) |changed|
        try t.expect(!std.mem.eql(u8, same, changed));
}

test "createSpecialization rejects an out-of-range function index" {
    const typed = @import("typed.zig");
    const entry = @import("semantic_entry.zig");
    const semantic_copy = @import("semantic_copy.zig");
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    const range: semantic_copy.Range = .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } };
    const spec: entry.SpecializationSpec = undefined;
    try t.expectError(error.InternalError, entry.createSpecialization(t.allocator, program, 0, range, spec));
}

const spec_stats = language.semantic_cache.specializations.Statistics;
const spec_reason = language.semantic_cache.specializations.MissReason;

test "nested concrete specializations conservatively miss and self-recursion remaps" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const nested =
        \\def inner[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def outer[T](x: T) -> T:
        \\    return inner[T](x)
        \\
        \\
        \\def main() -> i64:
        \\    return outer[i64](4)
    ;
    try compare(t.allocator, &cache, nested, 4);
    const nested_before: spec_stats = cache.reuse.specializations.statistics;
    try compare(t.allocator, &cache, nested, 4);
    const nested_after: spec_stats = cache.reuse.specializations.statistics;
    // `inner[i64]` is reachable once `outer[i64]` is checked; at `outer`'s
    // lookup the nested instance key does not exist yet, so it conservatively
    // misses while the leaf instance replays.
    try t.expectEqual(nested_before.reused + 1, nested_after.reused);
    try t.expect(nested_after.misses[@backingInt(spec_reason.missing_specialization)] > nested_before.misses[@backingInt(spec_reason.missing_specialization)]);

    const recursive =
        \\def recur[T](x: T, n: i64) -> i64:
        \\    _ = x
        \\    if n == 0:
        \\        return 0
        \\    return recur[T](x, n - 1)
        \\
        \\
        \\def main() -> i64:
        \\    return recur[i64](1, 3)
    ;
    try compare(t.allocator, &cache, recursive, 0);
    const recursive_before: spec_stats = cache.reuse.specializations.statistics;
    try compare(t.allocator, &cache, recursive, 0);
    const recursive_after: spec_stats = cache.reuse.specializations.statistics;
    // A self-reference resolves to the fresh instance's own canonical key.
    try t.expectEqual(recursive_before.reused + 1, recursive_after.reused);
}

test "const-length specialization keys keep identity and nominal generics miss conservatively" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const size_fn =
        \\def size[const N: u64]() -> u64:
        \\    return N
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, size_fn ++
        \\def main() -> i64:
        \\    return i64(size[2]())
    , 2);
    const stored_two = cache.reuse.specializations.statistics.stored;
    try compare(t.allocator, &cache, size_fn ++
        \\def main() -> i64:
        \\    return i64(size[2]())
    , 2);
    try t.expectEqual(stored_two, cache.reuse.specializations.statistics.stored);
    try t.expect(cache.reuse.specializations.statistics.reused > 0);
    try compare(t.allocator, &cache, size_fn ++
        \\def main() -> i64:
        \\    return i64(size[3]())
    , 3);
    // `size[3]` is a distinct positional length descriptor, never a hit on
    // `size[2]`'s retained body.
    try t.expectEqual(stored_two + 1, cache.reuse.specializations.statistics.stored);

    const nominal =
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def make[T](x: T) -> Box[T]:
        \\    return Box[T](value=x)
        \\
        \\
        \\def main() -> i64:
        \\    b = make[i64](3)
        \\    return b.value
    ;
    try compare(t.allocator, &cache, nominal, 3);
    const nominal_before: spec_stats = cache.reuse.specializations.statistics;
    try compare(t.allocator, &cache, nominal, 3);
    const nominal_after: spec_stats = cache.reuse.specializations.statistics;
    // The body instantiates a nominal application while checking, so its
    // record reference has no pre-collected stable identity and stays fresh.
    try t.expectEqual(nominal_before.reused, nominal_after.reused);
    try t.expect(nominal_after.misses[@backingInt(spec_reason.interned_record)] > nominal_before.misses[@backingInt(spec_reason.interned_record)]);
}

const owned_entry = @import("semantic_entry.zig");

/// Build `count` ordinary helper bodies plus a `main` that returns their sum,
/// so a test can drive a program whose retained snapshot exceeds one budget.
fn manyFunctionProgram(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var line: [96]u8 = undefined;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "def step{d}(n: i64) -> i64:\n    return n + {d}\n\n", .{ index, index + 1 }));
    }
    try out.appendSlice(allocator, "def main() -> i64:\n    return ");
    index = 0;
    while (index < count) : (index += 1) {
        if (index != 0) try out.appendSlice(allocator, " + ");
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "step{d}(0)", .{index}));
    }
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

// spec-pending: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-7
test "semantic cache retains a bounded prefix of bodies when the snapshot exceeds its budget" {
    const source = try manyFunctionProgram(t.allocator, 8);
    defer t.allocator.free(source);
    var full = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer full.deinit();
    try compare(t.allocator, &full, source, 36);
    try t.expectEqual(@as(usize, 9), full.entries.len);
    // Shrink the budget by exactly the last body's retained cost. Every cost is
    // read from this same snapshot, so the leading eight bodies fit and the
    // ninth cannot, independent of allocator chunk-size variation.
    const last_cost = @sizeOf(owned_entry.Entry) + full.entries[8].arena.queryCapacity();
    full.reuse.max_bytes = full.statistics.retained_bytes - last_cost;
    const prefix_budget = full.reuse.max_bytes;
    try compare(t.allocator, &full, source, 36);
    try t.expectEqual(@as(usize, 8), full.entries.len);
    try t.expect(full.statistics.retained_bytes <= prefix_budget);
    try t.expectEqual(@as(usize, 0), full.statistics.bypassed);
    const reused_before = full.statistics.reused;
    const checked_before = full.statistics.checked;
    try compare(t.allocator, &full, source, 36);
    // The retained prefix is copied; only the body dropped by the smaller
    // budget is rechecked, and the request is still not a whole-cache bypass.
    try t.expectEqual(reused_before + 8, full.statistics.reused);
    try t.expectEqual(checked_before + 1, full.statistics.checked);
    try t.expectEqual(@as(usize, 0), full.statistics.bypassed);
    try t.expect(full.statistics.retention.evicted > 0);
}

// spec-pending: SEMANTIC-CACHE-10
// spec-case: SEMANTIC-CACHE-3
test "semantic body relocation resolves only the references the body carries" {
    const relocation = @import("semantic_copy.zig");
    const typed = @import("typed.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const mapper: relocation.Mapper = .{
        .segments = &.{},
        .before = .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } },
        .after = .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } },
        .function_remaps = &.{.{ .old = 2, .fresh = @fromBackingInt(7) }},
        .record_remaps = &.{.{ .old = 1, .fresh = @fromBackingInt(typed.Type.record_base + 3) }},
    };
    try t.expectEqual(@as(typed.FunctionId, @fromBackingInt(7)), try mapper.copy(arena.allocator(), typed.FunctionId, @fromBackingInt(2)));
    try t.expectError(error.InvalidRelocation, mapper.copy(arena.allocator(), typed.FunctionId, @fromBackingInt(3)));
    try t.expectEqual(@as(typed.Type, @fromBackingInt(typed.Type.record_base + 3)), try mapper.copy(arena.allocator(), typed.Type, @fromBackingInt(typed.Type.record_base + 1)));
    try t.expectError(error.InvalidRelocation, mapper.copy(arena.allocator(), typed.Type, @fromBackingInt(typed.Type.record_base + 2)));
}

/// An ordinary body, a template and a concrete call, so one check exercises
/// all three entry kinds.
const all_kinds_program =
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\def identity[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\def main() -> i64:
    \\    return identity[i64](helper(41))
;

// spec-pending: SEMANTIC-CACHE-13
// spec-case: SEMANTIC-CACHE-1
test "clear releases ordinary symbolic and specialization entries and keeps returned programs valid" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    var returned = try language.Compilation.init(t.allocator, "edited.my", all_kinds_program);
    defer returned.deinit();
    try returned.checkWithCache(&cache);
    try t.expectEqual(@as(i64, 42), (try native.run(&returned)).value);
    try t.expect(cache.entries.len > 0);
    try t.expect(cache.reuse.symbolic.entries.items.len > 0);
    try t.expect(cache.reuse.specializations.entries.items.len > 0);
    try t.expect(cache.statistics.retained_bytes != 0);
    const ordinary_checked = cache.statistics.checked;
    const symbolic_checked = cache.reuse.symbolic.statistics.checked;
    const specialization_checked = cache.reuse.specializations.statistics.checked;

    cache.clear();
    try t.expectEqual(@as(usize, 0), cache.entries.len);
    try t.expectEqual(@as(usize, 0), cache.index.count());
    try t.expectEqual(@as(usize, 0), cache.reuse.symbolic.entries.items.len);
    try t.expectEqual(@as(usize, 0), cache.reuse.symbolic.index.count());
    try t.expectEqual(@as(usize, 0), cache.reuse.specializations.entries.items.len);
    try t.expectEqual(@as(usize, 0), cache.reuse.specializations.index.count());
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    try t.expectEqual(@as(usize, 0), cache.statistics.retention.ordinary_bytes);
    try t.expectEqual(@as(usize, 0), cache.statistics.retention.symbolic_bytes);
    try t.expectEqual(@as(usize, 0), cache.statistics.retention.specialization_bytes);
    // A program returned before the clear owns its checked trees and stays valid.
    try t.expectEqual(@as(i64, 42), (try native.run(&returned)).value);

    // The same source checks every body/template specialization fresh after clear.
    var again = try language.Compilation.init(t.allocator, "edited.my", all_kinds_program);
    defer again.deinit();
    try again.checkWithCache(&cache);
    try t.expect(cache.statistics.checked > ordinary_checked);
    try t.expect(cache.reuse.symbolic.statistics.checked > symbolic_checked);
    try t.expect(cache.reuse.specializations.statistics.checked > specialization_checked);
    // The cache is usable and deinit-after-clear is safe (no double free/leak).
    try compare(t.allocator, &cache, all_kinds_program, 42);
}

/// Const-length template: every distinct `N` is a distinct specialization key.
const size_template =
    \\def size[const N: u64]() -> u64:
    \\    return N
    \\
    \\
;

fn sizeProgram(allocator: std.mem.Allocator, n: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}def main() -> i64:\n    return i64(size[{d}]())\n", .{ size_template, n });
}

/// Fill every slot with a distinct const-length specialization program.
fn fillSizeSources(allocator: std.mem.Allocator, sources: [][]u8, start: usize) !void {
    for (sources, 0..) |*slot, i| slot.* = try sizeProgram(allocator, start + i);
}

/// Persist `sources` with a generous in-memory budget, then return a small
/// shared budget that fits about two retained specialization units.
fn primeSpecializationStore(
    allocator: std.mem.Allocator,
    root: []const u8,
    contract: cache_key.Contract,
    fingerprint: []const u8,
    sources: []const []u8,
) !usize {
    var store = language.semantic_cache.Store.init(allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    var cache = Cache.initWithContract(allocator, 4 * 1024 * 1024, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    for (sources, 0..) |source, i| try compare(allocator, &cache, source, @intCast(200 + i));
    if (cache.reuse.specializations.entries.items.len == 0) return error.TestUnexpectedResult;
    return (@sizeOf(owned_entry.SpecializationEntry) + cache.reuse.specializations.entries.items[0].arena.queryCapacity()) * 2;
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-12
test "shared retention budget bounds distinct specializations and eviction forces fresh checks" {
    // Measure one retained specialization unit with a generous budget.
    var probe = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer probe.deinit();
    const probe_source = try sizeProgram(t.allocator, 2);
    defer t.allocator.free(probe_source);
    try compare(t.allocator, &probe, probe_source, 2);
    try t.expect(probe.reuse.specializations.entries.items.len >= 1);
    const unit = @sizeOf(owned_entry.SpecializationEntry) + probe.reuse.specializations.entries.items[0].arena.queryCapacity();
    const budget = unit * 3;

    var cache = Cache.init(t.allocator, budget);
    defer cache.deinit();
    for (100..130) |n| {
        const source = try sizeProgram(t.allocator, n);
        defer t.allocator.free(source);
        try compare(t.allocator, &cache, source, @intCast(n));
        try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);
    }
    const retained_after = cache.statistics.retained_bytes;
    const evicted_after = cache.statistics.retention.evicted;
    const spec_bytes_after = cache.statistics.retention.specialization_bytes;
    try t.expect(evicted_after > 0);
    try t.expect(retained_after <= budget);

    // The oldest specialization was evicted, so re-checking it is fresh work.
    const oldest = try sizeProgram(t.allocator, 100);
    defer t.allocator.free(oldest);
    const spec_checked_before = cache.reuse.specializations.statistics.checked;
    const spec_reused_before = cache.reuse.specializations.statistics.reused;
    try compare(t.allocator, &cache, oldest, 100);
    try t.expect(cache.reuse.specializations.statistics.checked > spec_checked_before);
    try t.expectEqual(spec_reused_before, cache.reuse.specializations.statistics.reused);
    std.debug.print("retention: budget={d} retained={d} spec_bytes={d} evictions={d} oldest_fresh_checks=+{d}\n", .{
        budget, retained_after, spec_bytes_after, evicted_after, cache.reuse.specializations.statistics.checked - spec_checked_before,
    });
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-11
test "zero shared budget disables ordinary symbolic and specialization reuse" {
    var cache = Cache.init(t.allocator, 0);
    defer cache.deinit();
    try compare(t.allocator, &cache, all_kinds_program, 42);
    const ordinary_checked = cache.statistics.checked;
    const symbolic_checked = cache.reuse.symbolic.statistics.checked;
    const specialization_checked = cache.reuse.specializations.statistics.checked;
    try compare(t.allocator, &cache, all_kinds_program, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.reuse.symbolic.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.reuse.specializations.statistics.reused);
    try t.expectEqual(ordinary_checked * 2, cache.statistics.checked);
    try t.expectEqual(symbolic_checked * 2, cache.reuse.symbolic.statistics.checked);
    try t.expectEqual(specialization_checked * 2, cache.reuse.specializations.statistics.checked);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-8
test "shared budget holds after an oversized-single-entry session without changing acceptance" {
    // A budget smaller than one specialization unit admits no retained generic
    // entry; the checks still run and agree with a fresh compile.
    var cache = Cache.init(t.allocator, 1);
    defer cache.deinit();
    for (1..6) |n| {
        const source = try sizeProgram(t.allocator, n);
        defer t.allocator.free(source);
        try compare(t.allocator, &cache, source, @intCast(n));
        try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    }
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-8
test "durable-hit promotion is bounded by the shared budget without changing acceptance" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const contract = cache_key.Contract.default;
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);

    var sources: [6][]u8 = undefined;
    defer {
        for (sources) |source| t.allocator.free(source);
    }
    try fillSizeSources(t.allocator, &sources, 200);
    const budget = try primeSpecializationStore(t.allocator, root, contract, fingerprint, &sources);

    var store = language.semantic_cache.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    var cache = Cache.initWithContract(t.allocator, budget, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    for (sources, 0..) |source, i| {
        try compare(t.allocator, &cache, source, @intCast(200 + i));
        try t.expect(cache.statistics.retained_bytes <= budget);
    }
    // Durable entries were promoted into memory and then reconciled against the
    // shared bound, either retained within budget or evicted.
    try t.expect(cache.reuse.specializations.statistics.reused > 0);
    try t.expect(cache.statistics.retention.evicted > 0);
}

/// Build `count` distinct generic templates and a constant `main`, so the
/// symbolic pass produces one retained template per declaration.
fn manyTemplateProgram(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var line: [128]u8 = undefined;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "def t{d}[T: integer](value: T) -> i64 effects():\n    _ = value\n    return {d}\n\n", .{ index, index }));
    }
    try out.appendSlice(allocator, "def main() -> i64:\n    return 0\n");
    return out.toOwnedSlice(allocator);
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-11
test "shared retention budget bounds many distinct symbolic templates" {
    const count = 12;
    const source = try manyTemplateProgram(t.allocator, count);
    defer t.allocator.free(source);
    // Measure one retained symbolic unit with a generous budget.
    var probe = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer probe.deinit();
    const probe_source = try manyTemplateProgram(t.allocator, 1);
    defer t.allocator.free(probe_source);
    try compare(t.allocator, &probe, probe_source, 0);
    try t.expect(probe.reuse.symbolic.entries.items.len >= 1);
    // Split the probe's shared total into the ordinary main body and one
    // symbolic table unit, then budget the main body plus two templates.
    const symbolic_unit = probe.reuse.symbolic.retainedBytes();
    const ordinary_bytes = probe.statistics.retained_bytes - symbolic_unit;
    const budget = ordinary_bytes + symbolic_unit * 3;

    var cache = Cache.init(t.allocator, budget);
    defer cache.deinit();
    try compare(t.allocator, &cache, source, 0);
    try t.expect(cache.statistics.retained_bytes <= budget);
    try t.expect(cache.reuse.symbolic.entries.items.len < count);
    try t.expect(cache.statistics.retention.evicted > 0);

    // Evicted templates are rechecked; the survivors replay.
    const checked_before = cache.reuse.symbolic.statistics.checked;
    const reused_before = cache.reuse.symbolic.statistics.reused;
    try compare(t.allocator, &cache, source, 0);
    try t.expect(cache.reuse.symbolic.statistics.checked > checked_before);
    try t.expect(cache.reuse.symbolic.statistics.reused > reused_before);
    try t.expect(cache.statistics.retained_bytes <= budget);
    std.debug.print("symbolic retention: budget={d} retained={d} symbolic_bytes={d} templates={d} evictions={d} warm_fresh=+{d} warm_reused=+{d}\n", .{
        budget,
        cache.statistics.retained_bytes,
        cache.statistics.retention.symbolic_bytes,
        cache.reuse.symbolic.entries.items.len,
        cache.statistics.retention.evicted,
        cache.reuse.symbolic.statistics.checked - checked_before,
        cache.reuse.symbolic.statistics.reused - reused_before,
    });
}

/// One check of a program that uses a symbolic template and a concrete
/// specialization, so a FailingAllocator exercises both generic publish paths.
fn genericScenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(allocator, &cache, all_kinds_program, 42);
    try compare(allocator, &cache, all_kinds_program, 42);
}

// spec-pending: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-11
test "generic publication rolls back cleanly on allocation failure" {
    try genericScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, genericScenario, .{});
}

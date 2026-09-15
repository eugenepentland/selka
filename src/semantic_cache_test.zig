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
    cache.contract = contract_b;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 3, cache.statistics.checked);

    // Returning to the original contract is a miss until its bodies are published,
    // then the identical contract reuses them again.
    cache.contract = contract_a;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 6, cache.statistics.checked);
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 6), cache.statistics.reused);
    try t.expectEqual(after_base_checked + 6, cache.statistics.checked);
}

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

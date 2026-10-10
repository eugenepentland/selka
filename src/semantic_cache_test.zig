//! Changed-source cached/fresh agreement includes ownership, diagnostics and interrupted snapshots.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const checked_typed = @import("typed.zig");
const native = @import("native_execute.zig");
const semantic_key = @import("semantic_key.zig");
const cache_key = @import("cache_key.zig");
const semantic_store = @import("semantic_store.zig");
const Cache = language.semantic_cache.Cache;
const prefix =
    \\func helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\
;
const suffix =
    \\func keep(n: i64) -> i64:
    \\    mut unused = 1
    \\    mut x = n
    \\    x = x + 1
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    return keep(helper(40))
;
/// An allocator that never grows or shrinks a block in place, so every resize
/// becomes a fresh allocation. `checkAllAllocationFailures` needs the same
/// allocations in the same order on every run, but whether the backing
/// allocator can resize in place depends on the address-space layout left by
/// everything else in the process (a native run maps and unmaps pages), which
/// made the count drift by one between otherwise identical runs.
const Steady = struct {
    inner: std.mem.Allocator,
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Steady = @ptrCast(@alignCast(ctx));
        return self.inner.rawAlloc(len, alignment, ra);
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *Steady = @ptrCast(@alignCast(ctx));
        self.inner.rawFree(memory, alignment, ra);
    }
    fn allocator(self: *Steady) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
};
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
        \\func helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\
    ++ suffix, 43);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 4), cache.statistics.checked);
    try compare(allocator, &cache,
        \\func helper(n: i64) -> i64:
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
        \\func helper(n: bool) -> i64:
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
        \\record Item:
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
        \\func main() -> i64:
        \\    return N
    , 1);
    try compare(t.allocator, &cache,
        \\const N: i64 = 2
        \\
        \\
        \\func main() -> i64:
        \\    return N
    , 2);
    try compare(t.allocator, &cache,
        \\func id[T](n: T) -> T:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return id[i64](42)
    , 42);
    try compare(t.allocator, &cache,
        \\type Number = i64
        \\
        \\
        \\func main() -> i64:
        \\    return Number(42)
    , 42);
    try t.expectEqual(reused_before_unrelated + 3, cache.statistics.reused);
}
// spec-case: SEMANTIC-CACHE-2
// spec-case: CONSTANT-2
test "managed constant edits invalidate dependent bodies while unrelated constants reuse" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const main = "func main() -> int:\n    return len(S) + B[0]\n";
    try compare(t.allocator, &cache, "const S: str = \"a\"\nconst B: bytes = b\"A\"\n" ++ main, 66);
    try compare(t.allocator, &cache, "const S: str = \"é🙂\"\nconst B: bytes = b\"B\"\n" ++ main, 68);
    try compare(t.allocator, &cache, "const S: str = \"a\" + \"b\"\nconst B: bytes = b\"B\"\n" ++ main, null);
    // `B` is unchanged in the second request and reused there; every reader of the
    // edited `S` misses because the constant fingerprint participates in its context.
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    try t.expectEqual(@as(usize, 2), cache.statistics.stored);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
}
// spec: SEMANTIC-CACHE-16
test "a same-length body edit misses the retained body and reuses its neighbours" {
    const original = "func tweak(n: i64) -> i64:\n    return n + 1\n\n\nfunc keep(n: i64) -> i64:\n    return n * 2\n\n\nfunc main() -> i64:\n    return keep(tweak(20))\n";
    const mutated = "func tweak(n: i64) -> i64:\n    return n + 2\n\n\nfunc keep(n: i64) -> i64:\n    return n * 2\n\n\nfunc main() -> i64:\n    return keep(tweak(20))\n";
    // The two sources are the same length and differ in exactly one body byte, so
    // only the byte comparison can tell them apart.
    try t.expectEqual(original.len, mutated.len);
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, original, 42);
    const checked = cache.statistics.checked;
    const reused = cache.statistics.reused;
    const misses = cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.region_bytes_changed)];
    try compare(t.allocator, &cache, mutated, 44);
    try t.expectEqual(checked + 1, cache.statistics.checked);
    try t.expectEqual(reused + 2, cache.statistics.reused);
    try t.expectEqual(misses + 1, cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.region_bytes_changed)]);
}

// spec-case: SEMANTIC-CACHE-16
test "a same-length declaration edit misses with the dependency reason it always did" {
    const original = "func widen(n: i64) -> i64:\n    return n\n\n\nfunc main() -> i64:\n    return widen(41)\n";
    const mutated = "func widen(m: i64) -> i64:\n    return m\n\n\nfunc main() -> i64:\n    return widen(41)\n";
    try t.expectEqual(original.len, mutated.len);
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, original, 41);
    const misses = cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.context_changed)];
    try compare(t.allocator, &cache, mutated, 41);
    // The renamed parameter changes the edited declaration's own region text and
    // the fingerprint its caller depends on, so both miss as a dependency change
    // and neither is served from the retained pair.
    try t.expectEqual(misses + 2, cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.context_changed)]);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
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
        \\func helper(n: i64) -> i64:
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
        \\func main() -> i64:
        \\    mut cb = helper
        \\    return cb(40)
    ;
    try compare(t.allocator, &cache,
        \\func helper(n: i64) -> i64 effects():
        \\    return n + 1
        \\
        \\
        \\
    ++ caller, 41);
    try compare(t.allocator, &cache,
        \\func helper(n: i64) -> i64 effects():
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
        \\func size[const N: u64]() -> u64:
        \\    return N
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, function ++
        \\func main() -> i64:
        \\    return i64(size[2]())
    , 2);
    try compare(t.allocator, &cache, function ++
        \\func main() -> i64:
        \\    return i64(size[3]())
    , 3);
    const nominal =
        \\record Chunk[const N: u64]:
        \\    items: FixedArray[i64, N]
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, nominal ++
        \\func main() -> i64:
        \\    mut x = Chunk[1](items=FixedArray[int, 1]([42]))
        \\    return x.items[0]
    , 42);
    try compare(t.allocator, &cache, nominal ++
        \\func main() -> i64:
        \\    mut x = Chunk[2](items=FixedArray[int, 2]([43, 0]))
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
    // The extern declaration is never executed, so this stays a checking-only test.
    const shared =
        \\extern func tick(host: Host) -> i64 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64 effects():
        \\    return change(host)
        \\
        \\
        \\
    ;
    var first = try language.Compilation.init(t.allocator, "edited.my", shared ++
        \\func change(host: Host) -> i64:
        \\    _ = host
        \\    return 42
    );
    defer first.deinit();
    try first.checkWithCache(&cache);
    var second = try language.Compilation.init(t.allocator, "edited.my", shared ++
        \\func change(host: Host) -> i64:
        \\    return tick(host)
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
    runtime.runtime_abi = "runtime-abi-v4";
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
    const generic = "func identity[T](value: T) -> T:\n    return value\n\n\n";
    const second = "func second() -> i64:\n    return 7\n\n\n";
    const main = "func main() -> i64:\n    return first() + second()\n";
    try compare(t.allocator, &cache, "func first() -> i64:\n    return 1\n" ++ second ++ main ++ generic, 8);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
    try compare(t.allocator, &cache, "func first() -> i64:\n    return 2\n" ++ second ++ main ++ generic, 9);
    // The edited body is rechecked; the other two ordinary bodies are reused even
    // though the program still contains an unused generic template.
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 4), cache.statistics.checked);
}

test "insert delete and reorder unrelated declarations preserve function and type identities" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const ordered =
        \\record A:
        \\    n: i64
        \\
        \\
        \\record B:
        \\    n: i64
        \\
        \\
        \\func first() -> i64:
        \\    return 1
        \\
        \\
        \\func unused() -> i64:
        \\    return 9
        \\
        \\
        \\func main() -> i64:
        \\    mut a = A(n=40)
        \\    mut b = B(n=1)
        \\    return a.n + b.n + first()
    ;
    try compare(t.allocator, &cache, ordered, 42);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    const shuffled =
        \\record B:
        \\    n: i64
        \\
        \\
        \\record A:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut a = A(n=40)
        \\    mut b = B(n=1)
        \\    return a.n + b.n + first()
        \\
        \\
        \\func first() -> i64:
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
    // `debug` is a reserved builtin (a recorded negative lookup) and, unlike a
    // stream write, leaves the native run's stderr clean, so this test checks
    // resolution without executing a program.
    const base = "func main() -> i64:\n    debug(\"hi\")\n    return 1\n";
    var cached = try language.Compilation.init(t.allocator, "edited.my", base);
    defer cached.deinit();
    var fresh = try language.Compilation.init(t.allocator, "edited.my", base);
    defer fresh.deinit();
    try cached.checkWithCache(&cache);
    try fresh.check();
    const introduced =
        \\func debug(message: str) -> Unit:
        \\    _ = message
        \\
        \\
        \\func main() -> i64:
        \\    debug("hi")
        \\    return 1
    ;
    const before = cache.statistics.reused;
    var changed = try language.Compilation.init(t.allocator, "edited.my", introduced);
    defer changed.deinit();
    var changed_fresh = try language.Compilation.init(t.allocator, "edited.my", introduced);
    defer changed_fresh.deinit();
    try changed.checkWithCache(&cache);
    try changed_fresh.check();
    // Introducing the declaration changes resolution, so `main` misses even
    // though its body bytes are unchanged.
    try t.expectEqual(before, cache.statistics.reused);
}

test "reused bodies relocate diagnostics and warnings after code moves" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const base =
        \\func helper() -> i64:
        \\    mut unused = 41
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return helper()
    ;
    try compare(t.allocator, &cache, base, 1);
    const moved =
        \\func unrelated() -> i64:
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
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> i64:
        \\    mut values = [1]
        \\    touch(mut values)
        \\    return values[0]
    ;
    try compare(t.allocator, &cache, writing, 1);
    const reading =
        \\func touch(mut values: int[]) -> Unit:
        \\    mut first = 1
        \\    values[0] = first
        \\
        \\
        \\func main() -> i64:
        \\    mut values = [1]
        \\    touch(mut values)
        \\    return values[0]
    ;
    const before = cache.statistics.reused;
    // `touch`'s signature is unchanged, so `main` is reused; its summary is
    // recomputed by the mandatory global effect pass and must match fresh.
    try compare(t.allocator, &cache, reading, 1);
    try t.expectEqual(before + 1, cache.statistics.reused);
}

// spec-case: SEMANTIC-CACHE-7
test "declared callback slots and matching function values reuse when the contract is stable" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\func apply(f: func(i64) -> i64 effects(), x: i64) -> i64 effects():
        \\    return f(x)
        \\
        \\
        \\func one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\func main() -> i64 effects():
        \\    return apply(one, 41)
    ;
    try compare(t.allocator, &cache, program, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    // The declared callback parameter is interned before checking and `one`'s
    // contract matches it exactly, so the callable slot has a stable remap.
    try t.expectEqual(@as(usize, 0), cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.function_value)]);

    // Only the callee body changes: `main` still stores the same declared
    // callback contract, so its body reuses and revalidates globally.
    const edited =
        \\func apply(f: func(i64) -> i64 effects(), x: i64) -> i64 effects():
        \\    return f(x) + 0
        \\
        \\
        \\func one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\func main() -> i64 effects():
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
        \\func apply(f: func(i64) -> i64 effects(output), x: i64) -> i64 effects(output):
        \\    return f(x)
        \\
        \\
        \\func one(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\func main(out: Stream) -> i64:
        \\    _ = out
        \\    return apply(one, 41)
    ;
    try compare(t.allocator, &cache, program, 42);
    // `one`'s own contract differs from the declared callback parameter, so its
    // callable contract record is interned while checking and cannot be remapped.
    try t.expect(cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.function_value)] > 0);
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
        \\func identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\func main() -> i64:
        \\    return identity[i64](42)
    ;
    try compare(t.allocator, &cache, program, 42);
    try t.expect(cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.generic_specialization)] > 0);
    const before = cache.statistics.reused;
    const before_specialization = cache.reuse.specializations.statistics.reused;
    try compare(t.allocator, &cache, program, 42);
    // C3: the leaf specialization body itself is reused. Its caller is still a
    // conservative miss because ordinary bodies that reference a specialization
    // are not retained without a validated instance-key remap.
    try t.expectEqual(before + 1, cache.statistics.reused);
    try t.expectEqual(before_specialization + 1, cache.reuse.specializations.statistics.reused);
    try t.expect(cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.generic_specialization)] > 0);
}

// spec-case: SEMANTIC-CACHE-7
test "pre-collected array types reuse while a changed referenced contract invalidates dependents" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const program =
        \\func pair() -> FixedArray[i64, 2]:
        \\    return FixedArray[int, 2]([1, 2])
        \\
        \\
        \\func main() -> i64:
        \\    return pair()[0]
    ;
    try compare(t.allocator, &cache, program, 1);
    const before = cache.statistics.reused;
    try compare(t.allocator, &cache, program, 1);
    // The fixed array layout is collected with the declaration, so the ordinary
    // bodies remap it by stable identity and reuse.
    try t.expectEqual(before + 2, cache.statistics.reused);

    const edited =
        \\func pair() -> FixedArray[i64, 3]:
        \\    return FixedArray[int, 3]([1, 2, 3])
        \\
        \\
        \\func main() -> i64:
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
    cache.context.mutation_contract = "mutation-contract-under-test";
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

/// Borrow one retained entry's checked contract digest by declaration key suffix.
fn storedContract(cache: *Cache, key_suffix: []const u8) [32]u8 {
    for (cache.entries) |entry| {
        if (std.mem.endsWith(u8, entry.meta.identity.key, key_suffix)) return entry.meta.identity.checked_contract;
    }
    unreachable;
}

fn functionReturnOrigin(program: checked_typed.Program, name: []const u8) checked_typed.ReturnOrigin {
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

const durable_body_source =
    \\record Item:
    \\    n: i64
    \\
    \\func helper(n: i64) -> i64:
    \\    return Item(n=n).n + 1
    \\
    \\
++ suffix;

/// Keep less than one ordinary entry in memory, while keeping durable files.
const DurableWork = struct { checked: usize, reused: usize, stored: usize, damaged: usize, misses: language.semantic_cache.MissCounts };
fn transientDurableRun(root: []const u8, bytes: []const u8, expected: i64) !DurableWork {
    const contract = cache_key.Contract.default;
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var store = semantic_store.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    var cache = Cache.initWithContract(t.allocator, 1, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    try compare(t.allocator, &cache, bytes, expected);
    try t.expectEqual(@as(usize, 0), cache.entries.len);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    return .{
        .checked = cache.statistics.checked,
        .reused = cache.statistics.reused,
        .stored = store.statistics.stored,
        .damaged = store.statistics.damaged,
        .misses = cache.statistics.rejections.total,
    };
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-3
test "copyEntry restores exact default source proofs outside declaration region" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const bytes =
        \\record Item:
        \\    n: i64 = 42
        \\
        \\func get() -> i64:
        \\    return Item().n
        \\
        \\func main() -> i64:
        \\    return get()
    ;
    _ = try transientDurableRun(root, bytes, 42);
    const warm = try transientDurableRun(root, bytes, 42);
    try t.expectEqual(@as(usize, 0), warm.checked);
    try t.expectEqual(@as(usize, 2), warm.reused);
    try t.expectEqual(@as(usize, 0), warm.misses[@backingInt(language.semantic_cache.MissReason.relocation_failed)]);
    const edited = try t.allocator.dupe(u8, bytes);
    defer t.allocator.free(edited);
    edited[std.mem.indexOf(u8, edited, "42").? + 1] = '3';
    const changed = try transientDurableRun(root, edited, 43);
    try t.expect(changed.checked > 0);
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-15
test "durable bodies restore beyond the retention budget with edits and remapped identities" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const cold = try transientDurableRun(root, durable_body_source, 42);
    try t.expectEqual(@as(usize, 3), cold.checked);
    try t.expectEqual(@as(usize, 3), cold.stored);
    const warm = try transientDurableRun(root, durable_body_source, 42);
    try t.expectEqual(@as(usize, 0), warm.checked);
    try t.expectEqual(@as(usize, 3), warm.reused);
    try t.expectEqual(@as(usize, 0), warm.stored);
    // Same-length edits must compare body bytes even on an on-demand hit.
    const edited = try t.allocator.dupe(u8, durable_body_source);
    defer t.allocator.free(edited);
    edited[std.mem.indexOf(u8, edited, ".n + 1").? + 5] = '2';
    const changed = try transientDurableRun(root, edited, 43);
    try t.expectEqual(@as(usize, 1), changed.checked);
    try t.expectEqual(@as(usize, 2), changed.reused);
    try t.expectEqual(@as(usize, 1), changed.stored);
    // Shift source, function and nominal type ordinals before restoring every
    // old body; the fresh comparison checks values, facts and warning spans.
    const shifted = try std.mem.concat(t.allocator, u8, &.{
        "record Unrelated:\n    n: bool\n\nfunc uncalled() -> i64:\n    return 0\n\n",
        edited,
    });
    defer t.allocator.free(shifted);
    const moved = try transientDurableRun(root, shifted, 43);
    try t.expectEqual(@as(usize, 1), moved.checked);
    try t.expectEqual(@as(usize, 3), moved.reused);
    const repeated = try transientDurableRun(root, shifted, 43);
    try t.expectEqual(@as(usize, 0), repeated.checked);
    try t.expectEqual(@as(usize, 4), repeated.reused);
    try t.expectEqual(@as(usize, 0), repeated.stored);
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-15
test "durable bodies restore persistUnretained closes its batch on allocation failure" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const contract = cache_key.Contract.default;
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var seed = Cache.initWithContract(t.allocator, 4 << 20, fingerprint);
    defer seed.deinit();
    var unit = try language.Compilation.init(t.allocator, "edited.my", prefix ++ suffix);
    defer unit.deinit();
    try unit.checkWithCache(&seed);
    var failures = t.FailingAllocator.init(t.allocator, .{});
    var store = semantic_store.Store.init(failures.allocator(), t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    var cache = Cache.initWithContract(t.allocator, 1, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    var session = try cache.begin(unit.arena.allocator(), unit.src, unit.syntax.?, unit.program.?.records);
    try t.expectEqual(seed.entries.len, session.ranges.len);
    for (seed.entries, session.ranges) |entry, *range| range.* = entry.range;
    // beginBatch's namespace-existence probe allocates once; fail the first
    // publication allocation after the batch is active, exercising cleanup.
    failures.fail_index = failures.alloc_index + 1;
    try t.expectError(error.OutOfMemory, session.remember(unit.program.?));
    try t.expect(store.batch == null);
    try t.expectEqual(@as(usize, 0), cache.entries.len);
    failures.fail_index = std.math.maxInt(usize);
    try session.remember(unit.program.?);
    try t.expect(store.batch == null);
    try t.expectEqual(@as(usize, 3), store.statistics.stored);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}

// spec-case: SEMANTIC-CACHE-15
test "a damaged on-demand body rechecks and republishes without retaining trees" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    _ = try transientDurableRun(root, durable_body_source, 42);
    try t.expect(try truncateFirstEntry(t.allocator, root, cache_key.Contract.default));
    const repaired = try transientDurableRun(root, durable_body_source, 42);
    try t.expectEqual(@as(usize, 1), repaired.checked);
    try t.expectEqual(@as(usize, 2), repaired.reused);
    try t.expectEqual(@as(usize, 1), repaired.stored);
    try t.expect(repaired.damaged > 0);
    const warm = try transientDurableRun(root, durable_body_source, 42);
    try t.expectEqual(@as(usize, 0), warm.checked);
    try t.expectEqual(@as(usize, 3), warm.reused);
    try t.expectEqual(@as(usize, 0), warm.stored);
}

// spec-case: SEMANTIC-CACHE-9
test "durable restore combines a retained prefix with temporary body hits" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const contract = cache_key.Contract.default;
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var store = semantic_store.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    var seed = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer seed.deinit();
    seed.context.persistent = &store;
    try compare(t.allocator, &seed, durable_body_source, 42);
    // Allow the first entry and some arena growth variation, while excluding
    // the complete snapshot. Both memory and durable paths must supply trees.
    const budget = prefixRetainedCost(seed.entries[0..1]) + 1024;
    try t.expect(budget < seed.statistics.retained_bytes);
    var warm_store = semantic_store.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer warm_store.deinit();
    var warm = Cache.initWithContract(t.allocator, budget, fingerprint);
    defer warm.deinit();
    warm.context.persistent = &warm_store;
    try compare(t.allocator, &warm, durable_body_source, 42);
    try t.expect(warm.entries.len > 0 and warm.entries.len < 3);
    try t.expect(warm.statistics.retained_bytes <= budget);
    try t.expectEqual(@as(usize, 0), warm.statistics.checked);
    try t.expectEqual(@as(usize, 3), warm.statistics.reused);
    try t.expectEqual(@as(usize, 0), warm_store.statistics.stored);
}

const DurableRun = struct { checked: usize, reused: usize, evicted: usize = 0 };

fn durableRun(allocator: std.mem.Allocator, root: []const u8, source: []const u8, contract: cache_key.Contract, mutation_contract: []const u8, limits: semantic_store.Limits) !DurableRun {
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
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = "runtime-abi-v4", .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
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
    try source.appendSlice(t.allocator, "func main() -> i64:\n    return 42\n\n");
    var line_buffer: [64]u8 = undefined;
    for (0..64) |i| {
        const line = try std.fmt.bufPrint(&line_buffer, "func f{d}() -> i64:\n    return {d}\n\n", .{ i, i });
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

// spec: SEMANTIC-CACHE-15
test "durable batch publication renames complete images without a filesystem sync, cold or warm" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(t.allocator);
    try source.appendSlice(t.allocator, "func main() -> i64:\n    return 42\n\n");
    var line_buffer: [64]u8 = undefined;
    for (0..64) |i| {
        const line = try std.fmt.bufPrint(&line_buffer, "func f{d}() -> i64:\n    return {d}\n\n", .{ i, i });
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
    try t.expect(store.statistics.stored >= 2);
    try t.expectEqual(@as(usize, 0), store.statistics.bypassed);
    var warm_store = language.semantic_cache.Store.init(t.allocator, t.io, root, cache_key.Contract.default, language.semantic_cache.mutation_contract_version);
    defer warm_store.deinit();
    var warm_cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer warm_cache.deinit();
    warm_cache.context.persistent = &warm_store;
    try compare(t.allocator, &warm_cache, source.items, 42);
    try t.expectEqual(@as(usize, 65), warm_cache.statistics.reused);
    // A warm request publishes nothing.
    try t.expectEqual(@as(usize, 0), warm_store.statistics.stored);
}

// spec-case: SEMANTIC-CACHE-15
test "a torn durable entry is a miss that rechecks and republishes in one batch" {
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
    }
    try t.expect(try truncateFirstEntry(t.allocator, root, contract));
    var store = language.semantic_cache.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    // The torn image missed and its body checked fresh, then the fresh group was
    // republished; acceptance and diagnostics still agree.
    try t.expect(cache.statistics.checked > 0);
    try t.expect(store.statistics.stored > 0);
}

// spec-case: SEMANTIC-CACHE-15
test "an interrupted staging file and a foreign entry are ignored" {
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
    }
    // A crashed staging file and an unrelated complete-looking file model an
    // interrupted publisher and a concurrent one; both are invisible to lookup.
    try writeNamespaceFile(t.allocator, root, contract, "interrupted.tmp", "garbage");
    try writeNamespaceFile(t.allocator, root, contract, "foreign-entry", "garbage");
    var store = language.semantic_cache.Store.init(t.allocator, t.io, root, contract, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    const fingerprint = try contract.fingerprint(t.allocator);
    defer t.allocator.free(fingerprint);
    var cache = Cache.initWithContract(t.allocator, 4 * 1024 * 1024, fingerprint);
    defer cache.deinit();
    cache.context.persistent = &store;
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.checked);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), store.statistics.stored);
}

/// Write one file directly into the contract namespace, bypassing publication.
fn writeNamespaceFile(allocator: std.mem.Allocator, root: []const u8, contract: cache_key.Contract, name: []const u8, bytes: []const u8) !void {
    var hex: [64]u8 = undefined;
    contract.fingerprintHex(&hex);
    const directory = try std.fs.path.join(allocator, &.{ root, semantic_store.format_version, &hex });
    defer allocator.free(directory);
    try std.Io.Dir.cwd().createDirPath(t.io, directory);
    const path = try std.fs.path.join(allocator, &.{ directory, name });
    defer allocator.free(path);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
}

/// Truncate the first durable entry file under `root` so its checksum fails.
fn truncateFirstEntry(allocator: std.mem.Allocator, root: []const u8, contract: cache_key.Contract) !bool {
    var hex: [64]u8 = undefined;
    contract.fingerprintHex(&hex);
    const directory = try std.fs.path.join(allocator, &.{ root, semantic_store.format_version, &hex });
    defer allocator.free(directory);
    var dir = std.Io.Dir.cwd().openDir(t.io, directory, .{ .iterate = true }) catch return false;
    defer dir.close(t.io);
    var iterator = dir.iterate();
    while (try iterator.next(t.io)) |item| {
        if (item.kind != .file or std.mem.endsWith(u8, item.name, ".tmp")) continue;
        const path = try std.fs.path.join(allocator, &.{ directory, item.name });
        defer allocator.free(path);
        const file = try std.Io.Dir.cwd().openFile(t.io, path, .{ .mode = .write_only });
        defer file.close(t.io);
        try file.setLength(t.io, 32);
        return true;
    }
    return false;
}

// spec-case: SEMANTIC-CACHE-7
// spec: SEMANTIC-CACHE-11
test "symbolic template direct results reuse while changed templates miss" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const template =
        \\func size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\
    ;
    const program = template ++
        \\func main() -> i64:
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
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\func main() -> i64:
        \\    return size[u8](1u8)
    ;
    const before_unrelated_reuse = cache.reuse.symbolic.statistics.reused;
    try compare(t.allocator, &cache, unrelated, 7);
    try t.expect(cache.reuse.symbolic.statistics.reused > before_unrelated_reuse);
    // Editing the template body invalidates its retained direct result.
    const edited =
        \\func size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 8
        \\
        \\
        \\
    ++
        \\func main() -> i64:
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
        \\func broken[T](value: T) -> i64 effects():
        \\    return value
        \\
        \\
        \\func main() -> i64:
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
        \\func inner[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func outer[T](x: T) -> T:
        \\    return inner[T](x)
        \\
        \\
        \\func main() -> i64:
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
        \\func recur[T](x: T, n: i64) -> i64:
        \\    _ = x
        \\    if n == 0:
        \\        return 0
        \\    return recur[T](x, n - 1)
        \\
        \\
        \\func main() -> i64:
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
        \\func size[const N: u64]() -> u64:
        \\    return N
        \\
        \\
        \\
    ;
    try compare(t.allocator, &cache, size_fn ++
        \\func main() -> i64:
        \\    return i64(size[2]())
    , 2);
    const stored_two = cache.reuse.specializations.statistics.stored;
    try compare(t.allocator, &cache, size_fn ++
        \\func main() -> i64:
        \\    return i64(size[2]())
    , 2);
    try t.expectEqual(stored_two, cache.reuse.specializations.statistics.stored);
    try t.expect(cache.reuse.specializations.statistics.reused > 0);
    try compare(t.allocator, &cache, size_fn ++
        \\func main() -> i64:
        \\    return i64(size[3]())
    , 3);
    // `size[3]` is a distinct positional length descriptor, never a hit on
    // `size[2]`'s retained body.
    try t.expectEqual(stored_two + 1, cache.reuse.specializations.statistics.stored);

    const nominal =
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\func make[T](x: T) -> Box[T]:
        \\    return Box[T](value=x)
        \\
        \\
        \\func main() -> i64:
        \\    mut b = make[i64](3)
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
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "func step{d}(n: i64) -> i64:\n    return n + {d}\n\n", .{ index, index + 1 }));
    }
    try out.appendSlice(allocator, "func main() -> i64:\n    return ");
    index = 0;
    while (index < count) : (index += 1) {
        if (index != 0) try out.appendSlice(allocator, " + ");
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "step{d}(0)", .{index}));
    }
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

// spec-case: SEMANTIC-CACHE-14
test "semantic cache hash index model matches stdlib minimum and allocation" {
    try t.expectEqual(@as(usize, 0), owned_entry.indexCapacityFor(0));
    try t.expectEqual(@as(usize, 8), owned_entry.indexCapacityFor(1));
    try t.expectEqual(@as(usize, 8), owned_entry.indexCapacityFor(6));
    try t.expectEqual(@as(usize, 16), owned_entry.indexCapacityFor(7));
    try t.expectEqual(@as(usize, 16), owned_entry.indexCapacityFor(8));
    try t.expectEqual(@as(usize, 0), owned_entry.hashIndexBytes(0));
    // Capacity eight owns the Header, its one-byte metadatas and two aligned
    // slot arrays; the required 64-bit target total is 224 bytes.
    try t.expectEqual(@as(usize, 224), owned_entry.hashIndexBytes(8));

    // Drive a real stdlib map with these entry counts and compare the model
    // with the FailingAllocator's actual requested backing allocation. Counts 1
    // and 6 stay on the eight-slot minimum; 7 grows the map to sixteen slots; 8
    // is the last count before the next growth step.
    var key_storage: [16][24]u8 = undefined;
    for ([_]usize{ 1, 6, 7, 8 }) |count| {
        var failures = t.FailingAllocator.init(t.allocator, .{});
        var map: std.StringHashMapUnmanaged(usize) = .empty;
        for (0..count) |i| {
            const key = try std.fmt.bufPrint(&key_storage[i], "stable-key-{d}", .{i});
            try map.put(failures.allocator(), key, i);
        }
        const capacity = owned_entry.indexCapacityFor(count);
        try t.expectEqual(capacity, map.capacity());
        try t.expectEqual(owned_entry.hashIndexBytes(capacity), failures.allocated_bytes - failures.freed_bytes);
        map.deinit(failures.allocator());
    }
}

// spec-case: SEMANTIC-CACHE-14
test "semantic cache arena accounting includes chunk bookkeeping" {
    var failures = t.FailingAllocator.init(t.allocator, .{});
    var arena = std.heap.ArenaAllocator.init(failures.allocator());
    defer arena.deinit();
    try t.expectEqual(@as(usize, 0), owned_entry.arenaOwnedBytes(arena));
    _ = try arena.allocator().alloc(u8, 64);
    const owned = owned_entry.arenaOwnedBytes(arena);
    try t.expectEqual(failures.allocated_bytes - failures.freed_bytes, owned);
    try t.expect(owned > arena.queryCapacity());
}

/// Retained cost of a leading ordinary prefix: entry rows, the exact arenas and
/// the exact index backing the standard map allocates for that count.
fn prefixRetainedCost(entries: []const owned_entry.Entry) usize {
    var bytes: usize = 0;
    for (entries) |entry| bytes += owned_entry.entryCost(entry);
    bytes += owned_entry.indexBytesFor(entries.len);
    return bytes;
}

/// Run one cache-only check so callers can attribute every cache-owned
/// allocation without a fresh comparison compilation in the way.
fn checkCachedOnly(allocator: std.mem.Allocator, cache: *Cache, bytes: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "cached.my", bytes);
    defer compilation.deinit();
    try compilation.checkWithCache(cache);
}

const one_body_source = "func main() -> i64:\n    return 1\n";

fn profileHas(profile: *const language.timings.Profile, name: []const u8) bool {
    for (profile.records.phases[0..profile.records.len]) |phase| {
        if (std.mem.eql(u8, phase.name, name)) return true;
    }
    return false;
}

// spec-case: PHASE-TIMING-2
test "semantic cache timing records dependency keys and retention separately" {
    var cache = Cache.init(t.allocator, 1024 * 1024);
    defer cache.deinit();
    var profile = language.timings.Profile.init(t.io, true, .compiler);
    cache.context.timing = &profile;
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expect(profileHas(&profile, "dependency_key_preparation"));
    try t.expect(profileHas(&profile, "retention_store_io"));
    try t.expect(profileHas(&profile, "ordinary_body_replay"));
    try t.expect(profileHas(&profile, "effect_origin_passes"));
    for (profile.records.phases[0..profile.records.len]) |phase| {
        if (std.mem.eql(u8, phase.name, "dependency_key_preparation")) {
            try t.expect(!phase.inclusive);
        }
    }
}

// spec-case: SEMANTIC-CACHE-14
test "shared budget honors the ordinary one-entry hash minimum boundary" {
    // Retain one ordinary snapshot and measure its real owned cost. The
    // exact-at and evicting-below cases transfer or release that same entry, so
    // they do not depend on a fresh arena's chunk growth; the separate fresh
    // cache below checks the below-cost admission path.
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expectEqual(@as(usize, 1), cache.entries.len);
    try t.expectEqual(@as(usize, 8), cache.index.capacity());
    const exact = owned_entry.entryCost(cache.entries[0]) + owned_entry.indexBytesFor(1);

    // A fresh cache below the exact row+arena+minimum-index cost admits nothing,
    // yet the check still succeeds and reports zero retained storage. A fresh
    // entry's arena grows by whether the child allocator can extend a chunk in
    // place, so its cost can differ by a few bytes from the retained entry's
    // with the process's allocation history; the one-byte boundary itself is
    // asserted on the transferred entry below.
    var below = Cache.init(t.allocator, exact - 64);
    defer below.deinit();
    try checkCachedOnly(t.allocator, &below, one_body_source);
    try t.expectEqual(@as(usize, 0), below.entries.len);
    try t.expectEqual(@as(usize, 0), below.statistics.retained_bytes);
    try t.expectEqual(@as(usize, 0), below.index.count());

    // At the exact cost the retained entry transfers with the eight-slot index
    // and the reported bound holds.
    cache.reuse.max_bytes = exact;
    const reused_before = cache.statistics.reused;
    const checked_before = cache.statistics.checked;
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expectEqual(reused_before + 1, cache.statistics.reused);
    try t.expectEqual(checked_before, cache.statistics.checked);
    try t.expectEqual(@as(usize, 1), cache.entries.len);
    try t.expectEqual(exact, cache.statistics.retained_bytes);
    try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);

    // A warm rerun at the retained budget reuses the entry and still holds the
    // bound.
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expectEqual(reused_before + 2, cache.statistics.reused);
    try t.expectEqual(@as(usize, 1), cache.entries.len);
    try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);

    // One byte below the exact cost releases the previous snapshot instead of
    // letting it outlive the bound.
    cache.reuse.max_bytes = exact - 1;
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expectEqual(@as(usize, 0), cache.entries.len);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);
}

// spec-case: SEMANTIC-CACHE-14
test "shared budget covers ordinary hash growth boundaries" {
    const source = try manyFunctionProgram(t.allocator, 8);
    defer t.allocator.free(source);
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, source, 36);
    try t.expectEqual(@as(usize, 9), cache.entries.len);

    // Shrink through the eighth, seventh and sixth prefixes. The seventh entry
    // grows the fresh index from the eight-slot minimum to sixteen slots, and
    // the sixth is the largest count that still holds the minimum, so both
    // sides of the growth boundary are covered without rebuilding arenas.
    for ([_]usize{ 8, 7, 6 }) |target| {
        const budget = prefixRetainedCost(cache.entries[0..target]);
        cache.reuse.max_bytes = budget;
        try compare(t.allocator, &cache, source, 36);
        try t.expectEqual(target, cache.entries.len);
        try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);
        try t.expectEqual(budget, cache.statistics.retained_bytes);

        // Replaying the surviving prefix is warm work and must stay bounded.
        const reused_before = cache.statistics.reused;
        try compare(t.allocator, &cache, source, 36);
        try t.expect(cache.statistics.reused > reused_before);
        try t.expect(cache.statistics.retained_bytes <= cache.reuse.max_bytes);
        try t.expectEqual(target, cache.entries.len);
    }
}

// spec-case: SEMANTIC-CACHE-14
test "shared budget reported bytes equal cache-owned allocations" {
    var failures = t.FailingAllocator.init(t.allocator, .{});
    var cache = Cache.init(failures.allocator(), 4 * 1024 * 1024);
    defer cache.deinit();
    try checkCachedOnly(t.allocator, &cache, one_body_source);
    try t.expectEqual(@as(usize, 1), cache.entries.len);
    // The completed request released every temporary, so the tracker's net
    // allocation is exactly the reported retained storage.
    try t.expectEqual(failures.allocated_bytes - failures.freed_bytes, cache.statistics.retained_bytes);
}

// spec-case: SEMANTIC-CACHE-14
test "shared budget reported bytes equal cache-owned allocations for mixed kinds" {
    var failures = t.FailingAllocator.init(t.allocator, .{});
    var cache = Cache.init(failures.allocator(), 4 * 1024 * 1024);
    defer cache.deinit();
    try checkCachedOnly(t.allocator, &cache, all_kinds_program);
    try t.expect(cache.entries.len > 0);
    try t.expect(cache.reuse.symbolic.entries.items.len > 0);
    try t.expect(cache.reuse.specializations.entries.items.len > 0);
    // Ordinary, symbolic and specialization tables all survive the request, and
    // every session temporary has been released.
    try t.expectEqual(failures.allocated_bytes - failures.freed_bytes, cache.statistics.retained_bytes);
}

// spec: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-7
test "semantic cache retains a bounded prefix of bodies when the snapshot exceeds its budget" {
    const source = try manyFunctionProgram(t.allocator, 8);
    defer t.allocator.free(source);
    var full = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer full.deinit();
    try compare(t.allocator, &full, source, 36);
    try t.expectEqual(@as(usize, 9), full.entries.len);
    // Shrink the budget by exactly the last body's actually owned cost. Every
    // cost is read from this same snapshot, so the leading eight bodies fit and
    // the ninth cannot, independent of allocator chunk-size variation.
    const last_cost = owned_entry.entryCost(full.entries[8]);
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

// spec: SEMANTIC-CACHE-10
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
    \\func helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\func identity[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\func main() -> i64:
    \\    return identity[i64](helper(41))
;

// spec: SEMANTIC-CACHE-13
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

    // Eviction history is cumulative work, not retained storage, so clear
    // zeroes the byte fields without erasing the tally.
    cache.statistics.retention.evicted = 5;
    cache.clear();
    try t.expectEqual(@as(usize, 5), cache.statistics.retention.evicted);
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
    \\func size[const N: u64]() -> u64:
    \\    return N
    \\
    \\
;

fn sizeProgram(allocator: std.mem.Allocator, n: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}func main() -> i64:\n    return i64(size[{d}]())\n", .{ size_template, n });
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
    return (@sizeOf(owned_entry.SpecializationEntry) + owned_entry.specializationArenaBytes(cache.reuse.specializations.entries.items[0])) * 2;
}

// spec: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-12
test "shared retention budget bounds distinct specializations and eviction forces fresh checks" {
    // Measure one retained specialization unit with a generous budget.
    var probe = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer probe.deinit();
    const probe_source = try sizeProgram(t.allocator, 2);
    defer t.allocator.free(probe_source);
    try compare(t.allocator, &probe, probe_source, 2);
    try t.expect(probe.reuse.specializations.entries.items.len >= 1);
    const unit = @sizeOf(owned_entry.SpecializationEntry) + owned_entry.specializationArenaBytes(probe.reuse.specializations.entries.items[0]);
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

// spec-case: SEMANTIC-CACHE-14
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

// spec-case: SEMANTIC-CACHE-14
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

// spec-case: SEMANTIC-CACHE-14
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
        try out.appendSlice(allocator, try std.fmt.bufPrint(&line, "func t{d}[T: integer](value: T) -> i64 effects():\n    _ = value\n    return {d}\n\n", .{ index, index }));
    }
    try out.appendSlice(allocator, "func main() -> i64:\n    return 0\n");
    return out.toOwnedSlice(allocator);
}

// spec-case: SEMANTIC-CACHE-14
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

// spec-case: SEMANTIC-CACHE-14
// spec-case: SEMANTIC-CACHE-11
test "generic publication rolls back cleanly on allocation failure" {
    // Warm the native-build artifacts twice before the failing allocator runs:
    // creating one on first use costs a few allocations, and a baseline run that
    // pays them while a later run does not looks like nondeterministic memory
    // usage to `checkAllAllocationFailures`.
    var steady: Steady = .{ .inner = t.allocator };
    try genericScenario(steady.allocator());
    try genericScenario(steady.allocator());
    try t.checkAllAllocationFailures(steady.allocator(), genericScenario, .{});
}

// spec: CONTRACT-CACHE-2
test "invariant checks retain relocatable bodies including operator positions" {
    const source = "@invariant(self.low <= self.high and -self.low <= 0)\nrecord Span:\n    low: int\n    high: int\n\nfunc make() -> Span:\n    return Span(low=1, high=2)\n\nfunc main() -> int:\n    return make().high\n";
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, source, 2);
    try t.expectEqual(@as(usize, 2), cache.statistics.checked);
    try compare(t.allocator, &cache, "# Move every declaration down one line.\n" ++ source, 2);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 2), cache.statistics.checked);
}

// spec-case: SEMANTIC-CACHE-12
test "callback provider identities retain named labels and mutation positions" {
    const typed = @import("typed.zig");
    const callback_type: typed.Type = @fromBackingInt(typed.Type.record_base);
    const records = [_]typed.Record{.{
        .id = callback_type,
        .name = "mod::Callback",
        .declaration = .{ .start = 0, .end = 0 },
        .fields = &.{},
        .contract = .{ .callback = .{ .parameters = &.{.i64}, .return_type = .unit, .effects = 0, .labels = &.{"amount"} } },
    }};
    var changed = records;
    changed[0].contract.callback.?.mutates = &.{0};
    const original = try semantic_key.providerIdentity(t.allocator, &.{callback_type}, &records);
    defer t.allocator.free(original);
    const mutable = try semantic_key.providerIdentity(t.allocator, &.{callback_type}, &changed);
    defer t.allocator.free(mutable);
    try t.expect(!std.mem.eql(u8, original, mutable));
    changed[0].contract.callback.?.mutates = &.{};
    changed[0].contract.callback.?.labels = &.{"count"};
    const renamed = try semantic_key.providerIdentity(t.allocator, &.{callback_type}, &changed);
    defer t.allocator.free(renamed);
    try t.expect(!std.mem.eql(u8, original, renamed));
}

test "summary callable record identities distinguish return origins and reject shape changes" {
    var unit = try language.Compilation.init(t.allocator, "edited.my", prefix ++ suffix);
    defer unit.deinit();
    try unit.check();
    var cache = Cache.init(t.allocator, 4 << 20);
    defer cache.deinit();
    const callback: checked_typed.Callable = .{ .parameters = &.{}, .return_type = .i64, .effects = 0 };
    var records = [_]checked_typed.Record{
        .{ .id = @fromBackingInt(checked_typed.Type.record_base), .name = "func() -> i64", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .shape = .{ .domain = .u64 }, .contract = .{ .callback = callback } },
        .{ .id = @fromBackingInt(checked_typed.Type.record_base + 1), .name = "func() -> i64", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .shape = .{ .domain = .u64 }, .contract = .{ .callback = callback } },
    };
    records[1].contract.callback.?.return_origin = .fresh;
    const a = unit.arena.allocator();
    var before = try cache.begin(a, unit.src, unit.syntax.?, &records);
    const identity = (try before.recordIdentity(a, 0)).?;
    const other = (try before.recordIdentity(a, 1)).?;
    try t.expect(!std.mem.eql(u8, identity, other));
    try t.expect((try before.shapeOf(records[0].name)) == null);
    const expected = (try before.shapeOf(identity)).?;
    std.mem.swap(checked_typed.Record, &records[0], &records[1]);
    records[0].id = @fromBackingInt(checked_typed.Type.record_base);
    records[1].id = @fromBackingInt(checked_typed.Type.record_base + 1);
    var reordered = try cache.begin(a, unit.src, unit.syntax.?, &records);
    try t.expectEqualSlices(u8, &expected, &(try reordered.shapeOf(identity)).?);
    records[1].contract.callback.?.effects = 1;
    var changed = try cache.begin(a, unit.src, unit.syntax.?, &records);
    try t.expect((try changed.shapeOf(identity)) == null);
}

const DefaultFiles = struct {
    main: []const u8,
    model: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *DefaultFiles = @ptrCast(@alignCast(context.?));
        const bytes = if (std.mem.eql(u8, path, "main.my")) self.main else if (std.mem.eql(u8, path, "model.my")) self.model else return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};

fn compareDefaults(cache: *Cache, files: *DefaultFiles, expected: i64) !void {
    var cached_project = language.project.Project.init(t.allocator);
    defer cached_project.deinit();
    try cached_project.load(.{ .context = files, .read = DefaultFiles.read }, "main", .{});
    var cached_index = try language.interfaces.build(&cached_project);
    var cached = try language.project_compile.Compilation.init(&cached_index);
    try cached.checkWithCache(cache);
    var fresh_project = language.project.Project.init(t.allocator);
    defer fresh_project.deinit();
    try fresh_project.load(.{ .context = files, .read = DefaultFiles.read }, "main", .{});
    var fresh_index = try language.interfaces.build(&fresh_project);
    var fresh = try language.project_compile.Compilation.init(&fresh_index);
    try fresh.check();
    try t.expectEqual(expected, (try native.run(&cached)).value);
    try t.expectEqual(expected, (try native.run(&fresh)).value);
    try t.expectEqual(fresh.diagnostics.items.items.len, cached.diagnostics.items.items.len);
    for (fresh.diagnostics.items.items, cached.diagnostics.items.items) |left, right| {
        const a = try language.diagnostic_output.render(t.allocator, left, fresh.src, .json);
        defer t.allocator.free(a);
        const b = try language.diagnostic_output.render(t.allocator, right, cached.src, .json);
        defer t.allocator.free(b);
        try t.expectEqualStrings(a, b);
    }
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-15
// spec-case: SEMANTIC-CACHE-3
test "imported defaults retain exact source proof across importer edits and invalidate changed defaults" {
    var files: DefaultFiles = .{
        .main = "import model\nfunc helper() -> i64:\n    return 0\n\nfunc main() -> i64:\n    return model.Item().n + helper()\n",
        .model = "public record Item:\n    n: i64 = 42\n",
    };
    var cache = Cache.init(t.allocator, 4 << 20);
    defer cache.deinit();
    try compareDefaults(&cache, &files, 42);
    const checked = cache.statistics.checked;
    try compareDefaults(&cache, &files, 42);
    try t.expectEqual(checked, cache.statistics.checked);
    files.main = "import model\nfunc helper() -> i64:\n    return 1\n\nfunc main() -> i64:\n    return model.Item().n + helper()\n";
    try compareDefaults(&cache, &files, 43);
    try t.expectEqual(checked + 1, cache.statistics.checked);
    files.model = "# moved default\npublic record Item:\n    n: i64 = 43\n";
    try compareDefaults(&cache, &files, 44);
    try t.expect(cache.statistics.checked > checked + 1);
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-15
// spec-case: SEMANTIC-CACHE-3
test "copyEntry parser trailing span proof reuses matched body after another body changes" {
    var files: DefaultFiles = .{
        .main = "import model\nfunc helper() -> i64:\n    return 42\n\nfunc main() -> i64:\n    return model.keep(Some(helper()))\n",
        .model = "public func keep(n: i64?) -> i64:\n    match n:\n        case Some(value):\n            return value\n        case None:\n            return 0\n\n\npublic func unused() -> i64:\n    return 0\n",
    };
    var cache = Cache.init(t.allocator, 4 << 20);
    defer cache.deinit();
    try compareDefaults(&cache, &files, 42);
    var saw_trailing_span = false;
    for (cache.entries) |entry| {
        var refs = @import("semantic_copy.zig").RefSet.init(t.allocator);
        defer refs.deinit();
        refs.sources.enabled = true;
        try refs.collect([]const checked_typed.Node, entry.nodes);
        try refs.collect([]const checked_typed.Statement, entry.statements);
        var spans = refs.sources.items.keyIterator();
        while (spans.next()) |span| {
            if (span.end == entry.meta.identity.region.end + 3) saw_trailing_span = true;
        }
    }
    try t.expect(saw_trailing_span);
    const checked = cache.statistics.checked;
    files.model = "public func keep(n: i64?) -> i64:\n    match n:\n        case Some(value):\n            return value\n        case None:\n            return 0\n\n\npublic func unused() -> i64:\n    return 1\n";
    try compareDefaults(&cache, &files, 42);
    try t.expectEqual(checked + 1, cache.statistics.checked);
    try t.expectEqual(@as(usize, 0), cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.relocation_failed)]);
}

// spec-case: SEMANTIC-CACHE-9
// spec-case: SEMANTIC-CACHE-15
// spec-case: SEMANTIC-CACHE-3
test "source proof rejects renamed ambiguous edited and malformed module provenance" {
    const source = @import("source.zig");
    const provenance = @import("semantic_sources.zig");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = try source.Source.init(a, "model.my", "n=42");
    const main = try source.Source.init(a, "main.my", "get()");
    const original = try source.Source.initMapped(a, &.{ model, main });
    var before = try provenance.Catalog.init(t.allocator, original);
    defer before.deinit();
    var spans: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer spans.deinit(t.allocator);
    try spans.put(t.allocator, .{ .start = 2, .end = 4 }, {});
    const refs = try before.capture(t.allocator, .{ .start = 5, .end = 10 }, &spans);
    defer t.allocator.free(refs);
    try t.expectEqual(@as(usize, 1), refs.len);
    const moved = try source.Source.initMapped(a, &.{ main, model });
    var after = try provenance.Catalog.init(t.allocator, moved);
    defer after.deinit();
    const local: @import("semantic_copy.zig").Segment = .{ .before = .{ .start = 5, .end = 10 }, .after = 0 };
    const mapped = try after.segments(t.allocator, refs, local);
    defer t.allocator.free(mapped);
    try t.expectEqual(@as(usize, 2), mapped.len);
    try t.expectEqual(@as(usize, 6), mapped[0].after);
    const changed = try source.Source.init(a, "model.my", "n=43");
    const renamed = try source.Source.init(a, "other.my", "n=42");
    for ([_]source.Source{
        try source.Source.initMapped(a, &.{ main, changed }),
        try source.Source.initMapped(a, &.{ main, renamed }),
        try source.Source.initMapped(a, &.{ model, main, model }),
    }) |fresh| {
        var catalog = try provenance.Catalog.init(t.allocator, fresh);
        defer catalog.deinit();
        const rejected_segments = try catalog.segments(t.allocator, refs, local);
        defer t.allocator.free(rejected_segments);
        try t.expectEqual(@as(usize, 1), rejected_segments.len);
    }
    var malformed = refs[0];
    malformed.before.end = original.bytes.len + 1;
    try t.expect(!provenance.valid(&.{malformed}, original.bytes.len));
    try t.expect(!provenance.valid(&.{ refs[0], refs[0] }, original.bytes.len));
}

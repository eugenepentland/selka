//! Changed-source cached/fresh agreement includes ownership, diagnostics and interrupted snapshots.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const Cache = language.semantic_cache.Cache;
const prefix = "fn helper(n:i64)->i64{return n+1;}";
const suffix = "fn keep(n:i64)->i64{let unused=1;let mut x=n;x=x+1;return x;}fn main()->i64{return keep(helper(40));}";
fn compare(allocator: std.mem.Allocator, cache: *Cache, bytes: []const u8, expected: ?i64) !void {
    var cached = try language.Compilation.init(allocator, "edited.my", bytes);
    defer cached.deinit();
    var fresh = try language.Compilation.init(allocator, "edited.my", bytes);
    defer fresh.deinit();
    if (expected) |number| {
        try cached.checkWithCache(cache);
        try fresh.check();
        for (fresh.program.?.functions, cached.program.?.functions) |a, b|
            try t.expectEqual(a.policy.effects, b.policy.effects);
        try t.expectEqual(number, (try cached.execute(allocator)).value);
        try t.expectEqual(number, (try fresh.execute(allocator)).value);
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
    try compare(allocator, &cache, "fn helper(n:i64)->i64{\nreturn n+2;\n}" ++ suffix, 43);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expectEqual(@as(usize, 4), cache.statistics.checked);
    try compare(allocator, &cache, "fn helper(n:i64)->i64{return true;}" ++ suffix, null);
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
test "semantic cache falls back for declaration type constant generic and alias changes" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try compare(t.allocator, &cache, prefix ++ suffix, 42);
    try compare(t.allocator, &cache, "fn helper(n:bool)->i64{return 1;}" ++ suffix, null);
    try compare(t.allocator, &cache, "struct Item{n:i64}" ++ prefix ++ suffix, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try compare(t.allocator, &cache, "const N:i64=1;fn main()->i64{return N;}", 1);
    try compare(t.allocator, &cache, "const N:i64=2;fn main()->i64{return N;}", 2);
    try compare(t.allocator, &cache, "fn id<T:copy>(n:T)->T{return n;}fn main()->i64{return id::<i64>(42);}", 42);
    try compare(t.allocator, &cache, "type Number=i64;fn main()->i64{return cast<Number>(42);}", 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expect(cache.statistics.bypassed >= 4);
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
    var interrupted = try language.Compilation.init(t.allocator, "edited.my", "fn helper(n:i64)->i64{return n+2;}" ++ suffix);
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
    const caller = "fn main()->i64{let cb=helper;return cb(40);}";
    try compare(t.allocator, &cache, "fn helper(n:i64)->i64 effects(){return n+1;}" ++ caller, 41);
    try compare(t.allocator, &cache, "fn helper(n:i64)->i64 effects(){return n+2;}" ++ caller, 42);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
}

test "semantic cache bypasses constant length function and nominal specializations" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    const function = "fn size<const N:u64>()->u64{return N;}";
    try compare(t.allocator, &cache, function ++ "fn main()->i64{return cast<i64>(size::<2>());}", 2);
    try compare(t.allocator, &cache, function ++ "fn main()->i64{return cast<i64>(size::<3>());}", 3);
    const nominal = "struct Chunk<const N:u64>{items:[N]i64}";
    try compare(t.allocator, &cache, nominal ++ "fn main()->i64{let x=new Chunk<1>{items:new [1]i64[42]};return x.items[0];}", 42);
    try compare(t.allocator, &cache, nominal ++ "fn main()->i64{let x=new Chunk<2>{items:new [2]i64[43,0]};return x.items[0];}", 43);
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.statistics.stored);
    try t.expectEqual(@as(usize, 4), cache.statistics.bypassed);
}

// spec: SEMANTIC-CACHE-4
test "semantic cache rechecks transitive effects when only a callee body changes" {
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    // Only the callee body changes; the unchanged caller is reused but rechecked.
    // The host declaration is never executed, so this stays a checking-only test.
    const shared = "host fn tick()->i64 effects(host);fn main()->i64 effects(clock){return change();}";
    var first = try language.Compilation.init(t.allocator, "edited.my", shared ++ "fn change()->i64{return 42;}");
    defer first.deinit();
    try first.checkWithCache(&cache);
    var second = try language.Compilation.init(t.allocator, "edited.my", shared ++ "fn change()->i64{return tick();}");
    defer second.deinit();
    try t.expectError(error.SourceError, second.checkWithCache(&cache));
    try t.expectEqualStrings("E_EFFECT_BOUND", second.diagnostics.items[0].code);
    try t.expectEqual(@as(usize, 2), cache.statistics.reused);
    try t.expect(cache.statistics.stored > 0);
}

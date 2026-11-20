//! Ordinary caller hydration preserves generic memo constructor contracts.
const std = @import("std");
const language = @import("compiler.zig");
const t = std.testing;
const Cache = language.semantic_cache.Cache;
const store = @import("semantic_store.zig");
const cache_key = @import("cache_key.zig");
const source =
    \\import hex
    \\import strings
    \\import memo
    \\
    \\func compute(key: memo.Key) -> str[]:
    \\    match key:
    \\        case Number(value=value):
    \\            return ["number-" + str(value)]
    \\        case Text(value=value):
    \\            return ["text-" + value]
    \\        case Data(value=value):
    \\            return ["data-" + hex.encode(value)]
    \\
    \\func exercise() -> bool fails memo.Error:
    \\    mut cache = try memo.create[str[]](2, compute)
    \\    mut key = memo.Key.Text(value="dynamic-" + str(7))
    \\    const first = memo.call(mut cache, key)
    \\    const again = memo.call(mut cache, key)
    \\    if first.reused or not again.reused or first.value != ["text-dynamic-7"]:
    \\        return False
    \\    mut snapshot = copy(cache)
    \\    memo.clear(mut cache)
    \\    key = memo.Key.Number(value=11)
    \\    const number = memo.call(mut cache, key)
    \\    const data = memo.call(mut cache, memo.Key.Data(value=b"abc"))
    \\    const evicted = memo.call(mut cache, memo.Key.Number(value=12))
    \\    const replaced = memo.call(mut cache, key)
    \\    if number.value != ["number-11"] or data.value != ["data-616263"] or evicted.reused or replaced.reused:
    \\        return False
    \\    if memo.count(cache) != 2 or memo.capacity(cache) != 2 or memo.count(snapshot) != 1:
    \\        return False
    \\    memo.clear(mut snapshot)
    \\    if first.value != ["text-dynamic-7"] or again.value != first.value:
    \\        return False
    \\    mut disabled = try memo.create[str[]](0, compute)
    \\    const uncached = memo.call(mut disabled, memo.Key.Number(value=7))
    \\    const repeated = memo.call(mut disabled, memo.Key.Number(value=7))
    \\    return not uncached.reused and not repeated.reused and memo.count(disabled) == 0
    \\
    \\func main() -> int:
    \\    match memo.create[str[]](-1, compute):
    \\        case Ok(_):
    \\            return 1
    \\        case Err(error):
    \\            if strings.char_count(memo.message(error)) == 0:
    \\                return 2
    \\    match exercise():
    \\        case Ok(passed):
    \\            if (passed):
    \\                return (0)
    \\            else:
    \\                return (3)
    \\        case Err(_):
    \\            return 4
;

const Input = struct { text: []const u8 };

fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
    const input: *const Input = @ptrCast(@alignCast(context.?));
    if (input.text.len > limit) return error.TooLarge;
    return allocator.dupe(u8, input.text);
}

fn check(cache: *Cache, text: []const u8) !void {
    var input: Input = .{ .text = text };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &input, .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.checkWithCache(cache);
    try t.expect(compilation.program != null);
}

// spec-case: SEMANTIC-CACHE-3
// spec-case: SEMANTIC-CACHE-7
test "A08 persisted memo caller hydration preserves fresh checking" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const imports = "import hex\nimport strings\nimport memo\n";
    const relocated = imports ++ "func earlier() -> int:\n    return 7\n\n" ++ source[imports.len..];
    const invalid =
        \\import memo
        \\func compute(key: memo.Key) -> int:
        \\    return 7
        \\func main() -> int:
        \\    match memo.create[str[]](-1, compute):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(_):
        \\            return 0
    ;
    for ([_][]const u8{ source, source, relocated, invalid, source }, 0..) |text, run| {
        var storage = store.Store.init(t.allocator, t.io, root, cache_key.Contract.default, language.semantic_cache.mutation_contract_version);
        defer storage.deinit();
        var cache = Cache.init(t.allocator, 4 << 20);
        defer cache.deinit();
        cache.context.persistent = &storage;
        if (run == 3) {
            try t.expectError(error.SourceError, check(&cache, text));
            continue;
        }
        try check(&cache, text);
        if (run != 0) {
            try t.expect(cache.statistics.reused > 0);
            const miss = @backingInt(language.semantic_cache.MissReason.interned_record);
            try t.expect(cache.statistics.rejections.lookup[miss] > 0);
        }
    }
}

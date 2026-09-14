//! Unicode text and ordered dictionary ownership, bounds, and GC contracts.
const std = @import("std");
const gc = @import("gc_heap.zig");
const text = @import("managed_text.zig");
const dict = @import("managed_dict.zig");
const values = @import("runtime_values.zig");
const t = std.testing;
const debug = std.debug.print;
const str_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));
const dict_type: values.Type = @fromBackingInt(@intCast(34));

// spec: PY-TEXT-1
test "PY-TEXT-1 Unicode indexing split join and immutable aliases under GC stress" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const input = try text.create(&heap, str_type, "hé🙂,x,");
    defer input.release(t.allocator);
    try t.expectEqual(@as(usize, 6), try text.len(&heap, input));
    const emoji = try text.at(&heap, input, 2);
    defer emoji.release(t.allocator);
    const encoded = try text.encode(&heap, emoji);
    defer t.allocator.free(encoded);
    try t.expectEqualStrings("🙂", encoded);
    const last = try text.at(&heap, input, -1);
    defer last.release(t.allocator);
    const sep = try text.create(&heap, str_type, ",");
    defer sep.release(t.allocator);
    try t.expect(try text.equal(&heap, last, sep));
    const parts = try text.split(&heap, list_type, input, sep);
    defer parts.release(t.allocator);
    try t.expectEqual(@as(usize, 3), try heap.len(parts));
    const joined = try text.join(&heap, sep, parts);
    defer joined.release(t.allocator);
    try t.expect(try text.equal(&heap, input, joined));
    const doubled = try text.concat(&heap, emoji, emoji);
    defer doubled.release(t.allocator);
    try t.expectEqual(@as(usize, 2), try text.len(&heap, doubled));
    try t.expectEqual(@as(usize, 1), try text.len(&heap, emoji));
    try t.expectError(error.TypeMismatch, heap.append(emoji, .{ .integer = .{ .ty = .u32, .value = 65 } }));
    try t.expectError(error.InvalidUtf8, text.create(&heap, str_type, "\xff"));
    try t.expectError(error.Bounds, text.at(&heap, input, -7));
    try t.expectError(error.Bounds, text.at(&heap, input, std.math.maxInt(u64)));
    const empty = try text.create(&heap, str_type, "");
    defer empty.release(t.allocator);
    try t.expectError(error.EmptySeparator, text.split(&heap, list_type, input, empty));
}

// spec: PY-DICT-1
test "PY-DICT-1 ordered aliases replace equal text keys and preserve snapshots" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const map = try dict.create(&heap, dict_type, str_type, .i64);
    defer map.release(t.allocator);
    const alias = map.retain();
    defer alias.release(t.allocator);
    const one = try text.create(&heap, str_type, "α");
    defer one.release(t.allocator);
    const equivalent = try text.create(&heap, str_type, "α");
    defer equivalent.release(t.allocator);
    const two = try text.create(&heap, str_type, "β");
    defer two.release(t.allocator);
    try dict.write(&heap, map, one, .{ .i64 = 1 });
    try dict.write(&heap, map, two, .{ .i64 = 2 });
    const snapshot = try dict.snapshot(&heap, map, list_type, false);
    defer snapshot.release(t.allocator);
    try dict.write(&heap, alias, equivalent, .{ .i64 = 42 });
    try t.expectEqual(@as(usize, 2), try dict.len(&heap, map));
    try t.expectEqual(@as(i64, 42), (try dict.read(&heap, map, one)).i64);
    try t.expectEqual(@as(i64, 1), (try heap.read(snapshot, 0)).i64);
    const keys = try dict.snapshot(&heap, map, list_type, true);
    defer keys.release(t.allocator);
    const first = try heap.read(keys, 0);
    defer first.release(t.allocator);
    try t.expect(try text.equal(&heap, first, one));
    const missing = try text.create(&heap, str_type, "missing");
    defer missing.release(t.allocator);
    try t.expectError(error.MissingKey, dict.read(&heap, map, missing));
    try t.expectEqual(@as(i64, 9), (try dict.get(&heap, map, missing, .{ .i64 = 9 })).i64);
    try t.expect(!try dict.contains(&heap, map, missing));
    heap.max_capacity = 4;
    try t.expectError(error.CapacityLimit, dict.write(&heap, map, missing, .{ .i64 = 3 }));
    try t.expectEqual(@as(usize, 2), try dict.len(&heap, map));
}

// spec-case: PY-DICT-1
test "PY-DICT-1 dictionary cycles trace values and reclaim unreachable keys" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const map = try dict.create(&heap, dict_type, str_type, dict_type);
    const key = try text.create(&heap, str_type, "self");
    try dict.write(&heap, map, key, map);
    key.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 2), heap.statistics.live_objects);
    map.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
}

fn allocationFailures(allocator: std.mem.Allocator) !void {
    var heap = gc.Heap.init(allocator);
    defer heap.deinit();
    heap.stress = true;
    const map = try dict.create(&heap, dict_type, str_type, str_type);
    defer map.release(allocator);
    const key = try text.create(&heap, str_type, "hé🙂");
    defer key.release(allocator);
    try dict.write(&heap, map, key, key);
    const keys = try dict.snapshot(&heap, map, list_type, true);
    defer keys.release(allocator);
    const point = try text.at(&heap, key, 0);
    defer point.release(allocator);
    try t.expect(try @import("managed_equal.zig").equal(&heap, key, key));
    const joined = try text.join(&heap, key, keys);
    defer joined.release(allocator);
}
// spec-case: PY-DICT-1
test "PY-DICT-1 allocation failure releases partial construction including fromPoints" {
    try t.checkAllAllocationFailures(t.allocator, allocationFailures, .{});
}

test "dictionary InvalidKey and foreign heap values fail before mutation" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const map = try dict.create(&heap, dict_type, .bool, .i64);
    defer map.release(t.allocator);
    try t.expectError(error.InvalidKey, dict.write(&heap, map, .{ .bool = true }, .{ .i64 = 1 }));
    var foreign = gc.Heap.init(t.allocator);
    defer foreign.deinit();
    try t.expectError(error.ForeignMemory, dict.len(&foreign, map));
}

fn runSource(source: []const u8, expected: i64) !void {
    const language = @import("compiler.zig");
    var compilation = try language.Compilation.init(t.allocator, "managed-values.my", source);
    defer compilation.deinit();
    const result = @import("native_execute.zig").run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

test "managed text source literals concat equality Unicode index and length" {
    try runSource(
        \\def main() -> i64:
        \\    value: str = b"hé🙂"
        \\    suffix: str = b"!"
        \\    all = value + suffix
        \\    if all[3] == suffix:
        \\        return len(all)
        \\    return 0
    , 4);
}

test "managed dictionary source literals indexing alias updates get and snapshots" {
    try runSource(
        \\def main() -> i64:
        \\    scores: dict[str, i64] = {b"x": 1}
        \\    alias = scores
        \\    alias[b"x"] = 40
        \\    names = scores.keys()
        \\    key: str = b"x"
        \\    if names[0] == key:
        \\        return scores.get(b"x", 0) + scores.get(b"missing", 2)
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    scores = {1: 40, 2: 2}
        \\    return scores[1] + scores[2]
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"a,b,"
        \\    parts = text.split(b",")
        \\    sep: str = b","
        \\    joined = sep.join(parts)
        \\    if joined == text:
        \\        return len(joined)
        \\    return 0
    , 4);
}

test "managed text convert formats Unicode strings integers booleans and None" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const actual = try text.convert(&heap, str_type, .{ .i64 = -42 }, false, &.{});
    defer actual.release(t.allocator);
    const expected = try text.create(&heap, str_type, "-42");
    defer expected.release(t.allocator);
    try t.expect(try text.equal(&heap, expected, actual));
    const truth = try text.convert(&heap, str_type, .{ .bool = true }, false, &.{});
    defer truth.release(t.allocator);
    const encoded = try text.encode(&heap, truth);
    defer t.allocator.free(encoded);
    try t.expectEqualStrings("True", encoded);
    const absent = try text.convert(&heap, str_type, .unit, false, &.{});
    defer absent.release(t.allocator);
    try t.expectEqual(@as(usize, 4), try text.len(&heap, absent));
}

test "managed str conversion source evaluates argument once" {
    try runSource(
        \\def next(xs: List[i64]) -> i64:
        \\    xs.push(1)
        \\    return 42
        \\
        \\
        \\def main() -> i64:
        \\    xs: List[i64] = []
        \\    s = str(next(xs))
        \\    expected: str = b"42"
        \\    if s == expected:
        \\        return i64(xs.len())
        \\    return 0
    , 1);
}

// spec-case: PY-DICT-1
test "managed equality ignores dictionary insertion order and handles cyclic aliases" {
    const equal = @import("managed_equal.zig");
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const left = try dict.create(&heap, dict_type, .i64, dict_type);
    defer left.release(t.allocator);
    const right = try dict.create(&heap, dict_type, .i64, dict_type);
    defer right.release(t.allocator);
    try dict.write(&heap, left, .{ .i64 = 1 }, left);
    try dict.write(&heap, left, .{ .i64 = 2 }, left);
    try dict.write(&heap, right, .{ .i64 = 2 }, right);
    try dict.write(&heap, right, .{ .i64 = 1 }, right);
    try t.expect(try equal.equal(&heap, left, right));
    try t.expect(try equal.contains(&heap, left, .{ .i64 = 2 }));
    try dict.write(&heap, right, .{ .i64 = 3 }, right);
    try t.expect(!try equal.equal(&heap, left, right));
    const input = try text.create(&heap, str_type, "hé🙂");
    defer input.release(t.allocator);
    const part = try text.create(&heap, str_type, "é🙂");
    defer part.release(t.allocator);
    try t.expect(try equal.contains(&heap, input, part));
    const list = try heap.create(list_type, str_type, 0);
    defer list.release(t.allocator);
    try heap.append(list, input);
    try t.expect(!try equal.contains(&heap, list, part));
    try t.expect(try equal.contains(&heap, list, input));
}

test "managed equality source compares values rather than insertion order" {
    try runSource(
        \\def main() -> i64:
        \\    a = {1: 10, 2: 20}
        \\    b = {2: 20, 1: 10}
        \\    if a == b:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    a: List[i64] = []
        \\    b: List[i64] = []
        \\    a.push(42)
        \\    b.push(42)
        \\    if a == b:
        \\        if a.contains(42):
        \\            return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"hé🙂"
        \\    if text.contains(b"é🙂"):
        \\        return 42
        \\    return 0
    , 42);
}

test "managed equality membership rejects TypeMismatch" {
    const equal = @import("managed_equal.zig");
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    try t.expectError(error.TypeMismatch, equal.contains(&heap, .{ .i64 = 1 }, .{ .i64 = 1 }));
    const list = try heap.create(list_type, .i64, 0);
    defer list.release(t.allocator);
    try t.expectError(error.TypeMismatch, equal.contains(&heap, list, .{ .bool = true }));
}

test "user nominal str declaration preserves its declared fields" {
    try runSource(
        \\class str:
        \\    n: i64
        \\
        \\
        \\def main() -> i64:
        \\    value = str(n=42)
        \\    return value.n
    , 42);
}

test "managed membership source searches list values dictionary keys and text" {
    try runSource(
        \\def main() -> i64:
        \\    values = {1: 10, 2: 20}
        \\    if 2 in values:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.push(42)
        \\    if 42 in values:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"hé🙂"
        \\    part: str = b"é🙂"
        \\    if part in text:
        \\        return 42
        \\    return 0
    , 42);
}

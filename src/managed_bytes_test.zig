//! Managed byte-string ownership, bounds, conversion and GC contracts.
const std = @import("std");
const gc = @import("gc_heap.zig");
const bytes = @import("managed_bytes.zig");
const text = @import("managed_text.zig");
const equality = @import("managed_equal.zig");
const values = @import("runtime_values.zig");
const t = std.testing;
const bytes_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));
const str_type: values.Type = @fromBackingInt(@intCast(34));
const int_list_type: values.Type = @fromBackingInt(@intCast(35));

fn make(heap: *gc.Heap, input: []const u8) !values.Value {
    return bytes.create(heap, bytes_type, input);
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 byte indexing slicing concatenation and membership under GC stress" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const input = try make(&heap, "hello");
    defer input.release(t.allocator);
    try t.expectEqual(@as(usize, 5), try bytes.len(&heap, input));
    try t.expectEqual(@as(i128, 'h'), (try bytes.at(&heap, input, 0)).integer.value);
    try t.expectEqual(@as(i128, 'o'), (try bytes.at(&heap, input, -1)).integer.value);
    try t.expectError(error.Bounds, bytes.at(&heap, input, 5));
    try t.expectError(error.Bounds, bytes.at(&heap, input, -6));
    const tail = try bytes.slice(&heap, input, 1, 100);
    defer tail.release(t.allocator);
    const expected_tail = try make(&heap, "ello");
    defer expected_tail.release(t.allocator);
    try t.expect(try bytes.equal(&heap, tail, expected_tail));
    const reversed = try bytes.slice(&heap, input, 4, 1);
    defer reversed.release(t.allocator);
    try t.expectEqual(@as(usize, 0), try bytes.len(&heap, reversed));
    const negative = try bytes.slice(&heap, input, -2, -1);
    defer negative.release(t.allocator);
    const expected_negative = try make(&heap, "l");
    defer expected_negative.release(t.allocator);
    try t.expect(try bytes.equal(&heap, negative, expected_negative));
    const joined = try bytes.concat(&heap, input, expected_tail);
    defer joined.release(t.allocator);
    try t.expectEqual(@as(usize, 9), try bytes.len(&heap, joined));
    try t.expect(try bytes.contains(&heap, input, .{ .i64 = 'e' }));
    try t.expect(!try bytes.contains(&heap, input, .{ .i64 = 300 }));
    try t.expect(try bytes.contains(&heap, input, expected_tail));
    try t.expect(!try equality.equal(&heap, input, joined));
    try t.expect(try equality.contains(&heap, input, expected_tail));
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 empty byte strings compare equal and reject text or list identities" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const empty = try make(&heap, "");
    defer empty.release(t.allocator);
    const other = try make(&heap, "");
    defer other.release(t.allocator);
    try t.expectEqual(@as(usize, 0), try bytes.len(&heap, empty));
    try t.expect(try bytes.equal(&heap, empty, other));
    const owned = try bytes.toOwned(&heap, empty);
    defer t.allocator.free(owned);
    try t.expectEqualStrings("", owned);
    const unicode = try text.create(&heap, str_type, "hé");
    defer unicode.release(t.allocator);
    try t.expectError(error.TypeMismatch, bytes.len(&heap, unicode));
    try t.expectError(error.TypeMismatch, text.len(&heap, empty));
    try t.expect(!try equality.equal(&heap, empty, unicode));
    var foreign = gc.Heap.init(t.allocator);
    defer foreign.deinit();
    try t.expectError(error.ForeignMemory, bytes.len(&foreign, empty));
    try t.expectError(error.TypeMismatch, heap.append(empty, .{ .integer = .{ .ty = .u8, .value = 1 } }));
}

// spec-case: PY-BYTES-2
test "PY-BYTES-2 list conversion hex and UTF-8 round trips reject out-of-range input" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const items = try heap.create(int_list_type, .i64, 0);
    defer items.release(t.allocator);
    try heap.append(items, .{ .i64 = 0xCE });
    try heap.append(items, .{ .i64 = 0xB1 });
    const built = try bytes.fromList(&heap, bytes_type, items);
    defer built.release(t.allocator);
    try t.expectEqual(@as(usize, 2), try bytes.len(&heap, built));
    const back = try bytes.toList(&heap, int_list_type, built);
    defer back.release(t.allocator);
    try t.expectEqual(@as(i64, 0xCE), (try heap.read(back, 0)).i64);
    try heap.append(items, .{ .i64 = 256 });
    try t.expectError(error.ByteRange, bytes.fromList(&heap, bytes_type, items));
    try heap.append(items, .{ .i64 = -1 });
    try t.expectError(error.ByteRange, bytes.fromList(&heap, bytes_type, items));
    const decoded = try bytes.decode(&heap, str_type, built);
    defer decoded.release(t.allocator);
    try t.expectEqual(@as(usize, 1), try text.len(&heap, decoded));
    const encoded = try bytes.encode(&heap, bytes_type, decoded);
    defer encoded.release(t.allocator);
    try t.expect(try bytes.equal(&heap, encoded, built));
    const digits = try bytes.hex(&heap, str_type, built);
    defer digits.release(t.allocator);
    const printed = try text.encode(&heap, digits);
    defer t.allocator.free(printed);
    try t.expectEqualStrings("ceb1", printed);
    const parsed = try bytes.fromHex(&heap, bytes_type, digits);
    defer parsed.release(t.allocator);
    try t.expect(try bytes.equal(&heap, parsed, built));
}

// spec-case: PY-BYTES-2
test "PY-BYTES-2 invalid UTF-8 and malformed hexadecimal fail without partial values" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const broken = try make(&heap, "\xff\xfe");
    defer broken.release(t.allocator);
    try t.expectError(error.InvalidUtf8, bytes.decode(&heap, str_type, broken));
    const odd = try text.create(&heap, str_type, "abc");
    defer odd.release(t.allocator);
    try t.expectError(error.InvalidHex, bytes.fromHex(&heap, bytes_type, odd));
    const bad = try text.create(&heap, str_type, "zz");
    defer bad.release(t.allocator);
    try t.expectError(error.InvalidHex, bytes.fromHex(&heap, bytes_type, bad));
    const before = heap.statistics.live_objects;
    try heap.collect();
    try t.expect(heap.statistics.live_objects <= before);
}

// spec-case: PY-BYTES-3
test "PY-BYTES-3 split join prefix suffix and search mirror the text operations" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const input = try make(&heap, "a,b,");
    defer input.release(t.allocator);
    const separator = try make(&heap, ",");
    defer separator.release(t.allocator);
    const parts = try bytes.split(&heap, list_type, input, separator);
    defer parts.release(t.allocator);
    try t.expectEqual(@as(usize, 3), try heap.len(parts));
    const rejoined = try bytes.join(&heap, separator, parts);
    defer rejoined.release(t.allocator);
    try t.expect(try bytes.equal(&heap, rejoined, input));
    const empty = try make(&heap, "");
    defer empty.release(t.allocator);
    try t.expectError(error.EmptySeparator, bytes.split(&heap, list_type, input, empty));
    const prefix = try make(&heap, "a,");
    defer prefix.release(t.allocator);
    try t.expect(try bytes.startsWith(&heap, input, prefix));
    try t.expect(!try bytes.endsWith(&heap, input, prefix));
    try t.expect(try bytes.endsWith(&heap, input, separator));
    try t.expectEqual(@as(i64, 1), try bytes.find(&heap, input, separator));
    const absent = try make(&heap, "zzzzzz");
    defer absent.release(t.allocator);
    try t.expectEqual(@as(i64, -1), try bytes.find(&heap, input, absent));
    try t.expectEqual(@as(i64, 0), try bytes.find(&heap, input, empty));
}

// spec-case: PY-BYTES-3
test "PY-BYTES-3 byte strings survive list storage cycles and reclaim unreachable copies" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const holder = try heap.create(list_type, bytes_type, 0);
    const stored = try make(&heap, "payload");
    try heap.append(holder, stored);
    stored.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 2), heap.statistics.live_objects);
    const read = try heap.read(holder, 0);
    defer read.release(t.allocator);
    try t.expectEqual(@as(usize, 7), try bytes.len(&heap, read));
    holder.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
}

fn allocationFailures(allocator: std.mem.Allocator) !void {
    var heap = gc.Heap.init(allocator);
    defer heap.deinit();
    heap.stress = true;
    const input = try bytes.create(&heap, bytes_type, "a,b");
    defer input.release(allocator);
    const separator = try bytes.create(&heap, bytes_type, ",");
    defer separator.release(allocator);
    const parts = try bytes.split(&heap, list_type, input, separator);
    defer parts.release(allocator);
    const rejoined = try bytes.join(&heap, separator, parts);
    defer rejoined.release(allocator);
    const doubled = try bytes.concat(&heap, input, input);
    defer doubled.release(allocator);
    const piece = try bytes.slice(&heap, doubled, 1, 4);
    defer piece.release(allocator);
    const numbers = try bytes.toList(&heap, int_list_type, piece);
    defer numbers.release(allocator);
    const rebuilt = try bytes.fromList(&heap, bytes_type, numbers);
    defer rebuilt.release(allocator);
    const digits = try bytes.hex(&heap, str_type, rebuilt);
    defer digits.release(allocator);
    const parsed = try bytes.fromHex(&heap, bytes_type, digits);
    defer parsed.release(allocator);
    const decoded = try bytes.decode(&heap, str_type, parsed);
    defer decoded.release(allocator);
    const encoded = try bytes.encode(&heap, bytes_type, decoded);
    defer encoded.release(allocator);
}

// spec-case: PY-BYTES-2
test "PY-BYTES-2 allocation failure releases every partially built byte string" {
    try t.checkAllAllocationFailures(t.allocator, allocationFailures, .{});
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 capacity limits reject oversized byte strings before mutation" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const input = try make(&heap, "abcd");
    defer input.release(t.allocator);
    heap.max_capacity = 4;
    try t.expectError(error.CapacityLimit, bytes.concat(&heap, input, input));
    try t.expectEqual(@as(usize, 4), try bytes.len(&heap, input));
    try t.expectError(error.TypeMismatch, bytes.contains(&heap, input, .unit));
    try t.expectError(error.TypeMismatch, equality.contains(&heap, input, .unit));
    try t.expectError(error.InvalidDataValue, heap.validateElement(.{ .capability = .{ .environment_capability = .{ .execution = 0 } } }));
}

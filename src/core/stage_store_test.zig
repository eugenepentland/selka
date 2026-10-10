//! Stage artifact integrity, input identity, and relocation regression tests.
const std = @import("std");
const store = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");
const ir = @import("ir.zig");
const source = @import("mylang").source;
const codec = @import("mylang").persist_codec;

// spec: NEW-CORE-STAGE-CACHE-1
test "stage store loadRecord validates payloads and separates compiler stage and delimited inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    const key = storage.key("first", &.{ "ab", "c" });
    try std.testing.expect(!std.mem.eql(u8, &key, &storage.key("first", &.{ "a", "bc" })));
    try std.testing.expect(!std.mem.eql(u8, &key, &storage.key("second", &.{ "ab", "c" })));
    var other = storage;
    other.identity[0] ^= 1;
    try std.testing.expect(!std.mem.eql(u8, &key, &other.key("first", &.{ "ab", "c" })));
    const Value = struct { body: []const u8, refs: []const ir.Ref, number: f64 };
    try storage.storeValue(key, Value, .{ .body = "checked", .refs = &.{ @fromBackingInt(123), .none }, .number = -0.0 });
    const value = (try storage.loadValue(a, key, Value)).?;
    try std.testing.expectEqualStrings("checked", value.body);
    try std.testing.expectEqual(@as(usize, 123), value.refs[0].index());
    try std.testing.expectEqual(ir.Ref.none, value.refs[1]);
    try std.testing.expectEqual(@as(u64, 1) << 63, @as(u64, @bitCast(value.number)));
    const path = (try storage.artifactPath(a, key)).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    const payload = (try storage.load(a, key)).?;
    var expected: store.Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &expected, .{});
    try std.testing.expectEqualSlices(u8, payload, (try storage.loadExpected(a, key, expected)).?);
    var wrong = expected;
    wrong[0] ^= 1;
    try std.testing.expect((try storage.loadExpected(a, key, wrong)) == null);
    bytes[bytes.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expectEqual(@as(?[]u8, null), try storage.load(a, key));
    try std.testing.expect((try storage.loadExpected(a, key, expected)) == null);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "truncated" });
    try std.testing.expectEqual(@as(?[]u8, null), try storage.load(a, key));
    try std.testing.expect(try storage.save(key, "bad schema"));
    try std.testing.expect((try storage.loadValue(a, key, Value)) == null);
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "stage store unavailable paths lose reuse without refusing a computed result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "stages-packed-v1", .data = "not a directory" });
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, path);
    defer storage.deinit();
    const key = storage.key("stage", &.{});
    try std.testing.expect(!try storage.save(key, "valid result"));
    try std.testing.expect((try storage.load(arena.allocator(), key)) == null);
}

fn fixture(a: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    try module.strings.appendSlice(a, &.{ "unused", "hello", "assertion" });
    var f: ir.Function = .{ .name = "f", .signature = .{ .params = &.{}, .ret = .str }, .span = 9 };
    try f.insts.appendSlice(a, &.{
        .{ .op = .str_const, .ty = .str, .data = 1, .span = 10 },
        .{ .op = .@"unreachable", .ty = .void, .data = @import("flags.zig").assertion_trap | 2, .span = 11 },
    });
    var block: ir.Block = .{};
    try block.insts.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(1) });
    try f.blocks.append(a, block);
    try module.functions.append(a, f);
    return module;
}

// spec: NEW-CORE-STAGE-CACHE-2
test "stage snapshot relocates shifted files and literal pools and restores appendable lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const first = try source.Source.init(a, "a.my", "aaaaaaa");
    const second = try source.Source.init(a, "b.my", "bbbbbbb");
    const before = try source.Source.initMapped(a, &.{ first, second });
    const context = try snapshot.Context.init(a, &module, before);
    const wire = try snapshot.capture(a, context, module.functions.items[0]);
    const old_layout = try snapshot.layout(a, context);
    const old_digest = try snapshot.digest(a, context, module.functions.items[0]);
    var writer = codec.Writer.init(a);
    try writer.write(snapshot.Wire, wire);
    var reader = codec.Reader.init(a, writer.bytes.items);
    const decoded = try reader.read(snapshot.Wire);
    const after = try source.Source.initMapped(a, &.{ try source.Source.init(a, "a.my", "aaaaaaaaaaaaa"), second });
    module.strings = .empty;
    try module.strings.appendSlice(a, &.{ "assertion", "new literal" });
    const current = try snapshot.Context.init(a, &module, after);
    var restored = try snapshot.restore(a, current, decoded);
    try std.testing.expectEqual(@as(u32, 15), restored.span);
    try std.testing.expectEqual(@as(u32, 16), restored.insts.items[0].span);
    try std.testing.expectEqualStrings("hello", module.strings.items[@intCast(restored.insts.items[0].data)]);
    try std.testing.expectEqual(@import("flags.zig").assertion_trap, restored.insts.items[1].data);
    try std.testing.expectEqual(old_layout, try snapshot.layout(a, current));
    try std.testing.expectEqual(old_digest, try snapshot.digest(a, current, restored));
    try std.testing.expectEqual(restored.insts.items.len, restored.insts.capacity);
    try restored.insts.append(a, .{ .op = .iconst, .ty = .i64 });
    try restored.blocks.items[0].insts.append(a, @fromBackingInt(2));
    try std.testing.expectEqual(@as(usize, 3), restored.insts.items.len);
    module.functions.items[0].signature.ret = .i64;
    try std.testing.expect(!std.mem.eql(u8, &old_layout, &try snapshot.layout(a, current)));
}

fn shiftedSnapshot(a: std.mem.Allocator, mapped: bool) !void {
    var module = try fixture(a);
    const before_file = try source.Source.init(a, "body.my", "short\nfunc f:\n    return 1\n");
    const after_file = try source.Source.init(a, "body.my", "a substantially longer literal\nfunc f:\n    return 1\n");
    const prefix = try source.Source.init(a, "prefix.my", "prefix\n");
    const before = if (mapped) try source.Source.initMapped(a, &.{ prefix, before_file }) else before_file;
    const after = if (mapped) try source.Source.initMapped(a, &.{ prefix, after_file }) else after_file;
    module.functions.items[0].span = @intCast(std.mem.indexOf(u8, before.bytes, "func f").?);
    module.functions.items[0].insts.items[0].span = @intCast(std.mem.indexOf(u8, before.bytes, "return 1").?);
    const before_end = if (mapped) before.origins[1].start + before_file.bytes.len else before.bytes.len;
    const after_end = if (mapped) after.origins[1].start + after_file.bytes.len else after.bytes.len;
    module.functions.items[0].insts.items[1].span = @intCast(before_end);
    const old_context = try snapshot.Context.init(a, &module, before);
    const wire = try snapshot.capture(a, old_context, module.functions.items[0]);
    const context = try snapshot.Context.init(a, &module, after);
    const restored = try snapshot.restore(a, context, wire);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, after.bytes, "func f").?)), restored.span);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, after.bytes, "return 1").?)), restored.insts.items[0].span);
    try std.testing.expectEqual(@as(u32, @intCast(after_end)), restored.insts.items[1].span);
    try std.testing.expectEqual(try snapshot.digest(a, old_context, module.functions.items[0]), try snapshot.digest(a, context, restored));
    try std.testing.expectEqual(@as(u32, 0), try snapshot.relocate(context, try snapshot.locate(old_context, 0)));
}

// spec-case: NEW-CORE-STAGE-CACHE-2
test "stage snapshot source coordinates survive earlier same file literal length changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shiftedSnapshot(arena.allocator(), false);
    try shiftedSnapshot(arena.allocator(), true);
}

// spec-case: NEW-CORE-STAGE-CACHE-2
test "stage snapshot rejects invalid source line columns and preserves source less offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const text = try source.Source.init(a, "body.my", "abc\n");
    const context = try snapshot.Context.init(a, &module, text);
    try std.testing.expectEqual(@as(u32, 3), try snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 1, .column = 4 } }));
    try std.testing.expectEqual(@as(u32, 4), try snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 2, .column = 1 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 0, .column = 1 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 3, .column = 1 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 2, .column = 2 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 0, .point = .{ .line = 1, .column = 0 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 1, .point = .{ .line = 1, .column = 1 } }));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(context, .{ .offset = 1 }));
    const absent = try snapshot.Context.init(a, &module, null);
    try std.testing.expectEqual(@as(u32, 100), try snapshot.relocate(absent, try snapshot.locate(absent, 100)));
    try std.testing.expectError(error.InvalidSnapshot, snapshot.relocate(absent, .{ .offset = 0, .point = .{ .line = 1, .column = 1 } }));
    const no_lines: source.Source = .{ .path = "missing.my", .bytes = "abc", .line_starts = &.{} };
    try std.testing.expectError(error.InvalidSnapshot, snapshot.locate(.{ .module = &module, .source = no_lines }, 1));
}

// spec-case: NEW-CORE-STAGE-CACHE-2
test "stage snapshot rejects malformed locations block references and literal indexes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const context = try snapshot.Context.init(a, &module, null);
    const wire = try snapshot.capture(a, context, module.functions.items[0]);
    wire.function.insts[0].data = 999;
    try std.testing.expectError(error.InvalidSnapshot, snapshot.restore(a, context, wire));
    wire.function.insts[0].data = 0;
    wire.function.blocks[0].insts[0] = @fromBackingInt(999);
    try std.testing.expectError(error.InvalidSnapshot, snapshot.restore(a, context, wire));
    wire.function.blocks[0].insts[0] = @fromBackingInt(0);
    wire.locations[0].origin = 99;
    try std.testing.expectError(error.InvalidSnapshot, snapshot.restore(a, context, wire));
}

const Publisher = struct {
    storage: *const store.Store,
    key: store.Digest,
    bytes: []const u8,
    failed: std.atomic.Value(bool) = .init(false),

    fn run(self: *Publisher) void {
        for (0..12) |_| {
            const saved = self.storage.save(self.key, self.bytes) catch false;
            if (!saved) self.failed.store(true, .release);
        }
    }
};

// spec-case: NEW-CORE-STAGE-CACHE-1
test "stage store concurrent publishers expose only complete verified records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    var independent = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer independent.deinit();
    const key = storage.key("concurrent", &.{});
    const first = try a.alloc(u8, 32768);
    const second = try a.alloc(u8, 32768);
    @memset(first, 'a');
    @memset(second, 'b');
    try std.testing.expect(try storage.save(key, first));
    var one: Publisher = .{ .storage = &storage, .key = key, .bytes = first };
    var two: Publisher = .{ .storage = &storage, .key = key, .bytes = second };
    var three: Publisher = .{ .storage = &independent, .key = key, .bytes = second };
    const left = try std.Thread.spawn(.{}, Publisher.run, .{&one});
    const right = std.Thread.spawn(.{}, Publisher.run, .{&two}) catch |err| {
        left.join();
        return err;
    };
    const external = std.Thread.spawn(.{}, Publisher.run, .{&three}) catch |err| {
        left.join();
        right.join();
        return err;
    };
    {
        defer left.join();
        defer right.join();
        defer external.join();
        for (0..24) |_| {
            const loaded = (try storage.load(std.testing.allocator, key)).?;
            defer std.testing.allocator.free(loaded);
            try std.testing.expect(std.mem.eql(u8, loaded, first) or std.mem.eql(u8, loaded, second));
        }
    }
    try std.testing.expect(!one.failed.load(.acquire));
    try std.testing.expect(!two.failed.load(.acquire));
    try std.testing.expect(!three.failed.load(.acquire));
}

// spec: NEW-CORE-STAGE-PACK-1
test "stage store packs preserve live readers latest writes and physical cache loss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var first = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer first.deinit();
    var second = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer second.deinit();
    const left = first.key("packed-left", &.{});
    const right = first.key("packed-right", &.{});
    try std.testing.expect((try second.load(a, left)) == null);
    try std.testing.expect(try first.save(left, "first"));
    try std.testing.expectEqualStrings("first", (try second.load(a, left)).?);
    try std.testing.expect(try second.save(right, "external"));
    try std.testing.expect(try first.save(left, "latest"));
    try std.testing.expectEqualStrings("external", (try first.load(a, right)).?);
    try std.testing.expectEqualStrings("latest", (try second.load(a, left)).?);
    try std.testing.expect(try first.flush());
    try std.testing.expect(try second.flush());
    try std.testing.expectEqualStrings("latest", (try first.load(a, left)).?);
    try std.testing.expectEqualStrings("external", (try second.load(a, right)).?);
    const path = (try first.artifactPath(a, left)).?;
    try std.testing.expect(std.mem.endsWith(u8, path, ".pack"));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.testing.expect((try first.load(a, left)) == null);
    try std.testing.expect((try second.load(a, left)) == null);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store pack reads verify selected blocks without decoding unrelated bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const small = storage.key("packed-small", &.{});
    const large = storage.key("packed-large", &.{});
    const body = try a.alloc(u8, 700 << 10);
    @memset(body, 42);
    try std.testing.expect(try storage.save(small, "metadata"));
    try std.testing.expect(try storage.save(large, body));
    try std.testing.expect(try storage.flush());
    try std.testing.expectEqualStrings("metadata", (try storage.load(a, small)).?);
    const first = storage.statistics();
    try std.testing.expect(first.decoded_bytes < 4096);
    try std.testing.expectEqualStrings("metadata", (try storage.load(a, small)).?);
    try std.testing.expectEqual(first.blocks_decoded, storage.statistics().blocks_decoded);
    const path = (try storage.artifactPath(a, large)).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    bytes[bytes.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expect((try storage.load(a, large)) == null);
    try std.testing.expectEqualStrings("metadata", (try storage.load(a, small)).?);
    // Index damage is rejected even after its metadata was admitted in this Store.
    bytes[100] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expect((try storage.load(a, small)) == null);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store journals recover complete records after torn tails and counters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var first = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer first.deinit();
    const key = first.key("journal-recovery", &.{});
    try std.testing.expect(try first.save(key, "complete"));
    const path = (try first.artifactPath(a, key)).?;
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    const damaged = try std.mem.concat(a, u8, &.{ original, "partial next record" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = damaged });
    const counter = try std.fs.path.join(a, &.{ first.root, "sequence" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = counter, .data = "torn" });
    var recovered = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer recovered.deinit();
    try std.testing.expectEqualStrings("complete", (try recovered.load(a, key)).?);
    try std.testing.expect(try recovered.save(key, "recovered latest"));
    try std.testing.expectEqualStrings("recovered latest", (try first.load(a, key)).?);
    try std.testing.expect(try recovered.flush());
    try std.testing.expectEqualStrings("recovered latest", (try first.load(a, key)).?);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store decode handles compressed output smaller than the history window" {
    const compression = @import("stage_compression.zig");
    const a = std.testing.allocator;
    const payload: [32]u8 = @splat(7);
    const encoded = try compression.encode(a, &payload);
    defer a.free(encoded);
    try std.testing.expectEqual(@as(u8, 1), encoded[0]);
    const decoded = try compression.decode(a, encoded, payload.len);
    defer a.free(decoded);
    try std.testing.expectEqualSlices(u8, &payload, decoded);
    try std.testing.expectError(error.InvalidEncoding, compression.decode(a, encoded, 0));
    try std.testing.expectError(error.InvalidEncoding, compression.decode(a, encoded, std.math.maxInt(usize)));
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store decode rejects malformed and oversized compressed outputs" {
    const compression = @import("stage_compression.zig");
    const a = std.testing.allocator;
    const payload = try a.alloc(u8, 1024);
    defer a.free(payload);
    @memset(payload, 7);
    const encoded = try compression.encode(a, payload);
    defer a.free(encoded);
    try std.testing.expectEqual(@as(u8, 1), encoded[0]);
    const decoded = try compression.decode(a, encoded, payload.len);
    defer a.free(decoded);
    try std.testing.expectEqualSlices(u8, payload, decoded);
    try std.testing.expectError(error.InvalidEncoding, compression.decode(a, encoded, payload.len - 1));
    try std.testing.expectError(error.InvalidEncoding, compression.decode(a, encoded, payload.len + 1));
    const trailing = try std.mem.concat(a, u8, &.{ encoded, "trailing" });
    defer a.free(trailing);
    try std.testing.expectError(error.InvalidEncoding, compression.decode(a, trailing, payload.len));
    for (0..encoded.len) |length| try std.testing.expectError(error.InvalidEncoding, compression.decode(a, encoded[0..length], payload.len));
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store save rotates journals after truncation deletion and foreign replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const key = storage.key("journal-rotation", &.{});
    try std.testing.expect(try storage.save(key, "original"));
    var path = (try storage.artifactPath(a, key)).?;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "truncated" });
    try std.testing.expect(try storage.save(key, "after truncation"));
    try std.testing.expectEqualStrings("after truncation", (try storage.load(a, key)).?);
    path = (try storage.artifactPath(a, key)).?;
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.testing.expect(try storage.save(key, "after deletion"));
    try std.testing.expectEqualStrings("after deletion", (try storage.load(a, key)).?);
    path = (try storage.artifactPath(a, key)).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    bytes[17] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expect((try storage.load(a, key)) == null);
    try std.testing.expect(try storage.save(key, "after foreign header"));
    try std.testing.expect(try storage.flush());
    try std.testing.expectEqualStrings("after foreign header", (try storage.load(a, key)).?);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store fileId scanPack loadBlock publishBytes release ownership on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, packedAllocationFailure, .{std.testing.allocator});
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, store.Store.init(failing.allocator(), std.testing.io, "unused"));
}

fn packedAllocationFailure(a: std.mem.Allocator, backing: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", backing);
    defer backing.free(root);
    var writer = try store.Store.init(a, std.testing.io, root);
    defer writer.deinit();
    const key = writer.key("allocation-failure", &.{});
    const payload = try a.alloc(u8, 1024);
    defer a.free(payload);
    @memset(payload, 33);
    try std.testing.expect(try writer.save(key, payload));
    try std.testing.expect(try writer.flush());
    var reader = try store.Store.init(a, std.testing.io, root);
    defer reader.deinit();
    const loaded = (try reader.load(a, key)).?;
    defer a.free(loaded);
    try std.testing.expectEqualSlices(u8, payload, loaded);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store scanPack bounds valid checksum index counts before allocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    const key = writer.key("bounded-index", &.{});
    try std.testing.expect(try writer.save(key, "small"));
    try std.testing.expect(try writer.flush());
    const path = (try writer.artifactPath(a, key)).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    // A forged fixed-width count with a valid outer checksum must remain a miss.
    std.mem.writeInt(u64, bytes[89..97], std.math.maxInt(u64), .little);
    rehashPackIndex(bytes);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try std.testing.expect((try reader.load(a, key)) == null);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store loadBlock rejects invalid codecs after pack checksum verification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    const key = writer.key("invalid-codec", &.{});
    try std.testing.expect(try writer.save(key, "small"));
    try std.testing.expect(try writer.flush());
    const path = (try writer.artifactPath(a, key)).?;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    const offset: usize = @intCast(std.mem.readInt(u64, bytes[97..105], .little));
    const length = std.mem.readInt(u32, bytes[105..109], .little);
    bytes[offset] = 255;
    std.crypto.hash.Blake3.hash(bytes[offset..][0..length], bytes[113..145], .{});
    rehashPackIndex(bytes);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try std.testing.expect((try reader.load(a, key)) == null);
    try std.testing.expectEqual(@as(u64, 0), reader.statistics().blocks_decoded);
}

fn rehashPackIndex(bytes: []u8) void {
    const length: usize = @intCast(std.mem.readInt(u64, bytes[49..57], .little));
    std.crypto.hash.Blake3.hash(bytes[89..][0..length], bytes[57..89], .{});
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store body blocks bound collateral decoding and count payload cache hits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const payload = try a.alloc(u8, 40 << 10);
    @memset(payload, 17);
    const keys = [_]store.Digest{
        storage.key("body-block-first", &.{}),
        storage.key("body-block-second", &.{}),
        storage.key("body-block-third", &.{}),
    };
    for (keys) |key| try std.testing.expect(try storage.save(key, payload));
    try std.testing.expect(try storage.flush());
    try std.testing.expectEqualSlices(u8, payload, (try storage.load(a, keys[2])).?);
    const first = storage.statistics();
    try std.testing.expect(first.decoded_bytes < 64 << 10);
    try std.testing.expectEqual(@as(u64, payload.len), first.payload_bytes_returned);
    try std.testing.expectEqual(@as(u64, 1), first.blocks_decoded);
    try std.testing.expectEqual(@as(u64, 0), first.block_cache_hits);
    try std.testing.expectEqualSlices(u8, payload, (try storage.load(a, keys[2])).?);
    const second = storage.statistics();
    try std.testing.expectEqual(first.blocks_decoded, second.blocks_decoded);
    try std.testing.expectEqual(@as(u64, 1), second.block_cache_hits);
    try std.testing.expectEqual(@as(u64, payload.len * 2), second.payload_bytes_returned);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store automatically seals bounded journals and fresh readers retain every key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    const payload = try a.alloc(u8, 1 << 20);
    @memset(payload, 7);
    var keys: [4]store.Digest = undefined;
    var journal_path: ?[]const u8 = null;
    for (&keys, 0..) |*key, index| {
        const discriminator: [1]u8 = .{@intCast(index)};
        key.* = storage.key("auto-seal", &.{&discriminator});
        try std.testing.expect(try storage.save(key.*, payload));
        if (index == 0) journal_path = (try storage.artifactPath(a, key.*)).?;
    }
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().openFile(std.testing.io, journal_path.?, .{}));
    const artifact = (try storage.artifactPath(a, keys[3])).?;
    try std.testing.expect(std.mem.endsWith(u8, artifact, ".pack"));
    var fresh = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer fresh.deinit();
    try expectStoredPayloads(&fresh, std.testing.allocator, &keys, payload);
    try std.testing.expect(try storage.save(keys[0], "new value"));
    const replacement = (try fresh.load(std.testing.allocator, keys[0])).?;
    defer std.testing.allocator.free(replacement);
    try std.testing.expectEqualStrings("new value", replacement);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store automatic sealing propagates allocation failure without losing published records" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, autoSealAllocationFailure, .{std.testing.allocator});
}

fn autoSealAllocationFailure(a: std.mem.Allocator, backing: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", backing);
    defer backing.free(root);
    const payload = try backing.alloc(u8, 4 << 20);
    defer backing.free(payload);
    @memset(payload, 7);
    var storage = try store.Store.init(a, std.testing.io, root);
    defer storage.deinit();
    const key = storage.key("auto-seal-allocation-failure", &.{});
    const saved = storage.save(key, payload) catch |err| {
        var recovery = try store.Store.init(backing, std.testing.io, root);
        defer recovery.deinit();
        if (try recovery.load(backing, key)) |published| {
            defer backing.free(published);
            try std.testing.expectEqualSlices(u8, payload, published);
        }
        return err;
    };
    try std.testing.expect(saved);
    const loaded = (try storage.load(a, key)).?;
    defer a.free(loaded);
    try std.testing.expectEqualSlices(u8, payload, loaded);
}

fn expectStoredPayloads(storage: *const store.Store, a: std.mem.Allocator, keys: []const store.Digest, payload: []const u8) !void {
    for (keys) |key| {
        const loaded = (try storage.load(a, key)).?;
        defer a.free(loaded);
        try std.testing.expectEqualSlices(u8, payload, loaded);
    }
}

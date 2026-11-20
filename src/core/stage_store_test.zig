//! Stage artifact integrity, input identity, and relocation regression tests.
const std = @import("std");
const scopes_stage_count = @import("stage_scopes.zig").stage_count;
const store = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");
const ir = @import("ir.zig");
const source = @import("selka").source;
const codec = @import("selka").persist_codec;
const stage_pack = @import("stage_pack.zig");
/// Where a pack file's fields sit, counted from the length of its magic: the index length (u64) and digest (32 bytes) follow the
/// magic and the 32-byte identity, and the index, whose first entry is a block offset (u64), a length (u32) and a digest, follows them.
const index_length_at = stage_pack.pack_magic.len + 32;
const index_digest_at = index_length_at + 8;
const index_at = index_digest_at + 32;
const scopes = @import("stage_scopes.zig");

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
    // "first" is not routed, so its stage is `whole`: changing that stage's digest must move its key.
    other.stages[scopes_stage_count - 1][0] ^= 1;
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

test "stage store saves into its directory once it exists and again after the directory was removed under it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, path);
    defer storage.deinit();
    const first = storage.key("first", &.{});
    const second = storage.key("second", &.{});
    const third = storage.key("third", &.{});
    try std.testing.expect(try storage.save(first, "one"));
    try std.testing.expect(try storage.save(second, "two"));
    try std.Io.Dir.cwd().deleteTree(std.testing.io, try std.fs.path.join(a, &.{ path, "stages-packed-v1" }));
    try std.testing.expect(try storage.save(third, "three"));
    try std.testing.expectEqualStrings("three", (try storage.load(a, third)).?);
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

test "stage snapshots own nested borrowing paths across capture and restore" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const borrowed = try module.borrowedType(a, .str);
    const result = try module.intern(a, .{ .record = &.{ borrowed, .str } });
    const path = try a.dupe(ir.BorrowProjection, &.{.{ .field = 0 }});
    const owner = try a.dupe(ir.BorrowProjection, &.{.{ .field = 1 }});
    const sources = try a.dupe(ir.BorrowSource, &.{.{ .result = owner }});
    module.functions.items[0].signature = .{ .params = &.{.str}, .ret = result, .passing = .{ .owned = 1 }, .borrow = .{ .path = path, .sources = sources } };
    const context = try snapshot.Context.init(a, &module, null);
    const wire = try snapshot.capture(a, context, module.functions.items[0]);
    path[0] = .{ .field = 1 };
    owner[0] = .{ .field = 0 };
    sources[0] = .{ .argument = 0 };
    try std.testing.expect(ir.samePath(&.{.{ .field = 0 }}, wire.function.signature.borrow.path));
    try std.testing.expect(ir.samePath(&.{.{ .field = 1 }}, wire.function.signature.borrow.sources[0].result));
    module.functions.items[0].signature = try wire.function.signature.clone(a);
    const restored = try snapshot.restore(a, context, wire);
    @constCast(wire.function.signature.borrow.path)[0] = .{ .field = 1 };
    @constCast(wire.function.signature.borrow.sources[0].result)[0] = .{ .field = 0 };
    try std.testing.expect(ir.samePath(&.{.{ .field = 0 }}, restored.signature.borrow.path));
    try std.testing.expect(ir.samePath(&.{.{ .field = 1 }}, restored.signature.borrow.sources[0].result));
}

// spec: NEW-CORE-STAGE-CACHE-2
test "stage snapshot relocates shifted files and literal pools and restores appendable lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const first = try source.Source.init(a, "a.selka", "aaaaaaa");
    const second = try source.Source.init(a, "b.selka", "bbbbbbb");
    const before = try source.Source.initMapped(a, &.{ first, second });
    const context = try snapshot.Context.init(a, &module, before);
    const wire = try snapshot.capture(a, context, module.functions.items[0]);
    const old_layout = try snapshot.layout(a, context);
    const old_digest = try snapshot.digest(a, context, module.functions.items[0]);
    var writer = codec.Writer.init(a);
    try writer.write(snapshot.Wire, wire);
    var reader = codec.Reader.init(a, writer.bytes.items);
    const decoded = try reader.read(snapshot.Wire);
    const after = try source.Source.initMapped(a, &.{ try source.Source.init(a, "a.selka", "aaaaaaaaaaaaa"), second });
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
    const before_file = try source.Source.init(a, "body.selka", "short\nfunc f:\n    return 1\n");
    const after_file = try source.Source.init(a, "body.selka", "a substantially longer literal\nfunc f:\n    return 1\n");
    const prefix = try source.Source.init(a, "prefix.selka", "prefix\n");
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
    const text = try source.Source.init(a, "body.selka", "abc\n");
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
    const no_lines: source.Source = .{ .path = "missing.selka", .bytes = "abc", .line_starts = &.{} };
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

/// Two packs of one store: `left` and `middle` in the first, `right` in the second, each with a payload of its own.
fn twoPacks(a: std.mem.Allocator, storage: *const store.Store) ![3]store.Digest {
    const keys = [3]store.Digest{ storage.key("handle-left", &.{}), storage.key("handle-middle", &.{}), storage.key("handle-right", &.{}) };
    try std.testing.expect(try storage.save(keys[0], "left payload"));
    try std.testing.expect(try storage.save(keys[1], "middle payload"));
    try std.testing.expect(try storage.flush());
    try std.testing.expect(try storage.save(keys[2], try a.dupe(u8, "right payload")));
    try std.testing.expect(try storage.flush());
    return keys;
}

test "G3p-r11 handle: loads from a pack share one kept handle per pack, and a pack deleted under the reader reads as absent and drops its handle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const keys = try twoPacks(a, &storage);
    try std.testing.expectEqual(@as(usize, 0), storage.storage.openPacks());
    try std.testing.expectEqualStrings("left payload", (try storage.load(a, keys[0])).?);
    try std.testing.expectEqualStrings("middle payload", (try storage.load(a, keys[1])).?);
    try std.testing.expectEqualStrings("right payload", (try storage.load(a, keys[2])).?);
    try std.testing.expectEqualStrings("left payload", (try storage.load(a, keys[0])).?);
    try std.testing.expectEqual(@as(usize, 2), storage.storage.openPacks());
    // The pack of `right` is deleted while its handle is open: the name no longer reaches a file, so the record is a miss.
    try std.Io.Dir.cwd().deleteFile(std.testing.io, (try storage.artifactPath(a, keys[2])).?);
    try std.testing.expect((try storage.load(a, keys[2])) == null);
    try std.testing.expectEqual(@as(usize, 1), storage.storage.openPacks());
    try std.testing.expectEqualStrings("middle payload", (try storage.load(a, keys[1])).?);
}

test "G3p-r11 handle: a pack replaced or rewritten under the reader is opened again by name, and damage is a miss as it was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const keys = try twoPacks(a, &storage);
    try std.testing.expectEqualStrings("right payload", (try storage.load(a, keys[2])).?);
    const path = (try storage.artifactPath(a, keys[2])).?;
    const id = storage.storage.catalog.entries.get(keys[2]).?.file;
    const before = storage.storage.catalog.files.items[id].handle.?.stat.inode;
    // The same bytes under the same name in another file (another inode): the kept handle is not served for a file the name no longer reaches.
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.copy", .{path}), .data = bytes });
    try std.Io.Dir.cwd().rename(try std.fmt.allocPrint(a, "{s}.copy", .{path}), std.Io.Dir.cwd(), path, std.testing.io);
    try std.testing.expectEqualStrings("right payload", (try storage.load(a, keys[2])).?);
    try std.testing.expect(storage.storage.catalog.files.items[id].handle.?.stat.inode != before);
    // The pack is truncated in place under the open handle: the name reaches the same file with other contents, which fail their checks.
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "truncated" });
    try std.testing.expect((try storage.load(a, keys[2])) == null);
    try std.testing.expectEqualStrings("left payload", (try storage.load(a, keys[0])).?);
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

test "a record of a pack block damaged on disk is never served to a store that has not read the block, whatever the record's own checksum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    const small = writer.key("packed-small", &.{});
    const large = writer.key("packed-large", &.{});
    const body = try a.alloc(u8, 700 << 10);
    @memset(body, 42);
    try std.testing.expect(try writer.save(small, "metadata"));
    try std.testing.expect(try writer.save(large, body));
    try std.testing.expect(try writer.flush());
    const path = (try writer.artifactPath(a, large)).?;
    const clean = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    // Damage inside the small record's payload: the block's checksum no longer holds, though the record header and its checksum field do.
    const damaged = try a.dupe(u8, clean);
    damaged[std.mem.indexOf(u8, damaged, "metadata").? + 2] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = damaged });
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try std.testing.expect((try reader.load(a, small)) == null);
    try std.testing.expectEqualSlices(u8, body, (try reader.load(a, large)).?);
    // Damage in the middle of the large record's payload, the small block undamaged.
    const second = try a.dupe(u8, clean);
    second[second.len / 2] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = second });
    var again = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer again.deinit();
    try std.testing.expectEqualStrings("metadata", (try again.load(a, small)).?);
    try std.testing.expect((try again.load(a, large)) == null);
    // A block verified when it was read is served from the cache without hashing its records again: the second read costs no decode.
    const decoded = again.statistics().blocks_decoded;
    try std.testing.expectEqualStrings("metadata", (try again.load(a, small)).?);
    try std.testing.expectEqual(decoded, again.statistics().blocks_decoded);
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
    const counter = try std.fs.path.join(a, &.{ first.storage.config.root, "sequence" });
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
    const encoded = try compression.encodeWithPolicy(a, &payload, .zlib);
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
    const encoded = try compression.encodeWithPolicy(a, payload, .zlib);
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
test "stage store fileId readIndex refresh readRawBlock cacheBlock loadBlock publishBytes release ownership on allocation failure" {
    // Growing a block in place succeeds or fails with the testing allocator's layout, which earlier failing runs leave different, so
    // the allocations a run makes would vary between runs: the backing never resizes or remaps.
    var fixed: FixedBlocks = .{ .backing = std.testing.allocator };
    try std.testing.checkAllAllocationFailures(fixed.allocator(), packedAllocationFailure, .{std.testing.allocator});
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
    std.mem.writeInt(u64, bytes[index_at..][0..8], std.math.maxInt(u64), .little);
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
    const offset: usize = @intCast(std.mem.readInt(u64, bytes[index_at + 8 ..][0..8], .little));
    const length = std.mem.readInt(u32, bytes[index_at + 16 ..][0..4], .little);
    bytes[offset] = 255;
    std.crypto.hash.Blake3.hash(bytes[offset..][0..length], bytes[index_at + 24 ..][0..32], .{});
    rehashPackIndex(bytes);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try std.testing.expect((try reader.load(a, key)) == null);
    try std.testing.expectEqual(@as(u64, 0), reader.statistics().blocks_decoded);
}

fn rehashPackIndex(bytes: []u8) void {
    const length: usize = @intCast(std.mem.readInt(u64, bytes[index_length_at..][0..8], .little));
    std.crypto.hash.Blake3.hash(bytes[index_at..][0..length], bytes[index_digest_at..][0..32], .{});
}

// spec: NEW-CORE-STAGE-PACK-2
test "stage store filename indexing keeps bounded lookup work across many packs and external updates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    // This test counts one pack per saved key, so the writer must not merge them.
    var keys: [48]store.Digest = undefined;
    for (&keys, 0..) |*key, index| {
        const discriminator: [1]u8 = .{@intCast(index)};
        key.* = writer.key("indexed-filename", &.{&discriminator});
        try std.testing.expect(try writer.save(key.*, &discriminator));
        try std.testing.expect(try writer.flush());
    }
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try expectIndexedPayloads(&reader, a, &keys);
    const before = reader.statistics().publication;
    try std.testing.expectEqual(@as(u64, keys.len), before.filename_lookups);
    try std.testing.expect(try writer.save(keys[0], "newer"));
    try std.testing.expectEqualStrings("newer", (try reader.load(a, keys[0])).?);
    const after = reader.statistics().publication;
    try std.testing.expectEqual(@as(u64, keys.len + 1), after.filename_lookups - before.filename_lookups);
    const lost = (try reader.artifactPath(a, keys[1])).?;
    try std.Io.Dir.cwd().deleteFile(std.testing.io, lost);
    try std.testing.expect((try reader.load(a, keys[1])) == null);
    try std.testing.expectEqualStrings("newer", (try reader.load(a, keys[0])).?);
}

fn expectIndexedPayloads(reader: *store.Store, a: std.mem.Allocator, keys: []const store.Digest) !void {
    for (keys, 0..) |key, index| {
        const expected: [1]u8 = .{@intCast(index)};
        try std.testing.expectEqualSlices(u8, &expected, (try reader.load(a, key)).?);
    }
}

const FlushAction = union(enum) {
    publish: struct { writer: *store.Store, key: store.Digest },
    mutate: struct { path: []const u8, replace: bool },

    fn run(self: FlushAction, backing: std.mem.Allocator) !void {
        switch (self) {
            .publish => |input| try std.testing.expect(try input.writer.save(input.key, "newer")),
            .mutate => |input| {
                const io = std.testing.io;
                const dir = std.Io.Dir.cwd();
                const before = try dir.statFile(io, input.path, .{});
                const bytes = try dir.readFileAlloc(io, input.path, backing, .limited(1 << 20));
                defer backing.free(bytes);
                if (input.replace) {
                    var file = try dir.createFileAtomic(io, input.path, .{ .replace = true });
                    defer file.deinit(io);
                    try file.file.writeStreamingAll(io, bytes);
                    try file.replace(io);
                } else try dir.writeFile(io, .{ .sub_path = input.path, .data = bytes });
                try dir.setTimestamps(io, input.path, .{ .modify_timestamp = .{ .new = before.mtime } });
            },
        }
    }
};

const FlushProbe = struct {
    parent: std.mem.Allocator,
    sequence_path: []const u8,
    action: FlushAction,
    owner: ?*store.Store = null,
    state: struct { armed: bool = false, checks: usize = 0, blocked: bool = false, acted: bool = false, failed: bool = false } = .{},

    fn check(self: *FlushProbe) void {
        const lock = std.Io.Dir.cwd().createFile(std.testing.io, self.sequence_path, .{
            .read = true,
            .truncate = false,
            .lock = .exclusive,
            .lock_nonblocking = true,
        }) catch |err| {
            if (err == error.WouldBlock) self.state.blocked = true else self.state.failed = true;
            self.state.armed = false;
            return;
        };
        lock.close(std.testing.io);
        self.state.checks += 1;
        if (!self.state.acted) {
            self.state.acted = true;
            self.action.run(self.parent) catch {
                self.state.failed = true;
            };
        }
    }

    fn allocator(self: *FlushProbe) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *FlushProbe = @ptrCast(@alignCast(context));
        // Probe all large preparation allocations, including compressor storage; stop at staging completion.
        if (self.state.armed and len >= 16 << 10 and self.owner.?.storage.cached.statistics.publication.packs_prepared == 0) self.check();
        return self.parent.rawAlloc(len, alignment, ra);
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *FlushProbe = @ptrCast(@alignCast(context));
        self.parent.rawFree(bytes, alignment, ra);
    }
};

// spec-case: NEW-CORE-STAGE-PACK-2
test "stage store pack preparation releases sequence lock and independent newer publication wins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var independent = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer independent.deinit();
    const key = independent.key("prepare-unlocked", &.{});
    var probe: FlushProbe = .{
        .parent = std.testing.allocator,
        .sequence_path = try std.fs.path.join(a, &.{ independent.storage.config.root, "sequence" }),
        .action = .{ .publish = .{ .writer = &independent, .key = key } },
    };
    var storage = try store.Store.init(probe.allocator(), std.testing.io, root);
    defer storage.deinit();
    probe.owner = &storage;
    const payload = try a.alloc(u8, 256 << 10);
    @memset(payload, 37);
    try std.testing.expect(try storage.save(key, payload));
    probe.state.armed = true;
    try std.testing.expect(try storage.flush());
    probe.state.armed = false;
    try std.testing.expect(!probe.state.blocked and !probe.state.failed);
    try std.testing.expect(probe.state.acted and probe.state.checks >= 2);
    try std.testing.expectEqualStrings("newer", (try storage.load(a, key)).?);
    var fresh = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer fresh.deinit();
    try std.testing.expectEqualStrings("newer", (try fresh.load(a, key)).?);
    try std.testing.expectEqual(@as(u64, 1), storage.statistics().publication.packs_prepared);
}

// spec-case: NEW-CORE-STAGE-PACK-2
test "stage store unlocked preparation rejects restored bytes and atomic source replacement before commit" {
    for ([_]bool{ false, true }) |replace| try sourceMutationDuringPrepare(std.testing.allocator, replace);
}

fn sourceMutationDuringPrepare(backing: std.mem.Allocator, replace: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const packed_root = try std.fs.path.join(a, &.{ root, "stages-packed-v1" });
    var probe: FlushProbe = .{
        .parent = backing,
        .sequence_path = try std.fs.path.join(a, &.{ packed_root, "sequence" }),
        .action = .{ .mutate = .{ .path = "", .replace = replace } },
    };
    var storage = try store.Store.init(probe.allocator(), std.testing.io, root);
    defer storage.deinit();
    probe.owner = &storage;
    const key = storage.key("prepare-source-mutation", &.{});
    const payload = try a.alloc(u8, 256 << 10);
    @memset(payload, 19);
    try std.testing.expect(try storage.save(key, payload));
    const journal_path = (try storage.artifactPath(a, key)).?;
    probe.action.mutate.path = journal_path;
    const before = try std.Io.Dir.cwd().statFile(std.testing.io, journal_path, .{});
    probe.state.armed = true;
    const sealed = try storage.flush();
    probe.state.armed = false;
    try std.testing.expect(!sealed and probe.state.acted and !probe.state.failed and !probe.state.blocked);
    const after = try std.Io.Dir.cwd().statFile(std.testing.io, journal_path, .{});
    try std.testing.expectEqual(before.mtime.nanoseconds, after.mtime.nanoseconds);
    try std.testing.expect(if (replace) before.inode != after.inode else before.ctime.nanoseconds != after.ctime.nanoseconds);
    try std.testing.expectEqualStrings(journal_path, (try storage.artifactPath(a, key)).?);
    try std.testing.expectEqualSlices(u8, payload, (try storage.load(a, key)).?);
    // A clean retry may seal the surviving journal; rejection must not discard durable records.
    try std.testing.expect(try storage.flush());
    var fresh = try store.Store.init(backing, std.testing.io, root);
    defer fresh.deinit();
    try std.testing.expectEqualSlices(u8, payload, (try fresh.load(a, key)).?);
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

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store raw policy persists and fresh compressed readers preserve mixed mode keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var raw = try store.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .compression = .none });
    defer raw.deinit();
    const payload: [1024]u8 = @splat(7);
    const key = raw.key("policy", &.{});
    try std.testing.expect(try raw.save(key, &payload));
    try std.testing.expect(try raw.flush());
    const pack = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, (try raw.artifactPath(a, key)).?, a, .unlimited);
    const offset = std.mem.readInt(u64, pack[index_at + 8 ..][0..8], .little);
    try std.testing.expectEqual(@as(u8, 0), pack[@intCast(offset)]);
    var compressed = try store.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .compression = .zlib });
    defer compressed.deinit();
    try std.testing.expectEqual(key, compressed.key("policy", &.{}));
    try expectStoredPayloads(&compressed, std.testing.allocator, &.{key}, &payload);
    const other = compressed.key("compressed-policy", &.{});
    try std.testing.expect(try compressed.save(other, &payload));
    try std.testing.expect(try compressed.flush());
    const encoded = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, (try compressed.artifactPath(a, other)).?, a, .unlimited);
    const encoded_offset = std.mem.readInt(u64, encoded[index_at + 8 ..][0..8], .little);
    try std.testing.expectEqual(@as(u8, 1), encoded[@intCast(encoded_offset)]);
    try expectStoredPayloads(&raw, std.testing.allocator, &.{other}, &payload);
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store compression policy rejects invalid settings and defaults to none" {
    const compression = @import("stage_compression.zig");
    const policy = compression.Policy;
    try std.testing.expectEqual(policy.none, try policy.parse(null));
    try std.testing.expectEqual(policy.none, compression.default_policy);
    try std.testing.expectEqual(policy.none, (store.Options{}).compression);
    try std.testing.expectEqual(policy.zlib, try policy.parse("zlib"));
    try std.testing.expectEqual(policy.none, try policy.parse("none"));
    try std.testing.expectError(error.InvalidCompression, policy.parse(""));
    try std.testing.expectError(error.InvalidCompression, policy.parse("gzip"));
}

/// The encoding prefix (0 raw, 1 zlib) of the block that holds `key`'s record in its pack.
fn blockPrefix(storage: *const store.Store, a: std.mem.Allocator, key: store.Digest) !u8 {
    const pack = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, (try storage.artifactPath(a, key)).?, a, .unlimited);
    const offset = std.mem.readInt(u64, pack[index_at + 8 ..][0..8], .little);
    return pack[@intCast(offset)];
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "stage store defaults to raw blocks and still reads zlib blocks written before the switch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const payload: [1024]u8 = @splat(7);
    var written_zlib = try store.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .compression = .zlib });
    defer written_zlib.deinit();
    const old_key = written_zlib.key("written-as-zlib", &.{});
    try std.testing.expect(try written_zlib.save(old_key, &payload));
    try std.testing.expect(try written_zlib.flush());
    try std.testing.expectEqual(@as(u8, 1), try blockPrefix(&written_zlib, a, old_key));
    var current = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer current.deinit();
    try std.testing.expectEqual(old_key, current.key("written-as-zlib", &.{}));
    try expectStoredPayloads(&current, std.testing.allocator, &.{old_key}, &payload);
    const new_key = current.key("written-by-default", &.{});
    try std.testing.expect(try current.save(new_key, &payload));
    try std.testing.expect(try current.flush());
    try std.testing.expectEqual(@as(u8, 0), try blockPrefix(&current, a, new_key));
    try expectStoredPayloads(&written_zlib, std.testing.allocator, &.{new_key}, &payload);
}

/// The `.pack` files directly under `root`.
fn countPacks(root: []const u8) !usize {
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, root, .{ .iterate = true });
    defer directory.close(std.testing.io);
    var iterator = directory.iterate();
    var packs: usize = 0;
    while (try iterator.next(std.testing.io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".pack")) packs += 1;
    }
    return packs;
}

/// A store key and a payload that differ with `index`, so a merge that swaps or loses one shows.
fn mergeKey(storage: *const store.Store, index: usize) store.Digest {
    const discriminator: [1]u8 = .{@intCast(index)};
    return storage.key("compaction", &.{&discriminator});
}

fn mergePayload(buffer: []u8, index: usize, generation: u8) []const u8 {
    @memset(buffer, @intCast(index));
    buffer[0] = generation;
    return buffer;
}

/// Save and seal `count` values, one pack each, as one process per value would.
fn sealValues(storage: *store.Store, first: usize, count: usize, generation: u8) !void {
    var payload: [300]u8 = undefined;
    for (first..first + count) |index| {
        try std.testing.expect(try storage.save(mergeKey(storage, index), mergePayload(&payload, index, generation)));
        try std.testing.expect(try storage.flush());
    }
}

fn expectValues(storage: *store.Store, a: std.mem.Allocator, first: usize, count: usize, generation: u8) !void {
    var payload: [300]u8 = undefined;
    for (first..first + count) |index| {
        const loaded = (try storage.load(a, mergeKey(storage, index))) orelse return error.TestExpectedEqual;
        try std.testing.expectEqualSlices(u8, mergePayload(&payload, index, generation), loaded);
    }
}

test "stage store block cache serves a repeated read of a block from its slot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const key = storage.key("slot-reuse", &.{});
    const payload = try a.alloc(u8, 4096);
    @memset(payload, 9);
    try std.testing.expect(try storage.save(key, payload));
    try std.testing.expect(try storage.flush());
    try std.testing.expectEqualSlices(u8, payload, (try storage.load(a, key)).?);
    const first = storage.statistics();
    try std.testing.expectEqualSlices(u8, payload, (try storage.load(a, key)).?);
    const second = storage.statistics();
    try std.testing.expectEqual(first.blocks_decoded, second.blocks_decoded);
    try std.testing.expectEqual(first.block_cache_hits + 1, second.block_cache_hits);
}

// A build reads far more blocks than the cache's slots (about 40 here), so a second
// pass over the same records must decode nothing: every block it needs is still cached.
test "stage store block cache keeps every block of a build so a second pass decodes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try writeCacheProbe(std.testing.allocator, root, a, 160);
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try readCacheProbe(&reader, a, 160);
    const first = reader.statistics();
    try readCacheProbe(&reader, a, 160);
    const second = reader.statistics();
    try std.testing.expect(first.blocks_decoded > 32);
    try std.testing.expectEqual(first.blocks_decoded, second.blocks_decoded);
}

fn cacheProbeKey(storage: *const store.Store, index: usize) store.Digest {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, index, .little);
    return storage.key("block-cache-probe", &.{&buffer});
}

fn writeCacheProbe(backing: std.mem.Allocator, root: []const u8, a: std.mem.Allocator, count: usize) !void {
    var writer = try store.Store.init(backing, std.testing.io, root);
    defer writer.deinit();
    const payload = try a.alloc(u8, 64 << 10);
    @memset(payload, 7);
    var index: usize = 0;
    while (index < count) : (index += 1) try std.testing.expect(try writer.save(cacheProbeKey(&writer, index), payload));
    try std.testing.expect(try writer.flush());
}

fn readCacheProbe(storage: *const store.Store, a: std.mem.Allocator, count: usize) !void {
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const bytes = (try storage.load(a, cacheProbeKey(storage, index))).?;
        try std.testing.expectEqual(@as(usize, 64 << 10), bytes.len);
    }
}

test "a batch of records is published whole: each loads, a later record of a key wins, and a reopened store reads them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    const first_key: [32]u8 = @splat(1);
    const second_key: [32]u8 = @splat(2);
    const saves = [_]store.Save{
        .{ .key = first_key, .payload = "one" },
        .{ .key = second_key, .payload = "two" },
        .{ .key = first_key, .payload = "again" },
    };
    try std.testing.expect(try storage.saveAll(&saves));
    try std.testing.expectEqual(@as(u64, 3), storage.statistics().publication.records_saved);
    try std.testing.expectEqualStrings("again", (try storage.load(a, first_key)).?);
    try std.testing.expectEqualStrings("two", (try storage.load(a, second_key)).?);
    try std.testing.expect(try storage.contains(second_key));
    try std.testing.expect(!(try storage.contains(@splat(3))));
    storage.deinit();
    var reopened = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reopened.deinit();
    try std.testing.expectEqualStrings("again", (try reopened.load(a, first_key)).?);
    try std.testing.expectEqualStrings("two", (try reopened.load(a, second_key)).?);
}

/// The rank map of the keys `storage` holds at indices `first..first+count`: each key's rank is its index in that range.
fn rankRange(storage: *const store.Store, a: std.mem.Allocator, ranks: *stage_pack.Ranks, first: usize, count: usize) !void {
    for (first..first + count, 0..) |index, rank| try ranks.put(a, stage_pack.rankKey(mergeKey(storage, index)), rank);
}

test "compaction keeps every live record readable, drops the dead ones, and a dropped key is a miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 20, 1);
    try sealValues(&writer, 20, 20, 1);
    var ranks: stage_pack.Ranks = .empty;
    try rankRange(&writer, a, &ranks, 0, 10);
    const measured = (try writer.storage.compactLive(&ranks, stage_pack.default_band_bytes)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(measured.after.live_bytes == measured.before.live_bytes);
    try std.testing.expect(measured.after.pack_bytes < measured.before.pack_bytes);
    try expectValues(&writer, a, 0, 10, 1);
    try expectMissing(&writer, a, 10, 30);
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try expectValues(&reader, a, 0, 10, 1);
    try expectMissing(&reader, a, 10, 30);
}

test "a pack a reader holds open through compaction still reads its bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 20, 1);
    const pack_path = (try writer.artifactPath(a, mergeKey(&writer, 0))) orelse return error.TestUnexpectedResult;
    var held = try std.Io.Dir.cwd().openFile(std.testing.io, pack_path, .{});
    defer held.close(std.testing.io);
    const before = try a.alloc(u8, @intCast((try held.stat(std.testing.io)).size));
    try std.testing.expectEqual(before.len, try held.readPositionalAll(std.testing.io, before, 0));
    var ranks: stage_pack.Ranks = .empty;
    try rankRange(&writer, a, &ranks, 0, 5);
    _ = (try writer.storage.compactLive(&ranks, stage_pack.default_band_bytes)) orelse return error.TestUnexpectedResult;
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, pack_path, .{}));
    const after = try a.alloc(u8, before.len);
    try std.testing.expectEqual(after.len, try held.readPositionalAll(std.testing.io, after, 0));
    try std.testing.expectEqualSlices(u8, before, after);
}

test "compaction with no live roots removes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 10, 1);
    const packed_root = try std.fs.path.join(a, &.{ root, "stages-packed-v1" });
    const packs_before = try countPacks(packed_root);
    var ranks: stage_pack.Ranks = .empty;
    try std.testing.expectEqual(@as(?stage_pack.Compaction, null), try writer.storage.compactLive(&ranks, stage_pack.default_band_bytes));
    try expectValues(&writer, a, 0, 10, 1);
    try std.testing.expectEqual(packs_before, try countPacks(packed_root));
}

/// Every record at indices `first..first+count` reads as absent: a dropped record is a miss, never an error.
fn expectMissing(storage: *const store.Store, a: std.mem.Allocator, first: usize, count: usize) !void {
    for (first..first + count) |index| try std.testing.expectEqual(@as(?[]u8, null), try storage.load(a, mergeKey(storage, index)));
}

/// Rank every third value of a store of 30 values, in reverse of the order they were written. Fills `ranks`, and `ordered`
/// with the keys in rank order.
fn rankEveryThird(storage: *const store.Store, a: std.mem.Allocator, ranks: *stage_pack.Ranks, ordered: *[10]store.Digest) !void {
    for (0..10) |rank| {
        const index = 27 - rank * 3;
        try ranks.put(a, stage_pack.rankKey(mergeKey(storage, index)), rank);
        ordered[rank] = mergeKey(storage, index);
    }
}

/// The keys of `keys` must sit in `storage` in this order across packs: a later pack, or within a pack a later block or offset.
fn expectPackOrder(storage: *const store.Store, keys: []const store.Digest) !void {
    for (keys[0 .. keys.len - 1], keys[1..]) |left, right| {
        const first = storage.storage.catalog.entries.getContext(left, .{}).?;
        const second = storage.storage.catalog.entries.getContext(right, .{}).?;
        const same_pack = first.file == second.file;
        try std.testing.expect(first.file < second.file or (same_pack and (first.record.block < second.record.block or (first.record.block == second.record.block and first.record.offset < second.record.offset))));
    }
}

/// Every key of `keys` reads as a record.
fn expectLoaded(storage: *const store.Store, a: std.mem.Allocator, keys: []const store.Digest) !void {
    for (keys) |key| try std.testing.expect((try storage.load(a, key)) != null);
}

/// Write the keys of `keys` as records whose payloads fall in size, so sorting by size would reverse their order.
fn saveDescending(storage: *store.Store, a: std.mem.Allocator, keys: *[12]store.Digest) !void {
    for (keys, 0..) |*key, index| {
        key.* = storage.key("journal-order", &.{&[_]u8{@intCast(index)}});
        const payload = try a.alloc(u8, (12 - index) * 300);
        @memset(payload, @intCast(index));
        try std.testing.expect(try storage.save(key.*, payload));
    }
}

/// Write six small and six large records, interleaved, so each size class has its own order to keep.
fn saveClasses(storage: *store.Store, a: std.mem.Allocator, small: *[6]store.Digest, large: *[6]store.Digest) !void {
    for (0..6) |index| {
        const small_parts = [_][]const u8{ "small", &[_]u8{@intCast(index)} };
        const large_parts = [_][]const u8{ "large", &[_]u8{@intCast(index)} };
        small[index] = storage.key("journal-class", &small_parts);
        large[index] = storage.key("journal-class", &large_parts);
        try std.testing.expect(try storage.save(small[index], try a.alloc(u8, 300)));
        try std.testing.expect(try storage.save(large[index], try a.alloc(u8, 5000)));
    }
}

/// The keys of `keys` must sit in `storage` in this order: each lies in a block no earlier than the one before, and at a later
/// offset when it shares that block. A build's records written or compacted in order therefore share their blocks.
fn expectStoreOrder(storage: *const store.Store, keys: []const store.Digest) !void {
    for (keys[0 .. keys.len - 1], keys[1..]) |left, right| {
        const first = storage.storage.catalog.entries.get(left).?.record;
        const second = storage.storage.catalog.entries.get(right).?.record;
        try std.testing.expect(first.block < second.block or (first.block == second.block and first.offset < second.offset));
    }
}

test "compaction writes live records in rank order, so one build's records share blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 30, 1);
    // Live records are every third value, and they are ranked in reverse of the order they were written.
    var ranks: stage_pack.Ranks = .empty;
    var ordered: [10]store.Digest = undefined;
    try rankEveryThird(&writer, a, &ranks, &ordered);
    _ = (try writer.storage.compactLive(&ranks, stage_pack.default_band_bytes)) orelse return error.TestUnexpectedResult;
    try expectStoreOrder(&writer, &ordered);
    try expectLoaded(&writer, a, &ordered);
}

test "a sealed journal keeps each size class in the order it wrote it, so its blocks fill" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    var small: [6]store.Digest = undefined;
    var large: [6]store.Digest = undefined;
    try saveClasses(&writer, a, &small, &large);
    try std.testing.expect(try writer.flush());
    try expectStoreOrder(&writer, &small);
    try expectStoreOrder(&writer, &large);
}

test "a sealed journal keeps a build's writes in the order it wrote them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    // Payload sizes fall, so sorting by size would reverse the order the records were written in.
    var keys: [12]store.Digest = undefined;
    try saveDescending(&writer, a, &keys);
    try std.testing.expect(try writer.flush());
    try expectStoreOrder(&writer, &keys);
}

test "compaction in many small bands keeps every live record, and the bands keep rank order across packs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try sealValues(&writer, 0, 30, 1);
    var ranks: stage_pack.Ranks = .empty;
    var ordered: [10]store.Digest = undefined;
    try rankEveryThird(&writer, a, &ranks, &ordered);
    const compacted = (try writer.storage.compactLive(&ranks, 1500)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(compacted.passes > 1);
    try expectPackOrder(&writer, &ordered);
    try expectLoaded(&writer, a, &ordered);
    // Compacting again with the same roots keeps the same live records in the same number of bands.
    const again = (try writer.storage.compactLive(&ranks, 1500)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(compacted.after.live_bytes, again.after.live_bytes);
    try std.testing.expectEqual(compacted.passes, again.passes);
    try expectPackOrder(&writer, &ordered);
}

// spec: NEW-CORE-STAGE-CACHE-1
test "an observing stage store counts loads and saves under the scope of each key, and a silent one counts nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var observing = try store.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .observe = true });
    defer observing.deinit();
    const saved = observing.key("final", &.{"stored"});
    const absent = observing.key("final", &.{"absent"});
    _ = try observing.save(saved, "payload");
    try std.testing.expectEqualStrings("payload", (try observing.load(a, saved)).?);
    try std.testing.expect((try observing.load(a, absent)) == null);
    const counts = try observing.tallies(a);
    try std.testing.expectEqual(@as(usize, 1), counts.len);
    try std.testing.expectEqualStrings("final", counts[0].scope);
    try std.testing.expectEqual(@as(u64, 1), counts[0].hits);
    try std.testing.expectEqual(@as(u64, 1), counts[0].misses);
    try std.testing.expectEqual(@as(u64, 1), counts[0].saves);
    var silent = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer silent.deinit();
    _ = try silent.load(a, saved);
    try std.testing.expectEqual(@as(usize, 0), (try silent.tallies(a)).len);
}

// spec: NEW-CORE-STAGE-CATALOG-1
test "a reopened stage store finds every record a previous store saved, through its catalog" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    const first = writer.key("final", &.{"one"});
    const second = writer.key("final", &.{"two"});
    _ = try writer.save(first, "alpha");
    _ = try writer.save(second, "beta");
    try std.testing.expect(try writer.flush());
    writer.deinit();
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    try std.testing.expect(try reader.contains(first));
    try std.testing.expect(try reader.contains(second));
    try std.testing.expectEqualStrings("alpha", (try reader.load(a, first)).?);
    try std.testing.expectEqualStrings("beta", (try reader.load(a, second)).?);
    try std.testing.expect((try reader.load(a, writer.key("final", &.{"three"}))) == null);
}

// spec: NEW-CORE-STAGE-CACHE-1
test "a stage key hashes the same byte stream whether its input fits the stack buffer or not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    const identity = &storage.stages[@as(usize, @backingInt(scopes.stageOf("first")))];
    const large = try a.alloc(u8, 3000);
    @memset(large, 'x');
    const digest_part: [32]u8 = @splat(7);
    const small_parts: []const []const u8 = &.{ "ab", "c", &digest_part };
    const large_parts: []const []const u8 = &.{ "ab", large, "c" };
    try std.testing.expectEqual(referenceKey(identity, "first", small_parts), storage.key("first", small_parts));
    try std.testing.expectEqual(referenceKey(identity, "first", large_parts), storage.key("first", large_parts));
    try std.testing.expectEqual(referenceKey(identity, "first", &.{}), storage.key("first", &.{}));
}

/// The incremental form of `Store.key`: a hasher fed each length-delimited field in turn.
fn referenceKey(identity: *const store.Digest, scope: []const u8, parts: []const []const u8) store.Digest {
    const unit_cache = @import("unit_cache.zig");
    var hash = @import("fast_blake3.zig").Blake3.init(.{});
    unit_cache.field(&hash, "selka-stage-v2\n");
    unit_cache.field(&hash, identity);
    unit_cache.field(&hash, scope);
    for (parts) |part| unit_cache.field(&hash, part);
    var digest: store.Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// An allocator that forwards to `backing` but never resizes or remaps a block in place, so every growth is an allocation, a copy and a free.
const FixedBlocks = struct {
    backing: std.mem.Allocator,

    fn allocator(self: *FixedBlocks) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(context: *anyopaque, length: usize, alignment: std.mem.Alignment, address: usize) ?[*]u8 {
        const self: *FixedBlocks = @ptrCast(@alignCast(context));
        return self.backing.rawAlloc(length, alignment, address);
    }

    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, address: usize) void {
        const self: *FixedBlocks = @ptrCast(@alignCast(context));
        self.backing.rawFree(memory, alignment, address);
    }
};

// spec: NEW-CORE-STAGE-PACK-1
test "a store opened before any publication finds what another store publishes later, through its kept handle on the counter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var reader = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer reader.deinit();
    const first = reader.key("counter-handle", &.{"first"});
    const second = reader.key("counter-handle", &.{"second"});
    // No counter exists yet: the load scans nothing and misses.
    try std.testing.expect((try reader.load(a, first)) == null);
    var writer = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer writer.deinit();
    try std.testing.expect(try writer.save(first, "published once"));
    try std.testing.expect(try writer.flush());
    try std.testing.expectEqualStrings("published once", (try reader.load(a, first)).?);
    // The counter is open now; a second publication moves it in place and the reader sees it.
    try std.testing.expect(try writer.save(second, "published twice"));
    try std.testing.expect(try writer.flush());
    try std.testing.expectEqualStrings("published twice", (try reader.load(a, second)).?);
}

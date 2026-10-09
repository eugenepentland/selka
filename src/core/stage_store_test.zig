//! Stage artifact integrity, input identity, and relocation regression tests.
const std = @import("std");
const store = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");
const ir = @import("ir.zig");
const source = @import("mylang").source;
const codec = @import("mylang").persist_codec;

// spec: NEW-CORE-STAGE-CACHE-1
test "stage store validates payloads and separates compiler stage and delimited inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
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
    const path = try std.fmt.allocPrint(a, "{s}/{s}.stage", .{ storage.root, std.fmt.bytesToHex(key, .lower) });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    bytes[bytes.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expectEqual(@as(?[]u8, null), try storage.load(a, key));
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "stages-v1", .data = "not a directory" });
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
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const key = storage.key("concurrent", &.{});
    const first = try a.alloc(u8, 32768);
    const second = try a.alloc(u8, 32768);
    @memset(first, 'a');
    @memset(second, 'b');
    try std.testing.expect(try storage.save(key, first));
    var one: Publisher = .{ .storage = &storage, .key = key, .bytes = first };
    var two: Publisher = .{ .storage = &storage, .key = key, .bytes = second };
    const left = try std.Thread.spawn(.{}, Publisher.run, .{&one});
    const right = std.Thread.spawn(.{}, Publisher.run, .{&two}) catch |err| {
        left.join();
        return err;
    };
    {
        defer left.join();
        defer right.join();
        for (0..24) |_| {
            const loaded = (try storage.load(std.testing.allocator, key)).?;
            defer std.testing.allocator.free(loaded);
            try std.testing.expect(std.mem.eql(u8, loaded, first) or std.mem.eql(u8, loaded, second));
        }
    }
    try std.testing.expect(!one.failed.load(.acquire));
    try std.testing.expect(!two.failed.load(.acquire));
}

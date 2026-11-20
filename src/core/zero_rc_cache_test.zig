//! Owned recursive-copy identities bind logical types independently of catalog order.
const std = @import("std");
const ir = @import("ir.zig");
const emitter = @import("emit_llvm.zig");
fn location(_: *const anyopaque, offset: u32) emitter.Location {
    return .{ .path = "cache-modes.selka", .line = 1, .column = offset + 1 };
}
fn copyKey(a: std.mem.Allocator, shifted: bool, inner: ir.Type) ![32]u8 {
    var module: ir.Module = .{};
    if (shifted) _ = try module.intern(a, .{ .array = .{ .elem = .u8, .n = 5 } });
    const ty = try module.intern(a, .{ .box = inner });
    const name = try @import("test_support.zig").fixtureName(a, @import("emit_values.zig").copy_prefix, ty);
    const helper = try @import("test_builder.zig").helper(a, &module, name, &.{ty}, ty);
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
    return canon.callee(helper);
}
// spec: NEW-CORE-ZERO-RC-CACHE-1
test "zero RC generated copy identities follow type structure across catalog shifts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try copyKey(a, false, .i64);
    try std.testing.expectEqual(original, try copyKey(a, true, .i64));
    try std.testing.expect(!std.mem.eql(u8, &original, &try copyKey(a, true, .str)));
}

// spec: NEW-CORE-ZERO-RC-CACHE-1
// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "canonical digests see a helper declared after prepare" {
    // `view_materialize` can declare `myl_core_view_copy_bytes` while lowering
    // finishes, after a caller prepared its canonical form; the digest memo must
    // grow to cover the new function and compound rather than index past it
    // (B1 follow-up: the release test run panicked at canonical_ir.callee).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "first", .signature = .{ .params = &.{}, .ret = .i64, .linkage = .internal } });
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
    try module.functions.append(a, .{ .name = "late_helper", .signature = .{ .params = &.{}, .ret = .i64, .linkage = .runtime_c } });
    const late_compound = try module.intern(a, .{ .array = .{ .elem = .i64, .n = 2 } });
    const helper_digest = try canon.callee(1);
    const type_digest = try canon.typeDigest(late_compound);
    const zero: [32]u8 = @splat(0);
    try std.testing.expect(!std.mem.eql(u8, &helper_digest, &zero));
    try std.testing.expect(!std.mem.eql(u8, &type_digest, &zero));
    // A second call reuses the grown memo and answers the same digest.
    try std.testing.expectEqual(helper_digest, try canon.callee(1));
}

fn borrowingKey(a: std.mem.Allocator, module: *const ir.Module, contract: ir.BorrowContract) ![32]u8 {
    return signatureKey(a, module, .{ .params = &.{ .str, .str }, .ret = .str, .borrow = contract });
}

fn signatureKey(a: std.mem.Allocator, module: *const ir.Module, signature: ir.Signature) ![32]u8 {
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, module, .{ .context = &context, .locate = location });
    var hash = @import("fast_blake3.zig").Blake3.init(.{});
    try canon.signature(&hash, signature);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

test "canonical borrowing contracts hash projection tags and every nested source by value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const module: ir.Module = .{};
    const original: ir.BorrowContract = .{ .path = &.{.{ .payload = 1 }}, .sources = &.{ .{ .argument = 0 }, .{ .result = &.{ .{ .field = 2 }, .{ .payload = 1 } } } } };
    const digest = try borrowingKey(a, &module, original);
    try std.testing.expectEqual(digest, try borrowingKey(a, &module, try original.clone(a)));
    try std.testing.expect(!std.mem.eql(u8, &digest, &try borrowingKey(a, &module, .{ .path = &.{.{ .field = 1 }}, .sources = original.sources })));
    try std.testing.expect(!std.mem.eql(u8, &digest, &try borrowingKey(a, &module, .{ .path = original.path, .sources = &.{ .{ .argument = 1 }, original.sources[1] } })));
    try std.testing.expect(!std.mem.eql(u8, &digest, &try borrowingKey(a, &module, .{ .path = original.path, .sources = &.{ original.sources[0], .{ .result = &.{ .{ .field = 2 }, .{ .payload = 0 } } } } })));
}

test "canonical borrowed overlays retain identity while sharing owned storage layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const borrowed = try module.borrowedType(a, .str);
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
    try std.testing.expectEqual(module.size(.str), module.size(borrowed));
    try std.testing.expect(!module.managed(borrowed));
    try std.testing.expect(!std.mem.eql(u8, &try canon.typeDigest(.str), &try canon.typeDigest(borrowed)));
}

test "canonical passing metadata retains every position above the compact mask" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const params = try a.alloc(ir.Type, 70);
    @memset(params, .str);
    const owned = try a.dupe(u32, &.{65});
    const consumes = try a.dupe(u32, &.{67});
    const views = try a.dupe(u32, &.{69});
    const signature: ir.Signature = .{ .params = params, .ret = .str, .passing = .{ .owned = 1, .consumes = 2, .views = 4, .extra_owned = owned, .extra_consumes = consumes, .extra_views = views } };
    const retained = try signature.clone(a);
    const pointer = try module.intern(a, .{ .@"fn" = signature });
    const digest = try signatureKey(a, &module, signature);
    try std.testing.expectEqual(digest, try signatureKey(a, &module, retained));
    for ([_]ir.ParameterPassing{
        .{ .owned = 1, .consumes = 2, .views = 4, .extra_owned = &.{64}, .extra_consumes = consumes, .extra_views = views },
        .{ .owned = 1, .consumes = 2, .views = 4, .extra_owned = owned, .extra_consumes = &.{66}, .extra_views = views },
        .{ .owned = 1, .consumes = 2, .views = 4, .extra_owned = owned, .extra_consumes = consumes, .extra_views = &.{68} },
    }) |passing| {
        const changed: ir.Signature = .{ .params = params, .ret = .str, .passing = passing };
        try std.testing.expect(!std.mem.eql(u8, &digest, &try signatureKey(a, &module, changed)));
        const other = try module.intern(a, .{ .@"fn" = changed });
        const context: u8 = 0;
        var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
        try std.testing.expect(!std.mem.eql(u8, &try canon.typeDigest(pointer), &try canon.typeDigest(other)));
    }
    owned[0] = 64;
    consumes[0] = 66;
    views[0] = 68;
    try std.testing.expect(retained.passing.ownedAt(65) and retained.passing.consumesAt(67) and retained.passing.viewAt(69));
    try std.testing.expect(module.compound(pointer).@"fn".passing.eql(retained.passing));
}

test "effect result projections preserve owned arguments above the compact mask" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const params = try a.alloc(ir.Type, 70);
    @memset(params, .str);
    const result = try module.intern(a, .{ .record = &.{ .bool, .str, .str } });
    const signature: ir.Signature = .{ .params = params, .ret = result, .passing = .{ .owned = 1 << 3, .extra_owned = &.{69} } };
    const effects = @import("effects.zig");
    try std.testing.expectEqual(@as(?effects.Final, .{ .field = 1 }), effects.finalOf(&module, signature, 3));
    try std.testing.expectEqual(@as(?effects.Final, .{ .field = 2 }), effects.finalOf(&module, signature, 69));
    try std.testing.expectEqual(@as(?u32, 0), effects.declaredBool(&module, signature));
    try std.testing.expectEqual(@as(?effects.Final, .whole), effects.finalOf(&module, .{ .params = params, .ret = .str, .passing = .{ .extra_owned = &.{69} } }, 69));
}

test "O4 carrier take opcode and field survive canonical hashing and durable snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const record = try module.intern(a, .{ .record = &.{ .str, .str } });
    var builder: @import("test_builder.zig").Builder = .{
        .arena = a,
        .function = .{ .name = "take_field", .signature = .{ .params = &.{record}, .ret = .str, .passing = .{ .owned = 1 } } },
    };
    const block = try builder.block();
    const carrier = try builder.detached(.{ .op = .param, .ty = record });
    const selected = try builder.put(block, .{ .op = .record_take, .ty = .str, .a = carrier, .data = 1, .span = 7 });
    _ = try builder.put(block, .{ .op = .ret, .ty = .void, .a = selected, .span = 9 });
    try module.functions.append(a, builder.function);
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
    const digest = try canon.functionDigest(0);
    module.functions.items[0].insts.items[selected.index()].data = 0;
    try std.testing.expect(!std.mem.eql(u8, &digest, &try canon.functionDigest(0)));
    module.functions.items[0].insts.items[selected.index()].data = 1;
    module.functions.items[0].insts.items[selected.index()].op = .record_get;
    try std.testing.expect(!std.mem.eql(u8, &digest, &try canon.functionDigest(0)));
    module.functions.items[0].insts.items[selected.index()].op = .record_take;
    const snapshot = @import("ir_snapshot.zig");
    const codec = @import("selka").persist_codec;
    const saved = try snapshot.digest(a, .{ .module = &module }, module.functions.items[0]);
    const wire = try snapshot.capture(a, .{ .module = &module }, module.functions.items[0]);
    var writer = codec.Writer.init(a);
    try writer.write(snapshot.Wire, wire);
    var reader = codec.Reader.init(a, writer.bytes.items);
    const decoded = try reader.read(snapshot.Wire);
    try std.testing.expect(reader.done());
    const restored = try snapshot.restore(a, .{ .module = &module }, decoded);
    try std.testing.expectEqual(ir.Op.record_take, restored.insts.items[selected.index()].op);
    try std.testing.expectEqual(@as(u64, 1), restored.insts.items[selected.index()].data);
    try std.testing.expectEqual(carrier, restored.insts.items[selected.index()].a);
    try std.testing.expectEqual(ir.Ref.none, restored.insts.items[selected.index()].b);
    try std.testing.expectEqual(saved, try snapshot.digest(a, .{ .module = &module }, restored));
    module.functions.items[0] = restored;
    try std.testing.expectEqual(digest, try canon.functionDigest(0));
}

//! QBE-FRAMEMAP-1: the fast protocol's IL shape and the twin constant the
//! compiler and the native-build module share.
const std = @import("std");
const language = @import("compiler.zig");
const qbe = @import("qbe.zig");
const frame_map = @import("qbe_frame_map.zig");

const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { functions: []Unit };

fn named(manifest: Manifest, name: []const u8) ?Unit {
    for (manifest.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return unit;
    return null;
}

const recursive =
    \\def leaf(x: i64) -> i64:
    \\    return x + 1
    \\
    \\
    \\def rec(n: i64) -> i64:
    \\    if n <= 0:
    \\        return leaf(n)
    \\    return rec(n - 1) + 1
    \\
    \\
    \\def main() -> i64:
    \\    return rec(3)
;

// spec: QBE-FRAMEMAP-1
test "the fast protocol links no frame record and positions every call instead" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my", recursive);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, .{ .step_checks = false, .frame_checks = false });
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const rec = named(parsed.value, "rec").?;
    // No record, no metadata store, no link through `ctx->active_frame`, and no
    // position slot: the trace comes from return addresses.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, rec.il, "%position"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, rec.il, "_meta"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, rec.il, "%ctx, 48"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, rec.il, "alloc8 32"));
    // The unit names its file, and each call carries its instruction's position.
    try std.testing.expect(frame_map.usesFrameMap(rec.il));
    const header = try std.fmt.allocPrint(a, "dbgfile \"{s}\"\n", .{rec.symbol});
    defer a.free(header);
    try std.testing.expect(std.mem.startsWith(u8, rec.il, header));
    try std.testing.expect(std.mem.count(u8, rec.il, " dbgloc ") >= std.mem.count(u8, rec.il, "call $"));
    // The floor guard stays, and its failure call carries the guard column.
    try std.testing.expect(std.mem.indexOf(u8, rec.il, " dbgloc 1, 1\n call $myl_qbe_fail_frame(l %ctx)") != null);
    // A leaf makes no call, so it carries no position at all.
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, named(parsed.value, "leaf").?.il, "dbgloc"));
}

// spec-case: QBE-FRAMEMAP-1
test "an accounted build keeps the linked frame record and no call positions" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my", recursive);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, .{ .step_checks = false });
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    const rec = named(parsed.value, "rec").?.il;
    try std.testing.expect(std.mem.indexOf(u8, rec, "_meta, %v") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, rec, "dbgloc"));
    try std.testing.expect(!frame_map.usesFrameMap(rec));
}

// spec-case: QBE-FRAMEMAP-1
test "an unchecked fast build carries no call positions, as it links no record" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my", recursive);
    defer c.deinit();
    const manifest = try c.emitQbeWithOptions(a, .{ .step_checks = false, .frame_checks = false, .checks = false });
    defer a.free(manifest);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, manifest, "dbgloc"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, manifest, "dbgfile"));
}

// spec-case: QBE-FRAMEMAP-ASM-1
test "the compiler and the native build agree on the entry guard's column" {
    try std.testing.expectEqual(frame_map.guard_column, qbe.frame_map_guard_column);
}

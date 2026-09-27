//! Linkage is optional only after complete physical publication refusal.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const frame = @import("qbe_rc_frame.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Point:
    \\    x: int
    \\    y: int
    \\record Holder:
    \\    points: list[Point]
    \\def advance(points: mut list[Point], index: int) -> int:
    \\    old = points[index]
    \\    points[index].x = old.x + 1
    \\    return len(points)
    \\def rebind(points: mut list[Point]) -> int:
    \\    points = [Point(1, 2)]
    \\    points[0].x = 5
    \\    return len(points)
    \\def region(points: mut list[Point]) -> int:
    \\    with arena():
    \\        points[0].x = 7
    \\    return len(points)
    \\def callback(points: mut list[Point]) -> int:
    \\    return advance(mut points, 0)
    \\def managed(points: mut list[Point]) -> list[Point]:
    \\    points[0].x = 17
    \\    return points
    \\def referenced(holder: mut Holder):
    \\    holder.points[0].x = 11
    \\def pattern(points: mut list[Point], candidate: Option[list[int]]) -> int:
    \\    points[0].x = 19
    \\    if candidate is not None:
    \\        return len(candidate)
    \\    return len(points)
    \\def iterator(points: mut list[Point]) -> int:
    \\    points[0].x = 23
    \\    total = 0
    \\    for point in points:
    \\        total += point.x
    \\    return total
    \\def resource(points: mut list[Point], file: TextFile) -> int:
    \\    points[0].x = 29
    \\    return len(points)
    \\def main() -> int:
    \\    points = [Point(1, 2)]
    \\    return advance(mut points, 0)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_empty_frame.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: RC-EMPTY-FRAME-1
test "RC empty frame preserves private storage admission and all uncertain frames" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "advance");
    try t.expect(!contains(il, "myl_qbe_rc_frame_enter"));
    try t.expect(!contains(il, "myl_qbe_rc_frame_cleanup"));
    try t.expect(!contains(il, "myl_qbe_rc_frame_leave"));
    try t.expect(contains(il, "%rcentries =l alloc8 128"));
    try t.expect(contains(il, "%rcguards =l alloc8 32"));
    try t.expect(contains(il, "myl_qbe_fail_frame"));
    try t.expect(contains(il, "myl_qbe_fail_normalized_index_bounds"));
    try t.expect(contains(try named(manifest.value, "rebind"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "region"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "callback"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "managed"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "referenced"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "pattern"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "iterator"), "myl_qbe_rc_frame_enter"));
    try t.expect(contains(try named(manifest.value, "resource"), "myl_qbe_rc_frame_enter"));
}

const RefusalEmitter = struct {
    cow: ?struct { rc: ?*@import("qbe_rc_state.zig").State },
    touched: bool = false,

    /// Report unexpected instruction generation in an empty-frame assertion.
    pub fn temp(self: *RefusalEmitter) usize {
        self.touched = true;
        return 0;
    }
    /// Accept ordinary clear instructions for this small journal probe.
    pub fn print(self: *RefusalEmitter, comptime text: []const u8, args: anytype) frame.Error!void {
        _ = text;
        _ = args;
        self.touched = true;
    }
    /// Detect a uniqueness helper trying to form an address after refusal.
    pub fn address(self: *RefusalEmitter, pointer: usize, offset: u64) frame.Error!usize {
        _ = pointer;
        _ = offset;
        return self.temp();
    }
    /// Detect metadata emission after a forbidden runtime owner installation.
    pub fn descriptor(self: *RefusalEmitter, ty: @import("typed.zig").Type) frame.Error![]const u8 {
        _ = ty;
        self.touched = true;
        return "unused";
    }
};

// spec-case: RC-EMPTY-FRAME-1
test "RC empty frame refuses publication and scope before emitting instructions" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var state: @import("qbe_rc_state.zig").State = undefined;
    state.active = true;
    state.plan.journal = .{ .prefix = &.{ 0, 1 }, .unlinked = true };
    var emitter: RefusalEmitter = .{ .cow = .{ .rc = &state } };
    try t.expectError(error.InternalError, frame.initialized(RefusalEmitter, &emitter, 0, true));
    try t.expect(!emitter.touched);
    try t.expectError(error.InternalError, @import("qbe_rc_scope.zig").begin(RefusalEmitter, &emitter, 0));
    try t.expect(!emitter.touched);
    try t.expectError(error.InternalError, @import("qbe_rc_unique.zig").field(RefusalEmitter, &emitter, .{ .ty = .unit, .address = 0 }));
    try t.expect(!emitter.touched);
    try frame.initialized(RefusalEmitter, &emitter, 0, false);
    try t.expect(emitter.touched);
}

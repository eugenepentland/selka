//! Scoped SSA guards preserve captured mut places across argument evaluation.
const std = @import("std");
const ir = @import("ir.zig");
pub const Error = error{ OutOfMemory, Unsupported };

/// Start watching the ancestors of one fully selected interior argument.
pub fn watch(comptime Context: type, b: Context, place: *std.meta.Child(Context).FeaturePlace, span: u32) Error!void {
    if (place.steps.len == 0 or place.live != null) return;
    if ((b.versions.get(place.root) orelse 0) != place.root_version) return b.refuse("interior mut place changed while its index or key was evaluated", span);
    const live = try b.synthetic(.bool);
    try b.write(live, b.current.?, try b.constant(.bool, 1));
    try b.captures.append(b.allocator(), .{ .place = place.*, .live = live });
    place.live = live;
}

/// Distinct named fields or variants prove that two paths cannot be ancestors.
fn disjoint(comptime Place: type, written: Place, captured: Place) bool {
    for (written.steps, captured.steps[0..written.steps.len]) |left, right| {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        switch (left) {
            .field => |field| if (field != right.field) return true,
            .payload => |tag| if (tag != right.payload) return true,
            else => {},
        }
    }
    return false;
}

/// An executed ancestor write invalidates publication; sibling writes preserve it.
/// SSA joins keep writes in untaken argument branches from invalidating a capture.
pub fn invalidate(comptime Context: type, b: Context, written: std.meta.Child(Context).FeaturePlace, span: u32) Error!void {
    for (b.captures.items) |capture| {
        if (written.root != capture.place.root or written.steps.len >= capture.place.steps.len) continue;
        if (written.steps.len != 0) {
            if (disjoint(@TypeOf(written), written, capture.place)) continue;
            return b.refuse("interior mut argument ancestor changed by a later interior write", span);
        }
        try b.write(capture.live, b.current.?, try b.constant(.bool, 0));
    }
}

/// Reload a still-live place, or keep its selected value when an ancestor superseded it.
/// The orphaned path is never read again (its new parent can even be empty).
pub fn refresh(comptime Context: type, b: Context, place: *std.meta.Child(Context).FeaturePlace, selected: ir.Ref, span: u32) Error!ir.Ref {
    place.publish = try b.read(place.live.?, b.current.?);
    const result = try b.synthetic(b.typeOfRef(selected));
    const current = try b.newBlock();
    const orphan = try b.newBlock();
    const join = try b.newBlock();
    try b.branch(place.publish, current, orphan, span);
    try b.seal(current);
    b.current = current;
    try b.write(result, b.current.?, try b.readPlace(place.*, span));
    try b.jump(join);
    try b.seal(orphan);
    b.current = orphan;
    try b.write(result, orphan, selected);
    try b.jump(join);
    try b.seal(join);
    b.enter(join);
    return b.read(result, join);
}

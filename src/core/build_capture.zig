//! Scoped SSA guards preserve captured mut places across argument evaluation.
const std = @import("std");
const ir = @import("ir.zig");
const values = @import("build_values.zig");
pub const Error = error{ OutOfMemory, Unsupported };

/// Start watching the ancestors of one fully selected interior argument.
pub fn watch(comptime Context: type, b: Context, place: *std.meta.Child(Context).FeaturePlace) Error!void {
    if (place.steps.len == 0 or place.live != null) return;
    const live = try b.synthetic(.bool);
    try b.write(live, b.current.?, try b.constant(.bool, 1));
    try b.captures.append(b.allocator(), .{ .place = place.*, .live = live });
    place.live = live;
}

/// Compare path components without repeating their source expressions.
fn prefix(comptime Context: type, b: Context, written: std.meta.Child(Context).FeaturePlace, captured: std.meta.Child(Context).FeaturePlace, span: u32) Error!ir.Ref {
    var same = try b.constant(.bool, 1);
    for (written.steps, captured.steps[0..written.steps.len]) |left, right| {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return b.constant(.bool, 0);
        const component = switch (left) {
            .field => |field| try b.constant(.bool, @intFromBool(field == right.field)),
            .payload => |tag| try b.constant(.bool, @intFromBool(tag == right.payload)),
            .element => |index| try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = right.element, .data = @backingInt(ir.Predicate.eq), .span = span }),
            .mapping => |key| try values.equal(Context, b, key, right.mapping, span),
        };
        same = try b.emit(.{ .op = .bit_and, .ty = .bool, .a = same, .b = component, .span = span });
    }
    return same;
}

/// An executed ancestor write invalidates publication; sibling writes preserve it.
/// SSA joins keep writes in untaken argument branches from invalidating a capture.
pub fn invalidate(comptime Context: type, b: Context, written: std.meta.Child(Context).FeaturePlace, span: u32) Error!void {
    for (b.captures.items) |capture| {
        if (written.root != capture.place.root or written.steps.len >= capture.place.steps.len) continue;
        const ancestor = try prefix(Context, b, written, capture.place, span);
        const different = try b.emit(.{ .op = .cmp, .ty = .bool, .a = ancestor, .b = try b.constant(.bool, 0), .data = @backingInt(ir.Predicate.eq), .span = span });
        const live = try b.read(capture.live, b.current.?);
        try b.write(capture.live, b.current.?, try b.emit(.{ .op = .bit_and, .ty = .bool, .a = live, .b = different, .span = span }));
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

//! Bounded authority reachability for a physically moved collection argument.
const typed = @import("typed.zig");
const shapes = @import("rc_shape.zig");
/// Proof limits refuse optimization; allocation failures remain compiler errors.
pub const Error = error{ InternalError, OutOfMemory };
const Work = struct {
    pending: [256]typed.Type = undefined,
    seen: [256]typed.Type = undefined,
    count: usize = 0,
    visited: usize = 0,

    fn append(self: *Work, ty: typed.Type) bool {
        if (self.count == self.pending.len) return false;
        self.pending[self.count] = ty;
        self.count += 1;
        return true;
    }
    fn known(self: *Work, ty: typed.Type) bool {
        for (self.seen[0..self.visited]) |previous| if (previous == ty) return true;
        return false;
    }
};

/// No reachable callable, opaque handle, capability, live view or unique resource
/// may grant a callee authority over the temporarily cleared source storage.
pub fn safe(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    return walk(catalog, ty, false);
}

/// `safe` for a whole moved field value, which may carry a sealed capability:
/// capability bits are host authority with no path to guest storage, and the
/// walk does not look inside them. Everything else `safe` refuses stays refused.
pub fn movable(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    return walk(catalog, ty, true);
}

fn walk(catalog: *shapes.Catalog, ty: typed.Type, capabilities: bool) Error!bool {
    var work: Work = .{};
    _ = work.append(ty);
    while (work.count != 0) {
        work.count -= 1;
        const current = work.pending[work.count];
        if (work.known(current)) continue;
        if (work.visited == work.seen.len) return false;
        work.seen[work.visited] = current;
        work.visited += 1;
        if (capabilities and current.capabilityIndex() != null) continue;
        if (current.capabilityIndex() != null or current.resourceKind() != null) return false;
        const layout = catalog.native.layout(current) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
        if (layout.drop or layout.copy == .prohibited) return false;
        switch (layout.kind) {
            .callable, .resource, .handle, .pool_handle, .owned_buffer, .owned_pool => return false,
            else => {},
        }
        if (!current.isAggregate()) continue;
        const record = catalog.native.records[current.recordIndex()];
        if (record.shape.builtin != .none or record.isManagedRecord()) return false;
        if (!appendRecord(&work, record)) return false;
    }
    return true;
}

fn appendRecord(work: *Work, record: typed.Record) bool {
    if (record.shape.buffer) |child| if (!work.append(child)) return false;
    if (record.shape.domain) |child| if (!work.append(child)) return false;
    if (record.shape.array) |array| if (!work.append(array.element)) return false;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |child| if (!work.append(child)) return false;
    };
    for (record.fields) |field| if (!work.append(field.ty)) return false;
    return true;
}

// spec-case: RC-CALLER-FIELD-READ-1
test "RC record field safe-type admission propagates failed layout allocation and retries" {
    const t = @import("std").testing;
    const native = @import("native_types.zig");
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    const records = [_]typed.Record{.{ .id = ty, .name = "Plain", .declaration = span, .fields = &.{.{ .name = "value", .declaration = span, .ty = .i64 }} }};
    var layouts = try native.Catalog.initRecords(t.allocator, &records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    layouts.allocator = failing.allocator();
    try t.expectError(error.OutOfMemory, safe(&catalog, ty));
    layouts.allocator = t.allocator;
    try t.expect(try safe(&catalog, ty));
}

// spec-case: RC-CALLER-FIELD-READ-1
test "RC record field safe-type authority independently refuses transitive live views" {
    const t = @import("std").testing;
    const native = @import("native_types.zig");
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const view: typed.Type = @fromBackingInt(typed.Type.record_base);
    const wrapper: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const records = [_]typed.Record{
        .{ .id = view, .name = "View", .declaration = span, .shape = .{ .builtin = .live_view }, .fields = &.{.{ .name = "mapping", .declaration = span, .ty = .i64 }} },
        .{ .id = wrapper, .name = "Wrapper", .declaration = span, .fields = &.{.{ .name = "value", .declaration = span, .ty = view }} },
    };
    var layouts = try native.Catalog.initRecords(t.allocator, &records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    try t.expect(!try safe(&catalog, wrapper));
    try t.expect(!try safe(&catalog, view));
}

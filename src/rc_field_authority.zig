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
    var work: Work = .{};
    _ = work.append(ty);
    while (work.count != 0) {
        work.count -= 1;
        const current = work.pending[work.count];
        if (work.known(current)) continue;
        if (work.visited == work.seen.len) return false;
        work.seen[work.visited] = current;
        work.visited += 1;
        if (current.capabilityIndex() != null or current.resourceKind() != null) return false;
        const layout = catalog.native.layout(current) catch return error.InternalError;
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

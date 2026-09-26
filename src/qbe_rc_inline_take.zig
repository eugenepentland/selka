//! Bounded physical token moves with the general transaction as a fallback.
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const semantics = @import("value_semantics.zig");
const flat_limit = 8;
const Flat = struct { offsets: [flat_limit]u64 = undefined, len: usize = 0, remaining: usize = 256 };
// These are common-header flags; no RC-only prefix word is read. Arena and
// pinned sources need the runtime's region/clone transaction. DYING is invalid.
const slow_marks: u64 = (@as(u64, 1) << 62) | (@as(u64, 1) << 60) | 1;
/// Native emission failures; unsupported layouts simply keep the runtime path.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Begin a pure token relocation, or decline unsupported physical layouts.
/// The returned label joins the caller's existing fallible runtime fallback.
/// Guest entry follows a draining public ownership boundary; reentrant guest
/// calls inside a finalizer already have an active drain. Pure moves neither
/// enqueue deaths nor need to invoke that already-complete/active drain.
pub fn begin(comptime E: type, self: *E, operation: anytype) Error!?usize {
    const state = self.cow.?.rc orelse return null;
    const shape = state.catalog.get(operation.ty) catch |err| return translate(err);
    if (!shape.counted or shape.unique_drop) return null;
    var flat: Flat = .{};
    if (!try flatten(self.layouts, operation.ty, 0, &flat) or flat.len == 0) return null;
    const size = (try self.layout(operation.ty)).size;
    const label = self.temp();
    if (!operation.disjoint) try overlap(E, self, operation, size, label);
    for (flat.offsets[0..flat.len]) |offset| try pointer(E, self, operation.source, offset, label);
    // All pointer/header checks precede publication. Generated callers supply
    // the current valid region and an owning source guard; no count changes,
    // allocation, callback or recoverable failure remains on this path.
    try self.print(" blit %v{d}, %v{d}, {d}\n call $memset(l %v{d}, w 0, l {d})\n", .{ operation.source, operation.destination, size, operation.source, size });
    try self.print(" jmp @rcmoved{d}\n@rcmoveslow{d}\n", .{ label, label });
    return label;
}

fn flatten(catalog: *native.Catalog, ty: typed.Type, base: u64, flat: *Flat) Error!bool {
    if (flat.remaining == 0 or semantics.isLiveView(catalog.records, ty)) return false;
    flat.remaining -= 1;
    const layout = catalog.layout(ty) catch |err| return translate(err);
    if (layout.drop) return false;
    switch (layout.kind) {
        .managed => {
            if (flat.len == flat_limit) return false;
            flat.offsets[flat.len] = base;
            flat.len += 1;
        },
        .record, .domain, .niche => {
            for (layout.fields) |field| if (!try flatten(catalog, field.ty, base + field.offset, flat)) return false;
        },
        .array => {
            if (layout.fields.len != 1 or layout.count > flat.remaining) return false;
            for (0..layout.count) |index| if (!try flatten(catalog, layout.fields[0].ty, base + index * layout.stride, flat)) return false;
        },
        .scalar, .handle, .pool_handle, .callable => {},
        .variant, .resource, .owned_buffer, .owned_pool => return false,
    }
    return true;
}

fn overlap(comptime E: type, self: *E, operation: anytype, size: u64, label: usize) Error!void {
    const left = self.temp();
    const right = self.temp();
    const near_left = self.temp();
    const near_right = self.temp();
    const overlapping = self.temp();
    try self.print(" %v{d} =l sub %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ left, operation.source, operation.destination, right, operation.destination, operation.source });
    try self.print(" %v{d} =w cultl %v{d}, {d}\n %v{d} =w cultl %v{d}, {d}\n", .{ near_left, left, size, near_right, right, size });
    try self.print(" %v{d} =w or %v{d}, %v{d}\n jnz %v{d}, @rcmoveslow{d}, @rcmovecheck{d}\n@rcmovecheck{d}\n", .{ overlapping, near_left, near_right, overlapping, label, label, label });
}

fn pointer(comptime E: type, self: *E, source: usize, offset: u64, slow: usize) Error!void {
    const payload = self.temp();
    const nonnull = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =w cnel %v{d}, 0\n jnz %v{d}, @rcmoveheader{d}, @rcmovenext{d}\n@rcmoveheader{d}\n", .{ payload, try self.address(source, offset), nonnull, payload, nonnull, label, label, label });
    const header = self.temp();
    const mark = self.temp();
    const special = self.temp();
    const slow_path = self.temp();
    try self.print(" %v{d} =l sub %v{d}, 16\n %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, {d}\n", .{ header, payload, mark, header, special, mark, slow_marks });
    try self.print(" %v{d} =w cnel %v{d}, 0\n jnz %v{d}, @rcmoveslow{d}, @rcmovenext{d}\n@rcmovenext{d}\n", .{ slow_path, special, slow_path, slow, label, label });
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

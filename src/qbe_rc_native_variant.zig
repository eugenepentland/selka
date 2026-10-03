//! RC-NATIVE-VARIANT-1: the edge-free active case of a counted tagged value.
//! Unknown tags and counted cases keep the complete generated glue operation.
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const runtime = @import("runtime_mode.zig");
const zero = @import("qbe_zero.zig");
const heap_region_depth_offset = @import("qbe_alloc.zig").heap_region_depth_offset;

/// Native emission failures shared with the ownership glue emitter.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bound the repeated physical-case proof to at most 64 field visits per site.
pub const max_cases: usize = 8;
/// A small tagged layout and its declared cases with no physical obligations.
pub const Plan = struct { tags: [4]u32 = undefined, len: usize = 0, size: u64, alignment: u8 };

/// Prove exact declared active tags against the physical field table, including
/// payloadless cases. No niche, outer domain, unique resource or large layout.
pub fn plan(catalog: *native.Catalog, facts: *shapes.Catalog, ty: typed.Type) native.Error!?Plan {
    if (!ty.isAggregate()) return null;
    const layout = try catalog.layout(ty);
    const shape = try facts.get(ty);
    if (layout.kind != .variant or layout.alignment < 4) return null;
    if (layout.size < 4 or layout.size > 32) return null;
    if (!shape.counted or shape.unique_drop) return null;
    if (!shape.copyable) return null;
    const variants = catalog.records[ty.recordIndex()].shape.variants orelse return null;
    if (variants.cases.len > max_cases or layout.fields.len > max_cases) return null;
    var result: Plan = .{ .size = layout.size, .alignment = layout.alignment };
    for (variants.cases, 0..) |_, active| {
        var plain = true;
        for (layout.fields) |field| if (field.tag == active) {
            const child = try facts.get(field.ty);
            if (child.counted or child.unique_drop or !child.copyable) plain = false;
        };
        if (!plain) continue;
        if (result.len == result.tags.len) return null;
        result.tags[result.len] = @intCast(active);
        result.len += 1;
    }
    return if (result.len == 0) null else result;
}

fn admitted(comptime E: type, self: *E, ty: typed.Type) Error!?Plan {
    // Original policy refuses before any layout/catalog/temporary query.
    if (comptime !@hasField(E, "native_variants")) return null;
    if (self.native_variants != .qbe_v2) return null;
    if (comptime !(@hasField(E, "cow") and @hasField(E, "layouts"))) return null;
    if (!runtime.enabled() or runtime.counting()) return null;
    const cow = self.cow orelse return null;
    const state = cow.rc orelse return null;
    return plan(self.layouts, &state.catalog, ty) catch |err| translate(err);
}

/// Branch around the helper only for a declared edge-free tag; all other tags
/// reach slow before any value byte changes, including malformed tags.
fn tag(comptime E: type, self: *E, address: usize, layout: Plan, label: usize) Error!void {
    const active = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n", .{ active, address });
    for (layout.tags[0..layout.len], 0..) |value, index| {
        const selected = self.temp();
        const next = self.temp();
        try self.print(" %v{d} =w ceqw %v{d}, {d}\n", .{ selected, active, value });
        if (index + 1 == layout.len) {
            try self.print(" jnz %v{d}, @rcnativeplain{d}, @rcnativeslow{d}\n", .{ selected, label, label });
        } else try self.print(" jnz %v{d}, @rcnativeplain{d}, @rcnativenext{d}\n@rcnativenext{d}\n", .{ selected, label, next, next });
    }
    try self.print("@rcnativeplain{d}\n", .{label});
}

/// Copy every value byte, including inactive payload/padding, then clear every
/// source byte. Keep the generated helper's overlapping transaction unchanged.
pub fn take(comptime E: type, self: *E, operation: anytype) Error!?usize {
    const layout = try admitted(E, self, operation.ty) orelse return null;
    const label = self.temp();
    try self.print(" # RC-NATIVE-VARIANT-1 take\n", .{});
    try tag(E, self, operation.source, layout, label);
    // Generated take checks this even when the active tag has no edge. Use
    // its unsigned-word argument width and the runtime's published heap ABI.
    const depth_slot = self.temp();
    const depth = self.temp();
    const valid_region = self.temp();
    try self.print(" %v{d} =l add %heap, {d}\n %v{d} =w loaduw %v{d}\n", .{ depth_slot, heap_region_depth_offset, depth, depth_slot });
    try self.print(" %v{d} =w culew %v{d}, %v{d}\n jnz %v{d}, @rcnativeregion{d}, @rcnativeslow{d}\n@rcnativeregion{d}\n", .{ valid_region, operation.region, depth, valid_region, label, label, label });
    if (operation.disjoint) {
        // Only propagate the existing completed-publication storage proof.
        // Caller ownership/borrow/capture admission remains unchanged.
        try self.print(" # RC-DISJOINT-TAKE-1 native variant\n", .{});
    } else try @import("qbe_rc_overlap.zig").branch(E, self, .{ .source = operation.source, .destination = operation.destination, .size = layout.size }, .{ .slow = "rcnativeslow", .fast = "rcnativecopy", .number = label });
    try self.print("@rcnativecopy{d}\n blit %v{d}, %v{d}, {d}\n", .{ label, operation.source, operation.destination, layout.size });
    try zero.clear(*E, self, operation.source, layout.size, layout.alignment);
    try self.print(" jmp @rcnativedone{d}\n@rcnativeslow{d}\n", .{ label, label });
    return label;
}

/// The generated drop/unloan visits no edge for this tag: no count, history,
/// death, callback or drain occurs, and its only effect is whole-value clearing.
pub fn release(comptime E: type, self: *E, operation: anytype) Error!?usize {
    const layout = try admitted(E, self, operation.ty) orelse return null;
    const label = self.temp();
    try self.print(" # RC-NATIVE-VARIANT-1 release\n", .{});
    try tag(E, self, operation.address, layout, label);
    try zero.clear(*E, self, operation.address, layout.size, layout.alignment);
    try self.print(" jmp @rcnativedone{d}\n@rcnativeslow{d}\n", .{ label, label });
    return label;
}

/// Rejoin after the caller's unchanged helper, status mapping and failure edge.
pub fn join(comptime E: type, self: *E, label: ?usize) Error!void {
    if (label) |value| try self.print("@rcnativedone{d}\n", .{value});
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

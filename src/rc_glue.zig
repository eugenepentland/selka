//! RC-GLUE-1: generated per-type ownership glue for the RC runtime.
//!
//! Every counted inline type gets straight-line C in the program's metadata
//! unit: records are flattened, fixed arrays become loops, variants switch on
//! their tag and each pointer edge is a null test, a mark test and one count
//! update. No metadata lookup, shape interpretation, status plumbing or drain
//! runs on the fast path. Anything unusual (an arena or pinned edge, an
//! overlapping move) calls the unchanged runtime entry for the whole value
//! before any count changes, so the slow path keeps every existing semantic.
//! The metadata unit is compiled once per program with the runtime's own
//! flags, so a counting build counts through the same MYL_RC_STAT events and
//! checks the invariants the fast path otherwise skips, and full LTO can
//! inline the glue into guest code.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const shapes = @import("rc_shape.zig");
const semantics = @import("value_semantics.zig");
const acquisition = @import("rc_glue_acquisition.zig");

/// Layout, allocation or output failure while generating glue.
pub const Error = native.Error;

/// One generated entry per ownership operation kind.
pub const Operation = enum {
    /// Copy bytes and acquire one hold per edge; infallible.
    loan,
    /// Clear and release one hold per edge, draining only after a death.
    unloan,
    /// Copy bytes and acquire each edge's own token (O, or H for a live view).
    retain,
    /// Move bytes and clear the source; no count changes.
    take,
    /// Clear and release each edge's own token, draining only after a death.
    drop,
    /// Semantic direct publication: mark mutable payloads shared, then copy
    /// (retaining) or move the value.
    publish,
    /// Replace one list element in place (myl_rc_list_set's contract).
    list_set,
    /// Append one retained element (myl_rc_list_append's contract).
    list_append,

    /// The suffix a glue symbol carries after its type's descriptor symbol.
    pub fn suffix(self: Operation) []const u8 {
        return switch (self) {
            .loan => "_rcg_loan",
            .unloan => "_rcg_unloan",
            .retain => "_rcg_retain",
            .take => "_rcg_take",
            .drop => "_rcg_drop",
            .publish => "_rcg_publish",
            .list_set => "_rcg_list_set",
            .list_append => "_rcg_list_append",
        };
    }
};

/// Shared helpers for generated whole-value count preflight and token updates.
const success_return = "return 1;\n}}\n";

const prelude =
    \\#include "qbe_runtime.h"
    \\#include "native_rc_internal.h"
    \\#include "native_rc_values.h"
    \\#include "native_rc_collections.h"
    \\#include <string.h>
    \\/* RC-GLUE-1: active counts are unsigned 64-bit words. Generated glue
    \\ * preflights its whole value before changing bytes or marks: a count
    \\ * near saturation uses the runtime's exact alias-aware transaction.
    \\ * Remaining paths can acquire every leaf without wrapping. */
    \\#if (defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING) || defined(MYL_RC_GLUE_CHECKED)
    \\#define MYL_RCG_CHECK(valid) myl_rc_invariant(valid)
    \\#define MYL_RCG_CHECKED 1
    \\#else
    \\#define MYL_RCG_CHECK(valid) ((void)0)
    \\#define MYL_RCG_CHECKED 0
    \\#endif
    \\#define MYL_RCG_UNCOUNTED (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA)
    \\/* Helpers stay plain inline: clang inlines them at -O2 anyway, and
    \\ * forcing it costs a third of the unit's compile time. */
    \\#define MYL_RCG_INLINE static inline
    \\MYL_RCG_INLINE void *myl_rcg_load(const unsigned char *at) { void *p; memcpy(&p, at, sizeof p); return p; }
    \\MYL_RCG_INLINE void *myl_rcg_clear(unsigned char *at) { void *p; memcpy(&p, at, sizeof p); memset(at, 0, sizeof p); return p; }
    \\MYL_RCG_INLINE uint32_t myl_rcg_tag(const unsigned char *at) { uint32_t tag; memcpy(&tag, at, sizeof tag); return tag; }
    \\MYL_RCG_INLINE uintptr_t myl_rcg_flags(const void *p) { return p ? ((const myl_native_object *)p - 1)->mark : 0; }
    \\MYL_RCG_INLINE int myl_rcg_overlap(const void *a, const void *b, size_t bytes) {
    \\    uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
    \\    return x > y ? x - y < bytes : y - x < bytes;
    \\}
    \\/* The counted prefix of a live ordinary object, or NULL for null/immortal/arena. */
    \\MYL_RCG_INLINE myl_rc_object *myl_rcg_counted(const void *p) {
    \\    if (!p) return NULL;
    \\    uintptr_t mark = ((const myl_native_object *)p - 1)->mark;
    \\    if (mark & MYL_RCG_UNCOUNTED) return NULL;
    \\    myl_rc_object *object = (myl_rc_object *)p - 1;
    \\    MYL_RCG_CHECK(!(mark & MYL_RC_OBJECT_DYING) && (object->owners || object->holds));
    \\    return object;
    \\}
    \\MYL_RCG_INLINE int myl_rcg_capacity(const void *p, size_t bound, int hold) {
    \\    myl_rc_object *object = myl_rcg_counted(p);
    \\    return !object || (bound <= MYL_RC_COUNT_MAX &&
    \\        (hold ? object->holds : object->owners) <= MYL_RC_COUNT_MAX - bound);
    \\}
    \\MYL_RCG_INLINE void myl_rcg_owner_acquire(myl_native_heap *heap, void *p) {
    \\    myl_rc_object *object = myl_rcg_counted(p);
    \\    (void)heap;
    \\    if (!object) return;
    \\    ++object->owners;
    \\    MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_ACQUIRE);
    \\}
    \\MYL_RCG_INLINE void myl_rcg_hold_acquire(myl_native_heap *heap, void *p) {
    \\    myl_rc_object *object = myl_rcg_counted(p);
    \\    (void)heap;
    \\    if (!object) return;
    \\    ++object->holds;
    \\    MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_ACQUIRE);
    \\}
    \\/* A loan never pins a finalizing body; checked builds prove it per edge. */
    \\MYL_RCG_INLINE void myl_rcg_loan_check(myl_native_heap *heap, void *p) {
    \\#if MYL_RCG_CHECKED
    \\    if (p) {
    \\        const myl_native_object *header = (const myl_native_object *)p - 1;
    \\        const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(heap, header->element);
    \\        myl_rc_invariant((header->mark & MYL_NATIVE_OBJECT_IMMORTAL) || (descriptor && !descriptor->finalize));
    \\    }
    \\#else
    \\    (void)heap; (void)p;
    \\#endif
    \\}
    \\MYL_RCG_INLINE void myl_rcg_loan_acquire(myl_native_heap *heap, void *p) {
    \\    myl_rcg_loan_check(heap, p);
    \\    myl_rcg_hold_acquire(heap, p);
    \\}
    \\/* Returns 1 when the edge was the last token and its death is now queued. */
    \\MYL_RCG_INLINE int myl_rcg_owner_release(myl_native_heap *heap, void *p) {
    \\    myl_rc_object *object = myl_rcg_counted(p);
    \\    if (!object) return 0;
    \\    if (object->owners != 1 || object->holds) {
    \\        MYL_RCG_CHECK(object->owners != 0);
    \\        --object->owners;
    \\        MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_RELEASE);
    \\        return 0;
    \\    }
    \\    myl_rc_edge_release(heap, p);
    \\    return 1;
    \\}
    \\/* Semantic SHARE of one direct payload, as the runtime's queued marks. */
    \\MYL_RCG_INLINE void myl_rcg_share(void *p) {
    \\    if (!p) return;
    \\    myl_native_object *header = (myl_native_object *)p - 1;
    \\    if (header->mark & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_SHARED)) return;
    \\    MYL_RCG_CHECK(!(header->mark & MYL_NATIVE_OBJECT_PINNED));
    \\    if (myl_rc_native_mutable(p)) header->mark |= MYL_NATIVE_OBJECT_SHARED;
    \\}
    \\MYL_RCG_INLINE int myl_rcg_hold_release(myl_native_heap *heap, void *p) {
    \\    myl_rc_object *object = myl_rcg_counted(p);
    \\    if (!object) return 0;
    \\    if (object->holds != 1 || object->owners) {
    \\        MYL_RCG_CHECK(object->holds != 0);
    \\        --object->holds;
    \\        MYL_RC_STAT(heap, MYL_RC_STAT_HOLD_RELEASE);
    \\        return 0;
    \\    }
    \\    myl_rc_hold_edge_release(heap, p);
    \\    return 1;
    \\}
    \\
;

/// What one edge visit does. Scans read marks; the rest change counts.
const Action = enum { scan, share, loan, retain, drop, unloan, loan_capacity, retain_capacity };
/// Which token an edge owns: an ordinary owner or a live view's hold.
const Edge = enum { owner, hold };

const Generator = struct {
    allocator: std.mem.Allocator,
    catalog: *native.Catalog,
    facts: *shapes.Catalog,
    writer: *std.Io.Writer,
    serial: usize = 0,

    fn print(self: *Generator, comptime format: []const u8, arguments: anytype) Error!void {
        self.writer.print(format, arguments) catch return error.OutOfMemory;
    }

    /// Emit one statement per live edge of `ty` stored at C pointer `base`.
    fn edges(self: *Generator, ty: typed.Type, base: []const u8, action: Action) Error!void {
        if (!(try self.facts.get(ty)).counted) return;
        if (semantics.isLiveView(self.catalog.records, ty)) return self.edge(.hold, base, action);
        const layout = try self.catalog.layout(ty);
        switch (layout.kind) {
            .managed, .niche => try self.edge(.owner, base, action),
            .record, .domain => for (layout.fields) |field| {
                try self.edges(field.ty, try self.at(base, field.offset), action);
            },
            .variant => try self.variant(layout, base, action),
            .array => if (layout.count != 0 and layout.fields.len == 1) {
                const index = self.serial;
                self.serial += 1;
                try self.print("for (size_t i{d} = 0; i{d} < {d}; ++i{d}) {{\nunsigned char *b{d} = (unsigned char *)({s}) + i{d} * {d};\n", .{ index, index, layout.count, index, index, base, index, layout.stride });
                try self.edges(layout.fields[0].ty, try std.fmt.allocPrint(self.allocator, "b{d}", .{index}), action);
                try self.print("}}\n", .{});
            },
            .scalar, .handle, .pool_handle, .callable, .resource, .owned_buffer, .owned_pool => {},
        }
    }

    fn variant(self: *Generator, layout: native.Layout, base: []const u8, action: Action) Error!void {
        try self.print("switch (myl_rcg_tag((const unsigned char *)({s}))) {{\n", .{base});
        for (layout.fields, 0..) |field, index| {
            const tag = field.tag orelse 0;
            // Group every counted field of one tag under the first such field.
            var first = true;
            for (layout.fields[0..index]) |earlier| {
                if ((earlier.tag orelse 0) == tag and (try self.facts.get(earlier.ty)).counted) first = false;
            }
            if (!first or !(try self.facts.get(field.ty)).counted) continue;
            try self.print("case {d}:\n", .{tag});
            for (layout.fields[index..]) |member| if ((member.tag orelse 0) == tag) {
                try self.edges(member.ty, try self.at(base, member.offset), action);
            };
            try self.print("break;\n", .{});
        }
        try self.print("default: break;\n}}\n", .{});
    }

    fn edge(self: *Generator, kind: Edge, base: []const u8, action: Action) Error!void {
        if (action == .loan_capacity or action == .retain_capacity) {
            const hold = action == .loan_capacity or kind == .hold;
            try self.print("capacity &= myl_rcg_capacity(myl_rcg_load((const unsigned char *)({s})), bound, {d});\n", .{ base, @intFromBool(hold) });
            return;
        }
        // Only ordinary payloads take part in semantic history.
        if (action == .share and kind == .hold) return;
        // A loan takes H on every edge and an unloan returns it; retain and
        // drop use each edge's own token.
        const token: Edge = if (action == .loan or action == .unloan) .hold else kind;
        const call: []const u8 = switch (action) {
            .loan_capacity, .retain_capacity => unreachable,
            .scan => "any |= myl_rcg_flags",
            .share => "myl_rcg_share",
            .loan => "myl_rcg_loan_acquire",
            .retain => if (token == .owner) "myl_rcg_owner_acquire" else "myl_rcg_hold_acquire",
            .drop, .unloan => if (token == .owner) "died |= myl_rcg_owner_release" else "died |= myl_rcg_hold_release",
        };
        const heap = if (action == .scan or action == .share) "" else "heap, ";
        const access = if (action == .drop or action == .unloan) "myl_rcg_clear((unsigned char *)" else "myl_rcg_load((const unsigned char *)";
        try self.print("{s}({s}{s}({s})));\n", .{ call, heap, access, base });
    }

    fn at(self: *Generator, base: []const u8, offset: u64) Error![]const u8 {
        if (offset == 0) return base;
        return std.fmt.allocPrint(self.allocator, "(unsigned char *)({s}) + {d}", .{ base, offset });
    }

    /// The entries of one counted inline type; list element glue only for a
    /// type some collection stores.
    fn functions(self: *Generator, ty: typed.Type, name: []const u8, element: bool) Error!void {
        const size = (try self.catalog.layout(ty)).size;
        try self.print("int {s}_rcg_loan(myl_native_heap *heap, void *dst, const void *src) {{\n", .{name});
        const loan: acquisition.Value = .{ .ty = ty, .name = name, .size = size, .loan = true };
        if (!try acquisition.write(self.allocator, self.catalog, self.facts, loan, self.writer)) {
            try self.capacity(ty, size, .loan_capacity);
            try self.print("if (!capacity) return myl_rc_native_loan(heap, &{s}, dst, src);\n", .{name});
            try self.print("MYL_RCG_CHECK(!myl_rcg_overlap(dst, src, {d}));\n", .{size});
            // Every refusal precedes acquisition. Reading the admitted source
            // before copying keeps its tag and edge reads together for C codegen.
            try self.edges(ty, "src", .loan);
            try self.print("memcpy(dst, src, {d});\n", .{size});
        }
        try self.print(success_return, .{});
        inline for (.{ Action.unloan, Action.drop }) |action| {
            try self.print("void {s}_rcg_{s}(myl_native_heap *heap, void *value) {{\nint died = 0;\n", .{ name, @tagName(action) });
            try self.edges(ty, "value", action);
            try self.print("memset(value, 0, {d});\nif (died) myl_rc_drain(heap);\n}}\n", .{size});
        }
        // Physical retention ignores pins; only an arena edge needs the
        // runtime's region check, before any count changes.
        try self.print("int {s}_rcg_retain(myl_native_heap *heap, void *dst, const void *src, unsigned region) {{\n", .{name});
        const retained: acquisition.Value = .{ .ty = ty, .name = name, .size = size, .loan = false };
        if (!try acquisition.write(self.allocator, self.catalog, self.facts, retained, self.writer)) {
            try self.print("uintptr_t any = 0;\n", .{});
            try self.edges(ty, "src", .scan);
            try self.capacity(ty, size, .retain_capacity);
            try self.print("if (!capacity || (any & MYL_NATIVE_OBJECT_ARENA)) return myl_rc_native_retain(heap, &{s}, dst, src, region);\n", .{name});
            try self.print("MYL_RCG_CHECK(dst != src && region <= heap->region_depth);\n", .{});
            try self.edges(ty, "src", .retain);
            try self.print("memmove(dst, src, {d});\n", .{size});
        }
        try self.print(success_return, .{});
        // A pinned source needs the snapshot, an arena source the region
        // check and an overlapping move the staged copy: all runtime work.
        try self.print("int {s}_rcg_take(myl_native_heap *heap, void *dst, void *src, unsigned region) {{\nuintptr_t any = 0;\n", .{name});
        try self.edges(ty, "src", .scan);
        try self.print("if ((any & (MYL_NATIVE_OBJECT_ARENA | MYL_NATIVE_OBJECT_PINNED)) || myl_rcg_overlap(dst, src, {d}))\n", .{size});
        try self.print("return myl_rc_native_take(heap, &{s}, dst, src, region);\n", .{name});
        try self.print("MYL_RCG_CHECK(!(any & MYL_RC_OBJECT_DYING) && region <= heap->region_depth);\nmemcpy(dst, src, {d});\nmemset(src, 0, {d});\nreturn 1;\n}}\n", .{ size, size });
        // Only direct history runs here: child modes, pins, arenas and
        // overlapping ranges keep the runtime's semantic transaction.
        try self.print("int {s}_rcg_publish(myl_native_heap *heap, void *dst, void *src, unsigned region, unsigned mode) {{\nuintptr_t any = 0;\n", .{name});
        try self.edges(ty, "src", .scan);
        try self.print("if ((mode & 3u) || (any & (MYL_NATIVE_OBJECT_ARENA | MYL_NATIVE_OBJECT_PINNED)) || myl_rcg_overlap(dst, src, {d}))\n", .{size});
        try self.print("return myl_rc_native_publish(heap, &{s}, dst, src, region, mode);\n", .{name});
        try self.print("if (!(mode & MYL_RC_HISTORY_TAKE)) {{\n", .{});
        try self.capacity(ty, size, .retain_capacity);
        try self.print("if (!capacity) return myl_rc_native_publish(heap, &{s}, dst, src, region, mode);\n}}\n", .{name});
        try self.print("MYL_RCG_CHECK(!(any & MYL_RC_OBJECT_DYING) && region <= heap->region_depth);\n", .{});
        try self.edges(ty, "src", .share);
        try self.print("memcpy(dst, src, {d});\nif (mode & MYL_RC_HISTORY_TAKE) {{ memset(src, 0, {d}); return 1; }}\n", .{ size, size });
        try self.edges(ty, "dst", .retain);
        try self.print(success_return, .{});
        if (element) try self.lists(name, size);
    }

    // Each live pointer occupies eight disjoint value bytes. This upper bound
    // safely covers aliases across every variant/array arm; exact near-limit
    // admission is left to the runtime transaction.
    fn capacity(self: *Generator, ty: typed.Type, size: u64, action: Action) Error!void {
        try self.print("int capacity = 1; const size_t bound = {d};\n", .{size / 8});
        try self.edges(ty, "src", action);
    }

    /// List element writes with the runtime's contracts: set stages the new
    /// value before the old one is dropped; append retains straight into
    /// spare capacity unless the value lives in the list's own storage.
    fn lists(self: *Generator, name: []const u8, size: u64) Error!void {
        try self.print("int {s}_rcg_list_set(myl_native_heap *heap, myl_native_list *list, size_t index, const void *value) {{\n", .{name});
        try self.print("if (index >= list->length) return 0;\nMYL_RCG_CHECK(list->element && list->element->size == {d});\n", .{size});
        try self.print("unsigned char *slot = (unsigned char *)list->storage + index * {d};\nif ((const void *)slot == value) return 1;\n", .{size});
        try self.print("unsigned char staged[{d}], old[{d}];\nif (!{s}_rcg_retain(heap, staged, value, myl_native_header_region(list))) return 0;\n", .{ size, size, name });
        try self.print("memcpy(old, slot, {d});\nmemcpy(slot, staged, {d});\n{s}_rcg_drop(heap, old);\nreturn 1;\n}}\n", .{ size, size, name });
        try self.append(name, size, true);
    }

    /// Room append: retain (or, for a plain value, copy) straight into spare
    /// capacity; growth, an exhausted generation and a value that lives in
    /// the list's own storage keep the runtime helper.
    fn append(self: *Generator, name: []const u8, size: u64, counted: bool) Error!void {
        try self.print("int {s}_rcg_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {{\n", .{name});
        try self.print("size_t length = list->length;\nunsigned char *storage = list->storage;\n", .{});
        try self.print("if (length >= list->capacity || list->generation == UINT64_MAX || (uintptr_t)value - (uintptr_t)storage < length * {d})\n", .{size});
        try self.print("return myl_rc_list_append(heap, list, value);\nMYL_RCG_CHECK(list->element && list->element->size == {d});\n", .{size});
        if (counted) {
            try self.print("if (!{s}_rcg_retain(heap, storage + length * {d}, value, myl_native_header_region(list))) return 0;\n", .{ name, size });
        } else try self.print("memcpy(storage + length * {d}, value, {d});\n", .{ size, size });
        try self.print("list->length = length + 1;\n++list->generation;\nreturn 1;\n}}\n", .{});
    }
};

/// Whether the compiler routes ownership operations on `ty` through glue:
/// counted, not a raw unique resource and not an empty value.
pub fn eligible(catalog: *native.Catalog, facts: *shapes.Catalog, ty: typed.Type) Error!bool {
    const shape = try facts.get(ty);
    if (!shape.counted or shape.unique_drop) return false;
    return (try catalog.layout(ty)).size != 0;
}

/// Whether some managed collection stores `ty` as its element: only such a
/// type gets (and is routed to) list element glue.
pub fn listElement(catalog: *const native.Catalog, ty: typed.Type) bool {
    for (catalog.records) |record| {
        if (record.isCollection() and !record.collection.box and record.shape.buffer.? == ty) return true;
    }
    return false;
}

/// Whether `ty` is an inline aggregate without edges or unique resources:
/// its list appends copy bytes through glue instead of the runtime walker.
pub fn plainAggregate(catalog: *native.Catalog, facts: *shapes.Catalog, ty: typed.Type) Error!bool {
    if (!ty.isAggregate() or semantics.isLiveView(catalog.records, ty)) return false;
    const shape = try facts.get(ty);
    if (shape.counted or shape.unique_drop) return false;
    const layout = try catalog.layout(ty);
    if (layout.size == 0) return false;
    // Scalar-like domains keep the compiler's inline scalar room append.
    return switch (layout.kind) {
        .record, .array, .variant => true,
        else => false,
    };
}

/// Emit glue for every counted inline type. Unused entries cost nothing at
/// run time: the unit keeps one section per function and the link drops the
/// rest. Types the compiler never routes here still get consistent entries.
pub fn generate(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return render(allocator, try blocks(arena.allocator(), catalog));
}

/// Independently mergeable ownership and collection-element definitions.
pub const Block = struct { name: []const u8, text: []const u8 };

/// Produce glue groups keyed by semantic symbol, independently of catalog order.
pub fn blocks(a: std.mem.Allocator, catalog: *native.Catalog) Error![]Block {
    var facts = try shapes.Catalog.init(a, catalog);
    var out: std.ArrayList(Block) = .empty;
    for (0..typed.Type.record_base + catalog.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(index);
        const counted = (try facts.get(ty)).counted and (try catalog.layout(ty)).size != 0;
        const plain = try plainAggregate(catalog, &facts, ty);
        if (!counted and !plain) continue;
        const name = try descriptors.symbol(a, catalog, ty);
        var output: std.Io.Writer.Allocating = .init(a);
        var generator: Generator = .{ .allocator = a, .catalog = catalog, .facts = &facts, .writer = &output.writer };
        if (counted) {
            try generator.functions(ty, name, false);
            try out.append(a, .{ .name = name, .text = try output.toOwnedSlice() });
        }
        if (listElement(catalog, ty)) {
            if (counted) try generator.lists(name, (try catalog.layout(ty)).size) else try generator.append(name, (try catalog.layout(ty)).size, false);
            try out.append(a, .{ .name = try std.fmt.allocPrint(a, "{s}_list", .{name}), .text = try output.toOwnedSlice() });
        }
    }
    std.mem.sort(Block, out.items, {}, blockBefore);
    return out.toOwnedSlice(a);
}

fn blockBefore(_: void, a: Block, b: Block) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

/// Shared glue helpers followed by the program's symbol-sorted definition union.
pub fn render(a: std.mem.Allocator, items: []const Block) Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    output.writer.writeAll(prelude) catch return error.OutOfMemory;
    for (items) |item| output.writer.writeAll(item.text) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

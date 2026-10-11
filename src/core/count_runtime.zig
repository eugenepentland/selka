//! The runtime of a counting build (NEW-CORE-COUNTERS-2): the ordinary runtime
//! source with `runtime/core_count.h` inserted after its includes, a call to a
//! counting hook inserted at each place below, and `runtime/core_count.c`
//! appended. The ordinary runtime text is never edited for counting, so a build
//! without `--counters` compiles, names and links exactly the runtime object it
//! did before (the object's file name is its source digest, and that name is in
//! every executable's symbol table).
//!
//! Each insertion is anchored to text that must occur exactly once in the
//! runtime; an edit that moves or duplicates an anchor fails `source` with
//! `error.AnchorMissing` (and the NEW-CORE-COUNTERS-2 test), never a silently
//! uncounted path.
const std = @import("std");

/// The counting hooks' declarations, inserted after the runtime's includes.
pub const header = @embedFile("runtime/core_count.h");
/// The hooks and the JSON writer, appended after the runtime.
pub const body = @embedFile("runtime/core_count.c");

/// Text inserted right before or right after the one occurrence of `anchor`.
const Patch = struct { anchor: []const u8, before: []const u8 = "", after: []const u8 = "" };

const patches = [_]Patch{
    .{ .anchor = "#include <malloc.h>\n", .after = header },
    .{ .anchor = "static void os_exit(int status) { ", .after = "if (!core_parallel()) myl_count_dump(); " },
    // Every block: carved from a chunk or a free list, or a large aligned allocation.
    .{ .anchor = "    block->kind = kind | (class << MYL_CLASS_SHIFT);\n", .before = "    myl_count_alloc(class ? (size_t)class * MYL_GRANULE : malloc_usable_size(block));\n" },
    .{
        .anchor = "static void block_free(myl_block *block) {\n    uint32_t class = class_of(block);\n",
        .after = "    myl_count_free(class ? (size_t)class * MYL_GRANULE : malloc_usable_size(block));\n",
    },
    // A large list grows with realloc, which may move it.
    .{
        .anchor = "        if (heap_ceiling) heap_refund(malloc_usable_size(list));\n        myl_block *moved = realloc(list, bytes);\n",
        .before = "        size_t myl_count_held = malloc_usable_size(list);\n        uintptr_t myl_count_from = (uintptr_t)list;\n",
    },
    .{
        .anchor = "        if (heap_ceiling) heap_charge(malloc_usable_size(moved));\n        moved->cap = cap;\n",
        .after = "        myl_count_realloc(myl_count_held, malloc_usable_size(moved), (uintptr_t)moved != myl_count_from, MYL_HEADER + (size_t)moved->len * (size_t)element_size);\n",
    },
    // A large buffer grows with realloc too (NEW-CORE-U1-GROW-1).
    .{
        .anchor = "        if (heap_ceiling) heap_refund(malloc_usable_size(buffer));\n        myl_block *grown = realloc(buffer, bytes);\n",
        .before = "        size_t myl_count_held = malloc_usable_size(buffer);\n        uintptr_t myl_count_from = (uintptr_t)buffer;\n",
    },
    .{
        .anchor = "        if (heap_ceiling) heap_charge(malloc_usable_size(grown));\n        grown->cap = capacity;\n",
        .after = "        myl_count_realloc(myl_count_held, malloc_usable_size(grown), (uintptr_t)grown != myl_count_from, MYL_HEADER + (size_t)grown->len);\n",
    },
    // A small list grows into a fresh block of the next class.
    .{
        .anchor = "    myl_block *grown = block_new(MYL_KIND_LIST, cap, element_size);\n    memcpy(block_data(grown), block_data(list), (size_t)list->len * (size_t)element_size);\n",
        .after = "    myl_count_list_grow((size_t)list->len * (size_t)element_size);\n",
    },
    .{ .anchor = "myl_block *myl_core_list_copy(myl_block *list, int64_t element_size) {\n", .after = "    myl_count_copy(MYL_COUNT_LIST_COPIES, (size_t)list->len * (size_t)element_size);\n" },
    .{
        .anchor = "static void count_retain(myl_block *block) {\n    if (!block) return;\n    uint32_t count = count_load(block);\n",
        .after = "    if (count != MYL_SATURATED) myl_count_event(MYL_COUNT_RUNTIME_RETAINS, 0);\n",
    },
    .{
        .anchor = "static bool count_release(myl_block *block) {\n    if (!block) return false;\n    uint32_t count = count_load(block);\n",
        .after = "    if (count != MYL_SATURATED) myl_count_event(MYL_COUNT_RUNTIME_RELEASES, 0);\n",
    },
    .{
        .anchor = "void myl_core_retain_slow(myl_block *block) {\n    uint32_t count = count_load(block);\n",
        .after = "    if (count >= MYL_SHARED && count != MYL_SATURATED) myl_count_event(MYL_COUNT_SHARED_RETAINS, 0);\n",
    },
    .{
        .anchor = "static bool count_release_shared(myl_block *block) {\n    uint32_t count = count_load(block);\n",
        .after = "    if (count != MYL_SATURATED) myl_count_event(MYL_COUNT_SHARED_RELEASES, 0);\n",
    },
    .{
        .anchor = "    child->count = count | MYL_SHARED;\n",
        .after = "    uint32_t myl_share_class = class_of(child);\n    myl_count_event(MYL_COUNT_SHARE_MARKS, myl_share_class ? (size_t)myl_share_class * MYL_GRANULE : malloc_usable_size(child));\n",
    },
    .{ .anchor = "    memcpy(other->hashes, meta->hashes, (size_t)meta->elen * 8);\n", .after = "    myl_count_copy(MYL_COUNT_DICT_COPIES, (size_t)meta->elen * ((size_t)meta->desc->stride + 8));\n" },
    .{
        .anchor = "    memcpy(block_data(grown), block_data(dict), (size_t)meta->elen * meta->desc->stride);\n",
        .after = "    myl_count_event(MYL_COUNT_DICT_GROWS, (size_t)meta->elen * ((size_t)meta->desc->stride + 8));\n",
    },
    .{ .anchor = "myl_block *myl_core_owned_octets_copy(myl_block *source) {\n", .after = "    myl_count_copy(kind_of(source) == MYL_KIND_STR ? MYL_COUNT_TEXT_COPIES : MYL_COUNT_BUFFER_COPIES, (size_t)source->len);\n" },
    .{ .anchor = "myl_block *myl_core_ir_str_from_view(const unsigned char *data, uint64_t len) { ", .after = "myl_count_copy(MYL_COUNT_TEXT_COPIES, (size_t)len); " },
    .{ .anchor = "myl_block *myl_core_ir_str_from_span(const unsigned char *data, uint64_t len, bool ascii) { ", .after = "myl_count_copy(MYL_COUNT_TEXT_COPIES, (size_t)len); " },
    .{
        .anchor = "static inline myl_block *core_text_append_bytes(myl_block *a, const unsigned char *bytes, int64_t count, bool ascii) {\n",
        .after = "    myl_count_event(MYL_COUNT_TEXT_APPENDS, (size_t)count);\n",
    },
    .{ .anchor = "        grown->len = a->len;\n        memcpy(block_data(grown), block_data(a), (size_t)a->len);\n", .after = "        myl_count_event(MYL_COUNT_TEXT_GROWS, (size_t)a->len);\n" },
    .{ .anchor = "myl_block *myl_core_buffer_copy(myl_block *source) {\n", .after = "    myl_count_copy(MYL_COUNT_BUFFER_COPIES, (size_t)source->len);\n" },
    .{ .anchor = "    myl_block *out = myl_core_buffer_new((uint64_t)capacity);\n    out->len = buffer->len;\n", .after = "    myl_count_event(MYL_COUNT_BUFFER_GROWS, (size_t)buffer->len);\n" },
    .{ .anchor = "myl_block *myl_core_buffer_push(myl_block *buffer, uint8_t value) {\n", .after = "    myl_count_event(MYL_COUNT_BUFFER_PUSHES, 1);\n" },
    .{
        .anchor = "myl_block *myl_core_buffer_append_spelled(myl_block *buffer, const unsigned char *bytes, size_t length) {\n",
        .after = "    myl_count_event(MYL_COUNT_BUFFER_APPENDS, length);\n",
    },
    .{ .anchor = "    leak_report();\n    core_text_walk_report();\n", .before = "    myl_count_dump();\n" },
};

/// Why the counting runtime could not be made: an anchor is missing or not unique.
pub const Error = error{ OutOfMemory, AnchorMissing };

/// The counting runtime for `runtime`, the ordinary runtime source.
pub fn source(a: std.mem.Allocator, runtime: []const u8) Error![]u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, runtime);
    for (patches) |patch| {
        const at = std.mem.indexOf(u8, text.items, patch.anchor) orelse return error.AnchorMissing;
        if (std.mem.indexOfPos(u8, text.items, at + 1, patch.anchor) != null) return error.AnchorMissing;
        try text.insertSlice(a, at + patch.anchor.len, patch.after);
        try text.insertSlice(a, at, patch.before);
    }
    try text.append(a, '\n');
    try text.appendSlice(a, body);
    return text.toOwnedSlice(a);
}

/// The bytes `source` inserts into the runtime, for the test that every insertion applies.
pub const inserted: usize = blk: {
    var total: usize = 0;
    for (patches) |patch| total += patch.before.len + patch.after.len;
    break :blk total;
};

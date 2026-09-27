//! Generated per-type RC glue replaces runtime lookups on every hot operation.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;

const source =
    \\record Pair:
    \\    left: list[int]
    \\    right: bytes
    \\
    \\union Shape:
    \\    empty,
    \\    named: bytes,
    \\    points: list[int]
    \\
    \\record Holder:
    \\    rows: [3]list[int]
    \\    shape: Shape
    \\    count: int
    \\
    \\def first(pair: Pair) -> int:
    \\    return pair.left[0]
    \\
    \\def keep(items: list[int]) -> list[int]:
    \\    return items
    \\
    \\def make() -> Holder:
    \\    return Holder([[1], [2], [3]], Shape.points([4]), 3)
    \\
    \\def pairs() -> list[Pair]:
    \\    return [Pair([6], b"y")]
    \\
    \\def main() -> int:
    \\    pair = Pair([5], b"x")
    \\    holder = make()
    \\    kept = keep(holder.rows[1])
    \\    return first(pair) + kept[0] + holder.count + len(pairs())
;

const Manifest = struct { runtime_data: []const u8, functions: []const struct { name: []const u8, il: []const u8 } };

fn emitted(selection: runtime.Selection) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(selection);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_glue.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

fn allIl(manifest: Manifest) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    for (manifest.functions) |function| try text.appendSlice(t.allocator, function.il);
    return text.toOwnedSlice(t.allocator);
}

/// Compile the metadata unit against the runtime headers, as the native
/// build does, with the extra defines the selection implies.
fn compiles(data: []const u8, defines: []const []const u8) !bool {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    inline for (.{ "native_heap.h", "native_rc.h", "native_rc_internal.h", "native_rc_stats.h", "native_rc_values.h", "native_rc_alloc.h", "native_collections.h", "native_rc_collections.h", "qbe_runtime.h" }) |header| {
        try temporary.dir.writeFile(t.io, .{ .sub_path = header, .data = @embedFile(header) });
    }
    try temporary.dir.writeFile(t.io, .{ .sub_path = "glue.c", .data = data });
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(t.allocator);
    try argv.appendSlice(t.allocator, &.{ @import("native_test_options").zig_path, "cc", "-std=c11", "-Werror", "-O2", "-DMYL_NATIVE_RC=1" });
    try argv.appendSlice(t.allocator, defines);
    try argv.appendSlice(t.allocator, &.{ "-c", "glue.c", "-o", "glue.o" });
    const result = try std.process.run(t.allocator, t.io, .{ .argv = argv.items, .cwd = .{ .dir = temporary.dir } });
    defer t.allocator.free(result.stdout);
    defer t.allocator.free(result.stderr);
    const success = result.term == .exited and result.term.exited == 0;
    if (!success) try std.Io.File.stderr().writeStreamingAll(t.io, result.stderr);
    return success;
}

// spec: RC-GLUE-1
test "RC-GLUE-1 counted inline types get straight-line glue that compiles in both runtime modes" {
    var manifest = try emitted(.rc);
    defer manifest.deinit();
    const data = manifest.value.runtime_data;
    // Records flatten, fixed arrays loop and variants switch on their tag.
    try t.expect(contains(data, "_rcg_loan(myl_native_heap *heap, void *dst, const void *src)"));
    try t.expect(contains(data, "_rcg_unloan(myl_native_heap *heap, void *value)"));
    try t.expect(contains(data, "_rcg_retain(myl_native_heap *heap, void *dst, const void *src, unsigned region)"));
    try t.expect(contains(data, "_rcg_take(myl_native_heap *heap, void *dst, void *src, unsigned region)"));
    try t.expect(contains(data, "_rcg_drop(myl_native_heap *heap, void *value)"));
    try t.expect(contains(data, "for (size_t i"));
    try t.expect(contains(data, "switch (myl_rcg_tag("));
    // The per-type entries look nothing up and check no count limit.
    const entries = data[std.mem.indexOf(u8, data, "_rcg_loan(myl_native_heap").?..];
    try t.expect(!contains(entries, "COUNT_LIMIT"));
    try t.expect(!contains(entries, "myl_rc_descriptor_find"));
    try t.expect(contains(data, "if (died) myl_rc_drain(heap);"));
    try t.expect(contains(data, "#define MYL_RCG_INLINE static inline\n"));
    // List element glue exists only for types a collection stores.
    const sets = std.mem.count(u8, data, "_rcg_list_set(myl_native_heap");
    try t.expect(sets > 0 and sets < std.mem.count(u8, data, "_rcg_drop(myl_native_heap"));
    try t.expect(try compiles(data, &.{}));
    try t.expect(try compiles(data, &.{"-DMYL_NATIVE_RC_COUNTING=1"}));
}

/// Whether every inline glue branch tests a word computed at full width:
/// QBE's jnz reads only the low word of a pointer or a high mark bit.
fn fullWidthBranches(il: []const u8) bool {
    var lines = std.mem.splitScalar(u8, il, '\n');
    var previous: []const u8 = "";
    while (lines.next()) |line| {
        const inline_branch = std.mem.startsWith(u8, line, " jnz ") and std.mem.indexOf(u8, line, ", @rcg") != null;
        const guarded = std.mem.indexOf(u8, previous, " =w cnel ") != null or std.mem.indexOf(u8, previous, " =w ceql ") != null or
            std.mem.indexOf(u8, previous, " =w cultl ") != null;
        if (inline_branch and !guarded) return false;
        previous = line;
    }
    return true;
}

// spec-case: RC-GLUE-1
test "RC-GLUE-1 loans, retains and drops call glue instead of the runtime walkers" {
    var manifest = try emitted(.rc);
    defer manifest.deinit();
    const il = try allIl(manifest.value);
    defer t.allocator.free(il);
    try t.expect(!contains(il, "call $myl_rc_native_loan"));
    try t.expect(!contains(il, "call $myl_rc_native_retain"));
    try t.expect(!contains(il, "call $myl_rc_native_drop"));
    // One-word values keep their fast path inline: no glue call on success.
    try t.expect(contains(il, "@rcginc"));
    try t.expect(fullWidthBranches(il));
    try t.expect(contains(il, "_rcg_"));
}

// spec-case: RC-GLUE-1
test "RC-GLUE-1 counting builds keep every operation in the counting glue" {
    var manifest = try emitted(.rc_counting);
    defer manifest.deinit();
    const il = try allIl(manifest.value);
    defer t.allocator.free(il);
    try t.expect(!contains(il, "@rcginc"));
    try t.expect(contains(il, "_rcg_"));
    try t.expect(contains(manifest.value.runtime_data, "_rcg_drop("));
}

// spec-case: RC-GLUE-1
test "RC-GLUE-1 the traced runtime carries no glue" {
    var manifest = try emitted(.gc);
    defer manifest.deinit();
    try t.expect(!contains(manifest.value.runtime_data, "_rcg_"));
    const il = try allIl(manifest.value);
    defer t.allocator.free(il);
    try t.expect(!contains(il, "_rcg_"));
}

// spec-case: RC-GLUE-1
test "RC-GLUE-1 uniqueness checks skip their helper only for counted unshared payloads" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_glue_unique.my",
        \\def grow(items: mut list[list[int]]) -> None:
        \\    items[0].append(1)
        \\def main() -> int:
        \\    rows = [[0]]
        \\    grow(mut rows)
        \\    return len(rows[0])
    );
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    // Immortal, shared and arena marks (bits 1, 61 and 62) all keep the helper.
    try t.expect(contains(text, "@rcguniquecount"));
    try t.expect(contains(text, ", 6917529027641081858\\n"));
    try t.expect(contains(text, "myl_qbe_rc_unique_"));
}

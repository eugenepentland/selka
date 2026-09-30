//! Counted-artifact lowering of allocation-heavy paths: inline byte-buffer
//! appends, inline cell allocation and inline zeroing.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

/// The counted-artifact IL of one function in `source`; the caller frees it.
fn countedIl(source: []const u8, name: []const u8) ![]u8 {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_alloc.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    return t.allocator.dupe(u8, try named(manifest.value, name));
}

// spec: RC-BUFFER-APPEND-1
test "RC-BUFFER-APPEND-1 a counted byte-buffer append writes fitting octets inline after its uniqueness check" {
    const il = try countedIl(
        \\def build(n: i64) -> i64:
        \\    empty: list[i64] = []
        \\    buffer = byte_buffer(empty)
        \\    piece = b"mylang!\n"
        \\    for i in range(n):
        \\        _ = buffer.append_range(piece, 0, 8)
        \\    _ = buffer.append_byte(33)
        \\    return len(buffer)
        \\
        \\
        \\def main() -> i64:
        \\    return build(3)
    , "build");
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, il, "@buf_fast") != null);
    try t.expect(std.mem.indexOf(u8, il, "@byte_fast") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_native_bytes_copy_octets(") != null);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "=w call $myl_native_bytes_buffer_append_range("));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, "=w call $myl_native_bytes_buffer_append_byte("));
    // No root is ever published on a counted heap.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, "%root"));
}

const cell_source =
    \\record Node:
    \\    left: Option[Node]
    \\    right: Option[Node]
    \\
    \\
    \\def make(depth: int) -> Node:
    \\    if depth == 0:
    \\        return Node(left=None, right=None)
    \\    return Node(left=Some(make(depth - 1)), right=Some(make(depth - 1)))
    \\
    \\
    \\def main() -> int:
    \\    node = make(3)
    \\    return 0 if node.left is None else 1
;

// spec: RC-ALLOC-CACHE-1
test "RC-ALLOC-CACHE-1 a counted class body pops its size class's free slot inline and calls only on an empty list" {
    const il = try countedIl(cell_source, "make");
    defer t.allocator.free(il);

    // Each boxed `Some(...)` pops the 48-byte class's list inline (a 16-byte
    // payload behind the 24-byte prefix: list 2 at 5648 + 16) and keeps one
    // runtime fallback; a fresh constructor span may emit the pair twice.
    const pops = std.mem.count(u8, il, "\n@rccell_fast");
    try t.expect(pops >= 2);
    try t.expectEqual(pops, std.mem.count(u8, il, ", 5664\n"));
    try t.expectEqual(pops, std.mem.count(u8, il, "call $myl_native_heap_alloc(l %heap, "));
    // The counted prefix: one owner, no hold, a one-element mark.
    try t.expect(std.mem.indexOf(u8, il, " storew 1, %v") != null);
    try t.expect(std.mem.indexOf(u8, il, " storel 4, %v") != null);
    // The program opens no arena, so no region test is emitted.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, ", 112\n"));
}

// spec-case: RC-ALLOC-CACHE-1
test "RC-ALLOC-CACHE-1 counting builds and arena programs keep the runtime's counted allocation" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_alloc.my", cell_source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, text, "@rccell_fast"));
    runtime.set(.rc);
    const arena = try countedIl(
        \\record Box:
        \\    value: int
        \\    next: Option[Box]
        \\
        \\
        \\def fill(n: int) -> int:
        \\    total = 0
        \\    with arena():
        \\        chain = Box(value=n, next=Some(Box(value=1, next=None)))
        \\        total = chain.value
        \\    return total
        \\
        \\
        \\def main() -> int:
        \\    return fill(2)
    , "fill");
    defer t.allocator.free(arena);

    // An open arena takes the runtime call, which allocates in the arena.
    try t.expect(std.mem.indexOf(u8, arena, ", 112\n") != null);
    try t.expect(std.mem.indexOf(u8, arena, "\n@rccell_fast") != null);
}

// spec: RC-RANGE-KEY-1
test "RC-RANGE-KEY-1 a counted dictionary key slice borrows its text instead of building one" {
    const il = try countedIl(
        \\def frequencies(seq: str, k: int) -> dict[str, int]:
        \\    counts: dict[str, int] = {}
        \\    for i in range(len(seq) - k + 1):
        \\        key = seq[i:i + k]
        \\        counts[key] = counts.get(key, 0) + 1
        \\    return counts
        \\
        \\
        \\def main() -> int:
        \\    return len(frequencies("ACGTACGT", 2))
    , "frequencies");
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_text_range(") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_dictionary_read_range(") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_native_dictionary_write_range(") != null);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, "call $myl_native_text_slice("));
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, il, "call $myl_native_dictionary_write(l"));
    // The range local's span is stored with its counted value and read back.
    try t.expect(std.mem.indexOf(u8, il, " blit %rs") != null and std.mem.indexOf(u8, il, ", %rl") != null);
    try t.expect(std.mem.indexOf(u8, il, " blit %rl") != null);
}

// spec-case: RC-LAYOUT-1
// spec-case: RC-COUNTS-1
test "ABI4 generated increments are u32 and refuse saturation before storing a token" {
    const il = try countedIl(
        \\record Pair:
        \\    values: list[int]
        \\def keep(value: list[int], choose: bool) -> Pair:
        \\    return Pair(value) if choose else Pair([1])
        \\def main() -> int:
        \\    return len(keep([1, 2], True).values)
    , "keep");
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, il, " =w loaduw ") != null);
    try t.expect(std.mem.indexOf(u8, il, ", 4294967295\n") != null);
    try t.expect(std.mem.indexOf(u8, il, "@rcglimit") != null);
    try t.expect(std.mem.indexOf(u8, il, "$myl_qbe_rc_status(l %ctx, w 2)") != null);
    try t.expect(std.mem.indexOf(u8, il, " storew ") != null);
}

//! P1F-6 (B1): shared text caches publish after the pool starts; sequential lookups walk a bounded
//! number of octets; an owner that appends after a shared cursor grows its text; emitted code keeps
//! no atomic loads, so the zero-RC guard is unchanged.
const std = @import("std");
const native = @import("native_fixture.zig");
const support = @import("test_support.zig");
const zero_rc = @import("zero_rc.zig");
const source = @embedFile("shared_text_fixture.c");

fn exercise(a: std.mem.Allocator, sanitized: bool, mode: []const u8) native.Error!native.Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, source, .{ .sanitized = sanitized });
    return fixture.run(mode, "8");
}

// spec: SHARED-TEXT-CACHE-1
test "shared text sequential scalar lookups walk at most one text length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try exercise(arena.allocator(), false, "walk");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("plain=39998 shared=39998 octets for 20000 lookups\n", run.stdout);
}

// spec-case: SHARED-TEXT-CACHE-1
test "shared text hash scalar count and capacity cursor publish under ThreadSanitizer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try exercise(arena.allocator(), true, "concurrent");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("shared text caches: 8 workers, hash/scalars/cursor ok\n", run.stdout);
}

// spec-case: SHARED-TEXT-CACHE-1
test "an owner that appends after a shared cursor grows the text and its facts follow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try exercise(arena.allocator(), false, "owner");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("owner append: cursor grows the text, facts follow\n", run.stdout);
}

// spec-case: SHARED-TEXT-CACHE-1
test "emitted text hashing stays free of atomic loads so the zero-RC guard is unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmTextOfProject(arena.allocator(),
        \\func keyed(seq: str, at: int) -> int:
        \\    mut counts: dict[str, int] = {}
        \\    const key = copy(seq[at:at + 2])
        \\    counts[own key] = 1
        \\    return 1
        \\func main(out: Stream) -> int:
        \\    print(out, keyed("ééé", 1))
        \\    return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "load atomic") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%cached_hash = load i32, ptr %meta_at, align 4") != null);
    try std.testing.expect(zero_rc.emittedClean(text));
}

// spec-case: SHARED-TEXT-CACHE-1
test "the zero-RC guard still rejects an atomic i32 load in emitted code" {
    try std.testing.expect(!zero_rc.emittedClean("  %count = load atomic i32, ptr %count_at unordered, align 4\n"));
}

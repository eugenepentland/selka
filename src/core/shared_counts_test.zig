//! SHARED-COUNTS-1: boundary encodings, emitted dispatch and shared ownership.
const std = @import("std");
const driver = @import("driver.zig");
const support = @import("test_support.zig");
const counting = @import("count_runtime.zig");

const Error = error{ OutOfMemory, Unexpected, TestUnexpectedResult, TestExpectedEqual };

const harness =
    \\#include "core_rt.c"
    \\#include <pthread.h>
    \\#include <assert.h>
    \\static myl_block shared = {MYL_SHARED + 1, 0, 0, 0, 0};
    \\static myl_block saturated = {MYL_SATURATED - 100, 0, 0, 0, 0};
    \\static const myl_block immortal = {MYL_SATURATED, 0, 0, 0, 0};
    \\static void *count_worker(void *unused) {
    \\    (void)unused;
    \\    for (int i = 0; i < 200000; ++i) {
    \\        count_retain(&shared);
    \\        assert(!count_is_unique(&shared));
    \\        assert(!count_release(&shared));
    \\    }
    \\    for (int i = 0; i < 1000; ++i) {
    \\        count_retain(&saturated);
    \\        count_retain(&saturated);
    \\        assert(!count_release(&saturated));
    \\    }
    \\    return NULL;
    \\}
    \\int main(void) {
    \\    myl_block plain = {1, 0, 0, 0, 0};
    \\    assert(count_is_unique(&plain));
    \\    count_retain(&plain);
    \\    assert(plain.count == 2 && !count_is_unique(&plain));
    \\    assert(!count_release(&plain) && count_is_unique(&plain));
    \\    assert(count_release(&plain));
    \\    plain.count = MYL_PLAIN_MAX - 1;
    \\    count_retain(&plain);
    \\    assert(plain.count == MYL_PLAIN_MAX);
    \\    count_retain(&plain);
    \\    assert(plain.count == MYL_SATURATED);
    \\    count_retain(&plain);
    \\    assert(!count_release(&plain) && plain.count == MYL_SATURATED);
    \\    count_retain((myl_block *)&immortal);
    \\    myl_core_retain_slow((myl_block *)&immortal);
    \\    myl_core_release_slow((myl_block *)&immortal);
    \\    assert(!count_release((myl_block *)&immortal));
    \\    count_retain(NULL);
    \\    assert(!count_release(NULL));
    \\    pthread_t threads[8];
    \\    for (int i = 0; i < 8; ++i) assert(pthread_create(&threads[i], NULL, count_worker, NULL) == 0);
    \\    for (int i = 0; i < 8; ++i) assert(pthread_join(threads[i], NULL) == 0);
    \\    assert(shared.count == MYL_SHARED + 1 && !count_is_unique(&shared));
    \\    assert(count_release(&shared));
    \\    assert(saturated.count == MYL_SATURATED);
    \\    myl_block *head = myl_core_list_new_slow(1, 8), *tail = head;
    \\    for (int i = 0; i < 100000; ++i) {
    \\        myl_block *next = myl_core_list_new_slow(1, 8);
    \\        tail->count = MYL_SHARED + 1;
    \\        tail->reserved = (int64_t)(intptr_t)layout_blocks;
    \\        *(myl_block **)block_data(tail) = next;
    \\        tail->len = 1;
    \\        tail = next;
    \\    }
    \\    tail->count = MYL_SHARED + 1;
    \\    myl_block *copy = myl_core_list_copy(head, 8);
    \\    assert(count_is_unique(copy));
    \\    myl_core_release_slow(head);
    \\    myl_core_release(copy);
    \\    assert(live_count() == 0);
    \\    puts("shared counts ok");
    \\    return 0;
    \\}
;

fn runHarness(a: std.mem.Allocator) Error![]const u8 {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    dir.dir.writeFile(std.testing.io, .{ .sub_path = "core_rt.c", .data = driver.runtime_source }) catch return error.TestUnexpectedResult;
    dir.dir.writeFile(std.testing.io, .{ .sub_path = "harness.c", .data = harness }) catch return error.TestUnexpectedResult;
    const root = dir.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var env = try std.testing.environ.createMap(a);
    try env.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const source = try std.fs.path.join(a, &.{ root, "harness.c" });
    const binary = try std.fs.path.join(a, &.{ root, "harness" });
    const built = std.process.run(a, std.testing.io, .{ .argv = &.{ env.get("ZIG") orelse "zig", "cc", "-O2", "-std=c11", "-pthread", "-o", binary, source }, .environ_map = &env }) catch return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", built.stderr);
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = std.process.run(a, std.testing.io, .{ .argv = &.{binary} }) catch return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    return ran.stdout;
}

// spec: SHARED-COUNTS-1
test "shared counts saturate permanently, update atomically and free shared children iteratively" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("shared counts ok\n", try runHarness(arena.allocator()));
}

// spec-case: SHARED-COUNTS-1
test "shared count emission uses unordered reads, plain thresholds and cold helpers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(arena.allocator(),
        \\def held(xs: list[int]) -> list[int]:
        \\    return xs
        \\def changed(xs: list[int]) -> list[int]:
        \\    ys = xs
        \\    ys.append(1)
        \\    return ys
        \\def main(out: Stream) -> int:
        \\    xs = [1, 2]
        \\    out.print(changed(xs), held(xs), xs)
        \\    return 0
    , &refusal);
    const ran = try support.runOwned(arena.allocator(), &module, .{});
    const text = ran.llvm;
    try std.testing.expect(ran.status == 0);
    try std.testing.expect(std.mem.indexOf(u8, text, "load atomic i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "unordered, align 8, !tbaa !3, !range !8") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ", 2147483646\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, ", 2147483648\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call preserve_mostcc void @myl_core_retain_slow(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call preserve_mostcc void @myl_core_release_slow(ptr") != null);
}

// The compiler supplies the type checking: rename just myl_block.count, plus
// its sanctioned access sites. A new unsanctioned access fails C compilation,
// even through a typedef or a renamed pointer; unrelated .count fields survive.
fn guarded(a: std.mem.Allocator, source: []const u8) Error![]const u8 {
    var text = try std.mem.replaceOwned(u8, a, source, "    uint32_t count;\n    uint32_t kind;", "    uint32_t guarded_rc;\n    uint32_t kind;");
    const allowed = [_][]const u8{ "count_load", "myl_core_retain_slow", "count_release_shared", "count_retain", "count_release", "block_alloc" };
    for (allowed) |name| {
        const signature = try std.fmt.allocPrint(a, "{s}(", .{name});
        const start = std.mem.indexOf(u8, text, signature) orelse return error.TestUnexpectedResult;
        const open = std.mem.indexOfScalarPos(u8, text, start, '{') orelse return error.TestUnexpectedResult;
        const end = try bodyEnd(text, open);
        const changed = try std.mem.replaceOwned(u8, a, text[open..end], "->count", "->guarded_rc");
        text = try std.mem.concat(a, u8, &.{ text[0..open], changed, text[end..] });
    }
    return text;
}

fn bodyEnd(text: []const u8, start: usize) Error!usize {
    var depth: usize = 0;
    var at = start;
    while (at < text.len) : (at += 1) {
        if (text[at] == '"' or text[at] == '\'') {
            const quote = text[at];
            at += 1;
            while (at < text.len and text[at] != quote) : (at += 1) {
                if (text[at] == '\\') at += 1;
            }
        } else if (std.mem.startsWith(u8, text[at..], "/*")) {
            at = (std.mem.indexOfPos(u8, text, at + 2, "*/") orelse return error.TestUnexpectedResult) + 1;
        } else if (std.mem.startsWith(u8, text[at..], "//")) {
            at = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse return error.TestUnexpectedResult;
        } else if (text[at] == '{') {
            depth += 1;
        } else if (text[at] == '}') {
            depth -= 1;
            if (depth == 0) return at + 1;
        }
    }
    return error.TestUnexpectedResult;
}

fn compiles(a: std.mem.Allocator, source: []const u8, expect_success: bool) Error!bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    dir.dir.writeFile(std.testing.io, .{ .sub_path = "guard.c", .data = source }) catch return error.TestUnexpectedResult;
    const root = dir.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var env = try std.testing.environ.createMap(a);
    try env.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const input = try std.fs.path.join(a, &.{ root, "guard.c" });
    const output = try std.fs.path.join(a, &.{ root, "guard.o" });
    const built = std.process.run(a, std.testing.io, .{ .argv = &.{ env.get("ZIG") orelse "zig", "cc", "-std=c11", "-c", input, "-o", output }, .environ_map = &env }) catch return error.TestUnexpectedResult;
    if (expect_success) try std.testing.expectEqualStrings("", built.stderr);
    return built.term == .exited and built.term.exited == 0;
}

// spec-case: SHARED-COUNTS-1
test "shared count source guard permits only typed helper and initialization accesses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try guarded(a, driver.runtime_source);
    const counted = try guarded(a, try counting.source(a, driver.runtime_source));
    const invalid = try std.mem.concat(a, u8, &.{ source, "\nvoid illegal_count(myl_block *alias) { ++alias->count; }\n" });
    try std.testing.expect(try compiles(a, source, true));
    try std.testing.expect(try compiles(a, counted, true));
    try std.testing.expect(!try compiles(a, invalid, false));
}

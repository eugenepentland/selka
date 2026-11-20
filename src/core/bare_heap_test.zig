//! The bare runtime's two arenas (`runtime/bare/core_bare_heap.c`, MCU-CORE1): `malloc` and `free` work in the arena of
//! the calling core (`bare_arena_here`), so a block core 1 allocates is in core 1's arena, core 0's arena is untouched
//! while core 1 fills its own, and a block freed on the core that did not allocate it is refused, not linked into the
//! wrong list. The file is compiled for the host here with a stand-in for the core's number (on the device it is the
//! RP2040's SIO CPUID, `core_bare_cores.c`).
const std = @import("std");
const native = @import("native_fixture.zig");

const harness =
    \\#define MYL_BARE_CORES 1
    \\#include <stdbool.h>
    \\#include <stddef.h>
    \\#include <stdint.h>
    \\#include <stdio.h>
    \\#include <string.h>
    \\static unsigned fake_core;
    \\#include "core_bare_heap.c"
    \\static unsigned bare_core(void) { return fake_core; }
    \\static _Alignas(32) unsigned char memory[2][4096];
    \\static int inside(const void *data, unsigned arena) {
    \\    const unsigned char *at = data;
    \\    return at >= memory[arena] && at < memory[arena] + sizeof memory[arena];
    \\}
    \\int main(void) {
    \\    for (unsigned core = 0; core < 2; ++core)
    \\        printf("arena %u holds %llu bytes\n", core, (unsigned long long)bare_arena_init(&bare_arenas[core], (uintptr_t)memory[core], (uintptr_t)memory[core] + sizeof memory[core]));
    \\    fake_core = 0;
    \\    void *first = malloc_stand_in(100);
    \\    fake_core = 1;
    \\    void *second = malloc_stand_in(100);
    \\    printf("core 0's block is in arena 0: %d; core 1's block is in arena 1: %d\n", inside(first, 0), inside(second, 1));
    \\    printf("core 1 frees core 0's block: %d\n", bare_arena_free(bare_arena_here(), first));
    \\    fake_core = 0;
    \\    printf("core 0 frees it: %d\n", bare_arena_free(bare_arena_here(), first));
    \\    const uint32_t largest = bare_arena_largest(bare_arena_here());
    \\    fake_core = 1;
    \\    int blocks = 0, own = 1;
    \\    for (void *block; (block = malloc_stand_in(200)) != NULL; ++blocks) own &= inside(block, 1);
    \\    printf("core 1 filled its arena with %d blocks, all in arena 1: %d\n", blocks, own);
    \\    fake_core = 0;
    \\    printf("core 0's largest free block is unchanged: %d\n", bare_arena_largest(bare_arena_here()) == largest);
    \\    void *third = malloc_stand_in(100);
    \\    printf("core 0 still allocates in arena 0: %d\n", inside(third, 0));
    \\    fake_core = 1;
    \\    printf("core 1 frees its block: %d\n", bare_arena_free(bare_arena_here(), second));
    \\    return 0;
    \\}
    \\
;

test "the bare runtime allocates and frees in the calling core's arena, and refuses a block of the other core's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    // `malloc` itself is core_bare.c's (it would replace the host's): the harness calls what it calls.
    const source = try std.mem.concat(a, u8, &.{ "#define malloc_stand_in(bytes) bare_arena_alloc(bare_arena_here(), (bytes))\n", harness });
    const output = try native.buildProgram(a, root, .{
        .source = source,
        .binary_name = "arenas",
        .source_name = "arenas.c",
        .runtime_name = "core_bare_heap.c",
        .runtime = @embedFile("runtime/bare/core_bare_heap.c"),
    });
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .cwd = .{ .path = root } });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(
        \\arena 0 holds 4032 bytes
        \\arena 1 holds 4032 bytes
        \\core 0's block is in arena 0: 1; core 1's block is in arena 1: 1
        \\core 1 frees core 0's block: 0
        \\core 0 frees it: 1
        \\core 1 filled its arena with 17 blocks, all in arena 1: 1
        \\core 0's largest free block is unchanged: 1
        \\core 0 still allocates in arena 0: 1
        \\core 1 frees its block: 1
        \\
    , ran.stdout);
}

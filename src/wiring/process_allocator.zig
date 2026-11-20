//! The release compiler's allocator (L1R12-ALLOC-1): Zig's `SmpAllocator` for small blocks, and a bounded pool of freed mappings for large ones.
//!
//! `SmpAllocator` serves a block over 32 KiB with a mapping of its own and unmaps it on `free`. A build makes about 700 such blocks, frees most
//! of them before it ends, and asks for the next of nearly the same size, so every reuse pays the kernel twice: `munmap` of pages it zeroed and
//! faulted in a moment ago, and a fresh fault, about 1 us, for each page of the next block. Here a freed mapping of at most `pooled_limit` bytes
//! is kept by size class and handed to the next request of its class with its pages still resident, until `pool_cap` bytes are kept. A class is
//! a page count rounded up to a quarter of its power of two (at most 25% more than the request; the unused tail is address space no one
//! touches). Larger blocks keep the page allocator's exact mappings. A reused block holds what its last user left in it, like any block
//! `SmpAllocator` recycles from a free list; no caller may assume fresh memory is zero.
//!
//! Measured (L1r12, 99k and 400k one-line edits, paired on the P cores): page faults -10..-13%, kernel cycles -9..-13%, task-clock -4..-11%,
//! peak resident memory +8 MB at 99k and at 400k. Populating fresh mappings (`MADV_POPULATE_WRITE`) made a build 3-6% slower (the unused part of
//! a capacity is populated too), and `MADV_HUGEPAGE` made the kernel's half 60% slower on a host whose free memory is fragmented.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const PageAllocator = std.heap.PageAllocator; // allocator-ok: large mappings are this allocator's business

/// The largest block `SmpAllocator` serves from its size classes; anything larger is a mapping.
const small_limit: usize = 32 * 1024;
/// The page size of the targets this runs on (amd64 Linux).
const page: usize = 4096;
/// Freed mappings larger than this are returned to the kernel at once.
const pooled_limit: usize = 4 * 1024 * 1024;
/// The most address space the pool keeps.
const pool_cap: usize = 64 * 1024 * 1024;
/// Size classes: four per power of two of pages, from 2^3 pages up to `pooled_limit` (class 28 is the limit itself).
const class_count: usize = 29;

/// A pooled mapping: the pool stores its link in the block's first bytes.
const Block = struct { next: ?*Block };

/// The freed mappings kept for reuse, by class, and the address space they hold. One per process; tests make their own.
pub const Pool = struct {
    lock: std.atomic.Mutex = .unlocked,
    classes: [class_count]?*Block = @splat(null),
    bytes: usize = 0,

    /// The allocator interface over this pool and `SmpAllocator`.
    pub fn allocator(self: *Pool) Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn acquire(self: *Pool) void {
        var spins: u32 = 0;
        while (!self.lock.tryLock()) {
            spins += 1;
            if (spins % 64 == 0) std.Thread.yield() catch std.atomic.spinLoopHint() else std.atomic.spinLoopHint();
        }
    }
};

/// The process's pool.
var process_pool: Pool = .{};

/// The compiler process's allocator: the process pool over `SmpAllocator`.
pub fn allocator() Allocator {
    return process_pool.allocator();
}

const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

/// Bytes a pooled block of `len` bytes maps: pages rounded up to a quarter of their power of two.
fn classBytes(len: usize) usize {
    const pages = (len + page - 1) / page;
    const top: usize = @as(usize, 1) << @intCast(std.math.log2_int(usize, pages));
    const step = @max(top / 4, 1);
    return (pages + step - 1) / step * step * page;
}

/// The pool class of a mapping size produced by `classBytes`.
fn classOf(bytes: usize) usize {
    const pages = bytes / page;
    const octave = std.math.log2_int(usize, pages);
    const step = @max((@as(usize, 1) << @intCast(octave)) / 4, 1);
    return (octave - 3) * 4 + (pages / step - 4);
}

fn isLarge(len: usize) bool {
    return len > small_limit;
}

fn pooled(len: usize, alignment: Alignment) bool {
    return len <= pooled_limit and alignment.toByteUnits() <= page;
}

/// The bytes a block of `len` bytes maps: its class when pooled, else whole pages. A pure function of the block's length, so every operation agrees on it.
fn mappedFor(len: usize, alignment: Alignment) usize {
    return if (pooled(len, alignment)) classBytes(len) else std.mem.alignForward(usize, len, page);
}

fn alloc(context: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    if (!isLarge(len)) return std.heap.smp_allocator.rawAlloc(len, alignment, ra); // allocator-ok
    const self: *Pool = @ptrCast(@alignCast(context));
    const bytes = mappedFor(len, alignment);
    if (pooled(len, alignment)) {
        const class = classOf(bytes);
        self.acquire();
        const block = self.classes[class];
        if (block) |b| {
            self.classes[class] = b.next;
            self.bytes -= bytes;
        }
        self.lock.unlock();
        if (block) |b| return @ptrCast(b);
    }
    return PageAllocator.map(bytes, alignment);
}

fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    if (!isLarge(memory.len)) {
        if (isLarge(new_len)) return false;
        return std.heap.smp_allocator.rawResize(memory, alignment, new_len, ra); // allocator-ok
    }
    if (!isLarge(new_len)) return false;
    return move(memory, alignment, new_len, false) != null;
}

fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    if (!isLarge(memory.len)) {
        if (isLarge(new_len)) return null;
        return std.heap.smp_allocator.rawRemap(memory, alignment, new_len, ra); // allocator-ok
    }
    if (!isLarge(new_len)) return null;
    return move(memory, alignment, new_len, true);
}

/// Grow or shrink a large block through its mapping: in place within its mapped size, else by `mremap` (which keeps the pages already touched).
fn move(memory: []u8, alignment: Alignment, new_len: usize, may_move: bool) ?[*]u8 {
    const old_bytes = mappedFor(memory.len, alignment);
    const new_bytes = mappedFor(new_len, alignment);
    if (old_bytes == new_bytes) return memory.ptr;
    return PageAllocator.realloc(memory.ptr[0..old_bytes], alignment, new_bytes, may_move);
}

fn free(context: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    if (!isLarge(memory.len)) return std.heap.smp_allocator.rawFree(memory, alignment, ra); // allocator-ok
    const self: *Pool = @ptrCast(@alignCast(context));
    const bytes = mappedFor(memory.len, alignment);
    if (pooled(memory.len, alignment)) {
        const class = classOf(bytes);
        self.acquire();
        if (self.bytes + bytes <= pool_cap) {
            const block: *Block = @ptrCast(@alignCast(memory.ptr));
            block.next = self.classes[class];
            self.classes[class] = block;
            self.bytes += bytes;
            self.lock.unlock();
            return;
        }
        self.lock.unlock();
    }
    PageAllocator.unmap(@alignCast(memory.ptr[0..bytes]));
}

test "a freed large block is handed to the next request of its class with its pages" {
    var pool: Pool = .{};
    const a = pool.allocator();
    // The raw interface: `Allocator.free` fills a freed block with undefined bytes in a Debug build, which would hide what the pool keeps.
    const first = a.rawAlloc(100 * 1024, .@"1", 0) orelse return error.OutOfMemory;
    first[4096] = 7;
    a.rawFree(first[0 .. 100 * 1024], .@"1", 0);
    const second = a.rawAlloc(101 * 1024, .@"1", 0) orelse return error.OutOfMemory;
    defer a.rawFree(second[0 .. 101 * 1024], .@"1", 0);
    try std.testing.expectEqual(@intFromPtr(first), @intFromPtr(second));
    // Past the pool's link in the first bytes, the pages keep what they held.
    try std.testing.expectEqual(@as(u8, 7), second[4096]);
}

test "classes round up by a quarter of the power of two and never shrink a request" {
    try std.testing.expectEqual(@as(usize, 40 * 1024), classBytes(32 * 1024 + 1));
    try std.testing.expectEqual(@as(usize, 1280 * 1024), classBytes(1025 * 1024));
    try std.testing.expectEqual(classOf(classBytes(33 * 1024)) + 1, classOf(classBytes(41 * 1024)));
    try std.testing.expectEqual(class_count - 1, classOf(classBytes(pooled_limit)));
    try std.testing.expectEqual(@as(usize, 5 * 1024 * 1024), mappedFor(5 * 1024 * 1024, .@"1"));
}

test "a block grows and shrinks across classes and across the pooled limit with its bytes intact" {
    var pool: Pool = .{};
    const a = pool.allocator();
    var block = try a.alloc(u8, 40 * 1024);
    @memset(block, 3);
    block = a.remap(block, 400 * 1024) orelse try a.realloc(block, 400 * 1024);
    try std.testing.expectEqual(@as(u8, 3), block[40 * 1024 - 1]);
    block = a.remap(block, 6 * 1024 * 1024) orelse try a.realloc(block, 6 * 1024 * 1024);
    try std.testing.expectEqual(@as(u8, 3), block[0]);
    block = a.remap(block, 100 * 1024) orelse try a.realloc(block, 100 * 1024);
    try std.testing.expectEqual(@as(u8, 3), block[40 * 1024 - 1]);
    a.free(block);
}

test "a block does not move between the small and the large allocator in place" {
    var pool: Pool = .{};
    const a = pool.allocator();
    const small = try a.alloc(u8, 1000);
    try std.testing.expect(!a.resize(small, 100 * 1024));
    try std.testing.expect(a.remap(small, 100 * 1024) == null);
    a.free(small);
    const large = try a.alloc(u8, 100 * 1024);
    try std.testing.expect(!a.resize(large, 1000));
    a.free(large);
}

test "the pool keeps every large block intact under concurrent allocate, remap and free" {
    var pool: Pool = .{};
    var failures: std.atomic.Value(usize) = .init(0);
    try runChurn(pool.allocator(), &failures);
    try std.testing.expectEqual(@as(usize, 0), failures.load(.acquire));
}

/// Four threads churn through `a` at once and finish before this returns.
fn runChurn(a: Allocator, failures: *std.atomic.Value(usize)) !void {
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, churn, .{ a, index, failures });
    for (threads) |thread| thread.join();
}

/// One thread's share: keep up to 16 live large blocks, each filled with its own byte; every step verifies and frees one, or allocates or remaps one.
fn churn(a: Allocator, seed: usize, failures: *std.atomic.Value(usize)) void {
    var slots: [16][]u8 = @splat(&.{});
    var state: usize = seed *% 2654435761 +% 1;
    for (0..600) |_| {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        const index = (state >> 20) % slots.len;
        const choice = (state >> 40) % 4;
        const size = 33 * 1024 + (state >> 8) % (3 * 1024 * 1024);
        const fill: u8 = @truncate(index + seed);
        const block = slots[index];
        for (block) |byte| if (byte != fill) {
            _ = failures.fetchAdd(1, .monotonic);
            break;
        };
        if (block.len != 0 and choice == 0) {
            a.free(block);
            slots[index] = &.{};
        } else if (block.len != 0 and choice == 1) {
            // A refused remap leaves the block where it is; the next visit verifies it.
            const grown = a.remap(block, size) orelse continue;
            slots[index] = grown;
            @memset(grown, fill);
        } else {
            if (block.len != 0) a.free(block);
            const fresh = a.alloc(u8, size) catch {
                _ = failures.fetchAdd(1, .monotonic);
                return;
            };
            @memset(fresh, fill);
            slots[index] = fresh;
        }
    }
    for (slots) |block| if (block.len != 0) a.free(block);
}

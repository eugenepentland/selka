//! A bump arena that reserves no more address space than it hands out, give or
//! take one chunk (ARENA-BOUNDED-1).
//!
//! `std.heap.ArenaAllocator` makes each new node half again the size of the
//! last one. A project arena that reaches gigabytes therefore reserves its
//! newest node, most of it untouched, at half of everything before it: a cold
//! million-line check had 4.2 GB resident when its next node (3.3 GB) crossed the
//! compiler's 8 GiB address-space ceiling. Untouched pages cost no memory, but
//! the ceiling counts them, so the compiler failed with half its budget unused.
//!
//! Here shared chunks grow the same way only up to `chunk_limit`, and an
//! allocation of `dedicated_bytes` or more gets a mapping of its own from the
//! child allocator. Such an allocation — a program-wide list, typically — also
//! grows through the child's `remap` (an `mremap` for the page allocator)
//! instead of being copied into a new chunk, and a `free` returns it. So the
//! reserved-but-untouched remainder is at most one chunk, and large lists that
//! grow and move leave no dead copies behind.
//!
//! The state lives behind one pointer, so a copied owner (a project value
//! copied for a snapshot) keeps allocating from the same arena. Not
//! thread-safe: the frontend that owns a project runs on one thread.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

/// The largest shared chunk: the most address space the arena holds untouched.
pub const chunk_limit: usize = 64 * 1024 * 1024;
/// Allocations at least this large get a mapping of their own.
pub const dedicated_bytes: usize = 4 * 1024 * 1024;
/// The first shared chunk; later ones grow by half until `chunk_limit`.
const first_chunk: usize = 64 * 1024;
/// The alignment every dedicated mapping is requested with.
const dedicated_alignment: Alignment = .@"16";

/// One shared chunk: this header, then the bytes bumped out of it.
const Chunk = struct {
    next: ?*Chunk,
    /// Bytes of the whole chunk, header included, as the child allocated it.
    len: usize,
    /// Offset of the next free byte from the chunk's start.
    end: usize,

    fn base(self: *Chunk) [*]u8 {
        return @ptrCast(self);
    }
};

/// Everything the arena holds, allocated once from the child.
const State = struct {
    chunks: ?*Chunk = null,
    /// Dedicated allocations by address, with their current lengths.
    dedicated: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    /// Bytes held from the child: every chunk plus every dedicated allocation.
    reserved: usize = 0,
};

/// A single-threaded arena over `child_allocator`; `deinit` releases everything.
pub const ChunkedArena = struct {
    child_allocator: Allocator,
    state: ?*State = null,

    /// An empty arena that allocates its chunks from `child_allocator`.
    pub fn init(child_allocator: Allocator) ChunkedArena {
        return .{ .child_allocator = child_allocator };
    }

    /// Return every chunk and dedicated allocation to the child allocator.
    pub fn deinit(self: *ChunkedArena) void {
        const state = self.state orelse return;
        var it = state.chunks;
        while (it) |chunk| {
            it = chunk.next;
            self.child_allocator.rawFree(chunk.base()[0..chunk.len], .of(Chunk), @returnAddress());
        }
        var entries = state.dedicated.iterator();
        while (entries.next()) |entry| {
            const ptr: [*]u8 = @ptrFromInt(entry.key_ptr.*);
            self.child_allocator.rawFree(ptr[0..entry.value_ptr.*], dedicated_alignment, @returnAddress());
        }
        state.dedicated.deinit(self.child_allocator);
        self.child_allocator.destroy(state);
        self.state = null;
    }

    /// Bytes currently held from the child allocator, chunks and dedicated mappings together.
    pub fn reserved(self: ChunkedArena) usize {
        return if (self.state) |state| state.reserved else 0;
    }

    /// The allocator interface over this arena.
    pub fn allocator(self: *ChunkedArena) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn held(self: *ChunkedArena) ?*State {
        if (self.state) |state| return state;
        const state = self.child_allocator.create(State) catch return null;
        state.* = .{};
        self.state = state;
        return state;
    }

    fn shared(self: *ChunkedArena, state: *State, n: usize, alignment: Alignment) ?[*]u8 {
        if (state.chunks) |chunk| {
            const start = alignment.forward(@intFromPtr(chunk.base()) + chunk.end) - @intFromPtr(chunk.base());
            if (start + n <= chunk.len) {
                chunk.end = start + n;
                return chunk.base() + start;
            }
        }
        const previous = if (state.chunks) |chunk| chunk.len else first_chunk / 2;
        const needed = @sizeOf(Chunk) + alignment.toByteUnits() + n;
        const len = @max(needed, @min(chunk_limit, previous + previous / 2));
        const raw = self.child_allocator.rawAlloc(len, .of(Chunk), @returnAddress()) orelse return null;
        const chunk: *Chunk = @ptrCast(@alignCast(raw));
        chunk.* = .{ .next = state.chunks, .len = len, .end = @sizeOf(Chunk) };
        state.chunks = chunk;
        state.reserved += len;
        return self.shared(state, n, alignment);
    }

    /// Whether an allocation of `n` bytes at `alignment` gets its own mapping.
    fn dedicated(n: usize, alignment: Alignment) bool {
        return n >= dedicated_bytes and alignment.compare(.lte, dedicated_alignment);
    }

    fn alloc(context: *anyopaque, n: usize, alignment: Alignment, _: usize) ?[*]u8 {
        const self: *ChunkedArena = @ptrCast(@alignCast(context));
        const state = self.held() orelse return null;
        if (!dedicated(n, alignment)) return self.shared(state, n, alignment);
        state.dedicated.ensureUnusedCapacity(self.child_allocator, 1) catch return null;
        const ptr = self.child_allocator.rawAlloc(n, dedicated_alignment, @returnAddress()) orelse return null;
        state.dedicated.putAssumeCapacityNoClobber(@intFromPtr(ptr), n);
        state.reserved += n;
        return ptr;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        const self: *ChunkedArena = @ptrCast(@alignCast(context));
        const state = self.state.?;
        if (state.dedicated.getPtr(@intFromPtr(memory.ptr))) |len| {
            if (!self.child_allocator.rawResize(memory.ptr[0..len.*], dedicated_alignment, new_len, @returnAddress())) return false;
            state.reserved = state.reserved - len.* + new_len;
            len.* = new_len;
            return true;
        }
        if (new_len <= memory.len) {
            // Shrinking always succeeds; only the newest allocation gives bytes back.
            if (last(state, memory)) |chunk| chunk.end -= memory.len - new_len;
            return true;
        }
        // A shared allocation grows in place only while it stays below the
        // dedicated size; past it the caller moves it to a mapping of its own.
        if (dedicated(new_len, alignment)) return false;
        const chunk = last(state, memory) orelse return false;
        const start = @intFromPtr(memory.ptr) - @intFromPtr(chunk.base());
        if (start + new_len > chunk.len) return false;
        chunk.end = start + new_len;
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *ChunkedArena = @ptrCast(@alignCast(context));
        const state = self.state.?;
        const key = @intFromPtr(memory.ptr);
        const len = state.dedicated.get(key) orelse return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
        const moved = self.child_allocator.rawRemap(memory.ptr[0..len], dedicated_alignment, new_len, @returnAddress()) orelse return null;
        _ = state.dedicated.remove(key);
        state.dedicated.putAssumeCapacityNoClobber(@intFromPtr(moved), new_len);
        state.reserved = state.reserved - len + new_len;
        return moved;
    }

    fn free(context: *anyopaque, memory: []u8, _: Alignment, _: usize) void {
        const self: *ChunkedArena = @ptrCast(@alignCast(context));
        const state = self.state.?;
        if (state.dedicated.fetchRemove(@intFromPtr(memory.ptr))) |entry| {
            self.child_allocator.rawFree(memory.ptr[0..entry.value], dedicated_alignment, @returnAddress());
            state.reserved -= entry.value;
            return;
        }
        const chunk = last(state, memory) orelse return;
        chunk.end -= memory.len;
    }
};

/// The newest chunk when `memory` is the last allocation bumped out of it.
fn last(state: *State, memory: []u8) ?*Chunk {
    const chunk = state.chunks orelse return null;
    return if (chunk.base() + chunk.end == memory.ptr + memory.len) chunk else null;
}

fn fill(a: Allocator) !void {
    var list: std.ArrayList(u64) = .empty;
    for (0..3_000_000) |i| try list.append(a, i);
    for (0..20_000) |i| _ = try a.alloc(u8, 100 + i % 900);
    try std.testing.expectEqual(@as(u64, 2_999_999), list.items[list.items.len - 1]);
}

// spec: ARENA-BOUNDED-1
test "the chunked arena reserves at most one chunk beyond what it holds and returns what large lists leave behind" {
    var arena = ChunkedArena.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try fill(a);
    const state = arena.state.?;
    // A 24 MB list grown one element at a time stays one dedicated mapping:
    // every earlier capacity was remapped or freed, not left in a chunk.
    try std.testing.expectEqual(@as(usize, 1), state.dedicated.count());
    var chunked: usize = 0;
    var it = state.chunks;
    while (it) |chunk| : (it = chunk.next) {
        try std.testing.expect(chunk.len <= chunk_limit);
        chunked += chunk.len;
    }
    var lists = state.dedicated.valueIterator();
    try std.testing.expectEqual(arena.reserved(), chunked + lists.next().?.*);
    // Twenty thousand small allocations and the list's small early capacities
    // fit in chunks totalling well under two of the largest.
    try std.testing.expect(chunked < 2 * chunk_limit);
    // A copy of the owner allocates from the same arena.
    var copy = arena;
    const shared_bytes = try copy.allocator().alloc(u8, 64);
    try std.testing.expectEqual(state.chunks.?.base() + state.chunks.?.end, shared_bytes.ptr + shared_bytes.len);
    // Freeing the most recent small allocation hands its bytes back to the chunk.
    const newest = state.chunks.?.end;
    const extra = try a.alloc(u8, 64);
    a.free(extra);
    try std.testing.expectEqual(newest, state.chunks.?.end);
    // A large allocation freed is returned to the child allocator at once.
    const big = try a.alloc(u8, dedicated_bytes);
    const before = arena.reserved();
    a.free(big);
    try std.testing.expectEqual(before - dedicated_bytes, arena.reserved());
}

// spec-case: ARENA-BOUNDED-1
test "the chunked arena cleans up under allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(child: Allocator) !void {
            var arena = ChunkedArena.init(child);
            defer arena.deinit();
            const a = arena.allocator();
            const small = try a.alloc(u8, 100);
            const large = try a.alloc(u8, dedicated_bytes + 1);
            const grown = try a.realloc(large, 2 * dedicated_bytes);
            try std.testing.expectEqual(@as(usize, 100), small.len);
            try std.testing.expectEqual(2 * dedicated_bytes, grown.len);
        }
    }.run, .{});
}

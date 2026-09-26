//! Inline allocation of `class` bodies and the generational store barrier.
//!
//! A class body whose size is known at compile time and fits one of the
//! runtime's small size classes is allocated without a runtime call on the
//! common path: generated code bumps the cursor of the heap's per-class inline
//! window (`myl_native_heap.inline_windows`) over one prepaid slot, writes the
//! two header words and zeroes the payload. Only an exhausted window calls
//! `myl_native_heap_alloc_small`, which collects, charges and refuses exactly
//! where the ordinary path would and opens the next window. The slow call is
//! the only safepoint, so the root protocol is emitted on that branch alone.
//!
//! A store into an existing class body runs the barrier: when the body is old
//! (its mark bit is set) `myl_native_heap_remember` clears the bit and records
//! the body, so the next minor collection traces it.
const std = @import("std");
const typed = @import("typed.zig");
const allocation_failure = @import("qbe_format.zig").allocation_failure;
/// Errors reported while emitting native allocation.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Strides of the size classes generated code allocates from inline: the first
/// `MYL_NATIVE_INLINE_CLASSES` entries of `class_strides` in `src/native_heap.c`.
/// A test below reads that table and fails when the two drift apart.
pub const inline_class_strides = [_]u64{ 16, 32, 48, 64, 80, 96, 112, 128, 160, 192, 224, 256 };
/// Frozen byte offset of `myl_native_heap.inline_windows` — one `{cursor,
/// limit}` pair per inline class — matched by the `_Static_assert` on
/// `MYL_NATIVE_HEAP_INLINE_OFFSET` in `src/native_heap.c`.
pub const heap_inline_offset: u64 = 1280;
/// Frozen byte offset of `myl_native_heap.arena_window` — `{cursor, limit}`
/// followed by the one-element mark word — matched by the `_Static_assert`s on
/// `MYL_NATIVE_HEAP_ARENA_OFFSET` in `src/native_heap.c`.
pub const heap_arena_offset: u64 = 1472;
/// Two-word object header in front of every managed payload.
const header_bytes: u64 = 16;
/// Mark word of a fresh one-element tracing-heap object: count 1 above the two
/// flag bits (`MYL_NATIVE_OBJECT_COUNT_SHIFT`), unmarked.
const one_element_mark: u64 = 1 << 2;

/// The inline size class holding one object of `payload` bytes behind its
/// header, or null when the object is too large to allocate inline.
pub fn inlineClass(payload: u64) ?usize {
    if (payload > std.math.maxInt(u64) - header_bytes - 15) return null;
    const stride = (header_bytes + payload + 15) & ~@as(u64, 15);
    for (inline_class_strides, 0..) |candidate, index| if (candidate >= stride) return index;
    return null;
}

/// Allocate one zeroed class body for `ty` and return the temporary holding its
/// payload address. `stack` is the operand stack at the constructor, which the
/// slow path roots.
pub fn cell(comptime E: type, self: E, ty: typed.Type, stack: []const typed.Type) Error!usize {
    const body = self.layouts.heapLayout(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    const size = body.size;
    const aligned = body.alignment <= header_bytes;
    self.layouts.releaseLayout(body);
    const descriptor = try self.descriptor(ty);
    const pointer = self.temp();
    const class_index = (if (aligned and !@import("runtime_mode.zig").enabled()) inlineClass(size) else null) orelse {
        try self.print(" %v{d} =l call $myl_native_heap_alloc(l %heap, l extern ${s}_body, l 1)\n", .{ pointer, descriptor });
        try self.require(pointer, allocation_failure);
        return pointer;
    };
    const label = self.temp();
    const window = self.temp();
    const cursor = self.temp();
    const limit_slot = self.temp();
    const limit = self.temp();
    const next = self.temp();
    const fits = self.temp();
    try heapField(E, self, window, heap_inline_offset + 16 * class_index);
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, 8\n %v{d} =l loadl %v{d}\n", .{ cursor, window, limit_slot, window, limit, limit_slot });
    // An empty window is two null words, so the bumped cursor never fits it.
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l culel %v{d}, %v{d}\n", .{ next, cursor, inline_class_strides[class_index], fits, next, limit });
    try self.print(" jnz %v{d}, @cell_fast{d}, @cell_slow{d}\n@cell_slow{d}\n", .{ fits, label, label, label });
    if (self.arenas) try arenaBump(E, self, .{ .pointer = pointer, .label = label, .size = size, .descriptor = descriptor });
    const pushed = try self.roots(stack);
    try self.print(" %v{d} =l call $myl_native_heap_alloc_small(l %heap, l extern ${s}_body, l {d})\n", .{ pointer, descriptor, class_index });
    try self.require(pointer, allocation_failure);
    if (pushed) try self.restoreRoots();
    try self.print(" jmp @cell_done{d}\n@cell_fast{d}\n", .{ label, label });
    try self.markObject(cursor);
    const element = self.temp();
    try self.print(" storel %v{d}, %v{d}\n storel {d}, %v{d}\n", .{ next, window, one_element_mark, cursor });
    try self.print(" %v{d} =l add %v{d}, 8\n storel extern ${s}_body, %v{d}\n %v{d} =l add %v{d}, {d}\n", .{ element, cursor, descriptor, element, pointer, cursor, header_bytes });
    try zeroPayload(E, self, pointer, size);
    try self.print("@cell_done{d}\n", .{label});
    try self.markObject(pointer);
    self.inline_roots = true;
    return pointer;
}

/// Compute the address of the heap field at `offset` into `%v{target}`. The
/// heap pointer is copied first: the emitter drops every `=l add %heap, `
/// line from a function that never pushes a root, taking it for the root
/// chain's restore, and this address is not that.
fn heapField(comptime E: type, self: E, target: usize, offset: u64) Error!void {
    const base = self.temp();
    try self.print(" %v{d} =l copy %heap\n %v{d} =l add %v{d}, {d}\n", .{ base, target, base, offset });
}

/// One class body the arena path allocates: the temporary receiving its
/// payload, the constructor's label number, its body size and descriptor.
const ArenaBody = struct { pointer: usize, label: usize, size: u64, descriptor: []const u8 };

/// In a program that opens arenas, try the arena window before the runtime
/// call: inside an arena the inline window is always empty, and the innermost
/// arena's free tail is bumped instead. The header is the window's
/// precomputed one-element mark and the descriptor; the chunk is zero-filled,
/// so the payload is not cleared. Outside an arena the window is two null
/// words and the check falls through to the call.
fn arenaBump(comptime E: type, self: E, body: ArenaBody) Error!void {
    const window = self.temp();
    const cursor = self.temp();
    const limit_slot = self.temp();
    const limit = self.temp();
    const next = self.temp();
    const fits = self.temp();
    const bytes = (header_bytes + @max(body.size, 1) + 15) & ~@as(u64, 15);
    try heapField(E, self, window, heap_arena_offset);
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, 8\n %v{d} =l loadl %v{d}\n", .{ cursor, window, limit_slot, window, limit, limit_slot });
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l culel %v{d}, %v{d}\n", .{ next, cursor, bytes, fits, next, limit });
    try self.print(" jnz %v{d}, @cell_arena{d}, @cell_call{d}\n@cell_arena{d}\n", .{ fits, body.label, body.label, body.label });
    try self.markObject(cursor);
    const mark_slot = self.temp();
    const mark = self.temp();
    const element = self.temp();
    try self.print(" storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 16\n %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n", .{ next, window, mark_slot, window, mark, mark_slot, mark, cursor });
    try self.print(" %v{d} =l add %v{d}, 8\n storel extern ${s}_body, %v{d}\n %v{d} =l add %v{d}, {d}\n", .{ element, cursor, body.descriptor, element, body.pointer, cursor, header_bytes });
    try self.print(" jmp @cell_done{d}\n@cell_call{d}\n", .{ body.label, body.label });
}

/// Zero a reused slot's payload word by word. The constructor overwrites every
/// field right after, so an optimizing backend drops each store it shadows;
/// what remains is the padding and inactive variant payload a collection or a
/// byte-wise copy may read.
fn zeroPayload(comptime E: type, self: E, pointer: usize, size: u64) Error!void {
    var offset: u64 = 0;
    while (offset < size) {
        const left = size - offset;
        const width: u64 = if (left >= 8) 8 else if (left >= 4) 4 else if (left >= 2) 2 else 1;
        const op = switch (width) {
            8 => "storel",
            4 => "storew",
            2 => "storeh",
            else => "storeb",
        };
        if (offset == 0) try self.print(" {s} 0, %v{d}\n", .{ op, pointer }) else {
            const address = self.temp();
            try self.print(" %v{d} =l add %v{d}, {d}\n {s} 0, %v{d}\n", .{ address, pointer, offset, op, address });
        }
        offset += width;
    }
}

/// Run the generational barrier before a store into the class body at
/// `pointer`: an old body is remembered for the next minor collection. The
/// test is one header load; the call runs at most once per body per
/// collection, because it clears the mark bit it tests.
pub fn barrier(comptime E: type, self: E, pointer: usize) Error!void {
    const label = self.temp();
    const header = self.temp();
    const word = self.temp();
    const old = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, 1\n", .{ header, pointer, header_bytes, word, header, old, word });
    try self.print(" jnz %v{d}, @remember{d}, @remembered{d}\n@remember{d}\n call $myl_native_heap_remember(l %heap, l %v{d})\n@remembered{d}\n", .{ old, label, label, label, pointer, label });
}

test "inline size classes round a payload and its header up to a stride" {
    // spec: QBE-INLINE-ALLOC-1
    try std.testing.expectEqual(@as(?usize, 0), inlineClass(0));
    try std.testing.expectEqual(@as(?usize, 1), inlineClass(16));
    try std.testing.expectEqual(@as(?usize, 2), inlineClass(32));
    try std.testing.expectEqual(@as(?usize, 2), inlineClass(17));
    try std.testing.expectEqual(@as(?usize, 11), inlineClass(240));
    try std.testing.expectEqual(@as(?usize, null), inlineClass(241));
}

/// The first strides of the runtime's size-class table, read from its source.
fn runtimeStrides() ?[inline_class_strides.len]u64 {
    const source = @embedFile("native_heap.c");
    const opening = "class_strides[MYL_NATIVE_CLASS_COUNT] = {";
    const start = std.mem.indexOf(u8, source, opening) orelse return null;
    var numbers = std.mem.tokenizeAny(u8, source[start + opening.len ..], ", \n");
    var runtime: [inline_class_strides.len]u64 = undefined;
    for (&runtime) |*stride| stride.* = std.fmt.parseInt(u64, numbers.next() orelse return null, 10) catch return null;
    return runtime;
}

test "inline size classes match the runtime's class table" {
    // spec-case: QBE-INLINE-ALLOC-1
    const runtime = runtimeStrides();
    try std.testing.expect(runtime != null);
    try std.testing.expectEqualSlices(u64, &inline_class_strides, &runtime.?);
    const header = @embedFile("native_heap.h");
    try std.testing.expect(std.mem.indexOf(u8, header, "#define MYL_NATIVE_INLINE_CLASSES 12\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "#define MYL_NATIVE_HEAP_INLINE_OFFSET 1280\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "#define MYL_NATIVE_HEAP_ARENA_OFFSET 1472\n") != null);
}

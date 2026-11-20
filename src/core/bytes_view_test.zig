//! Wave 3: a byte slice is a view of its source too.
//!
//! `const part = data[1:3]` over an immutable `bytes` value borrows the octets
//! instead of allocating a copy. Owning storage and owning returns require a
//! written `copy(...)`; comparisons and span-aware readers borrow the octets.
//! This file pins the debug pipeline's shape, the values, the family of the
//! explicit copy, and the byte-slice behaviours the view must not change.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The body of the function named `name` in the dumped Core IR.
fn functionIr(arena: std.mem.Allocator, text: []const u8, name: []const u8) ![]const u8 {
    // A fixture that imports is an embedded project, whose entry functions are named `main::name`.
    const header = try std.fmt.allocPrint(arena, "fn {s}(", .{name});
    const qualified = try std.fmt.allocPrint(arena, "fn main::{s}(", .{name});
    const found = std.mem.indexOf(u8, text, header) orelse std.mem.indexOf(u8, text, qualified);
    const start = found orelse return "";
    const next = std.mem.indexOfPos(u8, text, start + header.len, "\nfn ") orelse text.len;
    return text[start..next];
}

test "owned variant payloads copy explicitly and declared wrappers stay borrowed natively" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\enum Packet:
        \\    data(value: bytes)
        \\record Kept:
        \\    data: bytes? = None
        \\func optional(data: bytes) -> bytes? from data:
        \\    return Some(data[1:3])
        \\func fallible(data: bytes) -> bytes from data fails str:
        \\    return data[1:3]
        \\func main(out: Stream) -> int:
        \\    const data = b"abcd"
        \\    mut kept = Kept()
        \\    kept.data = Some(copy(data[1:3]))
        \\    const packet = Packet.data(value=copy(data[1:3]))
        \\    const result: Result[bytes, str] = Ok(copy(data[1:3]))
        \\    assert kept.data == Some(b"bc")
        \\    assert optional(data) == Some(b"bc")
        \\    match packet:
        \\        case data(value=part):
        \\            assert part == b"bc"
        \\    match result:
        \\        case Ok(part):
        \\            assert part == b"bc"
        \\        case Err(_):
        \\            return 2
        \\    match fallible(data):
        \\        case Ok(part):
        \\            print(out, len(part), part[0], part[1])
        \\        case Err(_):
        \\            return 3
        \\    return 0
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkWithSource(a, unit.program.?, unit.src.?, &failure);
    inline for (.{ false, true }) |optimized| {
        var refusal: @import("build.zig").Refusal = .{};
        var module = try support.buildSource(a, source, &refusal);
        const result = if (optimized) try support.runPasses(a, &module, .verify) else try @import("passes.zig").debug(a, &module);
        const ran = try support.runOwned(a, &module, .{ .own = false, .release = optimized, .analysis = support.analysis(&result) });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("2 98 99\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

// spec-case: BYTES-VIEW-1
test "a byte slice bound to a local is a view in the debug pipeline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func measure(data: bytes, out: Stream) -> int:
        \\    const part = data[1:3]
        \\    print(out, len(part), part[0], part[1])
        \\    return len(part)
        \\func main(out: Stream) -> int:
        \\    return measure(b"abcd", out)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const measure = try functionIr(a, dumped, "measure");
    // A slice of a plain `bytes` parameter is a view of a view: the view helper, with no owned slice (C9 bytes).
    try std.testing.expect(contains(measure, "myl_core_view_slice"));
    try std.testing.expect(!contains(measure, "myl_core_bytes_slice"));
    // `measure` returns the length it read, and the entry point's value is the
    // process status.
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 2), ran.status);
    try std.testing.expectEqualStrings("2 98 99\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: BYTES-VIEW-1
test "a byte view copies into bytes where an owned value is needed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import hex
        \\
        \\record Kept:
        \\    data: bytes
        \\func hold(data: bytes) -> Kept:
        \\    const part = copy(data[1:3])
        \\    return Kept(data=own part)
        \\func copy_of(data: bytes) -> bytes:
        \\    const part = data[0:2]
        \\    return copy(part)
        \\func main(out: Stream) -> int:
        \\    const kept = hold(b"abcd")
        \\    print(out, kept.data, copy_of(b"wxyz"), hex.encode(kept.data))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // The copies are `bytes`, not text: the span copy of byte octets.
    try std.testing.expect(contains(try functionIr(a, dumped, "hold"), "myl_core_view_copy_bytes"));
    try std.testing.expect(contains(try functionIr(a, dumped, "copy_of"), "myl_core_view_copy_bytes"));
    try std.testing.expect(!contains(try functionIr(a, dumped, "hold"), "str_from_view"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("b'bc' b'wx' 6263\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: BYTES-VIEW-1
test "a byte view keeps the clamps of the copy it replaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func edges(data: bytes, out: Stream) -> int:
        \\    const clamped = data[1:99]
        \\    const reversed = data[3:1]
        \\    print(out, len(clamped), len(reversed), clamped[0], clamped[2])
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    return edges(b"abcd", out)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("3 0 98 100\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: BYTES-VIEW-1
test "a byte view reads and copies the same octets in release mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Kept:
        \\    data: bytes
        \\func hold(data: bytes) -> Kept:
        \\    const part = copy(data[1:3])
        \\    return Kept(data=own part)
        \\func main(out: Stream) -> int:
        \\    const part = copy(b"abcd"[1:3])
        \\    const kept = hold(b"abcd")
        \\    print(out, len(part), part[1], b"b" in part, kept.data, kept.data == b"bc")
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const ran = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2 99 True b'bc' True\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: BYTES-VIEW-1
test "storing a byte slice expression requires its written bytes copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Kept:
        \\    data: bytes
        \\func my_take(data: bytes) -> Kept:
        \\    mut kept = Kept(data=b"")
        \\    kept.data = copy(data[1:3])
        \\    return kept
        \\func main(out: Stream) -> int:
        \\    print(out, my_take(b"abcd").data)
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const take = try functionIr(a, dumped, "my_take");
    // The record field is an owned use of the borrowed slice: the store copies it, as a view materialization
    // (lane C-c, D9). The copy is still made: bytes escapes stay exempt from the refusal.
    try std.testing.expect(contains(take, "myl_core_view_copy_bytes"));
    try std.testing.expect(!contains(take, "myl_core_bytes_slice"));
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("b'bc'\n", ran.stdout);
}

/// A stable location for final-IR written-copy diagnostics in the span regression.
fn spanLocation(_: *const anyopaque, offset: u32) @import("source_location.zig").Location {
    return .{ .path = "borrowed_io_spans.selka", .line = 1, .column = offset + 1 };
}

fn writtenSpanCopies(a: std.mem.Allocator, module: *const ir.Module) !void {
    const marker: u8 = 0;
    var report: std.ArrayList(u8) = .empty;
    try @import("verify_ir.zig").writtenCopies(a, module, .{ .context = &marker, .locate = spanLocation }, true, &report);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
}

fn spanReaders(backing: std.mem.Allocator, release: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const source = @embedFile("borrowed_io_spans.selka");
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const expected = "7 0 255 3 0\n\x00\xffλλ!\n!\n120\n|tail\nTrue 2 True\n";
    if (release) {
        const result = try support.runPasses(a, &module, .trusted);
        try writtenSpanCopies(a, &module);
        const ran = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    } else {
        try writtenSpanCopies(a, &module);
        const ran = try support.runOwned(a, &module, .{});
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

test "C5 span readers avoid byte snapshots and preserve ordered text and file output" {
    try spanReaders(std.testing.allocator, false);
    try spanReaders(std.testing.allocator, true);
}

test "C5 span reader contracts borrow exact arguments and keep fresh conversions" {
    const contract = @import("zero_rc.zig").contract;
    try std.testing.expectEqual(@as(u64, 12), contract("myl_core_span_file_access").?.views);
    try std.testing.expectEqual(@as(u64, 8), contract("myl_core_span_file_method").?.views);
    try std.testing.expectEqual(@as(u64, 2), contract("myl_core_span_stream_write").?.views);
    try std.testing.expectEqual(@as(u64, 1), contract("myl_core_span_bytes_to_list").?.views);
    try std.testing.expect(contract("myl_core_span_bytes_to_list").?.result == .fresh);
    try std.testing.expectEqual(@as(u64, 0), contract("myl_core_span_bytes_to_list").?.owned);
}

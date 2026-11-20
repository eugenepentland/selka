//! `@freestanding` in Core (MCU-NOC2): a failed check is a fault that calls nothing, and the emitted-symbol check catches a
//! planted violation.
const std = @import("std");
const build = @import("build.zig");
const support = @import("test_support.zig");
const own = @import("own.zig");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const freestanding_emitted = @import("freestanding_emitted.zig");
const target = @import("target.zig");

const program =
    \\@freestanding
    \\func at(words: FixedArray[u32, 4], index: int) -> u32:
    \\    return words[index]
    \\
    \\
    \\func shout(x: int) -> int:
    \\    return x + 1
    \\
    \\
    \\func main() -> int:
    \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
    \\    return int(at(words, 2)) + shout(1)
    \\
;

fn noLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .line = 7, .column = 1 };
}

fn emitted(arena: std.mem.Allocator, module: *ir.Module, chosen: target.Target) emit_llvm.Error![]const u8 {
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = noLocation }, .source_path = "free.selka", .main = .{}, .target = chosen });
}

fn built(arena: std.mem.Allocator) !ir.Module {
    return builtFor(arena, 8);
}

fn builtFor(arena: std.mem.Allocator, pointer_bytes: u8) !ir.Module {
    var refusal: build.Refusal = .{};
    var module = try support.buildSourceFor(arena, program, &refusal, pointer_bytes);
    _ = try own.run(arena, &module, .{});
    return module;
}

/// The text of the function whose symbol is `my.NAME`, from its `define` line to its closing brace.
fn functionText(text: []const u8, name: []const u8) ?[]const u8 {
    var needle_buffer: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buffer, "@\"my.{s}\"(", .{name}) catch return null;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, needle)) |at| {
        const line = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
        from = at + needle.len;
        if (!std.mem.startsWith(u8, text[line..], "define ")) continue;
        const end = std.mem.indexOfPos(u8, text, at, "\n}") orelse return null;
        return text[line..end];
    }
    return null;
}

test "a failed check of a freestanding function is a fault with its code and place, and calls nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try built(arena.allocator());
    const host = functionText(try emitted(arena.allocator(), &module, target.host), "at").?;
    try std.testing.expect(std.mem.indexOf(u8, host, "call void asm sideeffect \"ud2\\0A.ascii \\22MYLF\\22\", \"{rdi},{rsi},{rdx}\"(i64 2, ptr @myl.path.") != null);
    try std.testing.expect(std.mem.indexOf(u8, host, ", i64 7)") != null);
    try std.testing.expect(std.mem.indexOf(u8, host, "@myl_core_trap") == null);
    try std.testing.expect(std.mem.indexOf(u8, host, "@myl.site.") == null);
    var small = try builtFor(arena.allocator(), 4);
    const device = functionText(try emitted(arena.allocator(), &small, target.thumbv6m_none), "at").?;
    try std.testing.expect(std.mem.indexOf(u8, device, "call void asm sideeffect \"udf #83\", \"{r0},{r1},{r2}\"(i32 2, ptr @myl.path.") != null);
    try std.testing.expect(std.mem.indexOf(u8, device, "call ") == std.mem.indexOf(u8, device, "call void asm"));
}

test "the text of a device build holds the fault site the runtime's flavour looks for exactly when a freestanding check can fail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var small = try builtFor(arena.allocator(), 4);
    const with = try emitted(arena.allocator(), &small, target.thumbv6m_none);
    try std.testing.expect(std.mem.indexOf(u8, with, freestanding_emitted.fault_site) != null);
    var plain = try builtFor(arena.allocator(), 4);
    plain.freestanding = .empty;
    const without = try emitted(arena.allocator(), &plain, target.thumbv6m_none);
    try std.testing.expect(std.mem.indexOf(u8, without, freestanding_emitted.fault_site) == null);
    try std.testing.expect(std.mem.indexOf(u8, without, "udf #83") == null);
}

test "a program with no freestanding function emits its checks as runtime traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try built(arena.allocator());
    module.freestanding = .empty;
    const text = functionText(try emitted(arena.allocator(), &module, target.host), "at").?;
    try std.testing.expect(std.mem.indexOf(u8, text, "call void @myl_core_trap(ptr @myl.site.") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "asm sideeffect") == null);
}

test "the emitted-symbol check refuses a planted function that calls the runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try built(arena.allocator());
    // `main` calls `shout` and the runtime's start-up helpers: marked freestanding, its text breaks the promise.
    try module.freestanding.put(arena.allocator(), ir.Module.nameKey("main"), {});
    try std.testing.expectError(error.UnsupportedInstruction, emitted(arena.allocator(), &module, target.host));
}

/// A freestanding function and an ordinary one, each calling C through a symbol and through an address (MCU-NOC2C).
const foreign_program =
    \\extern func weigh(host: Host, a: i64, b: i64) -> i64
    \\
    \\
    \\@address
    \\extern func weigh_at(host: Host, target: u32, a: i64, b: i64) -> i64
    \\
    \\
    \\@freestanding
    \\func through(host: Host, target: u32, a: i64) -> i64:
    \\    return weigh(host, a, 1) + weigh_at(host, target, a, 2)
    \\
    \\
    \\func ordinary(host: Host, target: u32, a: i64) -> i64:
    \\    return weigh(host, a, 1) + weigh_at(host, target, a, 2)
    \\
    \\
    \\func main(host: Host) -> int:
    \\    return int(through(host, 0, 5) + ordinary(host, 0, 5))
    \\
;

fn builtForeign(arena: std.mem.Allocator, pointer_bytes: u8) !ir.Module {
    var refusal: build.Refusal = .{};
    var module = try support.buildSourceFor(arena, foreign_program, &refusal, pointer_bytes);
    _ = try own.run(arena, &module, .{});
    return module;
}

fn contains(text: []const u8, piece: []const u8) bool {
    return std.mem.indexOf(u8, text, piece) != null;
}

test "a freestanding foreign call compares its Host token inline and faults, recording no place and calling no runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try builtForeign(arena.allocator(), 8);
    const whole = try emitted(arena.allocator(), &module, target.host);
    const host = functionText(whole, "through").?;
    try std.testing.expect(!contains(host, "myl_core_"));
    try std.testing.expect(contains(host, " = icmp ne i64 %p0, -6\n"));
    try std.testing.expect(contains(host, "call void asm sideeffect \"ud2\\0A.ascii \\22MYLF\\22\", \"{rdi},{rsi},{rdx}\"(i64 24, ptr @myl.path."));
    try std.testing.expect(contains(host, "call void asm sideeffect \"ud2\\0A.ascii \\22MYLF\\22\", \"{rdi},{rsi},{rdx}\"(i64 23, ptr @myl.path."));
    try std.testing.expect(contains(host, " = icmp eq i32 %p1, 0\n"));
    try std.testing.expect(contains(host, "call i64 @weigh(i64 "));
    // The ordinary function keeps its lowering: the place recorded, the runtime's Host check, the null target a trap.
    const plain = functionText(whole, "ordinary").?;
    try std.testing.expect(contains(plain, "call void @myl_core_io_at(ptr @myl.site."));
    try std.testing.expect(contains(plain, "call void @myl_core_host_check(i64 %p0)"));
    try std.testing.expect(contains(plain, "call void @myl_core_trap(ptr @myl.site."));
    try std.testing.expect(!contains(plain, "asm sideeffect"));
    // The unit holds a fault, so it carries the Linux handler, installed before `main`.
    try std.testing.expect(contains(whole, "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @myl.fault.install, ptr null }]"));
    try std.testing.expect(contains(whole, "define internal void @myl.fault.handler(i32 %signal, ptr %info, ptr %context)"));
    try std.testing.expect(contains(whole, "declare i32 @sigaction(i32, ptr, ptr)"));
    var small = try builtForeign(arena.allocator(), 4);
    const device_whole = try emitted(arena.allocator(), &small, target.thumbv6m_none);
    const device = functionText(device_whole, "through").?;
    try std.testing.expect(!contains(device, "myl_core_"));
    try std.testing.expect(contains(device, "call void asm sideeffect \"udf #83\", \"{r0},{r1},{r2}\"(i32 24, ptr @myl.path."));
    try std.testing.expect(contains(device, "call void asm sideeffect \"udf #83\", \"{r0},{r1},{r2}\"(i32 23, ptr @myl.path."));
    // A device reports a fault from its own fault handler (`bare/core_bare.c`): no Linux handler.
    try std.testing.expect(!contains(device_whole, "@myl.fault.") and !contains(device_whole, "@llvm.global_ctors"));
}

test "a unit with no freestanding code carries no fault handler and lowers its foreign calls as before" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try builtForeign(arena.allocator(), 8);
    module.freestanding = .empty;
    const whole = try emitted(arena.allocator(), &module, target.host);
    try std.testing.expect(!contains(whole, "@myl.fault.") and !contains(whole, "@llvm.global_ctors") and !contains(whole, "@sigaction"));
    const through = functionText(whole, "through").?;
    try std.testing.expect(contains(through, "call void @myl_core_io_at(ptr @myl.site."));
    try std.testing.expect(contains(through, "call void @myl_core_host_check(i64 %p0)"));
}

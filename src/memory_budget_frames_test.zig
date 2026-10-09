//! The call-depth budget check `memory_budget` gives the CLI: what a `--max-frames`
//! reserves, when the guest's address space cannot back it, and the text that says so.
const std = @import("std");
const budget = @import("memory_budget");

// spec-case: RUN-FRAME-BUDGET-1
test "a call-depth budget the memory ceiling cannot back is refused with what it needs" {
    // 20000 frames fit the 512M test ceiling, 25000 do not, exactly as the mapping decides.
    try std.testing.expect(budget.frameFit(20000, budget.test_default, null).fits);
    try std.testing.expect(!budget.frameFit(25000, budget.test_default, null).fits);
    const fit = budget.frameFit(150000, budget.run_default, null);
    try std.testing.expect(!fit.fits and !fit.inherited);
    try std.testing.expectEqual(@as(u64, 150000 * budget.frame_stack_bytes + budget.stack_slack), fit.need);
    try std.testing.expectEqual(@as(?u64, budget.run_default + budget.headroom), fit.limit);
    // No ceiling and no process limit bound nothing; an overflowing request never fits.
    try std.testing.expect(budget.frameFit(1 << 40, 0, null).fits);
    try std.testing.expect(!budget.frameFit(std.math.maxInt(u64), 0, 1 << 40).fits);
    // A process limit below the request is named as the cause, not --max-memory.
    const capped = budget.frameFit(400000, 64 << 30, 8 << 30);
    try std.testing.expect(!capped.fits and capped.inherited);
    try std.testing.expectEqual(@as(?u64, 8 << 30), capped.limit);
    const lifted = budget.frameFit(400000, 64 << 30, null);
    try std.testing.expect(lifted.fits and !lifted.inherited);
}

// spec-case: RUN-FRAME-BUDGET-1
test "the refusal names the reservation, the limit and both ways out" {
    const refuser: budget.Refuser = .{ .command = "run", .who = "a guest" };
    const text = (try budget.frameRefusalUnder(std.testing.allocator, refuser, 150000, budget.run_default, null)).?;
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "selka run: a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but a guest may map only 4."));
    try std.testing.expect(std.mem.indexOf(u8, text, "raise --max-memory to at least 5G, or lower --max-frames to at most 137984\n") != null);
    try std.testing.expect(try budget.frameRefusalUnder(std.testing.allocator, refuser, 1024, budget.run_default, null) == null);
    const inherited = (try budget.frameRefusalUnder(std.testing.allocator, refuser, 400000, 64 << 30, 8 << 30)).?;
    defer std.testing.allocator.free(inherited);
    try std.testing.expect(std.mem.indexOf(u8, inherited, "this process inherited an address-space limit below --max-memory") != null);
    try std.testing.expect(std.mem.indexOf(u8, inherited, "raise the caller's RLIMIT_AS") != null);
}

// spec-case: RUN-FRAME-BUDGET-1
test "the per-frame stack constants match the runtime that maps the stack" {
    const runtime = @embedFile("core/runtime/core_test.c");
    try std.testing.expect(std.mem.indexOf(u8, runtime, "CORE_TEST_FRAME_STACK = 32768, CORE_TEST_STACK_SLACK = 8 << 20") != null);
    try std.testing.expectEqual(@as(u64, 32768), budget.frame_stack_bytes);
}

// spec-case: RUN-FRAME-BUDGET-1
test "an overflowing frame reservation is refused without overflowing its advice" {
    try std.testing.expect(!budget.frameFit(1 << 49, 0, null).fits);
    const text = (try budget.frameRefusalUnder(std.testing.allocator, .{ .command = "run", .who = "a guest" }, 1 << 49, budget.run_default, null)).?;
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "exceeds the addressable native stack size") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "lower --max-frames") != null);
}

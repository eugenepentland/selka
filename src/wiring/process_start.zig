//! The `selka` process's start (SELKA-START-1): the allocator, I/O, arena and
//! environment Zig's start code hands `main`. The checking allocator is Zig's
//! DebugAllocator in its thread-safe mode and records no stack trace per
//! allocation: Zig's default records seven frames for every allocation, and the
//! first one parses and sorts the unwind tables of this whole executable, about
//! 17 ms of every Debug `selka` start, two thirds of a cached `selka run`, which
//! the unit suites spawn thousands of times. The leak and double-free checks stay,
//! and memory is never reused. This file used SafeAllocator before: its per-thread
//! bookkeeping raced when several threads allocated through it at once
//! (ThreadSanitizer, lane U, 2026-10-28), and its write-after-free check is not
//! part of DebugAllocator.
const std = @import("std");
const builtin = @import("builtin");
const crash_report = @import("crash_report.zig");
const process_allocator = @import("process_allocator.zig");
const budget = @import("memory_budget");

/// The checking allocator: no stack trace per allocation, and every call serialized by its own mutex.
pub const Checking = std.heap.DebugAllocator(.{ .stack_trace_frames = 0, .thread_safe = true });

/// Whether Zig's start code would use its checking allocator in this build mode.
const use_checking = switch (builtin.mode) {
    .debug, .safe => true,
    .fast, .small => false,
};

// The process's own allocator, as Zig's start code keeps it. // allocator-ok
var checking: Checking = .init;

/// Why a compiler built in `mode` refuses to start, or null when the mode is supported. A ReleaseSafe compiler spins at 100% CPU the
/// first time it reads a file to its end through a standard-library reader (`/proc/meminfo` in `memory_budget.available`, `/proc/PID/stat`
/// in the engine's lock owner check, about 570,000 `preadv` calls in 8 s): the reader's loop never sees the empty read that ends the
/// file. Zig's reader code is the one at fault and is used throughout the compiler, so no single call site can be mended; the mode is refused.
pub fn unsupportedMode(mode: std.lang.OptimizeMode) ?[]const u8 {
    return switch (mode) {
        .safe => "selka: this compiler was built in ReleaseSafe mode, which is not supported: it spins at 100% CPU the first time a " ++
            "standard-library reader reaches the end of a file. Build with -Doptimize=ReleaseFast (the installed compiler) or the default Debug mode.\n",
        .debug, .fast, .small => null,
    };
}

/// Call `body` with the `std.process.Init` that Zig's start code would pass `main`, on a thread whose stack is
/// `budget.compilerStack` bytes, 256 MiB unless the compiler's own memory ceiling is tight (DL2). The main thread's stack is whatever
/// `RLIMIT_STACK` says (8 MiB under most shells; Zig's start code raises it to the 16 MiB the executable declares, but not for the
/// incremental back end's executables, which declare none), and lowering recurses on the depth of an expression, so a compiler that
/// fits today depends on how a build was made. The main thread waits; `std.process.exit` from the worker ends the process as it did
/// from the main thread, and a normal return from `body` ends it with status 0 once the thread has finished. A thread the system
/// will not start (an address-space limit of the caller's, say) is tried again with Zig's default stack, and failing that the work
/// stays on the main thread, as it ran before.
pub fn run(minimal: std.process.Init.Minimal, comptime body: fn (std.process.Init) void) void {
    if (comptime unsupportedMode(builtin.mode)) |refusal| {
        _ = std.os.linux.write(2, refusal.ptr, refusal.len);
        std.os.linux.exit_group(2);
    }
    // A Debug compiler states the machine state of a SIGSEGV before Zig's own report (F22). The handler runs on the alternate
    // signal stack of the thread that faults, which `std.Thread` sets up for the worker as `std.start` does for this one.
    crash_report.install();
    const worker = struct {
        fn start(given: std.process.Init.Minimal) void {
            runHere(given, body);
        }
    };
    const wanted = budget.compilerStack(budget.hostCeiling(minimal.environ.getPosix(budget.host_variable)));
    const thread = std.Thread.spawn(.{ .stack_size = wanted }, worker.start, .{minimal}) catch
        std.Thread.spawn(.{}, worker.start, .{minimal}) catch return runHere(minimal, body);
    thread.join();
}

/// `run` on the calling thread: the allocators, I/O, arena and environment Zig's start code builds, then `body`.
fn runHere(minimal: std.process.Init.Minimal, comptime body: fn (std.process.Init) void) void {
    // The allocators Zig's start code chooses for the other build modes. // allocator-ok
    const gpa = if (use_checking) checking.allocator() else if (builtin.link_libc) std.heap.c_allocator else process_allocator.allocator();
    // Leaks are logged, as Zig's own start code does; they do not change the status.
    defer if (use_checking) {
        _ = checking.deinit();
    };
    // The process-lifetime arena `std.process.Init` carries. // allocator-ok
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // A release process leaves the arena to the kernel, which reclaims a process in one pass at exit, cheaper than unmapping it node by node (L1R12-EXIT-1).
    defer if (use_checking) arena.deinit();
    var threaded: std.Io.Threaded = .init(gpa, .{ .argv0 = .init(minimal.args), .environ = minimal.environ });
    defer threaded.deinit();
    var environ_map = std.process.Environ.createMap(minimal.environ, gpa) catch |err|
        std.process.fatal("failed to parse environment variables: {t}", .{err});
    defer if (use_checking) environ_map.deinit();
    const preopens = std.process.Preopens.init(arena.allocator()) catch |err|
        std.process.fatal("failed to init preopens: {t}", .{err});
    body(.{ .minimal = minimal, .arena = &arena, .gpa = gpa, .io = threaded.io(), .environ_map = &environ_map, .preopens = preopens });
}

test "only a ReleaseSafe compiler refuses to start, and its message names the mode and the ways out" {
    const message = unsupportedMode(.safe).?;
    try std.testing.expect(std.mem.indexOf(u8, message, "ReleaseSafe") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "-Doptimize=ReleaseFast") != null);
    try std.testing.expect(std.mem.endsWith(u8, message, "\n"));
    try std.testing.expectEqual(@as(?[]const u8, null), unsupportedMode(.debug));
    try std.testing.expectEqual(@as(?[]const u8, null), unsupportedMode(.fast));
    try std.testing.expectEqual(@as(?[]const u8, null), unsupportedMode(.small));
}

// spec: SELKA-START-1
test "the selka process allocator keeps its checks and records no stack trace per allocation" {
    // The checking allocator under test, configured as the process's. // allocator-ok
    var allocator: Checking = .init;
    const bytes = try allocator.allocator().alloc(u8, 16);
    allocator.allocator().free(bytes);
    try std.testing.expectEqual(std.heap.Check.ok, allocator.deinit());
}

test "the process allocator keeps every block intact under concurrent allocate, resize, remap and free" {
    var checking_under_test: Checking = .init;
    defer _ = checking_under_test.deinit();
    var failures: std.atomic.Value(usize) = .init(0);
    try runChurn(checking_under_test.allocator(), &failures);
    try std.testing.expectEqual(@as(usize, 0), failures.load(.acquire));
}

/// Eight threads churn through `a` at once and finish before this returns.
fn runChurn(a: std.mem.Allocator, failures: *std.atomic.Value(usize)) !void {
    var threads: [8]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, churn, .{ a, index, failures });
    for (threads) |thread| thread.join();
}

/// One thread's share of the stress: keep up to 32 live blocks, each filled with its own byte, and every step either
/// verifies and frees one, or allocates, resizes or remaps one. A block whose bytes changed under it is a failure.
fn churn(a: std.mem.Allocator, seed: usize, failures: *std.atomic.Value(usize)) void {
    var slots: [32][]u8 = @splat(&.{});
    var state: usize = seed *% 2654435761 +% 1;
    for (0..4000) |_| {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        const index = (state >> 20) % slots.len;
        const choice = (state >> 40) % 4;
        const size = 1 + (state >> 8) % 4096;
        const block = slots[index];
        if (block.len != 0) {
            for (block) |byte| if (byte != @as(u8, @truncate(index + seed))) {
                _ = failures.fetchAdd(1, .monotonic);
                break;
            };
        }
        if (block.len != 0 and choice == 0) {
            a.free(block);
            slots[index] = &.{};
        } else if (block.len != 0 and choice == 1) {
            const grown = a.remap(block, size) orelse {
                slots[index] = &.{};
                a.free(block);
                continue;
            };
            slots[index] = grown;
            @memset(grown, @as(u8, @truncate(index + seed)));
        } else {
            if (block.len != 0) a.free(block);
            const fresh = a.alloc(u8, size) catch {
                _ = failures.fetchAdd(1, .monotonic);
                return;
            };
            @memset(fresh, @as(u8, @truncate(index + seed)));
            slots[index] = fresh;
        }
    }
    for (slots) |block| if (block.len != 0) a.free(block);
}

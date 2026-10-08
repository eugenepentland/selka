//! The `mylang` process's start (MYLANG-START-1): the allocator, I/O, arena and
//! environment Zig's start code hands `main`, except that the safe-build allocator
//! records no stack trace per allocation. Zig's default records seven frames for
//! every allocation, and the first one parses and sorts the unwind tables of this
//! whole executable: about 17 ms of every Debug `mylang` start, two thirds of a
//! cached `mylang run`, which the unit suites spawn thousands of times. The leak,
//! double-free and write-after-free checks stay.
const std = @import("std");
const builtin = @import("builtin");

/// The safe-build allocator's options: Zig's checks, without per-allocation traces.
pub const safe_options: std.heap.SafeAllocator.Options = .{ .stack_trace_frames = 0 };

/// Whether Zig's start code would use its checking allocator in this build mode.
const use_safe = switch (builtin.mode) {
    .debug, .safe => true,
    .fast, .small => false,
};

// The process's own allocator, as Zig's start code keeps it. // allocator-ok
var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, safe_options);

/// Call `body` with the `std.process.Init` that Zig's start code would pass `main`.
pub fn run(minimal: std.process.Init.Minimal, comptime body: fn (std.process.Init) void) void {
    // The allocators Zig's start code chooses for the other build modes. // allocator-ok
    const gpa = if (use_safe) safe.allocator() else if (builtin.link_libc) std.heap.c_allocator else std.heap.smp_allocator;
    // Leaks are logged, as Zig's own start code does; they do not change the status.
    defer if (use_safe) {
        _ = safe.deinit();
    };
    // The process-lifetime arena `std.process.Init` carries. // allocator-ok
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var threaded: std.Io.Threaded = .init(gpa, .{ .argv0 = .init(minimal.args), .environ = minimal.environ });
    defer threaded.deinit();
    var environ_map = std.process.Environ.createMap(minimal.environ, gpa) catch |err|
        std.process.fatal("failed to parse environment variables: {t}", .{err});
    defer environ_map.deinit();
    const preopens = std.process.Preopens.init(arena.allocator()) catch |err|
        std.process.fatal("failed to init preopens: {t}", .{err});
    body(.{ .minimal = minimal, .arena = &arena, .gpa = gpa, .io = threaded.io(), .environ_map = &environ_map, .preopens = preopens });
}

// spec: MYLANG-START-1
test "the mylang process allocator keeps its checks and records no stack trace per allocation" {
    // The checking allocator under test, configured as the process's. // allocator-ok
    var allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, safe_options);
    const bytes = try allocator.allocator().alloc(u8, 16);
    allocator.allocator().free(bytes);
    try std.testing.expectEqual(@as(usize, 0), allocator.stack_trace_size);
    try std.testing.expect(allocator.check_write_after_free == (builtin.mode == .debug));
    try std.testing.expectEqual(@as(usize, 0), allocator.deinitLog(false));
}

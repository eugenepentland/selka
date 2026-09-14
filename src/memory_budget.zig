//! Byte ceilings for guest execution: the budget text every command line and
//! environment variable agrees on, the kernel backstop this process installs on
//! itself, and the fan-out width a machine's free memory can actually afford.
const std = @import("std");

/// Malformed budget or job-count text on a command line or in the environment.
pub const Error = error{InvalidMemoryLimit};

/// Environment variable carrying a guest process's byte ceiling. Every spawner
/// sets it, so a budget needs no new argument ABI and a program started by hand
/// from a shell that exported it is bounded the same way.
pub const variable = "MYLANG_MEMORY_LIMIT";
/// Environment variable overriding the ceiling the compiler puts on itself.
pub const host_variable = "MYLANG_HOST_MEMORY_LIMIT";
/// Environment variable overriding the directory-run fan-out width.
pub const jobs_variable = "MYLANG_JOBS";
/// Ceiling for one native guest test child; many run at once, so it is small.
pub const test_default: u64 = 512 << 20;
/// Ceiling for `mylang run` and `mylang build --run`; one guest, so it is large.
pub const run_default: u64 = 4 << 30;
/// Ceiling the compiler installs on itself, so a compiler defect fails loudly
/// instead of swapping. A cold native build of one program peaks near 75 MiB
/// resident and the `zig cc` and QBE children it spawns inherit this and finish.
pub const host_default: u64 = 8 << 30;
/// Address space a guest needs beyond its managed byte budget: program text,
/// the C library's arenas and the harness that loads it. Mirrors
/// `MYL_NATIVE_BUDGET_HEADROOM` in `native_heap.h`, which the runtime applies.
pub const headroom: u64 = 256 << 20;

/// Parse a byte budget written as digits with an optional `K`, `M` or `G`
/// suffix. Zero is accepted and means no ceiling at all.
pub fn parse(text: []const u8) Error!u64 {
    if (text.len == 0) return error.InvalidMemoryLimit;
    const suffix: u64 = switch (text[text.len - 1]) {
        'K', 'k' => 1 << 10,
        'M', 'm' => 1 << 20,
        'G', 'g' => 1 << 30,
        else => 1,
    };
    const digits = if (suffix == 1) text else text[0 .. text.len - 1];
    if (digits.len == 0) return error.InvalidMemoryLimit;
    const value = std.fmt.parseUnsigned(u64, digits, 10) catch return error.InvalidMemoryLimit;
    if (value > std.math.maxInt(u64) / suffix) return error.InvalidMemoryLimit;
    return value * suffix;
}

/// Resolve a ceiling in precedence order: an explicit flag, then the named
/// environment variable, then the built-in default for that kind of run.
pub fn resolve(flag: ?u64, environ: *const std.process.Environ.Map, name: []const u8, fallback: u64) Error!u64 {
    if (flag) |bytes| return bytes;
    const text = environ.get(name) orelse return fallback;
    if (text.len == 0) return fallback;
    return parse(text);
}

/// Render a byte count for a child's environment or command line.
pub fn decimal(allocator: std.mem.Allocator, bytes: u64) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{bytes});
}

/// Cap this process's address space at `bytes` plus `headroom`, the kernel
/// backstop behind every soft budget. Never raises an existing tighter ceiling
/// and does nothing for an unbounded budget; a kernel that refuses is not an
/// error, because the soft budget still applies. Reports whether one was set.
pub fn guard(bytes: u64) bool {
    if (bytes == 0 or bytes > std.math.maxInt(u64) - headroom) return false;
    const existing = std.posix.getrlimit(.AS) catch return false;
    var wanted: u64 = bytes + headroom;
    if (existing.max != std.math.maxInt(u64) and wanted > existing.max) wanted = existing.max;
    if (existing.cur <= wanted) return false;
    std.posix.setrlimit(.AS, .{ .cur = wanted, .max = existing.max }) catch return false;
    return true;
}

/// Install the compiler's own ceiling from `MYLANG_HOST_MEMORY_LIMIT`, falling
/// back to `host_default`. Malformed text leaves the process unbounded rather
/// than refusing to start, because argument parsing has not run yet.
pub fn guardHost(environ: *const std.process.Environ.Map) bool {
    return guard(resolve(null, environ, host_variable, host_default) catch return false);
}

/// Bytes the kernel reports as available for a new allocation without swapping,
/// from `MemAvailable`. Null when the report is unreadable or has no such line.
pub fn available(io: std.Io) ?u64 {
    var buffer: [8192]u8 = undefined;
    const bytes = std.Io.Dir.cwd().readFile(io, "/proc/meminfo", &buffer) catch return null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "MemAvailable:")) continue;
        const rest = std.mem.trim(u8, line["MemAvailable:".len..], " \tkB");
        const kibibytes = std.fmt.parseUnsigned(u64, rest, 10) catch return null;
        return kibibytes *| 1024;
    }
    return null;
}

/// What one directory run knows about the machine it is about to fan out over.
pub const Fanout = struct {
    /// Explicit `--jobs`/`MYLANG_JOBS` width; null asks for the derived default.
    jobs: ?usize = null,
    /// Programs waiting to run; never more workers than there is work.
    programs: usize = 1,
    /// Logical cores, the width the machine can actually execute at once.
    cores: usize = 1,
    /// Bytes free for new work, or null when the machine would not say.
    free: ?u64 = null,
    /// Soft ceiling one child grants its guest; each child also needs `headroom`.
    ceiling: u64 = test_default,
};

/// Worker count for a directory run: an explicit request wins, otherwise the
/// cores the machine has, further limited by how many child ceilings its free
/// memory can hold. Always at least one, so a loaded machine still makes
/// progress, and never more than the programs there are to run.
pub fn workers(fanout: Fanout) usize {
    const requested = fanout.jobs orelse derived: {
        const free = fanout.free orelse break :derived fanout.cores;
        const per_child = fanout.ceiling +| headroom;
        break :derived @min(fanout.cores, std.math.lossyCast(usize, free / @max(1, per_child)));
    };
    return @max(1, @min(fanout.programs, requested));
}

/// Parse a `--jobs` or `MYLANG_JOBS` width, rejecting zero and non-numeric text.
pub fn jobs(text: []const u8) Error!usize {
    const value = std.fmt.parseUnsigned(usize, text, 10) catch return error.InvalidMemoryLimit;
    if (value == 0) return error.InvalidMemoryLimit;
    return value;
}

// spec: MEMORY-CEILING-1
test "byte ceilings accept suffixed sizes and reject malformed text" {
    try std.testing.expectEqual(@as(u64, 1024), try parse("1024"));
    try std.testing.expectEqual(@as(u64, 512 << 20), try parse("512M"));
    try std.testing.expectEqual(@as(u64, 4 << 30), try parse("4G"));
    try std.testing.expectEqual(@as(u64, 2048), try parse("2k"));
    try std.testing.expectEqual(@as(u64, 0), try parse("0"));
    for ([_][]const u8{ "", "M", "12x", "-1", "1 M", "18446744073709551615G" }) |bad| {
        try std.testing.expectError(error.InvalidMemoryLimit, parse(bad));
    }
}

// spec-case: MEMORY-CEILING-1
test "a flag outranks the environment and the environment outranks the default" {
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try std.testing.expectEqual(test_default, try resolve(null, &environ, variable, test_default));
    try environ.put(variable, "64M");
    try std.testing.expectEqual(@as(u64, 64 << 20), try resolve(null, &environ, variable, test_default));
    try std.testing.expectEqual(@as(u64, 7), try resolve(7, &environ, variable, test_default));
    try environ.put(variable, "");
    try std.testing.expectEqual(test_default, try resolve(null, &environ, variable, test_default));
    try environ.put(variable, "not-a-size");
    try std.testing.expectError(error.InvalidMemoryLimit, resolve(null, &environ, variable, test_default));
    const rendered = try decimal(std.testing.allocator, 512);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("512", rendered);
}

// spec: MEMORY-CEILING-2
test "the kernel ceiling is installed once and never loosened afterwards" {
    // A terabyte bounds nothing this process could map, so the ceiling is
    // observable through getrlimit without constraining the test binary.
    const before = try std.posix.getrlimit(.AS);
    try std.testing.expect(!guard(0));
    try std.testing.expect(!guard(std.math.maxInt(u64)));
    const installed = guard(1 << 40);
    const after = try std.posix.getrlimit(.AS);
    try std.testing.expectEqual(installed, after.cur != before.cur);
    try std.testing.expect(after.cur <= (1 << 40) + headroom);
    // A looser request never raises the ceiling that is already in force.
    try std.testing.expect(!guard(2 << 40));
    try std.testing.expectEqual(after.cur, (try std.posix.getrlimit(.AS)).cur);
    try std.posix.setrlimit(.AS, before);
}

// spec: MEMORY-CEILING-3
test "fan-out follows free memory when the machine cannot afford every core" {
    try std.testing.expectEqual(@as(usize, 4), workers(.{ .programs = 100, .cores = 4, .free = 64 << 30 }));
    try std.testing.expectEqual(@as(usize, 2), workers(.{ .programs = 100, .cores = 20, .free = 2 << 30 }));
    try std.testing.expectEqual(@as(usize, 1), workers(.{ .programs = 100, .cores = 20, .free = 0 }));
    try std.testing.expectEqual(@as(usize, 3), workers(.{ .programs = 3, .cores = 20, .free = 64 << 30 }));
    try std.testing.expectEqual(@as(usize, 20), workers(.{ .programs = 100, .cores = 20, .free = null }));
    try std.testing.expectEqual(@as(usize, 7), workers(.{ .jobs = 7, .programs = 100, .cores = 2, .free = 0 }));
    try std.testing.expectEqual(@as(usize, 5), try jobs("5"));
    try std.testing.expectError(error.InvalidMemoryLimit, jobs("0"));
    try std.testing.expectError(error.InvalidMemoryLimit, jobs("many"));
}

// spec-case: MEMORY-CEILING-3
test "the machine reports free bytes for the derived fan-out width" {
    const free = available(std.testing.io);
    try std.testing.expect(free == null or free.? > 0);
    try std.testing.expect(workers(.{ .programs = 8, .cores = 8, .free = free }) >= 1);
}

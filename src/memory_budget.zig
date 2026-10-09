//! Byte ceilings for guest execution: the budget text every command line and
//! environment variable agrees on, the kernel backstop this process installs on
//! itself, and the fan-out width a machine's free memory can actually afford.
const std = @import("std");

/// Malformed budget or job-count text on a command line or in the environment.
pub const Error = error{InvalidMemoryLimit};

/// Environment variable carrying a guest process's byte ceiling. Every spawner
/// sets it, so a budget needs no new argument ABI and a program started by hand
/// from a shell that exported it is bounded the same way.
pub const variable = "SELKA_MEMORY_LIMIT";
/// Environment variable overriding the ceiling the compiler puts on itself.
pub const host_variable = "SELKA_HOST_MEMORY_LIMIT";
/// Environment variable overriding the directory-run fan-out width.
pub const jobs_variable = "SELKA_JOBS";
/// Ceiling for one native guest test child; many run at once, so it is small.
pub const test_default: u64 = 512 << 20;
/// Ceiling for `selka run` and `selka build --run`; one guest, so it is large.
pub const run_default: u64 = 4 << 30;
/// Ceiling the compiler installs on itself, so a compiler defect fails loudly
/// instead of swapping. A cold native build of one program peaks near 75 MiB
/// resident and the `zig cc` children it spawns inherit this and finish.
pub const host_default: u64 = 8 << 30;
/// Address space a guest needs beyond its managed byte budget: program text,
/// the C library's arenas and the harness that loads it. Mirrors
/// `SELKA_NATIVE_BUDGET_HEADROOM` in `native_heap.h`, which the runtime applies.
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

/// Host restart checkpoint for the soft ceiling this compiler installed.
/// Kept in the real environment across value/runtime-mode normalization.
pub const checkpoint_variable = "SELKA_HOST_LIMIT_CHECKPOINT";
/// Guest-only carrier for restoring the original caller's soft ceiling.
pub const restore_variable = "SELKA_HOST_LIMIT_RESTORE";

/// Add a guest-only restoration receipt. Build tools keep the host ceiling.
pub fn guestEnvironment(_: std.mem.Allocator, environ: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    if (environ.get(checkpoint_variable)) |limit| try environ.put(restore_variable, limit);
}

/// Install the compiler's own ceiling from `SELKA_HOST_MEMORY_LIMIT`, falling
/// back to `host_default`. Malformed text leaves the process unbounded rather
/// than refusing to start, because argument parsing has not run yet. Remember
/// the original caller limit across compiler mode-normalization restarts.
pub fn guardHost(environ: *std.process.Environ.Map) bool {
    const before = std.posix.getrlimit(.AS) catch return false;
    if (!guard(resolve(null, environ, host_variable, host_default) catch return false)) return false;
    const after = std.posix.getrlimit(.AS) catch return true;
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}:{d}", .{ after.cur, before.cur }) catch return true;
    environ.put(checkpoint_variable, text) catch return true;
    return true;
}

/// Native stack the runtime maps for each frame a `--max-frames` budget allows.
/// It mirrors `CORE_TEST_FRAME_STACK` in `src/core/runtime/core_test.c`; a test keeps them in step.
pub const frame_stack_bytes: u64 = 32768;
/// Stack mapped beyond the per-frame share, mirroring `CORE_TEST_STACK_SLACK` in `core_test.c`.
pub const stack_slack: u64 = 8 << 20;
/// Address space a guest needs besides its stack: program text, the C library's
/// arenas and the harness. Generous on purpose, so a budget refused here is one
/// the mapping would have refused too.
pub const frame_reserve: u64 = 32 << 20;

/// Address space the runtime maps for a call-depth budget of `frames`, or null
/// when the request cannot be expressed in 64 bits.
pub fn stackReservation(frames: u64) ?u64 {
    const share = std.math.mul(u64, frames, frame_stack_bytes) catch return null;
    return std.math.add(u64, share, stack_slack) catch null;
}

/// How a call-depth budget stands against the address space a guest may map.
pub const FrameFit = struct {
    /// Whether the stack reservation fits beside the guest's other mappings.
    fits: bool,
    /// Bytes of address space the stack reservation asks for.
    need: u64,
    /// The address space the guest may map, or null when nothing bounds it.
    limit: ?u64,
    /// True when the process's own limit is what bounds the guest, below what
    /// `--max-memory` asked for: the original caller's ceiling or `ulimit -v`.
    inherited: bool,
};

/// Decide whether a call-depth budget of `frames` fits. `memory` is the guest's
/// byte ceiling (zero means none) and `address_space` the soft `RLIMIT_AS` the
/// process runs under (null means unlimited). A ceiling maps `memory + headroom`
/// bytes, but never more than the process may map.
pub fn frameFit(frames: u64, memory: u64, address_space: ?u64) FrameFit {
    const reserved = stackReservation(frames);
    const need = reserved orelse std.math.maxInt(u64);
    const asked: ?u64 = if (memory == 0) null else memory +| headroom;
    var limit = asked;
    var inherited = false;
    if (address_space) |bound| {
        inherited = asked == null or bound < asked.?;
        limit = if (asked) |wanted| @min(wanted, bound) else bound;
    }
    const fits = reserved != null and (if (limit) |bytes| need <= bytes -| frame_reserve else true);
    return .{ .fits = fits, .need = need, .limit = limit, .inherited = inherited };
}

/// The soft address-space limit this process runs under, or null when unlimited.
pub fn addressSpaceLimit() ?u64 {
    const existing = std.posix.getrlimit(.AS) catch return null;
    return optionalLimit(existing.cur);
}

/// The guest's address-space ceiling after a matching compiler receipt is
/// restored; genuine caller ceilings and the inherited hard limit still apply.
pub fn guestAddressSpaceLimit(environ: *const std.process.Environ.Map) ?u64 {
    const text = environ.get(checkpoint_variable) orelse return addressSpaceLimit();
    const existing = std.posix.getrlimit(.AS) catch return null;
    return optionalLimit(restoredLimit(text, existing));
}

fn optionalLimit(limit: u64) ?u64 {
    return if (limit == std.math.maxInt(u64)) null else limit;
}

/// Match the runtime's receipt parsing and current-soft-limit equality check.
fn restoredLimit(text: []const u8, existing: std.posix.rlimit) u64 {
    for (text) |byte| if (!std.ascii.isDigit(byte) and byte != ':') return existing.cur;
    var parts = std.mem.splitScalar(u8, text, ':');
    const installed = std.fmt.parseUnsigned(u64, parts.next() orelse return existing.cur, 10) catch return existing.cur;
    const inherited = std.fmt.parseUnsigned(u64, parts.next() orelse return existing.cur, 10) catch return existing.cur;
    if (parts.next() != null or installed != existing.cur) return existing.cur;
    return @max(existing.cur, @min(inherited, existing.max));
}

fn sizeText(buffer: []u8, bytes: u64) []const u8 {
    const gib: f64 = @floatFromInt(1 << 30);
    const mib: f64 = @floatFromInt(1 << 20);
    const value: f64 = @floatFromInt(bytes);
    return (if (bytes >= 1 << 30) std.fmt.bufPrint(buffer, "{d:.1} GiB", .{value / gib}) else std.fmt.bufPrint(buffer, "{d:.0} MiB", .{value / mib})) catch "?";
}

/// The refusal for a call-depth budget the memory ceiling cannot back, or null
/// when it fits, judged against the ceiling the guest will actually inherit.
pub fn frameRefusal(allocator: std.mem.Allocator, environ: *const std.process.Environ.Map, command: []const u8, who: []const u8, frames: u64, memory: u64) std.mem.Allocator.Error!?[]u8 {
    return frameRefusalUnder(allocator, .{ .command = command, .who = who }, frames, memory, guestAddressSpaceLimit(environ));
}

/// Who a frame-budget refusal speaks for: the command that refuses, and what runs the guest.
pub const Refuser = struct { command: []const u8, who: []const u8 };

/// `frameRefusal` against an explicit address-space limit. The text names the
/// reservation, what the guest may map, and the two ways out: a larger
/// `--max-memory` (or the inherited limit lifted) and a smaller `--max-frames`.
pub fn frameRefusalUnder(allocator: std.mem.Allocator, refuser: Refuser, frames: u64, memory: u64, address_space: ?u64) std.mem.Allocator.Error!?[]u8 {
    const maximum = (std.math.maxInt(u64) - frame_reserve - stack_slack) / frame_stack_bytes;
    if (frames > maximum) {
        const refused = try std.fmt.allocPrint(allocator, "selka {s}: a call-depth budget of {d} frames (--max-frames) exceeds the addressable native stack size; lower --max-frames to at most {d}\n", .{ refuser.command, frames, maximum });
        return refused;
    }
    const fit = frameFit(frames, memory, address_space);
    if (fit.fits) return null;
    const limit = fit.limit orelse return null;
    var need_buffer: [32]u8 = undefined;
    var limit_buffer: [32]u8 = undefined;
    const largest = (limit -| frame_reserve -| stack_slack) / frame_stack_bytes;
    const inherited_fix = "this process inherited an address-space limit below --max-memory; raise the caller's RLIMIT_AS (`ulimit -v`), or lower --max-frames to at most {d}";
    const fix = if (fit.inherited)
        try std.fmt.allocPrint(allocator, inherited_fix, .{largest})
    else
        try std.fmt.allocPrint(allocator, "raise --max-memory to at least {d}G, or lower --max-frames to at most {d}", .{ (fit.need + frame_reserve) / (1 << 30) + @intFromBool((fit.need + frame_reserve) % (1 << 30) != 0), largest });
    defer allocator.free(fix);
    const sentence = try std.fmt.allocPrint(allocator, "selka {s}: a call-depth budget of {d} frames (--max-frames) reserves {s} of native stack ({d} KiB per frame), but {s} may map only {s}: {s}\n", .{
        refuser.command, frames, sizeText(&need_buffer, fit.need), frame_stack_bytes >> 10, refuser.who, sizeText(&limit_buffer, limit), fix,
    });
    return sentence;
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
    /// Explicit `--jobs`/`SELKA_JOBS` width; null asks for the derived default.
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

/// Parse a `--jobs` or `SELKA_JOBS` width, rejecting zero and non-numeric text.
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

// spec: MEMORY-HOST-GUEST-1
test "only guest environments carry the compiler's original address-space ceiling" {
    const before = try std.posix.getrlimit(.AS);
    defer std.posix.setrlimit(.AS, before) catch unreachable;
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try environ.put(host_variable, "1G");
    try std.testing.expect(guardHost(&environ));
    try std.testing.expect(environ.get(restore_variable) == null);
    try guestEnvironment(std.testing.allocator, &environ);
    try std.testing.expect(environ.get(restore_variable) != null);
    try std.testing.expectEqual(@as(u64, (1 << 30) + headroom), (try std.posix.getrlimit(.AS)).cur);
}

// spec-case: MEMORY-HOST-GUEST-1
test "frame preflight uses the restorable caller ceiling without loosening the compiler" {
    const before = try std.posix.getrlimit(.AS);
    defer std.posix.setrlimit(.AS, before) catch unreachable;
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try environ.put(host_variable, "1G");
    try std.testing.expect(guardHost(&environ));
    try std.testing.expectEqual(optionalLimit(before.cur), guestAddressSpaceLimit(&environ));
    try std.testing.expectEqual(@as(u64, (1 << 30) + headroom), (try std.posix.getrlimit(.AS)).cur);
    const installed = (try std.posix.getrlimit(.AS)).cur;
    try std.testing.expectEqual(installed, restoredLimit("invalid", .{ .cur = installed, .max = before.max }));
    try std.testing.expectEqual(@as(u64, 100), restoredLimit("100:+200", .{ .cur = 100, .max = 200 }));
    try std.testing.expectEqual(@as(u64, 100), restoredLimit("100:2_00", .{ .cur = 100, .max = 200 }));
    try std.testing.expectEqual(@as(u64, 100), restoredLimit("100:18446744073709551616", .{ .cur = 100, .max = 200 }));
    try std.testing.expectEqual(@as(u64, 50), restoredLimit("100:200", .{ .cur = 50, .max = 200 }));
    try std.testing.expectEqual(@as(u64, 150), restoredLimit("100:200", .{ .cur = 100, .max = 150 }));
}

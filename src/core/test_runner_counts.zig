//! The `work:` line (NEW-CORE-TEST-WORK-1): a plain `selka test` prints one line
//! for a test whose executed steps changed by 2x or more, in either direction, since
//! the last run of the same test in the same build mode. The previous values are a
//! small per-worktree store under the cache directory (`--cache-dir`): one file per
//! mode and test name, so a later run of the same test compares with its own record
//! and a run in another mode never does. A missing record prints nothing.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const report = @import("test_runner_report.zig");
const test_work = @import("test_work.zig");

/// The store's directory, under the cache directory.
pub const root = "tests/work-v1";

/// Compare every verdict that carries counts with the store's previous value for the
/// same test and mode, give it the `work:` line when the step count crossed 2x, and
/// record the current values. Best effort: an unwritable store never fails a run.
pub fn compare(a: std.mem.Allocator, io: std.Io, cache: []const u8, mode: []const u8, verdicts: []report.Verdict) void {
    for (verdicts) |*verdict| {
        const counts = verdict.details.counts orelse continue;
        const path = recordPath(a, cache, mode, verdict.name) catch continue;
        const previous = test_work.read(a, io, path);
        verdict.details.work_line = line(a, verdict.name, previous, counts) catch "";
        test_work.write(a, io, path, counts);
    }
}

/// The line for one test, or "" when there is no previous value, either count is
/// zero (a ratio to zero is undefined) or neither changed by 2x. The ratio is the
/// new count over the old one, so a shrink prints a fraction (`0.2x`).
fn line(a: std.mem.Allocator, name: []const u8, previous: ?report.Counts, current: report.Counts) ![]const u8 {
    const old = previous orelse return "";
    if (old.steps == 0 or current.steps == 0) return "";
    const grown = @as(u128, current.steps) >= 2 * @as(u128, old.steps);
    const shrunk = @as(u128, old.steps) >= 2 * @as(u128, current.steps);
    if (!grown and !shrunk) return "";
    const ratio = @as(f64, @floatFromInt(current.steps)) / @as(f64, @floatFromInt(old.steps));
    return std.fmt.allocPrint(a, "work: {s} steps {s} → {s} ({d:.1}×)", .{
        name,
        try grouped(a, old.steps),
        try grouped(a, current.steps),
        ratio,
    });
}

/// `value` with a comma every three digits, as the line prints it.
fn grouped(a: std.mem.Allocator, value: u64) ![]const u8 {
    var digits: [20]u8 = undefined;
    const text = try std.fmt.bufPrint(&digits, "{d}", .{value});
    var out: std.ArrayList(u8) = .empty;
    for (text, 0..) |byte, index| {
        if (index != 0 and (text.len - index) % 3 == 0) try out.append(a, ',');
        try out.append(a, byte);
    }
    return out.toOwnedSlice(a);
}

/// The store file of one test in one build mode.
fn recordPath(a: std.mem.Allocator, cache: []const u8, mode: []const u8, name: []const u8) ![]const u8 {
    var digest: [16]u8 = undefined;
    fast_blake3.hash(name, &digest);
    return std.fmt.allocPrint(a, "{s}/{s}/{s}/{s}.txt", .{ cache, root, mode, std.fmt.bytesToHex(digest, .lower) });
}

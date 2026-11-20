//! One test trial's work (NEW-CORE-TEST-WORK-1), as the test runtime reports it, a
//! report carries it, and a receipt stores it. A leaf module, so the trial transport,
//! the report, the receipt stores and the runner's store can all name it without an
//! import cycle.
//!
//! `steps` is the executed blocks of program functions, the count the step ceiling
//! charges (docs/tooling/runtime-budgets.md). `peak_bytes` is the peak of the byte
//! ceiling's accounting: the 64 KiB chunks small blocks are carved from (charged
//! once, never refunded) plus every large block's usable size while it lives.
//! `allocations` is deliberately absent: the ceiling's accounting counts chunks and
//! large blocks, not block events, so counting events would add work to every
//! allocation (docs/tooling/guest-tests.md#work-per-test).
//!
//! A receipt keeps its pass record byte-exact and its work in a sidecar file beside
//! it (`PATH.work`), so a receipt written before counts were reported stays valid and
//! simply has none, and a store's exact-record rules never see the counts.
const std = @import("std");

/// A trial's executed blocks and peak managed bytes.
pub const Counts = struct { steps: u64 = 0, peak_bytes: u64 = 0 };

/// The suffix of the file that holds a receipt's work.
pub const suffix = ".work";

/// The sidecar path of the record at `path`.
pub fn sidecar(a: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}{s}", .{ path, suffix });
}

/// Read the counts `path` holds as `steps N\npeak_bytes M\n`; null when the file is
/// missing, damaged, or holds only one of the two lines.
pub fn read(a: std.mem.Allocator, io: std.Io, path: []const u8) ?Counts {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(64)) catch return null;
    var counts: Counts = .{};
    var seen_steps = false;
    var seen_peak = false;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |row| {
        var fields = std.mem.tokenizeScalar(u8, row, ' ');
        const key = fields.next() orelse continue;
        const value = std.fmt.parseInt(u64, fields.next() orelse continue, 10) catch continue;
        if (std.mem.eql(u8, key, "steps")) {
            counts.steps = value;
            seen_steps = true;
        } else if (std.mem.eql(u8, key, "peak_bytes")) {
            counts.peak_bytes = value;
            seen_peak = true;
        }
    }
    return if (seen_steps and seen_peak) counts else null;
}

/// Record `counts` at `path` as `steps N\npeak_bytes M\n`, atomically, so a reader
/// never takes a torn write for counts. Best effort: an unwritable path leaves no
/// counts, which reads exactly like a record written before counts were reported.
pub fn write(a: std.mem.Allocator, io: std.Io, path: []const u8, counts: Counts) void {
    const bytes = std.fmt.allocPrint(a, "steps {d}\npeak_bytes {d}\n", .{ counts.steps, counts.peak_bytes }) catch return;
    const temporary = std.fmt.allocPrint(a, "{s}.partial", .{path}) catch return;
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, std.fs.path.dirname(path) orelse ".") catch return;
    cwd.deleteFile(io, temporary) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return,
    };
    {
        const file = cwd.createFile(io, temporary, .{ .exclusive = true }) catch return;
        defer file.close(io);
        file.writeStreamingAll(io, bytes) catch return;
    }
    cwd.rename(temporary, cwd, path, io) catch return;
}

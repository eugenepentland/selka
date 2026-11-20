//! The process-owned handle of the engine's shadow in `selka test` (spec section 13, C2a).
//!
//! The test runner runs directory roots in threads of one process and as child processes, and the shadow needs one engine
//! per process whichever way an entry runs, so the command attaches it here, as `friction_session.zig` and
//! `profile_session.zig` do for their sinks. The pointer is opaque: the shadow's type lives in the core, which imports
//! this module and casts it back. The pointer stays fixed until every worker has joined.
const std = @import("std");

var active: std.atomic.Value(?*anyopaque) = .init(null);
var report: std.atomic.Value(bool) = .init(false);

/// Make `shadow` the process's engine shadow, or detach it with null.
pub fn attach(shadow: ?*anyopaque) void {
    active.store(shadow, .release);
}

/// The attached shadow, or null when none is: an entry's run pays one atomic load.
pub fn current() ?*anyopaque {
    return active.load(.acquire);
}

/// Ask for the engine report line at the end of the command (`selka test --engine-report`).
pub fn requestReport() void {
    report.store(true, .release);
}

/// Whether the command asked for the engine report line.
pub fn reportRequested() bool {
    return report.load(.acquire);
}

var compiler_lines: std.atomic.Value(usize) = .init(0);

/// Claim one of the finding lines the compiler's shadow may write in this process: true while fewer than `limit` have been
/// claimed. Sessions of a process share the budget, so a log does not fill with one run's findings.
pub fn claimCompilerLine(limit: usize) bool {
    return compiler_lines.fetchAdd(1, .monotonic) < limit;
}

//! Process-owned friction sink. Producers that render a diagnostic anywhere in the
//! compiler hand it here; the command's `friction_log.Recorder`, attached by CLI
//! process wiring, turns it into the record's `diagnostics` list. With nothing
//! attached every call is a single optional check.
const std = @import("std");
const diagnostic = @import("../diagnostic.zig");
const friction_log = @import("../friction_log.zig");
const project = @import("../project.zig");

// Only CLI process wiring attaches a recorder, as `profile_session.zig` does for
// developer telemetry. The pointer stays fixed until every worker has joined, and
// `lock` serializes concurrent producers (a parallel `selka test`).
var active: ?*friction_log.Recorder = null;
var lock: std.Io.Mutex = .init;

/// Make `recorder` the command's process-wide friction sink, or detach it with
/// null. Call sites that render a diagnostic deep inside the compiler reach it
/// through `note`, so the record carries every diagnostic the user saw whichever
/// layer rendered it (FRICTION-LOG-4).
pub fn attach(recorder: ?*friction_log.Recorder) void {
    active = recorder;
}

/// Record `item` in the attached recorder; a no-op when none is attached, so an
/// ordinary command pays one optional check.
pub fn note(item: diagnostic.Diagnostic) void {
    const recorder = active orelse return;
    lock.lockUncancelable(recorder.io);
    defer lock.unlock(recorder.io);
    recorder.addDiagnostic(item);
}

/// Record the diagnostics of `loaded`'s module-discovery problem (a bad module
/// header or name, a missing or unreadable import), which the project loader
/// carries outside the checker's diagnostic list. The problem's message text is
/// never read.
pub fn noteProject(loaded: *const project.Project) void {
    const problem = loaded.problem orelse return;
    if (problem.recovered.len != 0) {
        for (problem.recovered) |item| note(item);
        return;
    }
    note(.{ .code = problem.code, .span = problem.site.span, .message = "" });
}

/// Whether a recorder is attached, so a producer can skip building a diagnostic
/// that only the friction log would read.
pub fn enabled() bool {
    return active != null;
}

/// Name the source path the attached recorder judged, once a command's own
/// parser has learned it. A command that never reaches this call (a usage error)
/// leaves the path empty, and the caller then writes no record.
pub fn setEntry(path: []const u8) void {
    const recorder = active orelse return;
    lock.lockUncancelable(recorder.io);
    defer lock.unlock(recorder.io);
    recorder.invocation.path = path;
}

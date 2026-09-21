//! Opt-in friction log: one JSON line per command, appended only when asked for.
//!
//! Enablement is decided exactly once, by `destination`: `--friction-log=PATH`
//! wins, then the `MYLANG_FRICTION_LOG` environment variable, then nothing is
//! written and no file is created. The compiler only ever appends to the log;
//! it never reads it back, and a write failure never changes the command's exit
//! status, so logging can never break a compile.
//!
//! Privacy rules, enforced by what a record can carry and pinned by tests:
//! source text, diagnostic message text, environment values, and absolute paths
//! the user did not pass are never written. The only source path in a record is
//! the path exactly as the user typed it, and the log destination is not itself
//! recorded.
//!
//! Proposed `src/main.zig` call sites (this module does not wire them; the
//! `--friction-log=PATH` spelling below is the plan's, and `mylang test` parses
//! its own options and would accept the same spelling there):
//!
//! 1. `parseArgs`: accept `--friction-log=PATH`, reject a repeated flag, and
//!    store `Parsed.friction_log: ?[]const u8`; `ArgumentParser` gains the same
//!    `friction_log: ?[]const u8 = null` field.
//! 2. `run(init, parsed)`: measure the command, start one recorder, and finish
//!    it once the status is known:
//!
//!    ```zig
//!    const started = std.Io.Timestamp.now(init.io, .awake);
//!    var friction = friction_log.Recorder.init(init.gpa, init.io, init.environ, .{
//!        .flag = parsed.friction_log,
//!        .command = @tagName(parsed.command),
//!        .path = parsed.path,
//!        .snapshot = "",
//!        .compiler = try language.source_receipt.implementation(init.gpa, try compilerIdentity(init.io)),
//!    });
//!    defer if (friction) |*recorder| recorder.deinit();
//!    errdefer if (friction) |*recorder| recorder.finish(2, elapsedNs(init, started));
//!    if (friction) |*recorder| command_init.friction = recorder;
//!    // ... runCommand(command_init, with_frontend) ...
//!    if (friction) |*recorder| recorder.finish(status, elapsedNs(init, started));
//!    ```
//!
//!    `elapsedNs` is `@intCast(@max(0, started.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds))`,
//!    the same monotonic measurement `runNative` already takes. The snapshot is
//!    filled where the source is loaded, because `run` never sees the bytes:
//!    in `runCommand` after the single file is read,
//!    `recorder.snapshot = try friction_log.snapshotHex(init.gpa, bytes)`, and
//!    in `listModulesWithCache` after `loadModules` succeeds, the entry module's
//!    existing `digest` rendered as lowercase hex.
//! 3. `report(init, compilation)` and `reportProject`: after rendering each
//!    diagnostic, hand the same value to the recorder, so the record carries
//!    exactly the codes that were printed:
//!
//!    ```zig
//!    if (init.friction) |*recorder| recorder.addDiagnostic(diagnostic);
//!    ```
//!
//! 4. `Context` gains `friction: ?*friction_log.Recorder = null`, and
//!    `run()` points it at its local recorder for the duration of the command.

const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source_receipt = @import("source_receipt.zig");

/// Environment variable that names the log destination when the flag is absent.
pub const variable = "MYLANG_FRICTION_LOG";

/// Schema identifier written as the `version` field of every record.
pub const version = "friction-log-v1";

/// Compiler build identity carried by a record. It is the receipt module's own
/// implementation identity rather than a parallel struct, so a record and a
/// receipt can never disagree about which compiler produced them; build it with
/// `source_receipt.implementation`.
pub const Compiler = source_receipt.Implementation;

/// How the command was invoked: its spelling and the source path as given.
pub const Invocation = struct {
    /// Command spelling as typed, for example `check` or `run-project`.
    command: []const u8,
    /// Source path exactly as the user typed it; never resolved or rewritten.
    path: []const u8,
};

/// One diagnostic reduced to what a record may carry: code, severity, byte span.
pub const Finding = struct {
    /// Diagnostic code such as `E_ARITY`; never the diagnostic's message text.
    code: []const u8,
    /// `"error"` or `"warning"`, spelled as the text renderer spells them.
    severity: []const u8,
    /// First byte offset of the diagnostic's span in the checked snapshot.
    start: usize,
    /// One past the last byte offset of the diagnostic's span.
    end: usize,
};

/// Everything a caller must know before recording one command's outcome.
pub const Request = struct {
    /// `--friction-log=PATH` as typed, or null when the flag was not passed.
    flag: ?[]const u8,
    /// Command spelling, for example `check`, `run` or `test`.
    command: []const u8,
    /// Source path exactly as the user typed it.
    path: []const u8,
    /// Lowercase SHA-256 of the source snapshot the command checked, from
    /// `snapshotHex` or an existing `source_receipt.Input.sha256`.
    snapshot: []const u8,
    /// Build identity from `source_receipt.implementation`.
    compiler: Compiler,
};

/// The JSON object written for one command: seven fields and no message text.
const Record = struct {
    version: []const u8,
    invocation: Invocation,
    compiler: Compiler,
    snapshot: []const u8,
    diagnostics: []const Finding,
    status: u8,
    wall_ns: u64,
};

/// Resolve the log destination before touching the file system: the flag wins,
/// then `MYLANG_FRICTION_LOG`; an absent or empty value means off. Every hook
/// that offers `--friction-log=PATH` shares this one decision.
pub fn destination(flag: ?[]const u8, environ: *const std.process.Environ.Map) ?[]const u8 {
    const path = flag orelse environ.get(variable) orelse return null;
    return if (path.len == 0) null else path;
}

/// Collects one command's diagnostics and appends its single record on `finish`.
///
/// `init` returns null when recording is off, so a call site that never asked
/// for a log pays one optional check. Every method is best effort: an allocation
/// or file-system failure drops information rather than failing the command.
pub const Recorder = struct {
    /// Destination exactly as given, or null once a record has been written.
    log_path: ?[]const u8,
    /// Handle used for the append; supplied by the caller.
    io: std.Io,
    /// Allocator that owns the collected codes and the serialized line.
    allocator: std.mem.Allocator,
    /// Command spelling and source path exactly as the user typed them.
    invocation: Invocation,
    /// Compiler build identity carried by every record in this session.
    compiler: Compiler,
    /// Source snapshot digest carried by every record in this session.
    snapshot: []const u8,
    /// Diagnostics collected so far, in the order they were rendered.
    diagnostics: std.ArrayList(Finding),

    /// Start recording, or return null when neither the flag nor the
    /// environment asked for a log. The destination is never normalized, so a
    /// relative path stays relative to the process working directory.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request) ?Recorder {
        return .{
            .log_path = destination(request.flag, environ) orelse return null,
            .io = io,
            .allocator = allocator,
            .invocation = .{ .command = request.command, .path = request.path },
            .compiler = request.compiler,
            .snapshot = request.snapshot,
            .diagnostics = .empty,
        };
    }

    /// Release the diagnostic codes collected for the record.
    pub fn deinit(self: *Recorder) void {
        for (self.diagnostics.items) |finding| self.allocator.free(finding.code);
        self.diagnostics.deinit(self.allocator);
        self.diagnostics = .empty;
    }

    /// Record one diagnostic's code, severity and byte span. The message text,
    /// any related notes and the stack trace are deliberately dropped: they
    /// quote source, which the log never carries.
    pub fn addDiagnostic(self: *Recorder, item: diagnostic.Diagnostic) void {
        const code = self.allocator.dupe(u8, item.code) catch return;
        self.diagnostics.append(self.allocator, .{
            .code = code,
            .severity = if (item.severity == .err) "error" else "warning",
            .start = item.span.start,
            .end = item.span.end,
        }) catch self.allocator.free(code);
    }

    /// Append this command's one JSON line and disarm the recorder, so a second
    /// call writes nothing. `wall_ns` is the command's monotonic duration in
    /// nanoseconds, never a calendar date.
    pub fn finish(self: *Recorder, status: u8, wall_ns: u64) void {
        const path = self.log_path orelse return;
        self.log_path = null;
        const json = std.json.Stringify.valueAlloc(self.allocator, Record{
            .version = version,
            .invocation = self.invocation,
            .compiler = self.compiler,
            .snapshot = self.snapshot,
            .diagnostics = self.diagnostics.items,
            .status = status,
            .wall_ns = wall_ns,
        }, .{}) catch return;
        defer self.allocator.free(json);
        const line = std.fmt.allocPrint(self.allocator, "{s}\n", .{json}) catch return;
        defer self.allocator.free(line);
        appendLine(self.io, path, line) catch return;
    }
};

/// Lowercase SHA-256 of a source snapshot, in the spelling
/// `source_receipt.Input.sha256` and `project.Module.digest` already use.
pub fn snapshotHex(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

/// Append one complete line to `path`, creating the file and any missing parent
/// directory. A concurrent writer is serialized with an advisory exclusive lock
/// when the file system offers one; the unlocked path still appends rather than
/// failing the command.
fn appendLine(io: std.Io, path: []const u8, line: []const u8) !void {
    if (std.fs.path.dirname(path)) |directory| try std.Io.Dir.cwd().createDirPath(io, directory);
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false, .read = true });
    defer file.close(io);
    const locked = file.tryLock(io, .exclusive) catch false;
    defer if (locked) file.unlock(io);
    // Without a usable length the append would overwrite earlier records, so a
    // failed stat drops this record instead.
    const offset = file.length(io) catch return;
    try file.writePositionalAll(io, line, offset);
}

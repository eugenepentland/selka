//! The line a failed build prints when its error carries no diagnostic of its own.
//!
//! `pipeline.Error` names a source error (diagnostics were printed), a refusal, a denied capability, or one of the errors
//! below, which a command line used to turn into exit status 2 without a word: a tool that failed, an output that could
//! not be written, a cached record that was missing or unusable after the complete retry. A command appends this line to the
//! report before it exits, so a failure always names the error and the work directory whose records it concerns.
const std = @import("std");
const pipeline = @import("pipeline.zig");

/// The directory of the stage store inside a work directory (`stage_store.zig`).
const stages_leaf = "stages-packed-v1";

/// What `err` means to a reader, or null for an error that has diagnostics of its own.
fn meaning(err: pipeline.Error) ?[]const u8 {
    return switch (err) {
        error.CacheMiss, error.InvalidIr => "a cached stage record was missing or unusable and the build could not recompute it",
        error.ToolFailed => "a build tool failed",
        error.WriteFailed => "a build output could not be written",
        error.ConfigurationFailed => "the build's configuration was refused",
        error.SourceError, error.Unsupported, error.PolicyDenied, error.OutOfMemory => null,
    };
}

/// The one line that names `err` and the stage store of the work directory `cache`, ending in a newline; null when `err`
/// already printed its diagnostics.
pub fn line(a: std.mem.Allocator, err: pipeline.Error, cache: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const what = meaning(err) orelse return null;
    const text = try std.fmt.allocPrint(a, "selka: build failed ({s}): {s}; stage store {s}/{s}\n", .{ @errorName(err), what, cache, stages_leaf });
    return text;
}

/// The internal errors that end a build with `InvalidIr` after printing what they found: a validator's rejection and the IR
/// verifier's refusal. A report that holds one has said why the build failed, and no stage record was missing.
const checked_codes = [_][]const u8{ "error[E_OWNERSHIP_VALIDATION]", "error[E_FACT_VALIDATION]", "error[E_CORE_INVALID_IR]", "error[E_CORE_HIDDEN_COPY]" };

/// Whether `report` already says why a build failed: an `InvalidIr` with one of `checked_codes`, or a refused configuration
/// whose `E_PROJECT_CONFIG` line names the file and the entry (a `links` entry that names no file, a malformed `selka.json`).
fn explained(err: pipeline.Error, report: []const u8) bool {
    if (err == error.ConfigurationFailed) return std.mem.indexOf(u8, report, "error[E_PROJECT_CONFIG]") != null;
    if (err != error.InvalidIr) return false;
    for (checked_codes) |code| if (std.mem.indexOf(u8, report, code) != null) return true;
    return false;
}

/// Append the line for `err` to `report`, when it has one and `report` has not already said why the build failed.
pub fn note(a: std.mem.Allocator, report: *std.ArrayList(u8), err: pipeline.Error, cache: []const u8) std.mem.Allocator.Error!void {
    if (explained(err, report.items)) return;
    const text = (try line(a, err, cache)) orelse return;
    defer a.free(text);
    try report.appendSlice(a, text);
}

test "an error without diagnostics is named with its work directory, one line each" {
    const a = std.testing.allocator;
    const invalid = (try line(a, error.InvalidIr, "/work/.selka-cache/core")).?;
    defer a.free(invalid);
    try std.testing.expectEqualStrings("selka: build failed (InvalidIr): a cached stage record was missing or unusable and the build could not recompute it; stage store /work/.selka-cache/core/stages-packed-v1\n", invalid);
    const written = (try line(a, error.WriteFailed, "cache")).?;
    defer a.free(written);
    try std.testing.expectEqualStrings("selka: build failed (WriteFailed): a build output could not be written; stage store cache/stages-packed-v1\n", written);
    const missed = (try line(a, error.CacheMiss, "c")).?;
    defer a.free(missed);
    try std.testing.expect(std.mem.startsWith(u8, missed, "selka: build failed (CacheMiss): "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, missed, "\n"));
}

test "errors that printed their diagnostics add no line, and a note lands in the report" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(?[]const u8, null), try line(a, error.SourceError, "c"));
    try std.testing.expectEqual(@as(?[]const u8, null), try line(a, error.Unsupported, "c"));
    try std.testing.expectEqual(@as(?[]const u8, null), try line(a, error.PolicyDenied, "c"));
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    try report.appendSlice(a, "warning: earlier\n");
    try note(a, &report, error.ToolFailed, "c");
    try note(a, &report, error.SourceError, "c");
    try std.testing.expectEqualStrings("warning: earlier\nselka: build failed (ToolFailed): a build tool failed; stage store c/stages-packed-v1\n", report.items);
}

test "a refused configuration that printed its E_PROJECT_CONFIG line adds no line naming the stage store" {
    const a = std.testing.allocator;
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    const said = "selka.json: error[E_PROJECT_CONFIG]: links entry \"c.c\" names no file (/p/c.c)\n";
    try report.appendSlice(a, said);
    try note(a, &report, error.ConfigurationFailed, "c");
    try std.testing.expectEqualStrings(said, report.items);
    var silent: std.ArrayList(u8) = .empty;
    defer silent.deinit(a);
    try note(a, &silent, error.ConfigurationFailed, "c");
    try std.testing.expect(std.mem.startsWith(u8, silent.items, "selka: build failed (ConfigurationFailed): "));
}

test "a validator's rejection or the verifier's refusal is the failure's explanation: no line about a missing record follows it" {
    const a = std.testing.allocator;
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    try report.appendSlice(a, "error[E_FACT_VALIDATION]: fact validation rejected f at block b1, value %18: F3 (phi)\n");
    try note(a, &report, error.InvalidIr, "c");
    try std.testing.expectEqualStrings("error[E_FACT_VALIDATION]: fact validation rejected f at block b1, value %18: F3 (phi)\n", report.items);
    report.clearRetainingCapacity();
    try report.appendSlice(a, "internal error[E_CORE_INVALID_IR]: f: bad\n");
    try note(a, &report, error.InvalidIr, "c");
    try std.testing.expectEqualStrings("internal error[E_CORE_INVALID_IR]: f: bad\n", report.items);
    // With nothing said, the line names the stage store as before; a cache miss is never explained away.
    report.clearRetainingCapacity();
    try note(a, &report, error.InvalidIr, "c");
    try std.testing.expect(std.mem.startsWith(u8, report.items, "selka: build failed (InvalidIr): "));
    report.clearRetainingCapacity();
    try report.appendSlice(a, "error[E_OWNERSHIP_VALIDATION]: x\n");
    try note(a, &report, error.CacheMiss, "c");
    try std.testing.expect(std.mem.indexOf(u8, report.items, "selka: build failed (CacheMiss): ") != null);
}

//! `@vectorize` in a release build: each marked loop must vectorize. The emitter writes one comment
//! per marked loop (`; vectorize <path>:<line>:<col>`) into the unit's LLVM text, and the release
//! compile of such a unit prints LLVM's remarks for that location. A loop that LLVM analysed and
//! could not vectorize fails the build with the reason LLVM gave.
const std = @import("std");

/// The comment the emitter writes for a `@vectorize` loop, before the location.
pub const marker = "; vectorize ";

/// The remark flags a release compile of a unit with a marked loop adds: the vectorizer's own
/// remarks, and its analysis remarks, which name why a loop was not vectorized. zig's compile cache
/// replays an object without its remarks, so the driver adds a per-process define as well.
pub const remark_flags = [_][]const u8{ "-Rpass=loop-vectorize", "-Rpass-missed=loop-vectorize", "-Rpass-analysis=loop-vectorize" };

/// Whether a unit's LLVM text marks any loop for vectorization (so its release compile needs the remarks).
pub fn marksLoops(llvm: []const u8) bool {
    return std.mem.indexOf(u8, llvm, "\n  " ++ marker) != null;
}

/// One line per marked loop that LLVM analysed and did not vectorize, as
/// `<path>:<line>:<col>: error[E_VECTORIZE_FAILED]: ...` with LLVM's reason. Empty when every
/// marked loop vectorized, or when LLVM printed no remark for it (the loop was folded away).
pub fn failures(allocator: std.mem.Allocator, llvm: []const u8, log: []const u8) std.mem.Allocator.Error![]u8 {
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(allocator);
    var lines = std.mem.splitScalar(u8, llvm, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " ");
        if (!std.mem.startsWith(u8, line, marker)) continue;
        const where = line[marker.len..];
        const vectorized = try std.fmt.allocPrint(allocator, "remark: {s}: vectorized loop", .{where});
        defer allocator.free(vectorized);
        if (std.mem.indexOf(u8, log, vectorized) != null) continue;
        const missed = try std.fmt.allocPrint(allocator, "remark: {s}: loop not vectorized", .{where});
        defer allocator.free(missed);
        // The analysis remark carries the reason; a forced loop that failed without one still fails.
        const reason = if (std.mem.indexOf(u8, log, missed)) |at| analysisReason(log[at + missed.len ..]) else null;
        const text = reason orelse if (std.mem.indexOf(u8, log, missed) != null) "LLVM's loop vectorizer did not vectorize it" else continue;
        try report.print(allocator, "{s}: error[E_VECTORIZE_FAILED]: a @vectorize loop was not vectorized: {s}\n", .{ where, text });
    }
    return report.toOwnedSlice(allocator);
}

/// The log without LLVM's remark lines (tagged `[-Rpass` or `[-Wpass-failed`), which only a
/// `@vectorize` check reads: a successful build prints none of them. Other lines are kept as they are.
pub fn withoutRemarks(allocator: std.mem.Allocator, log: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.indexOf(u8, log, "[-R") == null and std.mem.indexOf(u8, log, "[-Wpass-failed") == null) return log;
    var kept: std.ArrayList(u8) = .empty;
    errdefer kept.deinit(allocator);
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        const remark = std.mem.indexOf(u8, line, "[-R") != null or std.mem.indexOf(u8, line, "[-Wpass-failed") != null;
        if (remark or std.mem.indexOf(u8, line, " generated.") != null) continue;
        if (line.len == 0 and lines.peek() == null) continue;
        try kept.appendSlice(allocator, line);
        try kept.append(allocator, '\n');
    }
    const text = try kept.toOwnedSlice(allocator);
    if (std.mem.trim(u8, text, " \n").len == 0) {
        allocator.free(text);
        return "";
    }
    return text;
}

/// The reason of an analysis remark (`: <reason> [-Rpass-analysis]`), or null for the bare
/// `(Force=true)` remark that carries none.
fn analysisReason(rest: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, rest, ": ")) return null;
    return reasonAt(rest[2..]);
}

/// The reason text of a remark: the rest of its line without LLVM's trailing `[-Rpass...]` tag.
fn reasonAt(rest: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const line = rest[0..end];
    const tag = std.mem.lastIndexOf(u8, line, " [-R") orelse line.len;
    return std.mem.trimEnd(u8, line[0..tag], " \r");
}

test "a marked loop that vectorized is not a failure" {
    const llvm = "define void @f() {\n  ; vectorize src.selka:3:5\n}\n";
    const log = "remark: src.selka:3:5: vectorized loop (vectorization width: 4, interleaved count: 2) [-Rpass=loop-vectorize]\n";
    const report = try failures(std.testing.allocator, llvm, log);
    defer std.testing.allocator.free(report);
    try std.testing.expectEqualStrings("", report);
}

test "a marked loop LLVM could not vectorize names its reason" {
    const llvm = "define void @f() {\n  ; vectorize src.selka:13:3\n}\n";
    const log = "remark: src.selka:13:3: loop not vectorized: call instruction cannot be vectorized [-Rpass-analysis]\n" ++
        "remark: src.selka:13:3: loop not vectorized (Force=true) [-Rpass-missed=loop-vectorize]\n";
    const report = try failures(std.testing.allocator, llvm, log);
    defer std.testing.allocator.free(report);
    try std.testing.expectEqualStrings("src.selka:13:3: error[E_VECTORIZE_FAILED]: a @vectorize loop was not vectorized: call instruction cannot be vectorized\n", report);
}

test "a marked loop with no remark is not reported, and a 1-vs-11 column never matches the wrong loop" {
    const llvm = "  ; vectorize src.selka:1:1\n  ; vectorize src.selka:11:1\n";
    const log = "remark: src.selka:111:1: loop not vectorized: instruction cannot be vectorized [-Rpass-analysis]\n";
    const report = try failures(std.testing.allocator, llvm, log);
    defer std.testing.allocator.free(report);
    try std.testing.expectEqualStrings("", report);
}

test "only a marked unit asks for remarks" {
    try std.testing.expect(marksLoops("define void @f() {\n  br label %b1\n  ; vectorize src.selka:1:1\n}\n"));
    try std.testing.expect(!marksLoops("define void @f() {\n  br label %b1\n}\n"));
}

test "remark lines leave a build log and the other lines stay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const kept = try withoutRemarks(arena.allocator(), "warning: x\nremark: a.selka:1:1: vectorized loop [-Rpass=loop-vectorize]\n1 warning generated.\nerror: y\n");
    try std.testing.expectEqualStrings("warning: x\nerror: y\n", kept);
}

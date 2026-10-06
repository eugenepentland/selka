//! What `mylang-core test` prints: the old runner's per-test lines and summary line, or a
//! JSON report with the same `name`/`status`/`reason` keys as `mylang test --json`
//! (`native-tests-v1`), plus the `unsupported` status the old runner has no use for.
const std = @import("std");

/// How one test ended.
pub const Status = enum {
    passed,
    failed,
    /// The new core refuses a feature the test uses (`E_CORE_UNSUPPORTED`): neither a pass nor a failure.
    unsupported,
};

/// One test's verdict.
pub const Verdict = struct {
    /// `module::test_x`.
    name: []const u8,
    status: Status,
    /// Why it failed or is unsupported; failure reasons may span several lines (a trap's frames).
    reason: []const u8 = "",
    /// `line:column` of the refused construct, for an unsupported test.
    at: []const u8 = "",
    /// Exact property trial and counterexample evidence when this is a property.
    property: ?@import("test_runner_property.zig").Evidence = null,
};

/// The process exit status for a run: 1 when any test failed, 3 when none was selected, else 0.
pub fn exitStatus(verdicts: []const Verdict) u8 {
    if (verdicts.len == 0) return 3;
    for (verdicts) |verdict| if (verdict.status == .failed) return 1;
    return 0;
}

fn count(verdicts: []const Verdict, status: Status) usize {
    var total: usize = 0;
    for (verdicts) |verdict| total += @intFromBool(verdict.status == status);
    return total;
}

/// The text report: one line per test (`passed NAME`, `failed NAME: REASON`,
/// `unsupported NAME: E_CORE_UNSUPPORTED (REASON) at L:C`), then the old runner's summary
/// line, with `, N unsupported` appended only when some test was refused.
pub fn text(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (verdicts) |verdict| switch (verdict.status) {
        .passed => try out.print(allocator, "passed {s}\n", .{verdict.name}),
        .failed => try out.print(allocator, "failed {s}: {s}\n", .{ verdict.name, std.mem.trimEnd(u8, verdict.reason, "\n") }),
        .unsupported => {
            try out.print(allocator, "unsupported {s}: E_CORE_UNSUPPORTED ({s})", .{ verdict.name, verdict.reason });
            if (verdict.at.len != 0) try out.print(allocator, " at {s}", .{verdict.at});
            try out.appendSlice(allocator, "\n");
        },
    };
    try out.print(allocator, "{d} passed, 0 cached, {d} failed, 0 skipped", .{ count(verdicts, .passed), count(verdicts, .failed) });
    const refused = count(verdicts, .unsupported);
    if (refused != 0) try out.print(allocator, ", {d} unsupported", .{refused});
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

/// The JSON report: `{"version":"native-tests-v1","tests":[{"name","status","reason","at"}],"passed":…,"failed":…,"skipped":0,"cached":0,"unsupported":…}`.
pub fn json(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "{\"version\":\"native-tests-v1\",\"tests\":[");
    for (verdicts, 0..) |verdict, position| {
        if (position != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, "{\"name\":");
        try quoted(allocator, &out, verdict.name);
        try out.print(allocator, ",\"status\":\"{s}\",\"reason\":", .{@tagName(verdict.status)});
        try quoted(allocator, &out, verdict.reason);
        try out.appendSlice(allocator, ",\"at\":");
        try quoted(allocator, &out, verdict.at);
        if (verdict.property) |evidence| {
            try out.appendSlice(allocator, ",\"property\":");
            try out.appendSlice(allocator, try std.json.Stringify.valueAlloc(allocator, evidence, .{}));
        }
        try out.appendSlice(allocator, "}");
    }
    try out.print(allocator, "],\"passed\":{d},\"failed\":{d},\"skipped\":0,\"cached\":0,\"unsupported\":{d}}}\n", .{ count(verdicts, .passed), count(verdicts, .failed), count(verdicts, .unsupported) });
    return out.toOwnedSlice(allocator);
}

fn quoted(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) std.mem.Allocator.Error!void {
    try out.append(allocator, '"');
    for (value) |byte| switch (byte) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...31 => try out.print(allocator, "\\u{x:0>4}", .{byte}),
        else => try out.append(allocator, byte),
    };
    try out.append(allocator, '"');
}

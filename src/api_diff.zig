//! `selka api-diff`: classify interface changes between a recorded baseline
//! and the current checked project.
//!
//! The baseline is a line-oriented snapshot of every declaration's identity and
//! its interface/body fingerprints (`api-diff-baseline-v1`). A change is
//! additive when an identity is new, breaking when an identity disappeared or
//! its interface fingerprint changed, and compatible when only the body
//! fingerprint moved. The report never blocks: it is the classified answer a
//! maintainer or an agent reads before publishing.
const std = @import("std");
const incremental = @import("incremental.zig");
const project_compile = @import("project_compile.zig");

/// Failures an api-diff run reports.
pub const Error = error{ InternalError, InvalidBaseline, OutOfMemory };

/// Baseline format marker written as the first line.
pub const version = "api-diff-baseline-v1";

/// How one declaration changed between the baseline and the working tree.
pub const Class = enum { additive, compatible, breaking };

/// One declaration identity and its fingerprints, read from a baseline or
/// measured in the current project.
pub const Entry = struct {
    identity: []const u8,
    display: []const u8,
    kind: []const u8,
    interface: []const u8,
    body: []const u8,
};

/// One classified change with the declaration it names.
pub const Change = struct {
    class: Class,
    display: []const u8,
    detail: []const u8,
};

/// The full classified comparison.
pub const Report = struct {
    additive: []const Change,
    compatible: []const Change,
    breaking: []const Change,
    unchanged: usize,
};

/// Snapshot every declaration's identity and fingerprints for the current
/// project, one tab-separated row per declaration.
pub fn snapshot(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error![]u8 {
    const report = incremental.describePartial(allocator, compilation) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    defer incremental.deinit(report, allocator);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    writer.print("# {s}\n", .{version}) catch return error.OutOfMemory;
    for (report.modules) |module| {
        for (module.declarations) |declaration| {
            writer.print("{s}\t{s}::{s}\t{s}\t{s}\t{s}\n", .{
                declaration.identity,
                module.name,
                declaration.name,
                declaration.kind,
                declaration.interface_sha256 orelse "-",
                declaration.body_sha256 orelse "-",
            }) catch return error.OutOfMemory;
        }
    }
    const owned = try out.toOwnedSlice();
    return owned;
}

/// Release every owned string in a parsed baseline.
pub fn freeEntries(allocator: std.mem.Allocator, entries: []const Entry) void {
    for (entries) |entry| {
        allocator.free(entry.identity);
        allocator.free(entry.display);
        allocator.free(entry.kind);
        allocator.free(entry.interface);
        allocator.free(entry.body);
    }
    allocator.free(entries);
}

/// Parse one `api-diff-baseline-v1` snapshot. Comments and blank lines are
/// skipped; a row with the wrong field count is rejected.
pub fn parseBaseline(allocator: std.mem.Allocator, bytes: []const u8) Error![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.identity);
            allocator.free(entry.display);
            allocator.free(entry.kind);
            allocator.free(entry.interface);
            allocator.free(entry.body);
        }
        entries.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var saw_header = false;
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        if (row[0] == '#') {
            saw_header = true;
            continue;
        }
        var fields = std.mem.splitScalar(u8, row, '\t');
        const identity = fields.next() orelse return error.InvalidBaseline;
        const display = fields.next() orelse return error.InvalidBaseline;
        const kind = fields.next() orelse return error.InvalidBaseline;
        const interface = fields.next() orelse return error.InvalidBaseline;
        const body = fields.next() orelse return error.InvalidBaseline;
        if (fields.next() != null) return error.InvalidBaseline;
        try entries.append(allocator, .{
            .identity = try allocator.dupe(u8, identity),
            .display = try allocator.dupe(u8, display),
            .kind = try allocator.dupe(u8, kind),
            .interface = try allocator.dupe(u8, interface),
            .body = try allocator.dupe(u8, body),
        });
    }
    if (!saw_header) return error.InvalidBaseline;
    return entries.toOwnedSlice(allocator);
}

/// Read the current project's entries out of a rendered snapshot.
fn currentEntries(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error![]Entry {
    const bytes = try snapshot(allocator, compilation);
    defer allocator.free(bytes);
    return parseBaseline(allocator, bytes);
}

/// Classify one current entry against the baseline entry with the same identity.
fn classify(baseline: Entry, current: Entry, allocator: std.mem.Allocator) Error!?Change {
    if (!std.mem.eql(u8, baseline.interface, current.interface)) {
        return .{ .class = .breaking, .display = try allocator.dupe(u8, current.display), .detail = "interface changed" };
    }
    if (!std.mem.eql(u8, baseline.body, current.body)) {
        return .{ .class = .compatible, .display = try allocator.dupe(u8, current.display), .detail = "body changed" };
    }
    return null;
}

/// Compare a baseline against the current project and classify every change.
/// Changed display names are allocations the caller owns until `freeChanges`.
pub fn compare(allocator: std.mem.Allocator, baseline: []const Entry, compilation: *project_compile.Compilation) Error!Report {
    const current = try currentEntries(allocator, compilation);
    defer freeEntries(allocator, current);
    return compareEntries(allocator, baseline, current);
}

/// Classify current entries against baseline entries. Pure: no compiler state,
/// so the classification is unit-testable on its own.
pub fn compareEntries(allocator: std.mem.Allocator, baseline: []const Entry, current: []const Entry) Error!Report {
    var by_identity: std.StringHashMapUnmanaged(usize) = .empty;
    defer by_identity.deinit(allocator);
    for (baseline, 0..) |entry, index| try by_identity.put(allocator, entry.identity, index);
    var additive: std.ArrayList(Change) = .empty;
    errdefer additive.deinit(allocator);
    var compatible: std.ArrayList(Change) = .empty;
    errdefer compatible.deinit(allocator);
    var breaking: std.ArrayList(Change) = .empty;
    errdefer breaking.deinit(allocator);
    var unchanged: usize = 0;
    var seen = try allocator.alloc(bool, baseline.len);
    defer allocator.free(seen);
    @memset(seen, false);
    for (current) |entry| {
        const index = by_identity.get(entry.identity) orelse {
            try additive.append(allocator, .{ .class = .additive, .display = try allocator.dupe(u8, entry.display), .detail = "new declaration" });
            continue;
        };
        seen[index] = true;
        if (try classify(baseline[index], entry, allocator)) |change| {
            if (change.class == .breaking) {
                try breaking.append(allocator, change);
            } else {
                try compatible.append(allocator, change);
            }
        } else {
            unchanged += 1;
        }
    }
    for (baseline, 0..) |entry, index| {
        if (seen[index]) continue;
        try breaking.append(allocator, .{ .class = .breaking, .display = try allocator.dupe(u8, entry.display), .detail = "removed declaration" });
    }
    return .{
        .additive = try additive.toOwnedSlice(allocator),
        .compatible = try compatible.toOwnedSlice(allocator),
        .breaking = try breaking.toOwnedSlice(allocator),
        .unchanged = unchanged,
    };
}

/// Release the display names `compare` allocated.
pub fn freeChanges(allocator: std.mem.Allocator, report: Report) void {
    for (report.additive) |change| allocator.free(change.display);
    allocator.free(report.additive);
    for (report.compatible) |change| allocator.free(change.display);
    allocator.free(report.compatible);
    for (report.breaking) |change| allocator.free(change.display);
    allocator.free(report.breaking);
}

/// Render the classified report as text, or as one `api-diff-v1` JSON object.
pub fn render(allocator: std.mem.Allocator, report: Report, json: bool) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    if (json) {
        writer.writeAll("{\"version\":\"api-diff-v1\"") catch return error.OutOfMemory;
        try writeJsonList(writer, "additive", report.additive);
        try writeJsonList(writer, "compatible", report.compatible);
        try writeJsonList(writer, "breaking", report.breaking);
        writer.print(",\"unchanged\":{d}}}\n", .{report.unchanged}) catch return error.OutOfMemory;
    } else {
        writer.print("api-diff: additive={d} compatible={d} breaking={d} unchanged={d}\n", .{
            report.additive.len, report.compatible.len, report.breaking.len, report.unchanged,
        }) catch return error.OutOfMemory;
        try writeTextList(writer, "additive", report.additive);
        try writeTextList(writer, "compatible", report.compatible);
        try writeTextList(writer, "breaking", report.breaking);
    }
    const owned = try out.toOwnedSlice();
    return owned;
}

fn writeTextList(writer: *std.Io.Writer, label: []const u8, changes: []const Change) Error!void {
    for (changes) |change| {
        writer.print("  {s}: {s} ({s})\n", .{ label, change.display, change.detail }) catch return error.OutOfMemory;
    }
}

fn writeJsonList(writer: *std.Io.Writer, label: []const u8, changes: []const Change) Error!void {
    writer.print(",\"{s}\":[", .{label}) catch return error.OutOfMemory;
    for (changes, 0..) |change, index| {
        if (index != 0) writer.writeAll(",") catch return error.OutOfMemory;
        writer.print("\"{s}\"", .{change.display}) catch return error.OutOfMemory;
    }
    writer.writeAll("]") catch return error.OutOfMemory;
}

// spec: API-DIFF-1
test "api-diff classifies added compatible and breaking declarations" {
    const allocator = std.testing.allocator;
    const baseline_bytes = "# api-diff-baseline-v1\n" ++
        "a::gone\tapp::gone\tfunction\tiface-a\tbody-a\n" ++
        "a::same\tapp::same\tfunction\tiface-b\tbody-b\n" ++
        "a::moved\tapp::moved\tfunction\tiface-c\tbody-c\n";
    const baseline = try parseBaseline(allocator, baseline_bytes);
    defer freeEntries(allocator, baseline);
    try std.testing.expectEqual(@as(usize, 3), baseline.len);
    const current = [_]Entry{
        .{ .identity = "a::same", .display = "app::same", .kind = "function", .interface = "iface-b", .body = "body-b" },
        .{ .identity = "a::moved", .display = "app::moved", .kind = "function", .interface = "iface-c", .body = "body-c2" },
        .{ .identity = "a::new", .display = "app::new", .kind = "function", .interface = "iface-d", .body = "body-d" },
    };
    const report = try compareEntries(allocator, baseline, &current);
    defer freeChanges(allocator, report);
    try std.testing.expectEqual(@as(usize, 1), report.additive.len);
    try std.testing.expectEqual(@as(usize, 1), report.compatible.len);
    try std.testing.expectEqual(@as(usize, 1), report.breaking.len);
    try std.testing.expectEqual(@as(usize, 1), report.unchanged);
    try std.testing.expectEqualStrings("app::gone", report.breaking[0].display);
    try std.testing.expectEqualStrings("app::new", report.additive[0].display);
    const text = try render(allocator, report, false);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "api-diff: additive=1 compatible=1 breaking=1 unchanged=1") != null);
    const json = try render(allocator, report, true);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":\"api-diff-v1\"") != null);
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(allocator, "not a baseline\n"));
}

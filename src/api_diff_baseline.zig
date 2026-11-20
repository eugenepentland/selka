//! `selka api-diff`: classify interface changes between a recorded baseline
//! and the current checked project.
//!
//! Versioned baselines record declaration fingerprints, normalized return
//! sources and the digest of the remaining contract. Narrowing to a nonempty
//! source subset is compatible when that remaining contract is unchanged.
//! Removing every source, adding a source and other interface changes are
//! breaking. Body-only changes are compatible.
const std = @import("std");

/// Failures an api-diff run reports.
pub const Error = error{ InternalError, InvalidBaseline, OutOfMemory };

/// Baseline format marker written as the first line.
pub const version = "api-diff-baseline-v2";

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
    without_sources: []const u8 = "-",
    sources: []const u8 = "-",
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

/// Serialize baseline entries in qualified-name order, independent of input order.
pub fn serialize(allocator: std.mem.Allocator, entries: []const Entry) Error![]u8 {
    const sorted = try allocator.dupe(Entry, entries);
    defer allocator.free(sorted);
    std.mem.sort(Entry, sorted, {}, entryLess);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    out.writer.print("# {s}\n", .{version}) catch return error.OutOfMemory;
    for (sorted) |entry| out.writer.print("{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\n", .{
        entry.identity, entry.display, entry.kind, entry.interface, entry.body, entry.without_sources, entry.sources,
    }) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn entryLess(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.display, b.display);
}

/// Release every owned string in a parsed baseline.
pub fn freeEntries(allocator: std.mem.Allocator, entries: []const Entry) void {
    for (entries) |entry| {
        allocator.free(entry.identity);
        allocator.free(entry.display);
        allocator.free(entry.kind);
        allocator.free(entry.interface);
        allocator.free(entry.body);
        allocator.free(entry.without_sources);
        allocator.free(entry.sources);
    }
    allocator.free(entries);
}

/// Parse a release baseline only when its explicit version marker is present.
/// The older api-diff reader retains its permissive comment-header behavior.
pub fn parseReleaseBaseline(allocator: std.mem.Allocator, bytes: []const u8) Error![]Entry {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        if (!std.mem.eql(u8, row, "# " ++ version) and !std.mem.eql(u8, row, "# api-diff-baseline-v1")) return error.InvalidBaseline;
        return parseBaseline(allocator, bytes);
    }
    return error.InvalidBaseline;
}

/// Parse a v2 snapshot, or a conservative v1 baseline. Comments and blank lines are
/// skipped; a row with the wrong field count is rejected.
pub fn parseBaseline(allocator: std.mem.Allocator, bytes: []const u8) Error![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |entry| freeEntry(allocator, entry);
        entries.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var saw_header = false;
    var columns: usize = 5;
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \r");
        if (row.len == 0) continue;
        if (row[0] == '#') {
            saw_header = true;
            if (std.mem.eql(u8, row, "# " ++ version)) columns = 7;
            continue;
        }
        const entry = try parseRow(allocator, row, columns);
        errdefer freeEntry(allocator, entry);
        try entries.append(allocator, entry);
    }
    if (!saw_header) return error.InvalidBaseline;
    return entries.toOwnedSlice(allocator);
}

/// After parsing, identify an explicit pre-source baseline for the api-diff CLI.
/// Shared release and context readers retain their existing parsing behavior.
pub fn needsSourceUpgrade(bytes: []const u8) Error!bool {
    var obsolete: ?bool = null;
    var saw_entry = false;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        if (row[0] != '#') {
            saw_entry = true;
            continue;
        }
        if (!std.mem.startsWith(u8, row, "# api-diff-baseline-")) continue;
        if (saw_entry or obsolete != null) return error.InvalidBaseline;
        if (std.mem.eql(u8, row, "# api-diff-baseline-v1")) {
            obsolete = true;
        } else if (std.mem.eql(u8, row, "# " ++ version)) {
            obsolete = false;
        } else return error.InvalidBaseline;
    }
    return obsolete orelse false;
}

fn freeEntry(allocator: std.mem.Allocator, entry: Entry) void {
    inline for (@typeInfo(Entry).@"struct".field_names) |name| allocator.free(@field(entry, name));
}

fn parseRow(allocator: std.mem.Allocator, row: []const u8, columns: usize) Error!Entry {
    var fields = std.mem.splitScalar(u8, row, '\t');
    var entry: Entry = undefined;
    var copied: usize = 0;
    errdefer inline for (@typeInfo(Entry).@"struct".field_names, 0..) |name, i| {
        if (i < copied) allocator.free(@field(entry, name));
    };
    inline for (@typeInfo(Entry).@"struct".field_names, 0..) |name, i| {
        const value = if (i < columns) fields.next() orelse return error.InvalidBaseline else "-";
        if (value.len == 0) return error.InvalidBaseline;
        @field(entry, name) = try allocator.dupe(u8, value);
        copied += 1;
    }
    if (fields.next() != null) return error.InvalidBaseline;
    if (columns != 7) return entry;
    if (std.mem.eql(u8, entry.sources, "-")) return entry;
    if (!validSources(entry.sources)) return error.InvalidBaseline;
    return entry;
}

fn validSources(sources: []const u8) bool {
    if (std.mem.eql(u8, sources, "fresh")) return true;
    var previous: ?u16 = null;
    var fields = std.mem.splitScalar(u8, sources, ',');
    while (fields.next()) |field| {
        const position = std.fmt.parseInt(u16, field, 10) catch return false;
        if (previous) |old| if (position <= old) return false;
        previous = position;
    }
    return previous != null;
}

/// Classify one current entry against the baseline entry with the same identity.
fn classify(baseline: Entry, current: Entry, allocator: std.mem.Allocator) Error!?Change {
    if (!std.mem.eql(u8, baseline.interface, current.interface)) {
        if (sourceNarrowing(baseline, current)) return .{ .class = .compatible, .display = try allocator.dupe(u8, current.display), .detail = "return sources narrowed" };
        return .{ .class = .breaking, .display = try allocator.dupe(u8, current.display), .detail = "interface changed" };
    }
    if (!std.mem.eql(u8, baseline.body, current.body)) {
        return .{ .class = .compatible, .display = try allocator.dupe(u8, current.display), .detail = "body changed" };
    }
    return null;
}

fn sourceNarrowing(old: Entry, new: Entry) bool {
    if (std.mem.eql(u8, old.without_sources, "-")) return false;
    if (!std.mem.eql(u8, old.without_sources, new.without_sources)) return false;
    if (!validSources(old.sources) or !validSources(new.sources)) return false;
    if (std.mem.eql(u8, old.sources, new.sources)) return false;
    if (std.mem.eql(u8, new.sources, "fresh")) return false;
    var current = std.mem.splitScalar(u8, new.sources, ',');
    while (current.next()) |source_position| {
        _ = std.fmt.parseInt(u16, source_position, 10) catch return false;
        var previous = std.mem.splitScalar(u8, old.sources, ',');
        var found = false;
        while (previous.next()) |candidate| {
            if (std.mem.eql(u8, candidate, source_position)) found = true;
        }
        if (!found) return false;
    }
    return true;
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

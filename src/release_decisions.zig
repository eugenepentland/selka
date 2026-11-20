//! Pure decision parsing and public-interface coverage for checked project docs.
const std = @import("std");
const baseline = @import("api_diff_baseline.zig");

/// A located release finding; command layers render it as diagnostic-v1.
pub const Issue = struct { code: []const u8, path: []const u8, line: usize = 1, message: []const u8, name: ?[]const u8 = null };
/// Human-authored explanation fields preserved for the overview.
pub const Metadata = struct { title: []const u8 = "", date: ?[]const u8 = null, why: []const u8 = "", rejected: ?[]const u8 = null };
/// Parsed decision, borrowing input text and allocator-owned field lists.
pub const Decision = struct {
    identity: []const u8,
    path: []const u8,
    metadata: Metadata,
    changes: []const []const u8,
    body: []const u8,
    pending: bool,
    valid: bool,
};
/// Parse result retaining malformed pending files for useful diagnostics.
pub const Parsed = struct { decision: Decision, issues: []const Issue };

const invalid_code = "E_RELEASE_DECISION_INVALID";

/// Read one decision; archived files retain their text without validation.
/// All allocations belong to `allocator`, normally the command's arena.
pub fn parse(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8, pending: bool) std.mem.Allocator.Error!Parsed {
    var fields: Fields = .{ .allocator = allocator, .path = path, .pending = pending };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const first = std.mem.trim(u8, lines.next() orelse "", " \t\r");
    if (std.mem.startsWith(u8, first, "# ")) fields.metadata.title = std.mem.trim(u8, first[2..], " \t");
    if (pending and (fields.metadata.title.len == 0 or placeholder(fields.metadata.title))) try fields.problem(1, "the first line must be a non-placeholder # Title");
    var line_number: usize = 1;
    var why: std.ArrayList(u8) = .empty;
    var in_why = false;
    var seen: [4]bool = @splat(false);
    var fence: ?Fence = null;
    while (lines.next()) |raw| {
        line_number += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (fence) |opened| {
            if (opened.closes(line)) fence = null;
            continue;
        }
        if (Fence.marker(line)) |opened| {
            fence = opened;
            in_why = false;
            continue;
        }
        const tag = fieldTag(line);
        if (tag) |index| {
            if (seen[index] and pending) try fields.problem(line_number, "a decision field occurs more than once");
            seen[index] = true;
            in_why = index == 1;
            const value = std.mem.trim(u8, line[(std.mem.indexOfScalar(u8, line, ':') orelse return error.OutOfMemory) + 1 ..], " \t");
            switch (index) {
                0 => try fields.parseChanges(value, line_number),
                1 => try why.appendSlice(allocator, value),
                2 => {
                    fields.metadata.date = value;
                    if (pending and !validDate(value)) try fields.problem(line_number, "Date must be a valid YYYY-MM-DD date");
                },
                3 => fields.metadata.rejected = value,
                else => unreachable,
            }
        } else if (line.len == 0) {
            in_why = false;
        } else if (in_why) {
            try why.append(allocator, '\n');
            try why.appendSlice(allocator, line);
        }
    }
    fields.metadata.why = try why.toOwnedSlice(allocator);
    if (pending and fields.changes.items.len == 0) try fields.problem(1, "Changes must name at least one module::declaration");
    if (pending and (nonWhitespace(fields.metadata.why) < 30 or placeholder(fields.metadata.why))) try fields.problem(1, "Why must contain at least 30 non-whitespace characters and no TODO, TBD, FIXME or <why> placeholder");
    const basename = std.fs.path.basename(path);
    return .{ .decision = .{
        .identity = if (std.mem.endsWith(u8, basename, ".md")) basename[0 .. basename.len - 3] else basename,
        .path = path,
        .metadata = fields.metadata,
        .changes = try fields.changes.toOwnedSlice(allocator),
        .body = bytes,
        .pending = pending,
        .valid = fields.issues.items.len == 0,
    }, .issues = try fields.issues.toOwnedSlice(allocator) };
}

const Fence = struct {
    character: u8,
    width: usize,
    bare: bool,

    fn marker(line: []const u8) ?Fence {
        if (line.len < 3 or (line[0] != '`' and line[0] != '~')) return null;
        var width: usize = 0;
        while (width < line.len and line[width] == line[0]) width += 1;
        if (width < 3) return null;
        return .{ .character = line[0], .width = width, .bare = std.mem.trim(u8, line[width..], " \t").len == 0 };
    }

    fn closes(self: Fence, line: []const u8) bool {
        const found = marker(line) orelse return false;
        return found.character == self.character and found.width >= self.width and found.bare;
    }
};

const Fields = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    pending: bool,
    metadata: Metadata = .{},
    changes: std.ArrayList([]const u8) = .empty,
    issues: std.ArrayList(Issue) = .empty,

    fn problem(self: *Fields, line: usize, message: []const u8) !void {
        try self.issues.append(self.allocator, .{ .code = invalid_code, .path = self.path, .line = line, .message = message });
    }

    fn parseChanges(self: *Fields, text: []const u8, line: usize) !void {
        var names = std.mem.splitScalar(u8, text, ',');
        while (names.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (!qualifiedName(name)) {
                if (self.pending) try self.problem(line, "Changes contains a name that is not module::declaration");
                continue;
            }
            try self.changes.append(self.allocator, name);
        }
    }
};

fn fieldTag(line: []const u8) ?usize {
    const labels = [_][]const u8{ "Changes:", "Why:", "Date:", "Rejected:" };
    for (labels, 0..) |label, index| if (std.mem.startsWith(u8, line, label)) return index;
    return null;
}

fn nonWhitespace(text: []const u8) usize {
    var count: usize = 0;
    for (text) |byte| count += @intFromBool(!std.ascii.isWhitespace(byte));
    return count;
}

fn placeholder(text: []const u8) bool {
    for ([_][]const u8{ "TODO", "TBD", "FIXME", "<why>" }) |needle| {
        if (text.len < needle.len) continue;
        for (0..text.len - needle.len + 1) |offset| {
            if (std.ascii.eqlIgnoreCase(text[offset..][0..needle.len], needle)) return true;
        }
    }
    return false;
}

/// Whether a prose code span has exactly the qualified-reference spelling.
pub fn qualifiedName(name: []const u8) bool {
    const separator = std.mem.indexOf(u8, name, "::") orelse return false;
    if (separator == 0 or separator + 2 == name.len) return false;
    if (!identifier(name[separator + 2 ..])) return false;
    var parts = std.mem.splitScalar(u8, name[0..separator], '.');
    while (parts.next()) |part| if (!identifier(part)) return false;
    return true;
}

fn identifier(name: []const u8) bool {
    if (name.len == 0 or (!std.ascii.isAlphabetic(name[0]) and name[0] != '_')) return false;
    for (name[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    return true;
}

/// Check the date spelling and the actual Gregorian calendar day without a clock.
pub fn validDate(date: []const u8) bool {
    if (date.len != 10 or date[4] != '-' or date[7] != '-') return false;
    for (date, 0..) |byte, i| if (i != 4 and i != 7 and !std.ascii.isDigit(byte)) return false;
    const year = std.fmt.parseInt(u16, date[0..4], 10) catch return false;
    const month = std.fmt.parseInt(u8, date[5..7], 10) catch return false;
    const day = std.fmt.parseInt(u8, date[8..10], 10) catch return false;
    if (year == 0 or month == 0 or month > 12 or day == 0) return false;
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
    return day <= days[month - 1] + @as(u8, @intFromBool(month == 2 and leap));
}

/// Return pending decision coverage and name-resolution findings.
/// Only additions, removals and interface edits require a decision.
pub fn coverage(allocator: std.mem.Allocator, previous: ?[]const baseline.Entry, current: []const baseline.Entry, decisions: []const Decision) baseline.Error![]const Issue {
    return coverageAt(allocator, previous, current, decisions, .{});
}

/// Configured paths used by missing-baseline and missing-decision diagnostics.
pub const Locations = struct { baseline: []const u8 = "release/baseline.txt", pending: []const u8 = "decisions/unreleased" };

/// Compute coverage with the project's configured diagnostic locations.
pub fn coverageAt(allocator: std.mem.Allocator, previous: ?[]const baseline.Entry, current: []const baseline.Entry, decisions: []const Decision, locations: Locations) baseline.Error![]const Issue {
    var issues: std.ArrayList(Issue) = .empty;
    const old = previous orelse {
        try issues.append(allocator, .{ .code = "E_RELEASE_NO_BASELINE", .path = locations.baseline, .message = "release baseline is missing; run selka release init PROJECT" });
        return issues.toOwnedSlice(allocator);
    };
    for (decisions) |decision| {
        if (!decision.pending) continue;
        for (decision.changes) |name| {
            if (contains(old, name) or contains(current, name)) continue;
            try issues.append(allocator, .{ .code = "E_RELEASE_REFERENCE_UNKNOWN", .path = decision.path, .message = "Changes names no current or baseline public declaration", .name = name });
        }
    }
    const changes = try baseline.compareEntries(allocator, old, current);
    defer baseline.freeChanges(allocator, changes);
    try missingCoverage(allocator, &issues, changes.additive, decisions, locations.pending);
    try missingCoverage(allocator, &issues, changes.breaking, decisions, locations.pending);
    return issues.toOwnedSlice(allocator);
}

fn missingCoverage(allocator: std.mem.Allocator, issues: *std.ArrayList(Issue), changes: []const baseline.Change, decisions: []const Decision, pending_path: []const u8) !void {
    for (changes) |change| {
        if (covering(decisions, change.display) != null) continue;
        try issues.append(allocator, .{
            .code = "E_RELEASE_DECISION_MISSING",
            .path = pending_path,
            .message = "public interface changed without a pending decision; run selka release draft PROJECT --name SLUG",
            .name = try allocator.dupe(u8, change.display),
        });
    }
}

/// First valid pending decision covering a name, or null when it is uncovered.
pub fn covering(decisions: []const Decision, name: []const u8) ?usize {
    for (decisions, 0..) |decision, index| {
        if (!decision.pending or !decision.valid) continue;
        for (decision.changes) |changed| if (std.mem.eql(u8, changed, name)) return index;
    }
    return null;
}

fn contains(entries: []const baseline.Entry, name: []const u8) bool {
    for (entries) |entry| if (std.mem.eql(u8, entry.display, name)) return true;
    return false;
}

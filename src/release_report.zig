//! Gate status and diagnostic-v1 rendering shared by the release steps.
const std = @import("std");
const options = @import("release_options.zig");
/// A located gate finding, including its exact diagnostic-v1 record.
pub const Finding = struct { record: std.json.Value, code: []const u8, severity: []const u8, message: []const u8, path: []const u8, line: usize, column: usize };
/// Result of a selected step; skipped steps always explain their dependency.
pub const Result = struct { name: options.Step, status: enum { ok, failed, skipped } = .ok, findings: usize = 0, reason: []const u8 = "", detail: []const u8 = "" };
/// Arena-owned gate findings and ordered results.
pub const Report = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList(Finding) = .empty,
    steps: std.ArrayList(Result) = .empty,
    /// Release list storage; diagnostic records belong to the caller arena.
    pub fn deinit(self: *Report) void {
        self.findings.deinit(self.allocator);
        self.steps.deinit(self.allocator);
    }
    /// Add a located error using the compiler's standard diagnostic envelope.
    pub fn add(self: *Report, code: []const u8, path: []const u8, line: usize, message: []const u8) std.mem.Allocator.Error!void {
        try self.at(code, .{ .path = path, .line = line }, message);
    }
    /// Add a located error at an exact prose/source coordinate.
    pub fn at(self: *Report, code: []const u8, location: Position, message: []const u8) std.mem.Allocator.Error!void {
        const bytes = try std.json.Stringify.valueAlloc(self.allocator, .{
            .version = "diagnostic-v1",
            .kind = "diagnostic",
            .diagnostic = .{
                .code = code,
                .severity = "error",
                .message = message,
                .location = .{ .path = location.path, .start = .{ .line = location.line, .column = location.column }, .end = @as(?u8, null), .bytes = @as(?u8, null) },
                .notes = [_]u8{},
                .stack = .{ .frames = [_]u8{}, .omitted = 0 },
            },
        }, .{});
        _ = try self.appendJson(bytes, false);
    }
    /// Preserve the Core rule when a declaration failure is wrapped by release.
    pub fn atRule(self: *Report, code: []const u8, location: Position, message: []const u8, rule: ?@import("diagnostic.zig").Rule) std.mem.Allocator.Error!void {
        try self.at(code, location, message);
        const selected = rule orelse return;
        for (self.findings.items) |*finding| {
            if (!std.mem.eql(u8, finding.code, code) or !std.mem.eql(u8, finding.path, location.path)) continue;
            if (finding.line != location.line) continue;
            if (!std.mem.eql(u8, finding.message, message)) continue;
            const data = finding.record.object.getPtr("diagnostic").?;
            try data.object.put(self.allocator, "rule", .{ .string = @tagName(selected) });
            return;
        }
    }
    /// Import diagnostic-v1 lines, optionally omitting the three release docs rules.
    pub fn appendJson(self: *Report, bytes: []const u8, omit_docs: bool) std.mem.Allocator.Error!usize {
        var added: usize = 0;
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line, .{ .allocate = .alloc_always }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            const root = parsed.value;
            if (root != .object) continue;
            const data = root.object.get("diagnostic") orelse continue;
            if (data != .object) continue;
            const code = string(data, "code");
            if (omit_docs and documentationCode(code)) continue;
            const loc = data.object.get("location") orelse continue;
            const start = loc.object.get("start") orelse continue;
            const item: Finding = .{ .record = root, .code = code, .severity = string(data, "severity"), .message = string(data, "message"), .path = string(loc, "path"), .line = number(start, "line"), .column = number(start, "column") };
            if (self.duplicate(item)) continue;
            try self.findings.append(self.allocator, item);
            added += 1;
        }
        return added;
    }
    fn duplicate(self: *Report, item: Finding) bool {
        for (self.findings.items) |other| {
            if (std.mem.eql(u8, item.code, other.code) and std.mem.eql(u8, item.path, other.path) and item.line == other.line and std.mem.eql(u8, item.message, other.message)) return true;
        }
        return false;
    }
    /// Number of refusing findings from one starting offset.
    pub fn errors(self: Report, start: usize) usize {
        var count: usize = 0;
        for (self.findings.items[start..]) |finding| count += @intFromBool(std.mem.eql(u8, finding.severity, "error"));
        return count;
    }
    /// A skipped required step also prevents a green gate.
    pub fn status(self: Report) u8 {
        for (self.steps.items) |step| if (step.status != .ok) return 3;
        return if (self.errors(0) == 0) 0 else 3;
    }
    /// Emit the same selected steps and diagnostics as text or release-check-v1.
    pub fn render(self: Report, io: std.Io, json: bool) (std.mem.Allocator.Error || std.Io.File.Writer.Error)!void {
        var out: std.ArrayList(u8) = .empty;
        if (json) {
            var findings: std.ArrayList(std.json.Value) = .empty;
            for (self.findings.items) |finding| try findings.append(self.allocator, finding.record);
            const encoded = try std.json.Stringify.valueAlloc(self.allocator, .{
                .version = "release-check-v1",
                .status = if (self.status() == 0) "releasable" else "refused",
                .steps = self.steps.items,
                .findings = findings.items,
            }, .{});
            try out.appendSlice(self.allocator, encoded);
            try out.append(self.allocator, '\n');
        } else {
            var failed: usize = 0;
            for (self.steps.items) |step| {
                try out.print(self.allocator, "release: {s} ", .{@tagName(step.name)});
                switch (step.status) {
                    .ok => {
                        try out.appendSlice(self.allocator, "ok");
                        if (step.detail.len != 0) try out.print(self.allocator, " ({s})", .{step.detail});
                    },
                    .failed => {
                        failed += 1;
                        try out.print(self.allocator, "FAILED ({d} findings)", .{step.findings});
                    },
                    .skipped => {
                        failed += 1;
                        try out.print(self.allocator, "skipped ({s})", .{step.reason});
                    },
                }
                try out.append(self.allocator, '\n');
            }
            for (self.findings.items) |finding| {
                try out.print(self.allocator, "{s}:{d}:{d}: {s}[{s}]: {s}\n", .{ finding.path, finding.line, finding.column, finding.severity, finding.code, finding.message });
                const rule = string(finding.record.object.get("diagnostic").?, "rule");
                if (rule.len != 0) try out.print(self.allocator, "  note: ownership rule {s}\n", .{rule});
            }
            if (failed == 0) try out.appendSlice(self.allocator, "release check: releasable\n") else try out.print(self.allocator, "release check: not releasable ({d} of {d} steps failed)\n", .{ failed, self.steps.items.len });
        }
        try std.Io.File.stdout().writeStreamingAll(io, out.items);
    }
};
/// Root-relative source or prose position.
pub const Position = struct { path: []const u8, line: usize = 1, column: usize = 1 };
/// Extract a string from an optional JSON field.
pub fn string(value: std.json.Value, key: []const u8) []const u8 {
    if (value != .object) return "";
    const field = value.object.get(key) orelse return "";
    return if (field == .string) field.string else "";
}
fn number(value: std.json.Value, key: []const u8) usize {
    const field = value.object.get(key) orelse return 1;
    return if (field == .integer and field.integer >= 0) @intCast(field.integer) else 1;
}
fn documentationCode(code: []const u8) bool {
    for ([_][]const u8{ "L_UNDOCUMENTED_MODULE", "L_UNDOCUMENTED_EXPORT", "L_MISSING_EXAMPLE" }) |doc| if (std.mem.eql(u8, code, doc)) return true;
    return false;
}

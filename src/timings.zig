//! Opt-in command timing records; disjoint measured phases plus an inclusive total.
const std = @import("std");
/// Counts describe available work, not estimates of unobserved compiler phases.
pub const Counts = struct {
    modules: ?usize = null,
    source_bytes: ?usize = null,
    ast_nodes: ?usize = null,
    typed_nodes: ?usize = null,
    input_bytes: ?usize = null,
    output_bytes: ?usize = null,
};
/// One command owns the recorder; disabled recorders do not read the clock.
pub const Profile = struct {
    io: std.Io,
    enabled: bool,
    tool: enum { compiler, byte_io },
    counts: Counts = .{},
    started: std.Io.Timestamp = .zero,
    active: ?struct { name: []const u8, start: std.Io.Timestamp, inclusive: bool } = null,
    records: struct { phases: [16]struct { name: []const u8, duration_ns: i96, inclusive: bool } = undefined, len: usize = 0 } = .{},
    /// Start after argument parsing; total includes command work and cleanup.
    pub fn init(io: std.Io, enabled: bool, tool: @FieldType(Profile, "tool")) Profile {
        return .{ .io = io, .enabled = enabled, .tool = tool, .started = if (enabled) std.Io.Timestamp.now(io, .awake) else .zero };
    }
    /// Start a disjoint phase; close any prior phase at the same timestamp.
    pub fn begin(self: *Profile, name: []const u8, inclusive: bool) void {
        if (!self.enabled) return;
        const now = std.Io.Timestamp.now(self.io, .awake);
        self.close(now);
        self.active = .{ .name = name, .start = now, .inclusive = inclusive };
    }
    /// Finish measured work before unrelated command overhead.
    pub fn end(self: *Profile) void {
        if (self.enabled) self.close(std.Io.Timestamp.now(self.io, .awake));
    }
    fn close(self: *Profile, now: std.Io.Timestamp) void {
        if (self.active) |active| {
            std.debug.assert(self.records.len < self.records.phases.len);
            self.records.phases[self.records.len] = .{ .name = active.name, .duration_ns = @max(0, active.start.durationTo(now).nanoseconds), .inclusive = active.inclusive };
            self.records.len += 1;
            self.active = null;
        }
    }
    /// Emit JSON Lines to stderr; exit_code is the outcome of the whole command.
    pub fn report(self: *Profile, exit_code: u8) (std.Io.Writer.Error || std.Io.File.Writer.Error)!void {
        if (!self.enabled) return;
        const now = std.Io.Timestamp.now(self.io, .awake);
        self.close(now);
        for (self.records.phases[0..self.records.len]) |phase| try self.write(phase.name, phase.duration_ns, phase.inclusive, exit_code);
        try self.write("total", @max(0, self.started.durationTo(now).nanoseconds), true, exit_code);
    }
    fn write(self: *Profile, name: []const u8, duration_ns: i96, inclusive: bool, exit_code: u8) !void {
        var buffer: [2048]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try std.json.Stringify.value(.{
            .version = "phase-timings-v1",
            .kind = "timing",
            .tool = @tagName(self.tool),
            .name = name,
            .duration_ns = duration_ns,
            .inclusive = inclusive,
            .counts = self.counts,
            .exit_code = exit_code,
        }, .{ .emit_null_optional_fields = false }, &writer);
        try writer.writeByte('\n');
        try std.Io.File.stderr().writeStreamingAll(self.io, writer.buffered());
    }
};

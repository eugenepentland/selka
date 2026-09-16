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
    records: struct { phases: [64]struct { name: []const u8, duration_ns: i96, inclusive: bool } = undefined, len: usize = 0 } = .{},
    /// Start after argument parsing; total includes command work and cleanup.
    pub fn init(io: std.Io, enabled: bool, tool: @FieldType(Profile, "tool")) Profile {
        return .{ .io = io, .enabled = enabled, .tool = tool, .started = if (enabled) std.Io.Timestamp.now(io, .awake) else .zero };
    }
    /// Start a disjoint phase; close any prior phase at the same timestamp.
    pub fn begin(self: *Profile, name: []const u8, inclusive: bool) void {
        if (!self.enabled) return;
        const instant = std.Io.Timestamp.now(self.io, .awake);
        self.close(instant);
        self.active = .{ .name = name, .start = instant, .inclusive = inclusive };
    }
    /// Finish measured work before unrelated command overhead.
    pub fn end(self: *Profile) void {
        if (self.enabled) self.close(std.Io.Timestamp.now(self.io, .awake));
    }
    /// Read the recorder clock. Callers must check `enabled` before using it.
    pub fn now(self: *Profile) std.Io.Timestamp {
        return std.Io.Timestamp.now(self.io, .awake);
    }
    /// Accumulate one already-measured interval. Instrumentation that runs inside
    /// an active phase must use this instead of `begin`/`end` so it never closes
    /// or re-parents the caller's phase.
    pub fn add(self: *Profile, name: []const u8, duration_ns: i96, inclusive: bool) void {
        if (!self.enabled) return;
        const duration = @max(0, duration_ns);
        for (self.records.phases[0..self.records.len]) |*phase| {
            if (phase.inclusive == inclusive and std.mem.eql(u8, phase.name, name)) {
                phase.duration_ns += duration;
                return;
            }
        }
        if (self.records.len == self.records.phases.len) return;
        self.records.phases[self.records.len] = .{ .name = name, .duration_ns = duration, .inclusive = inclusive };
        self.records.len += 1;
    }
    /// Accumulate the interval from `start` to the recorder's current instant.
    pub fn addSince(self: *Profile, name: []const u8, start: std.Io.Timestamp, inclusive: bool) void {
        if (!self.enabled) return;
        self.add(name, start.durationTo(self.now()).nanoseconds, inclusive);
    }
    fn close(self: *Profile, instant: std.Io.Timestamp) void {
        if (self.active) |active| {
            if (self.records.len == self.records.phases.len) {
                self.active = null;
                return;
            }
            self.records.phases[self.records.len] = .{ .name = active.name, .duration_ns = @max(0, active.start.durationTo(instant).nanoseconds), .inclusive = active.inclusive };
            self.records.len += 1;
            self.active = null;
        }
    }
    /// Emit JSON Lines to stderr; exit_code is the outcome of the whole command.
    pub fn report(self: *Profile, exit_code: u8) (std.Io.Writer.Error || std.Io.File.Writer.Error)!void {
        if (!self.enabled) return;
        const instant = std.Io.Timestamp.now(self.io, .awake);
        self.close(instant);
        for (self.records.phases[0..self.records.len]) |phase| try self.write(phase.name, phase.duration_ns, phase.inclusive, exit_code);
        try self.write("total", @max(0, self.started.durationTo(instant).nanoseconds), true, exit_code);
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

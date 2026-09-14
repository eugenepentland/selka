//! Build one guest natively with the trusted board provider and drive it once
//! per request. The host interprets no board: it lays the request out in bytes,
//! runs the guest, and reads back the observation and the kernel's own count.
const std = @import("std");
const native = @import("host_native");
const transport = @import("transport.zig");
const m = @import("model.zig");
/// The trusted provider translation unit linked into every guest executable.
pub const provider = @embedFile("native_board.c");
/// The native step budget one validation may spend.
const steps = @import("host_native").step_budget;
/// A status byte and at most one report; the driver reads back nothing wider.
pub const observation_limit = 64;
/// Build, transport and guest-outcome failures of one trial invocation.
pub const Error = native.Error || transport.Error || error{ InvalidCallCount, GuestExit };
/// The kernel count the provider wrote beside the observation, and nothing else.
pub fn counted(bytes: []const u8) Error!u64 {
    const text = std.mem.trim(u8, bytes, "\r\n ");
    return std.fmt.parseInt(u64, text, 10) catch error.InvalidCallCount;
}
/// Owns the built guest and the private files one invocation's bytes travel on.
pub const Session = struct {
    program: native.Program,
    request: []const u8,
    observation: []const u8,
    counted: []const u8,
    /// Compile the guest project at this root together with the trusted provider
    /// and tell that provider where this invocation's bytes will live.
    pub fn init(process: std.process.Init, root: []const u8) Error!Session {
        var program = try native.Program.build(process, .{ .project = root, .provider = provider });
        errdefer program.deinit();
        var session: Session = .{
            .program = program,
            .request = try program.file("request"),
            .observation = try program.file("observation"),
            .counted = try program.file("calls"),
        };
        try session.describe();
        return session;
    }
    fn describe(self: *Session) Error!void {
        try self.program.set("MYLANG_BOARD_REQUEST", self.request);
        try self.program.set("MYLANG_BOARD_OBSERVATION", self.observation);
        try self.program.set("MYLANG_BOARD_CALLS", self.counted);
        try self.program.setNumber("MYLANG_BOARD_MAX_OUTPUT", observation_limit);
    }
    /// Remove the built guest and every transport file it used.
    pub fn deinit(self: *Session) void {
        self.program.deinit();
    }
    /// Validate one board in a fresh guest process and report what it observed.
    /// The kernel count comes from the provider itself, so an injected service
    /// failure is still counted exactly once.
    pub fn run(self: *Session, board: m.Board, unavailable: bool) Error!m.Observation {
        var bytes: transport.Request = undefined;
        transport.encode(board, &bytes);
        try self.program.write(self.request, &bytes);
        try self.program.write(self.counted, "");
        try self.program.set("MYLANG_BOARD_UNAVAILABLE", if (unavailable) "1" else "0");
        const value = try self.program.invoke(&.{steps});
        if (value != 0) return error.GuestExit;
        return .{ .outcome = try transport.decode(try self.program.read(self.observation)), .calls = try self.calls() };
    }
    fn calls(self: *Session) Error!u64 {
        return counted(try self.program.read(self.counted));
    }
};

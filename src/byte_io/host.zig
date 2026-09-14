//! Trusted raw byte operations; all input interpretation belongs to the guest.
//! The operations themselves are compiled into the guest's own native executable
//! (`native_byte_io.c`); this module is the driver that builds that executable,
//! hands it one invocation's bytes, and decides what reaches the real stdout.
const std = @import("std");
const native = @import("host_native");
const limits = @import("limits.zig");
const bulk = @import("bulk.zig");
/// The trusted provider translation unit linked into every guest executable.
pub const provider = @embedFile("native_byte_io.c");
/// Build, transport and guest-outcome failures of one native invocation.
pub const Error = native.Error;
/// Own one invocation's private build products and byte transport files.
pub const Session = struct {
    program: native.Program,
    input: []const u8,
    published: []const u8,
    /// Build the guest with the trusted provider and describe this authority to it.
    /// A validated copied-block shape names the exact types the provider copies,
    /// so a differently shaped block never reaches a callback.
    pub fn init(process: std.process.Init, options: limits.Options, shape: ?bulk.Shape) Error!Session {
        var program = try native.Program.build(process, .{
            .project = options.project,
            .provider = provider,
            .cache = options.tools.cache,
            .qbe = options.tools.qbe,
            .zig = options.tools.zig,
        });
        errdefer program.deinit();
        var session: Session = .{
            .program = program,
            .input = try program.file("input"),
            .published = try program.file("output"),
        };
        try session.describe(options, shape);
        return session;
    }
    /// Remove every private file; nothing an invocation produced outlives it.
    pub fn deinit(self: *Session) void {
        self.program.deinit();
    }
    fn describe(self: *Session, options: limits.Options, shape: ?bulk.Shape) Error!void {
        try self.program.set("MYLANG_BYTE_IO_INPUT", self.input);
        try self.program.set("MYLANG_BYTE_IO_OUTPUT", self.published);
        try self.program.setNumber("MYLANG_BYTE_IO_MAX_OUTPUT", options.output);
        try self.program.setNumber("MYLANG_BYTE_IO_MAX_CALLS", options.execution.calls);
        try self.program.setNumber("MYLANG_BYTE_IO_MAX_WORK", options.execution.work);
        if (shape) |names| {
            try self.program.set("MYLANG_BYTE_IO_BLOCK_TYPE", names.record);
            try self.program.set("MYLANG_BYTE_IO_ARRAY_TYPE", names.array);
        }
        try options.grants.install(self.program.allocator, &self.program.environment);
    }
    /// Run the guest once against these bytes and report its entry-point result.
    pub fn invoke(self: *Session, bytes: []const u8, steps: u64) Error!i64 {
        try self.program.write(self.input, bytes);
        const budget = try std.fmt.allocPrint(self.program.allocator, "--max-steps={d}", .{steps});
        return self.program.invoke(&.{budget});
    }
    /// Read back the bytes the guest asked to publish during this invocation.
    pub fn output(self: *Session) Error![]const u8 {
        return self.program.read(self.published);
    }
};

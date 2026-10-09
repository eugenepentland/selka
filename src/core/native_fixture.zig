//! Native runtime fixture support: real assertions, optional counting and TSan.
const std = @import("std");
const driver = @import("driver.zig");
const counting = @import("count_runtime.zig");
const io = std.testing.io;

/// Failures constructing or checking an isolated native fixture.
pub const Error = counting.Error || error{ Unexpected, TestUnexpectedResult, TestExpectedEqual };
/// The instrumentation a native fixture requests.
pub const Options = struct { counted: bool = false, sanitized: bool = false };
/// One native execution and its optional aggregate counters.
pub const Run = struct { status: u8, stdout: []const u8, stderr: []const u8, counts: []const u8 };
/// A compiled fixture whose caller owns its temporary directory and arena.
pub const Fixture = struct {
    arena: std.mem.Allocator,
    binary: []const u8,
    environment: std.process.Environ.Map,
    counted: bool,

    /// Build a fixture that includes `core_rt_all.c`; native C thunks define their
    /// explicit C bridge, while emitted-IR tests exercise the actual fastcc bridge.
    pub fn init(a: std.mem.Allocator, root: []const u8, source: []const u8, options: Options) Error!Fixture {
        const runtime = if (options.counted) try counting.source(a, driver.runtime_source) else driver.runtime_source;
        const runtime_path = try std.fs.path.join(a, &.{ root, "core_rt_all.c" });
        const source_path = try std.fs.path.join(a, &.{ root, "fixture.c" });
        const binary = try std.fs.path.join(a, &.{ root, "fixture" });
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = runtime_path, .data = runtime }) catch return error.TestUnexpectedResult;
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source_path, .data = source }) catch return error.TestUnexpectedResult;
        var environment = try std.testing.environ.createMap(a);
        errdefer environment.deinit();
        try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
        try environment.put("SELKA_COUNTERS", try std.fs.path.join(a, &.{ root, "counts.json" }));
        if (options.sanitized) try environment.put("SELKA_CORE_SANITIZE", "thread");
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(a, &.{ environment.get("ZIG") orelse "zig", "cc", "-O2", "-g", "-std=c11", "-pthread", source_path, "-o", binary });
        if (options.sanitized) try arguments.append(a, "-fsanitize=thread");
        const built = std.process.run(a, io, .{ .argv = arguments.items, .environ_map = &environment }) catch return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("", built.stderr);
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        return .{ .arena = a, .binary = binary, .environment = environment, .counted = options.counted };
    }
    /// Run one bounded fixture mode with the requested thread count.
    pub fn run(self: *Fixture, mode: []const u8, threads: []const u8) Error!Run {
        try self.environment.put("SELKA_THREADS", threads);
        const result = std.process.run(self.arena, io, .{ .argv = &.{ self.binary, mode }, .environ_map = &self.environment, .stdout_limit = .limited(2 << 20), .stderr_limit = .limited(2 << 20) }) catch return error.TestUnexpectedResult;
        try std.testing.expect(result.term == .exited);
        const counts = if (self.counted) std.Io.Dir.cwd().readFileAlloc(io, self.environment.get("SELKA_COUNTERS").?, self.arena, .limited(1 << 20)) catch return error.TestUnexpectedResult else "";
        return .{ .status = result.term.exited, .stdout = result.stdout, .stderr = result.stderr, .counts = counts };
    }
    /// Preserve exactly this binary for the separately recorded repetition gate.
    pub fn exportBinary(self: *const Fixture, name: []const u8) Error!void {
        const directory = self.environment.get("SELKA_P1_FIXTURE_OUTPUT") orelse return;
        const path = try std.fs.path.join(self.arena, &.{ directory, name });
        std.Io.Dir.cwd().createDirPath(io, directory) catch return error.TestUnexpectedResult;
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, self.binary, self.arena, .limited(64 << 20)) catch return error.TestUnexpectedResult;
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch return error.TestUnexpectedResult;
        std.Io.Dir.cwd().setFilePermissions(io, path, .executable_file, .{}) catch return error.TestUnexpectedResult;
    }
};

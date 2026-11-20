//! Native runtime fixture support: real assertions, optional counting and TSan.
const std = @import("std");
const driver = @import("driver.zig");
const counting = @import("count_runtime.zig");
const io = std.testing.io;

/// Failures constructing or checking an isolated native fixture.
pub const Error = counting.Error || error{ Unexpected, TestUnexpectedResult, TestExpectedEqual };
/// The instrumentation a native fixture requests.
pub const Options = struct {
    counted: bool = false,
    sanitized: bool = false,
    /// Overrides are for cache contract tests; ordinary fixtures share suite storage.
    cache_directory: ?[]const u8 = null,
    reuse: bool = true,
};
/// One native execution and its optional aggregate counters.
pub const Run = struct { status: u8, stdout: []const u8, stderr: []const u8, counts: []const u8 };

/// The variable that gives the stress fixtures their full counts (a million submits under
/// ThreadSanitizer, 40,000 allocator transfer rounds); the gate runs the shorter ones.
pub const full_stress_variable = "SELKA_FULL_STRESS";

/// The fixture mode a stress test runs: `full` when `SELKA_FULL_STRESS` is set and not
/// empty, otherwise `short`.
pub fn stressMode(short: []const u8, full: []const u8) []const u8 {
    return if (@import("core_test_options").lookup(std.testing.environ, full_stress_variable) != null) full else short;
}
/// A closed C program a test compiles and then runs on its own terms: its source, the
/// names the source and the runtime text take beside it, the compiler flags and the
/// binary's name. The runtime text is the compiler's own unless a test says otherwise.
pub const Program = struct {
    source: []const u8,
    binary_name: []const u8 = "fixture",
    runtime_name: []const u8 = "core_rt.c",
    source_name: []const u8 = "fixture.c",
    flags: []const []const u8 = &.{ "-O2", "-std=c11", "-pthread" },
    /// Instrument with ASan and bind its configured runtime to the fixture cache key.
    address_sanitized: bool = false,
    runtime: []const u8 = driver.runtime_source,
};

/// Compile `spec` in `root`, or restore the binary an identical compile left in the suite
/// store (the key binds the runtime and source texts, their names, the flags, the toolchain
/// and every header the compile read), and return the binary's path. The test runs it.
pub fn buildProgram(a: std.mem.Allocator, root: []const u8, spec: Program) Error![]const u8 {
    const runtime_path = try std.fs.path.join(a, &.{ root, spec.runtime_name });
    const source_path = try std.fs.path.join(a, &.{ root, spec.source_name });
    const binary = try std.fs.path.join(a, &.{ root, spec.binary_name });
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = runtime_path, .data = spec.runtime }) catch return error.TestUnexpectedResult;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = source_path, .data = spec.source }) catch return error.TestUnexpectedResult;
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    if (spec.address_sanitized) try environment.put("SELKA_CORE_SANITIZE", "address");
    const flags = if (spec.address_sanitized)
        try std.mem.concat(a, []const u8, &.{ spec.flags, &.{ "-fsanitize=address", @import("core_tool_platform").address_runtime.path } })
    else
        spec.flags;
    const cache = try std.fs.path.join(a, &.{ @import("core_test_options").suiteCache(a, @src()) catch return error.TestUnexpectedResult, "fixtures-v1" });
    _ = @import("native_fixture_cache.zig").build(a, &environment, .{
        .program = .{ .root = root, .binary = binary, .runtime = spec.runtime, .source = spec.source, .runtime_name = spec.runtime_name, .source_name = spec.source_name, .flags = flags },
        .sanitized = false,
        .directory = cache,
        .reuse = true,
    }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.TestUnexpectedResult;
    };
    return binary;
}

/// A compiled fixture whose caller owns its temporary directory and arena.
pub const Fixture = struct {
    arena: std.mem.Allocator,
    binary: []const u8,
    environment: std.process.Environ.Map,
    counted: bool,
    reused: bool,

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
        const cache = options.cache_directory orelse try std.fs.path.join(a, &.{ @import("core_test_options").suiteCache(a, @src()) catch return error.TestUnexpectedResult, "fixtures-v1" });
        const reused = @import("native_fixture_cache.zig").build(a, &environment, .{
            .program = .{ .root = root, .binary = binary, .runtime = runtime, .source = source },
            .sanitized = options.sanitized,
            .directory = cache,
            .reuse = options.reuse,
        }) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.TestUnexpectedResult;
        };
        return .{ .arena = a, .binary = binary, .environment = environment, .counted = options.counted, .reused = reused };
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

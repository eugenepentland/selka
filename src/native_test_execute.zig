//! Fresh native processes execute copied typed test inputs exactly once.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const wire = @import("native_test_wire.zig");
const budget = @import("memory_budget.zig");
const Value = std.json.Value;
const infrastructure_failure = "infrastructure-failure";
const magic: u64 = 0x3154534554594c4d;
/// Native test setup, validation, filesystem and child-process failures.
pub const Error = fs.Error || wire.Error || error{ InvalidNativeTestManifest, InvalidTestLimits, WriteFailed };
/// Execution quotas shared by guest function and declared domain codecs. The
/// byte ceiling is null until the command resolves the flag, the environment
/// and the built-in default against each other; a resolved value is part of a
/// receipt key, so raising or lowering it re-executes rather than reuses.
pub const Limits = struct {
    max_steps: u64 = 1000000,
    max_frames: u64 = 1024,
    max_calls: u64 = 4096,
    timeout_ms: u32 = 60000,
    max_memory: ?u64 = null,
};
/// One execution result; expected-value comparison never executes guest code.
pub const Outcome = struct { status: []const u8, actual: Value = .null, diagnostics: []const u8 = "", steps: u64 = 0 };
/// Reusable compiled harness and immutable schema for a native test library.
pub const Executor = struct {
    context: fs.Context,
    library: []const u8,
    temporary: []const u8,
    executable: []const u8,
    types: []const Value,
    /// Compile the embedded POSIX harness once; test calls load the library in new processes.
    pub fn init(context: fs.Context, manifest: Value, library: []const u8, temporary: []const u8, zig: []const u8) Error!Executor {
        const a = context.allocator;
        const schema = v.get(manifest, "schema");
        if (schema != .string) return error.InvalidNativeTestManifest;
        const parsed = std.json.parseFromSlice(Value, a, schema.string, .{ .allocate = .alloc_always }) catch return error.InvalidNativeTestManifest;
        errdefer parsed.deinit();
        const source = try std.fs.path.join(a, &.{ temporary, "native-test-runner.c" });
        const executable = try std.fs.path.join(a, &.{ temporary, "native-test-runner" });
        try context.write(source, @embedFile("native_test_runner.c"));
        inline for (.{ "native_host.h", "native_providers.h", "native_embed.h" }) |name| {
            try context.write(try std.fs.path.join(a, &.{ temporary, name }), @embedFile(name));
        }
        try context.command(&.{ zig, "cc", "-std=c11", "-O2", source, "-ldl", "-o", executable }, null);
        return .{ .context = context, .library = library, .temporary = temporary, .executable = executable, .types = v.array(v.get(parsed.value, "types")) };
    }
    /// Validate named typed arguments and run one bounded child invocation.
    pub fn execute(self: Executor, function: Value, arguments: Value, limits: Limits) Error!Outcome {
        if (limits.max_steps == 0 or limits.max_frames == 0) return error.InvalidTestLimits;
        if (limits.max_calls == 0 or limits.timeout_ms == 0) return error.InvalidTestLimits;
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types };
        defer codec.deinit();
        try codec.arguments(function, arguments);
        const directory = try self.context.temporary(self.temporary);
        defer self.context.remove(directory);
        const path = try std.fs.path.join(self.context.allocator, &.{ directory, "request" });
        try self.context.write(path, try request(self.context.allocator, v.text(v.get(function, "name")), codec.nodes.items, limits));
        const result = std.process.run(self.context.allocator, self.context.io, .{
            .argv = &.{ self.executable, self.library, path },
            .environ_map = try self.context.bounded(limits.max_memory orelse budget.test_default),
            .stdout_limit = .limited(32 * 1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(limits.timeout_ms), .clock = .awake } },
        }) catch |err| return .{ .status = infrastructure_failure, .diagnostics = @errorName(err) };
        if (fs.exitCode(result.term) != 0) return .{
            .status = infrastructure_failure,
            .diagnostics = try std.fmt.allocPrint(self.context.allocator, "NativeTestProcessFailed: {any}\n{s}", .{ result.term, result.stderr }),
        };
        return response(self.context.allocator, self.types, v.text(v.get(function, "result")), result.stdout);
    }
};
fn request(a: std.mem.Allocator, name: []const u8, nodes: []const wire.Node, limits: Limits) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    for ([_]u64{ magic, limits.max_steps, limits.max_frames, limits.max_calls }) |number| try w.writeInt(u64, number, .little);
    try string(w, name);
    try w.writeInt(u64, nodes.len, .little);
    for (nodes) |node| {
        try string(w, node.type);
        try w.writeInt(u64, node.bits, .little);
        try w.writeInt(u64, node.children, .little);
    }
    return buffer.toOwnedSlice();
}
fn string(w: *std.Io.Writer, bytes: []const u8) Error!void {
    if (bytes.len > 4096 or std.mem.indexOfScalar(u8, bytes, 0) != null) return error.InvalidTestValue;
    try w.writeInt(u64, bytes.len, .little);
    try w.writeAll(bytes);
}
const Reader = struct {
    bytes: []const u8,
    offset: usize = 0,
    fn number(self: *Reader) Error!u64 {
        if (self.bytes.len - self.offset < 8) return error.InvalidNativeTestResponse;
        const result = std.mem.readInt(u64, self.bytes[self.offset..][0..8], .little);
        self.offset += 8;
        return result;
    }
    fn text(self: *Reader) Error![]const u8 {
        const size = try self.number();
        if (size > 4096 or size > self.bytes.len - self.offset) return error.InvalidNativeTestResponse;
        const value = self.bytes[self.offset..][0..@intCast(size)];
        self.offset += @intCast(size);
        return value;
    }
};
fn response(a: std.mem.Allocator, types: []const Value, result_type: []const u8, bytes: []const u8) Error!Outcome {
    var reader: Reader = .{ .bytes = bytes };
    if (try reader.number() != magic) return error.InvalidNativeTestResponse;
    const status = try reader.number();
    const steps = try reader.number();
    const count = try reader.number();
    const frame_count = try reader.number();
    const omitted = try reader.number();
    const code = try reader.text();
    const domain = try reader.text();
    const rejected = try reader.number();
    if (status > 2 or frame_count > 16 or count > 100000) return error.InvalidNativeTestResponse;
    var diagnostics: std.Io.Writer.Allocating = .init(a);
    defer diagnostics.deinit();
    if (code.len != 0) try diagnostics.writer.print("{s}\n", .{code});
    if (domain.len != 0) try diagnostics.writer.print("domain: {s}; rejected: {d}\n", .{ domain, rejected });
    for (0..@intCast(frame_count)) |_| {
        const function = try reader.text();
        const path = try reader.text();
        const line = try reader.number();
        const column = try reader.number();
        try diagnostics.writer.print("  in {s} at {s}:{d}:{d}\n", .{ function, path, line, column });
    }
    if (omitted != 0) try diagnostics.writer.print("  {d} frames omitted\n", .{omitted});
    var codec: wire.Codec = .{ .allocator = a, .types = types };
    defer codec.deinit();
    for (0..@intCast(count)) |_| try codec.nodes.append(a, .{ .type = try reader.text(), .bits = try reader.number(), .children = @intCast(try reader.number()) });
    if (reader.offset != bytes.len) return error.InvalidNativeTestResponse;
    if (status != 0) return .{ .status = if (status == 1) "trap" else infrastructure_failure, .diagnostics = try diagnostics.toOwnedSlice(), .steps = steps };
    const actual = try codec.decode(result_type, 0);
    if (codec.cursor != codec.nodes.items.len) return error.InvalidNativeTestResponse;
    return .{ .status = "value", .actual = actual, .steps = steps };
}

test "native runner response reports source traces and rejects malformed bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    for ([_]u64{ magic, 1, 17, 0, 1, 0 }) |number| try w.writeInt(u64, number, .little);
    try string(w, "R_DIVISION_BY_ZERO");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    try string(w, "main::test_trap");
    try string(w, "main.my");
    try w.writeInt(u64, 7, .little);
    try w.writeInt(u64, 21, .little);
    const outcome = try response(a, &.{}, "i64", buffer.written());
    try std.testing.expectEqualStrings("trap", outcome.status);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO\n  in main::test_trap at main.my:7:21\n", outcome.diagnostics);
    try std.testing.expectError(error.InvalidNativeTestResponse, response(a, &.{}, "i64", "bad"));
}

test "native test setup rejects missing schema and empty execution budgets" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    try std.testing.expectError(error.InvalidNativeTestManifest, Executor.init(context, .null, "", "", ""));
    const executor: Executor = .{ .context = context, .library = "", .temporary = "", .executable = "", .types = &.{} };
    try std.testing.expectError(error.InvalidTestLimits, executor.execute(.null, .null, .{ .max_steps = 0 }));
    try std.testing.expectError(error.InvalidTestLimits, executor.execute(.null, .null, .{ .timeout_ms = 0 }));
}

test "native test child timeout is bounded and classified without a guest value" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const script = try std.fs.path.join(context.allocator, &.{ directory, "blocking-child" });
    try context.write(script, "exec /bin/sleep 5\n");
    const executor: Executor = .{ .context = context, .library = script, .temporary = directory, .executable = "/bin/sh", .types = &.{} };
    const outcome = try executor.execute(.null, .{ .object = .empty }, .{ .timeout_ms = 10 });
    try std.testing.expectEqualStrings(infrastructure_failure, outcome.status);
    try std.testing.expectEqualStrings("Timeout", outcome.diagnostics);
    try std.testing.expect(outcome.actual == .null);
}

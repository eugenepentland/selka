//! Fresh native processes execute copied typed test inputs exactly once, or
//! sample one copied-value call repeatedly under an in-process monotonic clock.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const wire = @import("native_test_wire.zig");
const trap_detail = @import("native_trap_detail.zig");
const budget = @import("memory_budget");
const Value = std.json.Value;
const infrastructure_failure = "infrastructure-failure";
const magic: u64 = 0x3154534554594c4d;
const bench_magic: u64 = 0x3248434e42594c4d;
const bench_response_magic: u64 = 0x3250535242594c4d;
/// Bytes of guest stdout one test response may carry back to the parent.
const output_limit = 256 * 1024;
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
/// Warmup, calibration target and batch count for one benchmark identity.
/// Bounds are shared by the parent request and the native sampler.
pub const Sampling = struct {
    warmup_iterations: u64 = 3,
    batch_count: u64 = 9,
    target_batch_ns: u64 = 250_000_000,
    max_iterations: u64 = 1_000_000,
};
/// Per-operation limits, sampling plan and whole-run child timeout.
pub const BenchConfig = struct {
    limits: Limits = .{},
    sampling: Sampling = .{},
    timeout_ms: u32 = 120000,
};
/// One raw timed batch: how many copied-value calls it covered and its duration.
pub const Batch = struct { iterations: u64, duration_ns: u64 };
/// One execution result; expected-value comparison never executes guest code.
/// `output` carries the guest stdout captured during the call, if any.
pub const Outcome = struct { status: []const u8, actual: Value = .null, diagnostics: []const u8 = "", output: []const u8 = "", steps: u64 = 0 };
/// One sampled benchmark call. `actual` is the validated value tree produced by
/// the sampled workload; `raw` preserves every timed batch for investigation.
pub const BenchOutcome = struct {
    status: []const u8,
    actual: Value = .null,
    diagnostics: []const u8 = "",
    steps: u64 = 0,
    warmup_iterations: u64 = 0,
    calibrated_iterations: u64 = 0,
    raw: []const Batch = &.{},
};
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
        if (!limitsValid(limits)) return error.InvalidTestLimits;
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types };
        defer codec.deinit();
        try codec.arguments(function, arguments);
        const path = try self.request(try testRequest(self.context.allocator, v.text(v.get(function, "name")), codec.nodes.items, limits));
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
        const parsed = try self.parse(v.text(v.get(function, "result")), result.stdout, false);
        return .{ .status = parsed.status, .actual = parsed.actual, .diagnostics = parsed.diagnostics, .output = parsed.output, .steps = parsed.steps };
    }
    /// Sample one validated copied-value call. Compilation is never timed; the
    /// child warms up, calibrates a batch size, then reports raw timed batches.
    pub fn benchmark(self: Executor, function: Value, arguments: Value, config: BenchConfig) Error!BenchOutcome {
        if (!limitsValid(config.limits)) return error.InvalidTestLimits;
        if (!samplingValid(config.sampling) or config.timeout_ms == 0) return error.InvalidTestLimits;
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types };
        defer codec.deinit();
        try codec.arguments(function, arguments);
        const bytes = try benchRequest(self.context.allocator, v.text(v.get(function, "name")), codec.nodes.items, config);
        const path = try self.request(bytes);
        const result = std.process.run(self.context.allocator, self.context.io, .{
            .argv = &.{ self.executable, self.library, path },
            .environ_map = try self.context.bounded(config.limits.max_memory orelse budget.test_default),
            .stdout_limit = .limited(32 * 1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(config.timeout_ms), .clock = .awake } },
        }) catch |err| return .{ .status = infrastructure_failure, .diagnostics = @errorName(err) };
        if (fs.exitCode(result.term) != 0) return .{
            .status = infrastructure_failure,
            .diagnostics = try std.fmt.allocPrint(self.context.allocator, "NativeTestProcessFailed: {any}\n{s}", .{ result.term, result.stderr }),
        };
        const parsed = try self.parse(v.text(v.get(function, "result")), result.stdout, true);
        return .{
            .status = parsed.status,
            .actual = parsed.actual,
            .diagnostics = parsed.diagnostics,
            .steps = parsed.steps,
            .warmup_iterations = parsed.warmup_iterations,
            .calibrated_iterations = parsed.calibrated_iterations,
            .raw = parsed.raw,
        };
    }
    /// Write one request under a fresh child directory and return its path.
    fn request(self: Executor, bytes: []const u8) Error![]const u8 {
        const directory = try self.context.temporary(self.temporary);
        errdefer self.context.remove(directory);
        const path = try std.fs.path.join(self.context.allocator, &.{ directory, "request" });
        try self.context.write(path, bytes);
        return path;
    }
    /// Parse a response body, validating every field and the exact byte length.
    fn parse(self: Executor, result_type: []const u8, bytes: []const u8, bench: bool) Error!Parsed {
        var reader: Reader = .{ .bytes = bytes };
        const expected = if (bench) bench_response_magic else magic;
        if (try reader.number() != expected) return error.InvalidNativeTestResponse;
        const status = try reader.number();
        const steps = try reader.number();
        const count = try reader.number();
        const frame_count = try reader.number();
        const omitted = try reader.number();
        // Read the wire detail sequentially before constructing the value; struct
        // literal evaluation order is not a stream contract.
        const detail_version: u32 = @intCast(try reader.number());
        const detail_present: u32 = @intCast(try reader.number());
        const detail_index: i64 = @bitCast(try reader.number());
        const detail_length: u64 = try reader.number();
        const detail_left: i64 = @bitCast(try reader.number());
        const detail_right: i64 = @bitCast(try reader.number());
        const detail_width: u64 = try reader.number();
        // `operation` is a bounded name for numeric traps but the assertion
        // message for `R_ASSERT`; keep the raw text so the failure can show it.
        const detail_operation_text = try reader.text();
        const detail_operation = trap_detail.Detail.operationFromName(detail_operation_text);
        const detail: trap_detail.Detail = .{
            .version = detail_version,
            .present = detail_present,
            .operation = detail_operation,
            .values = .{ .index = detail_index, .length = detail_length, .left = detail_left, .right = detail_right, .width = detail_width },
        };
        const code = try reader.text();
        const domain = try reader.text();
        const rejected = try reader.number();
        if (status > 2 or frame_count > 16 or count > 100000) return error.InvalidNativeTestResponse;
        var diagnostics: std.Io.Writer.Allocating = .init(self.context.allocator);
        defer diagnostics.deinit();
        if (code.len != 0) {
            try diagnostics.writer.writeAll(code);
            try detail.writeText(&diagnostics.writer);
            // `writeText` renders only numeric detail, so a message-only assert
            // detail is quoted here, matching the runtime's `R_ASSERT: text` line.
            if (std.mem.eql(u8, code, "R_ASSERT") and detail_version != 0 and detail_operation_text.len != 0)
                try diagnostics.writer.print(": {s}", .{detail_operation_text});
            try diagnostics.writer.writeAll("\n");
        }
        if (domain.len != 0) try diagnostics.writer.print("domain: {s}; rejected: {d}\n", .{ domain, rejected });
        for (0..@intCast(frame_count)) |_| {
            const function = try reader.text();
            const path = try reader.text();
            const line = try reader.number();
            const column = try reader.number();
            try diagnostics.writer.print("  in {s} at {s}:{d}:{d}\n", .{ function, path, line, column });
        }
        if (omitted != 0) try diagnostics.writer.print("  {d} frames omitted\n", .{omitted});
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types };
        defer codec.deinit();
        for (0..@intCast(count)) |_| try codec.nodes.append(self.context.allocator, .{ .type = try reader.text(), .bits = try reader.number(), .children = @intCast(try reader.number()) });
        var parsed: Parsed = .{ .status = if (status == 0) "value" else if (status == 1) "trap" else infrastructure_failure, .steps = steps };
        if (bench) {
            parsed.warmup_iterations = try reader.number();
            parsed.calibrated_iterations = try reader.number();
            const batch_count = try reader.number();
            if (batch_count > 64) return error.InvalidNativeTestResponse;
            const raw = try self.context.allocator.alloc(Batch, @intCast(batch_count));
            for (raw) |*batch| batch.* = .{ .iterations = try reader.number(), .duration_ns = try reader.number() };
            parsed.raw = raw;
        }
        // A response may end with the guest stdout the child captured. Older
        // responses without the trailer keep parsing because it is optional.
        if (reader.offset < bytes.len) {
            const size = try reader.number();
            if (size > output_limit or size > bytes.len - reader.offset) return error.InvalidNativeTestResponse;
            parsed.output = bytes[reader.offset..][0..@intCast(size)];
            reader.offset += @intCast(size);
        }
        if (reader.offset != bytes.len) return error.InvalidNativeTestResponse;
        if (status != 0) {
            parsed.diagnostics = try diagnostics.toOwnedSlice();
            return parsed;
        }
        const actual = try codec.decode(result_type, 0);
        if (codec.cursor != codec.nodes.items.len) return error.InvalidNativeTestResponse;
        parsed.actual = actual;
        return parsed;
    }
};
const Parsed = struct {
    status: []const u8,
    actual: Value = .null,
    diagnostics: []const u8 = "",
    output: []const u8 = "",
    steps: u64 = 0,
    warmup_iterations: u64 = 0,
    calibrated_iterations: u64 = 0,
    raw: []const Batch = &.{},
};
fn limitsValid(limits: Limits) bool {
    return limits.max_steps != 0 and limits.max_frames != 0 and limits.max_calls != 0 and limits.timeout_ms != 0;
}
fn samplingValid(sampling: Sampling) bool {
    return sampling.batch_count != 0 and sampling.batch_count <= 64 and sampling.warmup_iterations <= 1000 and sampling.max_iterations != 0;
}
fn testRequest(a: std.mem.Allocator, name: []const u8, items: []const wire.Node, limits: Limits) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    for ([_]u64{ magic, limits.max_steps, limits.max_frames, limits.max_calls }) |number| try w.writeInt(u64, number, .little);
    try string(w, name);
    try writeNodes(w, items);
    return buffer.toOwnedSlice();
}
fn benchRequest(a: std.mem.Allocator, name: []const u8, items: []const wire.Node, config: BenchConfig) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    for ([_]u64{
        bench_magic,
        config.limits.max_steps,
        config.limits.max_frames,
        config.limits.max_calls,
        config.sampling.warmup_iterations,
        config.sampling.batch_count,
        config.sampling.target_batch_ns,
        config.sampling.max_iterations,
    }) |number| try w.writeInt(u64, number, .little);
    try string(w, name);
    try writeNodes(w, items);
    return buffer.toOwnedSlice();
}
/// Test and benchmark requests share their argument/name trailer exactly.
/// Write a fixed field sequence; kept out of tests so a test body keeps one loop.
fn writeNumbers(w: *std.Io.Writer, numbers: []const u64) Error!void {
    for (numbers) |number| try w.writeInt(u64, number, .little);
}
fn writeNodes(w: *std.Io.Writer, items: []const wire.Node) Error!void {
    try w.writeInt(u64, items.len, .little);
    for (items) |node| {
        try string(w, node.type);
        try w.writeInt(u64, node.bits, .little);
        try w.writeInt(u64, node.children, .little);
    }
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

test "native runner response reports source traces and rejects malformed bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const executor: Executor = .{ .context = context, .library = "", .temporary = "", .executable = "", .types = &.{} };
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    try writeNumbers(w, &.{ magic, 1, 17, 0, 1, 0, 1, 12, 0, 0, 1, 0, 0 });
    try string(w, "div");
    try string(w, "R_DIVISION_BY_ZERO");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    try string(w, "main::test_trap");
    try string(w, "main.my");
    try w.writeInt(u64, 7, .little);
    try w.writeInt(u64, 21, .little);
    const parsed = try executor.parse("i64", buffer.written(), false);
    try std.testing.expectEqualStrings("trap", parsed.status);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO (div: left 1, right 0)\n  in main::test_trap at main.my:7:21\n", parsed.diagnostics);
    try std.testing.expectError(error.InvalidNativeTestResponse, executor.parse("i64", "bad", false));
}

/// One trap response with an optional captured-stdout trailer.
fn trapResponse(a: std.mem.Allocator, output: ?[]const u8) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(a);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    try writeNumbers(w, &.{ magic, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try string(w, "");
    try string(w, "R_ASSERT");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    if (output) |bytes| try string(w, bytes);
    return buffer.toOwnedSlice();
}

// spec: NATIVE-TEST-7
test "a captured guest stdout trailer round-trips and stays optional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const executor: Executor = .{ .context = context, .library = "", .temporary = "", .executable = "", .types = &.{} };
    const captured = try executor.parse("i64", try trapResponse(a, "debug\n"), false);
    try std.testing.expectEqualStrings("trap", captured.status);
    try std.testing.expectEqualStrings("debug\n", captured.output);
    const plain = try executor.parse("i64", try trapResponse(a, null), false);
    try std.testing.expectEqualStrings("", plain.output);
}

// spec-case: NATIVE-TEST-10
test "an assert trap response reports its message as the located trap detail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const executor: Executor = .{ .context = context, .library = "", .temporary = "", .executable = "", .types = &.{} };
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    try writeNumbers(w, &.{ magic, 1, 3, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0 });
    try string(w, "x should be two");
    try string(w, "R_ASSERT");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    try string(w, "main::test_x");
    try string(w, "main.my");
    try w.writeInt(u64, 3, .little);
    try w.writeInt(u64, 5, .little);
    const parsed = try executor.parse("i64", buffer.written(), false);
    try std.testing.expectEqualStrings("trap", parsed.status);
    try std.testing.expect(std.mem.indexOf(u8, parsed.diagnostics, "R_ASSERT: x should be two") != null);
    try std.testing.expect(std.mem.indexOf(u8, parsed.diagnostics, "in main::test_x at main.my:3:5") != null);
}

test "native benchmark response carries raw batches and rejects a wrong magic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var parsed_types = try std.json.parseFromSlice(Value, a,
        \\{"types":[{"name":"i64","kind":"integer","signed":true}]}
    , .{});
    defer parsed_types.deinit();
    const executor: Executor = .{ .context = context, .library = "", .temporary = "", .executable = "", .types = v.array(v.get(parsed_types.value, "types")) };
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    try writeNumbers(w, &.{ bench_response_magic, 0, 5, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try string(w, "");
    try string(w, "");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    try string(w, "i64");
    try w.writeInt(u64, 5, .little);
    try w.writeInt(u64, 0, .little);
    try w.writeInt(u64, 3, .little);
    try w.writeInt(u64, 7, .little);
    try w.writeInt(u64, 2, .little);
    for ([_][2]u64{ .{ 7, 700 }, .{ 7, 777 } }) |batch| {
        try w.writeInt(u64, batch[0], .little);
        try w.writeInt(u64, batch[1], .little);
    }
    const parsed = try executor.parse("i64", buffer.written(), true);
    try std.testing.expectEqualStrings("value", parsed.status);
    try std.testing.expectEqual(@as(u64, 3), parsed.warmup_iterations);
    try std.testing.expectEqual(@as(u64, 7), parsed.calibrated_iterations);
    try std.testing.expectEqual(@as(usize, 2), parsed.raw.len);
    try std.testing.expectEqual(@as(u64, 777), parsed.raw[1].duration_ns);
    try std.testing.expectEqualStrings("5", parsed.actual.string);
    try std.testing.expectError(error.InvalidNativeTestResponse, executor.parse("i64", buffer.written(), false));
}

// spec-case: NATIVE-BENCH-2
test "test and benchmark requests carry the name before the node block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = [_]wire.Node{.{ .type = "i64", .bits = 7, .children = 0 }};
    const test_bytes = try testRequest(a, "main::test_x", &items, .{ .max_steps = 11, .max_frames = 12, .max_calls = 13 });
    var reader: Reader = .{ .bytes = test_bytes };
    try std.testing.expectEqual(magic, try reader.number());
    try std.testing.expectEqual(@as(u64, 11), try reader.number());
    try std.testing.expectEqual(@as(u64, 12), try reader.number());
    try std.testing.expectEqual(@as(u64, 13), try reader.number());
    try std.testing.expectEqualStrings("main::test_x", try reader.text());
    try std.testing.expectEqual(@as(u64, 1), try reader.number());
    try std.testing.expectEqualStrings("i64", try reader.text());
    try std.testing.expectEqual(@as(u64, 7), try reader.number());
    try std.testing.expectEqual(@as(u64, 0), try reader.number());
    try std.testing.expectEqual(test_bytes.len, reader.offset);
    const bench_bytes = try benchRequest(a, "main::bench_x", &items, .{ .sampling = .{ .warmup_iterations = 2, .batch_count = 3, .target_batch_ns = 4, .max_iterations = 5 } });
    var bench_reader: Reader = .{ .bytes = bench_bytes };
    try std.testing.expectEqual(bench_magic, try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 1000000), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 1024), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 4096), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 2), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 3), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 4), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 5), try bench_reader.number());
    try std.testing.expectEqualStrings("main::bench_x", try bench_reader.text());
    try std.testing.expectEqual(@as(u64, 1), try bench_reader.number());
    try std.testing.expectEqualStrings("i64", try bench_reader.text());
    try std.testing.expectEqual(@as(u64, 7), try bench_reader.number());
    try std.testing.expectEqual(@as(u64, 0), try bench_reader.number());
    try std.testing.expectEqual(bench_bytes.len, bench_reader.offset);
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
    try std.testing.expectError(error.InvalidTestLimits, executor.benchmark(.null, .null, .{ .sampling = .{ .batch_count = 0 } }));
    try std.testing.expectError(error.InvalidTestLimits, executor.benchmark(.null, .null, .{ .sampling = .{ .batch_count = 65 } }));
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

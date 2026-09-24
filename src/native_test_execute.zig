//! Fresh native processes execute copied typed test inputs exactly once, or
//! sample one copied-value call repeatedly under an in-process monotonic clock.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const wire = @import("native_test_wire.zig");
const trap_detail = @import("native_trap_detail.zig");
const budget = @import("memory_budget");
const spawn = @import("qbe_build_spawn.zig");
const Value = std.json.Value;
const infrastructure_failure = "infrastructure-failure";
/// The harness switch that runs every call under the stress collector.
const gc_stress_flag = "--gc-stress";
/// Failure text for a child that exited abnormally: its termination and stderr.
const process_failed = "NativeTestProcessFailed: {any}\n{s}";
const magic: u64 = 0x3154534554594c4d;
const bench_magic: u64 = 0x3248434e42594c4d;
const bench_response_magic: u64 = 0x3250535242594c4d;
/// "MLYPROP1"/"MLYPRSP1"/"MLYPEND1": the property batch request, response
/// and trailer magics `native_test_runner.c` shares.
const property_magic: u64 = 0x31504f5250594c4d;
const property_response_magic: u64 = 0x3150535250594c4d;
const property_end_magic: u64 = 0x31444e4550594c4d;
/// Inputs one property batch request may carry; the harness enforces the same bound.
pub const batch_limit = 4096;
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
/// `output` carries the guest stdout captured during the call, if any, and
/// `trap` the structured first-trap fields a caller classifies by.
pub const Outcome = struct { status: []const u8, actual: Value = .null, diagnostics: []const u8 = "", output: []const u8 = "", steps: u64 = 0, trap: Trap = .{} };
/// The first trap of one call, read apart from its rendered diagnostics: the
/// trap code, the message an `assert` or a contract clause carries, and the
/// qualified function of the innermost frame, which tells a test's own
/// precondition from one a function it calls broke.
pub const Trap = struct { code: []const u8 = "", message: []const u8 = "", frame: []const u8 = "" };
/// One property batch call: the executor owning the library, the checked
/// function, and each input's copied argument nodes in run order.
pub const BatchCall = struct { executor: *const Executor, function: Value, inputs: []const []const wire.Node };
/// What one property batch child answered: an outcome per input it finished,
/// in input order, and whether it finished them all. A child that dies or
/// runs out of time mid-batch leaves the outcomes before the input it was
/// running; `ending` says why it stopped early.
pub const BatchOutcome = struct { outcomes: []const Outcome, complete: bool, ending: []const u8 = "", timed_out: bool = false };
/// One bounded child call and whether the wall-clock bound ended it. A caller
/// that must tell a timeout from a trap needs the distinction `Outcome` alone
/// cannot carry, because both leave no guest value.
pub const Attempt = struct { outcome: Outcome, timed_out: bool = false };
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
/// The embedded POSIX harness sources, in the order the runner key hashes them.
const runner_sources = .{ "native_test_runner.c", "native_host.h", "native_providers.h", "native_embed.h" };
/// Where the compiled harness is published and what builds it. `cache` is
/// null for a `--no-cache` run, which compiles a private copy under `temporary`.
pub const RunnerStore = struct { cache: ?[]const u8, temporary: []const u8, zig: []const u8, zig_stamp: []const u8 };
/// A usable harness path and whether this call had to compile it.
pub const Runner = struct { path: []const u8, compiled: bool };
/// The compiled harness for this compiler's embedded runner sources. A run
/// with a cache reuses the executable a previous run published under
/// `<cache>/runner/<key>`, where the key covers every embedded source byte,
/// the compile flags and the `zig` tool stamp, so an unchanged toolchain never
/// pays the C compile again; a miss compiles once and publishes by rename.
pub fn runner(context: fs.Context, store: RunnerStore) Error!Runner {
    const a = context.allocator;
    const flags = [_][]const u8{ "cc", "-std=c11", "-O2" };
    var hash = std.crypto.hash.Blake3.init(.{});
    inline for (.{"native-test-runner-v2"} ++ flags) |part| framed(&hash, part);
    framed(&hash, store.zig_stamp);
    inline for (runner_sources) |name| framed(&hash, @embedFile(name));
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const key = std.fmt.bytesToHex(digest, .lower);
    const cache = store.cache orelse return .{ .path = try compileRunner(context, store, store.temporary), .compiled = true };
    const directory = try std.fs.path.join(a, &.{ cache, "runner" });
    const published = try std.fs.path.join(a, &.{ directory, &key });
    if (context.runnable(published)) return .{ .path = published, .compiled = false };
    try context.mkdir(directory);
    const staging = try context.temporary(directory);
    defer context.remove(staging);
    const built = try compileRunner(context, store, staging);
    // A concurrent run may publish the same key first; both executables are
    // built from identical inputs, so whichever rename lands last is correct.
    // A cache that refuses the rename still has this run's private copy.
    context.rename(built, published) catch return .{ .path = try compileRunner(context, store, store.temporary), .compiled = true };
    return .{ .path = published, .compiled = true };
}
/// Write the embedded harness sources beneath `directory` and compile them there.
fn compileRunner(context: fs.Context, store: RunnerStore, directory: []const u8) Error![]const u8 {
    const a = context.allocator;
    inline for (runner_sources) |name| try context.write(try std.fs.path.join(a, &.{ directory, name }), @embedFile(name));
    const source = try std.fs.path.join(a, &.{ directory, "native_test_runner.c" });
    const executable = try std.fs.path.join(a, &.{ directory, "native-test-runner" });
    try context.command(&.{ store.zig, "cc", "-std=c11", "-O2", source, "-ldl", "-o", executable }, null);
    return executable;
}
fn framed(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
/// Reusable compiled harness and immutable schema for a native test library.
pub const Executor = struct {
    context: fs.Context,
    library: []const u8,
    temporary: []const u8,
    executable: []const u8,
    types: []const Value,
    /// `--gc-stress` for every child call; set from the invocation's flags.
    stress: bool = false,
    /// `--seed N` for every injected `Entropy`; null derives it from the test name.
    seed: ?u64 = null,
    /// Bind a compiled harness (`runner`) to one library and its schema; test
    /// calls load the library in new processes.
    pub fn init(context: fs.Context, manifest: Value, library: []const u8, temporary: []const u8, executable: []const u8) Error!Executor {
        const a = context.allocator;
        const schema = v.get(manifest, "schema");
        if (schema != .string) return error.InvalidNativeTestManifest;
        const parsed = std.json.parseFromSlice(Value, a, schema.string, .{ .allocate = .alloc_always }) catch return error.InvalidNativeTestManifest;
        return .{ .context = context, .library = library, .temporary = temporary, .executable = executable, .types = v.array(v.get(parsed.value, "types")) };
    }
    /// Validate named typed arguments and run one bounded child invocation.
    pub fn execute(self: Executor, function: Value, arguments: Value, limits: Limits) Error!Outcome {
        return (try self.attempt(function, arguments, limits)).outcome;
    }
    /// Validate named typed arguments and run one bounded child invocation,
    /// reporting whether the wall-clock bound ended the child. Test callers use
    /// `execute`; an invocation boundary that must name a timeout separately
    /// reads `timed_out`.
    pub fn attempt(self: Executor, function: Value, arguments: Value, limits: Limits) Error!Attempt {
        if (!limitsValid(limits)) return error.InvalidTestLimits;
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types, .seed = self.seed };
        defer codec.deinit();
        try codec.arguments(function, arguments);
        const path = try self.request(try testRequest(self.context.allocator, v.text(v.get(function, "name")), codec.nodes.items, limits));
        const result = std.process.run(self.context.allocator, self.context.io, .{
            .argv = try self.argv(path),
            .environ_map = try self.context.bounded(limits.max_memory orelse budget.test_default),
            .stdout_limit = .limited(32 * 1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(limits.timeout_ms), .clock = .awake } },
        }) catch |err| return .{ .outcome = .{ .status = infrastructure_failure, .diagnostics = @errorName(err) }, .timed_out = err == error.Timeout };
        if (fs.exitCode(result.term) != 0) return .{
            .outcome = .{
                .status = infrastructure_failure,
                .diagnostics = try std.fmt.allocPrint(self.context.allocator, process_failed, .{ result.term, result.stderr }),
            },
        };
        const parsed = try self.parse(v.text(v.get(function, "result")), result.stdout, false);
        return .{ .outcome = parsed.outcome() };
    }
    /// Validate one call's typed arguments and write its request and the path
    /// its child answers into; the child itself is started by `executeAll`.
    fn prepare(self: *const Executor, call: Call, limits: Limits) Error!Prepared {
        const a = self.context.allocator;
        var codec: wire.Codec = .{ .allocator = a, .types = self.types, .seed = self.seed };
        defer codec.deinit();
        try codec.arguments(call.function, call.arguments);
        const path = try self.request(try testRequest(a, v.text(v.get(call.function, "name")), codec.nodes.items, limits));
        const response = try std.fs.path.join(a, &.{ std.fs.path.dirname(path).?, "response" });
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(a, &.{ self.executable, self.library, path });
        if (self.stress) try arguments.append(a, gc_stress_flag);
        try arguments.appendSlice(a, &.{ "--response", response });
        return .{ .argv = arguments.items, .response = response };
    }
    /// Write one property batch request and the path its child answers into.
    fn prepareBatch(self: *const Executor, call: BatchCall, limits: Limits) Error!Prepared {
        const a = self.context.allocator;
        const path = try self.request(try batchRequest(a, v.text(v.get(call.function, "name")), call.inputs, limits));
        const response = try std.fs.path.join(a, &.{ std.fs.path.dirname(path).?, "response" });
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(a, &.{ self.executable, self.library, path });
        if (self.stress) try arguments.append(a, gc_stress_flag);
        try arguments.appendSlice(a, &.{ "--response", response });
        return .{ .argv = arguments.items, .response = response };
    }
    /// Copy one input's named typed arguments into the nodes a batch carries,
    /// with the deterministic stand-ins for every capability parameter.
    pub fn encode(self: Executor, function: Value, arguments: Value) Error![]const wire.Node {
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types, .seed = self.seed };
        try codec.arguments(function, arguments);
        return codec.nodes.items;
    }
    /// Sample one validated copied-value call. Compilation is never timed; the
    /// child warms up, calibrates a batch size, then reports raw timed batches.
    pub fn benchmark(self: Executor, function: Value, arguments: Value, config: BenchConfig) Error!BenchOutcome {
        if (!limitsValid(config.limits)) return error.InvalidTestLimits;
        if (!samplingValid(config.sampling) or config.timeout_ms == 0) return error.InvalidTestLimits;
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types, .seed = self.seed };
        defer codec.deinit();
        try codec.arguments(function, arguments);
        const bytes = try benchRequest(self.context.allocator, v.text(v.get(function, "name")), codec.nodes.items, config);
        const path = try self.request(bytes);
        const result = std.process.run(self.context.allocator, self.context.io, .{
            .argv = try self.argv(path),
            .environ_map = try self.context.bounded(config.limits.max_memory orelse budget.test_default),
            .stdout_limit = .limited(32 * 1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(config.timeout_ms), .clock = .awake } },
        }) catch |err| return .{ .status = infrastructure_failure, .diagnostics = @errorName(err) };
        if (fs.exitCode(result.term) != 0) return .{
            .status = infrastructure_failure,
            .diagnostics = try std.fmt.allocPrint(self.context.allocator, process_failed, .{ result.term, result.stderr }),
        };
        const parsed = try self.parse(v.text(v.get(function, "result")), result.stdout, true);
        return .{
            .status = parsed.status,
            .actual = parsed.actual,
            .diagnostics = parsed.diagnostics,
            .steps = parsed.steps,
            .warmup_iterations = parsed.sampled.warmup_iterations,
            .calibrated_iterations = parsed.sampled.calibrated_iterations,
            .raw = parsed.sampled.raw,
        };
    }
    /// Child argv: the runner, the library, the request, and the collector
    /// stress switch when the invocation asked for it.
    fn argv(self: Executor, path: []const u8) Error![]const []const u8 {
        const a = self.context.allocator;
        if (!self.stress) return a.dupe([]const u8, &.{ self.executable, self.library, path });
        return a.dupe([]const u8, &.{ self.executable, self.library, path, gc_stress_flag });
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
        var parsed = try self.record(&reader, result_type);
        if (bench) {
            parsed.sampled.warmup_iterations = try reader.number();
            parsed.sampled.calibrated_iterations = try reader.number();
            const batch_count = try reader.number();
            if (batch_count > 64) return error.InvalidNativeTestResponse;
            const raw = try self.context.allocator.alloc(Batch, @intCast(batch_count));
            for (raw) |*batch| batch.* = .{ .iterations = try reader.number(), .duration_ns = try reader.number() };
            parsed.sampled.raw = raw;
        }
        // A response may end with the guest stdout the child captured. Older
        // responses without the trailer keep parsing because it is optional.
        if (reader.offset < bytes.len) parsed.output = try reader.output();
        if (reader.offset != bytes.len) return error.InvalidNativeTestResponse;
        return parsed;
    }
    /// Read one call's shared header, trap frames and returned value tree: the
    /// part a test, a benchmark and every input of a property batch answer
    /// alike. A trapped call keeps its rendered diagnostics and no value.
    fn record(self: Executor, reader: *Reader, result_type: []const u8) Error!Parsed {
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
        const carries_message = trap_detail.messageTrap(code) and detail_version != 0 and detail_operation_text.len != 0;
        if (code.len != 0) {
            try diagnostics.writer.writeAll(code);
            try detail.writeText(&diagnostics.writer);
            // `writeText` renders only numeric detail, so a message-only assert
            // detail is quoted here, matching the runtime's `R_ASSERT: text` line.
            if (carries_message) try diagnostics.writer.print(": {s}", .{detail_operation_text});
            try diagnostics.writer.writeAll("\n");
        }
        if (domain.len != 0) try diagnostics.writer.print("domain: {s}; rejected: {d}\n", .{ domain, rejected });
        var trap: Trap = .{ .code = code, .message = if (carries_message) detail_operation_text else "" };
        for (0..@intCast(frame_count)) |index| {
            const function = try reader.text();
            const path = try reader.text();
            const line = try reader.number();
            const column = try reader.number();
            if (index == 0) trap.frame = function;
            try diagnostics.writer.print("  in {s} at {s}:{d}:{d}\n", .{ function, path, line, column });
        }
        if (omitted != 0) try diagnostics.writer.print("  {d} frames omitted\n", .{omitted});
        var codec: wire.Codec = .{ .allocator = self.context.allocator, .types = self.types, .seed = self.seed };
        defer codec.deinit();
        for (0..@intCast(count)) |_| try codec.nodes.append(self.context.allocator, .{ .type = try reader.text(), .bits = try reader.number(), .children = @intCast(try reader.number()) });
        var parsed: Parsed = .{ .status = if (status == 0) "value" else if (status == 1) "trap" else infrastructure_failure, .steps = steps, .trap = trap };
        if (status != 0) {
            parsed.diagnostics = try diagnostics.toOwnedSlice();
            return parsed;
        }
        const actual = try codec.decode(result_type, 0);
        if (codec.cursor != codec.nodes.items.len) return error.InvalidNativeTestResponse;
        parsed.actual = actual;
        return parsed;
    }
    /// Parse a property batch response: one record per finished input, in
    /// input order, then the trailer naming how many there were. A response
    /// cut short by a dying child keeps every record it holds in full and
    /// reports itself incomplete; a malformed record is still an error.
    pub fn parseBatch(self: Executor, result_type: []const u8, bytes: []const u8, inputs: usize) Error!BatchOutcome {
        var reader: Reader = .{ .bytes = bytes };
        var outcomes: std.ArrayList(Outcome) = .empty;
        if (bytes.len < 8) return .{ .outcomes = &.{}, .complete = false };
        if (try reader.number() != property_response_magic) return error.InvalidNativeTestResponse;
        while (reader.offset < bytes.len) {
            const index = reader.number() catch break;
            if (index == property_end_magic) {
                if (try reader.number() != inputs or outcomes.items.len != inputs or reader.offset != bytes.len) return error.InvalidNativeTestResponse;
                return .{ .outcomes = outcomes.items, .complete = true };
            }
            if (index != outcomes.items.len or index >= inputs) return error.InvalidNativeTestResponse;
            // A record the child did not finish writing is where it died.
            const parsed = self.record(&reader, result_type) catch |err| if (reader.exhausted) break else return err;
            const output = reader.output() catch |err| if (reader.exhausted) break else return err;
            try outcomes.append(self.context.allocator, .{ .status = parsed.status, .actual = parsed.actual, .diagnostics = parsed.diagnostics, .output = output, .steps = parsed.steps, .trap = parsed.trap });
        }
        return .{ .outcomes = outcomes.items, .complete = false };
    }
};
/// One queued test call: the executor that owns its library and schema, the
/// checked function and its typed arguments.
pub const Call = struct { executor: *const Executor, function: Value, arguments: Value };
/// A call whose request is written: the child's argument vector and the file
/// it answers into.
const Prepared = struct { argv: []const []const u8, response: []const u8 };
/// Bytes of one child's diagnostic stream kept for its failure text.
const stderr_limit = 1024 * 1024;
/// Bytes one response may hold, the bound the captured stdout had.
const response_limit = 32 * 1024 * 1024;
/// What one child left behind: how it ended and what it wrote to stderr, or
/// why it has no ending of its own (it could not start, or ran out of time).
/// A worker gathers it with a private allocator; the calling thread turns it
/// into an `Outcome`.
const Raw = struct {
    term: ?std.process.Child.Term = null,
    stderr: []const u8 = "",
    failure: ?[]const u8 = null,
};
/// The shared queue the execution workers take calls from.
const Pool = struct {
    prepared: []const Prepared,
    raw: []Raw,
    environment: *const std.process.Environ.Map,
    timeout_ns: i96,
    io: std.Io,
    /// Thread-safe allocator the kept stderr of a child lives in.
    keep: std.mem.Allocator,
    next: std.atomic.Value(usize) = .init(0),

    /// Take calls until none is left, running each child to its end. A child's
    /// start-up scratch (its stack, argument and environment blocks) lives in
    /// the worker's arena, which is reset after every child, so a run of many
    /// tests holds one child's scratch per worker.
    fn work(self: *Pool, arena: *std.heap.ArenaAllocator) void {
        while (true) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.prepared.len) return;
            var raw = self.runOne(arena.allocator(), self.prepared[index]);
            raw.stderr = self.keep.dupe(u8, raw.stderr) catch "";
            self.raw[index] = raw;
            _ = arena.reset(.retain_capacity);
        }
    }
    /// Start one child, collect its stderr until it ends, and reap it; kill a
    /// child still running at its deadline.
    fn runOne(self: *Pool, allocator: std.mem.Allocator, prepared: Prepared) Raw {
        const started = spawn.start(allocator, .{ .argv = prepared.argv, .environment = self.environment }) catch |err| return .{ .failure = @errorName(err) };
        const deadline = monotonic(self.io) + self.timeout_ns;
        var stderr: std.ArrayList(u8) = .empty;
        while (true) {
            const now = monotonic(self.io);
            if (now >= deadline) {
                _ = std.os.linux.kill(started.pid, .KILL);
                while (!(drain(allocator, started, &stderr) catch true)) {}
                _ = spawn.reap(started);
                return .{ .failure = "Timeout" };
            }
            var fds = [1]std.os.linux.pollfd{.{ .fd = started.stderr, .events = std.os.linux.POLL.IN, .revents = 0 }};
            const wait = @divFloor(deadline - now + std.time.ns_per_ms - 1, std.time.ns_per_ms);
            _ = std.os.linux.poll(&fds, 1, @intCast(@min(wait, std.math.maxInt(i32))));
            if (fds[0].revents == 0) continue;
            if (drain(allocator, started, &stderr) catch true) return .{ .term = spawn.reap(started), .stderr = stderr.items };
        }
    }
};
/// Read once what a child wrote to its stderr, keeping at most
/// `stderr_limit` bytes. True once the stream has ended.
fn drain(allocator: std.mem.Allocator, started: spawn.Started, stderr: *std.ArrayList(u8)) spawn.Error!bool {
    const ended = try spawn.pump(allocator, started, stderr);
    if (stderr.items.len > stderr_limit) stderr.shrinkRetainingCapacity(stderr_limit);
    return ended;
}
/// Run every call as its own fresh bounded native process, `width` at a time,
/// and return one outcome per call in call order. Every request is written
/// first; then `width` workers (this thread and `width - 1` more) each start a
/// child without copying this process (`qbe_build_spawn`), wait for it and
/// take the next, so starting children — an `execve` each — proceeds on every
/// worker at once instead of one after another. Each child answers into its
/// own response file. A child still running at `timeout_ms` is killed and
/// reported as `Timeout`, and one that cannot start is an infrastructure
/// failure of that case alone, exactly as the one-call `attempt` reports them.
pub fn executeAll(context: fs.Context, calls: []const Call, limits: Limits, width: usize) Error![]Outcome {
    if (!limitsValid(limits)) return error.InvalidTestLimits;
    const a = context.allocator;
    const prepared = try a.alloc(Prepared, calls.len);
    for (calls, prepared) |call, *slot| slot.* = try call.executor.prepare(call, limits);
    const raw = try runPool(context, prepared, limits, width);
    const outcomes = try a.alloc(Outcome, calls.len);
    for (calls, prepared, raw, outcomes) |call, request, ended, *outcome| outcome.* = try conclude(context, call, request, ended);
    return outcomes;
}
/// Run every property batch as its own bounded native process, `width` at a
/// time, exactly as `executeAll` runs tests: one child per batch, each
/// answering into its own response file, a child still running at
/// `timeout_ms` killed. A batch child makes one copied-value call per input,
/// so a property's inputs cost one process launch rather than one each.
pub fn executeBatches(context: fs.Context, calls: []const BatchCall, limits: Limits, width: usize) Error![]BatchOutcome {
    if (!limitsValid(limits)) return error.InvalidTestLimits;
    const a = context.allocator;
    const prepared = try a.alloc(Prepared, calls.len);
    for (calls, prepared) |call, *slot| slot.* = try call.executor.prepareBatch(call, limits);
    const raw = try runPool(context, prepared, limits, width);
    const outcomes = try a.alloc(BatchOutcome, calls.len);
    for (calls, prepared, raw, outcomes) |call, request, ended, *outcome| outcome.* = try concludeBatch(context, call, request, ended);
    return outcomes;
}
/// Start every prepared child on `width` workers and gather how each ended.
fn runPool(context: fs.Context, prepared: []const Prepared, limits: Limits, width: usize) Error![]Raw {
    const a = context.allocator;
    const raw = try a.alloc(Raw, prepared.len);
    @memset(raw, .{});
    var pool: Pool = .{
        .prepared = prepared,
        .raw = raw,
        .environment = try context.bounded(limits.max_memory orelse budget.test_default),
        .timeout_ns = @as(i96, limits.timeout_ms) * std.time.ns_per_ms,
        .io = context.io,
        .keep = a,
    };
    const workers = @max(1, @min(width, prepared.len));
    const arenas = try a.alloc(std.heap.ArenaAllocator, workers);
    for (arenas) |*arena| arena.* = .init(a);
    defer for (arenas) |*arena| arena.deinit();
    const threads = try a.alloc(?std.Thread, workers);
    @memset(threads, null);
    // A worker that cannot be started leaves its share to the others.
    for (threads[1..], arenas[1..]) |*thread, *arena| thread.* = std.Thread.spawn(.{}, Pool.work, .{ &pool, arena }) catch null;
    pool.work(&arenas[0]);
    for (threads) |thread| if (thread) |started| started.join();
    return raw;
}
/// Turn one batch child's ending into its per-input outcomes. The response
/// file is read whatever the ending, because a child that died or timed out
/// mid-batch still finished the inputs before the one it was running.
fn concludeBatch(context: fs.Context, call: BatchCall, prepared: Prepared, raw: Raw) Error!BatchOutcome {
    const a = context.allocator;
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, prepared.response, a, .limited(response_limit)) catch "";
    var outcome = try call.executor.parseBatch(v.text(v.get(call.function, "result")), bytes, call.inputs.len);
    if (outcome.complete) {
        const term = raw.term orelse return outcome;
        if (fs.exitCode(term) == 0) return outcome;
        outcome.complete = false;
    }
    if (raw.failure) |reason| {
        outcome.ending = reason;
        outcome.timed_out = std.mem.eql(u8, reason, "Timeout");
    } else if (raw.term) |term| {
        outcome.ending = try std.fmt.allocPrint(a, process_failed, .{ term, raw.stderr });
    } else outcome.ending = "NativeTestProcessFailed";
    return outcome;
}
/// Turn one child's ending into its outcome: its failure, its abnormal exit,
/// or the answer it wrote.
fn conclude(context: fs.Context, call: Call, prepared: Prepared, raw: Raw) Error!Outcome {
    const a = context.allocator;
    if (raw.failure) |reason| return .{ .status = infrastructure_failure, .diagnostics = reason };
    const term = raw.term orelse return .{ .status = infrastructure_failure, .diagnostics = "NativeTestProcessFailed" };
    if (fs.exitCode(term) != 0) return .{
        .status = infrastructure_failure,
        .diagnostics = try std.fmt.allocPrint(a, process_failed, .{ term, raw.stderr }),
    };
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, prepared.response, a, .limited(response_limit)) catch |err|
        return .{ .status = infrastructure_failure, .diagnostics = @errorName(err) };
    const parsed = try call.executor.parse(v.text(v.get(call.function, "result")), bytes, false);
    return parsed.outcome();
}
fn monotonic(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .awake).nanoseconds;
}
const Parsed = struct {
    status: []const u8,
    actual: Value = .null,
    diagnostics: []const u8 = "",
    output: []const u8 = "",
    steps: u64 = 0,
    trap: Trap = .{},
    /// A benchmark's sampling answer; zero for a test or a batch input.
    sampled: Sampled = .{},

    fn outcome(self: Parsed) Outcome {
        return .{ .status = self.status, .actual = self.actual, .diagnostics = self.diagnostics, .output = self.output, .steps = self.steps, .trap = self.trap };
    }
};
/// The sampling half of a benchmark response.
const Sampled = struct { warmup_iterations: u64 = 0, calibrated_iterations: u64 = 0, raw: []const Batch = &.{} };
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
/// A property batch request: the test request's limits and name, then the
/// input count and each input's node block.
fn batchRequest(a: std.mem.Allocator, name: []const u8, inputs: []const []const wire.Node, limits: Limits) Error![]const u8 {
    if (inputs.len > batch_limit) return error.TestValueLimit;
    var buffer: std.Io.Writer.Allocating = .init(a);
    defer buffer.deinit();
    const w = &buffer.writer;
    try writeNumbers(w, &.{ property_magic, limits.max_steps, limits.max_frames, limits.max_calls });
    try string(w, name);
    try w.writeInt(u64, inputs.len, .little);
    for (inputs) |nodes| try writeNodes(w, nodes);
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
    /// Set when a read ran past the end, which in a batch response means the
    /// child died while writing that record rather than that it wrote a bad one.
    exhausted: bool = false,
    fn number(self: *Reader) Error!u64 {
        if (self.bytes.len - self.offset < 8) return self.short();
        const result = std.mem.readInt(u64, self.bytes[self.offset..][0..8], .little);
        self.offset += 8;
        return result;
    }
    fn text(self: *Reader) Error![]const u8 {
        const size = try self.number();
        if (size > 4096) return error.InvalidNativeTestResponse;
        if (size > self.bytes.len - self.offset) return self.short();
        const value = self.bytes[self.offset..][0..@intCast(size)];
        self.offset += @intCast(size);
        return value;
    }
    /// The captured guest stdout trailer: a length and at most `output_limit` bytes.
    fn output(self: *Reader) Error![]const u8 {
        const size = try self.number();
        if (size > output_limit) return error.InvalidNativeTestResponse;
        if (size > self.bytes.len - self.offset) return self.short();
        const value = self.bytes[self.offset..][0..@intCast(size)];
        self.offset += @intCast(size);
        return value;
    }
    fn short(self: *Reader) Error {
        self.exhausted = true;
        return error.InvalidNativeTestResponse;
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
    try std.testing.expectEqual(@as(u64, 3), parsed.sampled.warmup_iterations);
    try std.testing.expectEqual(@as(u64, 7), parsed.sampled.calibrated_iterations);
    try std.testing.expectEqual(@as(usize, 2), parsed.sampled.raw.len);
    try std.testing.expectEqual(@as(u64, 777), parsed.sampled.raw[1].duration_ns);
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

/// Six fake children for the pool: four answer with a trap whose captured
/// output names their slot, one outlives any short timeout, one fails.
fn poolFixture(context: fs.Context, directory: []const u8) ![6]Executor {
    const a = context.allocator;
    var executors: [6]Executor = undefined;
    const bodies = [_][]const u8{ "", "", "", "", "exec /bin/sleep 5\n", "echo boom >&2\nexit 3\n" };
    for (&executors, bodies, 0..) |*executor, body, slot| {
        const response = try std.fmt.allocPrint(a, "{s}/response-{d}", .{ directory, slot });
        try context.write(response, try trapResponse(a, try std.fmt.allocPrint(a, "call-{d}", .{slot})));
        const script = try std.fmt.allocPrint(a, "{s}/child-{d}", .{ directory, slot });
        // The runner is handed `library request --response FILE`; a script sees FILE as `$3`.
        try context.write(script, if (body.len != 0) body else try std.fmt.allocPrint(a, "exec /bin/cp {s} \"$3\"\n", .{response}));
        executor.* = .{ .context = context, .library = script, .temporary = directory, .executable = "/bin/sh", .types = &.{} };
    }
    return executors;
}
// spec: NATIVE-TEST-PARALLEL-1
test "a parallel run returns every outcome in its call's slot, bounding and isolating each child" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const executors = try poolFixture(context, directory);
    var calls: [6]Call = undefined;
    for (&calls, &executors) |*call, *executor| call.* = .{ .executor = executor, .function = .null, .arguments = .{ .object = .empty } };
    const outcomes = try executeAll(context, &calls, .{ .timeout_ms = 400 }, 3);
    try std.testing.expectEqual(@as(usize, 6), outcomes.len);
    try std.testing.expectEqualStrings("trap", outcomes[0].status);
    try std.testing.expectEqualStrings("call-0", outcomes[0].output);
    try std.testing.expectEqualStrings("call-2", outcomes[2].output);
    try std.testing.expectEqualStrings("call-3", outcomes[3].output);
    try std.testing.expectEqualStrings(infrastructure_failure, outcomes[4].status);
    try std.testing.expectEqualStrings("Timeout", outcomes[4].diagnostics);
    try std.testing.expectEqualStrings(infrastructure_failure, outcomes[5].status);
    try std.testing.expect(std.mem.indexOf(u8, outcomes[5].diagnostics, "NativeTestProcessFailed") != null);
    try std.testing.expect(std.mem.indexOf(u8, outcomes[5].diagnostics, "boom") != null);
    try std.testing.expectError(error.InvalidTestLimits, executeAll(context, &calls, .{ .timeout_ms = 0 }, 3));
}

/// A stand-in `zig` whose `cc … -o FILE` writes an executable script to FILE.
fn fakeZig(context: fs.Context, directory: []const u8) ![]const u8 {
    const path = try std.fs.path.join(context.allocator, &.{ directory, "fake-zig" });
    var file = try std.Io.Dir.createFileAbsolute(context.io, path, .{ .permissions = .executable_file });
    defer file.close(context.io);
    try file.writeStreamingAll(context.io,
        \\#!/bin/sh
        \\while [ "$#" -gt 0 ]; do
        \\  if [ "$1" = "-o" ]; then out="$2"; fi
        \\  shift
        \\done
        \\printf '#!/bin/sh\n' > "$out"
        \\/bin/chmod +x "$out"
        \\
    );
    return path;
}
// spec: NATIVE-TEST-RUNNER-1
test "the compiled harness is published once per source and tool stamp and reused after that" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const zig = try fakeZig(context, directory);
    const cache = try std.fs.path.join(context.allocator, &.{ directory, "cache" });
    const scratch = try std.fs.path.join(context.allocator, &.{ directory, "scratch" });
    try context.mkdir(scratch);
    const first = try runner(context, .{ .cache = cache, .temporary = scratch, .zig = zig, .zig_stamp = "zig-a" });
    try std.testing.expect(first.compiled);
    try std.testing.expect(context.runnable(first.path));
    const second = try runner(context, .{ .cache = cache, .temporary = scratch, .zig = zig, .zig_stamp = "zig-a" });
    try std.testing.expect(!second.compiled);
    try std.testing.expectEqualStrings(first.path, second.path);
    // Another toolchain is another harness.
    const other = try runner(context, .{ .cache = cache, .temporary = scratch, .zig = zig, .zig_stamp = "zig-b" });
    try std.testing.expect(other.compiled);
    try std.testing.expect(!std.mem.eql(u8, first.path, other.path));
    // Without a cache the harness is compiled privately every time.
    const private = try runner(context, .{ .cache = null, .temporary = scratch, .zig = zig, .zig_stamp = "zig-a" });
    try std.testing.expect(private.compiled);
    try std.testing.expect(std.mem.startsWith(u8, private.path, scratch));
}

/// A property batch response answering the first `answered` of `total`
/// inputs, each returning `True` with a captured output naming its slot, and
/// the trailer only when every input was answered.
fn batchResponse(a: std.mem.Allocator, answered: usize, total: usize) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(a);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    try w.writeInt(u64, property_response_magic, .little);
    for (0..answered) |slot| try batchRecord(a, w, slot);
    if (answered == total) try writeNumbers(w, &.{ property_end_magic, total });
    return buffer.toOwnedSlice();
}
fn batchRecord(a: std.mem.Allocator, w: *std.Io.Writer, slot: usize) Error!void {
    try writeNumbers(w, &.{ slot, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try string(w, "");
    try string(w, "");
    try string(w, "");
    try w.writeInt(u64, 0, .little);
    try string(w, "bool");
    try writeNumbers(w, &.{ 1, 0 });
    try string(w, try std.fmt.allocPrint(a, "input-{d}", .{slot}));
}
fn boolExecutor(context: fs.Context, types: []const Value, library: []const u8, directory: []const u8) Executor {
    return .{ .context = context, .library = library, .temporary = directory, .executable = "/bin/sh", .types = types };
}

// spec: PROPERTY-TEST-4
test "property a batch response answers every input in one process and a cut-off one keeps its finished inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const parsed = try std.json.parseFromSliceLeaky(Value, a, "{\"types\":[{\"name\":\"bool\",\"kind\":\"boolean\"}]}", .{});
    const executor = boolExecutor(context, v.array(v.get(parsed, "types")), "", "");
    const whole = try executor.parseBatch("bool", try batchResponse(a, 3, 3), 3);
    try std.testing.expect(whole.complete);
    try std.testing.expectEqual(@as(usize, 3), whole.outcomes.len);
    try std.testing.expect(whole.outcomes[2].actual.bool);
    try std.testing.expectEqualStrings("input-2", whole.outcomes[2].output);
    // A child that died while writing its third record leaves two answers.
    const cut = try batchResponse(a, 3, 4);
    const partial = try executor.parseBatch("bool", cut[0 .. cut.len - 5], 4);
    try std.testing.expect(!partial.complete);
    try std.testing.expectEqual(@as(usize, 2), partial.outcomes.len);
    // A trailer that miscounts the inputs is a malformed answer, not a short one.
    try std.testing.expectError(error.InvalidNativeTestResponse, executor.parseBatch("bool", try batchResponse(a, 3, 3), 4));
    const nothing = try executor.parseBatch("bool", "", 2);
    try std.testing.expectEqual(@as(usize, 0), nothing.outcomes.len);
    // The request carries the limits and name once, then every input's nodes.
    const node = [_]wire.Node{.{ .type = "bool", .bits = 1 }};
    const request = try batchRequest(a, "main::test_p", &.{ &node, &node }, .{ .max_steps = 5, .max_frames = 6, .max_calls = 7 });
    var reader: Reader = .{ .bytes = request };
    try std.testing.expectEqual(property_magic, try reader.number());
    try std.testing.expectEqual(@as(u64, 5), try reader.number());
    try std.testing.expectEqual(@as(u64, 6), try reader.number());
    try std.testing.expectEqual(@as(u64, 7), try reader.number());
    try std.testing.expectEqualStrings("main::test_p", try reader.text());
    try std.testing.expectEqual(@as(u64, 2), try reader.number());
}

// spec-case: PROPERTY-TEST-4
test "property a batch child that dies mid-batch reports the inputs it finished and why it stopped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const directory = try temporary_dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const canned = try std.fs.path.join(a, &.{ directory, "canned" });
    try context.write(canned, try batchResponse(a, 2, 5));
    // The runner is handed `library request --response FILE`; the script sees FILE as `$3`.
    const script = try std.fs.path.join(a, &.{ directory, "dying-child" });
    try context.write(script, try std.fmt.allocPrint(a, "/bin/cp {s} \"$3\"\necho crashed >&2\nexit 7\n", .{canned}));
    const parsed = try std.json.parseFromSliceLeaky(Value, a, "{\"types\":[{\"name\":\"bool\",\"kind\":\"boolean\"}]}", .{});
    const executor = boolExecutor(context, v.array(v.get(parsed, "types")), script, directory);
    const node = [_]wire.Node{.{ .type = "bool", .bits = 1 }};
    const inputs = [_][]const wire.Node{ &node, &node, &node, &node, &node };
    const function = try std.json.parseFromSliceLeaky(Value, a, "{\"name\":\"main::test_p\",\"result\":\"bool\"}", .{});
    const answers = try executeBatches(context, &.{.{ .executor = &executor, .function = function, .inputs = &inputs }}, .{ .timeout_ms = 5000 }, 1);
    try std.testing.expectEqual(@as(usize, 2), answers[0].outcomes.len);
    try std.testing.expect(!answers[0].complete);
    try std.testing.expect(!answers[0].timed_out);
    try std.testing.expect(std.mem.indexOf(u8, answers[0].ending, "crashed") != null);
}

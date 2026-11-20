//! Process-owned developer telemetry. Producers copy structured observations into
//! this optional session; stdout/stderr and compiler outcomes keep their meaning.
const std = @import("std");
const builtin = @import("builtin");
pub const history = @import("../profile_history.zig");
pub const command = @import("../profile_command.zig");
const V = std.json.Value;
const invalidation = @import("../invalidation.zig");

// Only CLI process wiring installs this pointer. It stays fixed until all command
// workers have joined; the recorder serializes concurrent producer allocations.
var active: ?*Recorder = null;

/// Whether the current compiler command is recording history.
pub fn enabled() bool {
    return active != null;
}
/// Install the process session before workers begin, or detach after they join.
pub fn attach(recorder: ?*Recorder) void {
    active = recorder;
}

/// Accept the public command parser's entry, including options before the path.
pub fn setEntry(path: []const u8) void {
    const recorder = active orelse return;
    if (std.mem.eql(u8, path, history.string(recorder.metadata, "entry"))) return;
    const a = recorder.arena.allocator();
    const copy = a.dupe(u8, path) catch {
        markIncomplete();
        return;
    };
    recorder.metadata.object.put(a, "entry", .{ .string = copy }) catch {
        markIncomplete();
        return;
    };
    const source = std.Io.Dir.cwd().readFileAlloc(recorder.io, path, a, .limited(32 << 20)) catch null;
    const digest: V = if (source) |bytes| .{ .string = history.hash(a, bytes) catch {
        markIncomplete();
        return;
    } } else .null;
    recorder.metadata.object.put(a, "entry_sha256", digest) catch {
        markIncomplete();
    };
}

/// Exclude a command with missing observations from trend statistics.
pub fn markIncomplete() void {
    const recorder = active orelse return;
    recorder.mutex.lockUncancelable(recorder.io);
    defer recorder.mutex.unlock(recorder.io);
    recorder.observations.incomplete = true;
}

/// Copy a structured compiler report into the active session.
pub fn capture(value: anytype) void {
    const recorder = active orelse return;
    recorder.mutex.lockUncancelable(recorder.io);
    defer recorder.mutex.unlock(recorder.io);
    const a = recorder.arena.allocator();
    const bytes = std.json.Stringify.valueAlloc(a, value, .{}) catch {
        recorder.observations.incomplete = true;
        return;
    };
    recorder.addJson(bytes);
}

/// Copy an existing JSON report into the active session.
pub fn captureJson(bytes: []const u8) void {
    const recorder = active orelse return;
    recorder.mutex.lockUncancelable(recorder.io);
    defer recorder.mutex.unlock(recorder.io);
    recorder.addJson(bytes);
}

/// One command's isolated archive, report storage and measurement clocks.
pub const Recorder = struct {
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    directory: []const u8,
    metadata: V,
    clock: struct { started: std.Io.Timestamp, setup_ns: u64 },
    observations: struct { reports: std.ArrayList(V) = .empty, incomplete: bool = false } = .{},

    /// Disabled commands do no hashing, git invocation or report collection.
    pub fn start(init: std.process.Init, identity: []const u8, args: []const []const u8) ?Recorder {
        if (args.len < 2 or !supported(args[1])) return null;
        return startImpl(init, identity, args) catch |err| {
            warn(init.io, err);
            return null;
        };
    }

    fn startImpl(init: std.process.Init, identity: []const u8, args: []const []const u8) !?Recorder {
        const setup_start = std.Io.Timestamp.now(init.io, .awake);
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        errdefer arena.deinit();
        const a = arena.allocator();
        const directory = try history.destination(a, init.io, init.environ_map) orelse {
            arena.deinit();
            return null;
        };
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(init.io, ".", a);
        const timestamp = std.Io.Timestamp.now(init.io, .real).nanoseconds;
        const date = try history.utc(a, timestamp);
        var nonce: [16]u8 = undefined;
        std.Io.random(init.io, &nonce);
        const id = try std.fmt.allocPrint(a, "{d:0>20}-{s}", .{ timestamp, std.fmt.bytesToHex(nonce, .lower) });
        const binary = try history.binaryHash(a, init.io, directory);
        const git = try gitMetadata(a, init.io, init.environ_map);
        const cpu = try cpuMetadata(a, init.io);
        const arguments = try history.workloadArguments(a, args[1..]);
        const guest = for (args, 0..) |arg, index| {
            if (std.mem.eql(u8, arg, "--")) break args[index + 1 ..];
        } else &.{};
        const guest_hash = try history.hash(a, try std.json.Stringify.valueAlloc(a, guest, .{}));
        const environment = @import("../environment_identity.zig");
        var variables: std.ArrayList(environment.Variable) = .empty;
        var iterator = init.environ_map.iterator();
        while (iterator.next()) |item| try variables.append(a, .{ .name = item.key_ptr.*, .value = item.value_ptr.* });
        const env_hash = try a.dupe(u8, &environment.digest(.guest, variables.items, &.{}));
        const workload = try history.hash(a, try std.json.Stringify.valueAlloc(a, .{
            .arguments = arguments,
            .guest_arguments_sha256 = guest_hash,
            .cpu = cpu,
            .environment_sha256 = env_hash,
            .jobs = init.environ_map.get("SELKA_JOBS"),
            .unit_jobs = init.environ_map.get("SELKA_UNIT_JOBS"),
            .project = if (history.string(git, "common_directory").len != 0) history.string(git, "common_directory") else cwd,
        }, .{}));
        const entry = if (args.len > 2 and !std.mem.startsWith(u8, args[2], "-")) args[2] else "";
        const source = if (entry.len != 0) std.Io.Dir.cwd().readFileAlloc(init.io, entry, a, .limited(32 << 20)) catch null else null;
        const metadata = try std.json.Stringify.valueAlloc(a, .{
            .version = history.version,
            .id = id,
            .captured_utc = date,
            .timestamp_ns = timestamp,
            .command = args[1],
            .entry = entry,
            .entry_sha256 = if (source) |bytes| try history.hash(a, bytes) else null,
            .cwd = cwd,
            .arguments = arguments,
            .guest_arguments_sha256 = guest_hash,
            .environment_sha256 = env_hash,
            .workload_key = workload,
            .compiler_sha256 = binary,
            .compiler_source_identity = identity,
            .zig_version = builtin.zig_version_string,
            .git = git,
            .cpu = cpu,
            .cache_environment = .{
                .native_objects = init.environ_map.get("SELKA_CORE_RUNTIME_CACHE"),
                .shared_compiler = init.environ_map.get("SELKA_COMPILER_SHARED_CACHE"),
                .shared_tests = init.environ_map.get("SELKA_TEST_SHARED_CACHE"),
                .zig_local = init.environ_map.get("ZIG_LOCAL_CACHE_DIR"),
                .zig_global = init.environ_map.get("ZIG_GLOBAL_CACHE_DIR"),
            },
            .cache_state = "observed in reports; OS and CPU caches uncontrolled",
            .measurement_scope = "in-process command dispatch; excludes process startup, metadata capture and final history publication",
            .measurement_quality = "ordinary developer invocation; CPU contention uncontrolled; not an isolated benchmark",
        }, .{});
        const parsed = try std.json.parseFromSliceLeaky(V, a, metadata, .{});
        return .{ .arena = arena, .io = init.io, .directory = directory, .metadata = parsed, .clock = .{ .setup_ns = elapsed(init.io, setup_start), .started = std.Io.Timestamp.now(init.io, .awake) } };
    }

    fn addJson(self: *Recorder, bytes: []const u8) void {
        const a = self.arena.allocator();
        if (bytes.len > history.record_limit) {
            self.observations.incomplete = true;
            return;
        }
        const value = std.json.parseFromSliceLeaky(V, a, bytes, .{}) catch {
            self.observations.incomplete = true;
            return;
        };
        self.observations.reports.append(a, value) catch {
            self.observations.incomplete = true;
        };
    }

    /// Publish the completed command without changing its exit status on failure.
    pub fn finish(self: *Recorder, status: u8) void {
        const duration = elapsed(self.io, self.clock.started);
        self.finishImpl(status, duration) catch |err| warn(self.io, err);
    }

    fn finishImpl(self: *Recorder, status: u8, duration: u64) !void {
        const a = self.arena.allocator();
        try self.metadata.object.put(a, "elapsed_ns", .{ .integer = @intCast(duration) });
        try self.metadata.object.put(a, "exit_code", .{ .integer = status });
        try self.metadata.object.put(a, "capture_setup_ns", .{ .integer = @intCast(self.clock.setup_ns) });
        try self.metadata.object.put(a, "incomplete", .{ .bool = self.observations.incomplete });
        try self.metadata.object.put(a, "reports", .{ .array = std.json.Array.fromOwnedSlice(a, self.observations.reports.items) });
        const bytes = try std.json.Stringify.valueAlloc(a, self.metadata, .{});
        try validateRecordSize(bytes.len);
        const path = try std.fmt.allocPrint(a, "{s}/runs/{s}.json", .{ self.directory, history.string(self.metadata, "id") });
        try history.atomicWrite(a, self.io, path, bytes);
    }

    pub fn deinit(self: *Recorder) void {
        self.arena.deinit();
    }
};

fn supported(name_arg: []const u8) bool {
    for ([_][]const u8{ "check", "check-project", "check-module", "run", "run-project", "build", "test" }) |name|
        if (std.mem.eql(u8, name_arg, name)) return true;
    return false;
}

fn elapsed(io: std.Io, started: std.Io.Timestamp) u64 {
    return std.math.lossyCast(u64, @max(0, started.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds));
}

fn warn(io: std.Io, err: anyerror) void {
    var buffer: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "warning: developer profile history unavailable: {s}\n", .{@errorName(err)}) catch return;
    std.Io.File.stderr().writeStreamingAll(io, text) catch return;
}

fn gitOutput(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) ?[]const u8 {
    const argv = std.mem.concat(a, []const u8, &.{ &.{"git"}, args }) catch return null;
    const result = std.process.run(a, io, .{ .argv = argv, .environ_map = env, .timeout = .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } }, .stdout_limit = .limited(4 << 20), .stderr_limit = .limited(4096) }) catch return null;
    if (result.term != .exited or result.term.exited != 0) return null;
    return result.stdout;
}

fn gitMetadata(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map) !V {
    const basic = gitOutput(a, io, env, &.{ "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir", "HEAD" }) orelse return .null;
    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, basic, "\n"), '\n');
    const root = lines.next() orelse return .null;
    const common = lines.next() orelse return .null;
    const commit = lines.next() orelse return .null;
    const changed = gitOutput(a, io, env, &.{ "diff", "--name-only", "-z", "HEAD", "--" });
    const diff = gitOutput(a, io, env, &.{ "diff", "--no-ext-diff", "--binary", "HEAD", "--" });
    var paths: std.ArrayList([]const u8) = .empty;
    if (changed) |bytes| {
        var names = std.mem.splitScalar(u8, bytes, 0);
        while (names.next()) |name| if (name.len != 0) try paths.append(a, name);
    }
    const bytes = try std.json.Stringify.valueAlloc(a, .{
        .root = root,
        .common_directory = common,
        .commit = commit,
        .changed_files = paths.items,
        .tracked_diff_sha256 = if (diff) |text| try history.hash(a, text) else null,
        .dirty_scope = "tracked diff against HEAD; untracked sources are not enumerated",
    }, .{});
    return std.json.parseFromSliceLeaky(V, a, bytes, .{});
}

fn cpuMetadata(a: std.mem.Allocator, io: std.Io) !V {
    const info = std.Io.Dir.cwd().readFileAlloc(io, "/proc/cpuinfo", a, .limited(1 << 20)) catch "";
    var model: []const u8 = "unknown";
    var lines = std.mem.splitScalar(u8, info, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "model name")) continue;
        if (std.mem.indexOfScalar(u8, line, ':')) |colon| model = std.mem.trim(u8, line[colon + 1 ..], " \t");
        break;
    }
    var mask: std.os.linux.cpu_set_t = @splat(0);
    const valid = std.os.linux.errno(std.os.linux.sched_getaffinity(0, @sizeOf(@TypeOf(mask)), &mask)) == .SUCCESS;
    const hostname = std.Io.Dir.cwd().readFileAlloc(io, "/proc/sys/kernel/hostname", a, .limited(4096)) catch "unknown";
    const bytes = try std.json.Stringify.valueAlloc(a, .{
        .host = std.mem.trim(u8, hostname, "\n"),
        .model = model,
        .architecture = @tagName(builtin.cpu.arch),
        .os = @tagName(builtin.os.tag),
        .affinity = if (valid) try a.dupe(u8, &std.fmt.bytesToHex(std.mem.asBytes(&mask).*, .lower)) else null,
    }, .{});
    return std.json.parseFromSliceLeaky(V, a, bytes, .{});
}

fn validateRecordSize(size: usize) error{ProfileRecordTooLarge}!void {
    if (size > history.record_limit) return error.ProfileRecordTooLarge;
}

/// Preserve requested report failures while keeping optional history best effort.
pub fn renderWork(a: std.mem.Allocator, work: invalidation.Work, requested: bool) invalidation.Error!?[]u8 {
    return invalidation.renderWork(a, work) catch |err| {
        if (requested) return err;
        markIncomplete();
        return null;
    };
}

test "profile record size rejects ProfileRecordTooLarge without truncating" {
    try std.testing.expectEqual({}, try validateRecordSize(history.record_limit));
    try std.testing.expectError(error.ProfileRecordTooLarge, validateRecordSize(history.record_limit + 1));
}

test "profile startImpl releases its arena when configuration fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var env: std.process.Environ.Map = .init(a);
    try env.put("XDG_STATE_HOME", root);
    try history.configure(a, std.testing.io, &env, true, "invalid-relative-archive");
    const init: std.process.Init = .{
        .minimal = .{ .args = .{ .vector = &.{} }, .environ = std.testing.environ },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &env,
        .preopens = .empty,
    };
    try std.testing.expectError(error.InvalidProfileConfiguration, Recorder.startImpl(init, "test", &.{ "selka", "check", "test.selka" }));
}

test "profile renderWork retains explicit errors and marks optional reports incomplete" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var recorder: Recorder = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .io = std.testing.io,
        .directory = "",
        .metadata = .null,
        .clock = .{ .started = .now(std.testing.io, .awake), .setup_ns = 0 },
    };
    defer recorder.deinit();
    attach(&recorder);
    defer attach(null);
    try std.testing.expectError(error.OutOfMemory, renderWork(failing.allocator(), .{}, true));
    try std.testing.expect(try renderWork(failing.allocator(), .{}, false) == null);
    try std.testing.expect(recorder.observations.incomplete);
}

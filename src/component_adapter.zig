//! Explicit component launch boundary; the reference index stays pure.
//! Bounds framing, capture, and the complete child lifecycle with forced reaping.
const std = @import("std");
const typed = @import("typed.zig");
const index = @import("tests_index.zig");
const wire = @import("component_protocol.zig");
const config = @import("config/component_runtime.zig");
/// Failures at the bounded component boundary.
pub const Error = error{ OutOfMemory, ComponentMissing, ComponentManifest, ComponentDigest, ComponentProtocol, ComponentTimeout, ComponentFailed, ComponentIo, ComponentShadowMismatch, ComponentMode };
/// Explicit host capabilities and launch limits.
pub const Runtime = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    component_dir: ?[]const u8 = null,
    timeout_ms: i64 = 30000,
};
/// Select the pure reference, native component, or exact shadow comparison.
pub const Adapter = union(enum) {
    reference,
    component: Runtime,
    shadow: Runtime,
    invalid,
    /// Build an index over the checked program, borrowing its function names.
    pub fn build(self: Adapter, a: std.mem.Allocator, program: typed.Program, graph: []const []const typed.FunctionId, tests: []const typed.FunctionId) Error!index.Index {
        const names = try a.alloc([]const u8, program.functions.len);
        defer a.free(names);
        for (names, program.functions) |*name, function| name.* = function.name;
        return self.buildNamed(a, names, graph, tests);
    }
    /// Build an index over a named graph, preserving discovery order.
    pub fn buildNamed(self: Adapter, a: std.mem.Allocator, names: []const []const u8, graph: []const []const typed.FunctionId, tests: []const typed.FunctionId) Error!index.Index {
        if (names.len != graph.len) return error.ComponentProtocol;
        return switch (self) {
            .reference => index.buildNamed(a, names, graph, tests),
            .component => |runtime| execute(runtime, a, names, graph, tests),
            .shadow => |runtime| blk: {
                var actual = try execute(runtime, a, names, graph, tests);
                errdefer actual.deinit();
                var expected = try index.buildNamed(a, names, graph, tests);
                defer expected.deinit();
                for (actual.direct, expected.direct, actual.reached, expected.reached) |ad, ed, ar, er| {
                    if (!same(ad, ed) or !same(ar, er)) return error.ComponentShadowMismatch;
                }
                break :blk actual;
            },
            .invalid => error.ComponentMode,
        };
    }
};
/// Read deployment configuration; invalid modes fail when used.
pub fn configured(io: std.Io, environ: *const std.process.Environ.Map) Adapter {
    const runtime: Runtime = .{ .io = io, .environ = environ, .component_dir = environ.get("MYLANG_COMPONENT_DIR") };
    const mode = environ.get("MYLANG_TEST_INDEX_MODE") orelse "component";
    if (std.mem.eql(u8, mode, "reference")) return .reference;
    if (std.mem.eql(u8, mode, "component")) return .{ .component = runtime };
    if (std.mem.eql(u8, mode, "shadow")) return .{ .shadow = runtime };
    return .invalid;
}
fn same(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| if (!std.mem.eql(u8, left, right)) return false;
    return true;
}
const Manifest = struct { format: u32, component: []const u8, protocol: u32, schema: u32, artifact: []const u8, sha256: []const u8 };
/// Verify manifest and binary SHA-256, returning an allocator-owned path.
pub fn artifact(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error![]const u8 {
    const path = try std.fs.path.join(a, &.{ directory, "test-index.json" });
    defer a.free(path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(65536)) catch |err| return mapFailure(err, error.ComponentMissing);
    defer a.free(bytes);
    const parsed = std.json.parseFromSlice(Manifest, a, bytes, .{ .ignore_unknown_fields = true }) catch |err| return mapFailure(err, error.ComponentManifest);
    defer parsed.deinit();
    const m = parsed.value;
    if (m.format != 1 or m.protocol != 1 or m.schema != 1) return error.ComponentManifest;
    if (!std.mem.eql(u8, m.component, "test-index") or m.sha256.len != 64) return error.ComponentManifest;
    if (m.artifact.len == 0 or std.mem.indexOfAny(u8, m.artifact, "/\\") != null) return error.ComponentManifest;
    if (std.mem.eql(u8, m.artifact, ".") or std.mem.eql(u8, m.artifact, "..")) return error.ComponentManifest;
    var expected: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&expected, m.sha256) catch |err| return mapFailure(err, error.ComponentManifest);
    const binary = try std.fs.path.join(a, &.{ directory, m.artifact });
    errdefer a.free(binary);
    const contents = std.Io.Dir.cwd().readFileAlloc(io, binary, a, .limited(64 << 20)) catch |err| return mapFailure(err, error.ComponentMissing);
    defer a.free(contents);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
    if (!std.mem.eql(u8, &digest, &expected)) return error.ComponentDigest;
    return binary;
}
fn execute(runtime: Runtime, a: std.mem.Allocator, names: []const []const u8, graph: []const []const typed.FunctionId, tests: []const typed.FunctionId) Error!index.Index {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const directory = runtime.component_dir orelse blk: {
        const executable = std.process.executableDirPathAlloc(runtime.io, scratch) catch |err| return mapFailure(err, error.ComponentIo);
        break :blk try std.fs.path.join(scratch, &.{ executable, "..", "libexec", "mylang", "components" });
    };
    const binary = try artifact(scratch, runtime.io, directory);
    var nonce: [16]u8 = undefined;
    std.Io.random(runtime.io, &nonce);
    const configured_root = runtime.environ.get("TMPDIR") orelse "";
    const temporary_root = if (configured_root.len == 0) config.temporary_root else configured_root;
    const temporary_name = try std.fmt.allocPrint(scratch, "mylang-component-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
    const temporary = try std.fs.path.join(scratch, &.{ temporary_root, temporary_name });
    std.Io.Dir.cwd().createDir(runtime.io, temporary, .fromMode(0o700)) catch |err| return mapFailure(err, error.ComponentIo);
    defer discard(runtime.io, temporary);
    const request_path = try std.fs.path.join(scratch, &.{ temporary, "request.bin" });
    const request = try wire.request(scratch, graph, tests, std.mem.readInt(u64, nonce[0..8], .little));
    std.Io.Dir.cwd().writeFile(runtime.io, .{ .sub_path = request_path, .data = request.bytes }) catch |err| return mapFailure(err, error.ComponentIo);
    const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMilliseconds(runtime.timeout_ms) } };
    const result = runBounded(scratch, runtime.io, .{
        .argv = &.{ binary, "--request", request_path },
        .environ_map = runtime.environ,
        .timeout = timeout.toDeadline(runtime.io),
        .stdout_limit = .limited(wire.reply_limit),
        .stderr_limit = .limited(65536),
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Timeout => error.ComponentTimeout,
        error.StreamTooLong => error.ComponentProtocol,
        else => error.ComponentIo,
    };
    const successful = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!successful) {
        std.Io.File.stderr().writeStreamingAll(runtime.io, result.stderr) catch |err| return mapFailure(err, error.ComponentIo);
        return error.ComponentFailed;
    }
    return wire.reply(a, result.stdout, request.identity, names, tests);
}

/// Explain a boundary failure without exposing binary output as text.
pub fn diagnostic(err: Error) []const u8 {
    return switch (err) {
        error.ComponentMissing => "test-index component or manifest missing; rebuild/install components or set MYLANG_COMPONENT_DIR",
        error.ComponentManifest => "test-index manifest invalid; expected format/protocol/schema 1 and a local artifact filename",
        error.ComponentDigest => "test-index artifact SHA-256 differs from manifest; rebuild components",
        error.ComponentProtocol => "test-index component frame malformed, oversized, stale, or contains invalid IDs",
        error.ComponentTimeout => "test-index component exceeded its execution deadline",
        error.ComponentFailed => "test-index component exited unsuccessfully or trapped",
        error.ComponentIo => "test-index component could not be read or launched",
        error.ComponentShadowMismatch => "test-index component disagrees with the reference algorithm",
        error.ComponentMode => "MYLANG_TEST_INDEX_MODE must be component, reference, or shadow",
        error.OutOfMemory => "out of memory building test index",
    };
}

fn mapFailure(err: anyerror, fallback: Error) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else fallback;
}

/// Cleanup is best effort after the bounded child has terminated.
fn discard(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch |err| {
        var buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: test-index request cleanup failed: {t}\n", .{err}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
        return;
    };
}

const LaunchEvent = union(enum) {
    completed: std.process.RunError!std.process.RunResult,
    deadline: std.Io.Cancelable!void,
};

/// Race the entire child lifecycle against its deadline, including wait after EOF.
/// The allocator is the launch arena, so discarded late results die with that arena.
fn runBounded(arena: std.mem.Allocator, io: std.Io, options: std.process.RunOptions) std.process.RunError!std.process.RunResult {
    var events: [2]LaunchEvent = undefined;
    var select = std.Io.Select(LaunchEvent).init(io, &events);
    // Cancel joins every task before execute releases the launch arena. The run
    // task's defer kills and reaps its child when cancellation interrupts wait.
    defer select.cancelDiscard();
    select.concurrent(.completed, runChild, .{ arena, io, options }) catch return error.SystemResources;
    select.concurrent(.deadline, std.Io.Timeout.sleep, .{ options.timeout, io }) catch return error.SystemResources;
    const event = try select.await();
    return switch (event) {
        .completed => |result| result,
        .deadline => |result| blk: {
            try result;
            break :blk error.Timeout;
        },
    };
}

/// Own the process explicitly: canceled stdlib wait clears its ID before returning.
fn runChild(a: std.mem.Allocator, io: std.Io, options: std.process.RunOptions) std.process.RunError!std.process.RunResult {
    var child = try std.process.spawn(io, .{
        .argv = options.argv,
        .environ_map = options.environ_map,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer terminate(io, &child);
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(a, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(64, options.timeout)) |_| {
        if (reader.reader(0).buffered().len > wire.reply_limit) return error.StreamTooLong;
        if (reader.reader(1).buffered().len > 65536) return error.StreamTooLong;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |other| return other,
    }
    try reader.checkAnyError();
    const pid = child.id;
    const term = child.wait(io) catch |err| {
        // On Linux the stdlib clears ownership on cancellation without reaping.
        // Its descriptor cleanup has already run; restore only process ownership.
        child.id = pid;
        return err;
    };
    const stdout = try reader.toOwnedSlice(0);
    errdefer a.free(stdout);
    return .{ .term = term, .stdout = stdout, .stderr = try reader.toOwnedSlice(1) };
}

/// SIGKILL makes reaping bounded even if a component ignores SIGTERM.
fn terminate(io: std.Io, child: *std.process.Child) void {
    const pid = child.id orelse return;
    _ = std.os.linux.kill(pid, std.os.linux.SIG.KILL);
    child.kill(io);
}

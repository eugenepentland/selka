//! Shared bounded component process ownership and verified deployment.
const std = @import("std");
const content_hash = @import("component_digest.zig");
/// Immutable Linux executable snapshot. Keep this descriptor alive through launch.
/// A sealed memfd can execute while sibling forks retain writable descriptors.
pub fn sealedExecutable(io: std.Io, contents: []const u8) SnapshotError!std.Io.File {
    const linux = std.os.linux;
    const fd = try std.posix.memfd_createZ("mylang-planner", linux.MFD.CLOEXEC | linux.MFD.ALLOW_SEALING);
    const file: std.Io.File = .{ .handle = fd, .flags = .{ .nonblocking = false } };
    errdefer file.close(io);
    try file.writeStreamingAll(io, contents);
    try file.setPermissions(io, .fromMode(0o500));
    const seals = linux.F.SEAL_WRITE | linux.F.SEAL_GROW | linux.F.SEAL_SHRINK | linux.F.SEAL_SEAL;
    const result = linux.fcntl(fd, linux.F.ADD_SEALS, seals);
    if (linux.errno(result) != .SUCCESS) return std.posix.unexpectedErrno(linux.errno(result));
    return file;
}

/// Snapshot creation fails closed when the kernel cannot enforce immutability.
pub const SnapshotError = std.posix.MemFdCreateError || std.Io.File.Writer.Error || std.Io.File.SetPermissionsError || std.posix.UnexpectedError;

const LaunchEvent = union(enum) {
    completed: std.process.RunError!std.process.RunResult,
    deadline: std.Io.Cancelable!void,
};

/// Race the entire child lifecycle against its deadline, including wait after EOF.
/// The allocator is the launch arena, so discarded late results die with that arena.
pub fn runBounded(arena: std.mem.Allocator, io: std.Io, options: std.process.RunOptions) std.process.RunError!std.process.RunResult {
    var events: [2]LaunchEvent = undefined;
    var select = std.Io.Select(LaunchEvent).init(io, &events);
    // Cancel joins every task before execute releases the launch arena. The run
    // task's defer kills and reaps its child when cancellation interrupts wait.
    defer select.cancelDiscard();
    select.concurrent(.completed, runChild, .{ arena, io, options }) catch |err| {
        diagnose(io, "start child task", err);
        return error.SystemResources;
    };
    select.concurrent(.deadline, std.Io.Timeout.sleep, .{ options.timeout, io }) catch |err| {
        diagnose(io, "start deadline task", err);
        return error.SystemResources;
    };
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
    var child = std.process.spawn(io, .{
        .argv = options.argv,
        .environ_map = options.environ_map,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| {
        diagnose(io, "spawn child", err);
        return err;
    };
    defer terminate(io, &child);
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(a, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (reader.fill(64, options.timeout)) |_| {
        if (options.stdout_limit.toInt()) |limit| {
            if (reader.reader(0).buffered().len > limit) return error.StreamTooLong;
        }
        if (options.stderr_limit.toInt()) |limit| {
            if (reader.reader(1).buffered().len > limit) return error.StreamTooLong;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |other| {
            diagnose(io, "capture output", other);
            return other;
        },
    }
    reader.checkAnyError() catch |err| {
        diagnose(io, "read output stream", err);
        return err;
    };
    const pid = child.id;
    const term = child.wait(io) catch |err| {
        // On Linux the stdlib clears ownership on cancellation without reaping.
        // Its descriptor cleanup has already run; restore only process ownership.
        child.id = pid;
        diagnose(io, "wait for child", err);
        return err;
    };
    const stdout = try reader.toOwnedSlice(0);
    errdefer a.free(stdout);
    return .{ .term = term, .stdout = stdout, .stderr = try reader.toOwnedSlice(1) };
}

fn diagnose(io: std.Io, stage: []const u8, err: anyerror) void {
    switch (err) {
        error.Canceled, error.Timeout, error.StreamTooLong, error.OutOfMemory => return,
        else => {},
    }
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "mylang: component {s} failed: {s}\n", .{ stage, @errorName(err) }) catch return;
    std.Io.File.stderr().writeStreamingAll(io, message) catch return;
}

/// SIGKILL makes reaping bounded even if a component ignores SIGTERM.
fn terminate(io: std.Io, child: *std.process.Child) void {
    const pid = child.id orelse return;
    _ = std.os.linux.kill(pid, std.os.linux.SIG.KILL);
    child.kill(io);
}

/// Verified executable deployment identity and owned path.
pub const Verified = struct { path: []u8, digest: [32]u8 };
/// Verified deployment and its allocator-owned immutable executable bytes.
pub const Snapshot = struct {
    verified: Verified,
    contents: []const u8,
    /// Release both owned allocations after all borrowers have finished.
    pub fn deinit(self: Snapshot, a: std.mem.Allocator) void {
        a.free(self.verified.path);
        a.free(self.contents);
    }
};
/// Shared deployment validation failures.
pub const Error = error{ OutOfMemory, ComponentMissing, ComponentManifest, ComponentDigest };
const Manifest = struct { format: u32, component: []const u8, protocol: u32, schema: u32, artifact: []const u8, sha256: []const u8 };
/// Verify current deployment bytes with fixed hash storage, returning an owned path.
/// Every call authenticates content; filesystem metadata is never a trust shortcut.
pub fn artifact(a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) Error!Verified {
    const deployment = try manifestDeployment(a, io, directory, component);
    errdefer a.free(deployment.path);
    const digest = try digestFile(io, deployment.path, executable_limit);
    if (!std.mem.eql(u8, &digest, &deployment.digest)) return error.ComponentDigest;
    return .{ .path = deployment.path, .digest = digest };
}
const executable_limit = 64 << 20;
/// Verify once and retain the exact bytes associated with the deployment digest.
pub fn artifactSnapshot(a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) Error!Snapshot {
    const deployment = try manifestDeployment(a, io, directory, component);
    errdefer a.free(deployment.path);
    const contents = std.Io.Dir.cwd().readFileAlloc(io, deployment.path, a, .limited(executable_limit)) catch |err| return mapFailure(err, error.ComponentMissing);
    errdefer a.free(contents);
    const digest = content_hash.hash(contents);
    if (!std.mem.eql(u8, &digest, &deployment.digest)) return error.ComponentDigest;
    return .{ .verified = .{ .path = deployment.path, .digest = digest }, .contents = contents };
}
fn manifestDeployment(a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) Error!Verified {
    const filename = try std.fmt.allocPrint(a, "{s}.json", .{component});
    defer a.free(filename);
    const path = try std.fs.path.join(a, &.{ directory, filename });
    defer a.free(path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(65536)) catch |err| return mapFailure(err, error.ComponentMissing);
    defer a.free(bytes);
    const parsed = std.json.parseFromSlice(Manifest, a, bytes, .{ .ignore_unknown_fields = true }) catch |err| return mapFailure(err, error.ComponentManifest);
    defer parsed.deinit();
    const m = parsed.value;
    const version: u32 = if (std.mem.eql(u8, component, "cache-plan")) 2 else 1;
    const schema_two = std.mem.eql(u8, component, "lexer-pilot") or std.mem.eql(u8, component, "parser-pilot") or std.mem.eql(u8, component, "body-check");
    const schema: u32 = if (schema_two) 2 else version;
    if (m.format != 1 or m.protocol != version or m.schema != schema) return error.ComponentManifest;
    if (!std.mem.eql(u8, m.component, component) or m.sha256.len != 64) return error.ComponentManifest;
    if (m.artifact.len == 0 or std.mem.indexOfAny(u8, m.artifact, "/\\") != null) return error.ComponentManifest;
    if (std.mem.eql(u8, m.artifact, ".") or std.mem.eql(u8, m.artifact, "..")) return error.ComponentManifest;
    var expected: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&expected, m.sha256) catch |err| return mapFailure(err, error.ComponentManifest);
    const binary = try std.fs.path.join(a, &.{ directory, m.artifact });
    return .{ .path = binary, .digest = expected };
}
fn digestFile(io: std.Io, path: []const u8, limit: usize) Error![32]u8 {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| return mapFailure(err, error.ComponentMissing);
    defer file.close(io);
    var buffer: [65536]u8 = undefined;
    var hash = content_hash.Hasher.init();
    var total: usize = 0;
    while (true) {
        const n = file.readStreaming(io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return mapFailure(err, error.ComponentMissing),
        };
        if (n == 0) break;
        if (n > limit - total) return error.ComponentMissing;
        total += n;
        hash.update(buffer[0..n]);
    }
    return hash.final();
}

fn mapFailure(err: anyerror, fallback: Error) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else fallback;
}

// spec-case: SELFHOST-BODY-MANAGED-1
test "body check artifact admission requires managed schema two" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(directory);
    const contents = "body component fixture";
    const digest = content_hash.hash(contents);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = contents });
    const schema_one = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"body-check\",\"protocol\":1,\"schema\":1,\"artifact\":\"producer\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(schema_one);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "body-check.json", .data = schema_one });
    try std.testing.expectError(error.ComponentManifest, artifact(a, std.testing.io, directory, "body-check"));
    const schema_two = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"body-check\",\"protocol\":1,\"schema\":2,\"artifact\":\"producer\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(schema_two);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "body-check.json", .data = schema_two });
    const accepted = try artifact(a, std.testing.io, directory, "body-check");
    defer a.free(accepted.path);
    try std.testing.expectEqualSlices(u8, &digest, &accepted.digest);
}

// spec: SELFHOST-FRONTEND-VERIFY-1
test "artifact identities stream bounded content and reject same-path replacements" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(directory);
    const contents = try a.alloc(u8, 1 << 20);
    defer a.free(contents);
    @memset(contents, 19);
    const digest = content_hash.hash(contents);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = contents });
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"lexer-pilot\",\"protocol\":1,\"schema\":2,\"artifact\":\"producer\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lexer-pilot.json", .data = manifest });
    var storage: [32768]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    const verified = try artifact(fixed.allocator(), std.testing.io, directory, "lexer-pilot");
    try std.testing.expectEqualSlices(u8, &digest, &verified.digest);
    const snapshot = try artifactSnapshot(a, std.testing.io, directory, "lexer-pilot");
    defer snapshot.deinit(a);
    try std.testing.expectEqualSlices(u8, contents, snapshot.contents);
    try std.testing.expectEqualSlices(u8, &verified.digest, &snapshot.verified.digest);
    try std.testing.expectError(error.ComponentMissing, digestFile(std.testing.io, verified.path, contents.len - 1));
    const exact = try digestFile(std.testing.io, verified.path, contents.len);
    try std.testing.expectEqualSlices(u8, &digest, &exact);
    contents[contents.len - 1] ^= 1;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = contents });
    try std.testing.expectError(error.ComponentDigest, artifact(a, std.testing.io, directory, "lexer-pilot"));
    try std.testing.expectError(error.ComponentDigest, artifactSnapshot(a, std.testing.io, directory, "lexer-pilot"));
}

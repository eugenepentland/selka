//! Verified cache planner identity is bound before receipt lookup or replay.
const std = @import("std");
const wire = @import("cache_plan_protocol.zig");
const launch = @import("component_launch.zig");
const config = @import("config/component_runtime.zig");
/// Failures never authorize replay or an empty affected set.
pub const Error = error{
    OutOfMemory,
    ComponentMissing,
    ComponentManifest,
    ComponentDigest,
    ComponentProtocol,
    ComponentTimeout,
    ComponentFailed,
    ComponentIo,
    ComponentShadowMismatch,
    ComponentMode,
    ComponentChanged,
    UnsupportedCacheContract,
};
/// Explicit independently qualified execution mode.
pub const Mode = enum { reference, component, shadow };
/// Borrowable run-scoped binding; its allocated paths live with the binding allocator.
pub const Bound = struct {
    identity: wire.Digest,
    mode: Mode,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    directory: ?[]u8,
    artifact: ?launch.Verified,
    /// Release paths once after all borrowed copies have expired; arenas may omit this.
    pub fn deinit(self: *Bound, a: std.mem.Allocator) void {
        if (self.directory) |directory| a.free(directory);
        if (self.artifact) |artifact| a.free(artifact.path);
    }
    /// Revalidate deployment before accepting replay or publishing new receipts.
    pub fn validate(self: Bound, a: std.mem.Allocator) Error!void {
        if (self.mode == .reference) return;
        const current = try launch.artifact(a, self.io, self.directory.?, "cache-plan");
        defer a.free(current.path);
        if (!std.mem.eql(u8, &current.digest, &self.artifact.?.digest) or !std.mem.eql(u8, current.path, self.artifact.?.path)) return error.ComponentChanged;
    }
    /// Execute one bounded batch, or the explicit host oracle; shadow compares IDs exactly.
    pub fn batch(self: Bound, a: std.mem.Allocator, graph: wire.Graph, roots: []const []const u32) Error!wire.Results {
        if (self.mode == .reference) return wire.reference(a, graph, roots);
        try self.validate(a);
        var actual = try self.execute(a, graph, roots);
        errdefer actual.deinit();
        if (self.mode == .shadow) {
            var expected = try wire.reference(a, graph, roots);
            defer expected.deinit();
            for (actual.batches, expected.batches) |left, right| if (!std.mem.eql(u32, left, right)) return error.ComponentShadowMismatch;
        }
        return actual;
    }
    fn execute(self: Bound, a: std.mem.Allocator, graph: wire.Graph, roots: []const []const u32) Error!wire.Results {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const scratch = arena.allocator();
        var nonce: [16]u8 = undefined;
        std.Io.random(self.io, &nonce);
        const root = self.environ.get("TMPDIR") orelse config.temporary_root;
        const name = try std.fmt.allocPrint(scratch, "mylang-cache-plan-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
        const directory = try std.fs.path.join(scratch, &.{ if (root.len == 0) config.temporary_root else root, name });
        std.Io.Dir.cwd().createDir(self.io, directory, .fromMode(0o700)) catch |err| return ioFailure(self.io, "create temporary directory", err);
        defer discard(self.io, directory);
        // Seal the verified bytes before launch; disk copies can race sibling forks
        // retaining their write descriptors and fail exec with ETXTBSY.
        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, self.artifact.?.path, scratch, .limited(64 << 20)) catch |err| return ioFailure(self.io, "read verified executable", err);
        var digest: wire.Digest = undefined;
        std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
        if (!std.mem.eql(u8, &digest, &self.artifact.?.digest)) return error.ComponentChanged;
        const file = launch.sealedExecutable(self.io, contents) catch |err| return ioFailure(self.io, "seal executable snapshot", err);
        defer file.close(self.io);
        // The parent's proc path survives child CLOEXEC, including shebang interpreters.
        const executable = try std.fmt.allocPrint(scratch, "/proc/{d}/fd/{d}", .{ std.os.linux.getpid(), file.handle });
        const request = try wire.request(scratch, graph, roots, std.mem.readInt(u64, nonce[0..8], .little));
        const path = try std.fs.path.join(scratch, &.{ directory, "request.bin" });
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = request.bytes }) catch |err| return ioFailure(self.io, "write request", err);
        const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMilliseconds(30000) } };
        const result = launch.runBounded(scratch, self.io, .{
            .argv = &.{ executable, "--request", path },
            .environ_map = self.environ,
            .timeout = timeout.toDeadline(self.io),
            .stdout_limit = .limited(wire.reply_limit),
            .stderr_limit = .limited(65536),
        }) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Timeout => error.ComponentTimeout,
            error.StreamTooLong => error.ComponentProtocol,
            else => ioFailure(self.io, "run planner", err),
        };
        const successful = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        if (!successful) return error.ComponentFailed;
        try self.validate(scratch);
        return wire.reply(a, result.stdout, request.identity, graph, roots);
    }
};
/// Eagerly bind explicit mode, schema, and verified implementation before any replay.
pub fn bind(a: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) Error!Bound {
    // Wire v1 can express only this policy; future durable contracts must pass
    // explicit contract validation before a new protocol can bind them.
    try (@import("cache_plan_contract.zig").Policy{}).validate();
    const configured = environ.get("MYLANG_CACHE_PLAN_MODE") orelse "component";
    const mode = std.meta.stringToEnum(Mode, configured) orelse return error.ComponentMode;
    var result: Bound = .{ .identity = undefined, .mode = mode, .io = io, .environ = environ, .directory = null, .artifact = null };
    errdefer result.deinit(a);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("selka-cache-plan-v1/pure/disposable/success-only/");
    hash.update(@tagName(mode));
    if (mode == .reference) {
        hash.update("host-reach-v1/sorted-digest-id/ordered-roots");
    } else {
        result.directory = if (environ.get("MYLANG_COMPONENT_DIR")) |directory| try a.dupe(u8, directory) else blk: {
            const executable = std.process.executableDirPathAlloc(io, a) catch |err| return ioFailure(io, "locate executable directory", err);
            defer a.free(executable);
            break :blk try std.fs.path.join(a, &.{ executable, "..", "libexec", "mylang", "components" });
        };
        result.artifact = try launch.artifact(a, io, result.directory.?, "cache-plan");
        hash.update(&result.artifact.?.digest);
    }
    hash.final(&result.identity);
    return result;
}
fn ioFailure(io: std.Io, stage: []const u8, err: anyerror) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "mylang: cache-plan {s} failed: {s}\n", .{ stage, @errorName(err) }) catch return error.ComponentIo;
    std.Io.File.stderr().writeStreamingAll(io, message) catch return error.ComponentIo;
    return error.ComponentIo;
}

fn discard(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: cache-plan cleanup failed: {t}\n", .{err}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
    };
}

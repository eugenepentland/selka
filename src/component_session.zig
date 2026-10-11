//! Invocation-owned authenticated bytes; every reuse checks current deployment contents.
const std = @import("std");
const launch = @import("component_launch.zig");
const Entry = struct { component: []const u8, snapshot: launch.Snapshot, executable: ?struct { file: std.Io.File, io: std.Io } = null };
/// Caller-owned verified path with either borrowed retained bytes or owned fallback bytes.
pub const View = struct {
    verified: launch.Verified,
    contents: []const u8,
    owned: bool = false,
    /// Release this view while leaving invocation-retained bytes untouched.
    pub fn deinit(self: View, a: std.mem.Allocator) void {
        a.free(self.verified.path);
        if (self.owned) a.free(self.contents);
    }
};
/// Fully authenticate a caller-owned fallback when retaining is unavailable.
pub fn fallback(a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) launch.Error!View {
    const captured = try launch.artifactSnapshot(a, io, directory, component);
    return .{ .verified = captured.verified, .contents = captured.contents, .owned = true };
}
/// Borrowed retained executable or a caller-owned fallback descriptor.
pub const Executable = struct {
    file: std.Io.File,
    owned: bool = true,
    /// Close only caller-owned fallback descriptors.
    pub fn close(self: Executable, io: std.Io) void {
        if (self.owned) self.file.close(io);
    }
};
/// Lazy, bounded retained authority. Calls are serialized by the owning workflow.
pub const Session = struct {
    allocator: std.mem.Allocator,
    entries: [7]?Entry = @splat(null),
    retained: usize = 0,
    budget: usize = 64 << 20,
    /// Release retained bytes after all invocation borrowers finish.
    pub fn deinit(self: *Session) void {
        for (&self.entries) |*slot| if (slot.*) |entry| {
            if (entry.executable) |executable| executable.file.close(executable.io);
            self.allocator.free(entry.component);
            entry.snapshot.deinit(self.allocator);
            slot.* = null;
        };
        self.retained = 0;
    }
    /// Authenticate live contents, returning an allocator-owned path for the caller.
    pub fn artifact(self: *Session, a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) launch.Error!launch.Verified {
        const captured = try self.snapshot(a, io, directory, component);
        if (captured.owned) a.free(captured.contents);
        return captured.verified;
    }
    /// Borrow retained immutable bytes with a caller-owned verified path; fallback uses caller memory.
    pub fn snapshot(self: *Session, a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8) launch.Error!View {
        for (self.entries) |slot| if (slot) |entry| {
            if (std.mem.eql(u8, entry.component, component)) return self.check(a, io, directory, component, entry.snapshot);
        };
        var free_slot: ?usize = null;
        for (self.entries, 0..) |slot, i| if (slot == null) {
            free_slot = i;
            break;
        };
        if (free_slot == null) return fallback(a, io, directory, component);
        const captured = try launch.artifactSnapshot(self.allocator, io, directory, component);
        if (captured.contents.len > @min(self.budget, 64 << 20) -| self.retained) {
            captured.deinit(self.allocator);
            return fallback(a, io, directory, component);
        }
        errdefer captured.deinit(self.allocator);
        const name = try self.allocator.dupe(u8, component);
        errdefer self.allocator.free(name);
        const path = try a.dupe(u8, captured.verified.path);
        self.entries[free_slot.?] = .{ .component = name, .snapshot = captured };
        self.retained += captured.contents.len;
        return .{ .verified = .{ .path = path, .digest = captured.verified.digest }, .contents = captured.contents };
    }
    /// Reuse the sealed descriptor only for immutable bytes retained by this session.
    pub fn seal(self: *Session, io: std.Io, contents: []const u8) launch.SnapshotError!Executable {
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (entry.snapshot.contents.ptr != contents.ptr or entry.snapshot.contents.len != contents.len) continue;
            if (entry.executable == null) entry.executable = .{ .file = try launch.sealedExecutable(io, contents), .io = io };
            return .{ .file = entry.executable.?.file, .owned = false };
        };
        return .{ .file = try launch.sealedExecutable(io, contents) };
    }
    fn check(self: *Session, a: std.mem.Allocator, io: std.Io, directory: []const u8, component: []const u8, captured: launch.Snapshot) launch.Error!View {
        _ = self;
        const live = try launch.manifestDeployment(a, io, directory, component);
        // A different valid generation must still be authenticated before its caller rejects identity.
        if (!std.mem.eql(u8, live.path, captured.verified.path) or !std.mem.eql(u8, &live.digest, &captured.verified.digest)) {
            a.free(live.path);
            return fallback(a, io, directory, component);
        }
        errdefer a.free(live.path);
        try launch.compareFile(io, live.path, captured.contents);
        return .{ .verified = live, .contents = captured.contents };
    }
};

fn fixture(a: std.mem.Allocator, directory: std.Io.Dir, contents: []const u8) !void {
    const digest = @import("component_digest.zig").hash(contents);
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"lexer-pilot\",\"protocol\":1,\"schema\":2,\"artifact\":\"producer\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try directory.writeFile(std.testing.io, .{ .sub_path = "producer", .data = contents });
    try directory.writeFile(std.testing.io, .{ .sub_path = "lexer-pilot.json", .data = manifest });
}

// spec: SELFHOST-ARTIFACT-SESSION-1
test "artifact session checks live tamper truncation extension and valid replacement" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    var session: Session = .{ .allocator = a };
    defer session.deinit();
    try fixture(a, temporary.dir, "first");
    const original = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(original.path);
    const repeated = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(repeated.path);
    try std.testing.expectEqual(@as(usize, 5), session.retained);
    for ([_][]const u8{ "fIrst", "firs", "first!" }) |bad| {
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = bad });
        try std.testing.expectError(error.ComponentDigest, session.artifact(a, std.testing.io, path, "lexer-pilot"));
    }
    try fixture(a, temporary.dir, "other");
    const changed = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(changed.path);
    try std.testing.expect(!std.mem.eql(u8, &original.digest, &changed.digest));
    try std.testing.expectEqual(@as(usize, 5), session.retained);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = "wrong" });
    try std.testing.expectError(error.ComponentDigest, session.artifact(a, std.testing.io, path, "lexer-pilot"));
    try temporary.dir.deleteFile(std.testing.io, "lexer-pilot.json");
    try std.testing.expectError(error.ComponentMissing, session.artifact(a, std.testing.io, path, "lexer-pilot"));
}

// spec-case: SELFHOST-ARTIFACT-SESSION-1
test "artifact session budget fallback authenticates and retains no oversized entry" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    var session: Session = .{ .allocator = a, .budget = 4 };
    defer session.deinit();
    try fixture(a, temporary.dir, "first");
    const verified = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(verified.path);
    try std.testing.expectEqual(@as(usize, 0), session.retained);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "producer", .data = "wrong" });
    try std.testing.expectError(error.ComponentDigest, session.artifact(a, std.testing.io, path, "lexer-pilot"));
}

// spec-case: SELFHOST-ARTIFACT-SESSION-1
test "artifact session reuses sealed descriptors and closes retained state" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    var session: Session = .{ .allocator = a };
    defer session.deinit();
    try fixture(a, temporary.dir, "first");
    const captured = try session.snapshot(a, std.testing.io, path, "lexer-pilot");
    defer a.free(captured.verified.path);
    const first = try session.seal(std.testing.io, captured.contents);
    first.close(std.testing.io);
    const second = try session.seal(std.testing.io, captured.contents);
    try std.testing.expectEqual(first.file.handle, second.file.handle);
    try std.testing.expect(!second.owned);
    var bytes: [5]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 5), try second.file.readPositionalAll(std.testing.io, &bytes, 0));
    try std.testing.expectEqualSlices(u8, "first", &bytes);
    session.deinit();
    const closed = std.os.linux.fcntl(second.file.handle, std.os.linux.F.GETFD, 0);
    try std.testing.expectEqual(std.os.linux.E.BADF, std.os.linux.errno(closed));
    try std.testing.expectEqual(@as(usize, 0), session.retained);
}

fn allocationRoundTrip(a: std.mem.Allocator, path: []const u8) !void {
    var session: Session = .{ .allocator = a };
    defer session.deinit();
    const first = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(first.path);
    const second = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(second.path);
    try std.testing.expectEqualSlices(u8, &first.digest, &second.digest);
}

// spec-case: SELFHOST-ARTIFACT-SESSION-1
test "artifact session allocation failures release retained authentication state" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    try fixture(a, temporary.dir, "first");
    try std.testing.checkAllAllocationFailures(a, allocationRoundTrip, .{path});
}

// spec-case: SELFHOST-ARTIFACT-SESSION-1
test "artifact session aggregate budget keeps existing bytes and owns fallback views" {
    const a = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    var session: Session = .{ .allocator = a, .budget = 4 };
    defer session.deinit();
    try fixture(a, temporary.dir, "one");
    const first = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(first.path);
    const digest = @import("component_digest.zig").hash("bb");
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"test-index\",\"protocol\":1,\"schema\":1,\"artifact\":\"second\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "second", .data = "bb" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "test-index.json", .data = manifest });
    const fallback_view = try session.snapshot(a, std.testing.io, path, "test-index");
    defer fallback_view.deinit(a);
    try std.testing.expect(fallback_view.owned);
    try std.testing.expectEqual(@as(usize, 3), session.retained);
    const fallback_file = try session.seal(std.testing.io, fallback_view.contents);
    defer fallback_file.close(std.testing.io);
    try std.testing.expect(fallback_file.owned);
    const retained = try session.artifact(a, std.testing.io, path, "lexer-pilot");
    defer a.free(retained.path);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "second", .data = "cc" });
    try std.testing.expectError(error.ComponentDigest, session.artifact(a, std.testing.io, path, "test-index"));
}

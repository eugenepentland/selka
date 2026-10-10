//! Disposable completed-prefix evidence for explicitly indexed property campaigns.
//! A short per-campaign lock protects compare-and-publish; partial files never count.
const std = @import("std");
const contract = @import("property_campaign_contract.zig");
const codec = @import("mylang").persist_codec;

/// Exact complete target-closure and campaign-settings identity.
pub const Digest = [32]u8;
/// Cache I/O loses progress reuse; allocation failure remains explicit.
pub const Error = std.mem.Allocator.Error;
const magic = "core-property-prefix-v1\n";
const prefix_max_bytes = 256 << 10;
const max_clauses = 256;
const max_message = 4096;

/// Borrowed cache location and allocator; loaded progress belongs to the borrowed arena.
pub const Store = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    root: []const u8,

    /// Fixed lookup path; no directory inventory or latest-generation search is needed.
    pub fn artifactPath(self: Store, a: std.mem.Allocator, campaign: Digest) Error![]const u8 {
        return std.fmt.allocPrint(a, "{s}/tests/property-prefix-v1/{s}.bin", .{ self.root, std.fmt.bytesToHex(campaign, .lower) });
    }

    /// Restore only coherent completed ordinals that fit the requested passing budget.
    pub fn load(self: Store, campaign: Digest, budget: u64) Error!?contract.Progress {
        var scratch = std.heap.ArenaAllocator.init(self.arena);
        defer scratch.deinit();
        const a = scratch.allocator();
        const path = try self.artifactPath(a, campaign);
        const progress = try self.read(a, path, campaign) orelse return null;
        if (progress.passed > budget) return null;
        const discard_limit = std.math.mul(u64, budget, 10) catch std.math.maxInt(u64);
        if (progress.discarded > discard_limit) return null;
        const restored = try clone(self.arena, progress);
        return restored;
    }

    /// Publish a strictly extended prefix only if the exact previously loaded state remains.
    /// The caller must revalidate source/tool inputs immediately before every commit.
    pub fn commit(self: Store, campaign: Digest, expected: ?contract.Progress, next: contract.Progress) Error!bool {
        if (!valid(next)) return false;
        if (!extends(expected, next)) return false;
        var scratch = std.heap.ArenaAllocator.init(self.arena);
        defer scratch.deinit();
        const a = scratch.allocator();
        const path = try self.artifactPath(a, campaign);
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(self.io, std.fs.path.dirname(path).?) catch return false;
        const lock_path = try std.fmt.allocPrint(a, "{s}.lock", .{path});
        const lock = cwd.createFile(self.io, lock_path, .{ .truncate = false }) catch return false;
        defer lock.close(self.io);
        lock.lock(self.io, .exclusive) catch return false;
        const current = try self.read(a, path, campaign);
        if (!sameOptional(expected, current)) return false;
        const bytes = try encode(a, campaign, next);
        return self.publish(a, path, bytes);
    }

    fn read(self: Store, a: std.mem.Allocator, path: []const u8, campaign: Digest) Error!?contract.Progress {
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, a, .limited(prefix_max_bytes)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        return decode(a, campaign, bytes) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
    }

    fn publish(self: Store, a: std.mem.Allocator, path: []const u8, bytes: []const u8) Error!bool {
        const temporary = try std.fmt.allocPrint(a, "{s}.partial", .{path});
        defer removePartial(self.io, temporary);
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = temporary, .data = bytes }) catch return false;
        std.Io.Dir.cwd().rename(temporary, std.Io.Dir.cwd(), path, self.io) catch return false;
        return true;
    }
};

/// Free the clauses/messages returned by load when using a general allocator.
pub fn deinitProgress(a: std.mem.Allocator, progress: contract.Progress) void {
    for (progress.clauses) |clause| a.free(clause.message);
    a.free(progress.clauses);
}

fn clone(a: std.mem.Allocator, progress: contract.Progress) Error!contract.Progress {
    const clauses = try a.alloc(contract.Clause, progress.clauses.len);
    errdefer a.free(clauses);
    var completed: usize = 0;
    errdefer for (clauses[0..completed]) |clause| a.free(clause.message);
    for (progress.clauses, clauses) |source, *target| {
        target.* = .{ .message = try a.dupe(u8, source.message), .count = source.count };
        completed += 1;
    }
    var result = progress;
    result.clauses = clauses;
    return result;
}

fn valid(progress: contract.Progress) bool {
    if (progress.clauses.len > max_clauses) return false;
    if (progress.next_ordinal > contract.maximum_ordinal) return false;
    const total = std.math.add(u64, progress.passed, progress.discarded) catch return false;
    if (total != progress.next_ordinal) return false;
    var discarded: u64 = 0;
    var bytes: usize = 128;
    for (progress.clauses, 0..) |clause, i| {
        if (clause.message.len > max_message or clause.count == 0) return false;
        discarded = std.math.add(u64, discarded, clause.count) catch return false;
        bytes += clause.message.len + 12;
        if (bytes > prefix_max_bytes) return false;
        for (progress.clauses[0..i]) |prior| if (std.mem.eql(u8, clause.message, prior.message)) return false;
    }
    return discarded == progress.discarded;
}

fn extends(expected: ?contract.Progress, next: contract.Progress) bool {
    const previous = expected orelse return next.next_ordinal != 0;
    if (!valid(previous)) return false;
    if (next.next_ordinal <= previous.next_ordinal) return false;
    if (next.passed < previous.passed or next.discarded < previous.discarded) return false;
    if (next.clauses.len < previous.clauses.len) return false;
    for (previous.clauses, next.clauses[0..previous.clauses.len]) |before, after| {
        if (!std.mem.eql(u8, before.message, after.message)) return false;
        if (after.count < before.count) return false;
    }
    return true;
}

fn sameOptional(a: ?contract.Progress, b: ?contract.Progress) bool {
    if (a == null or b == null) return a == null and b == null;
    const left = a.?;
    const right = b.?;
    if (left.next_ordinal != right.next_ordinal or left.passed != right.passed) return false;
    if (left.discarded != right.discarded or left.clauses.len != right.clauses.len) return false;
    for (left.clauses, right.clauses) |l, r| {
        if (l.count != r.count or !std.mem.eql(u8, l.message, r.message)) return false;
    }
    return true;
}

fn encode(a: std.mem.Allocator, campaign: Digest, progress: contract.Progress) Error![]const u8 {
    var payload = codec.Writer.init(a);
    try payload.raw(&campaign);
    try payload.integer(progress.next_ordinal);
    try payload.integer(progress.passed);
    try payload.integer(progress.discarded);
    try payload.integer(@as(u32, @intCast(progress.clauses.len)));
    for (progress.clauses) |clause| {
        try payload.integer(@as(u32, @intCast(clause.message.len)));
        try payload.raw(clause.message);
        try payload.integer(clause.count);
    }
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload.bytes.items, &digest, .{});
    var framed = codec.Writer.init(a);
    try framed.raw(magic);
    try framed.raw(&digest);
    try framed.raw(payload.bytes.items);
    return framed.bytes.items;
}

fn decode(a: std.mem.Allocator, campaign: Digest, bytes: []const u8) codec.DecodeError!contract.Progress {
    if (bytes.len > prefix_max_bytes or bytes.len < magic.len + 32) return error.InvalidEncoding;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.InvalidEncoding;
    const payload = bytes[magic.len + 32 ..];
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &digest, .{});
    if (!std.mem.eql(u8, bytes[magic.len..][0..32], &digest)) return error.InvalidEncoding;
    var reader = codec.Reader.init(a, payload);
    if (!std.mem.eql(u8, try reader.slice(32), &campaign)) return error.InvalidEncoding;
    var progress: contract.Progress = .{
        .next_ordinal = try reader.integer(u64),
        .passed = try reader.integer(u64),
        .discarded = try reader.integer(u64),
        .clauses = &.{},
    };
    const count = try reader.integer(u32);
    if (count > max_clauses) return error.TooLarge;
    const clauses = try a.alloc(contract.Clause, count);
    for (clauses) |*clause| {
        const length = try reader.integer(u32);
        if (length > max_message) return error.TooLarge;
        clause.* = .{ .message = try reader.slice(length), .count = try reader.integer(u64) };
    }
    progress.clauses = clauses;
    if (!reader.done() or !valid(progress)) return error.InvalidEncoding;
    return progress;
}

fn removePartial(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

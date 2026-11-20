//! Checking one recorded read against the world now (spec §5, step 3), and saying what changed (spec §11, `explain`).
//!
//! A file read is unchanged when its stat tuple is the recorded one (a tuple of none is never trusted), else when its
//! bytes hash to the recorded digest. An existence test, a listing, a variable and a tool are unchanged when they give
//! the recorded answer. A placement variable is never compared. A query read is the engine's to check, because it
//! recurses: this file answers only for the reads that end at the world.
const std = @import("std");
const digest_rules = @import("digest.zig");
const record = @import("record.zig");
const context = @import("context.zig");
const world_rules = @import("world.zig");
const Digest = digest_rules.Digest;
const Host = context.Host;
const Error = context.Error;
const Read = record.Read;

/// What a read saw and what it sees now, as text.
pub const Difference = struct { then: []const u8, now: []const u8 };

/// How a recorded read compares with the world now.
pub const Outcome = union(enum) {
    /// As it was seen.
    same,
    /// As it was seen, found by hashing a file whose stat tuple had moved or was never trusted; the tuple seen around that
    /// hash is trustworthy now, so the record may be rewritten with it and the file need not be hashed again.
    refreshed: world_rules.Stat,
    /// Not as it was seen.
    changed,
};

/// Compare `read` with the world now. `scratch` holds the bytes of a file that has to be hashed. A query read is not
/// answered here (`error.Failed` would be a bug in the caller).
pub fn check(host: Host, scratch: std.mem.Allocator, read: Read) Error!Outcome {
    switch (read) {
        .file => |file| return checkFile(host, scratch, file),
        .exists => |probe| return outcome((host.stat(probe.path) != null) == probe.present),
        .listing => |listing| {
            const current = try host.listing(listing.path, listing.filter);
            if (!listing.opened) return outcome(current == null);
            return outcome(current != null and std.mem.eql(u8, &current.?, &listing.digest));
        },
        .variable => |variable| {
            if (host.world.placement(variable.name)) return .same;
            const current = host.world.variable(variable.name);
            if (!variable.set) return outcome(current == null);
            return outcome(current != null and std.mem.eql(u8, current.?, variable.value));
        },
        .tool => |tool| return outcome(std.mem.eql(u8, &(try host.tool(tool.path)), &tool.identity)),
        .query, .part => return error.Failed,
    }
}

fn outcome(holds: bool) Outcome {
    return if (holds) .same else .changed;
}

/// Whether `read` is as it was seen.
pub fn unchanged(host: Host, scratch: std.mem.Allocator, read: Read) Error!bool {
    return (try check(host, scratch, read)) != .changed;
}

fn checkFile(host: Host, scratch: std.mem.Allocator, file: record.FileRead) Error!Outcome {
    const current = host.stat(file.path);
    if (!file.present) return outcome(current == null);
    const found = current orelse return .changed;
    if (!file.stat.isNone() and file.stat.eql(found)) return .same;
    const before = host.world.stat(file.path);
    const bytes = (try host.world.read(scratch, file.path, host.assumptions.file_limit)) orelse return .changed;
    defer scratch.free(bytes);
    if (!std.mem.eql(u8, &digest_rules.hash(bytes), &file.digest)) return .changed;
    const after = host.world.stat(file.path);
    const steady = before != null and after != null and before.?.eql(after.?);
    const aged = steady and after.?.changed() <= host.world.now() - host.assumptions.racy_window_ns;
    return if (aged) .{ .refreshed = after.? } else .same;
}

/// What changed in `read`, or null when it is unchanged. Allocates the text in `arena`.
pub fn difference(host: Host, arena: std.mem.Allocator, read: Read) Error!?Difference {
    if (read != .query and read != .part and try unchanged(host, arena, read)) return null;
    switch (read) {
        .file => |file| return .{ .then = try describeFile(arena, file.present, file.digest), .now = try nowFile(host, arena, file.path) },
        .exists => |probe| return .{ .then = presence(probe.present), .now = presence(!probe.present) },
        .listing => |listing| {
            const current = try host.listing(listing.path, listing.filter);
            return .{
                .then = if (listing.opened) try shortDigest(arena, listing.digest) else "directory did not open",
                .now = if (current) |found| try shortDigest(arena, found) else "directory does not open",
            };
        },
        .variable => |variable| {
            const current = host.world.variable(variable.name);
            return .{
                .then = if (variable.set) try std.fmt.allocPrint(arena, "\"{s}\"", .{variable.value}) else "unset",
                .now = if (current) |value| try std.fmt.allocPrint(arena, "\"{s}\"", .{value}) else "unset",
            };
        },
        .tool => |tool| return .{ .then = try shortDigest(arena, tool.identity), .now = try shortDigest(arena, try host.tool(tool.path)) },
        .query, .part => return null,
    }
}

fn presence(present: bool) []const u8 {
    return if (present) "present" else "absent";
}

fn describeFile(arena: std.mem.Allocator, present: bool, digest: Digest) std.mem.Allocator.Error![]const u8 {
    if (!present) return "absent";
    return shortDigest(arena, digest);
}

fn nowFile(host: Host, arena: std.mem.Allocator, path: []const u8) Error![]const u8 {
    const bytes = (try host.world.read(arena, path, host.assumptions.file_limit)) orelse return "absent";
    return shortDigest(arena, digest_rules.hash(bytes));
}

/// The first eight hexadecimal digits of a digest, which are enough to tell two apart in a report.
pub fn shortDigest(arena: std.mem.Allocator, digest: Digest) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, "{s}", .{digest_rules.hex(digest)[0..8]});
}

/// The text a report gives for a read: its kind and subject.
pub fn describe(arena: std.mem.Allocator, read: Read) std.mem.Allocator.Error![]const u8 {
    return switch (read) {
        .file => |file| std.fmt.allocPrint(arena, "file {s}", .{file.path}),
        .exists => |probe| std.fmt.allocPrint(arena, "exists {s}", .{probe.path}),
        .listing => |listing| std.fmt.allocPrint(arena, "listing {s} (filter {d})", .{ listing.path, listing.filter }),
        .variable => |variable| std.fmt.allocPrint(arena, "variable {s}", .{variable.name}),
        .tool => |tool| std.fmt.allocPrint(arena, "tool {s}", .{tool.path}),
        .query => |query| std.fmt.allocPrint(arena, "query {s} {s}", .{ query.kind, digest_rules.hex(query.key)[0..8] }),
        .part => |part| std.fmt.allocPrint(arena, "part {s} {s} ({d} named)", .{ part.kind, digest_rules.hex(part.key)[0..8], part.parts.len }),
    };
}

/// Whether two reads saw the same thing: the same subject and the same answer, ignoring the stat tuple, which only
/// speeds up checking.
pub fn sameSight(left: Read, right: Read) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    switch (left) {
        .file => |a| {
            const b = right.file;
            return std.mem.eql(u8, a.path, b.path) and a.present == b.present and std.mem.eql(u8, &a.digest, &b.digest);
        },
        .exists => |a| return std.mem.eql(u8, a.path, right.exists.path) and a.present == right.exists.present,
        .listing => |a| {
            const b = right.listing;
            return std.mem.eql(u8, a.path, b.path) and a.filter == b.filter and a.opened == b.opened and std.mem.eql(u8, &a.digest, &b.digest);
        },
        .variable => |a| {
            const b = right.variable;
            if (a.placement and b.placement) return std.mem.eql(u8, a.name, b.name);
            return std.mem.eql(u8, a.name, b.name) and a.set == b.set and std.mem.eql(u8, a.value, b.value);
        },
        .tool => |a| return std.mem.eql(u8, a.path, right.tool.path) and std.mem.eql(u8, &a.identity, &right.tool.identity),
        .query => |a| {
            const b = right.query;
            return std.mem.eql(u8, a.kind, b.kind) and std.mem.eql(u8, &a.key, &b.key) and std.mem.eql(u8, &a.result, &b.result);
        },
        .part => |a| {
            const b = right.part;
            if (!std.mem.eql(u8, a.kind, b.kind) or !std.mem.eql(u8, &a.key, &b.key)) return false;
            return samePartSights(a.parts, b.parts);
        },
    }
}

/// Whether two lists of what a projection read saw name the same parts with the same answers.
fn samePartSights(left: []const record.PartSight, right: []const record.PartSight) bool {
    if (left.len != right.len) return false;
    for (left, right) |was, is| {
        if (!std.mem.eql(u8, was.name, is.name) or was.present != is.present) return false;
        if (!std.mem.eql(u8, &was.digest, &is.digest)) return false;
    }
    return true;
}

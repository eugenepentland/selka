//! Why a record would not be served (spec §11, `selka engine explain`): the first read that changed, what it saw and
//! what it sees now, and the chain of queries from the one asked about down to the one whose read changed. Nothing is
//! computed and nothing is written; a dependency that would itself be recomputed is reported as that.
const std = @import("std");
const engine_rules = @import("engine.zig");
const record_rules = @import("record.zig");
const digest_rules = @import("digest.zig");
const validate = @import("validate.zig");
const context = @import("context.zig");
const Digest = digest_rules.Digest;

/// The deepest chain of dependencies explained.
const depth_limit = 64;

/// A read that changed.
pub const Change = struct {
    /// The position of the read in its record.
    index: usize,
    /// The queries from the one asked about to the one whose read changed, as `kind(argument)` joined by ` -> `.
    trail: []const u8,
    /// The read, as text.
    read: []const u8,
    /// What it saw.
    then: []const u8,
    /// What it sees now.
    now: []const u8,
};

/// A record whose reads all hold: its result digest and the table of parts it publishes.
pub const Served = struct { result: Digest, parts: []const record_rules.Part };

/// What `explain` found.
pub const Verdict = union(enum) {
    /// Every read is as it was seen.
    served: Served,
    /// There is no record under this code identity.
    no_record,
    /// The file is torn, corrupt or of another format.
    unreadable,
    /// The first change.
    changed: Change,
};

/// The verdict for `kind(argument)`, with its text in `a`.
pub fn explain(engine: *engine_rules.Engine, a: std.mem.Allocator, kind: *const context.Kind, argument: []const u8) engine_rules.Error!Verdict {
    const index = engine.registry.indexOf(kind) orelse return error.UnknownKind;
    const key = digest_rules.key(kind.name, kind.identity, argument);
    return explainKey(engine, a, index, key, "", 0);
}

fn explainKey(engine: *engine_rules.Engine, a: std.mem.Allocator, index: usize, key: Digest, above: []const u8, depth: usize) engine_rules.Error!Verdict {
    const entry = engine.registry.entries[index];
    const path = try engine.store.recordPath(a, entry.directory, key);
    const bytes = (try engine.store.load(a, path)) orelse engine.packedBytes(key) orelse engine.sharedBytes(index, key, a) orelse return .no_record;
    const found = record_rules.decode(a, bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .unreadable,
    };
    if (!std.mem.eql(u8, &found.key, &key) or !std.mem.eql(u8, found.kind, entry.kind.name)) return .unreadable;
    const shown = found.argument[0..@min(found.argument.len, 40)];
    const trail = if (above.len == 0) try std.fmt.allocPrint(a, "{s}({s})", .{ found.kind, shown }) else try std.fmt.allocPrint(a, "{s} -> {s}({s})", .{ above, found.kind, shown });
    const host = engine.host();
    for (found.reads, 0..) |read, at| {
        if (read != .query and read != .part) {
            const difference = (try validate.difference(host, a, read)) orelse continue;
            return .{ .changed = .{ .index = at, .trail = trail, .read = try validate.describe(a, read), .then = difference.then, .now = difference.now } };
        }
        const dependency = Dependency.of(read);
        const described = try validate.describe(a, read);
        const at_kind = engine.registry.byName(dependency.kind) orelse
            return .{ .changed = .{ .index = at, .trail = trail, .read = described, .then = "a registered kind", .now = "no such kind is registered" } };
        if (depth + 1 >= depth_limit) return .{ .changed = .{ .index = at, .trail = trail, .read = described, .then = "", .now = "chain too deep to explain" } };
        const inner = try explainKey(engine, a, at_kind, dependency.key, trail, depth + 1);
        switch (inner) {
            .changed => return inner,
            .no_record, .unreadable => return .{ .changed = .{ .index = at, .trail = trail, .read = described, .then = try dependency.sawText(a), .now = "no usable record: it would be recomputed" } },
            .served => |now| {
                if (dependency.holds(now)) continue;
                return .{ .changed = .{ .index = at, .trail = trail, .read = described, .then = try dependency.sawText(a), .now = try dependency.seesText(a, now) } };
            },
        }
    }
    return .{ .served = .{ .result = found.result, .parts = found.parts } };
}

/// What a query read or a part read depends on, and how to compare it with the dependency's record now.
const Dependency = struct {
    kind: []const u8,
    key: Digest,
    /// The result digest a query read saw; null for a part read.
    result: ?Digest,
    /// What a part read saw of the parts it named.
    sights: []const record_rules.PartSight,

    fn of(read: record_rules.Read) Dependency {
        return switch (read) {
            .query => |query| .{ .kind = query.kind, .key = query.key, .result = query.result, .sights = &.{} },
            .part => |part| .{ .kind = part.kind, .key = part.key, .result = null, .sights = part.parts },
            else => unreachable,
        };
    }

    /// Whether the dependency's record, as it is now, is what this read saw.
    fn holds(self: Dependency, now: Served) bool {
        if (self.result) |seen| return std.mem.eql(u8, &seen, &now.result);
        return self.firstChangedPart(now) == null;
    }

    /// The first named part whose digest or presence differs from what the read saw.
    fn firstChangedPart(self: Dependency, now: Served) ?record_rules.PartSight {
        for (self.sights) |sight| {
            const current = context.findPart(now.parts, sight.name);
            if (sight.present != (current != null)) return sight;
            if (current) |digest| if (!std.mem.eql(u8, &digest, &sight.digest)) return sight;
        }
        return null;
    }

    fn sawText(self: Dependency, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        if (self.result) |seen| return validate.shortDigest(a, seen);
        return std.fmt.allocPrint(a, "{d} named parts", .{self.sights.len});
    }

    fn seesText(self: Dependency, a: std.mem.Allocator, current: Served) std.mem.Allocator.Error![]const u8 {
        if (self.result != null) return validate.shortDigest(a, current.result);
        const changed = self.firstChangedPart(current) orelse return "unchanged";
        const after: []const u8 = if (context.findPart(current.parts, changed.name)) |digest| try validate.shortDigest(a, digest) else "absent";
        const before: []const u8 = if (changed.present) try validate.shortDigest(a, changed.digest) else "absent";
        return std.fmt.allocPrint(a, "part {s}: {s} then, {s} now", .{ changed.name, before, after });
    }
};

/// Write the verdict as the lines `selka engine explain` prints.
pub fn write(writer: *std.Io.Writer, verdict: Verdict) std.Io.Writer.Error!void {
    switch (verdict) {
        .served => |served| try writer.print("served: every read is as it was seen (result {s})\n", .{digest_rules.hex(served.result)[0..8]}),
        .no_record => try writer.writeAll("no record: this query was not computed under this code identity\n"),
        .unreadable => try writer.writeAll("unreadable: the record is torn, corrupt or of another format; it would be recomputed\n"),
        .changed => |change| try writer.print(
            "would recompute: read #{d} of {s} changed\n  read: {s}\n  saw:  {s}\n  now:  {s}\n",
            .{ change.index, change.trail, change.read, change.then, change.now },
        ),
    }
}

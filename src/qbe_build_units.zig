//! One manifest unit's text, digest and build facts, whether the unit carries
//! its QBE text inline (`il`) or, in a lean manifest, names the text the
//! compiler stored in its fragment store (`il_digest`, `il_facts`, and either
//! the manifest's `store` directory or an older unit's own `il_file`;
//! `QBE-FRAGMENT-REUSE-1`). A lean unit names its metadata — positions,
//! assertion messages, inline frames — the same way (`meta_digest`,
//! `EMIT-META-1`). The driver reads a stored text only when the object it
//! names has to be built, so an unchanged unit costs a digest, not its text.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");

/// A stored unit whose file is missing or no longer matches its digest.
pub const Error = fs.Error || error{InvalidNativeManifest};

const inline_key = "il";
const digest_key = "il_digest";
const file_key = "il_file";
const facts_key = "il_facts";
/// The member naming a lean unit's stored metadata.
pub const meta_key = "meta_digest";

/// Whether a unit carries its text, or a complete stored reference to it.
pub fn wellFormed(unit: std.json.Value) bool {
    if (v.get(unit, inline_key) == .string) return true;
    if (!hexDigest(v.get(unit, digest_key))) return false;
    const meta = v.get(unit, meta_key);
    if (meta != .null and !hexDigest(meta)) return false;
    const path = v.get(unit, file_key);
    return (path == .null or path == .string) and v.get(unit, facts_key) == .string;
}

/// Whether a member is a lowercase hex BLAKE3 digest.
fn hexDigest(named: std.json.Value) bool {
    if (named != .string or named.string.len != 64) return false;
    for (named.string) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

/// The lines of the unit text the driver reads without compiling it: the whole
/// text for an inline unit, the recorded `dbgfile` and `# ` marker lines for a
/// stored one. Both answer `usesFrameMap` and the literal scan identically.
pub fn facts(unit: std.json.Value) []const u8 {
    const il = v.get(unit, inline_key);
    if (il == .string) return il.string;
    return v.text(v.get(unit, facts_key));
}

/// The lowercase hex BLAKE3 digest of the unit text, which names its object;
/// the compiler's fragment store names a stored text by the same digest.
pub fn digest(allocator: std.mem.Allocator, unit: std.json.Value) error{OutOfMemory}![]const u8 {
    const il = v.get(unit, inline_key);
    if (il != .string) return v.text(v.get(unit, digest_key));
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(il.string, &hash, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(hash, .lower));
}

/// Where a stored unit's text lives: its own `il_file`, or the manifest's
/// `store` directory joined with its digest.
pub fn file(allocator: std.mem.Allocator, store: []const u8, unit: std.json.Value) error{OutOfMemory}![]const u8 {
    const named = v.get(unit, file_key);
    if (named == .string) return named.string;
    return std.fs.path.join(allocator, &.{ store, v.text(v.get(unit, digest_key)) });
}

/// The unit text: inline, or read from the fragment store and checked against
/// its digest, so a damaged or replaced file can never build a wrong object.
/// `store` is the manifest's `store` directory.
pub fn text(context: fs.Context, store: []const u8, unit: std.json.Value) Error![]const u8 {
    const il = v.get(unit, inline_key);
    if (il == .string) return il.string;
    const path = try file(context.allocator, store, unit);
    return verified(context, path, v.text(v.get(unit, digest_key))) orelse return missing(context, unit, path);
}

/// The bytes of `path` when they hash to `expected`, else null.
fn verified(context: fs.Context, path: []const u8, expected: []const u8) ?[]const u8 {
    const bytes = context.read(path) catch return null;
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &hash, .{});
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(hash, .lower), expected)) return null;
    return bytes;
}

/// EMIT-META-1: the unit the build's function tables read — its symbol, name,
/// positions, assertion messages and inline frames. A unit that carries them
/// is itself; a lean unit's are its stored metadata record, read from `store`,
/// checked against `meta_digest` and given the unit's symbol and marker lines
/// (which the literal and frame-map scans of the same C unit read).
pub fn tables(context: fs.Context, store: []const u8, unit: std.json.Value) Error!std.json.Value {
    const named = v.get(unit, meta_key);
    if (named != .string) return unit;
    var record = try storedRecord(context, store, unit, named.string);
    for ([_][]const u8{ "symbol", facts_key, digest_key }) |member| try record.object.put(context.allocator, member, v.get(unit, member));
    return record;
}

/// A lean unit's metadata record: the copy the emission that computed it
/// carries inline (`meta`), or the stored one its digest names.
fn storedRecord(context: fs.Context, store: []const u8, unit: std.json.Value, digest_text: []const u8) Error!std.json.Value {
    const carried = v.get(unit, "meta");
    if (carried == .object) return .{ .object = try carried.object.clone(context.allocator) };
    const path = try std.fs.path.join(context.allocator, &.{ store, digest_text });
    const bytes = verified(context, path, digest_text) orelse return missing(context, unit, path);
    const record = std.json.parseFromSliceLeaky(std.json.Value, context.allocator, bytes, .{}) catch return missing(context, unit, path);
    if (record != .object) return missing(context, unit, path);
    return record;
}
/// One instruction's source position.
pub const Position = struct { path: []const u8, line: u64, column: u64 };

/// A unit's per-instruction positions and assertion messages, in pc order,
/// from either spelling (`BUILD-POSITIONS-1`): the `locations` and `messages`
/// arrays of an inline unit, or a lean unit's `paths`, space-separated
/// `path:line:column` `positions` and `[pc, message]` `assertions`.
pub const Positions = struct {
    unit: std.json.Value,
    /// The compact `positions` text still to read, or null for `locations`.
    compact: ?[]const u8,
    /// How many positions the unit has.
    count: usize,
    pc: usize = 0,
    /// The next entry of `assertions` not yet reached.
    assertion: usize = 0,

    /// Start reading `unit`'s positions.
    pub fn init(unit: std.json.Value) Positions {
        const packed_text = v.get(unit, "positions");
        if (packed_text != .string) return .{ .unit = unit, .compact = null, .count = v.array(v.get(unit, "locations")).len };
        const spelled = packed_text.string;
        const count = if (spelled.len == 0) 0 else std.mem.count(u8, spelled, " ") + 1;
        return .{ .unit = unit, .compact = spelled, .count = count };
    }

    /// The next instruction's position, or null after the last one. A
    /// malformed compact entry reads as an unknown position rather than
    /// shortening the table, so the table always has `count` entries.
    pub fn next(self: *Positions) ?Position {
        if (self.pc >= self.count) return null;
        defer self.pc += 1;
        const rest = self.compact orelse {
            const location = v.array(v.get(self.unit, "locations"))[self.pc];
            return .{ .path = v.text(v.get(location, "path")), .line = v.number(v.get(location, "line")), .column = v.number(v.get(location, "column")) };
        };
        const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
        self.compact = if (end < rest.len) rest[end + 1 ..] else rest[end..];
        var fields = std.mem.splitScalar(u8, rest[0..end], ':');
        const path = number(fields.next());
        const line = number(fields.next());
        const column = number(fields.next());
        const paths = v.array(v.get(self.unit, "paths"));
        return .{ .path = if (path < paths.len) v.text(paths[@intCast(path)]) else "", .line = line, .column = column };
    }

    /// The assertion message of instruction `pc`, or "" when it has none.
    /// Messages are asked for in increasing pc order.
    pub fn message(self: *Positions, pc: usize) []const u8 {
        if (v.get(self.unit, "positions") != .string) {
            const messages = v.array(v.get(self.unit, "messages"));
            return if (pc < messages.len) v.text(messages[pc]) else "";
        }
        const assertions = v.array(v.get(self.unit, "assertions"));
        while (self.assertion < assertions.len) : (self.assertion += 1) {
            const pair = v.array(assertions[self.assertion]);
            if (pair.len != 2) continue;
            const at = v.number(pair[0]);
            if (at > pc) return "";
            if (at == pc) return v.text(pair[1]);
        }
        return "";
    }
};

/// A decimal field of a compact position, or zero when it is absent or malformed.
fn number(field: ?[]const u8) u64 {
    return std.fmt.parseUnsigned(u64, field orelse return 0, 10) catch 0;
}

/// Name the unit whose stored text is gone, then refuse the manifest.
fn missing(context: fs.Context, unit: std.json.Value, path: []const u8) Error {
    const message = std.fmt.allocPrint(
        context.allocator,
        "mylang: the stored QBE text of `{s}` is missing or damaged ({s}); rebuild with --no-cache\n",
        .{ v.text(v.get(unit, "name")), path },
    ) catch return error.OutOfMemory;
    std.Io.File.stderr().writeStreamingAll(context.io, message) catch return error.InvalidNativeManifest;
    return error.InvalidNativeManifest;
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "an inline and a stored unit with the same text share one digest and one fact set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const il = "dbgfile \"myl_f_x\"\nexport function $myl_f_x() {\n@start\n ret\n}\n";
    const inline_unit = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"name\":\"m::x\",\"il\":\"dbgfile \\\"myl_f_x\\\"\\nexport function $myl_f_x() {\\n@start\\n ret\\n}\\n\"}", .{});
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(il, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    const stored_text = try std.fmt.allocPrint(a, "{{\"name\":\"m::x\",\"il_digest\":\"{s}\",\"il_file\":\"/nonexistent/unit\",\"il_facts\":\"dbgfile \\\"myl_f_x\\\"\\n\"}}", .{&hex});
    const stored = try std.json.parseFromSliceLeaky(std.json.Value, a, stored_text, .{});
    try std.testing.expect(wellFormed(inline_unit));
    try std.testing.expect(wellFormed(stored));
    try std.testing.expectEqualStrings(try digest(a, inline_unit), try digest(a, stored));
    try std.testing.expect(std.mem.startsWith(u8, facts(stored), "dbgfile "));
    // A truncated digest is not a stored reference.
    const short = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"il_digest\":\"ab\",\"il_file\":\"f\",\"il_facts\":\"\"}", .{});
    try std.testing.expect(!wellFormed(short));
}

// spec: BUILD-POSITIONS-1
test "compact positions read back the table the spelled-out locations and messages hold" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const spelled = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"locations":[{"path":"a.my","line":3,"column":5},{"path":"b.my","line":9,"column":1},{"path":"a.my","line":4,"column":2}],
        \\ "messages":["","x must be two",""]}
    , .{});
    const compact = try std.json.parseFromSliceLeaky(std.json.Value, a,
        \\{"paths":["a.my","b.my"],"positions":"0:3:5 1:9:1 0:4:2","assertions":[[1,"x must be two"]]}
    , .{});
    var left: Positions = .init(spelled);
    var right: Positions = .init(compact);
    try std.testing.expectEqual(@as(usize, 3), right.count);
    try std.testing.expectEqualDeep(left.next(), right.next());
    try std.testing.expectEqualStrings("", right.message(0));
    try std.testing.expectEqualDeep(left.next(), right.next());
    try std.testing.expectEqualStrings("x must be two", right.message(1));
    try std.testing.expectEqualDeep(left.next(), right.next());
    try std.testing.expectEqualStrings("", right.message(2));
    try std.testing.expectEqual(@as(?Position, null), right.next());
    // An empty table has no entries, and a malformed entry keeps its slot.
    const empty = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"paths\":[],\"positions\":\"\",\"assertions\":[]}", .{});
    try std.testing.expectEqual(@as(usize, 0), Positions.init(empty).count);
    const damaged = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"paths\":[\"a.my\"],\"positions\":\"7:x 0:1:1\",\"assertions\":[]}", .{});
    var read: Positions = .init(damaged);
    try std.testing.expectEqualDeep(@as(?Position, .{ .path = "", .line = 0, .column = 0 }), read.next());
    try std.testing.expectEqualDeep(@as(?Position, .{ .path = "a.my", .line = 1, .column = 1 }), read.next());
}

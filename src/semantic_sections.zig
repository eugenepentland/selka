//! The stored form of a check's summaries: one section per module, each decoded only when something asks for it.
//!
//! A table cut this way costs the edit and not the program. A module whose functions, dependency contexts and region digests (its
//! signature) are those of the last check is a section whose bytes are copied as they are, and a reader that wants only what the
//! planner asks every build (the flags of each function, the facts a stood-in body leaves the passes, the records and templates it
//! touched) reads one fixed-width column of the section's hot area and decodes nothing else.
//!
//! Layout of a payload (little endian):
//!   directory: version, section count, function count, the length and checksum of the shared block, then per section: name, function
//!              count, signature, hot and cold lengths and their checksums; a checksum of the directory. Then every section's hot area,
//!              then every section's cold area, then the shared block.
//!   hot area:  two u32 (records the section touched, bytes of rows), flags (u16 per function), row offsets (u32 per function and one
//!              more), the ids of the records the section's functions touched, and one row per function: facts, touched records (ids),
//!              notes, guard, references.
//!   cold area: a u32 (bytes of rows), row offsets, and one row per function: key, dependency context, region (length, digest, names),
//!              callee keys and, for a function whose `holds.values` flag is set, the keys of the functions it names as values.
//!   shared:    the string pool (names, owners, callee and value keys, the text of notes, keys of references) and the record list (name, shape
//!              digest) every section's ids point into. Ids never move while the table is rewritten: a section stored again as it was keeps
//!              meaning what it meant, because the pool and the list carry over from the table before with new entries only appended.
//!              When the pool has grown to more than twice what it held when it was last built, the table is written afresh.
//! A callee is named by key, so a section stays valid when other modules gain or lose functions.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const typed = @import("typed.zig");
const owned = @import("semantic_entry.zig");
const semantic_key = @import("semantic_key.zig");
const types = @import("semantic_summary_types.zig");

const Summary = types.Summary;
const Note = types.Note;
const Keep = types.Keep;
const FixEdit = types.FixEdit;
const Fact = types.Fact;
const Refs = types.Refs;
const Template = types.Template;
const Table = types.Table;
const OutSection = types.OutSection;
const SizeHint = types.SizeHint;

/// Payload version; bump for any layout or meaning change so old payloads miss.
pub const format_version = "check-summaries-v29";

/// The name of the section that holds the functions no module could be told for, which no module answer covers.
pub const ungrouped = "\x00ungrouped";

/// What the planner asks of a function before anything else: one bit each, stored in a column of the hot area.
pub const Flags = packed struct(u16) {
    /// The facts of the function that are flags.
    facts: packed struct(u4) { mutates_unknown: bool = false, return_unknown: bool = false, writes: bool = false, external: bool = false } = .{},
    /// `Summary.stubbable`.
    stubbable: bool = false,
    /// `Summary.notes.complete`.
    complete: bool = false,
    /// Which optional parts the function's rows hold: `Summary.notes.guard`; `Summary.uses.refs`; and `Summary.uses.values`, which end the cold
    /// row and which the planner reads only for functions that have some.
    holds: packed struct(u4) { guard: bool = false, refs: bool = false, values: bool = false, keeps: bool = false } = .{},
    /// Which notes the function holds.
    notes: packed struct(u2) { body: bool = false, pass: bool = false } = .{},
    padding: u4 = 0,

    /// The flags a summary is stored under.
    pub fn of(entry: Summary) Flags {
        return .{
            .facts = .{
                .mutates_unknown = entry.fact.mutates_unknown,
                .return_unknown = entry.fact.return_origin.unknown,
                .writes = entry.fact.inferred.writes,
                .external = entry.fact.inferred.external,
            },
            .stubbable = entry.stubbable,
            .complete = entry.notes.complete,
            .holds = .{ .guard = entry.notes.guard != null, .refs = entry.uses.refs != null, .values = entry.uses.values.len != 0, .keeps = entry.notes.keeps.len != 0 },
            .notes = .{ .body = entry.notes.body.len != 0, .pass = entry.notes.pass.len != 0 },
        };
    }

    fn bits(self: Flags) u16 {
        return @bitCast(self);
    }

    fn fromBits(value: u16) ?Flags {
        const flags: Flags = @bitCast(value);
        return if (flags.padding != 0) null else flags;
    }
};

/// The module a stable function key names (`fn\x1f<module>\x1f<owner>\x1f<name>`), or "" for a key of another shape.
pub fn moduleOfKey(key: []const u8) []const u8 {
    const first = std.mem.indexOfScalar(u8, key, 0x1f) orelse return "";
    const rest = key[first + 1 ..];
    return rest[0 .. std.mem.indexOfScalar(u8, rest, 0x1f) orelse return ""];
}

// ---------------------------------------------------------------------------------------------------------------------------------
// Varints and pools (shared by the encoder and the decoder)

fn putVar(writer: *codec.Writer, value: u64) std.mem.Allocator.Error!void {
    var rest = value;
    while (rest >= 0x80) : (rest >>= 7) try writer.raw(&.{@as(u8, @truncate(rest)) | 0x80});
    try writer.raw(&.{@as(u8, @truncate(rest))});
}

/// A varint at `bytes[at.*]`, advancing `at`; anything that does not fit a payload this size is corruption.
fn getVar(bytes: []const u8, at: *usize) codec.DecodeError!usize {
    var out: u64 = 0;
    var shift: u6 = 0;
    while (true) {
        if (at.* >= bytes.len) return error.Truncated;
        const byte = bytes[at.*];
        at.* += 1;
        out |= @as(u64, byte & 0x7f) << shift;
        if (byte & 0x80 == 0) break;
        if (shift >= 49) return error.InvalidEncoding;
        shift += 7;
    }
    return std.math.cast(usize, out) orelse error.InvalidEncoding;
}

/// A count of items that each take at least one byte, so it cannot exceed what is left.
fn getCount(bytes: []const u8, at: *usize) codec.DecodeError!usize {
    const count = try getVar(bytes, at);
    if (count > bytes.len - at.*) return error.InvalidEncoding;
    return count;
}

fn getBytes(bytes: []const u8, at: *usize, count: usize) codec.DecodeError![]const u8 {
    if (count > bytes.len - at.*) return error.Truncated;
    const out = bytes[at.*..][0..count];
    at.* += count;
    return out;
}

fn getDigest(bytes: []const u8, at: *usize) codec.DecodeError![32]u8 {
    return (try getBytes(bytes, at, 32))[0..32].*;
}

fn getText(bytes: []const u8, at: *usize) codec.DecodeError![]const u8 {
    return getBytes(bytes, at, try getVar(bytes, at));
}

fn putText(writer: *codec.Writer, text: []const u8) std.mem.Allocator.Error!void {
    try putVar(writer, text.len);
    try writer.raw(text);
}

fn putU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) std.mem.Allocator.Error!void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, @intCast(value), .little);
    try list.appendSlice(allocator, &bytes);
}

fn u32At(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

/// Strings a section repeats, written once and referred to by index.
const Pool = struct {
    ids: std.StringHashMapUnmanaged(u32) = .empty,
    list: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *Pool, allocator: std.mem.Allocator) void {
        self.ids.deinit(allocator);
        self.list.deinit(allocator);
    }

    fn id(self: *Pool, allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!u32 {
        const entry = try self.ids.getOrPut(allocator, text);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(self.list.items.len);
            try self.list.append(allocator, text);
        }
        return entry.value_ptr.*;
    }
};

// ---------------------------------------------------------------------------------------------------------------------------------
// Encoding

const Rows = struct {
    writer: codec.Writer,
    offsets: std.ArrayList(u32) = .empty,

    fn init(allocator: std.mem.Allocator) Rows {
        return .{ .writer = codec.Writer.init(allocator) };
    }

    fn deinit(self: *Rows, allocator: std.mem.Allocator) void {
        self.writer.deinit();
        self.offsets.deinit(allocator);
    }

    fn clear(self: *Rows) void {
        self.writer.bytes.clearRetainingCapacity();
        self.offsets.clearRetainingCapacity();
    }
};

/// The records of the shared block while a table is written: the list, and the id of each (name, shape) pair.
const RecordList = struct {
    ids: std.AutoHashMapUnmanaged([36]u8, u32) = .empty,
    list: std.ArrayList(struct { name: u32, shape: [32]u8 }) = .empty,

    fn deinit(self: *RecordList, allocator: std.mem.Allocator) void {
        self.ids.deinit(allocator);
        self.list.deinit(allocator);
    }

    fn id(self: *RecordList, allocator: std.mem.Allocator, name: u32, shape: [32]u8) std.mem.Allocator.Error!u32 {
        var key: [36]u8 = undefined;
        std.mem.writeInt(u32, key[0..4], name, .little);
        @memcpy(key[4..], &shape);
        const entry = try self.ids.getOrPut(allocator, key);
        if (!entry.found_existing) {
            entry.value_ptr.* = @intCast(self.list.items.len);
            try self.list.append(allocator, .{ .name = name, .shape = shape });
        }
        return entry.value_ptr.*;
    }
};

/// What one section's encoding keeps between sections, so a table of a thousand modules allocates once.
const Scratch = struct {
    allocator: std.mem.Allocator,
    hot: Rows,
    cold: Rows,
    flags: std.ArrayList(u16) = .empty,
    /// The shared block being built: its strings and its records.
    pool: Pool = .{},
    records: RecordList = .{},
    /// Position in the table's record list -> id in the shared list plus one (0: not yet asked).
    record_of: []u32,
    /// The distinct record ids the section being written touches, in the order its functions first name them.
    touched: std.ArrayList(u32) = .empty,
    touched_seen: std.AutoHashMapUnmanaged(u32, void) = .empty,

    fn init(allocator: std.mem.Allocator, records: usize) std.mem.Allocator.Error!Scratch {
        const record_of = try allocator.alloc(u32, records);
        @memset(record_of, 0);
        return .{ .allocator = allocator, .hot = Rows.init(allocator), .cold = Rows.init(allocator), .record_of = record_of };
    }

    fn deinit(self: *Scratch) void {
        self.hot.deinit(self.allocator);
        self.cold.deinit(self.allocator);
        self.flags.deinit(self.allocator);
        self.pool.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.touched.deinit(self.allocator);
        self.touched_seen.deinit(self.allocator);
        self.allocator.free(self.record_of);
    }

    /// Seed the shared block with the one of the table before, so that every id a section stored as it was holds still means what it meant.
    fn seed(self: *Scratch, shared: *const Shared) std.mem.Allocator.Error!void {
        try self.pool.ids.ensureTotalCapacity(self.allocator, @intCast(shared.strings.len));
        for (shared.strings) |text| _ = try self.pool.id(self.allocator, text);
        for (shared.records) |record| _ = try self.records.id(self.allocator, @intCast(self.pool.ids.get(record.name).?), record.shape);
    }

    /// The id in the shared list of the record at `position` of the table's own list; null for a position that names nothing.
    fn recordId(self: *Scratch, table: Table, position: u32) std.mem.Allocator.Error!?u32 {
        if (position >= self.record_of.len) return null;
        if (self.record_of[position] == 0) {
            const name = if (position < table.records.len) table.records[position] else "";
            const shape = if (position < table.record_shapes.len) table.record_shapes[position] else @as([32]u8, @splat(0));
            self.record_of[position] = try self.records.id(self.allocator, try self.pool.id(self.allocator, name), shape) + 1;
        }
        return self.record_of[position] - 1;
    }
};

fn putNotes(writer: *codec.Writer, pool: *Pool, allocator: std.mem.Allocator, notes: []const Note) std.mem.Allocator.Error!void {
    try putVar(writer, notes.len);
    for (notes) |note| {
        try putVar(writer, try pool.id(allocator, note.code));
        try putVar(writer, try pool.id(allocator, note.message));
        try putVar(writer, @backingInt(note.severity));
        try putVar(writer, note.start);
        try putVar(writer, note.end);
        try putVar(writer, if (note.rule) |rule| @as(u64, @backingInt(rule)) + 1 else 0);
        try putVar(writer, note.fix.len);
        for (note.fix) |edit| {
            try putVar(writer, edit.start);
            try putVar(writer, edit.end);
            try putVar(writer, try pool.id(allocator, edit.text));
        }
    }
}

/// The `W_COPY_MOVE` filter's answers of one caller (`Keep`): the callee's key and the parameter from the pool, the two flags
/// and a third that says the caller's `own ` marks follow (their count, then each start).
fn putKeeps(writer: *codec.Writer, pool: *Pool, allocator: std.mem.Allocator, keeps: []const Keep) std.mem.Allocator.Error!void {
    try putVar(writer, keeps.len);
    for (keeps) |keep| {
        try putVar(writer, try pool.id(allocator, keep.callee));
        try putVar(writer, try pool.id(allocator, keep.parameter));
        const marked = keep.marks.len != 0;
        try putVar(writer, @as(u64, @intFromBool(keep.result)) | @as(u64, @intFromBool(keep.keeps)) << 1 | @as(u64, @intFromBool(marked)) << 2);
        if (!marked) continue;
        try putVar(writer, keep.marks.len);
        for (keep.marks) |mark| try putVar(writer, mark);
    }
}

fn readKeeps(allocator: std.mem.Allocator, row: []const u8, at: *usize, pool: []const []const u8) ![]const Keep {
    const keeps = try allocator.alloc(Keep, try getCount(row, at));
    for (keeps) |*keep| {
        keep.callee = try poolText(pool, try getVar(row, at));
        keep.parameter = try poolText(pool, try getVar(row, at));
        const bits = try getVar(row, at);
        if (bits > 7) return error.InvalidEncoding;
        var marks: []u32 = &.{};
        if (bits & 4 != 0) {
            marks = try allocator.alloc(u32, try getCount(row, at));
            for (marks) |*mark| mark.* = std.math.cast(u32, try getVar(row, at)) orelse return error.InvalidEncoding;
        }
        keep.* = .{ .callee = keep.callee, .parameter = keep.parameter, .result = bits & 1 != 0, .keeps = bits & 2 != 0, .marks = marks };
    }
    return keeps;
}

fn putSpan(writer: *codec.Writer, span: source.Span) std.mem.Allocator.Error!void {
    try putVar(writer, span.start);
    try putVar(writer, span.end);
}

fn putType(writer: *codec.Writer, ty: typed.Type) std.mem.Allocator.Error!void {
    try putVar(writer, @backingInt(ty));
}

fn putRefs(writer: *codec.Writer, pool: *Pool, allocator: std.mem.Allocator, refs: Refs) std.mem.Allocator.Error!void {
    try putVar(writer, refs.functions.len);
    for (refs.functions) |reference| {
        try putVar(writer, @backingInt(reference.id));
        try putVar(writer, try pool.id(allocator, reference.key));
        try putVar(writer, if (reference.template) |template| @as(u64, try pool.id(allocator, template)) + 1 else 0);
    }
    try putVar(writer, refs.records.len);
    for (refs.records) |reference| {
        try putVar(writer, reference.index);
        try putVar(writer, try pool.id(allocator, reference.key));
        try writer.raw(&reference.shape);
        try putVar(writer, reference.recipes.len);
        for (reference.recipes) |recipe| switch (recipe) {
            .array => |array| {
                try writer.raw(&.{0});
                try putType(writer, array.element);
                try putVar(writer, array.length);
                try putSpan(writer, array.site);
            },
            .tuple => |elements| {
                try writer.raw(&.{1});
                try putVar(writer, elements.len);
                for (elements) |element| try putType(writer, element);
            },
            .callable => |site| {
                try writer.raw(&.{2});
                try putSpan(writer, site);
            },
            .instance => |instance| {
                try writer.raw(&.{3});
                try putVar(writer, try pool.id(allocator, instance.name));
                try putVar(writer, instance.arguments.len);
                for (instance.arguments) |argument| try putType(writer, argument);
                try putVar(writer, instance.lengths.len);
                for (instance.lengths) |length| try putVar(writer, if (length) |value| @as(u64, value) + 1 else 0);
                try putSpan(writer, instance.site);
            },
        };
    }
    try putVar(writer, refs.templates.len);
    for (refs.templates) |template| {
        try putVar(writer, try pool.id(allocator, template.key));
        try writer.raw(&template.context);
        try writer.raw(&template.digest);
    }
}

/// Append one function's hot row and cold row to the scratch buffers.
fn putFunction(scratch: *Scratch, table: Table, entry: Summary) std.mem.Allocator.Error!void {
    const allocator = scratch.allocator;
    const flags = Flags.of(entry);
    try scratch.flags.append(allocator, flags.bits());
    const hot = &scratch.hot;
    try hot.offsets.append(allocator, @intCast(hot.writer.bytes.items.len));
    const w = &hot.writer;
    try putVar(w, entry.fact.mutates.len);
    for (entry.fact.mutates) |position| try putVar(w, position);
    try putVar(w, entry.fact.return_origin.positions.len);
    for (entry.fact.return_origin.positions) |position| try putVar(w, position);
    try putVar(w, entry.uses.records.len);
    for (entry.uses.records) |position| {
        // A position outside the table's record list names nothing; the section stores an id that no record has, which no shape matches.
        const id = (try scratch.recordId(table, position)) orelse {
            try putVar(w, std.math.maxInt(u32));
            continue;
        };
        if (!(try scratch.touched_seen.getOrPut(allocator, id)).found_existing) try scratch.touched.append(allocator, id);
        try putVar(w, id);
    }
    try putNotes(w, &scratch.pool, allocator, entry.notes.body);
    try putNotes(w, &scratch.pool, allocator, entry.notes.pass);
    if (entry.notes.guard) |guard| try w.raw(&guard);
    if (entry.uses.refs) |refs| try putRefs(w, &scratch.pool, allocator, refs);
    if (entry.notes.keeps.len != 0) try putKeeps(w, &scratch.pool, allocator, entry.notes.keeps);

    const cold = &scratch.cold;
    try cold.offsets.append(allocator, @intCast(cold.writer.bytes.items.len));
    const c = &cold.writer;
    try putText(c, entry.key);
    try c.raw(&entry.context);
    try putVar(c, entry.region.len);
    try c.raw(&entry.region.digest);
    try putVar(c, entry.region.names.len);
    for (entry.region.names) |name| {
        try putVar(c, try scratch.pool.id(allocator, name.text));
        try putVar(c, if (name.owner) |owner| @as(u64, try scratch.pool.id(allocator, owner)) + 1 else 0);
    }
    try putVar(c, entry.uses.callees.len);
    for (entry.uses.callees) |callee| {
        const key = if (callee < table.summaries.len) table.summaries[callee].key else "";
        try putVar(c, try scratch.pool.id(allocator, key));
    }
    if (entry.uses.values.len == 0) return;
    try putVar(c, entry.uses.values.len);
    for (entry.uses.values) |value| {
        const key = if (value < table.summaries.len) table.summaries[value].key else "";
        try putVar(c, try scratch.pool.id(allocator, key));
    }
}

/// The hot and cold areas of one freshly encoded section, appended to `hot_out` and `cold_out`.
fn encodeSection(scratch: *Scratch, table: Table, section: OutSection, hot_out: *std.ArrayList(u8), cold_out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const allocator = scratch.allocator;
    scratch.hot.clear();
    scratch.cold.clear();
    scratch.flags.clearRetainingCapacity();
    scratch.touched.clearRetainingCapacity();
    scratch.touched_seen.clearRetainingCapacity();
    for (section.members) |instance| try putFunction(scratch, table, table.summaries[instance]);
    try scratch.hot.offsets.append(allocator, @intCast(scratch.hot.writer.bytes.items.len));
    try scratch.cold.offsets.append(allocator, @intCast(scratch.cold.writer.bytes.items.len));

    const count = section.members.len;
    try putU32(hot_out, allocator, scratch.touched.items.len);
    try putU32(hot_out, allocator, scratch.hot.writer.bytes.items.len);
    try hot_out.ensureUnusedCapacity(allocator, count * 6 + 4 + scratch.touched.items.len * 4 + scratch.hot.writer.bytes.items.len);
    for (scratch.flags.items) |bits| hot_out.appendSliceAssumeCapacity(&std.mem.toBytes(std.mem.nativeToLittle(u16, bits)));
    for (scratch.hot.offsets.items) |offset| hot_out.appendSliceAssumeCapacity(&std.mem.toBytes(std.mem.nativeToLittle(u32, offset)));
    for (scratch.touched.items) |id| hot_out.appendSliceAssumeCapacity(&std.mem.toBytes(std.mem.nativeToLittle(u32, id)));
    hot_out.appendSliceAssumeCapacity(scratch.hot.writer.bytes.items);

    try putU32(cold_out, allocator, scratch.cold.writer.bytes.items.len);
    try cold_out.ensureUnusedCapacity(allocator, count * 4 + 4 + scratch.cold.writer.bytes.items.len);
    for (scratch.cold.offsets.items) |offset| cold_out.appendSliceAssumeCapacity(&std.mem.toBytes(std.mem.nativeToLittle(u32, offset)));
    cold_out.appendSliceAssumeCapacity(scratch.cold.writer.bytes.items);
}

/// The bytes a varint of `value` takes.
fn varLen(value: u64) usize {
    var size: usize = 1;
    var rest = value >> 7;
    while (rest != 0) : (rest >>= 7) size += 1;
    return size;
}

/// Write the varint of `value` at `buffer[at.*]`, advancing `at`; the buffer was sized with `varLen`.
fn putVarAt(buffer: []u8, at: *usize, value: u64) void {
    var rest = value;
    while (rest >= 0x80) : (rest >>= 7) {
        buffer[at.*] = @as(u8, @truncate(rest)) | 0x80;
        at.* += 1;
    }
    buffer[at.*] = @as(u8, @truncate(rest));
    at.* += 1;
}

/// The shared block of the table being written: the first string count it was built with (`base`), the strings, and the records. Its size
/// is computed first, so it is one allocation.
fn sharedBlock(allocator: std.mem.Allocator, scratch: *const Scratch, base: usize) std.mem.Allocator.Error![]u8 {
    const strings = scratch.pool.list.items;
    const records = scratch.records.list.items;
    var size: usize = varLen(base) + varLen(strings.len) + varLen(records.len);
    for (strings) |text| size += varLen(text.len) + text.len;
    for (records) |record| size += varLen(record.name) + 32;
    const out = try allocator.alloc(u8, size);
    var at: usize = 0;
    putVarAt(out, &at, base);
    putVarAt(out, &at, strings.len);
    for (strings) |text| {
        putVarAt(out, &at, text.len);
        @memcpy(out[at..][0..text.len], text);
        at += text.len;
    }
    putVarAt(out, &at, records.len);
    for (records) |record| {
        putVarAt(out, &at, record.name);
        @memcpy(out[at..][0..32], &record.shape);
        at += 32;
    }
    return out;
}

/// Bytes of the directory entry of one section.
fn entrySize(name: []const u8) usize {
    return 2 + name.len + 4 + 32 + 4 + 4 + 8 + 8;
}

/// The sections of `table`: the ones it names, or, when it names none, one per module its keys name, in the order they first appear.
fn layoutOf(allocator: std.mem.Allocator, table: Table) std.mem.Allocator.Error![]const OutSection {
    if (table.sections.len != 0) return table.sections;
    var out: std.ArrayList(OutSection) = .empty;
    var members: std.ArrayList(std.ArrayList(u32)) = .empty;
    var by_name: std.StringHashMapUnmanaged(u32) = .empty;
    for (table.summaries, 0..) |entry, instance| {
        const name = moduleOfKey(entry.key);
        const found = try by_name.getOrPut(allocator, name);
        if (!found.found_existing) {
            found.value_ptr.* = @intCast(out.items.len);
            try out.append(allocator, .{ .name = name, .signature = undefined, .members = &.{} });
            try members.append(allocator, .empty);
        }
        try members.items[found.value_ptr.*].append(allocator, @intCast(instance));
    }
    for (out.items, members.items) |*section, list| {
        section.members = list.items;
        var hasher = SignatureHasher.init(section.name, list.items.len);
        for (list.items) |instance| hasher.add(table.summaries[instance].context, table.summaries[instance].region.digest);
        section.signature = hasher.final();
    }
    return out.items;
}

/// The domain a module signature is taken under.
const signature_domain = "selka-module-signature-v1";

/// The signature of a module (`sema_module_groups.signatureOf` computes the same value): its name and, for each function in order, the
/// dependency context and the region digest.
pub const SignatureHasher = struct {
    state: std.crypto.hash.Blake3,

    /// Begin the signature of module `name` with `count` functions.
    pub fn init(name: []const u8, count: usize) SignatureHasher {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(signature_domain);
        var size: [8]u8 = undefined;
        std.mem.writeInt(u64, &size, name.len, .little);
        hash.update(&size);
        hash.update(name);
        std.mem.writeInt(u64, &size, count, .little);
        hash.update(&size);
        return .{ .state = hash };
    }

    /// Add one function, in program order.
    pub fn add(self: *SignatureHasher, context: [32]u8, region: [32]u8) void {
        self.state.update(&context);
        self.state.update(&region);
    }

    /// The signature.
    pub fn final(self: *SignatureHasher) [32]u8 {
        var out: [32]u8 = undefined;
        self.state.final(&out);
        return out;
    }
};

/// Serialize a table. A section marked `reuse` is copied from `previous` as it was stored; every other is written afresh. The strings a
/// section repeats are written once, in its own pools, and every count and index takes only the bytes its value needs.
pub fn encodeTable(allocator: std.mem.Allocator, table: Table, previous: ?*Sections, hint: SizeHint) std.mem.Allocator.Error![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const sections = try layoutOf(arena, table);
    var scratch = try Scratch.init(allocator, table.records.len);
    defer scratch.deinit();

    var dir_size: usize = format_version.len + 1 + 4 + 4 + 4 + 8 + 8;
    for (sections) |section| dir_size += entrySize(section.name);

    // A section stored as it was refers to the shared block of the table it comes from: this table's starts as a copy of that one.
    var reuses = false;
    for (sections) |section| reuses = reuses or section.reuse != null;
    var base: ?usize = null;
    if (reuses) {
        const old = previous orelse @panic("a table with reused sections is encoded from the table it reuses");
        const shared = old.sharedOf() orelse @panic("a table with reused sections reuses a table whose shared block checks");
        try scratch.seed(shared);
        base = shared.base;
    }

    // Every area is known before any byte is placed, so the payload is allocated once.
    const Placed = struct { hot: usize, cold: usize, hot_sum: u64, cold_sum: u64, fresh: ?usize };
    const placed = try arena.alloc(Placed, sections.len);
    var hots: std.ArrayList(std.ArrayList(u8)) = .empty;
    defer for (hots.items) |*each| each.deinit(allocator);
    var colds: std.ArrayList(std.ArrayList(u8)) = .empty;
    defer for (colds.items) |*each| each.deinit(allocator);
    var total_size: usize = dir_size;
    for (sections, placed) |section, *slot| {
        if (section.reuse) |index| {
            const old = previous orelse @panic("a table with reused sections is encoded from the table it reuses");
            // A section is marked for reuse only when it is the previous table's: the planner and `reusable` compare the same two things.
            const range = old.reusable(index, section) orelse @panic("a section marked for reuse is not the previous table's");
            slot.* = .{ .hot = range.hot.len, .cold = range.cold.len, .hot_sum = range.hot_sum, .cold_sum = range.cold_sum, .fresh = null };
        } else {
            var hot: std.ArrayList(u8) = .empty;
            var cold: std.ArrayList(u8) = .empty;
            errdefer hot.deinit(allocator);
            errdefer cold.deinit(allocator);
            try encodeSection(&scratch, table, section, &hot, &cold);
            slot.* = .{ .hot = hot.items.len, .cold = cold.items.len, .hot_sum = codec.checksum(hot.items), .cold_sum = codec.checksum(cold.items), .fresh = hots.items.len };
            try hots.ensureUnusedCapacity(arena, 1);
            try colds.ensureUnusedCapacity(arena, 1);
            hots.appendAssumeCapacity(hot);
            colds.appendAssumeCapacity(cold);
        }
        total_size += slot.hot + slot.cold;
    }
    const shared = try sharedBlock(allocator, &scratch, base orelse scratch.pool.list.items.len);
    defer allocator.free(shared);
    total_size += shared.len;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, @max(total_size, hint.bytes));
    out.items.len = dir_size;
    for (sections, placed) |section, slot| {
        if (slot.fresh) |at| {
            out.appendSliceAssumeCapacity(hots.items[at].items);
        } else out.appendSliceAssumeCapacity(previous.?.reusable(section.reuse.?, section).?.hot);
    }
    for (sections, placed) |section, slot| {
        if (slot.fresh) |at| {
            out.appendSliceAssumeCapacity(colds.items[at].items);
        } else out.appendSliceAssumeCapacity(previous.?.reusable(section.reuse.?, section).?.cold);
    }
    out.appendSliceAssumeCapacity(shared);

    var at: usize = 0;
    @memcpy(out.items[at..][0..format_version.len], format_version);
    at += format_version.len;
    out.items[at] = 0;
    at += 1;
    var total: usize = 0;
    for (sections) |section| total += section.members.len;
    std.mem.writeInt(u32, out.items[at..][0..4], @intCast(sections.len), .little);
    std.mem.writeInt(u32, out.items[at + 4 ..][0..4], @intCast(total), .little);
    std.mem.writeInt(u32, out.items[at + 8 ..][0..4], @intCast(shared.len), .little);
    std.mem.writeInt(u64, out.items[at + 12 ..][0..8], codec.checksum(shared), .little);
    at += 20;
    for (sections, placed) |section, slot| {
        std.mem.writeInt(u16, out.items[at..][0..2], @intCast(section.name.len), .little);
        at += 2;
        @memcpy(out.items[at..][0..section.name.len], section.name);
        at += section.name.len;
        std.mem.writeInt(u32, out.items[at..][0..4], @intCast(section.members.len), .little);
        at += 4;
        @memcpy(out.items[at..][0..32], &section.signature);
        at += 32;
        std.mem.writeInt(u32, out.items[at..][0..4], @intCast(slot.hot), .little);
        std.mem.writeInt(u32, out.items[at + 4 ..][0..4], @intCast(slot.cold), .little);
        std.mem.writeInt(u64, out.items[at + 8 ..][0..8], slot.hot_sum, .little);
        std.mem.writeInt(u64, out.items[at + 16 ..][0..8], slot.cold_sum, .little);
        at += 24;
    }
    std.mem.writeInt(u64, out.items[at..][0..8], codec.checksum(out.items[0..at]), .little);
    return out.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------------------------------------------------------------
// Decoding

/// One record a section's functions touched: its catalog name and the shape digest it had when the table was made.
pub const RecordInfo = struct { name: []const u8, shape: [32]u8 };

/// One section of a payload as the directory lists it.
const Entry = struct {
    name: []const u8,
    count: u32,
    first: u32,
    signature: [32]u8,
    hot: []const u8,
    cold: []const u8,
    hot_sum: u64,
    cold_sum: u64,
};

/// The bytes of a section a table can be rewritten from without decoding it.
pub const Stored = struct { hot: []const u8, cold: []const u8, hot_sum: u64, cold_sum: u64 };

/// What opening a section found: its hot area laid out, and whatever has been decoded since.
const Data = struct {
    /// False: the section's bytes do not check (a checksum, a length or an offset is wrong); it is treated as absent.
    ok: bool,
    count: u32 = 0,
    hot: []const u8 = &.{},
    /// The ids of the records the section's functions touched.
    records: []const u32 = &.{},
    rows_at: usize = 0,
    /// The cold area, once it checked.
    cold: ?ColdArea = null,
    cold_failed: bool = false,
    memo: []Summary = &.{},
    done: []bool = &.{},
    hot_memo: []Hot = &.{},
    hot_done: []u8 = &.{},
    callee_memo: [][]const u32 = &.{},
    callee_done: []bool = &.{},
    keys: ?std.StringHashMapUnmanaged(u32) = null,
};

/// What a function's hot row holds besides its facts: the records it touched (indices into its section's list), its notes and guard,
/// and the references of a tree that names a specialization or an interned type.
pub const Hot = struct {
    records: []const u32 = &.{},
    body: []const Note = &.{},
    pass: []const Note = &.{},
    guard: ?[32]u8 = null,
    refs: ?Refs = null,
    keeps: []const Keep = &.{},
};

/// Bytes before the columns of a hot area (the record count and the bytes of rows) and of a cold area (the bytes of rows).
const hot_header = 8;
const cold_header = 4;

const ColdArea = struct { bytes: []const u8, rows_at: usize };

/// The shared block as read: the strings, the records (their names are strings), and how many strings the pool held when it was last built afresh.
pub const Shared = struct { strings: []const []const u8, records: []const RecordInfo, base: u32 };

/// What a view counts besides its directory: the functions it holds, the section of the functions no module could be told for (if any),
/// and how many sections or rows turned out not to check.
const Meta = struct {
    total: u32,
    misc: ?u32 = null,
    damaged: u32 = 0,
    /// The shared block's bytes and checksum, and what reading it gave (once asked; `shared_failed` when it does not check).
    shared_bytes: []const u8 = &.{},
    shared_sum: u64 = 0,
    shared: ?Shared = null,
    shared_failed: bool = false,
};

/// The decoded view of a payload: a directory, and sections opened on demand. Everything it allocates belongs to `allocator` (an arena);
/// strings borrow the payload, which the caller keeps alive for as long as the view is used.
pub const Sections = struct {
    allocator: std.mem.Allocator,
    payload: []const u8,
    entries: []Entry,
    section_of: []u32,
    by_name: std.StringHashMapUnmanaged(u32) = .empty,
    data: []?*Data,
    meta: Meta,

    /// The view of `payload`, or null for a payload that is malformed, foreign or of another version.
    pub fn open(allocator: std.mem.Allocator, payload: []const u8) ?*Sections {
        return openChecked(allocator, payload) catch null;
    }

    fn openChecked(allocator: std.mem.Allocator, payload: []const u8) !*Sections {
        if (payload.len < format_version.len + 1 + 8 + 12 + 8) return error.InvalidEncoding;
        if (!std.mem.eql(u8, payload[0..format_version.len], format_version) or payload[format_version.len] != 0) return error.InvalidEncoding;
        var cursor: usize = format_version.len + 1;
        const section_count = u32At(payload, cursor);
        const total = u32At(payload, cursor + 4);
        const shared_len = u32At(payload, cursor + 8);
        const shared_sum = std.mem.readInt(u64, payload[cursor + 12 ..][0..8], .little);
        cursor += 20;
        if (section_count > payload.len or total > payload.len) return error.InvalidEncoding;
        const entries = try allocator.alloc(Entry, section_count);
        const lengths = try allocator.alloc([2]u32, section_count);
        defer allocator.free(lengths);
        var index_at: usize = 0;
        var hot_total: usize = 0;
        var cold_total: usize = 0;
        var running: u32 = 0;
        for (entries) |*entry| {
            if (payload.len - cursor < 2) return error.Truncated;
            const name_len = std.mem.readInt(u16, payload[cursor..][0..2], .little);
            cursor += 2;
            const module = try getBytes(payload, &cursor, name_len);
            if (payload.len - cursor < 4 + 32 + 24) return error.Truncated;
            const members = u32At(payload, cursor);
            cursor += 4;
            const signature = payload[cursor..][0..32].*;
            cursor += 32;
            const hot_len = u32At(payload, cursor);
            const cold_len = u32At(payload, cursor + 4);
            const hot_sum = std.mem.readInt(u64, payload[cursor + 8 ..][0..8], .little);
            const cold_sum = std.mem.readInt(u64, payload[cursor + 16 ..][0..8], .little);
            cursor += 24;
            entry.* = .{ .name = module, .count = members, .first = running, .signature = signature, .hot = &.{}, .cold = &.{}, .hot_sum = hot_sum, .cold_sum = cold_sum };
            lengths[index_at] = .{ hot_len, cold_len };
            index_at += 1;
            running = std.math.add(u32, running, members) catch return error.InvalidEncoding;
            hot_total = std.math.add(usize, hot_total, hot_len) catch return error.InvalidEncoding;
            cold_total = std.math.add(usize, cold_total, cold_len) catch return error.InvalidEncoding;
        }
        if (running != total) return error.InvalidEncoding;
        if (payload.len - cursor < 8) return error.Truncated;
        if (codec.checksum(payload[0..cursor]) != std.mem.readInt(u64, payload[cursor..][0..8], .little)) return error.InvalidEncoding;
        cursor += 8;
        if (payload.len - cursor != hot_total + cold_total + shared_len) return error.InvalidEncoding;
        var hot_at = cursor;
        var cold_at = cursor + hot_total;
        for (entries, lengths) |*entry, each| {
            const hot_len = each[0];
            const cold_len = each[1];
            entry.hot = payload[hot_at..][0..hot_len];
            entry.cold = payload[cold_at..][0..cold_len];
            hot_at += hot_len;
            cold_at += cold_len;
        }
        const self = try allocator.create(Sections);
        self.* = .{
            .allocator = allocator,
            .payload = payload,
            .entries = entries,
            .meta = .{ .total = total, .shared_bytes = payload[payload.len - shared_len ..], .shared_sum = shared_sum },
            .section_of = try allocator.alloc(u32, total),
            .data = try allocator.alloc(?*Data, section_count),
        };
        @memset(self.data, null);
        try self.by_name.ensureTotalCapacity(allocator, section_count);
        for (entries, 0..) |entry, index| {
            @memset(self.section_of[entry.first..][0..entry.count], @intCast(index));
            const named = self.by_name.getOrPutAssumeCapacity(entry.name);
            // Two sections of one name cannot both be found; the first is, the other is never asked.
            if (!named.found_existing) named.value_ptr.* = @intCast(index);
            if (std.mem.eql(u8, entry.name, ungrouped)) self.meta.misc = @intCast(index);
        }
        return self;
    }

    /// Release the tables the view itself allocated. What opened sections decoded (names, notes, references) belongs to the allocator
    /// the view was made with, which is an arena in the compiler, and goes with it.
    pub fn deinit(self: *Sections) void {
        const allocator = self.allocator;
        self.by_name.deinit(allocator);
        allocator.free(self.data);
        allocator.free(self.section_of);
        allocator.free(self.entries);
        allocator.destroy(self);
    }

    /// How many functions the table holds.
    pub fn functionCount(self: *const Sections) usize {
        return self.meta.total;
    }

    /// How many sections.
    pub fn sectionCount(self: *const Sections) usize {
        return self.entries.len;
    }

    /// The section with this module name, or null.
    pub fn byName(self: *const Sections, module: []const u8) ?u32 {
        return self.by_name.get(module);
    }

    /// A section's signature.
    pub fn signatureOf(self: *const Sections, section: u32) *const [32]u8 {
        return &self.entries[section].signature;
    }

    /// The position of a section's first function.
    pub fn firstOf(self: *const Sections, section: u32) u32 {
        return self.entries[section].first;
    }

    /// How many functions a section holds.
    pub fn sizeOf(self: *const Sections, section: u32) u32 {
        return self.entries[section].count;
    }

    /// A section's module name.
    pub fn nameOf(self: *const Sections, section: u32) []const u8 {
        return self.entries[section].name;
    }

    /// The section of the function at `position`.
    pub fn sectionOf(self: *const Sections, position: u32) u32 {
        return self.section_of[position];
    }

    /// The cold area of a section as stored (its bytes in the payload), for tests that damage it.
    pub fn coldBytes(self: *const Sections, section: u32) []const u8 {
        return self.entries[section].cold;
    }

    /// Whether a table cut as `sections` is this table exactly: every section is the previous one in its place.
    pub fn sameAs(self: *const Sections, sections: []const OutSection) bool {
        if (sections.len != self.entries.len) return false;
        for (sections, 0..) |section, index| {
            const reuse = section.reuse orelse return false;
            if (reuse != index or self.reusable(reuse, section) == null) return false;
        }
        return true;
    }

    /// The stored bytes of section `cursor` when it is the one `section` stands for (the signatures and counts agree) and checks, else null.
    pub fn reusable(self: *const Sections, index: u32, section: OutSection) ?Stored {
        if (index >= self.entries.len) return null;
        const entry = self.entries[index];
        if (entry.count != section.members.len or !std.mem.eql(u8, &entry.signature, &section.signature)) return null;
        return .{ .hot = entry.hot, .cold = entry.cold, .hot_sum = entry.hot_sum, .cold_sum = entry.cold_sum };
    }

    /// A section's data, opened (its hot area checked and laid out) on first use.
    fn dataOf(self: *Sections, section: u32) *Data {
        if (self.data[section]) |known| return known;
        const made = self.allocator.create(Data) catch @panic("out of memory");
        made.* = self.openData(self.entries[section]) catch .{ .ok = false };
        if (!made.ok) self.meta.damaged += 1;
        self.data[section] = made;
        return made;
    }

    fn openData(self: *Sections, entry: Entry) !Data {
        const hot = entry.hot;
        if (hot.len < hot_header) return error.Truncated;
        if (codec.checksum(hot) != entry.hot_sum) return error.InvalidEncoding;
        const functions = entry.count;
        const n_records = u32At(hot, 0);
        const rows_len = u32At(hot, 4);
        const offsets_at = hot_header + 2 * @as(usize, functions);
        const records_at = offsets_at + 4 * (@as(usize, functions) + 1);
        const rows_at = records_at + 4 * @as(usize, n_records);
        if (rows_at + @as(usize, rows_len) != hot.len) return error.InvalidEncoding;
        const ids = try self.allocator.alloc(u32, n_records);
        for (ids, 0..) |*id, at_id| id.* = u32At(hot, records_at + 4 * at_id);
        return .{ .ok = true, .count = functions, .hot = hot, .records = ids, .rows_at = rows_at };
    }

    /// The ids of the records a section's functions touched (empty for a section that does not check).
    pub fn sectionRecords(self: *Sections, section: u32) []const u32 {
        return self.dataOf(section).records;
    }

    /// The shared block: the string pool and the record list every section refers to; null when it does not check.
    pub fn sharedOf(self: *Sections) ?*const Shared {
        if (self.meta.shared) |*known| return known;
        if (self.meta.shared_failed) return null;
        self.meta.shared = self.readShared() catch {
            self.meta.shared_failed = true;
            self.meta.damaged += 1;
            return null;
        };
        return &self.meta.shared.?;
    }

    fn readShared(self: *Sections) !Shared {
        const bytes = self.meta.shared_bytes;
        if (codec.checksum(bytes) != self.meta.shared_sum) return error.InvalidEncoding;
        var cursor: usize = 0;
        const base = std.math.cast(u32, try getVar(bytes, &cursor)) orelse return error.InvalidEncoding;
        const n_strings = try getCount(bytes, &cursor);
        const strings = try self.allocator.alloc([]const u8, n_strings);
        for (strings) |*text| text.* = try getText(bytes, &cursor);
        const n_records = try getCount(bytes, &cursor);
        const records = try self.allocator.alloc(RecordInfo, n_records);
        for (records) |*entry| {
            entry.name = try poolText(strings, try getVar(bytes, &cursor));
            entry.shape = try getDigest(bytes, &cursor);
        }
        if (cursor != bytes.len) return error.InvalidEncoding;
        return .{ .strings = strings, .records = records, .base = base };
    }

    /// Whether the string pool has grown to more than twice what it held when it was last built afresh: the table is then written afresh.
    pub fn needsRebuild(self: *Sections) bool {
        const shared = self.sharedOf() orelse return true;
        return shared.strings.len > 2 * @as(usize, shared.base) + 4096;
    }

    /// How many records the shared list holds.
    pub fn recordCount(self: *Sections) usize {
        return (self.sharedOf() orelse return 0).records.len;
    }

    /// The record with this id; an id that names none gives a record with no name and a shape nothing has.
    pub fn recordById(self: *Sections, id: u32) RecordInfo {
        const shared = self.sharedOf() orelse return .{ .name = "", .shape = @splat(0) };
        return if (id < shared.records.len) shared.records[id] else .{ .name = "", .shape = @splat(0) };
    }

    /// The flags of the function at `position`; none for a function of a section that does not check.
    pub fn flagsAt(self: *Sections, position: u32) Flags {
        const section = self.section_of[position];
        const data = self.dataOf(section);
        if (!data.ok) return .{};
        const local = position - self.entries[section].first;
        return Flags.fromBits(std.mem.readInt(u16, data.hot[hot_header + 2 * @as(usize, local) ..][0..2], .little)) orelse .{};
    }

    /// The key of the function at `position` (empty for one of a section that does not check).
    pub fn keyAt(self: *Sections, position: u32) []const u8 {
        const section = self.section_of[position];
        const cold = self.coldOf(section) orelse return "";
        const local = position - self.entries[section].first;
        var cursor = self.coldRowStart(section, cold, local);
        return getText(cold.bytes, &cursor) catch "";
    }

    fn hotRow(data: *const Data, local: usize) []const u8 {
        const offsets_at = hot_header + 2 * @as(usize, data.count);
        const from = u32At(data.hot, offsets_at + 4 * local);
        const to = u32At(data.hot, offsets_at + 4 * (local + 1));
        const rows = data.hot[data.rows_at..];
        return if (from <= to and to <= rows.len) rows[from..to] else &.{};
    }

    fn coldRowStart(self: *const Sections, section: u32, cold: ColdArea, local: usize) usize {
        _ = self;
        _ = section;
        const from = u32At(cold.bytes, cold_header + 4 * local);
        return cold.rows_at + from;
    }

    fn coldOf(self: *Sections, section: u32) ?ColdArea {
        const data = self.dataOf(section);
        if (!data.ok) return null;
        if (data.cold) |known| return known;
        if (data.cold_failed) return null;
        const made = self.openCold(self.entries[section]) catch {
            data.cold_failed = true;
            self.meta.damaged += 1;
            return null;
        };
        data.cold = made;
        return made;
    }

    fn openCold(self: *Sections, entry: Entry) !ColdArea {
        _ = self;
        const cold = entry.cold;
        if (cold.len < cold_header) return error.Truncated;
        if (codec.checksum(cold) != entry.cold_sum) return error.InvalidEncoding;
        const rows_len = u32At(cold, 0);
        const rows_at = cold_header + 4 * (@as(usize, entry.count) + 1);
        if (rows_at + @as(usize, rows_len) != cold.len) return error.InvalidEncoding;
        return .{ .bytes = cold, .rows_at = rows_at };
    }

    /// The position of the function with this key, or null. The section is the one the key's module names (or the one of unplaced
    /// functions); its keys are indexed on first use.
    pub fn find(self: *Sections, key: []const u8) ?u32 {
        const section = self.by_name.get(moduleOfKey(key)) orelse return self.findMisc(key);
        if (self.findIn(section, key)) |position| return position;
        return self.findMisc(key);
    }

    fn findMisc(self: *Sections, key: []const u8) ?u32 {
        const section = self.meta.misc orelse return null;
        return self.findIn(section, key);
    }

    fn findIn(self: *Sections, section: u32, key: []const u8) ?u32 {
        const data = self.dataOf(section);
        if (!data.ok) return null;
        if (data.keys == null) {
            const cold = self.coldOf(section) orelse return null;
            var map: std.StringHashMapUnmanaged(u32) = .empty;
            map.ensureTotalCapacity(self.allocator, data.count) catch @panic("out of memory");
            for (0..data.count) |local| {
                var cursor = self.coldRowStart(section, cold, local);
                const text = getText(cold.bytes, &cursor) catch {
                    data.cold_failed = true;
                    self.meta.damaged += 1;
                    return null;
                };
                const entry = map.getOrPutAssumeCapacity(text);
                // Keys are unique in a table this compiler wrote; a duplicate is foreign.
                if (entry.found_existing) {
                    data.ok = false;
                    self.meta.damaged += 1;
                    return null;
                }
                entry.value_ptr.* = @intCast(local);
            }
            data.keys = map;
        }
        const local = data.keys.?.get(key) orelse return null;
        return self.entries[section].first + local;
    }

    /// The facts of the function at `position`, decoded from its hot row alone.
    pub fn factAt(self: *Sections, position: u32) Fact {
        const section = self.section_of[position];
        const data = self.dataOf(section);
        if (!data.ok) return .{};
        const local = position - self.entries[section].first;
        const flags = Flags.fromBits(std.mem.readInt(u16, data.hot[hot_header + 2 * @as(usize, local) ..][0..2], .little)) orelse return .{};
        const row = hotRow(data, local);
        var cursor: usize = 0;
        var fact: Fact = .{};
        fact.mutates = self.readPositions(row, &cursor) catch return .{};
        fact.return_origin.positions = self.readPositions(row, &cursor) catch return .{};
        fact.mutates_unknown = flags.facts.mutates_unknown;
        fact.return_origin.unknown = flags.facts.return_unknown;
        fact.inferred = .{ .writes = flags.facts.writes, .external = flags.facts.external };
        return fact;
    }

    fn readPositions(self: *Sections, row: []const u8, cursor: *usize) !([]const u16) {
        const n = try getCount(row, cursor);
        if (n == 0) return &.{};
        const positions = try self.allocator.alloc(u16, n);
        for (positions) |*position| position.* = std.math.cast(u16, try getVar(row, cursor)) orelse return error.InvalidEncoding;
        return positions;
    }

    /// The region of the function at `position`: its length, digest and names, decoded from the cold row alone.
    pub fn regionAt(self: *Sections, position: u32) types.Region {
        const empty: types.Region = .{ .len = 0, .digest = @splat(0) };
        const section = self.section_of[position];
        const cold = self.coldOf(section) orelse return empty;
        const local = position - self.entries[section].first;
        const bytes = cold.bytes;
        var at_row = self.coldRowStart(section, cold, local);
        return self.readRegion(bytes, &at_row) catch empty;
    }

    fn readRegion(self: *Sections, bytes: []const u8, at_row: *usize) !types.Region {
        _ = try getText(bytes, at_row);
        _ = try getDigest(bytes, at_row);
        return self.readRegionTail(bytes, at_row);
    }

    /// The region of a cold row, whose cursor stands after the key and the context.
    fn readRegionTail(self: *Sections, bytes: []const u8, at_row: *usize) !types.Region {
        const strings = (self.sharedOf() orelse return error.InvalidEncoding).strings;
        var region: types.Region = .{ .len = 0, .digest = undefined };
        region.len = std.math.cast(u32, try getVar(bytes, at_row)) orelse return error.InvalidEncoding;
        region.digest = try getDigest(bytes, at_row);
        const names = try self.allocator.alloc(semantic_key.Name, try getCount(bytes, at_row));
        for (names) |*item| {
            item.text = try poolText(strings, try getVar(bytes, at_row));
            const owner = try getVar(bytes, at_row);
            item.owner = if (owner == 0) null else try poolText(strings, owner - 1);
        }
        region.names = names;
        return region;
    }

    /// The record that index `local` of the function at `position`'s `uses.records` names.
    pub fn recordOf(self: *Sections, position: u32, local: u32) RecordInfo {
        _ = position;
        return self.recordById(local);
    }

    /// The whole summary of the function at `position`, decoded on first use. A function of a section that does not check, or whose
    /// bytes do not decode, is a summary that stands in for nothing (empty key, not stubbable).
    pub fn at(self: *Sections, position: u32) *const Summary {
        const section = self.section_of[position];
        const data = self.dataOf(section);
        const local = position - self.entries[section].first;
        if (data.memo.len == 0 and data.count != 0) {
            data.memo = self.allocator.alloc(Summary, data.count) catch @panic("out of memory");
            data.done = self.allocator.alloc(bool, data.count) catch @panic("out of memory");
            @memset(data.done, false);
        }
        if (data.done.len == 0) return &absent;
        if (!data.done[local]) {
            data.memo[local] = self.decodeFunction(section, data, local) catch blk: {
                self.meta.damaged += 1;
                break :blk absent;
            };
            data.done[local] = true;
        }
        return &data.memo[local];
    }

    /// The hot row of the function at `position` beyond its facts, decoded on first use; null when the row does not decode.
    pub fn hotAt(self: *Sections, position: u32) ?*const Hot {
        const section = self.section_of[position];
        const data = self.dataOf(section);
        if (!data.ok) return null;
        const local = position - self.entries[section].first;
        if (data.hot_memo.len == 0) {
            data.hot_memo = self.allocator.alloc(Hot, data.count) catch @panic("out of memory");
            data.hot_done = self.allocator.alloc(u8, data.count) catch @panic("out of memory");
            @memset(data.hot_done, 0);
        }
        if (data.hot_done[local] == 0) {
            if (self.decodeHot(data, local)) |hot| {
                data.hot_memo[local] = hot;
                data.hot_done[local] = 1;
            } else |_| {
                self.meta.damaged += 1;
                data.hot_done[local] = 2;
            }
        }
        return if (data.hot_done[local] == 1) &data.hot_memo[local] else null;
    }

    fn decodeHot(self: *Sections, data: *Data, local: usize) !Hot {
        const flags = Flags.fromBits(std.mem.readInt(u16, data.hot[hot_header + 2 * local ..][0..2], .little)) orelse return error.InvalidEncoding;
        const allocator = self.allocator;
        const row = hotRow(data, local);
        var cursor: usize = 0;
        for (0..2) |_| {
            const n = try getCount(row, &cursor);
            for (0..n) |_| _ = try getVar(row, &cursor);
        }
        var hot: Hot = .{};
        const n_records = try getCount(row, &cursor);
        if (n_records != 0) {
            const locals = try allocator.alloc(u32, n_records);
            for (locals) |*local_id| {
                const index = try getVar(row, &cursor);
                if (index >= self.recordCount() and index != std.math.maxInt(u32)) return error.InvalidEncoding;
                local_id.* = @intCast(index);
            }
            hot.records = locals;
        }
        const pool: []const []const u8 = if (flags.notes.body or flags.notes.pass or flags.holds.refs or flags.holds.keeps) (self.sharedOf() orelse return error.InvalidEncoding).strings else &.{};
        hot.body = try readNotes(allocator, row, &cursor, pool);
        hot.pass = try readNotes(allocator, row, &cursor, pool);
        if (flags.holds.guard) hot.guard = try getDigest(row, &cursor);
        if (flags.holds.refs) hot.refs = try readRefs(allocator, row, &cursor, pool);
        if (flags.holds.keeps) hot.keeps = try readKeeps(allocator, row, &cursor, pool);
        if (cursor != row.len) return error.InvalidEncoding;
        return hot;
    }

    /// The callees of the function at `position` as positions of this table (`no_position` for a key the table does not hold), found by
    /// key on first use, which is why a summary's `uses.callees` is not filled when it is decoded.
    pub fn calleesAt(self: *Sections, position: u32) []const u32 {
        const section = self.section_of[position];
        const data = self.dataOf(section);
        const cold = self.coldOf(section) orelse return &.{};
        const local = position - self.entries[section].first;
        if (data.callee_memo.len == 0) {
            data.callee_memo = self.allocator.alloc([]const u32, data.count) catch @panic("out of memory");
            data.callee_done = self.allocator.alloc(bool, data.count) catch @panic("out of memory");
            @memset(data.callee_done, false);
        }
        if (!data.callee_done[local]) {
            data.callee_memo[local] = self.decodeCallees(section, cold, local) catch blk: {
                self.meta.damaged += 1;
                break :blk &.{};
            };
            data.callee_done[local] = true;
        }
        return data.callee_memo[local];
    }

    fn decodeCallees(self: *Sections, section: u32, cold: ColdArea, local: usize) ![]const u32 {
        var cold_at = try self.calleesStart(section, cold, local);
        return self.decodeKeys(cold.bytes, &cold_at);
    }

    /// The positions of this table of the functions the function at `position` names as values, found by key like its callees. Empty for a
    /// function whose `holds.values` flag is clear, which has no values in its row.
    pub fn valuesAt(self: *Sections, position: u32) []const u32 {
        if (!self.flagsAt(position).holds.values) return &.{};
        const section = self.section_of[position];
        const cold = self.coldOf(section) orelse return &.{};
        const local = position - self.entries[section].first;
        return self.decodeValues(section, cold, local) catch blk: {
            self.meta.damaged += 1;
            break :blk &.{};
        };
    }

    fn decodeValues(self: *Sections, section: u32, cold: ColdArea, local: usize) ![]const u32 {
        var cold_at = try self.calleesStart(section, cold, local);
        const strings = (self.sharedOf() orelse return error.InvalidEncoding).strings;
        for (0..try getCount(cold.bytes, &cold_at)) |_| _ = try poolText(strings, try getVar(cold.bytes, &cold_at));
        return self.decodeKeys(cold.bytes, &cold_at);
    }

    /// Where the callee keys of the function at `local` start in its cold row: past the key, the dependency context and the region.
    fn calleesStart(self: *Sections, section: u32, cold: ColdArea, local: usize) !usize {
        const bytes = cold.bytes;
        var cold_at = self.coldRowStart(section, cold, local);
        _ = try getText(bytes, &cold_at);
        _ = try getDigest(bytes, &cold_at);
        _ = try getVar(bytes, &cold_at);
        _ = try getDigest(bytes, &cold_at);
        const names = try getCount(bytes, &cold_at);
        for (0..names) |_| {
            _ = try getVar(bytes, &cold_at);
            _ = try getVar(bytes, &cold_at);
        }
        return cold_at;
    }

    /// A counted list of function keys at `bytes[cursor.*]`, as the positions of this table they name (`no_position` for a key it does not hold).
    fn decodeKeys(self: *Sections, bytes: []const u8, cursor: *usize) ![]const u32 {
        const strings = (self.sharedOf() orelse return error.InvalidEncoding).strings;
        const found = try self.allocator.alloc(u32, try getCount(bytes, cursor));
        for (found) |*position| {
            const key = try poolText(strings, try getVar(bytes, cursor));
            position.* = self.find(key) orelse no_position;
        }
        return found;
    }

    /// Everything but the callees of the function (`calleesAt`).
    fn decodeFunction(self: *Sections, section: u32, data: *Data, local: usize) !Summary {
        if (!data.ok) return error.InvalidEncoding;
        const cold = self.coldOf(section) orelse return error.InvalidEncoding;
        const position = self.entries[section].first + @as(u32, @intCast(local));
        const hot = self.hotAt(position) orelse return error.InvalidEncoding;
        const flags = Flags.fromBits(std.mem.readInt(u16, data.hot[hot_header + 2 * local ..][0..2], .little)) orelse return error.InvalidEncoding;
        var entry: Summary = undefined;
        entry.fact = self.factAt(position);
        entry.stubbable = flags.stubbable;
        entry.uses = .{ .records = hot.records, .refs = hot.refs };
        entry.notes = .{ .body = hot.body, .pass = hot.pass, .complete = flags.complete, .guard = hot.guard, .keeps = hot.keeps };
        const bytes = cold.bytes;
        var cold_at = self.coldRowStart(section, cold, local);
        entry.key = try getText(bytes, &cold_at);
        entry.context = try getDigest(bytes, &cold_at);
        entry.region = try self.readRegionTail(bytes, &cold_at);
        return entry;
    }

    /// The summary a function that does not decode stands for.
    const absent: Summary = .{ .key = "", .context = @splat(0), .region = .{ .len = 0, .digest = @splat(0) }, .fact = .{}, .stubbable = false };
};

/// A callee whose key names no function of the table (it is outside every position).
pub const no_position = std.math.maxInt(u32);

fn poolText(pool: []const []const u8, id: usize) codec.DecodeError![]const u8 {
    if (id >= pool.len) return error.InvalidEncoding;
    return pool[id];
}

fn readNotes(allocator: std.mem.Allocator, row: []const u8, at: *usize, pool: []const []const u8) ![]const Note {
    const n = try getCount(row, at);
    if (n == 0) return &.{};
    const notes = try allocator.alloc(Note, n);
    for (notes) |*note| {
        note.code = try poolText(pool, try getVar(row, at));
        note.message = try poolText(pool, try getVar(row, at));
        note.severity = std.enums.fromInt(diagnostic.Severity, try getVar(row, at)) orelse return error.InvalidEncoding;
        note.start = std.math.cast(u32, try getVar(row, at)) orelse return error.InvalidEncoding;
        note.end = std.math.cast(u32, try getVar(row, at)) orelse return error.InvalidEncoding;
        const rule = try getVar(row, at);
        note.rule = if (rule == 0) null else std.enums.fromInt(diagnostic.Rule, rule - 1) orelse return error.InvalidEncoding;
        const edits = try allocator.alloc(FixEdit, try getCount(row, at));
        for (edits) |*edit| {
            edit.start = std.math.cast(u32, try getVar(row, at)) orelse return error.InvalidEncoding;
            edit.end = std.math.cast(u32, try getVar(row, at)) orelse return error.InvalidEncoding;
            edit.text = try poolText(pool, try getVar(row, at));
        }
        note.fix = edits;
        if (!@import("ownership_rules.zig").valid(.{ .code = note.code, .rule = note.rule orelse continue })) return error.InvalidEncoding;
    }
    return notes;
}

fn getSpan(row: []const u8, at: *usize) codec.DecodeError!source.Span {
    const start = try getVar(row, at);
    const end = try getVar(row, at);
    return .{ .start = start, .end = end };
}

fn getType(row: []const u8, at: *usize) codec.DecodeError!typed.Type {
    return @fromBackingInt(try getVar(row, at));
}

fn readRecipe(allocator: std.mem.Allocator, row: []const u8, at: *usize, pool: []const []const u8) !owned.TypeRecipe {
    const tag = (try getBytes(row, at, 1))[0];
    return switch (tag) {
        0 => .{ .array = .{ .element = try getType(row, at), .length = try getVar(row, at), .site = try getSpan(row, at) } },
        1 => tuple: {
            const elements = try allocator.alloc(typed.Type, try getCount(row, at));
            for (elements) |*element| element.* = try getType(row, at);
            break :tuple .{ .tuple = elements };
        },
        2 => .{ .callable = try getSpan(row, at) },
        3 => instance: {
            const instance_name = try poolText(pool, try getVar(row, at));
            const arguments = try allocator.alloc(typed.Type, try getCount(row, at));
            for (arguments) |*argument| argument.* = try getType(row, at);
            const lengths = try allocator.alloc(?usize, try getCount(row, at));
            for (lengths) |*length| {
                const value = try getVar(row, at);
                length.* = if (value == 0) null else value - 1;
            }
            break :instance .{ .instance = .{ .name = instance_name, .arguments = arguments, .lengths = lengths, .site = try getSpan(row, at) } };
        },
        else => error.InvalidEncoding,
    };
}

fn readRefs(allocator: std.mem.Allocator, row: []const u8, at: *usize, pool: []const []const u8) !Refs {
    const functions = try allocator.alloc(owned.FunctionRef, try getCount(row, at));
    for (functions) |*reference| {
        const id = try getVar(row, at);
        reference.id = @fromBackingInt(id);
        reference.key = try poolText(pool, try getVar(row, at));
        const template = try getVar(row, at);
        reference.template = if (template == 0) null else try poolText(pool, template - 1);
    }
    const records = try allocator.alloc(owned.RecordRef, try getCount(row, at));
    for (records) |*reference| {
        reference.index = try getVar(row, at);
        reference.key = try poolText(pool, try getVar(row, at));
        reference.shape = try getDigest(row, at);
        const recipes = try allocator.alloc(owned.TypeRecipe, try getCount(row, at));
        for (recipes) |*recipe| recipe.* = try readRecipe(allocator, row, at, pool);
        reference.recipes = recipes;
    }
    const templates = try allocator.alloc(Template, try getCount(row, at));
    for (templates) |*template| {
        template.key = try poolText(pool, try getVar(row, at));
        template.context = try getDigest(row, at);
        template.digest = try getDigest(row, at);
    }
    return .{ .functions = functions, .records = records, .templates = templates };
}

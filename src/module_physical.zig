//! Symbolic physical inputs for separate compilation. These are real lowered
//! bodies, never semantic stand-ins; every RC proof is recomputed in the current
//! catalog. Type and function references use names so stored IDs cannot grant
//! authority in an unrelated program. Decoding remains allocation bounded.
const std = @import("std");
const codec = @import("persist_codec.zig");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");

/// One immutable symbol's physical data. Payload integrity belongs to the interface envelope.
pub const Data = struct { name: []const u8, bytes: []const u8 };
/// A module's complete physical bodies and the signature-only dependencies they name.
pub const Archive = struct {
    records: []const Data = &.{},
    functions: []const Data = &.{},
    dependencies: []const Data = &.{},
};
/// Original checked names used when writing one physical tree.
pub const Names = struct { functions: []const bytecode.Function, records: []const typed.Record };
/// All symbols must be reserved before reading any tree; a missing symbol refuses the artifact.
pub const Ids = struct {
    functions: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    records: std.StringHashMapUnmanaged(typed.Type) = .empty,
};

/// Serialize physical input references by semantic names rather than process-local IDs.
pub fn write(a: std.mem.Allocator, names: Names, value: anytype) std.mem.Allocator.Error!Data {
    var writer: codec.Writer = .init(a);
    defer writer.deinit();
    var plain = value;
    if (@TypeOf(value) == typed.Record) {
        const fields = try a.dupe(typed.Field, value.fields);
        defer a.free(fields);
        for (fields) |*field| field.default_value = null;
        plain.fields = fields;
        try writer.writeMapped(@TypeOf(value), plain, References, .{ .names = names });
    } else try writer.writeMapped(@TypeOf(value), value, References, .{ .names = names });
    return .{ .name = try a.dupe(u8, value.name), .bytes = try writer.bytes.toOwnedSlice(a) };
}

/// Restore one complete input tree against an already reserved symbol catalog.
pub fn read(a: std.mem.Allocator, ids: *const Ids, comptime T: type, data: Data) codec.DecodeError!T {
    var reader: codec.Reader = .init(a, data.bytes);
    const value = try reader.readMapped(T, References, .{ .ids = ids });
    if (!reader.done() or !std.mem.eql(u8, value.name, data.name)) return error.InvalidEncoding;
    if (T == bytecode.Function) {
        const id = ids.functions.get(data.name) orelse return error.InvalidEncoding;
        if (value.id != id) return error.InvalidEncoding;
    }
    if (T == typed.Record) for (@constCast(value.fields)) |*field| {
        field.default_value = null;
    };
    return value;
}

/// Position-independent identity of actual physical instructions and their typed locals.
pub fn digest(a: std.mem.Allocator, names: Names, value: anytype) std.mem.Allocator.Error![32]u8 {
    var writer: codec.Writer = .init(a);
    defer writer.deinit();
    try writer.writeMapped(@TypeOf(value), value, References, .{ .names = names });
    var out: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &out, .{});
    return out;
}

/// MODULE-SYMBOL-CUTOFF-1: the name of every function `value` refers to (a
/// call, a function value, an inline origin, a record's codec), in encoding
/// order and with repeats: exactly the function references `write` spells.
pub fn references(a: std.mem.Allocator, names: Names, comptime T: type, value: T) std.mem.Allocator.Error![]const []const u8 {
    const found = try referenced(a, T, value);
    const out = try a.alloc([]const u8, found.functions.len);
    for (found.functions, out) |index, *name| name.* = if (index < names.functions.len) names.functions[index].name else "";
    return out;
}

/// The functions and records one physical value refers to, by index into
/// its catalog, in encoding order and with repeats; an index outside the
/// catalog is kept as it is.
pub const Referenced = struct { functions: []const usize, records: []const usize };

/// MODULE-ARCHIVE-TRIM-1: every function and record reference `write`
/// spells in `value`.
pub fn referenced(a: std.mem.Allocator, comptime T: type, value: T) std.mem.Allocator.Error!Referenced {
    var writer: codec.Writer = .init(a);
    defer writer.deinit();
    var functions: std.ArrayList(usize) = .empty;
    var records: std.ArrayList(usize) = .empty;
    try writer.writeMapped(T, value, Collect, .{ .found = .{ .functions = &functions, .records = &records }, .allocator = a });
    return .{ .functions = functions.items, .records = records.items };
}

/// MODULE-ARCHIVE-TRIM-1: store every selected real body, a signature-only
/// dependency row for every function those bodies (and the kept records'
/// codecs) refer to, and every record the kept rows refer to, transitively.
/// A function or record nothing kept refers to is left out: a dependent's
/// restore reserves only the names the rows it reads spell.
pub fn archive(a: std.mem.Allocator, code: bytecode.Program, selected: []const bool) std.mem.Allocator.Error!Archive {
    const names: Names = .{ .functions = code.functions, .records = code.records };
    const keep_functions = try a.alloc(bool, code.functions.len);
    @memset(keep_functions, false);
    const keep_records = try a.alloc(bool, code.records.len);
    @memset(keep_records, false);
    var pending_functions: std.ArrayList(usize) = .empty;
    var pending_records: std.ArrayList(usize) = .empty;
    for (selected, 0..) |chosen, index| if (chosen and index < code.functions.len) {
        keep_functions[index] = true;
        try pending_functions.append(a, index);
    };
    var whole = false;
    while (!whole and (pending_functions.items.len != 0 or pending_records.items.len != 0)) {
        var found: Referenced = .{ .functions = &.{}, .records = &.{} };
        if (pending_functions.pop()) |index| {
            found = try referenced(a, bytecode.Function, row(code.functions[index], index < selected.len and selected[index]));
        } else if (pending_records.pop()) |index| {
            var plain = code.records[index];
            const fields = try a.dupe(typed.Field, plain.fields);
            for (fields) |*field| field.default_value = null;
            plain.fields = fields;
            found = try referenced(a, typed.Record, plain);
        }
        for (found.functions) |index| {
            if (index >= keep_functions.len) whole = true;
            if (whole or keep_functions[index]) continue;
            keep_functions[index] = true;
            try pending_functions.append(a, index);
        }
        for (found.records) |index| {
            if (index >= keep_records.len) whole = true;
            if (whole or keep_records[index]) continue;
            keep_records[index] = true;
            try pending_records.append(a, index);
        }
    }
    // A reference outside the catalog cannot be followed: keep every row.
    if (whole) {
        @memset(keep_functions, true);
        @memset(keep_records, true);
    }
    var records: std.ArrayList(Data) = .empty;
    for (code.records, keep_records) |record, kept| if (kept) try records.append(a, try write(a, names, record));
    var bodies: std.ArrayList(Data) = .empty;
    var dependencies: std.ArrayList(Data) = .empty;
    for (code.functions, keep_functions, 0..) |function, kept, index| {
        if (!kept) continue;
        const chosen = index < selected.len and selected[index];
        const data = try write(a, names, row(function, chosen));
        if (chosen) try bodies.append(a, data) else try dependencies.append(a, data);
    }
    return .{ .records = records.items, .functions = bodies.items, .dependencies = dependencies.items };
}

/// The value one archive row stores for `function`: its body when it is
/// emitted, its signature otherwise, never its imported facts.
fn row(function: bytecode.Function, chosen: bool) bytecode.Function {
    var plain = function;
    plain.physical = null;
    if (!chosen) plain.scope.instructions = &.{};
    return plain;
}

/// The reference fields `References` encodes, with every function and
/// record reference collected by catalog index instead of written.
const Collect = struct {
    found: struct { functions: *std.ArrayList(usize), records: *std.ArrayList(usize) },
    allocator: std.mem.Allocator,

    /// The same reference-bearing fields `References` handles.
    pub fn handles(comptime T: type) bool {
        return References.handles(T);
    }

    /// Record a function or record reference; every other reference names
    /// neither.
    pub fn encode(self: Collect, _: *codec.Writer, comptime T: type, value: T) std.mem.Allocator.Error!void {
        if (T == typed.FunctionId) try self.found.functions.append(self.allocator, @backingInt(value));
        if (T == typed.Type) if (value.isAggregate()) try self.found.records.append(self.allocator, value.recordIndex());
    }
};

/// The only reference-bearing physical fields with a supported stable encoding.
const References = struct {
    names: ?Names = null,
    ids: ?*const Ids = null,

    /// Identify the physical reference types that need stable symbol resolution.
    pub fn handles(comptime T: type) bool {
        return T == typed.Type or T == typed.FunctionId or T == @import("source.zig").Span or
            T == ?*const bytecode.Physical or T == *const typed.Blob;
    }

    /// Encode only explicitly supported physical references.
    pub fn encode(self: References, writer: *codec.Writer, comptime T: type, value: T) std.mem.Allocator.Error!void {
        const names = self.names.?;
        if (T == typed.Type) {
            try writer.integer(@as(u64, if (value.isAggregate()) typed.Type.record_base else @backingInt(value)));
            if (value.isAggregate()) try writer.write([]const u8, names.records[value.recordIndex()].name);
        } else if (T == typed.FunctionId) {
            try writer.write([]const u8, names.functions[@backingInt(value)].name);
        } else if (T == *const typed.Blob) {
            try writer.write(typed.Blob, value.*);
        }
    }

    /// Resolve references and refuse missing catalog authority.
    pub fn decode(self: References, reader: *codec.Reader, comptime T: type) codec.DecodeError!T {
        const ids = self.ids.?;
        if (T == typed.Type) {
            const tag = try reader.integer(u64);
            if (tag < typed.Type.record_base) return @fromBackingInt(tag);
            if (tag != typed.Type.record_base) return error.InvalidEncoding;
            const name = try reader.read([]const u8);
            return ids.records.get(name) orelse error.InvalidEncoding;
        }
        if (T == typed.FunctionId) {
            const name = try reader.read([]const u8);
            return ids.functions.get(name) orelse error.InvalidEncoding;
        }
        if (T == *const typed.Blob) {
            const blob = try reader.allocator.create(typed.Blob);
            blob.* = try reader.read(typed.Blob);
            return blob;
        }
        if (T == @import("source.zig").Span) return .{ .start = 0, .end = 0 };
        if (T == ?*const bytecode.Physical) return null;
        unreachable;
    }
};

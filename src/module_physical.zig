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

/// Store every selected real body and signatures for every dependency it names.
pub fn archive(a: std.mem.Allocator, code: bytecode.Program, selected: []const bool) std.mem.Allocator.Error!Archive {
    const names: Names = .{ .functions = code.functions, .records = code.records };
    const records = try a.alloc(Data, code.records.len);
    for (code.records, records) |record, *data| data.* = try write(a, names, record);
    var bodies: std.ArrayList(Data) = .empty;
    var dependencies: std.ArrayList(Data) = .empty;
    for (code.functions, selected) |function, chosen| {
        var plain = function;
        plain.physical = null;
        if (chosen) {
            try bodies.append(a, try write(a, names, plain));
        } else {
            plain.scope.instructions = &.{};
            try dependencies.append(a, try write(a, names, plain));
        }
    }
    return .{ .records = records, .functions = bodies.items, .dependencies = dependencies.items };
}

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

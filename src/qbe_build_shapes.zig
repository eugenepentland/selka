//! Shared native byte-layout rendering for copied wire and domain adapters.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const Value = std.json.Value;
/// Invalid compiler manifest or failed generated-source write.
pub const Error = error{ InvalidManifest, WriteFailed };
/// A native type table and the ordinary table whose C declarations are shared.
pub const Shapes = struct {
    types: []const Value,
    ordinary: []const Value = &.{},
    codecs: bool = false,
    /// The native descriptor symbol of each `types` entry, position for
    /// position. Absent on the ordinary manifest, which carries no list.
    descriptors: []const Value = &.{},

    /// Find a canonical type in this manifest.
    pub fn index(self: Shapes, name: []const u8) Error!usize {
        return find(self.types, name) orelse error.InvalidManifest;
    }
    /// Read the native storage size of a named type.
    pub fn size(self: Shapes, name: []const u8) Error!u64 {
        return v.number(v.get(self.types[try self.index(name)], "size"));
    }
    /// Identify scalar storage, including domain representations.
    pub fn scalar(self: Shapes, name: []const u8) Error!bool {
        var index_value = try self.index(name);
        for (0..self.types.len) |_| {
            const item = self.types[index_value];
            const kind = v.text(v.get(item, "kind"));
            if (!std.mem.eql(u8, kind, "domain")) return std.mem.eql(u8, kind, "scalar");
            const fields = v.array(v.get(item, "fields"));
            if (fields.len != 1) return error.InvalidManifest;
            index_value = try self.index(v.text(v.get(fields[0], "type")));
        }
        return error.InvalidManifest;
    }
    /// Render the C type matching a direct guest ABI value.
    pub fn ctype(self: Shapes, w: *std.Io.Writer, name: []const u8) Error!void {
        if (try self.scalar(name)) return w.writeAll("uint64_t");
        if (!self.codecs) return w.print("WireValue{d}", .{try self.index(name)});
        if (find(self.ordinary, name)) |index_value| return w.print("WireValue{d}", .{index_value});
        try w.print("CodecValue{d}", .{try self.index(name)});
    }
    /// Check whether the copied ABI supports every public signature position.
    pub fn supported(self: Shapes, item: Value) bool {
        if (v.boolean(v.get(item, "references"))) return false;
        if (find(self.types, v.text(v.get(item, "result"))) == null) return false;
        for (v.array(v.get(item, "parameters"))) |parameter| if (find(self.types, v.text(parameter)) == null) return false;
        return true;
    }
    /// Select the usesVector argument vector beyond the bounded direct ABI budget.
    pub fn usesVector(self: Shapes, parameters: []const Value) Error!bool {
        if (parameters.len > 128) return true;
        var bytes: u64 = 0;
        for (parameters) |parameter| {
            const size_value = try self.size(v.text(parameter));
            bytes += if (size_value > 4096 or try self.scalar(v.text(parameter))) 8 else std.mem.alignForward(u64, @max(8, size_value), 8);
            if (bytes > 4096) return true;
        }
        return false;
    }
    /// Declare the aggregate byte containers used by native C calls.
    pub fn typedefs(self: Shapes, w: *std.Io.Writer) Error!void {
        for (self.types, 0..) |item, i| {
            const name = v.text(v.get(item, "name"));
            if (try self.index(name) != i) return error.InvalidManifest;
            if (try self.scalar(name)) continue;
            if (self.codecs and find(self.ordinary, name) != null) continue;
            try w.print("typedef struct {{ _Alignas({d}) unsigned char bytes[{d}]; }} ", .{ v.number(v.get(item, "alignment")), @max(1, try self.size(name)) });
            try self.ctype(w, name);
            try w.writeAll(";\n");
        }
    }
    /// Declare and tabulate the native descriptor of every manifest entry,
    /// position for position, so the generated adapter hands the runtime the
    /// `myl_native_type` the program already publishes for that type instead of
    /// synthesizing a second descriptor that could drift from the collector's.
    /// A manifest carrying a list without this table is refused: an absent
    /// descriptor would reach the allocator as a null type rather than as a
    /// shape the collector can trace.
    pub fn descriptorTable(self: Shapes, w: *std.Io.Writer) Error!void {
        if (self.descriptors.len != 0 and self.descriptors.len != self.types.len) return error.InvalidManifest;
        if (self.descriptors.len == 0) for (self.types) |item| {
            if (try kindNumber(v.text(v.get(item, "kind"))) == list_kind) return error.InvalidManifest;
        };
        for (self.descriptors) |item| try w.print("extern const myl_native_type {s};\n", .{v.text(item)});
        try w.writeAll("static const myl_native_type *const co_native_types[]={\n");
        for (self.descriptors) |item| try w.print("&{s},\n", .{v.text(item)});
        if (self.descriptors.len == 0) try w.writeAll("NULL,\n");
        try w.writeAll("};\n");
    }
    /// Emit the common native layout fields of one conversion schema.
    pub fn schema(self: Shapes, w: *std.Io.Writer, item: Value) Error!void {
        try w.writeByte('{');
        try v.quote(w, v.text(v.get(item, "name")));
        const fields = v.array(v.get(item, "fields"));
        const kind = try kindNumber(v.text(v.get(item, "kind")));
        // A text and a list are each described by exactly one element field: the
        // type the wire carries one node per. Anything else is a malformed
        // manifest the generated adapter must refuse rather than walk off its
        // field table.
        if ((kind == 5 or kind == list_kind) and fields.len != 1) return error.InvalidManifest;
        // An array's, a text's and a list's element count is carried by the
        // manifest itself — zero for the two variable-length kinds. For every
        // other aggregate the field table is the count.
        const count = if (kind == 2 or kind == 5 or kind == list_kind) v.number(v.get(item, "count")) else fields.len;
        try w.print(",{d},{d},{d},{d},", .{ v.number(v.get(item, "size")), count, v.number(v.get(item, "stride")), kind });
        try self.renderFields(w, fields, false);
        try w.writeByte(',');
        try self.renderFields(w, fields, true);
    }
    fn renderFields(self: Shapes, w: *std.Io.Writer, entries: []const Value, offsets: bool) Error!void {
        if (entries.len == 0) return w.writeAll("NULL");
        try w.writeAll("(const size_t[]){");
        for (entries, 0..) |field, i| {
            if (i != 0) try w.writeByte(',');
            if (offsets) {
                try w.print("{d}", .{v.number(v.get(field, "offset"))});
            } else if (v.get(field, "type") == .null) {
                try w.writeAll("SIZE_MAX");
            } else try w.print("{d}", .{try self.index(v.text(v.get(field, "type")))});
        }
        try w.writeByte('}');
    }
    /// Whether one argument of this type crosses the native ABI as the address
    /// of the caller's storage, exactly as the compiler's emitter decided it.
    /// The manifest records the decision, so the adapter never re-derives the
    /// QBE-AGGREF-1 rule from the type's shape. A manifest without the fact is
    /// an older or incompatible one — its IL may have crossed either way — so
    /// it is refused instead of being read as the pre-fix by-value answer.
    pub fn byAddress(self: Shapes, name: []const u8) Error!bool {
        const value = v.get(self.types[try self.index(name)], "by_address");
        if (value != .bool) return error.InvalidManifest;
        return value.bool;
    }
    /// Declare a compiled function with large-result and usesVector-argument conventions.
    pub fn declaration(self: Shapes, w: *std.Io.Writer, symbol: []const u8, result: []const u8, parameters: []const Value) Error!void {
        const large = try self.size(result) > 4096;
        try w.writeAll("extern ");
        if (large) try w.writeAll("uint64_t") else try self.ctype(w, result);
        try w.print(" {s}(void *", .{symbol});
        if (large) try w.writeAll(", void *");
        if (try self.usesVector(parameters)) {
            try w.writeAll(", const uint64_t *");
        } else for (parameters) |parameter| {
            try w.writeAll(", ");
            const name = v.text(parameter);
            if (try self.byAddress(name)) try w.writeAll("const void *") else try self.ctype(w, name);
        }
        try w.writeAll(");\n");
    }
    /// Read one native argument using the selected copied ABI's input buffers.
    pub fn argument(self: Shapes, w: *std.Io.Writer, name: []const u8, i: usize, packed_value: bool) Error!void {
        const prefix = if (self.codecs) "co" else "wire";
        if (try self.scalar(name)) {
            if (self.codecs) {
                try w.print("co_word(co_arguments[{d}],{d})", .{ i, try self.index(name) });
            } else try w.print("wire_word(wire_arguments[{d}],&wire_types[{d}])", .{ i, try self.index(name) });
        } else if (packed_value or try self.byAddress(name)) {
            if (packed_value) try w.writeAll("(uint64_t)(uintptr_t)");
            try w.print("{s}_arguments[{d}]", .{ prefix, i });
        } else {
            try w.writeAll("*(");
            try self.ctype(w, name);
            try w.print(" *){s}_arguments[{d}]", .{ prefix, i });
        }
    }
};

/// Look up an optional canonical layout without allocating a name map.
pub fn find(types: []const Value, name: []const u8) ?usize {
    for (types, 0..) |item, index_value| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return index_value;
    return null;
}
/// Manifest kind names in their stable numeric order; the index is the number
/// the generated adapter switches on.
const kind_names = [_][]const u8{ "scalar", "record", "array", "variant", "domain", "text", "list" };
/// The manifest kind number of a user list, carried as one wire node per element.
const list_kind: u8 = 6;
fn kindNumber(name: []const u8) Error!u8 {
    for (kind_names, 0..) |kind, i| if (std.mem.eql(u8, name, kind)) return @intCast(i);
    return error.InvalidManifest;
}

test "native ABI vector budgets and domain scalar storage" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(Value, allocator,
        \\[{"name":"i64","kind":"scalar","size":8},{"name":"Domain","kind":"domain","size":8,"fields":[{"type":"i64"}]},{"name":"Array","kind":"array","size":1024},{"name":"Large","kind":"array","size":8192}]
    , .{});
    defer parsed.deinit();
    const shapes: Shapes = .{ .types = v.array(parsed.value) };
    const word: Value = .{ .string = "i64" };
    const array_type: Value = .{ .string = "Array" };
    const large: Value = .{ .string = "Large" };
    try std.testing.expect(try shapes.scalar("Domain"));
    try std.testing.expect(!try shapes.usesVector(&.{ array_type, array_type, array_type, array_type }));
    try std.testing.expect(try shapes.usesVector(&.{ array_type, array_type, array_type, array_type, array_type }));
    try std.testing.expect(!try shapes.usesVector(&.{ large, word }));
    const many: [129]Value = @splat(word);
    try std.testing.expect(try shapes.usesVector(&many));
    try std.testing.expectError(error.InvalidManifest, shapes.index("absent"));
}

// spec: QBE-AGGREF-7
test "the adapter refuses a manifest that omits a type's recorded crossing" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(Value, allocator,
        \\[{"name":"i64","kind":"scalar","size":8,"alignment":8,"by_address":false},
        \\ {"name":"Record","kind":"record","size":8,"alignment":8,"by_address":true},
        \\ {"name":"Older","kind":"record","size":8,"alignment":8}]
    , .{});
    defer parsed.deinit();
    const shapes: Shapes = .{ .types = v.array(parsed.value) };
    // A recorded "no" is a fact, a recorded "yes" is a fact, and an absent
    // `by_address` is missing information this adapter must not guess at: the
    // old default read it as the pre-fix by-value convention.
    try std.testing.expect(!try shapes.byAddress("i64"));
    try std.testing.expect(try shapes.byAddress("Record"));
    try std.testing.expectError(error.InvalidManifest, shapes.byAddress("Older"));
}

//! Versioned, bounded JSON serialization for checked ordinary language values.
const std = @import("std");
const typed = @import("typed.zig");
const Type = typed.Type;
const Value = typed.Value;
const Json = std.json.Value;
pub const Limits = struct {
    max_bytes: usize = 1024 * 1024,
    max_values: usize = 65536,
    max_tokens: usize = 262144,
    max_depth: u8 = 64,
    fn check(self: Limits) !void {
        if (self.max_bytes == 0 or self.max_values == 0 or self.max_tokens == 0 or self.max_depth == 0 or self.max_depth > 128) return error.InvalidCodecLimits;
    }
};
pub const Envelope = struct { version: []const u8, type: []const u8, value: Json };
pub const Document = struct {
    parsed: std.json.Parsed(Envelope),
    limits: Limits,
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) !Document {
        try limits.check();
        try scan(allocator, bytes, limits);
        const parsed = try std.json.parseFromSlice(Envelope, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false });
        errdefer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.version, "typed-json-v1")) return error.UnsupportedCodecVersion;
        return .{ .parsed = parsed, .limits = limits };
    }
    pub fn deinit(self: *Document) void {
        self.parsed.deinit();
    }
    /// The result owns its storage independently of the parsed document. Release
    /// it with the same allocator. Result-handling obligations still apply when
    /// handing this value to a language execution context.
    pub fn decode(self: Document, allocator: std.mem.Allocator, records: []const typed.Record, ty: Type) !Value {
        try checkType(allocator, records, ty);
        if (!std.mem.eql(u8, self.parsed.value.type, typed.typeName(ty, records))) return error.ValueTypeMismatch;
        var decoder: Decoder = .{ .allocator = allocator, .records = records, .budget = .{ .limits = self.limits } };
        return decoder.value(ty, self.parsed.value.value, 1);
    }
};
// Scan before building a JSON DOM: even invalid/unused subtrees are subject to
// depth/token bounds. next() returns string fragments without allocating strings.
fn scan(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) !void {
    if (bytes.len > limits.max_bytes) return error.CodecByteLimit;
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var depth: usize = 0;
    var tokens: usize = 0;
    while (true) {
        const token = try scanner.next();
        if (token == .end_of_document) break;
        if (tokens == limits.max_tokens) return error.CodecTokenLimit;
        tokens += 1;
        switch (token) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > @as(usize, limits.max_depth) + 1) return error.CodecDepthLimit;
            },
            .object_end, .array_end => depth -= 1,
            else => {},
        }
    }
}
/// Requires the complete selected type graph to have an implicit codec. An
/// unselected union arm or zero-length array cannot hide an opaque dependency.
pub fn checkType(allocator: std.mem.Allocator, records: []const typed.Record, root: Type) !void {
    var pending: std.ArrayList(Type) = .empty;
    defer pending.deinit(allocator);
    const seen = try allocator.alloc(bool, Type.record_base + records.len);
    defer allocator.free(seen);
    @memset(seen, false);
    try pending.append(allocator, root);
    while (pending.pop()) |ty| {
        if (@backingInt(ty) >= seen.len) return error.InvalidCodecType;
        if (seen[@backingInt(ty)]) continue;
        seen[@backingInt(ty)] = true;
        if (ty.isInteger() or ty == .bool) continue;
        if (!ty.isAggregate()) return error.NoImplicitCodec;
        const record = records[ty.recordIndex()];
        if (record.domain != null or record.buffer != null or record.resource != null or record.pool != null or record.handle_pool != null or record.move_only) return error.NoImplicitCodec;
        if (record.array) |array| {
            try pending.append(allocator, array.element);
            if (array.key) |key| try pending.append(allocator, key);
        } else if (record.variants) |variants| {
            for (variants.cases) |case| if (case.payload) |payload| try pending.append(allocator, payload);
        } else for (record.fields) |field| try pending.append(allocator, field.ty);
    }
}
const Budget = struct {
    limits: Limits,
    values: usize = 0,
    fn take(self: *Budget, depth: usize) !void {
        if (depth > self.limits.max_depth) return error.CodecDepthLimit;
        if (self.values == self.limits.max_values) return error.CodecValueLimit;
        self.values += 1;
    }
};
fn integer(ty: Type, text: []const u8) !Value {
    const number = ty.parseDecimal(text) catch |err| return switch (err) {
        error.InvalidInteger => error.InvalidCodecInteger,
        error.IntegerOutOfRange => error.CodecIntegerOutOfRange,
    };
    return Value.number(ty, number);
}
fn tagFor(cases: []const typed.Variant, name: []const u8) !usize {
    for (cases, 0..) |case, tag| if (std.mem.eql(u8, case.name, name)) return tag;
    return error.UnknownCodecCase;
}
const Decoder = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    budget: Budget,
    fn value(self: *Decoder, ty: Type, json: Json, depth: usize) anyerror!Value {
        try self.budget.take(depth);
        if (ty.isInteger()) return if (json == .string) integer(ty, json.string) else error.ValueTypeMismatch;
        if (ty == .bool) return if (json == .bool) .{ .bool = json.bool } else error.ValueTypeMismatch;
        const record = self.records[ty.recordIndex()];
        if (record.variants) |variants| {
            if (!variants.is_union) {
                if (json != .string) return error.ValueTypeMismatch;
                return Value.createVariant(self.allocator, ty, try tagFor(variants.cases, json.string), null);
            }
            if (json != .object) return error.ValueTypeMismatch;
            const case = json.object.get("case") orelse return error.IncompleteCodecValue;
            if (case != .string) return error.ValueTypeMismatch;
            const tag = try tagFor(variants.cases, case.string);
            if (variants.cases[tag].payload) |payload_type| {
                const payload = json.object.get("value") orelse return error.IncompleteCodecValue;
                if (json.object.count() != 2) return error.UnexpectedCodecField;
                const decoded = try self.value(payload_type, payload, depth + 1);
                defer decoded.release(self.allocator);
                return Value.createVariant(self.allocator, ty, tag, decoded);
            }
            if (json.object.count() != 1) return error.UnexpectedCodecField;
            return Value.createVariant(self.allocator, ty, tag, null);
        }
        const count = record.count();
        const array = record.array;
        const positional = array != null and array.?.key == null;
        if (positional) {
            if (json != .array) return error.ValueTypeMismatch;
            if (json.array.items.len != count) return error.IncompleteCodecValue;
        } else {
            if (json != .object) return error.ValueTypeMismatch;
            if (json.object.count() < count) return error.IncompleteCodecValue;
            if (json.object.count() > count) return error.UnexpectedCodecField;
        }
        // Reject expansive schemas before allocating the materialization buffer.
        if (count > self.budget.limits.max_values - self.budget.values) return error.CodecValueLimit;
        const fields = try self.allocator.alloc(Value, count);
        var initialized: usize = 0;
        defer {
            for (fields[0..initialized]) |field| field.release(self.allocator);
            self.allocator.free(fields);
        }
        for (fields, 0..) |*field, index| {
            const child = if (positional) json.array.items[index] else json.object.get(if (array) |a| self.records[a.key.?.recordIndex()].variants.?.cases[index].name else record.fields[index].name) orelse return error.IncompleteCodecValue;
            field.* = try self.value(record.elementType(index), child, depth + 1);
            initialized += 1;
        }
        return Value.create(self.allocator, ty, fields);
    }
};
const Encoder = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    budget: Budget,
    fn value(self: *Encoder, ty: Type, input: Value, depth: usize) anyerror!Json {
        try self.budget.take(depth);
        if (input.typeOf() != ty) return error.ValueTypeMismatch;
        if (ty.isInteger()) {
            const number = try input.asInteger();
            if (!ty.fits(number)) return error.CodecIntegerOutOfRange;
            return .{ .string = try std.fmt.allocPrint(self.allocator, "{d}", .{number}) };
        }
        if (ty == .bool) return if (input == .bool) .{ .bool = input.bool } else error.InvalidCodecValue;
        if (input != .aggregate or input.aggregate.moved_fields != null) return error.InvalidCodecValue;
        const record = self.records[ty.recordIndex()];
        const fields = input.aggregate.fields;
        if (record.variants) |variants| {
            const tag = input.aggregate.active_tag orelse return error.InvalidCodecValue;
            if (tag >= variants.cases.len) return error.InvalidCodecValue;
            const case = variants.cases[tag];
            if (fields.len != @intFromBool(case.payload != null)) return error.InvalidCodecValue;
            if (!variants.is_union) return .{ .string = case.name };
            var object: std.json.ObjectMap = .empty;
            try object.put(self.allocator, "case", .{ .string = case.name });
            if (case.payload) |payload| try object.put(self.allocator, "value", try self.value(payload, fields[0], depth + 1));
            return .{ .object = object };
        }
        if (input.aggregate.active_tag != null or fields.len != record.count()) return error.InvalidCodecValue;
        if (fields.len > self.budget.limits.max_values - self.budget.values) return error.CodecValueLimit;
        if (record.array) |array| {
            if (array.key == null) {
                var output = std.json.Array.init(self.allocator);
                for (fields) |field| try output.append(try self.value(array.element, field, depth + 1));
                return .{ .array = output };
            }
        }
        var output: std.json.ObjectMap = .empty;
        for (fields, 0..) |field, index| {
            const name = if (record.array) |array| self.records[array.key.?.recordIndex()].variants.?.cases[index].name else record.fields[index].name;
            try output.put(self.allocator, name, try self.value(record.elementType(index), field, depth + 1));
        }
        return .{ .object = output };
    }
};
/// Borrows input without changing its ownership. Returns an owned canonical
/// envelope. The complete type must have an implicit codec in both directions.
pub fn encode(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, input: Value, limits: Limits) ![]u8 {
    try limits.check();
    try checkType(allocator, records, ty);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var encoder: Encoder = .{ .allocator = arena.allocator(), .records = records, .budget = .{ .limits = limits } };
    const document: Envelope = .{ .version = "typed-json-v1", .type = typed.typeName(ty, records), .value = try encoder.value(ty, input, 1) };
    var counter = std.Io.Writer.Discarding.init(&.{});
    std.json.Stringify.value(document, .{}, &counter.writer) catch unreachable;
    if (counter.fullCount() > limits.max_bytes) return error.CodecByteLimit;
    const text = try std.json.Stringify.valueAlloc(allocator, document, .{});
    errdefer allocator.free(text);
    // Match parser token/depth limits, including escaped names and envelope.
    try scan(allocator, text, limits);
    return text;
}

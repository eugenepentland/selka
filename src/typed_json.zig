//! Versioned, bounded JSON serialization for checked ordinary language values.
const wire_version = "typed-json-v1";
/// Failures returned by check; callers must handle these boundary errors.
pub const CheckError = error{
    InvalidCodecLimits,
};
/// Failures returned by parse; callers must handle these boundary errors.
pub const ParseError = error{
    InternalError,
    CodecByteLimit,
    CodecDepthLimit,
    CodecTokenLimit,
    DuplicateField,
    InvalidCharacter,
    InvalidCodecLimits,
    InvalidNumber,
    MissingField,
    OutOfMemory,
    Overflow,
    SyntaxError,
    UnexpectedEndOfInput,
    UnexpectedToken,
    UnknownField,
    UnsupportedCodecVersion,
};
/// Failures returned by scanRequest; callers must handle these boundary errors.
pub const ScanRequestError = error{
    InternalError,
    CodecByteLimit,
    CodecDepthLimit,
    CodecTokenLimit,
    InvalidCodecLimits,
    OutOfMemory,
    SyntaxError,
    UnexpectedEndOfInput,
};
/// Failures returned by checkType; callers must handle these boundary errors.
pub const CheckTypeError = error{
    InvalidCodecType,
    InvalidDataType,
    NoImplicitCodec,
    NotDataType,
    OutOfMemory,
};

/// Wire validation and domain execution failures during typed value conversion.
pub const ValueError = @import("codec_execution.zig").DecodeError || CheckTypeError || ScanRequestError || error{
    CodecByteLimit,
    CodecDepthLimit,
    CodecIntegerOutOfRange,
    CodecValueLimit,
    CodecWorkLimit,
    IncompleteCodecValue,
    InvalidCodecInteger,
    InvalidCodecLimits,
    InvalidCodecValue,
    UnexpectedCodecField,
    UnknownCodecCase,
};

const std = @import("std");
const typed = @import("typed.zig");
const Type = typed.Type;
const Value = typed.Value;
const Json = std.json.Value;
const Execution = @import("codec_execution.zig").Execution;
const Part = union(enum) { key: []const u8, index: usize };
/// Owned diagnostic prefix: independent of document/catalog lifetimes. Path capture
/// allocates nothing and never replaces a data failure with an allocation failure.
pub const Location = struct {
    buffer: [4096]u8 = undefined,
    len: usize = 0,
    has_path: bool = false,
    truncated: bool = false,
    /// Borrow the currently recorded JSON pointer identifying a conversion failure.
    pub fn text(self: *const Location) []const u8 {
        return self.buffer[0..self.len];
    }
    /// Replace the current JSON pointer with one root field location.
    pub fn field(self: *Location, name: []const u8) void {
        self.capture(&.{.{ .key = name }});
    }
    fn append(self: *Location, bytes: []const u8) bool {
        if (bytes.len > self.buffer.len - self.len) {
            self.truncated = true;
            while (self.len > 0 and !std.unicode.utf8ValidateSlice(self.buffer[0..self.len])) self.len -= 1;
            return false;
        }
        @memcpy(self.buffer[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
        return true;
    }
    fn capture(self: *Location, parts: []const Part) void {
        self.len = 0;
        self.has_path = true;
        self.truncated = false;
        for (parts) |part| {
            if (!self.append("/")) return;
            var digits: [32]u8 = undefined;
            const key = switch (part) {
                .key => |key| key,
                .index => |index| std.fmt.bufPrint(&digits, "{d}", .{index}) catch {
                    self.truncated = true;
                    return;
                },
            };
            for (key) |byte| {
                if (!self.append(if (byte == '~') "~0" else if (byte == '/') "~1" else &.{byte})) return;
            }
        }
    }
};
const Trace = struct {
    location: ?*Location,
    parts: [130]Part = undefined,
    len: usize = 1,
    fn init(location: ?*Location) Trace {
        var trace: Trace = .{ .location = location };
        trace.parts[0] = .{ .key = "value" };
        return trace;
    }
    fn push(self: *Trace, part: Part) void {
        self.parts[self.len] = part;
        self.len += 1;
    }
    fn pop(self: *Trace) void {
        self.len -= 1;
    }
    fn failure(self: *Trace, err: anyerror) void {
        if (err == error.OutOfMemory) return;
        if (self.location) |location| if (!location.has_path) location.capture(self.parts[0..self.len]);
    }
    fn at(self: *Trace, part: Part, err: ValueError) ValueError {
        self.push(part);
        defer self.pop();
        self.failure(err);
        return err;
    }
};
fn checkLocatedType(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, location: ?*Location) !void {
    checkType(allocator, records, ty) catch |err| {
        if (err != error.OutOfMemory) if (location) |out| out.field("type");
        return err;
    };
}
/// Bounds on input bytes, tokens, traversed values, and JSON nesting depth.
pub const Limits = struct {
    max_bytes: usize = 1024 * 1024,
    max_values: usize = 65536,
    max_tokens: usize = 262144,
    max_depth: u8 = 64,
    /// Reject invalid or unsupported JSON traversal limits before processing input.
    pub fn check(self: Limits) CheckError!void {
        const empty_budget = self.max_bytes == 0 or self.max_values == 0 or self.max_tokens == 0;
        if (empty_budget or self.max_depth == 0 or self.max_depth > 128) return error.InvalidCodecLimits;
    }
};
/// Versioned typed JSON value with its fully qualified type identity.
pub const Envelope = struct { version: []const u8, type: []const u8, value: Json };
/// Parsed typed JSON envelope owning its parse allocations and traversal limits.
pub const Document = struct {
    parsed: std.json.Parsed(Envelope),
    limits: Limits,
    /// Parse a bounded typed JSON envelope and validate its structural identity.
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) ParseError!Document {
        return parseWithLocation(allocator, bytes, limits, null);
    }
    /// Parse a bounded envelope while recording the JSON pointer of a failure.
    pub fn parseWithLocation(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, location: ?*Location) ParseError!Document {
        if (location) |out| out.* = .{};
        try limits.check();
        try scan(allocator, bytes, limits);
        // parseFromSlice supplies complete input and uses its length as max_value_len.
        // These concrete documents contain no fixed-size arrays; generic parser-only
        // failures indicate an internal contract mismatch, not a caller input category.
        const parsed = std.json.parseFromSlice(Envelope, allocator, bytes, .{ .allocate = .alloc_always, .parse_numbers = false }) catch |err| switch (err) {
            error.BufferUnderrun, error.LengthMismatch, error.ValueTooLong, error.InvalidEnumTag => return error.InternalError,
            else => |failure| return failure,
        };
        errdefer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.version, wire_version)) {
            if (location) |out| out.field("version");
            return error.UnsupportedCodecVersion;
        }
        return .{ .parsed = parsed, .limits = limits };
    }
    pub fn deinit(self: *Document) void {
        self.parsed.deinit();
    }
    /// The result owns its storage independently of the parsed document. Release
    /// it with the same allocator. Result-handling obligations still apply when
    /// handing this value to a language execution context.
    pub fn decode(self: Document, allocator: std.mem.Allocator, records: []const typed.Record, ty: Type) ValueError!Value {
        return self.decodeWithLocation(allocator, records, ty, null);
    }
    /// Allocate a checked ordinary value and locate schema/value conversion failures.
    pub fn decodeWithLocation(self: Document, allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, location: ?*Location) ValueError!Value {
        if (location) |out| out.* = .{};
        try self.limits.check();
        try checkLocatedType(allocator, records, ty, location);
        if (!std.mem.eql(u8, self.parsed.value.type, typed.typeName(ty, records))) {
            if (location) |out| out.field("type");
            return error.ValueTypeMismatch;
        }
        var budget: Budget = .{ .limits = self.limits };
        var decoder: Decoder = .{ .allocator = allocator, .records = records, .budget = &budget, .trace = .init(location) };
        return decoder.value(ty, self.parsed.value.value, 1);
    }
    /// Internal operation entry: the caller shares traversal/execution budgets.
    pub fn decodeWithCodecs(self: Document, allocator: std.mem.Allocator, execution: *Execution, ty: Type, budget: *Budget, location: *Location) ValueError!Value {
        const records = execution.program.records;
        location.* = .{};
        try checkCodecType(allocator, records, ty, location);
        if (!std.mem.eql(u8, self.parsed.value.type, typed.typeName(ty, records))) {
            location.field("type");
            return error.ValueTypeMismatch;
        }
        var decoder: Decoder = .{ .allocator = allocator, .records = records, .budget = budget, .execution = execution, .trace = .init(location) };
        return decoder.value(ty, self.parsed.value.value, 1);
    }
};
/// Decode one named argument while sharing the operation's counters.
pub fn decodeArgument(allocator: std.mem.Allocator, execution: *Execution, argument: Argument, budget: *Budget, location: *Location) ValueError!Value {
    var trace = Trace.init(location);
    trace.parts[0] = .{ .key = "arguments" };
    trace.parts[1] = .{ .key = argument.name };
    trace.len = 2;
    var decoder: Decoder = .{ .allocator = allocator, .records = execution.program.records, .execution = execution, .budget = budget, .trace = trace };
    return decoder.value(argument.ty, argument.value, 1);
}
// Scan before building a JSON DOM: even invalid/unused subtrees are subject to
// depth/token bounds. next() returns string fragments without allocating strings.
fn scan(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) !void {
    return scanDepth(allocator, bytes, limits, @as(usize, limits.max_depth) + 1);
}
/// Validate JSON syntax and resource bounds with allowance for the call request envelope.
pub fn scanRequest(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) ScanRequestError!void {
    try limits.check();
    return scanDepth(allocator, bytes, limits, @as(usize, limits.max_depth) + 2);
}
fn scanDepth(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits, container_depth: usize) !void {
    if (bytes.len > limits.max_bytes) return error.CodecByteLimit;
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var depth: usize = 0;
    var tokens: usize = 0;
    while (true) {
        // Complete-input scanners cannot request another input buffer.
        const token = scanner.next() catch |err| switch (err) {
            error.BufferUnderrun => return error.InternalError,
            else => |scan_error| return scan_error,
        };
        if (token == .end_of_document) break;
        if (tokens == limits.max_tokens) return error.CodecTokenLimit;
        tokens += 1;
        switch (token) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > container_depth) return error.CodecDepthLimit;
            },
            .object_end, .array_end => depth -= 1,
            else => {},
        }
    }
}
/// Requires the complete selected type graph to have an implicit codec. An
/// unselected union arm or zero-length array cannot hide an opaque dependency.
pub fn checkType(allocator: std.mem.Allocator, records: []const typed.Record, root: Type) CheckTypeError!void {
    @import("data_type.zig").check(allocator, records, root, false) catch |err| return switch (err) {
        error.InvalidDataType => error.InvalidCodecType,
        error.NotDataType => error.NoImplicitCodec,
        else => err,
    };
}

fn checkCodecType(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, location: *Location) !void {
    @import("data_type.zig").checkCodecs(allocator, records, ty) catch |err| {
        if (err != error.OutOfMemory) location.field("type");
        return switch (err) {
            error.NotDataType => error.NoImplicitCodec,
            error.InvalidDataType => error.InvalidCodecType,
            else => err,
        };
    };
}

/// Shared value traversal count across input and output conversion directions.
pub const WorkBudget = struct { limit: usize, values: usize = 0 };
/// Per-direction JSON limits and optional shared operation traversal accounting.
pub const Budget = struct {
    work: ?*WorkBudget = null,
    limits: Limits,
    values: usize = 0,
    fn take(self: *Budget, depth: usize) !void {
        if (depth > self.limits.max_depth) return error.CodecDepthLimit;
        if (self.values == self.limits.max_values) return error.CodecValueLimit;
        if (self.work) |work| {
            if (work.values == work.limit) return error.CodecWorkLimit;
            work.values += 1;
        }
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
    budget: *Budget,
    execution: ?*Execution = null,
    trace: Trace,
    fn variant(self: *Decoder, ty: Type, json: Json, depth: usize, variants: typed.Variants) ValueError!Value {
        if (!variants.is_union) {
            if (json != .string) return error.ValueTypeMismatch;
            return Value.createVariant(self.allocator, ty, try tagFor(variants.cases, json.string), null);
        }
        if (json != .object) return error.ValueTypeMismatch;
        const case = json.object.get("case") orelse return self.trace.at(.{ .key = "case" }, error.IncompleteCodecValue);
        if (case != .string) return self.trace.at(.{ .key = "case" }, error.ValueTypeMismatch);
        const tag = tagFor(variants.cases, case.string) catch |err| return self.trace.at(.{ .key = "case" }, err);
        if (variants.cases[tag].payload) |payload_type| {
            const payload = json.object.get("value") orelse return self.trace.at(.{ .key = "value" }, error.IncompleteCodecValue);
            if (json.object.count() != 2) return error.UnexpectedCodecField;
            const decoded = try self.child(payload_type, payload, depth + 1, .{ .key = "value" });
            defer decoded.release(self.allocator);
            return Value.createVariant(self.allocator, ty, tag, decoded);
        }
        if (json.object.count() != 1) return error.UnexpectedCodecField;
        return Value.createVariant(self.allocator, ty, tag, null);
    }
    fn child(self: *Decoder, ty: Type, json: Json, depth: usize, part: Part) ValueError!Value {
        self.trace.push(part);
        defer self.trace.pop();
        return self.value(ty, json, depth);
    }
    fn value(self: *Decoder, ty: Type, json: Json, depth: usize) ValueError!Value {
        return self.valueInner(ty, json, depth) catch |err| {
            self.trace.failure(err);
            return err;
        };
    }
    fn valueInner(self: *Decoder, ty: Type, json: Json, depth: usize) ValueError!Value {
        try self.budget.take(depth);
        if (ty.isInteger()) return if (json == .string) integer(ty, json.string) else error.ValueTypeMismatch;
        if (ty == .bool) return if (json == .bool) .{ .bool = json.bool } else error.ValueTypeMismatch;
        const record = self.records[ty.recordIndex()];
        if (record.shape.domain != null) {
            const execution = self.execution orelse return error.NoImplicitCodec;
            const codec = record.contract.codec orelse return error.NoImplicitCodec;
            const wire = try self.value(codec.wire, json, depth);
            defer wire.release(self.allocator);
            return execution.decode(self.allocator, ty, wire);
        }
        if (record.shape.variants) |variants| return self.variant(ty, json, depth, variants);
        const count = record.count();
        const array = record.shape.array;
        const positional = array != null and array.?.key == null;
        if (positional) {
            if (json != .array) return error.ValueTypeMismatch;
            if (json.array.items.len != count) return self.trace.at(.{ .index = @min(json.array.items.len, count) }, error.IncompleteCodecValue);
        } else {
            if (json != .object) return error.ValueTypeMismatch;

            if (json.object.count() > count) return error.UnexpectedCodecField;
            for (0..count) |index| {
                const key = if (array) |a| self.records[a.key.?.recordIndex()].shape.variants.?.cases[index].name else record.fields[index].name;
                if (!json.object.contains(key)) return self.trace.at(.{ .key = key }, error.IncompleteCodecValue);
            }
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
            const part: Part = if (positional) .{ .index = index } else .{ .key = if (array) |a| self.records[a.key.?.recordIndex()].shape.variants.?.cases[index].name else record.fields[index].name };
            const child_json = if (positional) json.array.items[index] else json.object.get(part.key).?;
            field.* = try self.child(record.elementType(index), child_json, depth + 1, part);
            initialized += 1;
        }
        return Value.create(self.allocator, ty, fields);
    }
};
const Encoder = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    budget: *Budget,
    execution: ?*Execution = null,
    execution_allocator: ?std.mem.Allocator = null,
    trace: Trace,
    fn child(self: *Encoder, ty: Type, input: Value, depth: usize, part: Part) ValueError!Json {
        self.trace.push(part);
        defer self.trace.pop();
        return self.value(ty, input, depth);
    }
    fn value(self: *Encoder, ty: Type, input: Value, depth: usize) ValueError!Json {
        return self.valueInner(ty, input, depth) catch |err| {
            self.trace.failure(err);
            return err;
        };
    }
    fn valueInner(self: *Encoder, ty: Type, input: Value, depth: usize) ValueError!Json {
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
        if (record.shape.domain != null) {
            const execution = self.execution orelse return error.NoImplicitCodec;
            const codec = record.contract.codec orelse return error.NoImplicitCodec;
            if (self.budget.values == self.budget.limits.max_values) return error.CodecValueLimit;
            const runtime_allocator = self.execution_allocator.?;
            const wire = try execution.encode(runtime_allocator, ty, input);
            defer wire.release(runtime_allocator);
            return self.value(codec.wire, wire, depth);
        }
        if (record.shape.variants) |variants| {
            const tag = input.aggregate.active_tag orelse return error.InvalidCodecValue;
            if (tag >= variants.cases.len) return error.InvalidCodecValue;
            const case = variants.cases[tag];
            if (fields.len != @intFromBool(case.payload != null)) return error.InvalidCodecValue;
            if (!variants.is_union) return .{ .string = case.name };
            var object: std.json.ObjectMap = .empty;
            try object.put(self.allocator, "case", .{ .string = case.name });
            if (case.payload) |payload| try object.put(self.allocator, "value", try self.child(payload, fields[0], depth + 1, .{ .key = "value" }));
            return .{ .object = object };
        }
        if (input.aggregate.active_tag != null or fields.len != record.count()) return error.InvalidCodecValue;
        if (fields.len > self.budget.limits.max_values - self.budget.values) return error.CodecValueLimit;
        if (record.shape.array) |array| {
            if (array.key == null) {
                var output = std.json.Array.init(self.allocator);
                for (fields, 0..) |field, index| try output.append(try self.child(array.element, field, depth + 1, .{ .index = index }));
                return .{ .array = output };
            }
        }
        var output: std.json.ObjectMap = .empty;
        for (fields, 0..) |field, index| {
            const name = if (record.shape.array) |array| self.records[array.key.?.recordIndex()].shape.variants.?.cases[index].name else record.fields[index].name;
            try output.put(self.allocator, name, try self.child(record.elementType(index), field, depth + 1, .{ .key = name }));
        }
        return .{ .object = output };
    }
};
/// Borrows input without changing its ownership. Returns an owned canonical
/// envelope. The complete type must have an implicit codec in both directions.
pub fn encode(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, input: Value, limits: Limits) ValueError![]u8 {
    return encodeWithLocation(allocator, records, ty, input, limits, null);
}
/// Allocate ordinary typed JSON and locate conversion errors within the value.
pub fn encodeWithLocation(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, input: Value, limits: Limits, location: ?*Location) ValueError![]u8 {
    if (location) |out| out.* = .{};
    return encodeLocatedInner(allocator, records, ty, input, limits, location) catch |err| {
        if (location) |out| if (err != error.OutOfMemory and !out.has_path) out.capture(&.{});
        return err;
    };
}
fn encodeLocatedInner(allocator: std.mem.Allocator, records: []const typed.Record, ty: Type, input: Value, limits: Limits, location: ?*Location) ![]u8 {
    try limits.check();
    try checkLocatedType(allocator, records, ty, location);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var budget: Budget = .{ .limits = limits };
    var encoder: Encoder = .{ .allocator = arena.allocator(), .records = records, .budget = &budget, .trace = .init(location) };
    const document: Envelope = .{ .version = wire_version, .type = typed.typeName(ty, records), .value = try encoder.value(ty, input, 1) };
    return serialize(allocator, document, limits);
}
/// Allocate typed JSON using the operation's declared domain encoders and shared budgets.
pub fn encodeWithCodecs(allocator: std.mem.Allocator, execution: *Execution, ty: Type, input: Value, budget: *Budget, location: *Location) ValueError![]u8 {
    location.* = .{};
    return encodeCodecsInner(allocator, execution, ty, input, budget, location) catch |err| {
        if (err != error.OutOfMemory and !location.has_path) location.capture(&.{});
        return err;
    };
}
fn encodeCodecsInner(allocator: std.mem.Allocator, execution: *Execution, ty: Type, input: Value, budget: *Budget, location: *Location) ![]u8 {
    try checkCodecType(allocator, execution.program.records, ty, location);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var encoder: Encoder = .{ .allocator = arena.allocator(), .records = execution.program.records, .budget = budget, .execution = execution, .execution_allocator = allocator, .trace = .init(location) };
    const document: Envelope = .{ .version = wire_version, .type = typed.typeName(ty, execution.program.records), .value = try encoder.value(ty, input, 1) };
    return serialize(allocator, document, budget.limits);
}
fn serialize(allocator: std.mem.Allocator, document: Envelope, limits: Limits) ![]u8 {
    var counter = std.Io.Writer.Discarding.init(&.{});
    std.json.Stringify.value(document, .{}, &counter.writer) catch return error.InternalError;
    if (counter.fullCount() > limits.max_bytes) return error.CodecByteLimit;
    const text = try std.json.Stringify.valueAlloc(allocator, document, .{});
    errdefer allocator.free(text);
    // Match parser token/depth limits, including escaped names and envelope.
    try scan(allocator, text, limits);
    return text;
}

/// A named wire argument and its checked language type; JSON storage is borrowed.
pub const Argument = struct { name: []const u8, ty: Type, value: Json };

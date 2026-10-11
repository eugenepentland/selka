//! Versioned named-field syntax values shared by the parser oracle and component.
//! The wire describes logical AST fields, never pointers, capacities or Zig layout.
const std = @import("std");
const ast = @import("ast.zig");
const codec = @import("persist_codec.zig");
const diagnostic = @import("diagnostic.zig");

/// A malformed, over-budget syntax value or an allocation failure.
pub const Error = error{ ComponentProtocol, OutOfMemory };
/// Maximum encoded reply size, including the value-table header.
pub const value_wire_limit = 64 * 1024 * 1024;
/// Maximum number of postorder values in one reply.
pub const max_values = 1048576;
/// Maximum aggregate child references in one syntax value table.
pub const max_edges = 4194304;
/// Closed row policies; all other wire and expansion budgets remain shared.
pub const ValueProfile = enum {
    syntax,
    body,

    /// Maximum postorder rows admitted by this component profile.
    pub fn rows(self: ValueProfile) u32 {
        return switch (self) {
            .syntax => max_values,
            .body => 2097152,
        };
    }
};
const max_depth = 256;
const magic = "SLKAST01";
const error_magic = "SLKERR01";
const Kind = enum(u8) { null, integer, boolean, bytes, enumeration, record, list, tagged };
const Value = struct {
    kind: Kind,
    integer: i64 = 0,
    data: []const u8 = &.{},
    children: []const u32 = &.{},
    names: []const []const u8 = &.{},
};

const Encoder = struct {
    writer: codec.Writer,
    scratch: std.mem.Allocator,
    count: u32 = 0,
    edges: usize = 0,
    profile: ValueProfile = .syntax,

    fn blob(self: *Encoder, data: []const u8) Error!void {
        if (data.len > value_wire_limit) return error.ComponentProtocol;
        try self.writer.integer(@as(u32, @intCast(data.len)));
        try self.writer.raw(data);
    }
    fn append(self: *Encoder, item: Value) Error!u32 {
        if (self.count >= self.profile.rows() or item.children.len > max_edges - self.edges) return error.ComponentProtocol;
        self.edges += item.children.len;
        try self.writer.integer(@as(u8, @backingInt(item.kind)));
        try self.writer.integer(item.integer);
        try self.blob(item.data);
        try self.writer.integer(@as(u32, @intCast(item.children.len)));
        for (item.children) |child| try self.writer.integer(child);
        try self.writer.integer(@as(u32, @intCast(item.names.len)));
        for (item.names) |name| try self.blob(name);
        if (self.writer.bytes.items.len > value_wire_limit) return error.ComponentProtocol;
        const id = self.count;
        self.count += 1;
        return id;
    }
    fn sequence(self: *Encoder, comptime T: type, items: []const T, depth: usize) Error!u32 {
        if (items.len > self.profile.rows()) return error.ComponentProtocol;
        const children = try self.scratch.alloc(u32, items.len);
        for (items, children) |item, *child| child.* = try self.value(T, item, depth + 1);
        return self.append(.{ .kind = .list, .children = children });
    }
    fn value(self: *Encoder, comptime T: type, item: T, depth: usize) Error!u32 {
        if (depth > max_depth) return error.ComponentProtocol;
        if (T == std.ArrayList(ast.Node)) return self.sequence(ast.Node, item.items, depth);
        if (T == std.ArrayList(ast.Statement)) return self.sequence(ast.Statement, item.items, depth);
        switch (@typeInfo(T)) {
            .void => return self.append(.{ .kind = .null }),
            .int => return self.append(.{ .kind = .integer, .integer = std.math.cast(i64, item) orelse return error.ComponentProtocol }),
            .bool => return self.append(.{ .kind = .boolean, .integer = @intFromBool(item) }),
            .@"enum" => |info| {
                if (info.mode == .nonexhaustive) return self.append(.{ .kind = .integer, .integer = std.math.cast(i64, @backingInt(item)) orelse return error.ComponentProtocol });
                return self.append(.{ .kind = .enumeration, .data = @tagName(item) });
            },
            .optional => |info| return if (item) |present| self.value(info.child, present, depth + 1) else self.append(.{ .kind = .null }),
            .pointer => |info| {
                if (info.size != .slice) @compileError("syntax values require owned slices");
                if (info.child == u8) return self.append(.{ .kind = .bytes, .data = item });
                return self.sequence(info.child, item, depth);
            },
            .array => |info| return self.sequence(info.child, &item, depth),
            .@"struct" => |info| {
                var children: [info.field_names.len]u32 = undefined;
                var names: [info.field_names.len][]const u8 = undefined;
                inline for (info.field_names, info.field_types, 0..) |field_name, Field, index| {
                    children[index] = try self.value(Field, @field(item, field_name), depth + 1);
                    names[index] = field_name;
                }
                return self.append(.{ .kind = .record, .children = &children, .names = &names });
            },
            .@"union" => |info| {
                inline for (info.field_names, info.field_types) |field_name, Field| {
                    if (std.mem.eql(u8, @tagName(item), field_name)) {
                        const payload = try self.value(Field, @field(item, field_name), depth + 1);
                        return self.append(.{ .kind = .tagged, .data = field_name, .children = &.{payload} });
                    }
                }
                unreachable;
            },
            else => @compileError("unsupported syntax value " ++ @typeName(T)),
        }
    }
};

/// Encode an AST as deterministic named-field values, preserving all metadata.
pub fn encode(allocator: std.mem.Allocator, program: ast.Program) Error![]u8 {
    return encodeTree(allocator, ast.Program, program, magic);
}

/// Encode a bounded logical named-field value under an eight-byte schema signature.
pub fn encodeTree(allocator: std.mem.Allocator, comptime T: type, value: T, signature: []const u8) Error![]u8 {
    return encodeTreeProfile(allocator, T, value, signature, .syntax);
}

/// Encode under a closed component row policy without widening other budgets.
pub fn encodeTreeProfile(allocator: std.mem.Allocator, comptime T: type, value: T, signature: []const u8, profile: ValueProfile) Error![]u8 {
    @setEvalBranchQuota(200000);
    if (signature.len != 8) return error.ComponentProtocol;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var encoder: Encoder = .{ .writer = .init(allocator), .scratch = scratch.allocator(), .profile = profile };
    defer encoder.writer.deinit();
    try encoder.writer.raw(signature);
    try encoder.writer.integer(@as(u32, 0));
    try encoder.writer.integer(@as(u32, 0));
    const root = try encoder.value(T, value, 0);
    std.mem.writeInt(u32, encoder.writer.bytes.items[8..12], encoder.count, .little);
    std.mem.writeInt(u32, encoder.writer.bytes.items[12..16], root, .little);
    return encoder.writer.bytes.toOwnedSlice(allocator);
}

const Budget = struct {
    remaining: usize = 512 * 1024 * 1024,
    visits: usize = 4 * max_values,
    edges: usize = max_edges,

    fn allocate(self: *Budget, allocator: std.mem.Allocator, comptime T: type, count: usize) Error![]T {
        if (count > self.remaining / @max(1, @sizeOf(T))) return error.ComponentProtocol;
        self.remaining -= count * @sizeOf(T);
        return allocator.alloc(T, count);
    }
    fn visit(self: *Budget, depth: usize) Error!void {
        if (depth > max_depth or self.visits == 0) return error.ComponentProtocol;
        self.visits -= 1;
    }
};

const Reader = struct {
    wire: codec.Reader,
    budget: *Budget,
    profile: ValueProfile,

    fn integer(self: *Reader, comptime T: type) Error!T {
        return self.wire.integer(T) catch return error.ComponentProtocol;
    }
    fn blob(self: *Reader) Error![]const u8 {
        return self.wire.slice(try self.integer(u32)) catch return error.ComponentProtocol;
    }
    fn value(self: *Reader, index: usize) Error!Value {
        const kind = std.enums.fromInt(Kind, try self.integer(u8)) orelse return error.ComponentProtocol;
        const integer_value = try self.integer(i64);
        const data = try self.blob();
        const count = try self.integer(u32);
        if (count > self.profile.rows() or count > self.budget.edges) return error.ComponentProtocol;
        self.budget.edges -= count;
        const children = try self.budget.allocate(self.wire.allocator, u32, count);
        for (children) |*child| {
            child.* = try self.integer(u32);
            if (child.* >= index) return error.ComponentProtocol;
        }
        const name_count = try self.integer(u32);
        if (name_count > (if (self.profile == .body) @as(u32, 8) else 7)) return error.ComponentProtocol;
        const names = try self.budget.allocate(self.wire.allocator, []const u8, name_count);
        for (names) |*name| {
            name.* = try self.blob();
            if (name.len == 0 or name.len > 64) return error.ComponentProtocol;
        }
        if (kind != .integer and kind != .boolean and integer_value != 0) return error.ComponentProtocol;
        if (kind != .bytes and kind != .enumeration and kind != .tagged and data.len != 0) return error.ComponentProtocol;
        if (kind != .record and names.len != 0) return error.ComponentProtocol;
        switch (kind) {
            .null, .integer, .bytes, .enumeration => if (count != 0) return error.ComponentProtocol,
            .boolean => if (count != 0 or (integer_value != 0 and integer_value != 1)) return error.ComponentProtocol,
            .tagged => if (count != 1 or data.len == 0) return error.ComponentProtocol,
            .record => if (name_count != count) return error.ComponentProtocol,
            .list => {},
        }
        return .{ .kind = kind, .integer = integer_value, .data = data, .children = children, .names = names };
    }
};

const Decoder = struct {
    allocator: std.mem.Allocator,
    values: []const Value,
    budget: *Budget,

    fn field(item: Value, wanted: []const u8) Error!u32 {
        var found: ?u32 = null;
        for (item.names, item.children) |name, child| {
            if (!std.mem.eql(u8, name, wanted)) continue;
            if (found != null) return error.ComponentProtocol;
            found = child;
        }
        return found orelse error.ComponentProtocol;
    }

    fn sequence(self: *Decoder, comptime T: type, item: Value, depth: usize) Error![]T {
        if (item.kind != .list) return error.ComponentProtocol;
        const items = try self.budget.allocate(self.allocator, T, item.children.len);
        for (items, item.children) |*element, child| element.* = try self.value(T, child, depth + 1);
        return items;
    }
    fn value(self: *Decoder, comptime T: type, id: u32, depth: usize) Error!T {
        try self.budget.visit(depth);
        const item = self.values[id];
        if (T == std.ArrayList(ast.Node)) {
            const items = try self.sequence(ast.Node, item, depth);
            return .{ .items = items, .capacity = items.len };
        }
        if (T == std.ArrayList(ast.Statement)) {
            const items = try self.sequence(ast.Statement, item, depth);
            return .{ .items = items, .capacity = items.len };
        }
        switch (@typeInfo(T)) {
            .void => {
                if (item.kind != .null) return error.ComponentProtocol;
                return {};
            },
            .int => {
                if (item.kind != .integer) return error.ComponentProtocol;
                return std.math.cast(T, item.integer) orelse error.ComponentProtocol;
            },
            .bool => {
                if (item.kind != .boolean) return error.ComponentProtocol;
                return item.integer == 1;
            },
            .@"enum" => |info| {
                if (info.mode == .nonexhaustive) {
                    if (item.kind != .integer or item.integer < 0) return error.ComponentProtocol;
                    return @fromBackingInt(std.math.cast(info.tag_type, item.integer) orelse return error.ComponentProtocol);
                }
                if (item.kind != .enumeration) return error.ComponentProtocol;
                return std.meta.stringToEnum(T, item.data) orelse error.ComponentProtocol;
            },
            .optional => |info| return if (item.kind == .null) null else try self.value(info.child, id, depth + 1),
            .pointer => |info| {
                if (info.size != .slice) @compileError("syntax values require owned slices");
                if (info.child == u8) {
                    if (item.kind != .bytes) return error.ComponentProtocol;
                    const result = try self.budget.allocate(self.allocator, u8, item.data.len);
                    @memcpy(result, item.data);
                    return result;
                }
                return self.sequence(info.child, item, depth);
            },
            .array => |info| {
                if (item.kind != .list or item.children.len != info.len) return error.ComponentProtocol;
                var result: T = undefined;
                for (&result, item.children) |*element, child| element.* = try self.value(info.child, child, depth + 1);
                return result;
            },
            .@"struct" => |info| {
                if (item.kind != .record or item.names.len != info.field_names.len) return error.ComponentProtocol;
                var result: T = undefined;
                inline for (info.field_names, info.field_types) |field_name, Field| {
                    @field(result, field_name) = try self.value(Field, try field(item, field_name), depth + 1);
                }
                return result;
            },
            .@"union" => |info| {
                if (item.kind != .tagged) return error.ComponentProtocol;
                inline for (info.field_names, info.field_types) |field_name, Field| {
                    if (std.mem.eql(u8, field_name, item.data)) return @unionInit(T, field_name, try self.value(Field, item.children[0], depth + 1));
                }
                return error.ComponentProtocol;
            },
            else => @compileError("unsupported syntax value " ++ @typeName(T)),
        }
    }
};

/// Owned syntax received from a component, independent of its reply buffer.
pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    program: ast.Program,

    /// Release all decoded AST storage, including partially shared slices.
    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Decode a bounded table and reject unknown fields, spans, references and cycles.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, source_len: usize) Error!Decoded {
    var result = try decodeTree(ast.Program, allocator, bytes, magic);
    errdefer result.arena.deinit();
    try @import("parser_value_validate.zig").validate(allocator, result.value, source_len);
    return .{ .arena = result.arena, .program = result.value };
}

/// Arena-owned generic logical value returned by the bounded decoder.
pub fn Owned(comptime T: type) type {
    return struct { arena: std.heap.ArenaAllocator, value: T };
}

/// Decode a bounded logical named-field value; callers validate domain invariants.
pub fn decodeTree(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, signature: []const u8) Error!Owned(T) {
    return decodeTreeProfile(T, allocator, bytes, signature, .syntax);
}

/// Decode with a closed row policy and the unchanged allocation/visit budgets.
pub fn decodeTreeProfile(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, signature: []const u8, profile: ValueProfile) Error!Owned(T) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const item = try decodeTarget(T, allocator, arena.allocator(), bytes, signature, profile);
    return .{ .arena = arena, .value = item };
}

/// Decode bounded logical values into caller-owned arena storage for adoption.
/// The caller releases partial allocations with its arena if decoding fails.
pub fn decodeInto(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, signature: []const u8) Error!T {
    return decodeIntoProfile(T, allocator, bytes, signature, .syntax);
}

/// Decode into caller-owned storage using an explicitly selected closed policy.
pub fn decodeIntoProfile(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, signature: []const u8, profile: ValueProfile) Error!T {
    return decodeTarget(T, allocator, allocator, bytes, signature, profile);
}
fn decodeTarget(comptime T: type, scratch_allocator: std.mem.Allocator, allocator: std.mem.Allocator, bytes: []const u8, signature: []const u8, profile: ValueProfile) Error!T {
    @setEvalBranchQuota(200000);
    if (signature.len != 8) return error.ComponentProtocol;
    if (bytes.len < 16 or bytes.len > value_wire_limit or !std.mem.eql(u8, bytes[0..8], signature)) return error.ComponentProtocol;
    const count = std.mem.readInt(u32, bytes[8..12], .little);
    const root = std.mem.readInt(u32, bytes[12..16], .little);
    if (count == 0 or count > profile.rows() or root != count - 1 or count > (bytes.len - 16) / 21) return error.ComponentProtocol;
    var scratch = std.heap.ArenaAllocator.init(scratch_allocator);
    defer scratch.deinit();
    var budget: Budget = .{};
    const values = try budget.allocate(scratch.allocator(), Value, count);
    var reader: Reader = .{ .wire = .init(scratch.allocator(), bytes[16..]), .budget = &budget, .profile = profile };
    for (values, 0..) |*value, index| value.* = try reader.value(index);
    if (!reader.wire.done()) return error.ComponentProtocol;
    var decoder: Decoder = .{ .allocator = allocator, .values = values, .budget = &budget };
    return decoder.value(T, root, 0);
}

/// Parser diagnostics retain prose, notes and fixes without runtime-only state.
pub const SyntaxDiagnostic = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    span: @import("source.zig").Span,
    message: []const u8,
    related: ?diagnostic.Related,
    provenance: struct { origin: ?diagnostic.Related, requirement: ?diagnostic.Related, fix: ?diagnostic.Fix },
};
/// Ordered recovered parser diagnostics, encoded with the SLKERR01 signature.
pub const ErrorReport = struct { diagnostics: []const SyntaxDiagnostic };
/// Independently owned parser failure data.
pub const DecodedErrors = struct {
    arena: std.heap.ArenaAllocator,
    report: ErrorReport,

    /// Release all diagnostic data received from a component.
    pub fn deinit(self: *DecodedErrors) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
/// Encode every parser diagnostic, refusing runtime traces and checker obligations.
pub fn encodeErrors(allocator: std.mem.Allocator, problems: []const diagnostic.Diagnostic) Error![]u8 {
    const diagnostics = try allocator.alloc(SyntaxDiagnostic, problems.len);
    defer allocator.free(diagnostics);
    for (problems, diagnostics) |problem, *item| {
        if (problem.provenance.obligation != null or problem.stack.len != 0 or problem.stack.omitted != 0) return error.ComponentProtocol;
        item.* = .{
            .code = problem.code,
            .severity = problem.severity,
            .span = problem.span,
            .message = problem.message,
            .related = problem.related,
            .provenance = .{ .origin = problem.provenance.origin, .requirement = problem.provenance.requirement, .fix = problem.provenance.fix },
        };
    }
    return encodeTree(allocator, ErrorReport, .{ .diagnostics = diagnostics }, error_magic);
}
/// Decode all parser failures with exact field and source-range validation.
pub fn decodeErrors(allocator: std.mem.Allocator, bytes: []const u8, source_len: usize) Error!DecodedErrors {
    var result = try decodeTree(ErrorReport, allocator, bytes, error_magic);
    errdefer result.arena.deinit();
    if (result.value.diagnostics.len == 0) return error.ComponentProtocol;
    try @import("parser_value_validate.zig").ranges(ErrorReport, result.value, source_len);
    return .{ .arena = result.arena, .report = result.value };
}

/// Canonicalize a decoded error reply so producer table ordering is irrelevant.
pub fn encodeReport(allocator: std.mem.Allocator, report: ErrorReport) Error![]u8 {
    return encodeTree(allocator, ErrorReport, report, error_magic);
}

// spec-case: SELFHOST-FRONTEND-PROFILE-1
test "parser values enforce aggregate edge budget across otherwise valid rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var bytes: [25]u8 = @splat(0);
    bytes[0] = 6;
    std.mem.writeInt(u32, bytes[13..17], 1, .little);
    var budget: Budget = .{ .edges = 1 };
    var first: Reader = .{ .wire = .init(arena.allocator(), &bytes), .budget = &budget };
    const admitted = try first.value(1);
    try std.testing.expectEqual(@as(usize, 1), admitted.children.len);
    try std.testing.expectEqual(@as(usize, 0), budget.edges);
    var excess: Reader = .{ .wire = .init(arena.allocator(), &bytes), .budget = &budget };
    try std.testing.expectError(error.ComponentProtocol, excess.value(1));
}

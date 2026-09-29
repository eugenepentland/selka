//! Canonical copied-host declarations and concrete native field offsets.
const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode.zig");
const native = @import("native_types.zig");
/// Copied-value child identity and its native byte offset.
pub const Field = struct { type: ?[]const u8, offset: u64 };
/// Finite data shape accepted by a trusted copied-value host callback.
pub const Type = struct { name: []const u8, kind: []const u8, size: u64, alignment: u8, bits: u8 = 0, signed: bool = false, count: u64 = 0, stride: u64 = 0, fields: []const Field = &.{} };
/// Stable host symbol and the exact signature and declared effects.
pub const Declaration = struct { name: []const u8, symbol: []const u8, parameters: []const []const u8, result: []const u8, effects: u32 };
/// Serializable native host type and declaration tables.
pub const Metadata = struct { types: []const Type, declarations: []const Declaration };
/// Describe host data without interpreting guest bytecode or using VM values.
/// MODULE-HOST-1: the table holds the types the declarations reach (their
/// parameters and results, and those types' fields, cases and elements),
/// sorted by name, and the declarations sorted by symbol, so a table merged
/// from the modules' own tables is this one, row for row.
pub fn describe(allocator: std.mem.Allocator, program: bc.Program, catalog: *native.Catalog) native.Error!Metadata {
    var declarations: std.ArrayList(Declaration) = .empty;
    var pending: std.ArrayList(typed.Type) = .empty;
    for (program.functions) |function| {
        if (function.policy.host == null or function.policy.c_abi) continue;
        // The leading `Host` authority never reaches the copied host bridge.
        const values = function.scope.locals[@min(1, function.scope.locals.len)..function.signature.parameter_count];
        const parameters = try allocator.alloc([]const u8, values.len);
        for (parameters, values) |*parameter, local| parameter.* = try catalog.identity(local.ty);
        for (values) |local| try pending.append(allocator, local.ty);
        try pending.append(allocator, function.signature.return_type);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(function.name, &digest, .{});
        try declarations.append(allocator, .{
            .name = function.name,
            .symbol = try std.fmt.allocPrint(allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)}),
            .parameters = parameters,
            .result = try catalog.identity(function.signature.return_type),
            .effects = function.policy.effects,
        });
    }
    if (declarations.items.len == 0) return .{ .types = &.{}, .declarations = &.{} };
    const reached = try allocator.alloc(bool, typed.Type.record_base + program.records.len);
    @memset(reached, false);
    var types: std.ArrayList(Type) = .empty;
    while (pending.pop()) |next| {
        const index: usize = @backingInt(next);
        if (index >= reached.len or reached[index]) continue;
        reached[index] = true;
        const item = try types.addOne(allocator);
        try describeType(allocator, .{ .program = program, .catalog = catalog, .pending = &pending }, next, item);
    }
    std.mem.sort(Type, types.items, {}, typeBefore);
    std.mem.sort(Declaration, declarations.items, {}, declarationBefore);
    return .{ .types = types.items, .declarations = try declarations.toOwnedSlice(allocator) };
}

fn typeBefore(_: void, left: Type, right: Type) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn declarationBefore(_: void, left: Declaration, right: Declaration) bool {
    return std.mem.lessThan(u8, left.symbol, right.symbol);
}

/// What describing one type reads, and where the types it reaches go.
const Reach = struct { program: bc.Program, catalog: *native.Catalog, pending: *std.ArrayList(typed.Type) };

/// One type's row; every type its row names is appended to `reach.pending`.
fn describeType(allocator: std.mem.Allocator, reach: Reach, ty: typed.Type, item: *Type) native.Error!void {
    const program = reach.program;
    const catalog = reach.catalog;
    const layout = try catalog.layout(ty);
    item.* = .{ .name = try catalog.identity(ty), .kind = "unsupported", .size = layout.size, .alignment = layout.alignment };
    if (ty.integer()) |info| {
        item.kind = "scalar";
        item.bits = info.bits;
        item.signed = info.signed;
    } else if (ty == .bool) {
        item.kind = "scalar";
        item.bits = 1;
    } else if (ty.isAggregate()) {
        // The immutable byte string is the one managed shape the boundary
        // carries: one owned payload the packed bridge copies whole.
        if (typed.isByteString(program.records[ty.recordIndex()])) {
            item.kind = "bytes";
            return;
        }
        if (layout.trace or layout.drop) return;
        if (program.records[ty.recordIndex()].contract.callback != null) return;
        if (program.records[ty.recordIndex()].shape.hasRuntimeIdentity()) return;
        const record = program.records[ty.recordIndex()];
        if (record.shape.variants) |variants| {
            item.kind = "variant";
            item.count = variants.cases.len;
            const fields = try allocator.alloc(Field, variants.cases.len);
            for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| try catalog.identity(payload) else null, .offset = layout.payload_offset };
            for (variants.cases) |case| if (case.payload) |payload| try reach.pending.append(allocator, payload);
            item.fields = fields;
        } else {
            item.kind = if (record.shape.domain != null) "domain" else if (record.shape.array != null) "array" else "record";
            // FLOAT-NAN-OBSERVED-6: the builtin binary64 domain is the one
            // domain whose width is set, so the copied bridge knows which
            // backing words to canonicalize before a host reads them.
            if (@import("numeric_surface.zig").isFloat(ty, program.records)) item.bits = 64;
            item.count = if (record.shape.array != null) layout.count else layout.fields.len;
            item.stride = layout.stride;
            const fields = try allocator.alloc(Field, layout.fields.len);
            for (layout.fields, fields) |field, *target| target.* = .{ .type = try catalog.identity(field.ty), .offset = field.offset };
            for (layout.fields) |field| try reach.pending.append(allocator, field.ty);
            item.fields = fields;
        }
    }
}

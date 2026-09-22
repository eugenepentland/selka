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
pub fn describe(allocator: std.mem.Allocator, program: bc.Program, catalog: *native.Catalog) native.Error!Metadata {
    var declarations: std.ArrayList(Declaration) = .empty;
    for (program.functions) |function| {
        if (function.policy.host == null or function.policy.c_abi) continue;
        // The leading `Host` authority never reaches the copied host bridge.
        const values = function.scope.locals[@min(1, function.scope.locals.len)..function.signature.parameter_count];
        const parameters = try allocator.alloc([]const u8, values.len);
        for (parameters, values) |*parameter, local| parameter.* = try catalog.identity(local.ty);
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
    const types = try allocator.alloc(Type, typed.Type.record_base + program.records.len);
    for (types, 0..) |*item, index| {
        const ty: typed.Type = @fromBackingInt(index);
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
                continue;
            }
            if (layout.trace or layout.drop) continue;
            if (program.records[ty.recordIndex()].contract.callback != null) continue;
            if (program.records[ty.recordIndex()].shape.hasRuntimeIdentity()) continue;
            const record = program.records[ty.recordIndex()];
            if (record.shape.variants) |variants| {
                item.kind = "variant";
                item.count = variants.cases.len;
                const fields = try allocator.alloc(Field, variants.cases.len);
                for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| try catalog.identity(payload) else null, .offset = layout.payload_offset };
                item.fields = fields;
            } else {
                item.kind = if (record.shape.domain != null) "domain" else if (record.shape.array != null) "array" else "record";
                item.count = if (record.shape.array != null) layout.count else layout.fields.len;
                item.stride = layout.stride;
                const fields = try allocator.alloc(Field, layout.fields.len);
                for (layout.fields, fields) |field, *target| target.* = .{ .type = try catalog.identity(field.ty), .offset = field.offset };
                item.fields = fields;
            }
        }
    }
    return .{ .types = types, .declarations = try declarations.toOwnedSlice(allocator) };
}

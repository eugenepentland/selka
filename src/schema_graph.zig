//! Public checked type graph. This describes language contracts, not a wire format or ABI.
/// Failures returned by render; callers must handle these boundary errors.
pub const RenderError = error{
    InvalidCheckedType,
    OutOfMemory,
    SourceError,
    InternalError,
};

const std = @import("std");
const typed = @import("typed.zig");
const interfaces = @import("interfaces.zig");
const effects = @import("effect_set.zig");
const Field = struct { name: []const u8, type: []const u8 };
const Case = struct { name: []const u8, payload: ?[]const u8 };
const Codec = struct { wire: []const u8, decode: []const u8, encode: []const u8, error_type: []const u8 };
const Definition = struct {
    callback: ?struct { parameters: []const []const u8, result: []const u8, effects: u8, borrowed: u16, slices: u16 } = null,
    codec: ?Codec = null,
    name: []const u8,
    kind: enum { callback, integer, boolean, capability, record, array, table, domain, enumeration, tagged_union, result, buffer, resource, pool, handle },
    move_only: bool = false,
    requires_handling: bool = false,
    @"opaque": bool = false,
    bits: ?u7 = null,
    signed: ?bool = null,
    minimum: ?[]const u8 = null,
    maximum: ?[]const u8 = null,
    fields: ?[]const Field = null,
    cases: ?[]const Case = null,
    element: ?[]const u8 = null,
    length: ?usize = null,
    key: ?[]const u8 = null,
    handle: ?[]const u8 = null,
    pool: ?[]const u8 = null,
    authority: ?[]const u8 = null,
};
const Parameter = struct { name: []const u8, type: []const u8, mode: enum { value, shared_reference, exclusive_reference, shared_slice, exclusive_slice } };
const ReturnReference = struct { parameter: usize, mutable: bool, slice: bool };
const Function = struct { name: []const u8, parameters: []const Parameter, result: []const u8, return_reference: ?ReturnReference, effects: []const []const u8 };
const Graph = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    functions: []const typed.Function,
    seen: []bool,
    queue: std.ArrayList(typed.Type) = .empty,
    fn reference(self: *Graph, ty: typed.Type) ![]const u8 {
        const id = @backingInt(ty);
        if (!self.seen[id]) {
            try self.queue.append(self.allocator, ty);
            self.seen[id] = true;
        }
        return typed.typeName(ty, self.records);
    }
    fn definition(self: *Graph, ty: typed.Type) !Definition {
        const name = typed.typeName(ty, self.records);
        if (ty.integer()) |integer| return .{
            .name = name,
            .kind = .integer,
            .bits = integer.bits,
            .signed = integer.signed,
            .minimum = try std.fmt.allocPrint(self.allocator, "{d}", .{ty.min()}),
            .maximum = try std.fmt.allocPrint(self.allocator, "{d}", .{ty.max()}),
        };
        if (!ty.isAggregate()) return .{ .name = name, .kind = if (ty == .bool) .boolean else .capability, .@"opaque" = ty != .bool };
        const record = self.records[ty.recordIndex()];
        var out: Definition = .{ .name = name, .kind = .record, .move_only = record.contract.move_only, .requires_handling = record.contract.requires_handling };
        if (record.contract.callback) |contract| {
            const parameters = try self.allocator.alloc([]const u8, contract.parameters.len);
            for (contract.parameters, parameters) |parameter, *out_type| out_type.* = try self.reference(parameter);
            out.kind = .callback;
            out.@"opaque" = true;
            out.callback = .{ .parameters = parameters, .result = try self.reference(contract.return_type), .effects = contract.effects, .borrowed = contract.borrowed, .slices = contract.slices };
            return out;
        }
        // Domains may only be constructed through their checked factories. Runtime
        // owners/handles/capabilities have no portable reconstruction operation.
        if (record.shape.domain != null or record.shape.hasRuntimeIdentity()) {
            out.kind = if (record.shape.domain != null) .domain else if (record.shape.buffer != null) .buffer else if (record.shape.resource != null) .resource else if (record.shape.pool != null) .pool else .handle;
            out.@"opaque" = true;
            if (record.contract.codec) |codec| {
                const decode = self.functions[@backingInt(codec.decode)];
                const shape = typed.resultShape(decode.signature.return_type, self.records).?;
                out.codec = .{ .wire = try self.reference(codec.wire), .decode = decode.name, .encode = self.functions[@backingInt(codec.encode)].name, .error_type = try self.reference(shape.error_type) };
            }
            if (record.shape.buffer) |element| out.element = try self.reference(element);
            if (record.shape.resource) |kind| out.authority = @tagName(kind);
            if (record.shape.pool) |pool| {
                out.element = try self.reference(pool.element);
                out.handle = try self.reference(pool.handle);
            }
            if (record.shape.handle_pool) |pool| out.pool = try self.reference(pool);
        } else if (record.shape.array) |array| {
            out.kind = if (array.key != null) .table else .array;
            out.element = try self.reference(array.element);
            out.length = array.length;
            if (array.key) |key| out.key = try self.reference(key);
        } else if (record.shape.variants) |variants| {
            out.kind = if (variants.fallible) .result else if (variants.is_union) .tagged_union else .enumeration;
            const cases = try self.allocator.alloc(Case, variants.cases.len);
            for (cases, variants.cases) |*item, variant| item.* = .{ .name = variant.name, .payload = if (variant.payload) |payload| try self.reference(payload) else null };
            out.cases = cases;
        } else {
            const fields = try self.allocator.alloc(Field, record.fields.len);
            for (fields, record.fields) |*field, original| field.* = .{ .name = original.name, .type = try self.reference(original.ty) };
            out.fields = fields;
        }
        return out;
    }
};
fn lessDefinition(_: void, a: Definition, b: Definition) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessFunction(_: void, a: Function, b: Function) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn lessName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
/// Checks all bodies before deriving anything. Output is owned by allocator;
/// temporary graph storage is released, including on allocation failure.
pub fn render(allocator: std.mem.Allocator, index: *interfaces.Index, program: typed.Program, function_ids: []const typed.FunctionId) RenderError![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var graph: Graph = .{ .allocator = scratch, .records = program.records, .functions = program.functions, .seen = try scratch.alloc(bool, typed.Type.record_base + program.records.len) };
    @memset(graph.seen, false);
    var roots: std.ArrayList([]const u8) = .empty;
    // Resolve exported nominal declarations by identity; structural array names
    // are not declarations and acquire visibility only through public contracts.
    var nominal: std.StringHashMapUnmanaged(typed.Type) = .empty;
    for (program.records) |record| try nominal.put(scratch, record.name, record.id);
    for (program.aliases) |alias| try nominal.put(scratch, alias.name, alias.target);
    for (index.units, 0..) |unit, module| {
        for (unit.symbols.items) |symbol| {
            if (!symbol.exported or symbol.kind != .type) continue;
            const name = try std.fmt.allocPrint(scratch, "{s}::{s}", .{ index.project.modules.items[module].name, symbol.name });
            const ty = nominal.get(name) orelse {
                // A public template is a type constructor, not a concrete schema root.
                if (@import("generic_api.zig").isConstructor(unit, symbol.span)) continue;
                return error.InvalidCheckedType;
            };
            try roots.append(scratch, try graph.reference(ty));
        }
    }
    const functions = try scratch.alloc(Function, function_ids.len);
    for (functions, function_ids) |*output, id| {
        const function = program.functions[@backingInt(id)];
        const parameters = try scratch.alloc(Parameter, function.signature.parameter_count);
        for (parameters, function.scope.locals[0..function.signature.parameter_count]) |*parameter, local| parameter.* = .{
            .name = local.name,
            .type = try graph.reference(local.ty),
            .mode = if (local.parameter.reference_parameter) |mutable| (if (local.parameter.slice_parameter) (if (mutable) .exclusive_slice else .shared_slice) else (if (mutable) .exclusive_reference else .shared_reference)) else .value,
        };
        var names: std.ArrayList([]const u8) = .empty;
        inline for (std.meta.tags(effects.Effect)) |effect| {
            if (function.policy.effects & effects.bit(effect) != 0) try names.append(scratch, @tagName(effect));
        }
        output.* = .{
            .name = function.name,
            .parameters = parameters,
            .result = try graph.reference(function.signature.return_type),
            .effects = names.items,
            .return_reference = if (function.signature.return_reference) |ref| .{ .parameter = @backingInt(ref.parameter), .mutable = ref.mutable, .slice = ref.slice } else null,
        };
    }
    var definitions: std.ArrayList(Definition) = .empty;
    var next: usize = 0;
    while (next < graph.queue.items.len) : (next += 1) try definitions.append(scratch, try graph.definition(graph.queue.items[next]));
    std.mem.sort(Definition, definitions.items, {}, lessDefinition);
    std.mem.sort(Function, functions, {}, lessFunction);
    std.mem.sort([]const u8, roots.items, {}, lessName);
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "language-schema-v1",
        .scope = "reachable-module-exports",
        .representation = "language-contracts-no-wire-format-or-abi",
        .entry = index.project.modules.items[0].name,
        .exports = roots.items,
        .functions = functions,
        .types = definitions.items,
        .generic_templates_version = "generic-templates-v1",
        .generic_templates = try @import("generic_api.zig").collect(scratch, index),
    }, .{ .emit_null_optional_fields = false });
}

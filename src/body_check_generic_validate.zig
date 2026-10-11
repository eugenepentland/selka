//! Concrete free-function identity authority for the schema 11 rollout.
//! This module does not check bodies or supply specialization answers to a producer.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const instances = @import("generic_instances.zig");
const requirements = @import("generic_requirements.zig");
const policy = @import("body_check_record_validate.zig");
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Restored declaration keys and ordinary executable ownership, in output order.
/// Key argument storage borrows the validated decoded batch until adoption copies it.
pub const Plan = struct {
    keys: []instances.Key,
    ordinary: []?typed.FunctionId,
    ordinary_count: usize,
};
fn located(at: source.Span, size: usize) Error!void {
    if (at.start > at.end or at.end > size) return error.ComponentProtocol;
}
fn known(input: value.Input, accepted: []const bool, ty: typed.Type) bool {
    if (ty.isInteger() or ty == .bool or ty == .unit) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= input.catalog.records.len) return false;
    return ty.recordIndex() < accepted.len and accepted[ty.recordIndex()];
}
fn promises(input: value.Input, parameter: @import("ast.zig").TypeParameter, argument: typed.Type) Error!void {
    if (parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0 or parameter.named_requirements.len != 0) return error.ComponentProtocol;
    var required: requirements.Set = .{};
    if (parameter.default_copy) required.include(.copy);
    for (parameter.requirements) |at| {
        try located(at, input.context.source.len);
        const spelling = input.context.source[at.start..at.end];
        const requirement: requirements.Requirement = if (std.mem.eql(u8, spelling, "copy"))
            .copy
        else if (std.mem.eql(u8, spelling, "equality"))
            .equality
        else if (std.mem.eql(u8, spelling, "integer"))
            .integer
        else if (std.mem.eql(u8, spelling, "storable"))
            .storable
        else
            return error.ComponentProtocol;
        required.include(requirement);
    }
    if (!required.accepts(argument, input.catalog.records)) return error.ComponentProtocol;
}
fn baseName(a: std.mem.Allocator, input: value.Input, at: source.Span) Error![]const u8 {
    try located(at, input.context.source.len);
    const leaf = input.context.source[at.start..at.end];
    if (input.modules.len == 0) return leaf;
    var low: usize = 0;
    var high = input.modules.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (input.modules[middle].offset <= at.start) low = middle + 1 else high = middle;
    }
    if (low == 0) return error.ComponentProtocol;
    const module = input.modules[low - 1];
    if (at.end > module.offset + module.context.source.len) return error.ComponentProtocol;
    return std.fmt.allocPrint(a, "{s}::{s}", .{ module.context.name, leaf });
}
/// Canonical names use runtime identity spellings, never source-facing diagnostics.
pub fn name(a: std.mem.Allocator, input: value.Input, key: instances.Key) Error![]const u8 {
    const declaration = @backingInt(key.declaration);
    if (declaration >= input.program.functions.len) return error.ComponentProtocol;
    const base = try baseName(a, input, input.program.functions[declaration].name);
    if (key.arguments.len == 0) return base;
    defer if (input.modules.len != 0) a.free(base);
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    output.writer.print("{s}[", .{base}) catch return error.OutOfMemory;
    for (key.arguments, 0..) |argument, index| {
        if (index != 0) output.writer.writeByte(',') catch return error.OutOfMemory;
        if (key.length(index)) |length| {
            output.writer.print("{d}", .{length}) catch return error.OutOfMemory;
        } else output.writer.writeAll(typed.typeName(argument, input.catalog.records)) catch return error.OutOfMemory;
    }
    output.writer.writeByte(']') catch return error.OutOfMemory;
    return output.toOwnedSlice();
}
/// Prove ordinary-prefix ownership, concrete keys, canonical names and prior demand.
/// Signature authentication is a separate adoption proof after recipe materialization.
fn concrete(input: value.Input, accepted: []const bool, parameters: []const @import("ast.zig").TypeParameter, key: instances.Key) Error!void {
    if (parameters.len == 0 or parameters.len > 16 or parameters.len != key.arguments.len or parameters.len != key.lengths.len) return error.ComponentProtocol;
    for (parameters, key.arguments, key.lengths) |parameter, argument, length| {
        if (!known(input, accepted, argument)) return error.ComponentProtocol;
        if (parameter.constant_length) {
            if (argument != .u64 or length == null or length.? > 1048576) return error.ComponentProtocol;
        } else {
            if (length != null) return error.ComponentProtocol;
            try promises(input, parameter, argument);
        }
    }
}
/// Authenticate declaration keys, ordinary ownership, and earlier-owner demand.
pub fn plan(a: std.mem.Allocator, input: value.Input, batch: value.Batch) Error!Plan {
    if (batch.functions.len > 65536 or batch.ranges.len != batch.functions.len) return error.ComponentProtocol;
    const keys = try a.alloc(instances.Key, batch.functions.len);
    errdefer a.free(keys);
    const ordinary = try a.alloc(?typed.FunctionId, input.program.functions.len);
    errdefer a.free(ordinary);
    @memset(ordinary, null);
    var declarations: std.AutoHashMapUnmanaged(source.Span, usize) = .empty;
    defer declarations.deinit(a);
    var ordinary_count: usize = 0;
    for (input.program.functions, 0..) |raw, declaration| {
        const entry = try declarations.getOrPut(a, raw.name);
        if (entry.found_existing) return error.ComponentProtocol;
        entry.value_ptr.* = declaration;
        if (raw.signature.type_parameters.len == 0) {
            if (ordinary_count >= batch.functions.len) return error.ComponentProtocol;
            ordinary[declaration] = @fromBackingInt(ordinary_count);
            keys[ordinary_count] = .{ .declaration = @fromBackingInt(declaration), .arguments = &.{} };
            ordinary_count += 1;
        }
    }
    const accepted = try policy.policy(a, input.catalog);
    defer a.free(accepted);
    var registry: instances.Registry = .{};
    defer registry.deinit(a);
    for (batch.functions, 0..) |function, id| {
        if (@backingInt(function.id) != id) return error.ComponentProtocol;
        const declaration = declarations.get(function.declaration) orelse return error.ComponentProtocol;
        const raw = input.program.functions[declaration];
        if (id < ordinary_count) {
            if (@backingInt(keys[id].declaration) != declaration or function.type_arguments.len != 0 or function.signature.constant_arguments.len != 0) return error.ComponentProtocol;
        } else {
            const parameters = raw.signature.type_parameters;
            const key: instances.Key = .{ .declaration = @fromBackingInt(declaration), .arguments = function.type_arguments, .lengths = function.signature.constant_arguments };
            try concrete(input, accepted, parameters, key);
            const ordinal = registry.intern(a, key) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.ComponentProtocol,
            };
            if (@backingInt(ordinal) != id - ordinary_count) return error.ComponentProtocol;
            keys[id] = key;
        }
        const expected_name = try name(a, input, keys[id]);
        defer if (input.modules.len != 0 or keys[id].arguments.len != 0) a.free(expected_name);
        if (!std.mem.eql(u8, expected_name, function.name)) return error.ComponentProtocol;
    }
    const demanded = try a.alloc(bool, batch.functions.len);
    defer a.free(demanded);
    @memset(demanded, false);
    for (batch.ranges, 0..) |range, caller| {
        if (range.nodes.start > range.nodes.end or range.nodes.end > batch.nodes.len) return error.ComponentProtocol;
        for (batch.nodes[range.nodes.start..range.nodes.end]) |node| switch (node.data) {
            .call => |call| {
                const callee = @backingInt(call.function);
                if (callee >= batch.functions.len) return error.ComponentProtocol;
                if (caller < callee) demanded[callee] = true;
            },
            else => {},
        };
    }
    for (ordinary_count..batch.functions.len) |id| if (!demanded[id]) return error.ComponentProtocol;
    return .{ .keys = keys, .ordinary = ordinary, .ordinary_count = ordinary_count };
}

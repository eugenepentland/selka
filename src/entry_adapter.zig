//! Normalize convenient guest entry results to the existing scalar runner ABI.
const std = @import("std");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;

const Builder = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(typed.Node),
    statements: std.ArrayList(typed.Statement),
    span: Span,

    fn node(self: *Builder, ty: typed.Type, data: @FieldType(typed.Node, "data")) !typed.NodeId {
        const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = self.span, .ty = ty, .data = data });
        return id;
    }
    fn statement(self: *Builder, data: @FieldType(typed.Statement, "data"), terminates: bool) !typed.StatementId {
        const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = self.span, .terminates = terminates, .data = data });
        return id;
    }
};

/// Name of the synthesized wrapper. It is not a source declaration, so nothing
/// exports it and no public interface names it.
pub const wrapper_name = "<entry>";

/// Accept unit or checked scalar-status results in addition to the legacy int entry.
pub fn supported(ty: typed.Type, records: []const typed.Record) bool {
    if (ty == .i64 or ty == .unit) return true;
    const shape = typed.resultShape(ty, records) orelse return false;
    return (shape.ok_type == .unit or shape.ok_type == .i64) and shape.error_type == .i64;
}

/// Element type of an entry point's optional first `list[str]` parameter.
/// Returns null when `ty` is any other shape.
pub fn argvElement(ty: typed.Type, records: []const typed.Record) ?typed.Type {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const list = records[ty.recordIndex()];
    if (!list.managed or list.collection.kind != .list) return null;
    const element = list.shape.buffer orelse return null;
    if (!element.isAggregate() or element.recordIndex() >= records.len) return null;
    const text = records[element.recordIndex()];
    if (!text.managed or text.collection.kind != .string) return null;
    return element;
}

/// Append a checked wrapper, preserving the user function's signature for ordinary calls.
pub fn adapt(allocator: std.mem.Allocator, program: *typed.Program) std.mem.Allocator.Error!void {
    const entry = program.functions[@backingInt(program.main)];
    const result_type = entry.signature.return_type;
    if (result_type == .i64) return;
    var builder: Builder = .{
        .allocator = allocator,
        .span = entry.declaration,
        .nodes = .empty,
        .statements = .empty,
    };
    try builder.nodes.appendSlice(allocator, program.nodes);
    try builder.statements.appendSlice(allocator, program.statements);
    const count = entry.signature.parameter_count;
    const arguments = try allocator.alloc(typed.NodeId, count);
    const shape = typed.resultShape(result_type, program.records);
    const payload_count: usize = if (shape) |result| (if (result.ok_type == .i64) @as(usize, 2) else 1) else 0;
    const locals = try allocator.alloc(typed.Local, count + payload_count);
    for (entry.scope.locals[0..count], arguments, locals[0..count], 0..) |parameter, *argument, *local, index| {
        local.* = parameter;
        local.usage = .{ .reads = 1, .temporary = true };
        argument.* = try builder.node(parameter.ty, .{ .local = @fromBackingInt(index) });
    }
    const call = try builder.node(result_type, .{ .call = .{ .function = entry.id, .arguments = arguments } });
    const zero = try builder.node(.i64, .{ .integer = 0 });
    const body = if (shape) |result| match_body: {
        const error_slot: typed.LocalId = @fromBackingInt(count);
        locals[count] = .{ .name = "<entry-error>", .declaration = entry.declaration, .ty = .i64, .mutable = false, .usage = .{ .reads = 1, .temporary = true } };
        const error_value = try builder.node(.i64, .{ .local = error_slot });
        const error_body = try builder.statement(.{ .ret = error_value }, true);
        var success_slot: ?typed.LocalId = null;
        var success_value = zero;
        if (result.ok_type == .i64) {
            success_slot = @fromBackingInt(count + 1);
            locals[count + 1] = .{ .name = "<entry-status>", .declaration = entry.declaration, .ty = .i64, .mutable = false, .usage = .{ .reads = 1, .temporary = true } };
            success_value = try builder.node(.i64, .{ .local = success_slot.? });
        }
        const success_body = try builder.statement(.{ .ret = success_value }, true);
        const arms = try allocator.dupe(typed.MatchArm, &.{
            .{ .tag = result.ok_tag, .slot = success_slot, .body = success_body },
            .{ .tag = result.error_tag, .slot = error_slot, .body = error_body },
        });
        break :match_body try builder.statement(.{ .match = .{ .value = call, .arms = arms } }, true);
    } else unit_body: {
        const discard = try builder.statement(.{ .discard = call }, false);
        const ret = try builder.statement(.{ .ret = zero }, true);
        const children = try allocator.dupe(typed.StatementId, &.{ discard, ret });
        break :unit_body try builder.statement(.{ .block = children }, true);
    };
    const functions = try allocator.alloc(typed.Function, program.functions.len + 1);
    @memcpy(functions[0..program.functions.len], program.functions);
    const id: typed.FunctionId = @fromBackingInt(program.functions.len);
    functions[program.functions.len] = .{
        .id = id,
        .name = wrapper_name,
        .declaration = entry.declaration,
        .signature = .{ .parameter_count = count, .return_type = .i64 },
        .scope = .{ .locals = locals, .body = body },
    };
    program.functions = functions;
    program.nodes = try builder.nodes.toOwnedSlice(allocator);
    program.statements = try builder.statements.toOwnedSlice(allocator);
    program.main = id;
}

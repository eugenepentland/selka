//! Copied Host calls use compiler schemas and existing box/record/call instructions.
const std = @import("std");
const typed = @import("selka").typed;
const ir = @import("ir.zig");
/// Allocation or a checked Host schema that cannot cross the copied boundary.
pub const Error = error{ OutOfMemory, Unsupported };

/// Evaluate Host and value arguments in order and invoke the copied-value adapter.
pub fn call(c: anytype, function: typed.Function, nodes: []const typed.NodeId, evaluation: ?typed.StatementId, span: u32) Error!ir.Ref {
    if (evaluation) |body| try c.statement(body);
    if (c.current == null) return .none;
    const values = try c.allocator().alloc(ir.Ref, nodes.len - 1);
    const host = try c.expression(nodes[0]);
    for (nodes[1..], values) |node, *value| value.* = try c.expression(node);
    _ = try c.effectCall("myl_core_host_check", &.{.cap}, .void, &.{host}, span);
    const params = try c.allocator().alloc(ir.Type, values.len);
    for (values, params) |value, *param| param.* = c.typeOfRef(value);
    const input = try c.module().intern(c.allocator(), .{ .record = params });
    const record = try c.emit(.{ .op = .record_make, .ty = input, .data = try c.extraSlice(values), .span = span });
    const box_type = try c.module().intern(c.allocator(), .{ .box = input });
    const box = try c.emit(.{ .op = .box_make, .ty = box_type, .a = record, .span = span });
    const metadata = try schema(c, function, input, span);
    const string_index = c.module().strings.items.len;
    try c.module().strings.append(c.allocator(), metadata);
    const text = try c.detached(.{ .op = .str_const, .ty = .str, .data = string_index });
    const ret = try c.mb.mapType(function.signature.return_type, span);
    const output_type = try c.module().intern(c.allocator(), .{ .box = if (ret == .void) .u64 else ret });
    const output = try c.effectCall("myl_core_host_invoke", &.{ .str, box_type }, output_type, &.{ text, box }, span);
    return if (ret == .void) .none else c.emit(.{ .op = .box_get, .ty = ret, .a = output, .span = span });
}

fn schema(c: anytype, function: typed.Function, input: ir.Type, span: u32) Error![]const u8 {
    var graph: Graph(@TypeOf(c)) = .{ .context = c, .span = span };
    const result = try graph.add(function.signature.return_type);
    const locals = function.scope.locals[1..function.signature.parameter_count];
    const params = try c.allocator().alloc(usize, locals.len);
    for (locals, params) |local, *parameter| parameter.* = try graph.add(local.ty);
    var output: std.ArrayList(u8) = .empty;
    var host_count: usize = 0;
    for (c.mb.input.program.functions) |declaration| if (declaration.policy.host != null and !declaration.policy.c_abi) {
        host_count += 1;
    };
    try output.print(c.allocator(), "{s}\n{d} {d} {d} {d} {d} {d}\n", .{ function.name, params.len, result, function.policy.effects, c.module().size(input), graph.definitions.items.len, host_count });
    for (params, 0..) |parameter, index| try output.print(c.allocator(), "{d} {d}\n", .{ parameter, c.module().fieldOffset(input, index) });
    for (c.mb.input.program.functions) |declaration| if (declaration.policy.host != null and !declaration.policy.c_abi) try output.print(c.allocator(), "{s}\n", .{declaration.name});
    for (graph.definitions.items) |definition| try output.appendSlice(c.allocator(), definition);
    return output.items;
}

fn Graph(comptime Context: type) type {
    return struct {
        context: Context,
        span: u32,
        seen: std.AutoHashMapUnmanaged(typed.Type, usize) = .empty,
        definitions: std.ArrayList([]const u8) = .empty,

        fn add(self: *@This(), ty: typed.Type) Error!usize {
            if (self.seen.get(ty)) |found| return found;
            const index = self.definitions.items.len;
            try self.seen.put(self.context.allocator(), ty, index);
            try self.definitions.append(self.context.allocator(), "");
            self.definitions.items[index] = try self.describe(ty);
            return index;
        }
        fn describe(self: *@This(), ty: typed.Type) Error![]const u8 {
            const c = self.context;
            const physical = try c.mb.mapType(ty, self.span);
            const name = if (ty.isAggregate()) c.mb.input.program.records[ty.recordIndex()].name else @tagName(ty);
            var shape: [6]u64 = .{ 1, c.module().size(physical), 0, 0, 1, 0 };
            var children: std.ArrayList(u64) = .empty;
            if (ty.integer()) |integer| {
                shape[4] = integer.bits;
                shape[5] = @intFromBool(integer.signed);
            } else if (ty == .bool) {} else if (ty == .unit) {
                shape[0] = 2;
            } else if (ty.isAggregate()) {
                const definition = c.mb.input.program.records[ty.recordIndex()];
                if (physical == .bytes) {
                    shape[0] = 6;
                } else if (definition.shape.domain) |wire| {
                    shape[0] = 5;
                    shape[2] = 1;
                    shape[4] = if (physical == .f64) 64 else 0;
                    try children.appendSlice(c.allocator(), &.{ try self.add(wire), 0 });
                } else if (definition.shape.array) |array| {
                    shape[0] = 3;
                    shape[2] = array.length;
                    shape[3] = c.module().size(c.module().compound(physical).array.elem);
                    try children.appendSlice(c.allocator(), &.{ try self.add(array.element), 0 });
                } else if (definition.shape.variants) |variants| {
                    shape[0] = 4;
                    shape[2] = variants.cases.len;
                    for (variants.cases) |variant| try children.appendSlice(c.allocator(), &.{ if (variant.payload) |payload| try self.add(payload) else std.math.maxInt(u64), 8 });
                } else if (definition.isRecord()) {
                    shape[0] = 2;
                    shape[2] = definition.fields.len;
                    for (definition.fields, 0..) |field, field_index| {
                        if (field.boxed) return c.mb.refuse("recursive Host value", self.span);
                        try children.appendSlice(c.allocator(), &.{ try self.add(field.ty), c.module().fieldOffset(physical, field_index) });
                    }
                } else return c.mb.refuse("Host copied-value type", self.span);
            } else return c.mb.refuse("Host copied-value type", self.span);
            var out: std.ArrayList(u8) = .empty;
            try out.print(c.allocator(), "{s}\n{d} {d} {d} {d} {d} {d}\n", .{ name, shape[0], shape[1], shape[2], shape[3], shape[4], shape[5] });
            for (children.items) |child| try out.print(c.allocator(), "{d} ", .{child});
            try out.append(c.allocator(), '\n');
            return out.items;
        }
    };
}

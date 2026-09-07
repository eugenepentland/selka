//! Conservative lifetime dependency analysis over checked function bodies. Local
//! dependencies are monotone across assignments/control flow; calls retain all
//! region-bearing argument dependencies rather than guessing callee behavior.
const std = @import("std");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const diagnostic = @import("diagnostic.zig");
const origin = @import("region_origin.zig");
const Dependency = origin.Dependency;
const grow = origin.grow;
const requireLimit = origin.requireLimit;
/// Whether a concrete value can retain arena authority or arena-owned storage.
pub fn carries(ty: typed.Type, types: []const bool) bool {
    return ty == .allocator or (ty.isAggregate() and types[ty.recordIndex()]);
}
const Analysis = struct {
    program: typed.Program,
    function: typed.Function,
    types: []const bool,
    nodes: []Dependency,
    locals: []Dependency,
    fn node(self: Analysis, id: typed.NodeId) Dependency {
        return self.nodes[@backingInt(id)];
    }
    fn local(self: Analysis, id: typed.LocalId) Dependency {
        return self.locals[@backingInt(id)];
    }
    fn reference(self: Analysis, id: typed.ReferenceId) Dependency {
        return self.local(self.function.scope.references[@backingInt(id)].owner);
    }
    fn arguments(self: Analysis, inputs: []const typed.NodeId) Dependency {
        var dependency: Dependency = .{};
        for (inputs) |input| dependency = origin.combine(dependency, self.node(input));
        return dependency;
    }
    fn fields(self: Analysis, inputs: []const typed.FieldInit) Dependency {
        var dependency: Dependency = .{};
        for (inputs) |input| dependency = origin.combine(dependency, self.node(input.value));
        return dependency;
    }
    fn call(self: Analysis, invocation: @FieldType(@FieldType(typed.Node, "data"), "call")) Dependency {
        var dependency = self.arguments(invocation.arguments);
        for (invocation.references) |id| {
            const ref = self.function.scope.references[@backingInt(id)];
            if (carries(ref.ty, self.types)) dependency = origin.combine(dependency, self.reference(id));
        }
        return dependency;
    }
    fn mutableArgument(self: Analysis, invocation: @FieldType(@FieldType(typed.Node, "data"), "call"), reference_index: usize) bool {
        const callee = self.program.functions[@backingInt(invocation.function)];
        var index: usize = 0;
        for (callee.scope.locals[0..callee.signature.parameter_count]) |parameter| if (parameter.parameter.reference_parameter) |mutable| {
            if (index == reference_index) return mutable;
            index += 1;
        };
        unreachable; // Checked reference argument count.
    }
    fn expression(self: Analysis, expression_node: typed.Node) Dependency {
        if (!carries(expression_node.ty, self.types)) return .{};
        return switch (expression_node.data) {
            .local => |id| self.local(id),
            .read_ref => |id| self.reference(id),
            .read_slice => |read| self.reference(read.reference),
            .read_field, .take_field => |read| self.local(read.owner),
            .acquire_buffer, .acquire_pool => |acquire| self.node(acquire.allocator),
            .json_codec => |codec| self.node(codec.arguments[0]),
            .reset_arena, .cast, .wrap, .unwrap, .length, .complete_resource => |value| self.node(value),
            .propagate => |propagate| self.node(propagate.value),
            .variant => |variant| if (variant.value) |value| self.node(value) else .{},
            .array => |inputs| self.arguments(inputs),
            .record => |inputs| self.fields(inputs),
            .update => |update| origin.combine(self.node(update.base), self.fields(update.fields)),
            .field => |field| self.node(field.base),
            .index => |index| self.node(index.base),
            .replace => |replace| origin.combine(self.node(replace.base), self.node(replace.value)),
            .call => |invocation| self.call(invocation),
            .buffer_operation => |operation| self.local(operation.owner),
            .pool_operation => |operation| self.local(operation.owner),
            .unary => |unary| self.node(unary.operand),
            .binary => |binary| origin.combine(self.node(binary.left), self.node(binary.right)),
            .integer, .boolean, .len_slice, .acquire_resource, .resource_io, .restrict_resource, .environment_get, .external_read => .{},
        };
    }
    fn writeReference(self: Analysis, id: typed.ReferenceId, value: typed.NodeId) bool {
        const ref = self.function.scope.references[@backingInt(id)];
        if (!carries(ref.ty, self.types)) return false;
        const owner_type = self.function.scope.locals[@backingInt(ref.owner)].ty;
        if (owner_type.isAggregate() and self.program.records[owner_type.recordIndex()].shape.buffer != null) return false;
        return grow(&self.locals[@backingInt(ref.owner)], self.node(value));
    }
    fn refLimit(self: Analysis, id: typed.ReferenceId) usize {
        const ref = self.function.scope.references[@backingInt(id)];
        const owner = self.function.scope.locals[@backingInt(ref.owner)];
        if (owner.ty.isAggregate() and self.program.records[owner.ty.recordIndex()].shape.buffer != null) return self.local(ref.owner).depth;
        return owner.ownership.arena_depth;
    }
    fn validateExpression(self: Analysis, expression_node: typed.Node, sink: *diagnostic.Sink) diagnostic.Error!void {
        switch (expression_node.data) {
            .propagate => |propagate| {
                const input = typed.resultShape(self.program.nodes[@backingInt(propagate.value)].ty, self.program.records).?;
                if (carries(input.error_type, self.types)) try requireLimit(self.node(propagate.value), 0, expression_node.span, sink);
            },
            .buffer_operation => |operation| {
                if (operation.kind == .append) try requireLimit(self.node(operation.arguments[0]), self.local(operation.owner).depth, expression_node.span, sink);
                if (operation.kind == .write or operation.kind == .resize) try requireLimit(self.node(operation.arguments[1]), self.local(operation.owner).depth, expression_node.span, sink);
            },
            .pool_operation => |operation| {
                if (operation.kind == .insert or operation.kind == .replace) try requireLimit(self.node(operation.arguments[if (operation.kind == .insert) 0 else 1]), self.local(operation.owner).depth, expression_node.span, sink);
            },
            .call => |invocation| {
                const dependency = self.call(invocation);
                for (invocation.references, 0..) |id, reference_index| {
                    const ref = self.function.scope.references[@backingInt(id)];
                    if (self.mutableArgument(invocation, reference_index) and carries(ref.ty, self.types)) try requireLimit(dependency, self.refLimit(id), expression_node.span, sink);
                }
            },
            else => {},
        }
    }
};

fn hasRegions(function: typed.Function) bool {
    for (function.scope.locals) |local| if (local.ownership.arena_depth != 0) return true;
    return false;
}

/// Validate that checked values and references do not escape their allocation regions.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
    var any_regions = false;
    for (program.functions) |function| any_regions = any_regions or hasRegions(function);
    if (!any_regions) return;
    const types = try typeDependencies(allocator, program.records);
    defer allocator.free(types);
    var changed = false;
    const nodes = try allocator.alloc(Dependency, program.nodes.len);
    defer allocator.free(nodes);
    @memset(nodes, .{});
    for (program.functions) |function| {
        // A helper without local regions cannot introduce a shorter lifetime;
        // callers conservatively propagate all argument/reference dependencies.
        if (!hasRegions(function)) continue;
        var walker = try walk.Walker.init(allocator, program, function.scope.body);
        defer walker.deinit();
        var items: std.ArrayList(walk.Item) = .empty;
        defer items.deinit(allocator);
        while (try walker.next()) |item| try items.append(allocator, item);
        const locals = try allocator.alloc(Dependency, function.scope.locals.len);
        defer allocator.free(locals);
        @memset(locals, .{});
        const analysis: Analysis = .{ .program = program, .function = function, .types = types, .nodes = nodes, .locals = locals };
        changed = true;
        while (changed) {
            changed = false;
            var i = items.items.len;
            while (i != 0) {
                i -= 1;
                changed = propagateDependencies(analysis, items.items[i]) or changed;
            }
        }
        for (items.items) |item| switch (item) {
            .expression => |id| try analysis.validateExpression(program.nodes[@backingInt(id)], sink),
            .statement => |id| {
                const statement = program.statements[@backingInt(id)];
                switch (statement.data) {
                    .ret => |value| try requireLimit(analysis.node(value), 0, statement.span, sink),
                    .ret_ref => |ref| try requireLimit(analysis.reference(ref), 0, statement.span, sink),
                    .initialize, .assign => |store| try requireLimit(analysis.node(store.value), function.scope.locals[@backingInt(store.slot)].ownership.arena_depth, statement.span, sink),
                    .write_ref => |write| try requireLimit(analysis.node(write.value), analysis.refLimit(write.reference), statement.span, sink),
                    .write_slice => |write| try requireLimit(analysis.node(write.value), analysis.refLimit(write.reference), statement.span, sink),
                    else => {},
                }
            },
        };
    }
}

/// Compute transitive arena-bearing concrete types for ordinary and generic checking.
pub fn typeDependencies(allocator: std.mem.Allocator, records: []const typed.Record) std.mem.Allocator.Error![]bool {
    const types = try allocator.alloc(bool, records.len);
    @memset(types, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, index| {
            if (recordDepends(record, types) and !types[index]) {
                types[index] = true;
                changed = true;
            }
        }
    }
    return types;
}

fn recordDepends(record: typed.Record, types: []const bool) bool {
    var depends = record.shape.buffer != null or record.shape.pool != null;
    if (record.shape.array) |array| {
        depends = array.length != 0 and carries(array.element, types);
    } else if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| {
            depends = depends or carries(payload, types);
        };
    } else for (record.fields) |field| {
        depends = depends or carries(field.ty, types);
    }
    return depends;
}

fn propagateDependencies(analysis: Analysis, item: walk.Item) bool {
    const program = analysis.program;
    const function = analysis.function;
    const types = analysis.types;
    const nodes = analysis.nodes;
    const locals = analysis.locals;
    var changed = false;
    switch (item) {
        .expression => |id| {
            const expression_node = program.nodes[@backingInt(id)];
            changed = grow(&nodes[@backingInt(id)], analysis.expression(expression_node)) or changed;
            if (expression_node.data == .call) {
                const invocation = expression_node.data.call;
                const dependency = analysis.call(invocation);
                for (invocation.references, 0..) |ref_id, reference_index| {
                    const ref = function.scope.references[@backingInt(ref_id)];
                    const owner_type = function.scope.locals[@backingInt(ref.owner)].ty;
                    const buffer = owner_type.isAggregate() and program.records[owner_type.recordIndex()].shape.buffer != null;
                    if (analysis.mutableArgument(invocation, reference_index) and carries(ref.ty, types) and !buffer) changed = grow(&locals[@backingInt(ref.owner)], dependency) or changed;
                }
            }
        },
        .statement => |id| switch (program.statements[@backingInt(id)].data) {
            .arena_scope => |scope| changed = grow(&locals[@backingInt(scope.slot)], .{
                .depth = function.scope.locals[@backingInt(scope.slot)].ownership.arena_depth,
                .scope = function.scope.locals[@backingInt(scope.slot)].declaration,
            }) or changed,
            .initialize, .assign => |store| changed = grow(&locals[@backingInt(store.slot)], analysis.node(store.value)) or changed,
            .match => |match| for (match.arms) |arm| {
                if (arm.slot) |slot| if (carries(function.scope.locals[@backingInt(slot)].ty, types)) {
                    changed = grow(&locals[@backingInt(slot)], analysis.node(match.value)) or changed;
                };
            },
            .write_ref => |write| changed = analysis.writeReference(write.reference, write.value) or changed,
            .write_slice => |write| changed = analysis.writeReference(write.reference, write.value) or changed,
            else => {},
        },
    }
    return changed;
}

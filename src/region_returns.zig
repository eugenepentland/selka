//! Bounded proofs of immutable parameter provenance and aggregate field projections.
const std = @import("std");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
/// A proven input parameter and ordered record-field path supplying the returned authority.
pub const Origin = struct { parameter: usize, fields: [16]usize = undefined, count: usize = 0 };
/// Immutable initializers may be followed; mutable or borrowed aliases stay conservative.
pub fn definitions(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error![]?typed.NodeId {
    const result = try allocator.alloc(?typed.NodeId, function.scope.locals.len);
    errdefer allocator.free(result);
    @memset(result, null);
    var walker = try walk.Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| if (item == .statement) {
        const statement = program.statements[@backingInt(item.statement)];
        if (statement.data != .initialize) continue;
        const slot = @backingInt(statement.data.initialize.slot);
        if (stable(function.scope.locals[slot])) result[slot] = statement.data.initialize.value;
    };
    return result;
}
fn stable(local: typed.Local) bool {
    return !local.mutable and local.usage.writes == 0 and !local.usage.mutable_borrow;
}
/// Select an exact field source where immutable construction proves it; otherwise return no proof.
pub fn select(program: typed.Program, bindings: []const ?typed.NodeId, id: typed.NodeId, path: []const usize, depth: usize) ?typed.NodeId {
    if (depth == 256) return null;
    if (path.len == 0) return id;
    return switch (program.nodes[@backingInt(id)].data) {
        .local => |slot| if (bindings[@backingInt(slot)]) |value| select(program, bindings, value, path, depth + 1) else null,
        .block_value => |block| select(program, bindings, block.value, path, depth + 1),
        .record => |fields| find: {
            for (fields) |field| if (field.index == path[0]) break :find select(program, bindings, field.value, path[1..], depth + 1);
            break :find null;
        },
        .update => |update| find: {
            for (update.fields) |field| if (field.index == path[0]) break :find select(program, bindings, field.value, path[1..], depth + 1);
            break :find select(program, bindings, update.base, path, depth + 1);
        },
        .field => |field| nested: {
            if (path.len == 16) break :nested null;
            var combined: [16]usize = undefined;
            combined[0] = field.index;
            @memcpy(combined[1 .. path.len + 1], path);
            break :nested select(program, bindings, field.base, combined[0 .. path.len + 1], depth + 1);
        },
        else => null,
    };
}
const Proof = struct {
    program: typed.Program,
    function: typed.Function,
    bindings: []const ?typed.NodeId,
    work: usize = 0,
    fn local(self: *Proof, slot: typed.LocalId, depth: usize) ?Origin {
        const index = @backingInt(slot);
        if (!stable(self.function.scope.locals[index])) return null;
        if (index < self.function.signature.parameter_count) return .{ .parameter = index };
        return self.expression(self.bindings[index] orelse return null, depth + 1);
    }
    fn field(self: *Proof, id: typed.NodeId, index: usize, depth: usize) ?Origin {
        if (select(self.program, self.bindings, id, &.{index}, 0)) |value| return self.expression(value, depth + 1);
        return append(self.expression(id, depth + 1) orelse return null, index);
    }
    fn expression(self: *Proof, id: typed.NodeId, depth: usize) ?Origin {
        if (depth == 256 or self.work == 100000) return null;
        self.work += 1;
        return switch (self.program.nodes[@backingInt(id)].data) {
            .local => |slot| self.local(slot, depth),
            .field => |field_value| self.field(field_value.base, field_value.index, depth),
            .read_field, .take_field => |read| projected: {
                if (self.bindings[@backingInt(read.owner)]) |value| break :projected self.field(value, read.field, depth);
                break :projected append(self.local(read.owner, depth) orelse return null, read.field);
            },
            .variant => |variant| self.expression(variant.value orelse return null, depth + 1),
            .wrap, .unwrap, .cast => |value| self.expression(value, depth + 1),
            .block_value => |block| self.expression(block.value, depth + 1),
            else => null,
        };
    }
};
fn append(input: Origin, field: usize) ?Origin {
    var result = input;
    if (result.count == result.fields.len) return null;
    result.fields[result.count] = field;
    result.count += 1;
    return result;
}
fn summarize(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error!?Origin {
    if (function.policy.host != null or function.signature.return_reference != null) return null;
    for (function.scope.locals[0..function.signature.parameter_count]) |parameter| {
        if (parameter.parameter.reference_parameter != null) return null;
    }
    const bindings = try definitions(allocator, program, function);
    defer allocator.free(bindings);
    var proof: Proof = .{ .program = program, .function = function, .bindings = bindings };
    var walker = try walk.Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    var selected: ?Origin = null;
    while (try walker.next()) |item| switch (item) {
        .expression => |id| if (program.nodes[@backingInt(id)].data == .propagate) return null,
        .statement => |id| {
            const statement = program.statements[@backingInt(id)];
            if (statement.data != .ret) continue;
            const current = proof.expression(statement.data.ret, 0) orelse return null;
            if (selected) |previous| {
                if (previous.parameter != current.parameter or previous.count != current.count) return null;
                if (!std.mem.eql(usize, previous.fields[0..previous.count], current.fields[0..current.count])) return null;
            }
            selected = current;
        },
    };
    return selected;
}
/// Unknown or ambiguous returns retain the caller's conservative all-input dependency.
pub fn collect(allocator: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error![]?Origin {
    const summaries = try allocator.alloc(?Origin, program.functions.len);
    errdefer allocator.free(summaries);
    for (program.functions, summaries) |function, *summary| summary.* = try summarize(allocator, program, function);
    return summaries;
}

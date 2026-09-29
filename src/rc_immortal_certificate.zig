//! Public constant-result convention, independent of parameter-anchored borrows.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");
const physical = @import("rc_readonly_plan.zig");
const Hash = std.crypto.hash.Blake3;
/// Bind the complete constant grammar and common physical preflight policy.
pub const version = "mylang-rc-immortal-entry-v2";

/// Only initialized constant bits and frozen bytes may leave this zero-arg body.
/// Public refusal is optional; allocation failure remains a compiler error.
pub fn certify(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?model.ImmortalCertificate {
    const code = function.scope.instructions;
    if (function.signature.parameter_count != 0 or function.policy.c_abi or function.policy.host != null) return null;
    if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return null;
    if (code.len == 0 or code.len > 128 or function.scope.locals.len > 32) return null;
    if (!(try catalog.get(function.signature.return_type)).counted) return null;
    var proof: Proof = .{ .catalog = catalog, .function = function };
    if (!try proof.safe(function.signature.return_type)) return null;
    for (function.scope.locals) |local| if (!try proof.safe(local.ty)) return null;
    var hash = Hash.init(.{});
    std.hash.autoHashStrat(&hash, version, .Deep);
    std.hash.autoHashStrat(&hash, abi, .Deep);
    std.hash.autoHashStrat(&hash, function.name, .Deep);
    hash.update(&(try catalog.native.layout(function.signature.return_type)).hash);
    for (function.scope.locals) |local| hash.update(&(try catalog.native.layout(local.ty)).hash);
    for (code, 0..) |instruction, pc| {
        if (!try proof.step(pc)) return null;
        try @import("rc_proof_identity.zig").operation(&hash, catalog, functions, instruction.op);
    }
    if (code[code.len - 1].op != .ret or proof.stack.len != 0) return null;
    var budget: physical.Budget = .{};
    if (!physical.quietReturns(catalog.native.records, function)) return null;
    if (!try physical.certify(catalog, functions, function, &budget)) return null;
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return .{ .shape_identity = (try catalog.native.layout(function.signature.return_type)).hash, .dependency_identity = digest };
}

const Stack = struct { values: [128]typed.Type = undefined, len: usize = 0 };
const Types = struct { values: [256]typed.Type = undefined, len: usize = 0 };
const Proof = struct {
    catalog: *shapes.Catalog,
    function: bytecode.Function,
    stack: Stack = .{},
    locals: [32]bool = @splat(false),
    remaining: usize = 4096,
    types: Types = .{},

    fn charge(self: *Proof, count: usize) bool {
        if (count > self.remaining) return false;
        self.remaining -= count;
        return true;
    }
    fn appendType(self: *Proof, ty: typed.Type) bool {
        for (self.types.values[0..self.types.len]) |known| if (known == ty) return true;
        if (self.types.len == self.types.values.len) return false;
        self.types.values[self.types.len] = ty;
        self.types.len += 1;
        return true;
    }
    fn safe(self: *Proof, ty: typed.Type) native.Error!bool {
        const first = self.types.len;
        if (!self.appendType(ty)) return false;
        var cursor = first;
        while (cursor < self.types.len) : (cursor += 1) {
            if (!self.charge(1)) return false;
            const current = self.types.values[cursor];
            const layout = try self.catalog.native.layout(current);
            if (layout.drop or layout.copy == .prohibited) return false;
            if (!current.isAggregate()) {
                if (current.integer() == null and current != .bool and current != .unit) return false;
                continue;
            }
            const record = self.catalog.native.records[current.recordIndex()];
            if (record.shape.builtin != .none) return false;
            if (record.managed) {
                if (!typed.isByteString(record) or record.shape.buffer != .u8) return false;
            } else switch (layout.kind) {
                .record => for (record.fields) |field| {
                    if (!self.charge(1) or !self.appendType(field.ty)) return false;
                },
                .array => if (!self.appendType(record.shape.array.?.element)) return false,
                .domain => if (!self.appendType(record.shape.domain.?)) return false,
                else => return false,
            }
        }
        return true;
    }
    fn push(self: *Proof, ty: typed.Type) native.Error!bool {
        if (self.stack.len == self.stack.values.len or !try self.safe(ty)) return false;
        self.stack.values[self.stack.len] = ty;
        self.stack.len += 1;
        return true;
    }
    fn pop(self: *Proof, ty: typed.Type) bool {
        if (self.stack.len == 0 or self.stack.values[self.stack.len - 1] != ty) return false;
        self.stack.len -= 1;
        return true;
    }
    fn step(self: *Proof, pc: usize) native.Error!bool {
        if (!self.charge(1)) return false;
        const code = self.function.scope.instructions;
        return switch (code[pc].op) {
            .push_i64 => self.push(.i64),
            .push_integer => |number| self.push(number.ty),
            .push_bool => self.push(.bool),
            .push_unit => self.push(.unit),
            .load_local => |id| blk: {
                const index = @backingInt(id);
                if (index >= self.function.scope.locals.len or !self.locals[index]) break :blk false;
                break :blk self.push(self.function.scope.locals[index].ty);
            },
            .store_local => |id| blk: {
                const index = @backingInt(id);
                if (index >= self.function.scope.locals.len or !self.pop(self.function.scope.locals[index].ty)) break :blk false;
                self.locals[index] = true;
                break :blk true;
            },
            .drop_local => |id| blk: {
                const index = @backingInt(id);
                if (index >= self.function.scope.locals.len) break :blk false;
                self.locals[index] = false;
                break :blk true;
            },
            .make_record => |record| self.construct(pc, record),
            .ret => pc + 1 == code.len and self.stack.len == 1 and self.pop(self.function.signature.return_type),
            else => false,
        };
    }
    fn construct(self: *Proof, pc: usize, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record")) native.Error!bool {
        if (!record.ty.isAggregate() or record.ty.recordIndex() >= self.catalog.native.records.len) return false;
        if (record.fields > self.stack.len or !self.charge(record.fields)) return false;
        const schema = self.catalog.native.records[record.ty.recordIndex()];
        const base = self.stack.len - record.fields;
        if (schema.managed) {
            if (!typed.isByteString(schema) or schema.shape.buffer != .u8) return false;
            if (!@import("constant_literal.zig").frozen(self.function.scope.instructions, pc, record, .u8, false)) return false;
        } else {
            const layout = try self.catalog.native.layout(record.ty);
            if (layout.kind != .record and layout.kind != .array) return false;
            if (record.fields != schema.count() or (record.order.len != 0 and record.order.len != record.fields)) return false;
            var seen: [128]bool = @splat(false);
            for (self.stack.values[base..self.stack.len], 0..) |value, i| {
                const member = if (record.order.len == 0) i else record.order[i];
                if (member >= record.fields or seen[member] or value != schema.elementType(member)) return false;
                seen[member] = true;
            }
        }
        self.stack.len = base;
        return self.push(record.ty);
    }
};

//! Every-return proof for a deliberately small physical borrowed-entry grammar.
//! Unknown instructions decline the optimization; canonical ownership remains.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");
const Hash = std.crypto.hash.Blake3;
/// Changing the accepted physical grammar changes every certificate identity.
pub const version = "mylang-rc-borrowed-entry-v1";
const Value = struct { ty: typed.Type, anchor: ?u32 = null };

/// Certify one readonly parameter projection on every reachable normal return.
/// The initial grammar is straight-line and has exactly one terminal return;
/// branches, calls, parameter stores, allocation, boxes and mutation decline it.
pub fn certify(allocator: std.mem.Allocator, catalog: *shapes.Catalog, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    const signature = function.signature;
    if (function.policy.c_abi or function.policy.host != null) return null;
    if (signature.mutates.len != 0 or signature.declared_mutates.len != 0) return null;
    const shape = try catalog.get(signature.return_type);
    if (!shape.counted) return null;
    if (shape.unique_drop or !shape.copyable) return null;
    if (signature.parameter_count > function.scope.locals.len) return null;
    for (function.scope.locals[0..signature.parameter_count]) |local| {
        if ((try catalog.get(local.ty)).unique_drop) return null;
    }
    const code = function.scope.instructions;
    if (code.len == 0 or code[code.len - 1].op != .ret) return null;
    const locals = try allocator.alloc(?Value, function.scope.locals.len);
    defer allocator.free(locals);
    @memset(locals, null);
    var proof: Proof = .{ .catalog = catalog, .function = function, .locals = locals };
    defer proof.stack.deinit(allocator);
    part(&proof.hash, version);
    part(&proof.hash, abi);
    part(&proof.hash, function.name);
    for (code[0 .. code.len - 1]) |instruction| {
        part(&proof.hash, @tagName(instruction.op));
        if (!try proof.step(allocator, instruction.op)) return null;
    }
    if (proof.stack.items.len != 1) return null;
    const result = proof.stack.items[0];
    if (result.ty != signature.return_type) return null;
    const parameter = result.anchor orelse return null;
    number(&proof.hash, parameter);
    const layout = try catalog.native.layout(result.ty);
    proof.hash.update(&layout.hash);
    var identity: [32]u8 = undefined;
    proof.hash.final(&identity);
    return .{ .parameter = parameter, .shape_identity = layout.hash, .dependency_identity = identity };
}

const Proof = struct {
    catalog: *shapes.Catalog,
    function: bytecode.Function,
    stack: std.ArrayList(Value) = .empty,
    locals: []?Value,
    hash: Hash = .init(.{}),

    fn step(self: *Proof, allocator: std.mem.Allocator, op: @FieldType(bytecode.Instruction, "op")) native.Error!bool {
        switch (op) {
            .load_local => |local| {
                const index = @backingInt(local);
                if (index >= self.locals.len) return false;
                if (index >= self.function.signature.parameter_count) {
                    try self.stack.append(allocator, self.locals[index] orelse return false);
                    number(&self.hash, index);
                    return true;
                }
                const ty = self.function.scope.locals[index].ty;
                const shape = try self.catalog.get(ty);
                const layout = try self.catalog.native.layout(ty);
                self.hash.update(&layout.hash);
                number(&self.hash, index);
                try self.stack.append(allocator, .{ .ty = ty, .anchor = if (shape.counted) @intCast(index) else null });
            },
            .store_local => |local| {
                const index = @backingInt(local);
                if (index < self.function.signature.parameter_count or index >= self.locals.len or self.stack.items.len == 0) return false;
                self.locals[index] = self.stack.pop().?;
                number(&self.hash, index);
            },
            .buffer_operation => |operation| return self.read(allocator, operation),
            .get_field => |index| return self.field(index),
            .get_index => |access| return self.projectIndex(access),
            .value_copy => |copy| {
                if (self.stack.items.len == 0 or (copy.site != .ret and copy.site != .assign)) return false;
                if (self.stack.items[self.stack.items.len - 1].ty != copy.ty) return false;
                if ((try self.catalog.get(copy.ty)).unique_drop) return false;
            },
            .push_i64 => |value| {
                number(&self.hash, @bitCast(value));
                try self.stack.append(allocator, .{ .ty = .i64 });
            },
            .push_integer => |value| {
                if (value.ty != .i64) return false;
                const integer = std.math.cast(i64, value.value) orelse return false;
                number(&self.hash, @bitCast(integer));
                try self.stack.append(allocator, .{ .ty = .i64 });
            },
            else => return false,
        }
        return true;
    }

    fn read(self: *Proof, allocator: std.mem.Allocator, operation: @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation")) native.Error!bool {
        const index = @backingInt(operation.owner);
        if (index >= self.locals.len) return false;
        const owner = self.locals[index] orelse return false;
        if (!owner.ty.isAggregate()) return false;
        const record = self.catalog.native.records[owner.ty.recordIndex()];
        if (record.collection.kind != .list or operation.kind != .read or self.stack.items.len == 0) return false;
        if (self.stack.items[self.stack.items.len - 1].ty != .i64) return false;
        if (record.shape.buffer != operation.output or (try self.catalog.get(operation.output)).unique_drop) return false;
        number(&self.hash, index);
        self.hash.update(&(try self.catalog.native.layout(owner.ty)).hash);
        _ = self.stack.pop();
        try self.stack.append(allocator, .{ .ty = operation.output, .anchor = if ((try self.catalog.get(operation.output)).counted) owner.anchor else null });
        return true;
    }

    fn field(self: *Proof, index: usize) native.Error!bool {
        if (self.stack.items.len == 0) return false;
        const value = &self.stack.items[self.stack.items.len - 1];
        const layout = try self.catalog.native.layout(value.ty);
        // Projecting an immutable box may materialize a private owned body.
        if (layout.kind != .record or index >= layout.fields.len) return false;
        const field_value = layout.fields[index];
        if (field_value.tag != null or (try self.catalog.get(field_value.ty)).unique_drop) return false;
        number(&self.hash, index);
        number(&self.hash, field_value.offset);
        self.hash.update(&layout.hash);
        value.ty = field_value.ty;
        if (!(try self.catalog.get(value.ty)).counted) value.anchor = null;
        return true;
    }

    fn projectIndex(self: *Proof, access: bytecode.Access) native.Error!bool {
        if (self.stack.items.len < 2) return false;
        const at = self.stack.items.len - 2;
        const source = self.stack.items[at];
        if (source.ty != access.ty or self.stack.items[at + 1].ty != .i64 or !source.ty.isAggregate()) return false;
        const record = self.catalog.native.records[source.ty.recordIndex()];
        const layout = try self.catalog.native.layout(source.ty);
        const element = if (layout.kind == .array and layout.fields.len == 1) layout.fields[0].ty else if (record.collection.kind == .list) record.shape.buffer orelse return false else return false;
        if ((try self.catalog.get(element)).unique_drop) return false;
        self.hash.update(&layout.hash);
        number(&self.hash, @intFromBool(access.from_end));
        self.stack.items[at] = .{ .ty = element, .anchor = if ((try self.catalog.get(element)).counted) source.anchor else null };
        self.stack.items.len -= 1;
        return true;
    }
};

fn number(hash: *Hash, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}
fn part(hash: *Hash, bytes: []const u8) void {
    number(hash, bytes.len);
    hash.update(bytes);
}

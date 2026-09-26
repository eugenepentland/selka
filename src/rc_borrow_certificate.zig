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
pub const version = "mylang-rc-borrowed-entry-v3";
const Value = struct { ty: typed.Type, anchor: ?u32 = null };

/// Certify a standalone function; direct calls require the program-aware entry.
pub fn certify(allocator: std.mem.Allocator, catalog: *shapes.Catalog, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    return certifyIn(allocator, catalog, &.{}, function, abi);
}

/// Every reachable return must contain only one parameter's edges or immortals.
/// Forward branch joins are exact; unknown operations, backedges and fresh heap
/// objects decline certification. Calls must independently prove immortal-only.
pub fn certifyIn(allocator: std.mem.Allocator, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    var traversal: Traversal = .{};
    const answer = (try analyze(.{ .allocator = allocator, .catalog = catalog, .functions = functions, .function = function, .abi = abi, .traversal = &traversal })) orelse return null;
    const parameter = answer.value.anchor orelse return null;
    return .{ .parameter = parameter, .shape_identity = (try catalog.native.layout(answer.value.ty)).hash, .dependency_identity = answer.identity };
}

const Answer = struct { value: Value, identity: [32]u8 };
const State = struct { stack: []Value, locals: []?Value };
// One root query has a bounded call depth and total state-copy work. Active
// instruction slices identify recursion without allocating another graph.
const Traversal = struct { active: [16]?[*]const bytecode.Instruction = @splat(null), depth: usize = 0, remaining: usize = 65536 };
const Input = struct { allocator: std.mem.Allocator, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8, traversal: *Traversal };
fn analyze(input: Input) native.Error!?Answer {
    const traversal = input.traversal;
    if (traversal.depth == traversal.active.len) return null;
    const code = input.function.scope.instructions;
    for (traversal.active[0..traversal.depth]) |active| if (active == code.ptr) return null;
    // Each supported instruction pushes at most one abstract value. This
    // bounds all copied local and stack states, including callees and joins.
    const width = std.math.add(usize, input.function.scope.locals.len, code.len) catch return null;
    const cells = std.math.mul(usize, code.len, width) catch return null;
    if (cells > traversal.remaining) return null;
    traversal.remaining -= cells;
    traversal.active[traversal.depth] = code.ptr;
    traversal.depth += 1;
    defer traversal.depth -= 1;
    if (!try admissible(input.catalog, input.function)) return null;
    var arena = std.heap.ArenaAllocator.init(input.allocator);
    defer arena.deinit();
    var scoped = input;
    scoped.allocator = arena.allocator();
    return flow(scoped);
}

fn admissible(catalog: *shapes.Catalog, function: bytecode.Function) native.Error!bool {
    const signature = function.signature;
    if (function.policy.c_abi or function.policy.host != null) return false;
    if (signature.mutates.len != 0 or signature.declared_mutates.len != 0) return false;
    const shape = try catalog.get(signature.return_type);
    if (!shape.counted) return false;
    if (shape.unique_drop or !shape.copyable) return false;
    if (signature.parameter_count > function.scope.locals.len) return false;
    for (function.scope.locals) |local| if ((try catalog.get(local.ty)).unique_drop) return false;
    return function.scope.instructions.len != 0;
}

fn flow(input: Input) native.Error!?Answer {
    const a = input.allocator;
    const code = input.function.scope.instructions;
    const incoming = try a.alloc(?State, code.len);
    @memset(incoming, null);
    const locals = try a.alloc(?Value, input.function.scope.locals.len);
    @memset(locals, null);
    for (0..input.function.signature.parameter_count) |index| {
        const ty = input.function.scope.locals[index].ty;
        locals[index] = .{ .ty = ty, .anchor = if ((try input.catalog.get(ty)).counted) @intCast(index) else null };
    }
    incoming[0] = .{ .stack = &.{}, .locals = locals };
    var proof: Proof = .{ .catalog = input.catalog, .function = input.function, .functions = input.functions, .abi = input.abi, .traversal = input.traversal, .locals = locals };
    part(&proof.hash, version);
    part(&proof.hash, input.abi);
    part(&proof.hash, input.function.name);
    number(&proof.hash, input.function.signature.parameter_count);
    for (input.function.scope.locals[0..input.function.signature.parameter_count]) |local| proof.hash.update(&(try input.catalog.native.layout(local.ty)).hash);
    var result: ?Value = null;
    for (code, 0..) |instruction, pc| {
        const state = incoming[pc] orelse continue;
        proof.locals = try a.dupe(?Value, state.locals);
        proof.stack = .empty;
        try proof.stack.appendSlice(a, state.stack);
        proof.pc = pc;
        number(&proof.hash, pc);
        std.hash.autoHashStrat(&proof.hash, instruction.op, .Deep);
        switch (instruction.op) {
            .ret => {
                if (proof.stack.items.len != 1) return null;
                const value = proof.stack.items[0];
                if (value.ty != input.function.signature.return_type) return null;
                if (result) |*prior| {
                    if (!mergeValue(prior, value)) return null;
                } else result = value;
                continue;
            },
            .jump => |target| {
                if (target <= pc or !try publish(a, incoming, target, proof)) return null;
                continue;
            },
            .jump_if_false => |target| {
                const condition = proof.stack.pop() orelse return null;
                if (condition.ty != .bool or target <= pc) return null;
                if (!try publish(a, incoming, target, proof)) return null;
            },
            else => if (!try proof.step(a, instruction.op)) return null,
        }
        if (!try publish(a, incoming, pc + 1, proof)) return null;
    }
    const value = result orelse return null;
    proof.hash.update(&(try input.catalog.native.layout(value.ty)).hash);
    var identity: [32]u8 = undefined;
    proof.hash.final(&identity);
    return .{ .value = value, .identity = identity };
}

fn mergeValue(destination: *Value, source: Value) bool {
    if (destination.ty != source.ty) return false;
    if (destination.anchor) |anchor| {
        if (source.anchor) |other| if (anchor != other) return false;
    } else destination.anchor = source.anchor;
    return true;
}

fn publish(a: std.mem.Allocator, incoming: []?State, target: usize, proof: Proof) native.Error!bool {
    if (target >= incoming.len) return false;
    const stack = proof.stack.items;
    if (incoming[target]) |state| {
        if (state.stack.len != stack.len) return false;
        for (state.stack, stack) |*destination, source| if (!mergeValue(destination, source)) return false;
        for (state.locals, proof.locals) |*destination, source| {
            if (destination.* != null and source != null) {
                if (!mergeValue(&destination.*.?, source.?)) return false;
            } else destination.* = null;
        }
    } else incoming[target] = .{ .stack = try a.dupe(Value, stack), .locals = try a.dupe(?Value, proof.locals) };
    return true;
}

const Proof = struct {
    catalog: *shapes.Catalog,
    function: bytecode.Function,
    functions: []const bytecode.Function,
    abi: []const u8,
    traversal: *Traversal,
    pc: usize = 0,
    stack: std.ArrayList(Value) = .empty,
    locals: []?Value,
    hash: Hash = .init(.{}),

    fn step(self: *Proof, allocator: std.mem.Allocator, op: @FieldType(bytecode.Instruction, "op")) native.Error!bool {
        switch (op) {
            .load_local, .move_local => |local| {
                const index = @backingInt(local);
                if (index >= self.locals.len) return false;
                const value = self.locals[index] orelse return false;
                self.hash.update(&(try self.catalog.native.layout(value.ty)).hash);
                try self.stack.append(allocator, value);
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
                if (self.stack.items.len == 0) return false;
                if (self.stack.items[self.stack.items.len - 1].ty != copy.ty) return false;
                if ((try self.catalog.get(copy.ty)).unique_drop) return false;
            },
            .push_i64 => |value| {
                number(&self.hash, @bitCast(value));
                try self.stack.append(allocator, .{ .ty = .i64 });
            },
            .push_integer => |value| {
                try self.stack.append(allocator, .{ .ty = value.ty });
            },
            .push_bool => try self.stack.append(allocator, .{ .ty = .bool }),
            .push_unit => try self.stack.append(allocator, .{ .ty = .unit }),
            .pop, .acknowledge => {
                _ = self.stack.pop() orelse return false;
            },
            .drop_local => |local| self.locals[@backingInt(local)] = null,
            .array_length => {
                if (self.stack.items.len == 0) return false;
                self.stack.items[self.stack.items.len - 1] = .{ .ty = .i64 };
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked => return self.binary(.i64, .i64),
            .cmp_i64 => return self.binary(.i64, .bool),
            .cmp_bool => return self.binary(.bool, .bool),
            .not_bool => return self.unary(.bool, .bool),
            .neg_i64_checked => return self.unary(.i64, .i64),
            .cast_integer => |ty| {
                if (self.stack.items.len == 0 or !ty.isInteger()) return false;
                const value = &self.stack.items[self.stack.items.len - 1];
                if (!value.ty.isInteger()) return false;
                value.* = .{ .ty = ty };
            },
            .assert_true => {
                return (self.stack.pop() orelse return false).ty == .bool;
            },
            .make_record => |record| return self.construct(allocator, record),
            .make_variant => |value| return self.variant(allocator, value),
            .call => |target| return self.call(allocator, target),
            else => return false,
        }
        return true;
    }

    fn binary(self: *Proof, input: typed.Type, output: typed.Type) bool {
        if ((self.stack.pop() orelse return false).ty != input) return false;
        return self.unary(input, output);
    }
    fn unary(self: *Proof, input: typed.Type, output: typed.Type) bool {
        if (self.stack.items.len == 0) return false;
        const value = &self.stack.items[self.stack.items.len - 1];
        if (value.ty != input) return false;
        value.* = .{ .ty = output };
        return true;
    }

    fn call(self: *Proof, allocator: std.mem.Allocator, target: typed.FunctionId) native.Error!bool {
        const index = @backingInt(target);
        if (index >= self.functions.len) return false;
        const callee = self.functions[index];
        const answer = (try analyze(.{ .allocator = allocator, .catalog = self.catalog, .functions = self.functions, .function = callee, .abi = self.abi, .traversal = self.traversal })) orelse return false;
        // Only immortal factories are admitted as calls, so a canonical owned
        // result cannot create an unjournaled runtime ownership obligation.
        if (answer.value.anchor != null) return false;
        const count = callee.signature.parameter_count;
        if (self.stack.items.len < count) return false;
        self.stack.items.len -= count;
        self.hash.update(&answer.identity);
        try self.stack.append(allocator, answer.value);
        return true;
    }

    fn construct(self: *Proof, allocator: std.mem.Allocator, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record")) native.Error!bool {
        if (self.stack.items.len < record.fields) return false;
        const schema = self.catalog.native.records[record.ty.recordIndex()];
        const layout = try self.catalog.native.layout(record.ty);
        const base = self.stack.items.len - record.fields;
        var result: Value = .{ .ty = record.ty };
        if (schema.isCollection()) {
            if (!self.frozen(record, schema)) return false;
        } else {
            if (layout.kind != .record and layout.kind != .array) return false;
            for (self.stack.items[base..]) |value| {
                if (result.anchor) |anchor| {
                    if (value.anchor) |other| if (anchor != other) return false;
                } else result.anchor = value.anchor;
            }
        }
        self.hash.update(&layout.hash);
        self.stack.items.len = base;
        try self.stack.append(allocator, result);
        return true;
    }

    fn frozen(self: *Proof, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record"), schema: typed.Record) bool {
        if (schema.collection.kind != .bytes and schema.collection.kind != .string) return false;
        if (record.order.len != 0 or self.pc < record.fields) return false;
        const element: typed.Type = if (schema.collection.kind == .string) .u32 else schema.shape.buffer.?;
        for (self.function.scope.instructions[self.pc - record.fields .. self.pc]) |instruction| switch (instruction.op) {
            .push_integer => |value| {
                if (value.ty != element) return false;
                if (schema.collection.kind == .string) {
                    if (value.value < 0 or value.value > 0x10ffff) return false;
                    if (value.value >= 0xd800 and value.value <= 0xdfff) return false;
                }
            },
            else => return false,
        };
        return true;
    }

    fn variant(self: *Proof, allocator: std.mem.Allocator, value: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_variant")) native.Error!bool {
        const schema = self.catalog.native.records[value.ty.recordIndex()].shape.variants orelse return false;
        if (value.tag >= schema.cases.len) return false;
        const payload = schema.cases[value.tag].payload;
        var result: Value = .{ .ty = value.ty };
        if (payload) |ty| {
            const source = self.stack.pop() orelse return false;
            if (source.ty != ty) return false;
            result.anchor = source.anchor;
        }
        self.hash.update(&(try self.catalog.native.layout(value.ty)).hash);
        try self.stack.append(allocator, result);
        return true;
    }

    fn read(self: *Proof, allocator: std.mem.Allocator, operation: @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation")) native.Error!bool {
        const index = @backingInt(operation.owner);
        if (index >= self.locals.len) return false;
        const owner = self.locals[index] orelse return false;
        if (!owner.ty.isAggregate()) return false;
        if (operation.kind == .length) {
            if (!operation.output.isInteger()) return false;
            try self.stack.append(allocator, .{ .ty = operation.output });
            return true;
        }
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

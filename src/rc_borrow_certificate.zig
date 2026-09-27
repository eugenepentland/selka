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
pub const version = "mylang-rc-borrowed-entry-v6";
const cfg = @import("rc_borrow_flow.zig");
const Value = cfg.Value;

/// Certify a standalone function; direct calls require the program-aware entry.
pub fn certify(allocator: std.mem.Allocator, catalog: *shapes.Catalog, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    return certifyIn(allocator, catalog, &.{}, function, abi);
}

/// Every reachable return must contain only one parameter's edges or immortals.
/// Monotone CFG joins converge before any physical return is accepted. Unknown
/// operations and fresh heap objects decline; callees need complete proofs.
pub fn certifyIn(allocator: std.mem.Allocator, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    // Scalar proofs are internal call dependencies, never alternate entries.
    if (!(try catalog.get(function.signature.return_type)).counted) return null;
    var traversal: Traversal = .{};
    const answer = (try analyze(.{ .allocator = allocator, .catalog = catalog, .functions = functions, .function = function, .abi = abi, .traversal = &traversal })) orelse return null;
    const parameter = answer.value.anchor orelse return null;
    return .{ .parameter = parameter, .shape_identity = (try catalog.native.layout(answer.value.ty)).hash, .dependency_identity = answer.identity };
}

const Answer = struct { value: Value, identity: [32]u8 };
const State = cfg.State;
// One root query has a bounded call depth and total state-copy work. Active
// instruction slices identify recursion without allocating another graph.
const Traversal = struct {
    active: [16]?[*]const bytecode.Instruction = @splat(null),
    depth: usize = 0,
    remaining: usize = 65536,
    work: usize = 524288,
    memo: Memo = .{},
};
// Retain every completed dependency: eviction could let a caller rely on a
// differently budgeted proof than the callee's independent emission query.
const Memo = struct {
    entries: [16]struct { target: usize, answer: ?Answer } = undefined,
    count: usize = 0,
};
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
    // Internal scalar helpers use the same closed grammar. Public alternate
    // entries still require a managed parameter anchor in certifyIn.
    const result = signature.return_type;
    const scalar = result.isInteger() or result == .bool or result == .unit;
    if (!shape.counted and !scalar) return false;
    if (shape.unique_drop or !shape.copyable) return false;
    if (signature.parameter_count > function.scope.locals.len) return false;
    for (function.scope.locals) |local| if ((try catalog.get(local.ty)).unique_drop) return false;
    return function.scope.instructions.len != 0;
}

fn flow(input: Input) native.Error!?Answer {
    const a = input.allocator;
    const code = input.function.scope.instructions;
    var graph = try cfg.Graph.init(a, code.len, input.function.scope.locals.len, &input.traversal.work);
    defer graph.deinit();
    const locals = try a.alloc(?Value, input.function.scope.locals.len);
    @memset(locals, null);
    for (0..input.function.signature.parameter_count) |index| {
        const ty = input.function.scope.locals[index].ty;
        locals[index] = .{ .ty = ty, .anchor = if ((try input.catalog.get(ty)).counted) @intCast(index) else null };
    }
    if (!try graph.publish(0, .{ .stack = &.{}, .locals = locals })) return null;
    var proof: Proof = .{ .catalog = input.catalog, .function = input.function, .functions = input.functions, .abi = input.abi, .traversal = input.traversal, .locals = locals };
    // Reuse one scratch state. Incoming arrays are allocated once per reachable
    // instruction and joined in place; backedges never allocate state copies.
    try proof.stack.ensureTotalCapacity(a, code.len + 1);
    while (graph.take()) |pc| {
        if (!graph.charge()) return null;
        proof.restore(graph.incoming[pc].?, pc);
        const op = code[pc].op;
        switch (op) {
            .ret => continue, // Inspect only the final converged incoming state.
            .jump => |target| {
                if (!try graph.publish(target, proof.state())) return null;
                continue;
            },
            .jump_if_false => |target| {
                if (!proof.condition() or !try graph.publish(target, proof.state())) return null;
            },
            else => if (!try proof.step(a, op)) return null,
        }
        if (!try graph.publish(pc + 1, proof.state())) return null;
    }
    // Hash in source order after convergence. Queue order and repeated visits
    // cannot change dependency identity; helper work shares the same bounds.
    proof.hash = .init(.{});
    part(&proof.hash, version);
    part(&proof.hash, input.abi);
    part(&proof.hash, input.function.name);
    number(&proof.hash, input.function.signature.parameter_count);
    for (input.function.scope.locals[0..input.function.signature.parameter_count]) |local| proof.hash.update(&(try input.catalog.native.layout(local.ty)).hash);
    var result: ?Value = null;
    for (code, 0..) |instruction, pc| {
        const state = graph.incoming[pc] orelse continue;
        if (!graph.charge()) return null;
        proof.restore(state, pc);
        number(&proof.hash, pc);
        std.hash.autoHashStrat(&proof.hash, instruction.op, .Deep);
        switch (instruction.op) {
            .ret => {
                if (proof.stack.items.len != 1) return null;
                const value = proof.stack.items[0];
                if (value.ty != input.function.signature.return_type) return null;
                if (result) |*prior| {
                    if (!cfg.merge(prior, value)) return null;
                } else result = value;
            },
            .jump => {},
            .jump_if_false => if (!proof.condition()) return null,
            else => if (!try proof.step(a, instruction.op)) return null,
        }
    }
    const value = result orelse return null;
    proof.hash.update(&(try input.catalog.native.layout(value.ty)).hash);
    var identity: [32]u8 = undefined;
    proof.hash.final(&identity);
    return .{ .value = value, .identity = identity };
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

    fn restore(self: *Proof, incoming: State, pc: usize) void {
        @memcpy(self.locals, incoming.locals);
        self.stack.clearRetainingCapacity();
        self.stack.appendSliceAssumeCapacity(incoming.stack);
        self.pc = pc;
    }
    fn state(self: *Proof) State {
        return .{ .stack = self.stack.items, .locals = self.locals };
    }
    fn condition(self: *Proof) bool {
        return (self.stack.pop() orelse return false).ty == .bool;
    }

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
                if (@import("value_semantics.zig").needsCopy(self.catalog.native.records, copy.ty)) return false;
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
        const count = callee.signature.parameter_count;
        if (self.stack.items.len < count or count > callee.scope.locals.len) return false;
        const base = self.stack.items.len - count;
        for (self.stack.items[base..], callee.scope.locals[0..count]) |argument, parameter|
            if (argument.ty != parameter.ty) return false;
        const answer = (try self.calleeProof(allocator, index)) orelse return false;
        var value = answer.value;
        if (value.anchor) |parameter| {
            if (parameter >= count) return false;
            value.anchor = self.stack.items[base + parameter].anchor;
            number(&self.hash, parameter);
            number(&self.hash, if (value.anchor) |anchor| @as(u64, anchor) + 1 else 0);
        }
        self.stack.items.len = base;
        self.hash.update(&answer.identity);
        try self.stack.append(allocator, value);
        return true;
    }

    fn calleeProof(self: *Proof, allocator: std.mem.Allocator, index: usize) native.Error!?Answer {
        const memo = &self.traversal.memo;
        for (memo.entries[0..memo.count]) |entry| if (entry.target == index) return entry.answer;
        if (memo.count == memo.entries.len) return null;
        const slot = memo.count;
        memo.count += 1;
        memo.entries[slot] = .{ .target = index, .answer = null };
        const answer = try analyze(.{ .allocator = allocator, .catalog = self.catalog, .functions = self.functions, .function = self.functions[index], .abi = self.abi, .traversal = self.traversal });
        memo.entries[slot].answer = answer;
        return answer;
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
        const element: typed.Type = if (schema.collection.kind == .string) .u32 else schema.shape.buffer.?;
        return @import("constant_literal.zig").frozen(self.function.scope.instructions, self.pc, record, element, schema.collection.kind == .string);
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

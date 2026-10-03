//! RC-LOCAL-LIST-1: one bounded scalar builder can live in frame scratch.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const runtime = @import("runtime_mode.zig");
const cow = @import("cow_plan.zig");
const Error = @import("qbe_rc_frame.zig").Error;
const Op = @FieldType(bytecode.Instruction, "op");
const prefix = 16;
const header = 72;
/// The sole builder and its fixed scalar payload within the certified frame.
pub const Proof = struct { pc: usize, owner: usize, capacity: usize, ty: typed.Type };

fn scalar(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}

/// The public literal lowers to a capacity push, acquire_buffer, its builder
/// local, and a straight sequence of scalar evaluations and appends. Refuse
/// a second constructor, managed inputs/results, calls, publication, mutation,
/// captures, arenas and every backedge throughout the complete activation.
fn constructor(comptime E: type, self: *E) ?Proof {
    const f = self.function;
    var proof: ?Proof = null;
    for (f.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op != .acquire_buffer) continue;
        if (proof != null or pc == 0 or pc + 1 >= f.scope.instructions.len) return null;
        const before = f.scope.instructions[pc - 1].op;
        const after = f.scope.instructions[pc + 1].op;
        if (before != .push_i64 or after != .store_local) return null;
        if (before.push_i64 <= 0 or before.push_i64 > 16) return null;
        const ty = instruction.op.acquire_buffer;
        const schema = self.program.records[ty.recordIndex()];
        if (schema.collection.kind != .list or !scalar(schema.shape.buffer.?)) return null;
        if (schema.shape.buffer.? == .unit) return null;
        proof = .{ .pc = pc, .owner = @backingInt(after.store_local), .capacity = @intCast(before.push_i64), .ty = ty };
    }
    return proof;
}

fn certify(comptime E: type, self: *E) ?Proof {
    if (!runtime.enabled() or runtime.counting() or self.heap_frame) return null;
    const f = self.function;
    if (f.policy.host != null or f.policy.c_abi or !scalar(f.signature.return_type)) return null;
    if (f.scope.instructions.len > 512 or f.scope.locals.len > 32) return null;
    if (f.signature.mutates.len != 0 or f.signature.declared_mutates.len != 0) return null;
    const found = constructor(E, self) orelse return null;
    for (f.scope.locals, 0..) |local, i| {
        if (self.byReference(i) or self.callerStorage(i)) return null;
        if (!scalar(local.ty) and (i < f.signature.parameter_count or local.ty != found.ty)) return null;
    }
    const state = self.cow orelse return null;
    const rc = state.rc orelse return null;
    if (rc.plan.scope_records.len != 0) return null;
    var appended: usize = 0;
    for (f.scope.instructions, 0..) |instruction, pc| {
        const building = pc <= found.pc + 1 or appended < found.capacity;
        if (!allowed(instruction.op, found, building, pc)) return null;
        if (instruction.op == .buffer_operation and instruction.op.buffer_operation.kind == .append) appended += 1;
        const capture = state.captures[pc];
        if (capture.begin != cow.none or capture.active != cow.none) return null;
        const site = state.plan.at(pc);
        if (site.unique_field != null or site.fill or site.capture) return null;
        if (site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return null;
        for (site.unique) |unique| {
            if (instruction.op != .buffer_operation or instruction.op.buffer_operation.kind != .append) return null;
            if (unique.local != found.owner or unique.alias != cow.none) return null;
        }
        if (self.states[pc]) |stack| {
            if (stack.len > 32) return null;
            for (stack) |ty| if (!scalar(ty) and ty != found.ty) return null;
        }
    }
    return if (appended == found.capacity) found else null;
}

fn allowed(op: Op, proof: Proof, building: bool, pc: usize) bool {
    return switch (op) {
        .acquire_buffer => pc == proof.pc,
        .buffer_operation => |operation| switch (operation.kind) {
            .append => building and pc > proof.pc + 1 and @backingInt(operation.owner) == proof.owner,
            .length, .read => !building,
            else => false,
        },
        .jump, .jump_if_false => |target| !building and target > pc,
        .load_local, .move_local => |slot| !building or @backingInt(slot) != proof.owner,
        .store_local => |slot| !building or @backingInt(slot) != proof.owner or pc == proof.pc + 1,
        .value_copy => |copy| scalar(copy.ty) or (!building and copy.ty == proof.ty),
        .push_integer => |value| scalar(value.ty),
        .cast_integer, .neg_integer, .acknowledge => |ty| scalar(ty),
        .binary_integer => |binary| scalar(binary.ty),
        .drop_local => |slot| !building or @backingInt(slot) != proof.owner,
        .push_i64,
        .push_bool,
        .push_unit,
        .pop,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .assert_true,
        => true,
        .ret => !building,
        else => false,
    };
}

/// Plans and stack states are final before temporary sizing. Cache their
/// immutable certificate once; a heap-backed relowering still refuses it.
fn proofFor(comptime E: type, self: *E) ?Proof {
    if (self.heap_frame) return null;
    if (!self.local_list_checked) {
        self.local_list_proof = certify(E, self);
        self.local_list_checked = true;
    }
    return self.local_list_proof;
}

/// A guarded receiver can be in this frame. Neither header nor element
/// pointers may claim the LLVM heap/stack disjointness of ordinary lists.
pub fn usesStack(comptime E: type, self: *E) bool {
    return proofFor(E, self) != null;
}

/// Count the immortal prefix, complete native header and fixed scalar payload
/// in the existing aux scratch pair before the normal frame-size admission.
pub fn scratchBytes(comptime E: type, self: *E, pc: usize) Error!u64 {
    const proof = proofFor(E, self) orelse return 0;
    if (proof.pc != pc) return 0;
    const element = self.program.records[proof.ty.recordIndex()].shape.buffer.?;
    return prefix + header + proof.capacity * (try self.layout(element)).size;
}

/// Emit an empty stack builder, or enter the unchanged located constructor.
pub fn begin(comptime E: type, self: *E, base: usize) Error!?usize {
    const proof = proofFor(E, self) orelse return null;
    if (proof.pc != self.pc) return null;
    const element = self.program.records[proof.ty.recordIndex()].shape.buffer.?;
    const label = self.temp();
    const admitted = self.temp();
    try self.print(" # RC-LOCAL-LIST-1\n storel 0, %aux{d}\n %v{d} =w call $myl_qbe_local_list(l %ctx, l ${s}, l {d})\n", .{ self.pc, admitted, try self.descriptor(element), proof.capacity });
    try self.print(" jnz %v{d}, @rclocal{d}, @rclocalslow{d}\n@rclocal{d}\n", .{ admitted, label, label, label });
    const object = self.temp();
    const payload = self.temp();
    const storage = self.temp();
    const descriptor = self.temp();
    try self.print(" %v{d} =l copy %aux{d}\n storel 2, %v{d}\n", .{ object, self.pc, object });
    try self.print(" %v{d} =l loadl $myl_native_list_header_type\n storel %v{d}, %v{d}\n", .{ descriptor, descriptor, try self.address(object, 8) });
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l add %v{d}, {d}\n", .{ payload, object, prefix, storage, payload, header });
    try self.print(" storel 0, %v{d}\n storel {d}, %v{d}\n storel 0, %v{d}\n", .{ payload, proof.capacity, try self.address(payload, 8), try self.address(payload, 16) });
    try self.print(" storel ${s}, %v{d}\n storel %v{d}, %v{d}\n", .{ try self.descriptor(element), try self.address(payload, 24), storage, try self.address(payload, 32) });
    for ([_]u64{ 40, 48, 56, 64 }) |offset| try self.print(" storel 0, %v{d}\n", .{try self.address(payload, offset)});
    try self.store(base, payload);
    try self.print(" jmp @rclocaldone{d}\n@rclocalslow{d}\n", .{ label, label });
    return label;
}

/// Only the admitted builder skips uniqueness and append helpers. The cold
/// path retains all original preparation, checks, ownership and publication.
pub fn beginAppend(comptime E: type, self: *E, pc: usize, stack: []const typed.Type) Error!?usize {
    const op = self.function.scope.instructions[pc].op;
    if (op != .buffer_operation or op.buffer_operation.kind != .append) return null;
    const proof = proofFor(E, self) orelse return null;
    const label = self.temp();
    const admitted = self.temp();
    try self.print(" %v{d} =l loadl %aux{d}\n jnz %v{d}, @rclocalappend{d}, @rclocalappendcold{d}\n@rclocalappend{d}\n", .{ admitted, proof.pc, admitted, label, label, label });
    const list = try self.load("l", proof.owner);
    const length = self.temp();
    const storage = self.temp();
    const element = self.program.records[proof.ty.recordIndex()].shape.buffer.?;
    const size = (try self.layout(element)).size;
    try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l loadl %v{d}\n", .{ length, list, storage, try self.address(list, 32) });
    const offset = self.temp();
    const destination = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, length, size, destination, storage, offset });
    try self.writeValue(destination, try self.load("s", stack.len - 1), element);
    const next = self.temp();
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n storel %v{d}, %v{d}\n", .{ next, length, next, list, next, try self.address(list, 16) });
    try self.print(" storel 0, %s{d}\n", .{stack.len - 1});
    try self.print(" jmp @rclocalappenddone{d}\n@rclocalappendcold{d}\n", .{ label, label });
    return label;
}

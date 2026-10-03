//! RC-PLAIN-UPDATE-CALL-1: which `mut` record parameters a function only
//! updates in their count-free fields.
//!
//! `frame.constants[read_byte(mut frame)]` passes the root of a borrowed list
//! to a callee. If the callee (and every callee it passes the parameter on
//! to) only ever assigns count-free fields of it (`frame.ip = frame.ip + 1`),
//! it cannot replace or release any list the record holds, so a borrow of
//! such a list survives the call. The proof reads bytecode only and refuses
//! every shape it does not recognize.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const shapes = @import("rc_shape.zig");
const branchTarget = bytecode.branchTarget;
const Op = @FieldType(bytecode.Instruction, "op");

/// How deep one query follows the parameter through further calls.
const depth_limit = 6;
/// The largest callee body one query scans.
const code_limit = 1024;

/// The facts one query reads: the counted-shape catalog and every function.
pub const Program = struct { catalog: *shapes.Catalog, functions: []const bytecode.Function };

/// Whether the `ref_local` at `pc` of `function` feeds the `mut` argument of
/// a direct call that only updates count-free fields of it: `ref_local r`,
/// plain pushes, then the call.
pub fn plainCall(program: Program, function: bytecode.Function, pc: usize) bool {
    return refConsumer(program, function, pc, depth_limit);
}

/// Whether the `store_local r` at `pc` stores back an update of count-free
/// fields of `r`'s own value, so no counted field of `r` changes.
pub fn plainStore(program: Program, function: bytecode.Function, pc: usize) bool {
    const code = function.scope.instructions;
    if (pc >= code.len or code[pc].op != .store_local) return false;
    return plainUpdate(program, function, pc, @backingInt(code[pc].op.store_local));
}

// Whether `function` writes its parameter `parameter` only by storing back an
// update of count-free fields of that parameter's own value, and passes it
// `mut` only to calls that do the same.
fn check(program: Program, function: bytecode.Function, parameter: usize, depth: usize) bool {
    const code = function.scope.instructions;
    if (function.physical) |facts| if (facts.unknown) return false;
    if (depth == 0 or code.len > code_limit or parameter >= function.signature.parameter_count) return false;
    if (!plainRecord(program, function.scope.locals[parameter].ty)) return false;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == parameter and !plainUpdate(program, function, pc, parameter)) return false,
        .ref_local => |id| if (@backingInt(id) == parameter and !refConsumer(program, function, pc, depth - 1)) return false,
        .move_local => |id| if (@backingInt(id) == parameter) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == parameter) return false;
        },
        else => {},
    };
    return !writesThroughPaths(program, function, parameter);
}

// `ref_local r; <plain pushes>; call f` where `f` only updates count-free
// fields of the parameter the reference lands in.
fn refConsumer(program: Program, function: bytecode.Function, pc: usize, depth: usize) bool {
    const code = function.scope.instructions;
    var at = pc + 1;
    var pushes: usize = 0;
    while (at < code.len and plainPush(code[at].op)) : (at += 1) pushes += 1;
    if (at >= code.len or code[at].op != .call) return false;
    const callee = program.functions[@backingInt(code[at].op.call)];
    const count = callee.signature.parameter_count;
    if (pushes >= count) return false;
    return check(program, callee, count - 1 - pushes, depth);
}

// `load_local q; <k plain pushes>; update_record fields; store_local r` where
// `q` is `r` or a copy of it and every updated field is count-free.
fn plainUpdate(program: Program, function: bytecode.Function, pc: usize, local: usize) bool {
    const code = function.scope.instructions;
    if (pc == 0 or code[pc - 1].op != .update_record) return false;
    const update = code[pc - 1].op.update_record;
    if (update.ty != function.scope.locals[local].ty) return false;
    const record = program.catalog.native.records[update.ty.recordIndex()];
    if (record.managed or !record.isRecord()) return false;
    const layout = program.catalog.native.layout(update.ty) catch return false;
    for (update.indices) |index| {
        if (index >= layout.fields.len) return false;
        const shape = program.catalog.get(layout.fields[index].ty) catch return false;
        if (shape.counted or shape.unique_drop) return false;
    }
    const k = update.indices.len;
    if (pc < k + 2) return false;
    for (code[pc - 1 - k .. pc - 1]) |value| if (!plainPush(value.op)) return false;
    const base = code[pc - 2 - k].op;
    if (base != .load_local) return false;
    return copyOf(function, @backingInt(base.load_local), local);
}

// `q` is `r`, or every store into `q` copies `r` straight in and nothing else
// writes it.
fn copyOf(function: bytecode.Function, copy: usize, local: usize) bool {
    if (copy == local) return true;
    const code = function.scope.instructions;
    var seen = false;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == copy) {
            if (pc == 0 or code[pc - 1].op != .load_local or @backingInt(code[pc - 1].op.load_local) != local) return false;
            seen = true;
        },
        .ref_local, .move_local => |id| if (@backingInt(id) == copy) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == copy) return false;
        },
        else => {},
    };
    return seen;
}

// RC-PLAIN-UPDATE-CALL-2: a local projected out of the parameter (a field
// chain, an element or entry read, an array element, or a copy of the
// parameter or of such a local) that is then mutated, moved, passed by
// reference, or loaded where a call or callback may write an argument, writes
// through the parameter: a nested write `r.items[0].append(x)` or a `mut`
// field or element argument `push(mut r.items)` changes (and, when the list
// is pinned or shared, clones and releases) a counted field.
fn writesThroughPaths(program: Program, function: bytecode.Function, parameter: usize) bool {
    const writing = writingCalls(program, function);
    for (0..function.scope.locals.len) |local| {
        if (local == parameter or !mutated(program, function, local, writing)) continue;
        if (derived(function, local, parameter, depth_limit)) return true;
    }
    return false;
}

// Whether `local` may hold a projection of `parameter`. An unrecognized
// producer or an exhausted bound answers yes.
fn derived(function: bytecode.Function, local: usize, parameter: usize, depth: usize) bool {
    if (local == parameter) return true;
    if (depth == 0) return true;
    const code = function.scope.instructions;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .store_local or @backingInt(instruction.op.store_local) != local) continue;
        switch (projectionRoot(code, pc)) {
            .fresh => {},
            .unknown => return true,
            .local => |root| if (root != local and derived(function, root, parameter, depth - 1)) return true,
        }
    }
    return false;
}

const Root = union(enum) { fresh, unknown, local: usize };

// The local the value stored at `pc` was projected out of: the base of a
// field chain, the receiver of a collection operation, or a copied local.
// A value that reaches the store along a branch is unrecognized.
fn projectionRoot(code: []const bytecode.Instruction, pc: usize) Root {
    if (pc == 0 or branchTarget(code, pc)) return .unknown;
    var at = pc - 1;
    while (at != 0 and code[at].op == .value_copy) : (at -= 1) {
        if (branchTarget(code, at)) return .unknown;
    }
    switch (code[at].op) {
        .get_field => {
            while (at != 0 and code[at].op == .get_field) : (at -= 1) {
                if (branchTarget(code, at)) return .unknown;
            }
            return if (code[at].op == .load_local) .{ .local = @backingInt(code[at].op.load_local) } else .unknown;
        },
        .buffer_operation => |operation| return .{ .local = @backingInt(operation.owner) },
        .load_local, .move_local => |id| return .{ .local = @backingInt(id) },
        .get_index => return .unknown,
        else => return .fresh,
    }
}

// Whether any direct call or callback in `function` may write an argument.
fn writingCalls(program: Program, function: bytecode.Function) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .invoke => return true,
        .call => |target| {
            const callee = program.functions[@backingInt(target)];
            if (callee.signature.mutates.len != 0 or callee.signature.declared_mutates.len != 0) return true;
        },
        else => {},
    };
    return false;
}

fn mutated(program: Program, function: bytecode.Function, local: usize, writing: bool) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .ref_local, .move_local => |id| if (@backingInt(id) == local) return true,
        .load_local => |id| if (writing and @backingInt(id) == local and managed(program, function.scope.locals[local].ty)) return true,
        .buffer_operation => |operation| if (@backingInt(operation.owner) == local and operation.kind != .read and operation.kind != .length) return true,
        else => {},
    };
    return false;
}

// A counted value a `mut` argument hands over by its payload, so a callee can
// write it in place. A plain record or fixed array crosses `mut` by address
// (`ref_local`), so loading one only reads it.
fn managed(program: Program, ty: typed.Type) bool {
    if (typed.referenceMut(program.catalog.native.records, ty)) return false;
    const shape = program.catalog.get(ty) catch return true;
    return shape.counted or shape.unique_drop;
}

fn plainPush(op: Op) bool {
    return switch (op) {
        .load_local, .push_i64, .push_integer, .push_bool, .push_unit => true,
        else => false,
    };
}

fn plainRecord(program: Program, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = program.catalog.native.records[ty.recordIndex()];
    return record.isRecord() and !record.managed and !record.isCollection();
}

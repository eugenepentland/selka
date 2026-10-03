//! Conservative bytecode inliner for callees that cannot allocate.
//!
//! Milestone 1 inlined only leaf functions whose every instruction could not
//! trap and could not allocate, so a splice could change no trap trace.
//! Milestone 2 admits callees that can trap but cannot allocate — the
//! bounds-checked scalar reads and the checked integer arithmetic the per-byte
//! tokenizer helpers are made of — and records provenance for every spliced
//! instruction. `src/qbe.zig` turns that provenance into one inline-frame record
//! per splice, and `fail()` in `src/qbe_runtime.c` replays the callee frames a
//! native call would have pushed, so trap text and `MYLANG-TRAP` JSON stay
//! byte-identical to the pre-inlining compiler.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;

/// Failures returned by the inliner.
pub const Error = error{ OutOfMemory, InternalError };

/// Largest callee body, in instructions, that may be inlined at any call site.
/// Widened from 32 to 48 by milestone 2 so the small remaining predicates
/// (`is_form` 42, `is_operator_char` 46, `is_atom_start` 40) join their siblings.
const max_instructions = 48;
/// Largest callee body that may be inlined where the call site runs inside a
/// loop of the caller. The per-byte tokenizer step `advance` is 52 instructions:
/// splicing it into the scan loops replaces a call with straight-line code that
/// QBE can keep in registers, while its cold call sites — one `"` skip, one
/// comment skip — keep the call instead of paying for a copy that runs once.
const max_loop_instructions = 64;
/// Largest callee local table that may be inlined.
const max_locals = 24;
/// Nominal nesting bound for the owned-resource test; deeper types are refused.
const max_type_depth = 16;

/// One function's current instruction stream, local table and eligibility.
const State = struct {
    instructions: []const bytecode.Instruction,
    locals: []const typed.Local,
    eligible: bool = false,
};

/// The parts of an eligible callee one splice needs.
const Callee = struct {
    id: typed.FunctionId,
    body: []const bytecode.Instruction,
    locals: []const typed.Local,
    params: usize,
};

/// Inline every eligible direct call in `program`, repeating until no function
/// changes, and return the rewritten program or the original when nothing
/// changed. Callees are processed before their callers, so a function that only
/// calls other eligible functions becomes eligible itself.
pub fn inlineProgram(allocator: std.mem.Allocator, program: bytecode.Program) Error!bytecode.Program {
    const states = try allocator.alloc(State, program.functions.len);
    for (program.functions, states) |function, *state| {
        state.* = .{ .instructions = function.scope.instructions, .locals = function.scope.locals };
    }
    var changed = false;
    var sweeping = true;
    while (sweeping) {
        sweeping = false;
        for (program.functions, 0..) |_, index| {
            states[index].eligible = eligible(program, index, states[index].instructions, states[index].locals);
        }
        for (states, 0..) |*state, index| {
            // A caller that opens an arena keeps its watermark locals untouched,
            // so the inliner never splices into one.
            if (containsArena(state.instructions)) continue;
            if (try rewrite(allocator, program, states, index)) |next| {
                state.* = next;
                state.eligible = eligible(program, index, state.instructions, state.locals);
                sweeping = true;
                changed = true;
            }
        }
    }
    if (!changed) return program;
    const functions = try allocator.alloc(bytecode.Function, program.functions.len);
    for (program.functions, states, functions) |function, state, *out| {
        out.* = function;
        out.scope = .{ .locals = state.locals, .instructions = state.instructions };
    }
    return .{ .functions = functions, .main = program.main, .records = program.records };
}

/// Whether function `index` of an already inlined program may be spliced into
/// a caller — the inliner's own test on that final body. A build that reuses a
/// caller's unit without lowering it (`EMIT-STANDIN-1`) keys the caller by what
/// it may have inlined.
pub fn eligibleFunction(program: bytecode.Program, index: usize) bool {
    const function = program.functions[index];
    return eligible(program, index, function.scope.instructions, function.scope.locals);
}

/// Whether one function may be inlined at a call site: a non-entry, non-host,
/// non-c_abi, non-conversion leaf within the size budget whose every instruction
/// is on the no-allocation allow-list and whose locals need no drop.
fn eligible(program: bytecode.Program, index: usize, code: []const bytecode.Instruction, locals: []const typed.Local) bool {
    if (index == @backingInt(program.main)) return false;
    const function = program.functions[index];
    const policy = function.policy;
    // `constant` is an AST-only policy: constant declarations are evaluated at
    // check time, so no lowered bytecode function carries it.
    if (policy.host != null or policy.c_abi or policy.conversion) return false;
    // ERROR-TRACE-1: a `return` of a result records its `Err` in the error
    // return trace from the callee's own frame, which a splice would not have.
    if (typed.resultShape(function.signature.return_type, program.records) != null) return false;
    if (code.len == 0 or code.len > max_loop_instructions) return false;
    if (locals.len > max_locals) return false;
    if (function.signature.parameter_count > locals.len) return false;
    // A `mut` fixed array (or, under value semantics, record) names its
    // caller's variable; a splice would bind a copy of it instead, so such a
    // callee keeps its call.
    for (function.signature.declared_mutates) |position| {
        if (position < locals.len and typed.referenceMut(program.records, locals[position].ty)) return false;
    }
    var returns = false;
    for (code) |instruction| {
        if (instruction.op == .ret) returns = true;
        if (!allowed(program, instruction.op)) return false;
    }
    if (!returns) return false;
    for (locals) |local| if (needsDrop(local.ty, program.records, 0)) return false;
    return true;
}

/// The no-allocation allow-list. Every opcode here lowers to straight-line IL, a
/// pure runtime helper (`myl_qbe_int_binary`, `myl_qbe_int_cast`,
/// `myl_qbe_int_neg`, `myl_qbe_float_unary`, `myl_native_owned_drop`) or a cold `myl_qbe_fail_*` trap
/// path, so no splice can run a collection and none needs a root. Explicitly
/// refused because their lowering can allocate or reach a host: `call` and
/// `invoke`, `make_record`/`make_variant` of a managed type, `buffer_operation`,
/// `acquire_buffer`/`acquire_resource`/`complete_resource`, `begin_arena`,
/// `end_arena` and `arena_escape`, `print` and `stream_write`, and every
/// file/resource/provider operation. `get_index` is admitted per operand type
/// because a `str` element read allocates; `update_record` and `switch_variant`
/// write through pointers or per-pc stack scratch and never the managed heap.
fn allowed(program: bytecode.Program, op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .push_i64,
        .push_bool,
        .push_unit,
        .push_integer,
        .load_local,
        .move_local,
        .store_local,
        .drop_local,
        .jump,
        .jump_if_false,
        .ret,
        .pop,
        .cmp_i64,
        .cmp_bool,
        .cmp_enum,
        .cmp_domain,
        .not_bool,
        .wrap_domain,
        .unwrap_domain,
        .get_field,
        .update_record,
        .array_length,
        .switch_variant,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        => true,
        // Checked scalar arithmetic and comparisons lower inline or through the
        // pure `myl_qbe_int_binary`; a trapping add or division only fails, it
        // never allocates. Aggregate integer forms are string/list operations.
        .binary_integer => |binary| binary.ty.isInteger(),
        // `sqrt`, `float(i)` and the other float conversions call the pure
        // `myl_qbe_float_unary`, which allocates nothing (INLINE-FLOAT-UNARY-1).
        .unary_float => true,
        .cast_integer => |ty| ty.isInteger(),
        .neg_integer => |ty| ty.isInteger(),
        .get_index => |access| indexIsAllocationFree(program, access.ty),
        else => false,
    };
}

/// Whether `get_index` on a receiver of type `ty` lowers without allocating. A
/// list, byte string or static array read after an inline bounds check is a load
/// from the receiver's own storage. A `str` read builds a one-character string
/// through `myl_native_text_at`, and a dictionary read names an aggregate key
/// scratch, so both stay calls. Only integer, boolean and unit elements qualify.
fn indexIsAllocationFree(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    if (record.collection.kind == .string or record.collection.kind == .dictionary) return false;
    const element = if (record.shape.array) |array| array.element else record.shape.buffer orelse return false;
    return element.isInteger() or element == .bool or element == .unit;
}

/// Whether a type needs owned-resource cleanup, so a cloned local would be
/// dropped by the caller's epilogue in addition to whatever the callee does.
/// Managed collections are GC-owned and are deliberately not drop types.
fn needsDrop(ty: typed.Type, records: []const typed.Record, depth: usize) bool {
    if (depth > max_type_depth) return true;
    if (ty.isFile()) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.contract.callback != null) return false;
    if (record.shape.resource != null) return true;
    if (record.shape.hasRuntimeIdentity() and record.contract.move_only) return true;
    if (record.shape.array) |array| return needsDrop(array.element, records, depth + 1);
    if (record.shape.domain) |backing| return needsDrop(backing, records, depth + 1);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| {
            if (needsDrop(payload, records, depth + 1)) return true;
        };
    }
    for (record.fields) |field| if (needsDrop(field.ty, records, depth + 1)) return true;
    return false;
}

/// Whether a caller opens an arena region, which the inliner never inlines into.
fn containsArena(code: []const bytecode.Instruction) bool {
    for (code) |instruction| if (instruction.op == .begin_arena) return true;
    return false;
}

/// The callee index one instruction may inline, or null when it stays a call.
/// An owner-scoped callee is only spliced into a caller of the same owner: its
/// `wrap`/`unwrap` operations are valid only inside that owner's scope. A callee
/// over the flat budget is only spliced where the call site repeats, which
/// `loops` marks.
fn inlineTarget(program: bytecode.Program, states: []const State, caller: usize, loops: []const bool, pc: usize) ?usize {
    const id = switch (states[caller].instructions[pc].op) {
        .call => |callee| callee,
        else => return null,
    };
    const index = @backingInt(id);
    if (index >= states.len or index == @backingInt(program.main)) return null;
    // Each splice keeps an entry marker outside the callee's trace range.
    // Native depth accounting checks its logical frame before entering it,
    // including calls made by the program's entry function.
    if (program.functions[index].policy.owner != null and program.functions[index].policy.owner != program.functions[caller].policy.owner) return null;
    if (!states[index].eligible) return null;
    if (states[index].instructions.len == 0) return null;
    if (states[index].instructions.len > max_instructions and !loops[pc]) return null;
    return index;
}

/// Mark every instruction inside a loop of one function's own control flow. The
/// lowering is structured — there is no `goto` — so a loop body is the
/// contiguous pc range ending at its backward branch, and a call site is hot
/// exactly when it falls inside one of those ranges. Over-marking only admits a
/// larger splice; nothing here changes what a splice means.
fn loopBody(allocator: std.mem.Allocator, code: []const bytecode.Instruction) Error![]bool {
    const loops = try allocator.alloc(bool, code.len);
    @memset(loops, false);
    for (code, 0..) |instruction, pc| {
        const entry: ?usize = switch (instruction.op) {
            .jump => |target| target,
            .jump_if_false => |target| target,
            .try_result => |propagate| propagate.error_target,
            .switch_variant => |dispatch| blk: {
                var lowest: ?usize = null;
                for (dispatch.arms) |arm| {
                    if (arm.target > pc) continue;
                    if (lowest == null or arm.target < lowest.?) lowest = arm.target;
                }
                break :blk lowest;
            },
            else => null,
        };
        if (entry) |start| {
            if (start <= pc) {
                for (loops[start .. pc + 1]) |*flag| flag.* = true;
            }
        }
    }
    return loops;
}

/// Rewrite one caller, or return null when it has no inlinable call site.
fn rewrite(allocator: std.mem.Allocator, program: bytecode.Program, states: []const State, caller: usize) Error!?State {
    const code = states[caller].instructions;
    const loops = try loopBody(allocator, code);
    defer allocator.free(loops);
    var any = false;
    for (code, 0..) |_, pc| if (inlineTarget(program, states, caller, loops, pc) != null) {
        any = true;
        break;
    };
    if (!any) return null;
    // Phase one: the new pc of every old pc, sized by the splice each inlined
    // call expands to. Phase two emits the same decision, so the two must agree.
    const base = try allocator.alloc(usize, code.len);
    var cursor: usize = 0;
    for (code, 0..) |_, index| {
        base[index] = cursor;
        if (inlineTarget(program, states, caller, loops, index)) |callee| {
            cursor += 1 + program.functions[callee].signature.parameter_count + states[callee].instructions.len;
        } else cursor += 1;
    }
    var instructions: std.ArrayList(bytecode.Instruction) = .empty;
    var locals: std.ArrayList(typed.Local) = .empty;
    try locals.appendSlice(allocator, states[caller].locals);
    for (code, 0..) |instruction, index| {
        if (inlineTarget(program, states, caller, loops, index)) |callee| {
            const view: Callee = .{
                .id = program.functions[callee].id,
                .body = states[callee].instructions,
                .locals = states[callee].locals,
                .params = program.functions[callee].signature.parameter_count,
            };
            try splice(allocator, view, instruction.span, base[index], &instructions, &locals);
        } else try instructions.append(allocator, .{
            .span = instruction.span,
            .op = try remapCaller(allocator, instruction.op, base),
            .inline_entry = instruction.inline_entry,
            // A splice from an earlier sweep keeps its callee and callee-local
            // pc, but its call-site pc moves with every instruction before it.
            .inline_origin = if (instruction.inline_origin) |origin| .{
                .callee = origin.callee,
                .callee_pc = origin.callee_pc,
                .call_position = base[origin.call_position],
            } else null,
        });
    }
    return .{ .instructions = try instructions.toOwnedSlice(allocator), .locals = try locals.toOwnedSlice(allocator) };
}

/// Replace one call with its argument stores followed by the callee's body,
/// whose locals are cloned into fresh caller-side slots at `base`. Every spliced
/// body instruction records its callee and callee-local pc plus the caller pc
/// that holds the call's source location, so the native trace can replay the
/// frames the removed call would have pushed.
fn splice(
    allocator: std.mem.Allocator,
    callee: Callee,
    span: Span,
    base: usize,
    instructions: *std.ArrayList(bytecode.Instruction),
    locals: *std.ArrayList(typed.Local),
) Error!void {
    const fresh = locals.items.len;
    try locals.appendSlice(allocator, callee.locals);
    // The call site is outside the new inline range even for a zero-argument
    // callee, so a refused frame reports only the callers already entered.
    try instructions.append(allocator, .{ .span = span, .op = .{ .jump = base + 1 }, .inline_entry = true });
    var remaining = callee.params;
    while (remaining > 0) {
        remaining -= 1;
        try instructions.append(allocator, .{ .span = span, .op = .{ .store_local = @fromBackingInt(fresh + remaining) } });
    }
    const body_base = base + 1 + callee.params;
    const continuation = body_base + callee.body.len;
    for (callee.body, 0..) |instruction, offset| {
        try instructions.append(allocator, .{
            .span = instruction.span,
            .op = try remapCallee(allocator, instruction.op, fresh, body_base, continuation),
            .inline_entry = instruction.inline_entry,
            .inline_origin = .{ .callee = callee.id, .callee_pc = offset, .call_position = base },
        });
    }
}

/// Shift one callee local slot into its fresh caller-side clone.
fn shift(slot: typed.LocalId, base: usize) typed.LocalId {
    return @fromBackingInt(base + @backingInt(slot));
}

/// Remap one spliced callee instruction: locals move to the clone range, branch
/// targets move to the spliced body, a `switch_variant` arm's target and payload
/// slot move with them, and `ret` leaves for the continuation.
fn remapCallee(allocator: std.mem.Allocator, op: @FieldType(bytecode.Instruction, "op"), fresh: usize, body_base: usize, continuation: usize) Error!@FieldType(bytecode.Instruction, "op") {
    return switch (op) {
        .ret => .{ .jump = continuation },
        .jump => |target| .{ .jump = body_base + target },
        .jump_if_false => |target| .{ .jump_if_false = body_base + target },
        .load_local => |slot| .{ .load_local = shift(slot, fresh) },
        .ref_local => |slot| .{ .ref_local = shift(slot, fresh) },
        .store_local => |slot| .{ .store_local = shift(slot, fresh) },
        .move_local => |slot| .{ .move_local = shift(slot, fresh) },
        .drop_local => |slot| .{ .drop_local = shift(slot, fresh) },
        .switch_variant => |dispatch| blk: {
            const arms = try allocator.alloc(bytecode.SwitchArm, dispatch.arms.len);
            for (dispatch.arms, arms) |arm, *out| out.* = .{
                .target = body_base + arm.target,
                .slot = if (arm.slot) |slot| shift(slot, fresh) else null,
            };
            break :blk .{ .switch_variant = .{ .ty = dispatch.ty, .arms = arms, .borrowed = dispatch.borrowed } };
        },
        else => op,
    };
}

/// Remap one surviving caller instruction whose targets moved because a
/// preceding call site expanded.
fn remapCaller(allocator: std.mem.Allocator, op: @FieldType(bytecode.Instruction, "op"), base: []const usize) Error!@FieldType(bytecode.Instruction, "op") {
    return switch (op) {
        .jump => |target| .{ .jump = base[target] },
        .jump_if_false => |target| .{ .jump_if_false = base[target] },
        .try_result => |propagate| .{ .try_result = .{ .input = propagate.input, .output = propagate.output, .error_target = base[propagate.error_target] } },
        .switch_variant => |dispatch| blk: {
            const arms = try allocator.alloc(bytecode.SwitchArm, dispatch.arms.len);
            for (dispatch.arms, arms) |arm, *out| out.* = .{ .target = base[arm.target], .slot = arm.slot };
            break :blk .{ .switch_variant = .{ .ty = dispatch.ty, .arms = arms, .borrowed = dispatch.borrowed } };
        },
        else => op,
    };
}

/// Count the direct call instructions still present in `program`; used by
/// tests to observe inlining without reaching into the pass internals.
pub fn callSites(program: bytecode.Program) usize {
    var count: usize = 0;
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (instruction.op == .call) count += 1;
    };
    return count;
}

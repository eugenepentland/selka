//! Parallel task groups (E1b): the lowering of `with parallel.group() as g:`, `g.submit(fn, ARGS)` and `t.result()`.
//!
//! A group is one runtime block, which Core IR types `box(i64)`: a managed owner whose scope end
//! (`myl_core_owned_group_end`) joins its tasks and consumes it on every exit edge. A handle is an i64, the index
//! of its task in the group's list. A submit builds one environment, a box of a record with a field per argument:
//! a scalar argument is stored as itself, and every managed argument sits in a box of its own.
//!
//! - A place passed to a parameter that is not `own` is lent. Its box is a lent box (`flags.lent_box`): it holds
//!   the lender's value without owning it and has no layout, so the environment never releases it. own.zig keeps
//!   the value alive until every group join, so the lender's drop follows the join.
//! - Any other managed argument is owned by the environment. An `own` parameter takes its box out of the
//!   environment (`myl_core_task_take`) and unboxes it. The environment's drop releases what the thunk left.
//! - A plain `str`, `bytes` or list parameter is lent as the view itself (FR58), beside a lent box of the owner a direct
//!   call passes with it; the environment is the one place a view is stored (`verify_ir.taskEnvironment`). Any other
//!   view argument is lent as its owner, and the thunk makes the view from the owner.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const typed = @import("selka").typed;
const build_cap = @import("build_cap.zig");
const parallel = @import("build_parallel.zig");

/// The lowering builder's allocation and unsupported-shape failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// The IR type of a task group: a box, so ownership treats the group as a managed owner.
pub fn groupType(module: *ir.Module, allocator: std.mem.Allocator) Error!ir.Type {
    return module.intern(allocator, .{ .box = .i64 });
}

/// One argument of a submit, as the environment and the thunk see it.
const Arg = struct {
    /// The type of the value the thunk works with: the argument's own type, or the owner of a view.
    value: ir.Type,
    /// Whether the environment holds the value in a box of its own.
    boxed: bool,
    /// Whether the thunk takes the box out of the environment, because the callee's parameter is `own`.
    take: bool,
    /// The environment field that holds the value or its box.
    field: u32,
    /// For a lent view parameter (FR58): the field of the lent box of its cache owner, which the thunk passes after
    /// the arguments, as a direct call does.
    owner: ?Owner = null,
};

/// The cache owner of a lent view parameter: its type and the environment field of its lent box.
const Owner = struct { ty: ir.Type, field: u32 };

/// What the thunk unpacks and calls: the environment, its record, one entry per argument, and the callee.
const Plan = struct {
    env: ir.Type,
    record: ir.Type,
    args: []const Arg,
    callee: u32,
    span: u32,
};

/// `with parallel.group() as g:` (E1b): open the group into the scope's local, lower the body, and join on every exit
/// edge. The scope closes through `build_cap.closeScope`, as every other resource does.
pub fn scope(comptime Context: type, c: Context, slot: typed.LocalId, body: typed.StatementId, span: u32) Error!void {
    const group_type = try groupType(&c.mb.module, c.allocator());
    const group = try c.runtimeCall("myl_core_group_open", &.{}, group_type, &.{}, span);
    if (c.current == null) return;
    try c.write(c.local(slot), c.current.?, group);
    const cleanup: build_cap.Scope = .{ .owner = group, .depth = c.loops.items.len, .group = true };
    try c.ssa.resources.append(c.allocator(), cleanup);
    try c.statement(body);
    if (c.current != null) try build_cap.closeScope(Context, c, cleanup, span);
    _ = c.ssa.resources.pop();
}

/// `g.submit(fn, ARGS)` (E1b): build the task's environment from the arguments, start the task on the group, and
/// return its index in the group's task list. The checker has already checked `fn(ARGS)` as a direct call.
pub fn submit(comptime Context: type, c: Context, group_local: typed.LocalId, call_node: typed.NodeId, span: u32) Error!ir.Ref {
    const mb = c.mb;
    const m = &mb.module;
    const arena = c.allocator();
    const call = c.nodeOf(call_node).data.call;
    const checked = mb.input.program.functions[@backingInt(call.function)];
    if (checked.policy.host != null or checked.policy.c_abi) return mb.refuse("a task that calls a host or C function", span);
    if (checked.signature.declared_mutates.len != 0) return mb.refuse("invalid checked task callee with a mut parameter", span);
    const callee = try mb.functionIndex(call.function);
    const callee_params = m.functions.items[callee].signature.params;
    // The callee takes each passed argument in order; borrowed text and list parameters append their owners after them.
    if (callee_params.len < call.arguments.len) return mb.refuse("a task argument list that does not match its function", span);
    const owned = checked.scope.own_parameters;
    // The group rides in a lent box's second operand, so own.zig keeps a lent value alive to the joins of its own group (E1b).
    const group = try c.read(c.local(group_local), c.current.?);
    var fields: std.ArrayList(ir.Ref) = .empty;
    var field_types: std.ArrayList(ir.Type) = .empty;
    const args = try arena.alloc(Arg, call.arguments.len);
    for (call.arguments, 0..) |argument, position| {
        const evaluated = try c.expression(argument);
        if (c.current == null) return .none;
        const value = try c.borrowStorage(evaluated, span);
        const ty = c.typeOfRef(value);
        if (ty == .void) return mb.refuse("a task argument of type Unit", span);
        const takes = position < owned.len and owned[position];
        const lent = !takes and @import("task_lending.zig").isPlace(mb.input.program, argument);
        var boxed_value = value;
        var value_type = ty;
        var is_boxed = false;
        var data: u64 = 0;
        if (!takes and lendsView(Context, c, value, callee_params[position])) {
            args[position] = try lendView(Context, c, .{ .fields = &fields, .types = &field_types }, value, group, span);
            continue;
        }
        if (ty.isSpan() or m.kind(ty) == .list_view) {
            if (takes) return mb.refuseOwnership("a view passed to an own parameter of a task", span);
            const owner = try taskOwner(Context, c, value, span);
            if (c.function.inst(c.function.resolve(owner)).op == .text_sentinel) {
                // A view with no owner is a slice: a view parameter is lent as the view above (lendView).
                const given: []const u8 = switch (ty) {
                    .str_view => "a slice of text given to a task",
                    .bytes_view => "a slice of bytes given to a task",
                    else => "a slice of a list given to a task",
                };
                return mb.refuseOwnershipHint(given, "a slice has no owner to lend, so copy it into a local first", span);
            }
            boxed_value = owner;
            value_type = c.typeOfRef(owner);
            is_boxed = true;
            data = flags.lent_box;
        } else if (m.managed(ty)) {
            is_boxed = true;
            data = if (lent) flags.lent_box else 0;
        }
        args[position] = .{ .value = value_type, .boxed = is_boxed, .take = takes and is_boxed, .field = @intCast(fields.items.len) };
        if (is_boxed) {
            const box_type = try m.intern(arena, .{ .box = value_type });
            try fields.append(arena, try c.emit(.{ .op = .box_make, .ty = box_type, .a = boxed_value, .b = if (data & flags.lent_box != 0) group else .none, .data = data, .span = span }));
            try field_types.append(arena, box_type);
        } else {
            try fields.append(arena, value);
            try field_types.append(arena, ty);
        }
    }
    const record = try m.intern(arena, .{ .record = field_types.items });
    const built = try c.emit(.{ .op = .record_make, .ty = record, .data = try c.extraSlice(fields.items), .span = span });
    const env = try m.intern(arena, .{ .box = record });
    const env_box = try c.emit(.{ .op = .box_make, .ty = env, .a = built, .span = span });
    const callee_ret = m.functions.items[callee].signature.ret;
    const boxed_result = try m.intern(arena, .{ .box = if (callee_ret == .void) .bool else callee_ret });
    const thunk_type = try m.intern(arena, .{ .@"fn" = .{ .params = try arena.dupe(ir.Type, &.{env}), .ret = boxed_result } });
    const thunk = try buildThunk(Context, c, .{ .env = env, .record = record, .args = args, .callee = callee, .span = span });
    const group_type = try groupType(m, arena);
    const run = try c.detached(.{ .op = .func_ref, .ty = thunk_type, .data = thunk });
    const submit_fn = try mb.runtimeFunction("myl_core_owned_task_submit_indexed", &.{ group_type, thunk_type, env, .i64 }, .i64, .extern_c);
    const item = try c.constant(.i64, -1);
    return c.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(@intCast(submit_fn)), .data = try c.extraSlice(&.{ group, run, env_box, item }), .span = span });
}

/// The environment's fields as a submit builds them: one value and its type each.
const Fields = struct { fields: *std.ArrayList(ir.Ref), types: *std.ArrayList(ir.Type) };

/// Lend view parameter `value` to a task as the view itself (FR58), as a direct call passes it: the caller's slice, not
/// the whole of its cache owner. The environment holds the view and a lent box of the C9 owner a direct call passes with
/// it: the parameter's trailing owner (the sentinel at run time when the caller passed a slice), or for a bytes view, which
/// has none, the static sentinel, which the thunk does not pass. The parameter outlives this call, and the group joins
/// before the call returns.
fn lendView(comptime Context: type, c: Context, out: Fields, value: ir.Ref, group: ir.Ref, span: u32) Error!Arg {
    const m = &c.mb.module;
    const arena = c.allocator();
    const ty = c.typeOfRef(value);
    const owner = try c.passedOwner(value);
    const owner_type = c.typeOfRef(owner);
    const box_type = try m.intern(arena, .{ .box = owner_type });
    const field: u32 = @intCast(out.fields.items.len);
    try out.fields.append(arena, value);
    try out.types.append(arena, ty);
    // For a bytes view this box of the static sentinel stands for no loan: the thunk never reads it. It exists so that the
    // record consumes something and is owned, so boxing it passes J5 (`consume-borrowed`); a record that only read the view
    // would be borrowed. One `myl_core_box_new` block per such submit. For text and lists it is the owner a call passes.
    try out.fields.append(arena, try c.emit(.{ .op = .box_make, .ty = box_type, .a = owner, .b = group, .data = flags.lent_box, .span = span }));
    try out.types.append(arena, box_type);
    return .{ .value = ty, .boxed = false, .take = false, .field = field, .owner = .{ .ty = owner_type, .field = field + 1 } };
}

/// Whether argument `value` is a view parameter the callee takes as that same view (FR58), so the task is lent it as is.
fn lendsView(comptime Context: type, c: Context, value: ir.Ref, wanted: ir.Type) bool {
    const ty = c.typeOfRef(value);
    if (ty != wanted or !c.mb.module.isView(ty)) return false;
    return c.function.inst(c.function.resolve(value)).op == .param;
}

/// A whole const view lends the storage it reads. Parameters keep their
/// existing owner convention; a slice never becomes a view of the whole owner.
fn taskOwner(comptime Context: type, c: Context, value: ir.Ref, span: u32) Error!ir.Ref {
    const instruction = c.function.inst(c.function.resolve(value));
    if (instruction.op == .list_view_of) return c.borrowStorage(instruction.a, span);
    if (wholeTextView(Context, c, instruction)) return c.borrowStorage(instruction.a, span);
    return c.passedOwner(value);
}

fn wholeTextView(comptime Context: type, c: Context, instruction: ir.Inst) bool {
    if (instruction.op != .str_view_of) return false;
    const first = c.function.inst(c.function.resolve(instruction.b));
    if (first.op != .iconst or first.data != 0) return false;
    const lengths = c.function.operands(instruction.data);
    if (lengths.len != 1) return false;
    const length = c.function.inst(c.function.resolve(lengths[0]));
    if (length.op != .str_len and length.op != .list_len) return false;
    return c.function.resolve(length.a) == c.function.resolve(instruction.a);
}

/// `t.result()` (E1b): join the handle's task through its group and take its value out of the result box.
pub fn result(comptime Context: type, c: Context, handle: typed.LocalId, ty: typed.Type, span: u32) Error!ir.Ref {
    const mb = c.mb;
    const value_type = try mb.mapType(ty, span);
    if (value_type == .void) return mb.refuse("reading the result of a task that returns nothing", span);
    const group_local = c.task_groups.get(c.local(handle)) orelse return mb.refuse("invalid checked task result without its group", span);
    const group = try c.read(group_local, c.current.?);
    const index = try c.read(c.local(handle), c.current.?);
    const group_type = try groupType(&mb.module, c.allocator());
    const boxed_type = try mb.module.intern(c.allocator(), .{ .box = value_type });
    const take = try mb.runtimeFunction("myl_core_owned_group_take", &.{ group_type, .i64 }, boxed_type, .extern_c);
    const boxed = try c.emit(.{ .op = .call, .ty = boxed_type, .a = @fromBackingInt(@intCast(take)), .data = try c.extraSlice(&.{ group, index }), .span = span });
    return c.emit(.{ .op = .box_take, .ty = value_type, .a = boxed, .span = span });
}

/// A `const` handle initialised by a submit to `group_local` (E1b): its `result` reads that group.
pub fn bindHandle(c: anytype, handle: typed.LocalId, group_local: typed.LocalId) Error!void {
    try c.task_groups.put(c.allocator(), c.local(handle), c.local(group_local));
}

/// Build the thunk a task runs: it reads the environment, takes or borrows each argument, calls the callee with the
/// arguments the callee's parameters expect (a view with its owner, as a direct call passes it), and returns the result
/// boxed, so the group's `result` can take it. Returns the thunk's function index.
fn buildThunk(comptime Context: type, c: Context, plan: Plan) Error!u32 {
    const mb = c.mb;
    const m = &mb.module;
    const arena = c.allocator();
    const callee_ret = m.functions.items[plan.callee].signature.ret;
    const callee_params = m.functions.items[plan.callee].signature.params;
    const boxed_result = try m.intern(arena, .{ .box = if (callee_ret == .void) .bool else callee_ret });
    const thunk_type = try m.intern(arena, .{ .@"fn" = .{ .params = try arena.dupe(ir.Type, &.{plan.env}), .ret = boxed_result } });
    const name = try mb.generatedName(.task_thunk, "task.thunk");
    var w = try parallel.Writer.init(arena, .{ .name = name, .signature = m.compound(thunk_type).@"fn", .span = plan.span });
    const env = try w.emit(.{ .op = .param, .ty = plan.env, .data = 0 });
    const record = try w.emit(.{ .op = .box_get, .ty = plan.record, .a = env, .span = plan.span });
    const values = try arena.alloc(ir.Ref, plan.args.len);
    // A lent view parameter's cache owner follows every argument, as a direct call passes it (FR58); a bytes view has none.
    const view_owners = try arena.alloc(?ir.Ref, plan.args.len);
    for (plan.args, 0..) |arg, position| {
        view_owners[position] = null;
        const field_type = m.compound(plan.record).record[arg.field];
        const field = try w.emit(.{ .op = .record_get, .ty = field_type, .a = record, .data = arg.field, .span = plan.span });
        if (arg.owner) |owner| if (arg.value != .bytes_view) {
            const box = try w.emit(.{ .op = .record_get, .ty = m.compound(plan.record).record[owner.field], .a = record, .data = owner.field, .span = plan.span });
            view_owners[position] = try w.emit(.{ .op = .box_get, .ty = owner.ty, .a = box, .span = plan.span });
        };
        if (!arg.boxed) {
            values[position] = field;
        } else if (arg.take) {
            const take = try mb.runtimeFunction("myl_core_task_take", &.{ plan.env, .u64 }, field_type, .extern_c);
            const offset = try w.integer(m.fieldOffset(plan.record, arg.field));
            const boxed = try w.emit(.{ .op = .call, .ty = field_type, .a = @fromBackingInt(@intCast(take)), .data = try w.extra(&.{ env, offset }), .span = plan.span });
            values[position] = try w.emit(.{ .op = .box_take, .ty = arg.value, .a = boxed, .span = plan.span });
        } else {
            values[position] = try w.emit(.{ .op = .box_get, .ty = arg.value, .a = field, .span = plan.span });
        }
    }
    // Each argument is lent at the callee's read-only parameter type, as `parallel.map` lends its arguments: a text or list
    // view with its owner after every parameter, a bytes view, a borrowed overlay, or an option or result rebuilt around
    // its lent payload.
    var lending: parallel.Lending = .{ .w = &w, .allocator = arena, .m = m };
    defer lending.deinit();
    for (values, plan.args, 0..) |value, arg, position| {
        if (arg.owner == null) {
            try parallel.lend(&lending, value, callee_params[position], plan.span);
            continue;
        }
        // A lent view parameter is passed as it is, with its cache owner when it has one.
        try lending.in_place.append(arena, value);
        if (view_owners[position]) |owner| try lending.owners.append(arena, owner);
    }
    const call_args = &lending.in_place;
    const owners = &lending.owners;
    try call_args.appendSlice(arena, owners.items);
    const called = try w.emit(.{ .op = .call, .ty = callee_ret, .a = @fromBackingInt(plan.callee), .data = try w.extra(call_args.items), .span = plan.span });
    const payload = if (callee_ret == .void) try w.emit(.{ .op = .iconst, .ty = .bool, .data = 0 }) else called;
    const boxed = try w.emit(.{ .op = .box_make, .ty = boxed_result, .a = payload, .span = plan.span });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = boxed, .span = plan.span });
    const index: u32 = @intCast(m.functions.items.len);
    try m.functions.append(arena, w.function);
    try mb.touch(index);
    return index;
}

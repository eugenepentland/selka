//! A synchronous map keeps borrowed inputs live until every worker has joined. `parallel.map` with trailing arguments
//! (E1b, E1c) is `map_with1` to `map_with5`: the same worker, whose callback also takes the arguments. The map takes its
//! input and any text, bytes or list argument as a view (FR59), as any function takes a plain parameter, and lends the
//! view itself to every item: a slice is read in place, with no copy. A scalar argument is held as itself, and any other
//! managed argument (a record or a dictionary) is lent through a lent box of it, joined by a group the map opens and
//! closes around its own call (E1c); a view's owner is lent the same way. The map joins before it returns, so its
//! capture outlives every task.
const std = @import("std");
const ir = @import("ir.zig");
const build_fn = @import("build_fn.zig");
const flags = @import("flags.zig");
const language = @import("selka");
/// Allocation and unsupported callback shapes are the lowering failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// The number of trailing arguments a map variant takes, from its name: `map_with1` to `map_with5` take one to five.
fn argumentCount(name: []const u8) ?usize {
    const prefix = "map_with";
    if (!std.mem.startsWith(u8, name, prefix) or name.len != prefix.len + 1) return null;
    const digit = name[prefix.len];
    if (digit < '1' or digit > '5') return null;
    return digit - '0';
}

/// Only the compiler-owned standard definition selects the task boundary: `map`, `map_results` and the `map_with`
/// variants, whose bodies the builder replaces, and `threads` and `cpus`, which read the runtime. `map_fallible` is ordinary
/// guest code over `map_results`.
pub fn matches(source: ?language.source.Source, checked: language.typed.Function) bool {
    const src = source orelse return false;
    if (!std.mem.eql(u8, src.locate(checked.declaration.start).path, "@stdlib/parallel.selka")) return false;
    const name = src.text(checked.declaration);
    return std.mem.eql(u8, name, "map") or std.mem.eql(u8, name, "map_results") or runtimeRead(name) != null or argumentCount(name) != null;
}

/// The runtime reader behind `parallel.threads` (the pool's size, which the runtime reads from `SELKA_THREADS` or the process's
/// CPUs once and keeps, so a task answers what the calling thread does) and `parallel.cpus` (the process's affinity mask).
fn runtimeRead(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "threads")) return "myl_core_threads";
    if (std.mem.eql(u8, name, "cpus")) return "myl_core_cpus";
    return null;
}

/// A call of the runtime reader `symbol`, which takes nothing and answers an `int`.
fn readRuntime(mb: anytype, declared: ir.Function, symbol: []const u8) Error!ir.Function {
    var w = try Writer.init(mb.allocator, declared);
    const read = try mb.runtimeFunction(symbol, &.{}, .i64, .extern_c);
    const count = try w.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(read), .data = try w.extra(&.{}), .span = declared.span });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = count });
    return w.function;
}

/// A raw function writer for generated workers and task thunks: constants and parameters stay out of the blocks, and
/// `block` is the block instructions go to.
pub const Writer = struct {
    a: std.mem.Allocator,
    function: ir.Function,
    block: usize = 0,

    /// A writer for `declared`, with its entry block.
    pub fn init(a: std.mem.Allocator, declared: ir.Function) Error!Writer {
        var result: Writer = .{ .a = a, .function = declared };
        try result.function.blocks.append(a, .{});
        return result;
    }
    /// Append `inst`; any but a parameter, a constant or a function reference goes to the current block.
    pub fn emit(w: *Writer, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(w.function.insts.items.len)));
        try w.function.insts.append(w.a, inst);
        if (inst.op != .param and inst.op != .iconst and inst.op != .func_ref)
            try w.function.blocks.items[w.block].insts.append(w.a, ref);
        return ref;
    }
    /// Store `refs` in the function's extra operands; the packed slice that names them.
    pub fn extra(w: *Writer, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(w.function.extra.items.len);
        try w.function.extra.appendSlice(w.a, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }
    /// A `u64` constant.
    pub fn integer(w: *Writer, value: u64) Error!ir.Ref {
        return w.emit(.{ .op = .iconst, .ty = .u64, .data = value });
    }
    fn newBlock(w: *Writer) Error!usize {
        const index = w.function.blocks.items.len;
        try w.function.blocks.append(w.a, .{});
        return index;
    }
    fn jump(w: *Writer, target: usize) Error!void {
        try w.function.blocks.items[target].preds.append(w.a, @fromBackingInt(@intCast(w.block)));
        _ = try w.emit(.{ .op = .jump, .ty = .void, .data = target });
    }
    fn branch(w: *Writer, condition: ir.Ref, yes: usize, no: usize) Error!void {
        try w.function.blocks.items[yes].preds.append(w.a, @fromBackingInt(@intCast(w.block)));
        try w.function.blocks.items[no].preds.append(w.a, @fromBackingInt(@intCast(w.block)));
        _ = try w.emit(.{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(@fromBackingInt(@intCast(yes)), @fromBackingInt(@intCast(no))) });
    }
};

/// The lowered shape of one map: its element and result types, its callback, the worker's capture record and environment,
/// and the trailing arguments (empty for `map`), which the capture holds after its count field.
const Shape = struct { input: ir.Type, output: ir.Type, callback: ir.Type, capture: ir.Type, result: ir.Type, thunk: ir.Type, args: []const Argument };

/// How the capture holds one trailing argument (FR59): a scalar as itself, a text, bytes or list view as the view itself
/// beside a lent box of the owner a call passes with it (the next field), and any other managed value in a lent box.
const Argument = struct {
    ty: ir.Type,
    how: enum { scalar, view, lent },
    /// The argument's field in the capture record.
    field: u32,
    /// The map's parameter that is the view's trailing owner, when it has one; its lent box is the field after `field`.
    owner: ?u32 = null,
};

/// The environment type of a worker: a box of its capture record.
fn envOf(m: *ir.Module, allocator: std.mem.Allocator, capture: ir.Type) Error!ir.Type {
    return m.intern(allocator, .{ .box = capture });
}

/// The number of parameters the map passes before the trailing owners of its view parameters (C9).
fn passedCount(comptime Context: type, mb: Context, checked: language.typed.Function, span: u32) Error!usize {
    var count: usize = 0;
    for (checked.scope.locals[0..checked.signature.parameter_count]) |local| {
        if (try mb.mapType(local.ty, span) != .void) count += 1;
    }
    return count;
}

/// The capture fields of the trailing arguments `args`, appended to `fields`, and how each is held. `owners` is the index of
/// the first trailing owner parameter that belongs to an argument (the source's own owner, when it has one, comes first).
fn argumentFields(m: *ir.Module, allocator: std.mem.Allocator, args: []const ir.Type, first_owner: u32, fields: *std.ArrayList(ir.Type)) Error![]const Argument {
    const held = try allocator.alloc(Argument, args.len);
    var owner = first_owner;
    for (args, held) |ty, *argument| {
        argument.* = .{ .ty = ty, .how = .scalar, .field = @intCast(fields.items.len) };
        if (m.isView(ty)) {
            argument.how = .view;
            try fields.append(allocator, ty);
            if (try build_fn.ownerOf(m, allocator, ty)) |owner_type| {
                argument.owner = owner;
                owner += 1;
                try fields.append(allocator, try m.intern(allocator, .{ .box = owner_type }));
            }
        } else if (m.managed(ty)) {
            argument.how = .lent;
            try fields.append(allocator, try m.intern(allocator, .{ .box = ty }));
        } else try fields.append(allocator, ty);
    }
    return held;
}

fn shape(comptime Context: type, mb: Context, declared: ir.Function, checked: language.typed.Function) Error!Shape {
    const m = &mb.module;
    const params = declared.signature.params;
    const passed = try passedCount(Context, mb, checked, declared.span);
    if (passed < 2 or passed > 7 or passed > params.len) return mb.refuse("parallel.map without a list and a function", declared.span);
    // The input is the caller's list as a view (FR59), or a whole list where a list parameter keeps its owned type.
    const source_kind = m.kind(params[0]);
    if ((source_kind != .list and source_kind != .list_view) or m.kind(params[1]) != .@"fn" or m.kind(declared.signature.ret) != .list)
        return mb.refuse("parallel.map without a list and a function", declared.span);
    const args = params[2..passed];
    for (args) |ty| if (ty == .void) return mb.refuse(
        "parallel.map takes scalar, list, text, record or dictionary arguments; a Unit argument has no value to pass",
        declared.span,
    );
    const input = if (source_kind == .list) m.compound(params[0]).list else m.compound(params[0]).list_view;
    const output = m.compound(declared.signature.ret).list;
    if (input == .void or output == .void) return mb.refuse("parallel.map over Unit elements", declared.span);
    const callback = m.compound(params[1]).@"fn";
    // The callback takes the element, then the trailing arguments, each in place as its view, and then every owner (E1c).
    var views: std.ArrayList(ir.Type) = .empty;
    var owners: std.ArrayList(ir.Type) = .empty;
    const source_type = checked.scope.locals[0].ty;
    const element_type = mb.input.program.records[source_type.recordIndex()].shape.buffer.?;
    try views.append(mb.allocator, try mb.readOnlyParameter(element_type, input, declared.span));
    // Unit parameters are evaluated but erased from the ABI. Walk source
    // parameters so later arguments retain their own wrapper representation.
    for (checked.scope.locals[2..checked.signature.parameter_count]) |local| {
        const ty = try mb.mapType(local.ty, declared.span);
        if (ty == .void) continue;
        try views.append(mb.allocator, try mb.readOnlyParameter(local.ty, ty, declared.span));
    }
    for (views.items) |view| {
        if (try build_fn.ownerOf(m, mb.allocator, view)) |owner| try owners.append(mb.allocator, owner);
    }
    const expected = try std.mem.concat(mb.allocator, ir.Type, &.{ views.items, owners.items });
    if (!std.mem.eql(ir.Type, callback.params, expected) or callback.ret != output)
        return mb.refuse("parallel.map of a function that is not read-only or that takes or returns Unit", declared.span);
    if (callback.passing.hasOwned())
        return mb.refuse("invalid checked parallel.map callback with an owning or mutable parameter", declared.span);
    // The capture holds the input, the callback, a chunk's start and count, and a lent box of the input's owner (a whole
    // list, or a view's trailing owner: the sentinel when the caller passed a slice). The worker reads the elements from
    // the input and never reads the box: it is the loan the map's group joins, and it makes the record one the map owns,
    // so boxing it takes nothing borrowed (J5), as FR58's lent view does. The trailing arguments follow (FR59).
    const source_owner = (try build_fn.ownerOf(m, mb.allocator, params[0])) orelse params[0];
    var fields: std.ArrayList(ir.Type) = .empty;
    try fields.appendSlice(mb.allocator, &.{ params[0], params[1], .u64, .u64, try m.intern(mb.allocator, .{ .box = source_owner }) });
    const first_owner: u32 = @intCast(passed + @intFromBool(source_owner != params[0]));
    const held = try argumentFields(m, mb.allocator, args, first_owner, &fields);
    const capture = try m.intern(mb.allocator, .{ .record = fields.items });
    const env = try envOf(m, mb.allocator, capture);
    const result = declared.signature.ret;
    const thunk = try m.intern(mb.allocator, .{ .@"fn" = .{ .params = try mb.allocator.dupe(ir.Type, &.{env}), .ret = result } });
    return .{ .input = input, .output = output, .callback = params[1], .capture = capture, .result = result, .thunk = thunk, .args = held };
}

/// The arguments of one callback call being built (E1c): the writer and module it emits into, the values passed in place,
/// and the owners appended after every parameter.
pub const Lending = struct {
    w: *Writer,
    allocator: std.mem.Allocator,
    m: *ir.Module,
    in_place: std.ArrayList(ir.Ref) = .empty,
    owners: std.ArrayList(ir.Ref) = .empty,

    /// Free the two argument lists.
    pub fn deinit(self: *Lending) void {
        self.in_place.deinit(self.allocator);
        self.owners.deinit(self.allocator);
    }
};

/// Lend one value at the callback's declared read-only ABI, with the trailing
/// cache owner used by a top-level text or list parameter.
pub fn lend(lending: *Lending, value: ir.Ref, target: ir.Type, span: u32) Error!void {
    try lending.in_place.append(lending.allocator, try readOnlyValue(lending, value, target, span));
    if (target == .str_view or lending.m.kind(target) == .list_view) try lending.owners.append(lending.allocator, value);
}

fn readOnlyValue(lending: *Lending, value: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
    const w = lending.w;
    const m = lending.m;
    const actual = w.function.inst(value).ty;
    if (actual == target) return value;
    if (m.kind(actual) == .box) {
        const child = m.compound(actual).box;
        const wrapper = m.kind(child) == .@"union" and m.kind(target) == .@"union" and m.containsBorrow(target);
        if (child == m.storageType(target) or wrapper) {
            const payload = try w.emit(.{ .op = .box_get, .ty = child, .a = value, .span = span });
            return readOnlyValue(lending, payload, target, span);
        }
    }
    if (m.isBorrowed(target)) return w.emit(.{ .op = .borrow, .ty = target, .a = value, .span = span });
    if (target.isSpan()) {
        const length = try w.emit(.{ .op = if (actual == .str) .str_len else .list_len, .ty = .u64, .a = value, .span = span });
        return w.emit(.{ .op = .str_view_of, .ty = target, .a = value, .b = try w.integer(0), .data = try w.extra(&.{length}), .span = span });
    }
    if (m.kind(target) == .list_view) return w.emit(.{ .op = .list_view_of, .ty = target, .a = value, .span = span });
    return readOnlyWrapper(lending, value, target, span);
}

/// Preserve the active standard wrapper case while lending its payload. Nested
/// wrappers can add blocks of their own, so the join records each final edge.
fn readOnlyWrapper(lending: *Lending, value: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
    const w = lending.w;
    const source_cases = lending.m.compound(w.function.inst(value).ty).@"union";
    const cases = lending.m.compound(target).@"union";
    const tag = try w.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
    const join = try w.newBlock();
    var values: std.ArrayList(ir.Ref) = .empty;
    for (source_cases, 0..) |stored, index| {
        const body = try w.newBlock();
        const next = if (index + 1 < cases.len) try w.newBlock() else null;
        if (next) |other| {
            const tag_value = try w.emit(.{ .op = .iconst, .ty = .u32, .data = index });
            const matches_tag = try w.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = tag_value, .data = @backingInt(ir.Predicate.eq), .span = span });
            try w.branch(matches_tag, body, other);
        } else try w.jump(body);
        w.block = body;
        const raw = if (stored == .void) ir.Ref.none else try w.emit(.{ .op = .union_payload, .ty = stored, .a = value, .data = index, .span = span });
        const payload = if (raw == .none) raw else try readOnlyValue(lending, raw, cases[index], span);
        try values.append(w.a, try w.emit(.{ .op = .union_make, .ty = target, .a = payload, .data = index, .span = span }));
        try w.jump(join);
        if (next) |other| w.block = other;
    }
    w.block = join;
    return w.emit(.{ .op = .phi, .ty = target, .data = try w.extra(values.items), .span = span });
}

/// The function each chunk's task runs. It is a task thunk (`<task.thunk.K@map>`): its environment holds the input and
/// any text, bytes or list argument as the view itself (FR59), which only a task thunk's environment may store
/// (`verify_ir.taskEnvironment`, as FR58 lends a view parameter to `g.submit`).
fn worker(comptime Context: type, mb: Context, s: Shape, span: u32) Error!u32 {
    const name = try mb.generatedName(.task_thunk, "task.thunk");
    var w = try Writer.init(mb.allocator, .{ .name = name, .signature = mb.module.compound(s.thunk).@"fn", .span = span });
    const env = try w.emit(.{ .op = .param, .ty = try envOf(&mb.module, mb.allocator, s.capture), .data = 0 });
    const capture = try w.emit(.{ .op = .box_get, .ty = s.capture, .a = env });
    const fields = mb.module.compound(s.capture).record;
    const source = try w.emit(.{ .op = .record_get, .ty = fields[0], .a = capture, .data = 0 });
    const callback = try w.emit(.{ .op = .record_get, .ty = s.callback, .a = capture, .data = 1 });
    const start = try w.emit(.{ .op = .record_get, .ty = .u64, .a = capture, .data = 2 });
    const count = try w.emit(.{ .op = .record_get, .ty = .u64, .a = capture, .data = 3 });
    // The trailing arguments are read once, before the loop, and each is the same for every item: a view as itself with
    // the owner from its lent box, any other managed argument through its lent box (E1c).
    const argument_values = try mb.allocator.alloc(ir.Ref, s.args.len);
    const argument_owners = try mb.allocator.alloc(?ir.Ref, s.args.len);
    for (s.args, argument_values, argument_owners) |argument, *value, *owner| {
        const field = try w.emit(.{ .op = .record_get, .ty = fields[argument.field], .a = capture, .data = argument.field });
        value.* = if (argument.how == .lent) try w.emit(.{ .op = .box_get, .ty = argument.ty, .a = field }) else field;
        owner.* = null;
        if (argument.owner == null) continue;
        const box = try w.emit(.{ .op = .record_get, .ty = fields[argument.field + 1], .a = capture, .data = argument.field + 1 });
        owner.* = try w.emit(.{ .op = .box_get, .ty = mb.module.compound(fields[argument.field + 1]).box, .a = box });
    }
    const end = try w.emit(.{ .op = .add, .ty = .u64, .a = start, .b = count, .check = .exact });
    const empty = try w.emit(.{ .op = .list_new, .ty = s.result, .a = count });
    try w.function.blocks.appendSlice(w.a, &.{ .{}, .{}, .{} });
    try w.function.blocks.items[1].preds.appendSlice(w.a, &.{ @fromBackingInt(@intCast(0)), @fromBackingInt(@intCast(2)) });
    try w.function.blocks.items[2].preds.append(w.a, @fromBackingInt(@intCast(1)));
    try w.function.blocks.items[3].preds.append(w.a, @fromBackingInt(@intCast(1)));
    _ = try w.emit(.{ .op = .jump, .ty = .void, .data = 1 });
    w.block = 1;
    const cursor = try w.emit(.{ .op = .phi, .ty = .u64 });
    const output = try w.emit(.{ .op = .phi, .ty = s.result });
    const more = try w.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = end, .data = @backingInt(ir.Predicate.lt) });
    _ = try w.emit(.{ .op = .branch, .ty = .void, .a = more, .data = ir.packTargets(@fromBackingInt(@intCast(2)), @fromBackingInt(@intCast(3))) });
    w.block = 2;
    const mark = try mb.runtimeFunction("myl_core_task_item", &.{.u64}, .void, .extern_c);
    _ = try w.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(mark), .data = try w.extra(&.{cursor}) });
    const input = try w.emit(.{ .op = .list_get, .ty = s.input, .a = source, .b = cursor, .check = .exact, .span = span });
    // The element and each argument, in place as their views, then every owner after them (the callback ABI, E1c).
    var lending: Lending = .{ .w = &w, .allocator = mb.allocator, .m = &mb.module };
    const callback_params = mb.module.compound(s.callback).@"fn".params;
    try lend(&lending, input, callback_params[0], span);
    for (argument_values, argument_owners, s.args, 0..) |value, owner, argument, index| {
        if (argument.how != .view) {
            try lend(&lending, value, callback_params[index + 1], span);
            continue;
        }
        // A view argument is passed as it is, with the owner a direct call passes with it (FR59).
        try lending.in_place.append(mb.allocator, value);
        if (owner) |passed| try lending.owners.append(mb.allocator, passed);
    }
    try lending.in_place.appendSlice(mb.allocator, lending.owners.items);
    const arguments = try w.extra(lending.in_place.items);
    const result = try w.emit(.{ .op = .call_indirect, .ty = s.output, .a = callback, .data = arguments, .span = span });
    const pushed = try w.emit(.{ .op = .list_push, .ty = s.result, .a = output, .b = result });
    const next = try w.emit(.{ .op = .add, .ty = .u64, .a = cursor, .b = try w.integer(1), .check = .exact });
    _ = try w.emit(.{ .op = .jump, .ty = .void, .data = 1 });
    w.function.blocks.items[1].preds.items[1] = @fromBackingInt(@intCast(w.block));
    w.function.insts.items[cursor.index()].data = try w.extra(&.{ start, next });
    w.function.insts.items[output.index()].data = try w.extra(&.{ empty, pushed });
    try w.function.loops.append(w.a, .{ .id = 0, .header = @fromBackingInt(@intCast(1)), .body = @fromBackingInt(@intCast(2)), .latch = @fromBackingInt(@intCast(w.block)), .exit = @fromBackingInt(@intCast(3)) });
    w.block = 3;
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = output });
    const index: u32 = @intCast(mb.module.functions.items.len);
    try mb.module.functions.append(mb.allocator, w.function);
    try mb.touch(index);
    return index;
}

/// Build the standard map body at its ordinary callable ABI, including indirect calls. The map builds its capture record
/// (the input, the callback, room for a chunk's start and count, and the trailing arguments) and passes it by address
/// to the runtime, which copies it into each chunk's environment and joins every chunk before it returns (FR59).
pub fn build(mb: anytype, declared: ir.Function, checked: language.typed.Function) Error!ir.Function {
    const src = mb.input.source orelse return error.Unsupported;
    if (runtimeRead(src.text(checked.declaration))) |symbol| return readRuntime(mb, declared, symbol);
    const s = try shape(@TypeOf(mb), mb, declared, checked);
    const task = try worker(@TypeOf(mb), mb, s, declared.span);
    var w = try Writer.init(mb.allocator, declared);
    const params = declared.signature.params;
    // Every parameter has its value in the body, the input's trailing owner too, which the map does not read.
    const refs = try mb.allocator.alloc(ir.Ref, params.len);
    for (params, refs, 0..) |ty, *ref, index| ref.* = try w.emit(.{ .op = .param, .ty = ty, .data = index });
    const list = refs[0];
    const callback = refs[1];
    const run = try w.emit(.{ .op = .func_ref, .ty = s.thunk, .data = task });
    const length = try w.emit(.{ .op = .list_len, .ty = .u64, .a = list });
    const out = try w.emit(.{ .op = .list_new, .ty = declared.signature.ret, .a = length });
    // The input's owner, a lent argument and a view argument's owner are lent to every item through a lent box (E1c,
    // FR59). The group opened here is the join the lent boxes read (own.zig, rule A): it is closed after the map's own
    // call, so each owner outlives the map.
    const group_type = try mb.module.intern(mb.allocator, .{ .box = .i64 });
    const open = try mb.runtimeFunction("myl_core_group_open", &.{}, group_type, .extern_c);
    const group = try w.emit(.{ .op = .call, .ty = group_type, .a = @fromBackingInt(open), .data = try w.extra(&.{}), .span = declared.span });
    const fields = mb.module.compound(s.capture).record;
    const values = try mb.allocator.alloc(ir.Ref, fields.len);
    values[0] = list;
    values[1] = callback;
    values[2] = try w.integer(0);
    values[3] = values[2];
    const owner_ref = if (mb.module.kind(params[0]) == .list) list else refs[try passedCount(@TypeOf(mb), mb, checked, declared.span)];
    values[4] = try w.emit(.{ .op = .box_make, .ty = fields[4], .a = owner_ref, .b = group, .data = flags.lent_box, .span = declared.span });
    for (s.args, 0..) |argument, index| {
        const value = refs[index + 2];
        values[argument.field] = if (argument.how == .lent)
            try w.emit(.{ .op = .box_make, .ty = fields[argument.field], .a = value, .b = group, .data = flags.lent_box, .span = declared.span })
        else
            value;
        const owner_param = argument.owner orelse continue;
        const owner = refs[owner_param];
        values[argument.field + 1] = try w.emit(.{ .op = .box_make, .ty = fields[argument.field + 1], .a = owner, .b = group, .data = flags.lent_box, .span = declared.span });
    }
    const record = try w.emit(.{ .op = .record_make, .ty = s.capture, .data = try w.extra(values), .span = declared.span });
    // The capture is boxed as the worker's environment type, the one box that may hold a view (`taskEnvironment`).
    const env_type = try envOf(&mb.module, mb.allocator, s.capture);
    const capture = try w.emit(.{ .op = .box_make, .ty = env_type, .a = record, .span = declared.span });
    const capture_size = try w.integer(mb.module.size(s.capture));
    const start_offset = try w.integer(mb.module.fieldOffset(s.capture, 2));
    const count_offset = try w.integer(mb.module.fieldOffset(s.capture, 3));
    const output_size = try w.integer(mb.module.size(s.output));
    const result_type = declared.signature.ret;
    // The trailing arguments are in the capture, so every map calls the one runtime entry. Its zero-rc contract transfers
    // `out`, the seventh argument, and reads the rest.
    const target = try mb.runtimeFunction("myl_core_owned_map", &.{ env_type, .u64, .u64, s.thunk, .u64, .u64, result_type, .u64 }, result_type, .extern_c);
    const args = try w.extra(&.{ capture, capture_size, length, run, start_offset, count_offset, out, output_size });
    const result = try w.emit(.{ .op = .call, .ty = result_type, .a = @fromBackingInt(target), .data = args, .span = declared.span });
    const close = try mb.runtimeFunction("myl_core_owned_group_end", &.{group_type}, .void, .extern_c);
    _ = try w.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(close), .data = try w.extra(&.{group}), .span = declared.span });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = result });
    return w.function;
}

//! TASK-SCHEDULER-1: construct task programs without changing the front end.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const builder = @import("test_builder.zig");
const Hand = support.Hand;
const Error = support.Error;

const Shape = struct { ints: ir.Type, nested: ir.Type, dict: ir.Type, record: ir.Type, env: ir.Type, result: ir.Type, handle: ir.Type };
fn shape(a: std.mem.Allocator, m: *ir.Module) Error!Shape {
    const ints = try m.intern(a, .{ .list = .i64 });
    const nested = try m.intern(a, .{ .list = ints });
    const dict = try m.intern(a, .{ .dict = .{ .key = .str, .value = ints } });
    const record = try m.intern(a, .{ .record = try a.dupe(ir.Type, &.{ ints, nested, dict, .str }) });
    const env = try m.intern(a, .{ .box = record });
    const result = try m.intern(a, .{ .box = try m.intern(a, .{ .record = try a.dupe(ir.Type, &.{ ints, .str, .i64 }) }) });
    return .{ .ints = ints, .nested = nested, .dict = dict, .record = record, .env = env, .result = result, .handle = try m.intern(a, .{ .box = .i64 }) };
}
const Abi = struct { open: u32, submit: u32, result: u32, close: u32, threads: u32, thunk: ir.Type };
fn abi(a: std.mem.Allocator, m: *ir.Module, s: Shape) Error!Abi {
    const thunk = try m.intern(a, .{ .@"fn" = .{ .params = try a.dupe(ir.Type, &.{s.env}), .ret = s.result } });
    return .{
        .open = try builder.helper(a, m, "myl_core_group_open", &.{}, s.handle),
        .submit = try builder.helper(a, m, "myl_core_task_submit", &.{ s.handle, thunk, s.env, .i64 }, s.handle),
        .result = try builder.helper(a, m, "myl_core_task_result", &.{s.handle}, s.result),
        .close = try builder.helper(a, m, "myl_core_group_close", &.{s.handle}, .void),
        .threads = try builder.helper(a, m, "myl_core_threads", &.{}, .i64),
        .thunk = thunk,
    };
}
fn call(h: *Hand, target: u32, args: []const ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .call, .ty = h.module.functions.items[target].signature.ret, .a = @fromBackingInt(target), .data = try h.extra(args), .span = 100 });
}
fn field(h: *Hand, value: ir.Ref, index: u64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .record_get, .ty = ty, .a = value, .data = index });
}
fn list(h: *Hand, ty: ir.Type, items: []const ir.Ref) Error!ir.Ref {
    var result = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.u64, @intCast(items.len)) });
    for (items) |item| result = try h.emit(.{ .op = .list_push, .ty = ty, .a = result, .b = item });
    return result;
}
fn get(h: *Hand, value: ir.Ref, index: i64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .list_get, .ty = ty, .a = value, .b = try h.int(.i64, index), .check = .exact });
}
fn length(h: *Hand, value: ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .list_len, .ty = .u64, .a = value });
}
fn taskBody(a: std.mem.Allocator, m: *ir.Module, s: Shape, api: Abi, fail: bool) Error!u32 {
    var h = try Hand.init(a, m, "captured_task", m.compound(api.thunk).@"fn");
    if (fail) _ = try h.emit(.{ .op = .div, .ty = .i64, .a = try h.int(.i64, 1), .b = try h.int(.i64, 0), .check = .exact, .span = 200 });
    const record = try h.emit(.{ .op = .box_get, .ty = s.record, .a = try h.param(0) });
    const ints = try field(&h, record, 0, s.ints);
    const nested = try field(&h, record, 1, s.nested);
    const dict = try field(&h, record, 2, s.dict);
    const text = try field(&h, record, 3, .str);
    const key = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    const entry = try h.emit(.{ .op = .dict_find, .ty = .i64, .a = dict, .b = key });
    const from_dict = try h.emit(.{ .op = .dict_entry_value, .ty = s.ints, .a = dict, .b = entry, .check = .exact });
    const from_nested = try get(&h, nested, 1, s.ints);
    const a0 = try get(&h, ints, 0, .i64);
    const b0 = try get(&h, from_dict, 1, .i64);
    const c0 = try get(&h, from_nested, 2, .i64);
    const ab = try h.emit(.{ .op = .add, .ty = .i64, .a = a0, .b = b0, .check = .exact });
    const sum = try h.emit(.{ .op = .add, .ty = .i64, .a = ab, .b = c0, .check = .exact });
    const result_type = m.compound(s.result).box;
    const result = try h.emit(.{ .op = .record_make, .ty = result_type, .data = try h.extra(&.{ from_dict, text, sum }) });
    const boxed = try h.emit(.{ .op = .box_make, .ty = s.result, .a = result });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = boxed });
    return h.finish();
}
fn environment(h: *Hand, s: Shape, ints: ir.Ref) Error!ir.Ref {
    const nested = try list(h, s.nested, &.{ ints, ints });
    const key = try h.loose(.{ .op = .str_const, .ty = .str, .data = 0 });
    const suffix = try h.loose(.{ .op = .str_const, .ty = .str, .data = 1 });
    const text = try h.emit(.{ .op = .str_append, .ty = .str, .a = key, .b = suffix });
    var dict = try h.emit(.{ .op = .dict_new, .ty = s.dict, .a = try h.int(.u64, 1) });
    const probe = try h.emit(.{ .op = .dict_find, .ty = .i64, .a = dict, .b = key });
    dict = try h.emit(.{ .op = .dict_insert, .ty = s.dict, .a = dict, .b = probe, .data = try h.extra(&.{ key, ints }) });
    const record = try h.emit(.{ .op = .record_make, .ty = s.record, .data = try h.extra(&.{ ints, nested, dict, text }) });
    return h.emit(.{ .op = .box_make, .ty = s.env, .a = record });
}
/// Eight tasks retain shared list and string results from a mixed capture graph.
/// Parent mutation must copy, even if all workers finish before that mutation.
pub fn captures(a: std.mem.Allocator) Error!ir.Module {
    return captureProgram(a, false);
}

/// A real emitted task fails after submission, for the captured-PC footer.
pub fn trapped(a: std.mem.Allocator) Error!ir.Module {
    return captureProgram(a, true);
}

fn captureProgram(a: std.mem.Allocator, fail: bool) Error!ir.Module {
    var m: ir.Module = .{};
    try m.strings.appendSlice(a, &.{ "key", "é" });
    const s = try shape(a, &m);
    const api = try abi(a, &m, s);
    const thunk = try taskBody(a, &m, s, api, fail);
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const stream = try h.param(0);
    const ints = try list(&h, s.ints, &.{ try h.int(.i64, 10), try h.int(.i64, 20), try h.int(.i64, 30) });
    const env = try environment(&h, s, ints);
    const group = try call(&h, api.open, &.{});
    const run = try h.loose(.{ .op = .func_ref, .ty = api.thunk, .data = thunk });
    var tasks: [8]ir.Ref = undefined;
    for (&tasks) |*task| task.* = try call(&h, api.submit, &.{ group, run, env, try h.int(.i64, -1) });
    const changed = try h.emit(.{ .op = .list_push, .ty = s.ints, .a = ints, .b = try h.int(.i64, 99) });
    try h.printValues(stream, &.{try length(&h, changed)});
    for (tasks) |task| {
        const boxed = try call(&h, api.result, &.{task});
        const again = try call(&h, api.result, &.{task});
        const result_type = m.compound(s.result).box;
        const record = try h.emit(.{ .op = .box_get, .ty = result_type, .a = boxed });
        const other = try h.emit(.{ .op = .box_get, .ty = result_type, .a = again });
        const held = try field(&h, record, 0, s.ints);
        const text = try field(&h, record, 1, .str);
        const sum = try field(&h, other, 2, .i64);
        try h.printValues(stream, &.{ try length(&h, held), text, sum });
    }
    _ = try call(&h, api.close, &.{group});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

const RangeShape = struct { items: ir.Type, capture: ir.Type, env: ir.Type, result: ir.Type, handle: ir.Type, thunk: ir.Type };
fn rangeShape(a: std.mem.Allocator, m: *ir.Module) Error!RangeShape {
    const items = try m.intern(a, .{ .list = .i64 });
    const capture = try m.intern(a, .{ .record = try a.dupe(ir.Type, &.{ items, .i64, .i64, .i64 }) });
    const env = try m.intern(a, .{ .box = capture });
    const result = try m.intern(a, .{ .box = items });
    return .{ .items = items, .capture = capture, .env = env, .result = result, .handle = try m.intern(a, .{ .box = .i64 }), .thunk = try m.intern(a, .{ .@"fn" = .{ .params = try a.dupe(ir.Type, &.{env}), .ret = result } }) };
}
fn rangeBody(a: std.mem.Allocator, m: *ir.Module, s: RangeShape, fail: bool) Error!u32 {
    const mark = try builder.helper(a, m, "myl_core_task_item", &.{.i64}, .void);
    var h = try Hand.init(a, m, "map_range", m.compound(s.thunk).@"fn");
    const capture = try h.emit(.{ .op = .box_get, .ty = s.capture, .a = try h.param(0) });
    const items = try field(&h, capture, 0, s.items);
    const context = try field(&h, capture, 1, .i64);
    const start = try field(&h, capture, 2, .i64);
    const end = try field(&h, capture, 3, .i64);
    const empty = try list(&h, s.items, &.{});
    const header = try h.newBlock();
    const body = try h.newBlock();
    const done = try h.newBlock();
    try h.jump(header);
    h.block = header;
    const cursor = try h.emit(.{ .op = .phi, .ty = .i64 });
    const output = try h.emit(.{ .op = .phi, .ty = s.items });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = end, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, body, done);
    h.block = body;
    _ = try call(&h, mark, &.{cursor});
    if (fail) {
        const denominator = try h.emit(.{ .op = .sub, .ty = .i64, .a = cursor, .b = try h.int(.i64, 17), .check = .exact });
        _ = try h.emit(.{ .op = .div, .ty = .i64, .a = try h.int(.i64, 1), .b = denominator, .check = .exact, .span = 200 });
    }
    const item = try h.emit(.{ .op = .list_get, .ty = .i64, .a = items, .b = cursor, .check = .exact });
    const mapped = try h.emit(.{ .op = .add, .ty = .i64, .a = item, .b = context, .check = .exact });
    const pushed = try h.emit(.{ .op = .list_push, .ty = s.items, .a = output, .b = mapped });
    const next = try h.emit(.{ .op = .add, .ty = .i64, .a = cursor, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(header);
    h.function.insts.items[cursor.index()].data = try h.extra(&.{ start, next });
    h.function.insts.items[output.index()].data = try h.extra(&.{ empty, pushed });
    h.block = done;
    const boxed = try h.emit(.{ .op = .box_make, .ty = s.result, .a = output });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = boxed });
    return h.finish();
}
/// P2-0 proof: a generated range thunk loops over shared items, borrows context,
/// returns a fresh chunk list and the parent gathers results in input order.
pub fn mapRanges(a: std.mem.Allocator) Error!ir.Module {
    return rangeProgram(a, false);
}
/// A map fails on item 17, beyond its range's first item at one/two threads.
pub fn mapTrapped(a: std.mem.Allocator) Error!ir.Module {
    return rangeProgram(a, true);
}
fn rangeProgram(a: std.mem.Allocator, fail: bool) Error!ir.Module {
    var m: ir.Module = .{};
    const s = try rangeShape(a, &m);
    const open = try builder.helper(a, &m, "myl_core_group_open", &.{}, s.handle);
    const submit = try builder.helper(a, &m, "myl_core_task_submit", &.{ s.handle, s.thunk, s.env, .i64 }, s.handle);
    const result = try builder.helper(a, &m, "myl_core_task_result", &.{s.handle}, s.result);
    const close = try builder.helper(a, &m, "myl_core_group_close", &.{s.handle}, .void);
    const chunks = try builder.helper(a, &m, "myl_core_map_chunks", &.{.i64}, .i64);
    const share = try builder.helper(a, &m, "myl_core_share", &.{s.items}, .void);
    const threads = try builder.helper(a, &m, "myl_core_threads", &.{}, .i64);
    const thunk = try rangeBody(a, &m, s, fail);
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    var refs: [32]ir.Ref = undefined;
    for (&refs, 0..) |*value, i| value.* = try h.int(.i64, @intCast(i));
    const items = try list(&h, s.items, &refs);
    const count_threads = try call(&h, threads, &.{});
    const parallel = try h.emit(.{ .op = .cmp, .ty = .bool, .a = count_threads, .b = try h.int(.i64, 1), .data = @backingInt(ir.Predicate.gt) });
    const publish = try h.newBlock();
    const ready = try h.newBlock();
    try h.branch(parallel, publish, ready);
    h.block = publish;
    _ = try call(&h, share, &.{items});
    try h.jump(ready);
    h.block = ready;
    const group = try call(&h, open, &.{});
    const run = try h.loose(.{ .op = .func_ref, .ty = s.thunk, .data = thunk });
    const k = try call(&h, chunks, &.{try h.int(.i64, 32)});
    const handles_type = try m.intern(a, .{ .list = s.handle });
    const handles = try list(&h, handles_type, &.{});
    const header = try h.newBlock();
    const body = try h.newBlock();
    const gather = try h.newBlock();
    try h.jump(header);
    h.block = header;
    const cursor = try h.emit(.{ .op = .phi, .ty = .i64 });
    const tasks = try h.emit(.{ .op = .phi, .ty = handles_type });
    const more = try h.emit(.{ .op = .cmp, .ty = .bool, .a = cursor, .b = k, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(more, body, gather);
    h.block = body;
    const next = try h.emit(.{ .op = .add, .ty = .i64, .a = cursor, .b = try h.int(.i64, 1), .check = .exact });
    const left = try h.emit(.{ .op = .mul, .ty = .i64, .a = cursor, .b = try h.int(.i64, 32), .check = .exact });
    const right = try h.emit(.{ .op = .mul, .ty = .i64, .a = next, .b = try h.int(.i64, 32), .check = .exact });
    const start = try h.emit(.{ .op = .div, .ty = .i64, .a = left, .b = k, .check = .exact });
    const end = try h.emit(.{ .op = .div, .ty = .i64, .a = right, .b = k, .check = .exact });
    const record = try h.emit(.{ .op = .record_make, .ty = s.capture, .data = try h.extra(&.{ items, try h.int(.i64, 100), start, end }) });
    const env = try h.emit(.{ .op = .box_make, .ty = s.env, .a = record });
    const task = try call(&h, submit, &.{ group, run, env, start });
    const pushed = try h.emit(.{ .op = .list_push, .ty = handles_type, .a = tasks, .b = task });
    try h.jump(header);
    h.function.insts.items[cursor.index()].data = try h.extra(&.{ try h.int(.i64, 0), next });
    h.function.insts.items[tasks.index()].data = try h.extra(&.{ handles, pushed });
    h.block = gather;
    const outer = try h.newBlock();
    const enter = try h.newBlock();
    const inner = try h.newBlock();
    const emit = try h.newBlock();
    const advance = try h.newBlock();
    const done = try h.newBlock();
    try h.jump(outer);
    h.block = outer;
    const which = try h.emit(.{ .op = .phi, .ty = .i64 });
    const has_task = try h.emit(.{ .op = .cmp, .ty = .bool, .a = which, .b = k, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(has_task, enter, done);
    h.block = enter;
    const held = try h.emit(.{ .op = .list_get, .ty = s.handle, .a = tasks, .b = which, .check = .exact });
    const boxed = try call(&h, result, &.{held});
    const chunk = try h.emit(.{ .op = .box_get, .ty = s.items, .a = boxed });
    const count = try h.emit(.{ .op = .convert, .ty = .i64, .a = try length(&h, chunk), .check = .exact });
    try h.jump(inner);
    h.block = inner;
    const offset = try h.emit(.{ .op = .phi, .ty = .i64 });
    const has_item = try h.emit(.{ .op = .cmp, .ty = .bool, .a = offset, .b = count, .data = @backingInt(ir.Predicate.lt) });
    try h.branch(has_item, emit, advance);
    h.block = emit;
    const item = try h.emit(.{ .op = .list_get, .ty = .i64, .a = chunk, .b = offset, .check = .exact });
    try h.printValues(try h.param(0), &.{item});
    const following = try h.emit(.{ .op = .add, .ty = .i64, .a = offset, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(inner);
    h.function.insts.items[offset.index()].data = try h.extra(&.{ try h.int(.i64, 0), following });
    h.block = advance;
    const after = try h.emit(.{ .op = .add, .ty = .i64, .a = which, .b = try h.int(.i64, 1), .check = .exact });
    try h.jump(outer);
    h.function.insts.items[which.index()].data = try h.extra(&.{ try h.int(.i64, 0), after });
    h.block = done;
    _ = try call(&h, close, &.{group});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

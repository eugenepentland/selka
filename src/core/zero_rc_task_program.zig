//! Zero-RC task prototype at the branch's existing Core task boundary.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const builder = @import("test_builder.zig");
const Hand = support.Hand;
const Error = support.Error;
const Shape = struct { ints: ir.Type, texts: ir.Type, capture: ir.Type, env: ir.Type, success: ir.Type, outcome: ir.Type, result: ir.Type, group: ir.Type, thunk: ir.Type };
const Api = struct { open: u32, submit: u32, take: u32, end: u32, number: u32 };

fn shape(a: std.mem.Allocator, m: *ir.Module) Error!Shape {
    const ints = try m.intern(a, .{ .list = .i64 });
    const texts = try m.intern(a, .{ .list = .str });
    const capture = try m.intern(a, .{ .record = &.{ .i64, .str, ints } });
    const env = try m.intern(a, .{ .box = capture });
    const success = try m.intern(a, .{ .record = &.{ .i64, texts } });
    const outcome = try m.intern(a, .{ .@"union" = &.{ success, .str } });
    const result = try m.intern(a, .{ .box = outcome });
    const thunk = try m.intern(a, .{ .@"fn" = .{ .params = try a.dupe(ir.Type, &.{env}), .ret = result } });
    return .{ .ints = ints, .texts = texts, .capture = capture, .env = env, .success = success, .outcome = outcome, .result = result, .group = try m.intern(a, .{ .box = .i64 }), .thunk = thunk };
}
fn api(a: std.mem.Allocator, m: *ir.Module, s: Shape) Error!Api {
    const submit = try builder.helper(a, m, "myl_core_owned_task_submit", &.{ s.group, s.thunk, s.env, .i64 }, .void);
    m.functions.items[submit].signature.owned = 4;
    const end = try builder.helper(a, m, "myl_core_owned_group_end", &.{s.group}, .void);
    m.functions.items[end].signature.owned = 1;
    return .{
        .open = try builder.helper(a, m, "myl_core_group_open", &.{}, s.group),
        .submit = submit,
        .end = end,
        .take = try builder.helper(a, m, "myl_core_owned_group_take", &.{ s.group, .i64 }, s.result),
        .number = try builder.helper(a, m, "myl_core_str_from_i64", &.{.i64}, .str),
    };
}
fn call(h: *Hand, target: u32, args: []const ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .call, .ty = h.module.functions.items[target].signature.ret, .a = @fromBackingInt(target), .data = try h.extra(args), .span = 100 });
}
fn field(h: *Hand, value: ir.Ref, index: u64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .record_get, .ty = ty, .a = value, .data = index });
}
fn list(h: *Hand, ty: ir.Type, items: []const ir.Ref) Error!ir.Ref {
    var out = try h.emit(.{ .op = .list_new, .ty = ty, .a = try h.int(.u64, @intCast(items.len)) });
    for (items) |item| out = try h.emit(.{ .op = .list_push, .ty = ty, .a = out, .b = item });
    return out;
}
fn literal(h: *Hand, index: u64) Error!ir.Ref {
    return h.loose(.{ .op = .str_const, .ty = .str, .data = index });
}
fn length(h: *Hand, value: ir.Ref) Error!ir.Ref {
    return h.emit(.{ .op = .str_len, .ty = .u64, .a = value });
}
fn get(h: *Hand, value: ir.Ref, index: i64, ty: ir.Type) Error!ir.Ref {
    return h.emit(.{ .op = .list_get, .ty = ty, .a = value, .b = try h.int(.i64, index), .check = .exact });
}
fn task(a: std.mem.Allocator, m: *ir.Module, s: Shape) Error!u32 {
    var h = try Hand.init(a, m, "owned_capture_task", m.compound(s.thunk).@"fn");
    const capture = try h.emit(.{ .op = .box_get, .ty = s.capture, .a = try h.param(0) });
    const index = try field(&h, capture, 0, .i64);
    const text = try field(&h, capture, 1, .str);
    const ints = try field(&h, capture, 2, s.ints);
    const sum = try h.emit(.{ .op = .add, .ty = .i64, .a = try get(&h, ints, 0, .i64), .b = try get(&h, ints, 2, .i64), .check = .exact });
    const first = try h.emit(.{ .op = .str_char, .ty = .str, .a = text, .b = try h.int(.u64, 0) });
    const prefix = try h.emit(.{ .op = .str_append, .ty = .str, .a = try literal(&h, 1), .b = first });
    const fresh = try h.emit(.{ .op = .str_append, .ty = .str, .a = prefix, .b = text });
    const rem = try h.emit(.{ .op = .rem, .ty = .i64, .a = index, .b = try h.int(.i64, 3), .check = .exact });
    const fails = try h.emit(.{ .op = .cmp, .ty = .bool, .a = rem, .b = try h.int(.i64, 0), .data = @backingInt(ir.Predicate.eq) });
    const bad = try h.newBlock();
    const good = try h.newBlock();
    try h.branch(fails, bad, good);
    h.block = bad;
    const failure = try h.emit(.{ .op = .union_make, .ty = s.outcome, .a = fresh, .data = 1 });
    const failed = try h.emit(.{ .op = .box_make, .ty = s.result, .a = failure });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = failed });
    h.block = good;
    const texts = try list(&h, s.texts, &.{fresh});
    const success = try h.emit(.{ .op = .record_make, .ty = s.success, .data = try h.extra(&.{ sum, texts }) });
    const value = try h.emit(.{ .op = .union_make, .ty = s.outcome, .a = success, .data = 0 });
    const boxed = try h.emit(.{ .op = .box_make, .ty = s.result, .a = value });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = boxed });
    return h.finish();
}
fn score(a: std.mem.Allocator, m: *ir.Module, s: Shape) Error!u32 {
    var h = try Hand.init(a, m, "result_score", .{ .params = try a.dupe(ir.Type, &.{s.result}), .ret = .u64 });
    const outcome = try h.emit(.{ .op = .box_get, .ty = s.outcome, .a = try h.param(0) });
    const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = outcome });
    const fails = try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    const bad = try h.newBlock();
    const good = try h.newBlock();
    try h.branch(fails, bad, good);
    h.block = bad;
    const message = try h.emit(.{ .op = .union_payload, .ty = .str, .a = outcome, .data = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try length(&h, message) });
    h.block = good;
    const success = try h.emit(.{ .op = .union_payload, .ty = s.success, .a = outcome, .data = 0 });
    const number = try h.emit(.{ .op = .convert, .ty = .u64, .a = try field(&h, success, 0, .i64) });
    const texts = try field(&h, success, 1, s.texts);
    const size = try length(&h, try get(&h, texts, 0, .str));
    const sum = try h.emit(.{ .op = .add, .ty = .u64, .a = number, .b = size, .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = sum });
    return h.finish();
}
fn makeCapture(h: *Hand, s: Shape, methods: Api, index: i64) Error!ir.Ref {
    const item = try h.int(.i64, index);
    const number = try call(h, methods.number, &.{item});
    const text = try h.emit(.{ .op = .str_append, .ty = .str, .a = try literal(h, 0), .b = number });
    const ints = try list(h, s.ints, &.{ item, try h.int(.i64, index + 1), try h.int(.i64, index + 2) });
    const record = try h.emit(.{ .op = .record_make, .ty = s.capture, .data = try h.extra(&.{ item, text, ints }) });
    return h.emit(.{ .op = .box_make, .ty = s.env, .a = record });
}
/// Submit 64 moved captures. Half the outcomes are taken; the group owns and
/// destroys the rest. Implicit exit skips taking and lets automatic cleanup join.
pub fn program(a: std.mem.Allocator, implicit_exit: bool, invalid_reuse: bool) Error!ir.Module {
    var m: ir.Module = .{ .single_owner = true, .zero_rc = true };
    try m.strings.appendSlice(a, &.{ "item:", "done:" });
    const s = try shape(a, &m);
    const methods = try api(a, &m, s);
    const worker = try task(a, &m, s);
    const reader = try score(a, &m, s);
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const stream = try h.param(0);
    const group = try call(&h, methods.open, &.{});
    const run = try h.loose(.{ .op = .func_ref, .ty = s.thunk, .data = worker });
    for (0..64) |i| {
        const env = try makeCapture(&h, s, methods, @intCast(i));
        _ = try call(&h, methods.submit, &.{ group, run, env, try h.int(.i64, @intCast(i)) });
        if (invalid_reuse) {
            const record = try h.emit(.{ .op = .box_get, .ty = s.capture, .a = env });
            try h.printValues(stream, &.{try field(&h, record, 0, .i64)});
        }
    }
    var total = try h.int(.u64, 0);
    if (!implicit_exit) {
        const saved = try call(&h, methods.take, &.{ group, try h.int(.i64, 0) });
        for (1..32) |i| {
            const result = try call(&h, methods.take, &.{ group, try h.int(.i64, @intCast(i)) });
            const value = try call(&h, reader, &.{result});
            total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = value, .check = .exact });
        }
        _ = try call(&h, methods.end, &.{group});
        const after_join = try call(&h, reader, &.{saved});
        total = try h.emit(.{ .op = .add, .ty = .u64, .a = total, .b = after_join, .check = .exact });
    }
    try h.printValues(stream, &.{total});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    m.entry = try h.finish();
    return m;
}

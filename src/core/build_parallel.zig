//! A synchronous map keeps borrowed inputs live until every worker has joined.
const std = @import("std");
const ir = @import("ir.zig");
const language = @import("mylang");
/// Allocation and unsupported callback shapes are the lowering failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Only the compiler-owned standard definition selects the task boundary.
pub fn matches(source: ?language.source.Source, checked: language.typed.Function) bool {
    const src = source orelse return false;
    return std.mem.eql(u8, src.locate(checked.declaration.start).path, "@stdlib/parallel.my") and
        std.mem.eql(u8, src.text(checked.declaration), "map");
}

const Writer = struct {
    a: std.mem.Allocator,
    function: ir.Function,
    block: usize = 0,

    fn init(a: std.mem.Allocator, declared: ir.Function) Error!Writer {
        var result: Writer = .{ .a = a, .function = declared };
        try result.function.blocks.append(a, .{});
        return result;
    }
    fn emit(w: *Writer, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(w.function.insts.items.len)));
        try w.function.insts.append(w.a, inst);
        if (inst.op != .param and inst.op != .iconst and inst.op != .func_ref)
            try w.function.blocks.items[w.block].insts.append(w.a, ref);
        return ref;
    }
    fn extra(w: *Writer, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(w.function.extra.items.len);
        try w.function.extra.appendSlice(w.a, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }
    fn integer(w: *Writer, value: u64) Error!ir.Ref {
        return w.emit(.{ .op = .iconst, .ty = .u64, .data = value });
    }
};

const Shape = struct { input: ir.Type, output: ir.Type, callback: ir.Type, capture: ir.Type, env: ir.Type, result: ir.Type, thunk: ir.Type };
fn shape(comptime Context: type, mb: Context, declared: ir.Function) Error!Shape {
    const m = &mb.module;
    const params = declared.signature.params;
    if (params.len != 2 or m.kind(params[0]) != .list or m.kind(params[1]) != .@"fn" or m.kind(declared.signature.ret) != .list)
        return mb.refuse("parallel.map requires a list and a function", declared.span);
    const input = m.compound(params[0]).list;
    const output = m.compound(declared.signature.ret).list;
    if (input == .void or output == .void) return mb.refuse("parallel.map does not support Unit elements", declared.span);
    const callback = m.compound(params[1]).@"fn";
    if (callback.params.len != 1 or callback.params[0] != input or callback.ret != output or callback.owned != 0)
        return mb.refuse("parallel.map requires a read-only function with a non-Unit input and result", declared.span);
    const capture = try m.intern(mb.allocator, .{ .record = &.{ params[0], params[1], .u64, .u64 } });
    const env = try m.intern(mb.allocator, .{ .box = capture });
    const result = declared.signature.ret;
    const thunk = try m.intern(mb.allocator, .{ .@"fn" = .{ .params = try mb.allocator.dupe(ir.Type, &.{env}), .ret = result } });
    return .{ .input = input, .output = output, .callback = params[1], .capture = capture, .env = env, .result = result, .thunk = thunk };
}

fn worker(comptime Context: type, mb: Context, s: Shape, span: u32) Error!u32 {
    const name = try std.fmt.allocPrint(mb.allocator, "<parallel.map.worker.{d}>", .{mb.module.functions.items.len});
    var w = try Writer.init(mb.allocator, .{ .name = name, .signature = mb.module.compound(s.thunk).@"fn", .span = span });
    const env = try w.emit(.{ .op = .param, .ty = s.env, .data = 0 });
    const capture = try w.emit(.{ .op = .box_get, .ty = s.capture, .a = env });
    const source = try w.emit(.{ .op = .record_get, .ty = mb.module.compound(s.capture).record[0], .a = capture, .data = 0 });
    const callback = try w.emit(.{ .op = .record_get, .ty = s.callback, .a = capture, .data = 1 });
    const start = try w.emit(.{ .op = .record_get, .ty = .u64, .a = capture, .data = 2 });
    const count = try w.emit(.{ .op = .record_get, .ty = .u64, .a = capture, .data = 3 });
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
    const result = try w.emit(.{ .op = .call_indirect, .ty = s.output, .a = callback, .data = try w.extra(&.{input}), .span = span });
    const pushed = try w.emit(.{ .op = .list_push, .ty = s.result, .a = output, .b = result });
    const next = try w.emit(.{ .op = .add, .ty = .u64, .a = cursor, .b = try w.integer(1), .check = .exact });
    _ = try w.emit(.{ .op = .jump, .ty = .void, .data = 1 });
    w.function.insts.items[cursor.index()].data = try w.extra(&.{ start, next });
    w.function.insts.items[output.index()].data = try w.extra(&.{ empty, pushed });
    try w.function.loops.append(w.a, .{ .id = 0, .header = @fromBackingInt(@intCast(1)), .body = @fromBackingInt(@intCast(2)), .latch = @fromBackingInt(@intCast(2)), .exit = @fromBackingInt(@intCast(3)) });
    w.block = 3;
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = output });
    const index: u32 = @intCast(mb.module.functions.items.len);
    try mb.module.functions.append(mb.allocator, w.function);
    return index;
}

/// Build the standard map body at its ordinary callable ABI, including indirect calls.
pub fn build(mb: anytype, declared: ir.Function) Error!ir.Function {
    const s = try shape(@TypeOf(mb), mb, declared);
    const task = try worker(@TypeOf(mb), mb, s, declared.span);
    var w = try Writer.init(mb.allocator, declared);
    const list = try w.emit(.{ .op = .param, .ty = declared.signature.params[0], .data = 0 });
    const callback = try w.emit(.{ .op = .param, .ty = s.callback, .data = 1 });
    const run = try w.emit(.{ .op = .func_ref, .ty = s.thunk, .data = task });
    const length = try w.emit(.{ .op = .list_len, .ty = .u64, .a = list });
    const out = try w.emit(.{ .op = .list_new, .ty = declared.signature.ret, .a = length });
    const callback_offset = try w.integer(mb.module.fieldOffset(s.capture, 1));
    const start_offset = try w.integer(mb.module.fieldOffset(s.capture, 2));
    const count_offset = try w.integer(mb.module.fieldOffset(s.capture, 3));
    const output_size = try w.integer(mb.module.size(s.output));
    const target = try mb.runtimeFunction("myl_core_owned_map", &.{ declared.signature.params[0], s.callback, s.thunk, .u64, .u64, .u64, declared.signature.ret, .u64 }, declared.signature.ret, .extern_c);
    const args = try w.extra(&.{ list, callback, run, callback_offset, start_offset, count_offset, out, output_size });
    const result = try w.emit(.{ .op = .call, .ty = declared.signature.ret, .a = @fromBackingInt(target), .data = args, .span = declared.span });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = result });
    return w.function;
}

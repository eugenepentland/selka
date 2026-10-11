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

    fn init(a: std.mem.Allocator, declared: ir.Function) Error!Writer {
        var result: Writer = .{ .a = a, .function = declared };
        try result.function.blocks.append(a, .{});
        return result;
    }
    fn emit(w: *Writer, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(w.function.insts.items.len)));
        try w.function.insts.append(w.a, inst);
        if (inst.op != .param and inst.op != .iconst and inst.op != .func_ref)
            try w.function.blocks.items[0].insts.append(w.a, ref);
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
    const capture = try m.intern(mb.allocator, .{ .record = &.{ input, params[1] } });
    const env = try m.intern(mb.allocator, .{ .box = capture });
    const result = try m.intern(mb.allocator, .{ .box = output });
    const thunk = try m.intern(mb.allocator, .{ .@"fn" = .{ .params = try mb.allocator.dupe(ir.Type, &.{env}), .ret = result } });
    return .{ .input = input, .output = output, .callback = params[1], .capture = capture, .env = env, .result = result, .thunk = thunk };
}

fn worker(comptime Context: type, mb: Context, s: Shape, span: u32) Error!u32 {
    const name = try std.fmt.allocPrint(mb.allocator, "<parallel.map.worker.{d}>", .{mb.module.functions.items.len});
    var w = try Writer.init(mb.allocator, .{ .name = name, .signature = mb.module.compound(s.thunk).@"fn", .span = span });
    const env = try w.emit(.{ .op = .param, .ty = s.env, .data = 0 });
    const capture = try w.emit(.{ .op = .box_get, .ty = s.capture, .a = env });
    const input = try w.emit(.{ .op = .record_get, .ty = s.input, .a = capture, .data = 0 });
    const callback = try w.emit(.{ .op = .record_get, .ty = s.callback, .a = capture, .data = 1 });
    const result = try w.emit(.{ .op = .call_indirect, .ty = s.output, .a = callback, .data = try w.extra(&.{input}), .span = span });
    const box = try w.emit(.{ .op = .box_make, .ty = s.result, .a = result });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = box });
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
    const input_size = try w.integer(mb.module.size(s.input));
    const callback_offset = try w.integer(mb.module.fieldOffset(s.capture, 1));
    const env_size = try w.integer(mb.module.size(s.capture));
    const output_size = try w.integer(mb.module.size(s.output));
    const target = try mb.runtimeFunction("myl_core_owned_map", &.{ declared.signature.params[0], s.callback, s.thunk, .u64, .u64, .u64, declared.signature.ret, .u64 }, declared.signature.ret, .extern_c);
    const result = try w.emit(.{ .op = .call, .ty = declared.signature.ret, .a = @fromBackingInt(target), .data = try w.extra(&.{ list, callback, run, input_size, callback_offset, env_size, out, output_size }), .span = declared.span });
    _ = try w.emit(.{ .op = .ret, .ty = .void, .a = result });
    return w.function;
}

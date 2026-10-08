//! A batched copied-value test entry using the frozen Core IR and C helper ABI.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const entry = @import("test_runner_entry.zig");
const adapters = @import("property_ir.zig");
const types = @import("property_types.zig");
/// Allocation or a checked data type without a generator.
pub const Error = adapters.Error;
/// Type names paired with the ordered Core parameter/result types.
pub const Signature = struct { parameters: []const []const u8, result: []const u8 };
/// Build an argv dispatcher and a copied-value trial wrapper per selected test.
pub fn add(a: std.mem.Allocator, module: *ir.Module, tests: []const entry.Target, schema: types.Schema) Error!void {
    var context: adapters.Context = .{ .arena = a, .module = module, .schema = schema };
    const callbacks = try a.alloc(u32, tests.len);
    for (tests, callbacks) |target, *callback| callback.* = try trial(&context, target);
    const list_of_str = try module.intern(a, .{ .list = .str });
    const parsed_type = try module.option(a, .i64);
    const callback_type = try module.intern(a, .{ .@"fn" = .{ .params = &.{}, .ret = .void } });
    var b: tools.Builder = .{ .arena = a, .function = .{ .name = entry.entry_name, .signature = .{ .params = try a.dupe(ir.Type, &.{list_of_str}), .ret = .i64 } } };
    const start = try b.block();
    const parse = try b.block();
    const select = try b.block();
    const usage = try b.block();
    const args = try b.detached(.{ .op = .param, .ty = list_of_str });
    const have = try b.put(start, .{ .op = .list_len, .ty = .u64, .a = args });
    const enough = try b.put(start, .{ .op = .cmp, .ty = .bool, .a = have, .b = try b.constant(.u64, 3), .data = @backingInt(ir.Predicate.ge) });
    try b.branch(start, enough, parse, usage);
    const first = try b.put(parse, .{ .op = .list_get, .ty = .str, .a = args, .b = try b.constant(.u64, 0) });
    const number = try b.put(parse, .{ .op = .str_parse_int, .ty = parsed_type, .a = first });
    const tag = try b.put(parse, .{ .op = .union_tag, .ty = .u32, .a = number });
    const some = try b.put(parse, .{ .op = .cmp, .ty = .bool, .a = tag, .b = try b.constant(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    try b.branch(parse, some, select, usage);
    const index = try b.put(select, .{ .op = .union_payload, .ty = .i64, .a = number, .data = 1 });
    var at = select;
    for (callbacks, 0..) |callback, position| {
        const hit = try b.block();
        const run = try b.block();
        const next = try b.block();
        const is_it = try b.put(at, .{ .op = .cmp, .ty = .bool, .a = index, .b = try b.constant(.i64, @intCast(position)), .data = @backingInt(ir.Predicate.eq) });
        try b.branch(at, is_it, hit, next);
        const input = try b.put(hit, .{ .op = .list_get, .ty = .str, .a = args, .b = try b.constant(.u64, 1) });
        const output = try b.put(hit, .{ .op = .list_get, .ty = .str, .a = args, .b = try b.constant(.u64, 2) });
        const opened = try b.call(hit, module, try tools.helper(a, module, "myl_core_test_open", &.{ .str, .str }, .bool), &.{ input, output });
        try b.branch(hit, opened, run, usage);
        const function = try b.put(run, .{ .op = .func_ref, .ty = callback_type, .data = callback });
        const status = try b.call(run, module, try tools.helper(a, module, "myl_core_test_run", &.{callback_type}, .i64), &.{function});
        _ = try b.put(run, .{ .op = .ret, .ty = .void, .a = status });
        at = next;
    }
    try b.jump(at, usage);
    _ = try b.put(usage, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, entry.status_usage) });
    module.entry = @intCast(module.functions.items.len);
    try module.functions.append(a, b.function);
    try context.finish();
    try retainTraceOwners(a, module);
}
/// The leaf inliner keeps instruction spans but uses the caller's name for
/// trace sites. A real return block keeps trace-bearing test functions intact
/// until LLVM sees their already recorded source owner. Only test modules use
/// this control-flow boundary; neither the frozen IR nor shared passes change.
fn retainTraceOwners(a: std.mem.Allocator, module: *ir.Module) Error!void {
    for (module.functions.items) |*function| {
        if (function.blocks.items.len != 1) continue;
        const body = function.blocks.items[0].insts.items;
        if (body.len == 0 or function.inst(body[body.len - 1]).op != .ret) continue;
        var traced = false;
        for (body) |ref| traced = traced or function.inst(ref).op == .err_trace;
        if (!traced) continue;
        const returned = body[body.len - 1];
        var b: tools.Builder = .{ .arena = a, .function = function.* };
        b.function.blocks.items[0].insts.items.len -= 1;
        const end = try b.block();
        try b.jump(@fromBackingInt(0), end);
        try b.function.blocks.items[end.index()].insts.append(a, returned);
        function.* = b.function;
    }
}
fn trial(context: *adapters.Context, target: entry.Target) Error!u32 {
    const a = context.arena;
    const module = context.module;
    const signature = target.data orelse return error.UnsupportedTestType;
    const source = module.functions.items[target.function].signature;
    var digest: [16]u8 = undefined;
    std.crypto.hash.Blake3.hash(module.functions.items[target.function].name, &digest, .{});
    var b: tools.Builder = .{ .arena = a, .function = .{ .name = try std.fmt.allocPrint(a, "__test_trial_{s}", .{std.fmt.bytesToHex(digest, .lower)}), .signature = .{ .params = &.{}, .ret = .void } } };
    const start = try b.block();
    const arguments = try a.alloc(ir.Ref, source.params.len);
    var stream_index: usize = 0;
    for (arguments, source.params, target.parameters, signature.parameters) |*argument, ty, family, name| {
        if (family == 5) {
            argument.* = try b.constant(.cap, target.streams[stream_index]);
            stream_index += 1;
        } else if (family <= 4) {
            const operand: i64 = if (family == 0) 946684800000000000 else if (family == 1) @bitCast(target.seed) else 0;
            const helper = try tools.helper(a, module, "myl_core_stand_in", &.{ .u32, .i64 }, .capability);
            argument.* = try b.call(start, module, helper, &.{ try b.constant(.u32, family), try b.constant(.i64, operand) });
        } else {
            argument.* = try b.call(start, module, try context.adapter(name, ty, false), &.{});
        }
    }
    const result = try b.call(start, module, target.function, arguments);
    const encode = try context.adapter(signature.result, source.ret, true);
    _ = try b.call(start, module, encode, &.{result});
    var end = start;
    if (target.result) |shape| {
        const trace = try b.block();
        const done = try b.block();
        const tag = try b.put(start, .{ .op = .union_tag, .ty = .u32, .a = result });
        const bad = try b.put(start, .{ .op = .cmp, .ty = .bool, .a = tag, .b = try b.constant(.u32, shape.error_tag), .data = @backingInt(ir.Predicate.eq) });
        try b.branch(start, bad, trace, done);
        _ = try b.call(trace, module, try tools.helper(a, module, "myl_core_test_trace", &.{}, .void), &.{});
        try b.jump(trace, done);
        end = done;
    }
    _ = try b.put(end, .{ .op = .ret, .ty = .void });
    const index: u32 = @intCast(module.functions.items.len);
    try module.functions.append(a, b.function);
    return index;
}

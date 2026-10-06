//! The dispatching entry of a test executable (docs/design/new-core-s1.md §9).
//!
//! `mylang-core test` builds one executable per file. Its `main` is this synthesized
//! function, `__test_main(args: list[str]) -> int`: it parses the first argument as the
//! decimal index of a test in the runner's table, calls that test, and exits with
//! `status_pass`, `status_false` (the test returned false) or `status_usage` (no such
//! test). A trap inside the test exits 1 through the runtime, as in every program. The
//! index stands for the qualified name because the IR has no string comparison yet;
//! the runner owns the name-to-index table.
const std = @import("std");
const ir = @import("ir.zig");

/// Exit status of a test that returned true.
pub const status_pass: u8 = 0;
/// Exit status of a test that returned false.
pub const status_false: u8 = 2;
/// Exit status when the index argument is missing, malformed or past the last test.
pub const status_usage: u8 = 64;

/// The name of the synthesized entry function.
pub const entry_name = "__test_main";

/// Whether a test returning `ret` has a verdict this entry can read.
pub fn readable(module: *const ir.Module, ret: ir.Type) bool {
    if (ret == .bool) return true;
    if (module.kind(ret) != .@"union") return false;
    for (module.compound(ret).@"union") |payload| if (payload == .bool) return true;
    return false;
}

/// A test the entry can call.
pub const Target = struct {
    /// The test's index in `Module.functions`.
    function: u32,
    /// The capability value passed for each `Stream` parameter (1 stdout, 2 stderr).
    streams: []const i64 = &.{},
    /// Capability families in source parameter order.
    parameters: []const u8 = &.{},
    /// Stable name-derived entropy seed.
    seed: u64 = 0,
    /// Result case tags for Result[bool,E].
    result: ?@import("emit_llvm.zig").MainResult = null,
    /// Checked source type names for generated input and result adapters.
    data: ?struct { parameters: []const []const u8, result: []const u8 } = null,
};

/// Append the dispatching entry to `module` and make it the module's entry. `tests` are
/// the tests in table order; each must return a readable type.
pub fn addEntry(allocator: std.mem.Allocator, module: *ir.Module, tests: []const Target) std.mem.Allocator.Error!void {
    const list_of_str = try module.intern(allocator, .{ .list = .str });
    const parsed_type = try module.option(allocator, .i64);
    var b: Builder = .{ .arena = allocator, .function = .{ .name = entry_name, .signature = .{ .params = try allocator.dupe(ir.Type, &.{list_of_str}), .ret = .i64 } } };
    const start = try b.block();
    const parse = try b.block();
    const select = try b.block();
    const pass = try b.block();
    const fail = try b.block();
    const usage = try b.block();
    // b0: at least one argument?
    const args = try b.detached(.{ .op = .param, .ty = list_of_str, .data = 0 });
    const have = try b.put(start, .{ .op = .list_len, .ty = .u64, .a = args });
    const enough = try b.put(start, .{ .op = .cmp, .ty = .bool, .a = have, .b = try b.constant(.u64, 1), .data = @backingInt(ir.Predicate.ge) });
    try b.branch(start, enough, parse, usage);
    // b1: parse the index; a malformed one is a usage error.
    const first = try b.put(parse, .{ .op = .list_get, .ty = .str, .a = args, .b = try b.constant(.u64, 0) });
    const number = try b.put(parse, .{ .op = .str_parse_int, .ty = parsed_type, .a = first });
    const tag = try b.put(parse, .{ .op = .union_tag, .ty = .u32, .a = number });
    const some = try b.put(parse, .{ .op = .cmp, .ty = .bool, .a = tag, .b = try b.constant(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    try b.branch(parse, some, select, usage);
    // b2..: compare the index with each test's position and call the match.
    const index = try b.put(select, .{ .op = .union_payload, .ty = .i64, .a = number, .data = 1 });
    var at = select;
    for (tests, 0..) |target, position| {
        const hit = try b.block();
        const next = try b.block();
        const is_it = try b.put(at, .{ .op = .cmp, .ty = .bool, .a = index, .b = try b.constant(.i64, @intCast(position)), .data = @backingInt(ir.Predicate.eq) });
        try b.branch(at, is_it, hit, next);
        const arguments = try inject(&b, module, target, hit);
        const ret = module.functions.items[target.function].signature.ret;
        const verdict = try b.put(hit, .{ .op = .call, .ty = ret, .a = @fromBackingInt(target.function), .data = try b.extra(arguments) });
        if (ret == .bool) try b.branch(hit, verdict, pass, fail) else {
            const tags = target.result orelse return error.OutOfMemory;
            const ok = try b.block();
            const bad = try b.block();
            const result_tag = try b.put(hit, .{ .op = .union_tag, .ty = .u32, .a = verdict });
            const is_ok = try b.put(hit, .{ .op = .cmp, .ty = .bool, .a = result_tag, .b = try b.constant(.u32, tags.ok_tag), .data = @backingInt(ir.Predicate.eq) });
            try b.branch(hit, is_ok, ok, bad);
            const truth = try b.put(ok, .{ .op = .union_payload, .ty = .bool, .a = verdict, .data = tags.ok_tag });
            try b.branch(ok, truth, pass, fail);
            const error_type = module.compound(ret).@"union"[tags.error_tag];
            const error_value = try b.put(bad, .{ .op = .union_payload, .ty = error_type, .a = verdict, .data = tags.error_tag });
            _ = try b.put(bad, .{ .op = .print, .ty = .void, .data = try b.extra(&.{ try b.constant(.cap, 3), error_value }) });
            _ = try b.put(bad, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, 1) });
        }
        at = next;
    }
    try b.jump(at, usage);
    _ = try b.put(pass, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_pass) });
    _ = try b.put(fail, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_false) });
    _ = try b.put(usage, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_usage) });
    module.entry = @intCast(module.functions.items.len);
    try module.functions.append(allocator, b.function);
}

const Builder = @import("test_builder.zig").Builder;
const helper = @import("test_builder.zig").helper;
fn inject(b: *Builder, module: *ir.Module, target: Target, at: ir.BlockId) ![]const ir.Ref {
    const count = if (target.parameters.len == 0) target.streams.len else target.parameters.len;
    const arguments = try b.arena.alloc(ir.Ref, count);
    var stream_index: usize = 0;
    for (arguments, 0..) |*argument, index| {
        const family = if (target.parameters.len == 0) @as(u8, 5) else target.parameters[index];
        if (family == 5) {
            argument.* = try b.constant(.cap, target.streams[stream_index]);
            stream_index += 1;
            continue;
        }
        const callee = try helper(b.arena, module, "myl_core_stand_in", &.{ .u32, .i64 }, .capability);
        const operand: i64 = if (family == 0) 946684800000000000 else if (family == 1) @bitCast(target.seed) else 0;
        argument.* = try b.put(at, .{ .op = .call, .ty = .capability, .a = @fromBackingInt(callee), .data = try b.extra(&.{ try b.constant(.u32, family), try b.constant(.i64, operand) }) });
    }
    return arguments;
}

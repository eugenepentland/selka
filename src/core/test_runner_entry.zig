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
pub fn readable(ret: ir.Type) bool {
    return ret == .bool;
}

/// A test the entry can call.
pub const Target = struct {
    /// The test's index in `Module.functions`.
    function: u32,
    /// The capability value passed for each `Stream` parameter (1 stdout, 2 stderr).
    streams: []const i64 = &.{},
};

/// Append the dispatching entry to `module` and make it the module's entry. `tests` are
/// the tests in table order; each must return a readable type.
pub fn addEntry(allocator: std.mem.Allocator, module: *ir.Module, tests: []const Target) std.mem.Allocator.Error!void {
    const list_of_str = try module.intern(allocator, .{ .list = .str });
    const parsed_type = try module.option(allocator, .i64);
    var b: Builder = .{ .allocator = allocator, .function = .{ .name = entry_name, .signature = .{ .params = try allocator.dupe(ir.Type, &.{list_of_str}), .ret = .i64 } } };
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
        const arguments = try allocator.alloc(ir.Ref, target.streams.len);
        for (arguments, target.streams) |*argument, stream| argument.* = try b.constant(.cap, stream);
        const verdict = try b.put(hit, .{ .op = .call, .ty = .bool, .a = @fromBackingInt(target.function), .data = try b.extra(arguments) });
        try b.branch(hit, verdict, pass, fail);
        at = next;
    }
    try b.jump(at, usage);
    _ = try b.put(pass, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_pass) });
    _ = try b.put(fail, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_false) });
    _ = try b.put(usage, .{ .op = .ret, .ty = .void, .a = try b.constant(.i64, status_usage) });
    module.entry = @intCast(module.functions.items.len);
    try module.functions.append(allocator, b.function);
}

const Builder = struct {
    allocator: std.mem.Allocator,
    function: ir.Function,

    fn block(self: *Builder) std.mem.Allocator.Error!ir.BlockId {
        const id: ir.BlockId = @fromBackingInt(@intCast(self.function.blocks.items.len));
        try self.function.blocks.append(self.allocator, .{});
        return id;
    }

    /// An instruction that belongs to no block (a parameter or a constant).
    fn detached(self: *Builder, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.allocator, inst);
        return ref;
    }

    fn constant(self: *Builder, ty: ir.Type, value: i64) std.mem.Allocator.Error!ir.Ref {
        return self.detached(.{ .op = .iconst, .ty = ty, .data = @bitCast(value) });
    }

    /// Append `inst` to `in`.
    fn put(self: *Builder, in: ir.BlockId, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
        const ref = try self.detached(inst);
        try self.function.blocks.items[in.index()].insts.append(self.allocator, ref);
        return ref;
    }

    fn extra(self: *Builder, refs: []const ir.Ref) std.mem.Allocator.Error!u64 {
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.allocator, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }

    fn jump(self: *Builder, from: ir.BlockId, to: ir.BlockId) std.mem.Allocator.Error!void {
        _ = try self.put(from, .{ .op = .jump, .ty = .void, .data = @backingInt(to) });
        try self.function.blocks.items[to.index()].preds.append(self.allocator, from);
    }

    fn branch(self: *Builder, from: ir.BlockId, condition: ir.Ref, then: ir.BlockId, otherwise: ir.BlockId) std.mem.Allocator.Error!void {
        _ = try self.put(from, .{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(then, otherwise) });
        try self.function.blocks.items[then.index()].preds.append(self.allocator, from);
        try self.function.blocks.items[otherwise.index()].preds.append(self.allocator, from);
    }
};

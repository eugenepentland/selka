//! The borrowed-provider identity carries no ownership or runtime implementation.
const std = @import("std");
const ir = @import("ir.zig");
const borrowed = @import("borrowed_provider.zig");
const Hand = @import("test_support.zig").Hand;

const Fixture = struct { module: ir.Module, function: u32, marker: u32, value: ir.Ref, first: ir.Ref, second: ir.Ref };
fn fixture(a: std.mem.Allocator) !Fixture {
    var module: ir.Module = .{ .zero_rc = true };
    const ty = try module.intern(a, .{ .record = &.{ .capability, .capability, .i64 } });
    const marker = try borrowed.declare(a, &module, ty);
    var h = try Hand.init(a, &module, "context", .{ .params = &.{ .capability, .capability }, .ret = .i64 });
    const first = try h.param(0);
    const second = try h.param(1);
    const value = try h.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(marker), .data = try h.extra(&.{ first, second, try h.int(.i64, 7) }) });
    const scalar = try h.emit(.{ .op = .record_get, .ty = .i64, .a = value, .data = 2 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = scalar });
    const index = try h.finish();
    return .{ .module = module, .function = index, .marker = marker, .value = value, .first = first, .second = second };
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider marker admits only exact flat signature and parameter roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    try borrowed.validateModule(a, &f.module);
    const function = &f.module.functions.items[f.function];
    try std.testing.expect(borrowed.contains(&f.module, function));
    try std.testing.expectEqual(@as(usize, 3), (try borrowed.call(&f.module, function, function.inst(f.value))).?.len);
    function.signature.owned = 1;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.signature.owned = 0;
    function.signature.consumes = 2;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider marker refuses wrong ABI malformed identity and nested storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const marker = &f.module.functions.items[f.marker];
    const original = marker.*;
    for ([_][]const u8{ borrowed.prefix, borrowed.prefix ++ "015", borrowed.prefix ++ "15x", borrowed.prefix ++ "4294967295" }) |name| {
        marker.name = name;
        try std.testing.expectError(error.UnsupportedInstruction, borrowed.declaration(&f.module, marker));
    }
    marker.* = original;
    marker.signature.linkage = .internal;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.declaration(&f.module, marker));
    marker.* = original;
    marker.signature.owned = 1;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.declaration(&f.module, marker));
    marker.* = original;
    marker.signature.ret = .capability;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.declaration(&f.module, marker));
    marker.* = original;
    const nested = try f.module.intern(a, .{ .record = &.{original.signature.ret} });
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.declare(a, &f.module, nested));
    const mixed = try f.module.intern(a, .{ .record = &.{ .capability, .str } });
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.declare(a, &f.module, mixed));
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider marker refuses field return and structural mutation through copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const function = &f.module.functions.items[f.function];
    const index = function.insts.items.len - 1;
    const original = function.insts.items[index];
    function.insts.items[index].a = f.value;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.insts.items[index] = original;
    const alias: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(a, .{ .op = .copy, .ty = function.inst(f.value).ty, .a = f.value });
    const projected: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(a, .{ .op = .record_get, .ty = .capability, .a = alias, .data = 0 });
    function.insts.items[index].a = projected;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.insts.items[index] = .{ .op = .record_set, .ty = function.inst(f.value).ty, .a = alias, .b = f.first, .data = 0 };
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider marker rejects foreign origins malformed operand ranges and copy cycles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const function = &f.module.functions.items[f.function];
    const original = function.insts.items[f.value.index()];
    function.insts.items[f.value.index()].data = std.math.maxInt(u64);
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.insts.items[f.value.index()] = original;
    const param = function.insts.items[f.first.index()];
    function.insts.items[f.first.index()] = .{ .op = .undef, .ty = .capability };
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.insts.items[f.first.index()] = .{ .op = .copy, .ty = .capability, .a = f.first };
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validate(a, &f.module, function));
    function.insts.items[f.first.index()] = param;
    f.module.zero_rc = false;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.validateModule(a, &f.module));
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider construction prevents inlining away immutable parameter provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    var caller = try Hand.init(a, &f.module, "caller", .{ .params = &.{ .capability, .capability }, .ret = .i64 });
    const result = try caller.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(f.function), .data = try caller.extra(&.{ try caller.param(0), try caller.param(1) }) });
    _ = try caller.emit(.{ .op = .ret, .ty = .void, .a = result });
    const index = try caller.finish();
    var origins: @import("inline_origins.zig").Table = .{};
    const changed = try @import("inline.zig").leafCaller(a, &f.module, index, &.{}, &origins);
    try std.testing.expectEqual(@as(u32, 0), changed);
    const cfg = try @import("inline.zig").cfgCallerDemandWithScratch(a, a, &f.module, index, &origins, null);
    try std.testing.expectEqual(@as(u32, 0), cfg);
    try std.testing.expect(!try @import("destination.zig").qualifies(a, &f.module, &f.module.functions.items[f.function]));
    try borrowed.validateModule(a, &f.module);
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider source predicate recognizes exact immutable parameters and excludes nesting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Context:
        \\    fs: Filesystem
        \\    env: Environment
        \\func main(fs: Filesystem, env: Environment) -> int:
        \\    mut ctx = Context(fs=fs, env=env)
        \\    return len(ctx.env.names())
    ;
    var unit = try @import("mylang").Compilation.init(a, "borrowed-provider.my", source);
    try unit.check();
    const program = unit.program.?;
    const function = program.functions[@backingInt(program.main)];
    try std.testing.expectEqual(@as(usize, 1), initializerCount(program, function));
    const locals = try a.dupe(@import("mylang").typed.Local, function.scope.locals);
    locals[0].mutable = true;
    var mutable = function;
    mutable.scope.locals = locals;
    try std.testing.expectEqual(@as(usize, 0), initializerCount(program, mutable));
}

fn initializerCount(program: @import("mylang").typed.Program, function: @import("mylang").typed.Function) usize {
    var count: usize = 0;
    for (program.nodes, 0..) |node, index| {
        if (node.data == .record and borrowed.initializer(program, function, @fromBackingInt(index))) count += 1;
    }
    return count;
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "borrowed provider noalloc proof refuses malformed helpers and source extern names" {
    var module: ir.Module = .{ .zero_rc = true };
    var function: ir.Function = .{ .name = "myl_core_provider_keepalive", .signature = .{ .params = &.{.capability}, .ret = .void, .linkage = .runtime_c } };
    try std.testing.expect(try borrowed.keepalive(&module, &function));
    const original = function;
    function.signature.linkage = .extern_c;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.keepalive(&module, &function));
    function = original;
    function.span = 4;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.keepalive(&module, &function));
    function = original;
    function.signature.params = &.{.i64};
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.keepalive(&module, &function));
    function = original;
    function.signature.owned = 1;
    try std.testing.expectError(error.UnsupportedInstruction, borrowed.keepalive(&module, &function));
}

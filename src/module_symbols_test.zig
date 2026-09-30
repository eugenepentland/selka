//! What a module compile consumed of its imports' emission sections, by
//! symbol (MODULE-SYMBOL-CUTOFF-1).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const symbols = language.module_symbols;
const physical = language.module_physical;
const bytecode = language.bytecode;
const Interface = language.module_interface.Interface;

const at: @import("source.zig").Span = .{ .start = 0, .end = 0 };

fn call(target: usize) bytecode.Instruction {
    return .{ .span = at, .op = .{ .call = @fromBackingInt(target) } };
}

fn constant(value: i64) bytecode.Instruction {
    return .{ .span = at, .op = .{ .push_i64 = value } };
}

/// `main.run` calls `lib.api`, which calls `lib.helper`; `lib.other` is
/// reached by nothing.
fn program(a: std.mem.Allocator, helper: i64, other: i64) ![]bytecode.Function {
    return a.dupe(bytecode.Function, &.{
        .{ .name = "main.run", .id = @fromBackingInt(0), .scope = .{ .instructions = try a.dupe(bytecode.Instruction, &.{call(1)}) } },
        .{ .name = "lib.api", .id = @fromBackingInt(1), .scope = .{ .instructions = try a.dupe(bytecode.Instruction, &.{call(2)}) } },
        .{ .name = "lib.helper", .id = @fromBackingInt(2), .scope = .{ .instructions = try a.dupe(bytecode.Instruction, &.{constant(helper)}) } },
        .{ .name = "lib.other", .id = @fromBackingInt(3), .scope = .{ .instructions = try a.dupe(bytecode.Instruction, &.{constant(other)}) } },
    });
}

/// `lib`'s interface whose archive holds the bodies of `functions` but the first.
fn library(a: std.mem.Allocator, functions: []const bytecode.Function) !Interface {
    const archive = try physical.archive(a, .{ .functions = functions }, &.{ false, true, true, true });
    return .{ .module = "lib", .text = "", .emission = .{ .config = "rc", .physical = archive } };
}

fn digestOf(a: std.mem.Allocator, interface: Interface, reached: []const []const u8) ![32]u8 {
    const table = try symbols.Table.of(a, interface);
    return table.digest(a, reached);
}

// spec: MODULE-SYMBOL-CUTOFF-1
test "a compile consumes the rows of the functions its emitted units reach, and only those" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = try program(a, 1, 2);
    const reached = (try symbols.reach(a, .{ .functions = functions }, &.{ true, false, false, false })).?;
    try t.expectEqual(@as(usize, 3), reached.len);
    try t.expectEqualStrings("lib.api", reached[0]);
    try t.expectEqualStrings("lib.helper", reached[1]);
    try t.expectEqualStrings("main.run", reached[2]);
    const before = try digestOf(a, try library(a, functions), reached);
    // A body nothing reached changes: what the compile consumed did not.
    const unreached = try program(a, 1, 5);
    try t.expectEqual(before, try digestOf(a, try library(a, unreached), reached));
    // A body reached only transitively changes: it did.
    const transitive = try program(a, 7, 2);
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, try library(a, transitive), reached))));
    // Another emission configuration is another input.
    var configured = try library(a, functions);
    configured.emission.config = "gc";
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, configured, reached))));
    // A reached function's emission facts are part of what was consumed.
    var stated = try library(a, functions);
    stated.emission.functions = &.{.{ .name = "lib.api", .allocates = true, .writes = &.{} }};
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, stated, reached))));
}

// spec-case: MODULE-SYMBOL-CUTOFF-1
test "a reached function value call or an unknown callee consumes every row" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = try program(a, 1, 2);
    functions[2].scope.instructions = &.{.{ .span = at, .op = .{ .invoke = .i64 } }};
    try t.expect((try symbols.reach(a, .{ .functions = functions }, &.{ true, false, false, false })) == null);
    // Only reached bodies count: the same call in `lib.other` is not read.
    functions[2].scope.instructions = &.{constant(1)};
    functions[3].scope.instructions = &.{.{ .span = at, .op = .{ .invoke = .i64 } }};
    try t.expect((try symbols.reach(a, .{ .functions = functions }, &.{ true, false, false, false })) != null);
    // Two functions of one name cannot say which one was reached.
    functions[3].name = "lib.api";
    try t.expect((try symbols.reach(a, .{ .functions = functions }, &.{ true, false, false, false })) == null);
}

// spec-case: MODULE-SYMBOL-CUTOFF-1
test "records, invariant callbacks and the modules dependency rows name are consumed whole" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = try program(a, 1, 2);
    const reached: []const []const u8 = &.{ "lib.api", "lib.helper", "main.run" };
    const base = try library(a, functions);
    const before = try digestOf(a, base, reached);
    var recorded = base;
    recorded.emission.physical.records = &.{.{ .name = "lib.Hidden", .bytes = "x" }};
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, recorded, reached))));
    var callback = base;
    const rows = base.emission.physical.functions;
    callback.emission.physical.functions = &.{ rows[0], rows[1], rows[2], .{ .name = "@invariant:lib.Hidden", .bytes = "y" } };
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, callback, reached))));
    var dependent = base;
    dependent.emission.physical.dependencies = &.{.{ .name = "other::far", .bytes = "z" }};
    try t.expect(!std.mem.eql(u8, &before, &(try digestOf(a, dependent, reached))));
}

// spec-case: MODULE-SYMBOL-CUTOFF-5
test "positions read through some stretches ignore the others and every source offset" {
    const text = "def a():\n    pass\n\ndef b():\n    pass\n";
    const origins = [_]language.module_interface.Origin{
        .{ .text = 0, .source = 0, .len = 17, .gap = 1, .line = 1, .column = 1 },
        .{ .text = 18, .source = 30, .len = 17, .gap = 0, .line = 5, .column = 1 },
    };
    const interface: Interface = .{ .module = "lib", .text = text, .positions = .{ .origins = &origins } };
    const before = symbols.stretchDigest(interface, &.{0});
    // The second stretch moved down two lines and along the source.
    var moved = origins;
    moved[1].line = 7;
    moved[1].source = 44;
    var later = interface;
    later.positions.origins = &moved;
    try t.expectEqual(before, symbols.stretchDigest(later, &.{0}));
    try t.expect(!std.mem.eql(u8, &symbols.stretchDigest(interface, &.{1}), &symbols.stretchDigest(later, &.{1})));
    // The first stretch's own line, or where a stretch lies in the text, is read.
    var shifted = origins;
    shifted[0].line = 2;
    later.positions.origins = &shifted;
    try t.expect(!std.mem.eql(u8, &before, &symbols.stretchDigest(later, &.{0})));
    var spread = origins;
    spread[0].gap = 0;
    later.positions.origins = &spread;
    try t.expect(!std.mem.eql(u8, &before, &symbols.stretchDigest(later, &.{0})));
    // A stretch after the last one read decides nothing.
    var tail = origins;
    tail[1].gap = 3;
    later.positions.origins = &tail;
    try t.expectEqual(before, symbols.stretchDigest(later, &.{0}));
}

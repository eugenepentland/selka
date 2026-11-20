//! What the emitter made, described to the `unit-emit` kind (part 2, G4a step 3; spec §17.2).
//!
//! `compute` takes the units the emitter returned (each keyed by a compact receipt, `emit_units.Identity`), the key of every function
//! of the module (`program_facts_shadow.keysOf`, the names the optimizer's shadow publishes its `opt:` parts under) and the
//! `unit-optimize` argument that holds each function, and describes each unit as the kind answers it: the argument, the payload (the
//! digest of the unit's text) and the optimizer parts the emission reads. A function no optimizer unit claims is counted, never
//! silently dropped.
const std = @import("std");
const kind = @import("engine/kinds/unit_emit.zig");
const emit_units = @import("emit_units.zig");
const optimize_shadow = @import("optimize_shadow.zig");

/// One unit's emission: the argument and the answer.
pub const Unit = struct { argument: []const u8, answer: kind.Answer };

/// The units described, and how many functions of them no optimizer unit claims.
pub const Described = struct { units: []const Unit, unowned: u32 };

/// The name a unit is asked under: a module by its path, the entry as itself, and a generic instance or helper by its first function's key.
fn nameOf(a: std.mem.Allocator, unit: emit_units.Unit, identity: emit_units.Identity, keys: []const ?[]const u8) std.mem.Allocator.Error![]const u8 {
    return switch (unit.kind) {
        .module => std.fmt.allocPrint(a, "module:{s}", .{unit.source_path}),
        .entry => "entry",
        .program => "program",
        .generic, .helper => blk: {
            for (identity.functions) |index| if (index < keys.len) if (keys[index]) |key| break :blk try std.fmt.allocPrint(a, "{s}:{s}", .{ @tagName(unit.kind), key });
            break :blk try std.fmt.allocPrint(a, "{s}:{s}", .{ @tagName(unit.kind), unit.name });
        },
    };
}

fn partBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The optimizer parts `identity`'s functions are read from, grouped by the unit-optimize argument that holds each. `owner` maps a
/// function key to that argument. Reads come in the order the arguments are first met, and their parts sorted.
fn readsOf(a: std.mem.Allocator, identity: emit_units.Identity, keys: []const ?[]const u8, owner: *const std.StringHashMapUnmanaged([]const u8), unowned: *u32) std.mem.Allocator.Error![]const kind.Read {
    var arguments: std.ArrayList([]const u8) = .empty;
    var parts: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    for (identity.functions) |index| {
        if (index >= keys.len) continue;
        const key = keys[index] orelse continue;
        const argument = owner.get(key) orelse {
            unowned.* += 1;
            continue;
        };
        const at = for (arguments.items, 0..) |known, position| {
            if (std.mem.eql(u8, known, argument)) break position;
        } else blk: {
            try arguments.append(a, argument);
            try parts.append(a, .empty);
            break :blk arguments.items.len - 1;
        };
        try parts.items[at].append(a, try std.fmt.allocPrint(a, "{s}{s}", .{ optimize_shadow.function_prefix, key }));
    }
    const reads = try a.alloc(kind.Read, arguments.items.len);
    for (reads, arguments.items, parts.items) |*read, argument, names| {
        std.mem.sort([]const u8, names.items, {}, partBefore);
        read.* = .{ .argument = argument, .parts = names.items };
    }
    return reads;
}

/// Describe the units of an emission. `owner` maps the key of a function to the `unit-optimize` argument that holds its `opt:` part.
pub fn compute(a: std.mem.Allocator, units: []const emit_units.Unit, keys: []const ?[]const u8, owner: *const std.StringHashMapUnmanaged([]const u8), mode: []const u8) std.mem.Allocator.Error!Described {
    var out: std.ArrayList(Unit) = .empty;
    var unowned: u32 = 0;
    for (units) |unit| {
        const identity = unit.identity orelse continue;
        const name = try nameOf(a, unit, identity, keys);
        try out.append(a, .{
            .argument = try kind.argumentOf(a, name, mode, identity.input),
            .answer = .{ .payload = try kind.payloadOf(a, identity.text), .optimized = try readsOf(a, identity, keys, owner, &unowned) },
        });
    }
    return .{ .units = out.items, .unowned = unowned };
}

test "a unit's emission reads the optimizer parts of its functions, grouped by the optimizer unit that holds each" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var owner: std.StringHashMapUnmanaged([]const u8) = .empty;
    try owner.put(a, "m.f", "unit-1");
    try owner.put(a, "m.g", "unit-1");
    try owner.put(a, "n.h", "unit-2");
    const keys = [_]?[]const u8{ "m.g", null, "n.h", "m.f", "x.lost" };
    const unit: emit_units.Unit = .{
        .name = "module-abc",
        .source_path = "m.selka",
        .kind = .module,
        .llvm = "",
        .dependencies = .{},
        .identity = .{ .input = @splat(1), .text = @splat(2), .functions = &.{ 0, 1, 2, 3, 4 } },
    };
    const described = try compute(a, &.{unit}, &keys, &owner, "debug");
    try std.testing.expectEqual(@as(usize, 1), described.units.len);
    try std.testing.expectEqual(@as(u32, 1), described.unowned);
    try std.testing.expectEqualStrings("module:m.selka\x00emit=debug\x00in=01010101010101010101010101010101", described.units[0].argument);
    const reads = described.units[0].answer.optimized;
    try std.testing.expectEqual(@as(usize, 2), reads.len);
    try std.testing.expectEqualStrings("unit-1", reads[0].argument);
    try std.testing.expectEqualStrings("opt:m.f", reads[0].parts[0]);
    try std.testing.expectEqualStrings("opt:m.g", reads[0].parts[1]);
    try std.testing.expectEqualStrings("opt:n.h", reads[1].parts[0]);
}

test "a unit that no receipt keyed is not described" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var owner: std.StringHashMapUnmanaged([]const u8) = .empty;
    const unit: emit_units.Unit = .{ .name = "entry", .source_path = "m.selka", .kind = .entry, .llvm = "", .dependencies = .{} };
    const described = try compute(a, &.{unit}, &.{}, &owner, "debug");
    try std.testing.expectEqual(@as(usize, 0), described.units.len);
}

//! What the optimizer made, grouped into the units the `unit-optimize` kind describes (part 2, G3e; spec §17.2).
//!
//! `compute` takes the lowering shadow's units (which function belongs to which, by name), what the optimizer observed (the final
//! digest of every internal function, what it calls, what was inlined into it) and the facts it joined, and describes each unit as
//! the kind answers it. A function lowering made besides the checked ones (an adapter, a thunk, a helper) belongs to the unit of the
//! function that made it; one no unit claims belongs to no unit and is counted, never silently dropped.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const kind = @import("engine/kinds/unit_optimize.zig");
const optimizer_shadow = @import("optimizer_shadow.zig");
const lowering_shadow = @import("lowering_shadow.zig");
const facts_shadow = @import("program_facts_shadow.zig");

/// The first line of every unit's payload.
pub const payload_magic = "selka-unit-optimize-v1";
/// The prefix of the part a function's final body is published under.
pub const function_prefix = "opt:";

/// One unit's optimization: the argument, the answer, and what the old optimizer did for it.
pub const Unit = struct {
    argument: []const u8,
    answer: kind.Answer,
    /// Functions of the unit the optimizer analysed afresh in this build, and the functions it restored or bypassed.
    fresh: u32,
    kept: u32,
};

/// What `compute` needs: the settings the optimizer ran under, the entry, and the parts of the program's facts, whose values a
/// unit's argument takes (G-D13): the record reads no query that names the program.
pub const Inputs = struct { mode: []const u8, entry: []const u8, facts: []const record.Part };

/// A unit being collected: its lowering unit, and the functions that belong to it.
const Collected = struct {
    lowering: usize,
    members: std.ArrayList(usize) = .empty,
};

fn partBefore(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn stringBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn addOnce(a: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) std.mem.Allocator.Error!void {
    for (list.items) |known| if (std.mem.eql(u8, known, value)) return;
    try list.append(a, value);
}

/// Describe the units of `observed`. `units` are the lowering shadow's, whose member and made names say which function is whose.
/// Returns the units and how many functions belong to none.
pub fn compute(a: std.mem.Allocator, observed: *const optimizer_shadow.Observed, units: []const lowering_shadow.Unit, inputs: Inputs) std.mem.Allocator.Error!struct { units: []const Unit, unowned: u32 } {
    var owner: std.StringHashMapUnmanaged(usize) = .empty;
    for (units, 0..) |unit, at| for (unit.names) |name| try owner.put(a, name, at);
    var groups: std.array_hash_map.Auto(usize, Collected) = .empty;
    var unowned: u32 = 0;
    for (observed.entries, 0..) |entry, index| {
        const at = owner.get(entry.key) orelse {
            unowned += 1;
            continue;
        };
        const slot = try groups.getOrPut(a, at);
        if (!slot.found_existing) slot.value_ptr.* = .{ .lowering = at };
        try slot.value_ptr.members.append(a, index);
    }
    var out: std.ArrayList(Unit) = .empty;
    var each = groups.iterator();
    while (each.next()) |group| try out.append(a, try describe(a, observed, units, &owner, group.value_ptr.*, inputs));
    return .{ .units = out.items, .unowned = unowned };
}

/// The digest of what the program supplies to a unit's optimization: the lowered units its record reads (their arguments) and the
/// value of each fact part it reads. Both lists are sorted. A fact the program does not hold digests as absent, so a program that
/// lacks it and one that holds it differ.
fn suppliedBy(held: []const record.Part, lowered: []const []const u8, wanted: []const []const u8) [32]u8 {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("unit-optimize-supplied-v1\x00");
    for (lowered) |unit| {
        hash.update(unit);
        hash.update("\x00");
    }
    hash.update("\x01");
    for (wanted) |name| {
        hash.update(name);
        hash.update("\x00");
        const found = for (held) |part| {
            if (std.mem.eql(u8, part.name, name)) break part.digest;
        } else null;
        if (found) |digest| hash.update(&digest) else hash.update("\xff");
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn describe(a: std.mem.Allocator, observed: *const optimizer_shadow.Observed, units: []const lowering_shadow.Unit, owner: *const std.StringHashMapUnmanaged(usize), group: Collected, inputs: Inputs) std.mem.Allocator.Error!Unit {
    const own = units[group.lowering];
    var parts: std.ArrayList(record.Part) = .empty;
    var payload: std.ArrayList(u8) = .empty;
    var lowered: std.ArrayList([]const u8) = .empty;
    var facts: std.ArrayList([]const u8) = .empty;
    var fresh: u32 = 0;
    try payload.print(a, "{s}\n", .{payload_magic});
    try addOnce(a, &lowered, own.argument);
    for ([_][]const u8{ "closed", "fields", "helpers" }) |name| try addOnce(a, &facts, name);
    for (group.members.items) |index| {
        const entry = observed.entries[index];
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ function_prefix, entry.key });
        try parts.append(a, .{ .name = name, .digest = entry.body });
        try payload.print(a, "{s} {s}\n", .{ name, digest_rules.hex(entry.body)[0..16] });
        fresh += @intFromBool(entry.fresh);
        if (std.mem.eql(u8, entry.key, inputs.entry)) try addOnce(a, &facts, "entry");
        for ([_][]const u8{ facts_shadow.params_prefix, facts_shadow.returns_prefix, facts_shadow.effects_prefix }) |prefix| {
            try addOnce(a, &facts, try std.fmt.allocPrint(a, "{s}{s}", .{ prefix, entry.key }));
        }
        for (entry.callees) |callee| {
            try addOnce(a, &facts, try std.fmt.allocPrint(a, "{s}{s}", .{ facts_shadow.returns_prefix, callee }));
            try addOnce(a, &facts, try std.fmt.allocPrint(a, "{s}{s}", .{ facts_shadow.effects_prefix, callee }));
        }
        for (entry.contributors) |contributor| if (owner.get(contributor)) |at| try addOnce(a, &lowered, units[at].argument);
    }
    std.mem.sort(record.Part, parts.items, {}, partBefore);
    std.mem.sort([]const u8, lowered.items, {}, stringBefore);
    std.mem.sort([]const u8, facts.items, {}, stringBefore);
    const argument = try kind.argumentOf(a, own.argument, inputs.mode, suppliedBy(inputs.facts, lowered.items, facts.items));
    return .{
        .argument = argument,
        .answer = .{ .payload = payload.items, .parts = parts.items, .lowered = lowered.items },
        .fresh = fresh,
        .kept = @as(u32, @intCast(group.members.items.len)) - fresh,
    };
}

test "what the program supplies is a digest of the units read and the fact values read, so programs that agree share an argument and programs that do not, do not" {
    const held: []const record.Part = &.{ .{ .name = "closed", .digest = @splat(1) }, .{ .name = "params:f", .digest = @splat(2) } };
    const changed: []const record.Part = &.{ .{ .name = "closed", .digest = @splat(1) }, .{ .name = "params:f", .digest = @splat(3) } };
    const units: []const []const u8 = &.{"module\x00a.selka\x00debug=1\x00demand=00"};
    const names: []const []const u8 = &.{ "closed", "params:f" };
    const same = suppliedBy(held, units, names);
    try std.testing.expectEqual(same, suppliedBy(held, units, names));
    try std.testing.expect(!std.mem.eql(u8, &same, &suppliedBy(changed, units, names)));
    try std.testing.expect(!std.mem.eql(u8, &same, &suppliedBy(held, &.{"module\x00a.selka\x00debug=1\x00demand=01"}, names)));
    try std.testing.expect(!std.mem.eql(u8, &same, &suppliedBy(held, units, &.{ "closed", "params:g" })));
}

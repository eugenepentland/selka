//! MODULE-SYMBOL-CUTOFF-1..3: what one module compile consumed of each
//! imported interface's emission section, by symbol, so a body edit that
//! changes an import's emission hash recompiles only the dependents that
//! read what changed.
//!
//! A module compile restores every imported interface's physical archive
//! (`module_physical_inputs.restore`) and runs its RC analyses over the whole
//! restored program. Those analyses are call-graph local: what a unit, an
//! emission fact or a runtime-data block of the module reads about a
//! function comes from that function's body, facts and signature and,
//! transitively, from its callees'. So the compile's output is a function of
//!
//! - the functions its emitted units reach through the physical references
//!   every body spells (calls, function values, inline origins), starting
//!   from its emitted functions, every record's codec and every invariant
//!   callback (`reach`);
//! - for each import, its rows for those functions (emission facts, physical
//!   body, signature-only dependency), every record row it restores, its
//!   invariant callbacks, the modules its dependency rows send the restore to,
//!   and its emission configuration (`digest`).
//!
//! A dependent whose units report positions inside an import's text (an
//! inlined or instantiated body) reads only the stretches of that text those
//! positions fall in (`stretchDigest`), unless it renders a diagnostic.
//!
//! A reached body that invokes a function value may reach any function taken
//! as a value anywhere, so such a compile records no reach at all and any
//! change of an import's emission hash recompiles it, as before.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const iface = @import("module_interface.zig");
const physical = @import("module_physical.zig");
const invariant_callbacks = @import("invariant_callbacks.zig");

/// Version of the reach and digest rules; part of every digest.
pub const version = "module-symbols-v1";

/// The sorted, unique names of every function the output of a compile over
/// the restored program `code`, emitting `emit`, can depend on; null when one
/// of them invokes a function value (or names a function outside `code`),
/// when the compile consumed every row of every import.
pub fn reach(a: std.mem.Allocator, code: bytecode.Program, emit: []const bool) std.mem.Allocator.Error!?[]const []const u8 {
    const names: physical.Names = .{ .functions = code.functions, .records = code.records };
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    for (code.functions, 0..) |function, at| {
        // A name two functions share cannot say which one was reached.
        const slot = try index.getOrPut(a, function.name);
        if (slot.found_existing) return null;
        slot.value_ptr.* = at;
    }
    const seen = try a.alloc(bool, code.functions.len);
    @memset(seen, false);
    var pending: std.ArrayList(usize) = .empty;
    for (code.functions, 0..) |function, at| {
        const root = (at < emit.len and emit[at]) or invariant_callbacks.isName(function.name);
        if (!root) continue;
        seen[at] = true;
        try pending.append(a, at);
    }
    for (code.records) |record| {
        for (try physical.references(a, names, @TypeOf(record), record)) |name| if (!try visit(a, &index, seen, &pending, name)) return null;
    }
    while (pending.pop()) |at| {
        const function = code.functions[at];
        for (function.scope.instructions) |instruction| if (instruction.op == .invoke) return null;
        for (try physical.references(a, names, bytecode.Function, function)) |name| if (!try visit(a, &index, seen, &pending, name)) return null;
    }
    var out: std.ArrayList([]const u8) = .empty;
    for (code.functions, seen) |function, reached| if (reached) try out.append(a, function.name);
    std.mem.sort([]const u8, out.items, {}, lessText);
    return unique(out.items);
}

/// Queue the function `name` names; false when it names none.
fn visit(a: std.mem.Allocator, index: *const std.StringHashMapUnmanaged(usize), seen: []bool, pending: *std.ArrayList(usize), name: []const u8) std.mem.Allocator.Error!bool {
    const at = index.get(name) orelse return false;
    if (seen[at]) return true;
    seen[at] = true;
    try pending.append(a, at);
    return true;
}

/// The rows of one interface's emission section, by function name.
pub const Table = struct {
    interface: iface.Interface,
    facts: std.StringHashMapUnmanaged(iface.EmittedFunction) = .empty,
    bodies: std.StringHashMapUnmanaged([]const u8) = .empty,
    signatures: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Every invariant callback any of its rows names, sorted and unique.
    invariants: []const []const u8 = &.{},

    /// Index `interface`'s rows; storage comes from `a`, an arena.
    pub fn of(a: std.mem.Allocator, interface: iface.Interface) std.mem.Allocator.Error!Table {
        var out: Table = .{ .interface = interface };
        var invariants: std.ArrayList([]const u8) = .empty;
        for (interface.emission.functions) |function| {
            try out.facts.put(a, function.name, function);
            if (invariant_callbacks.isName(function.name)) try invariants.append(a, function.name);
        }
        const physical_rows = interface.emission.physical;
        for ([_][]const physical.Data{ physical_rows.functions, physical_rows.dependencies }, [_]*std.StringHashMapUnmanaged([]const u8){ &out.bodies, &out.signatures }) |rows, map| {
            for (rows) |row| {
                try map.put(a, row.name, row.bytes);
                if (invariant_callbacks.isName(row.name)) try invariants.append(a, row.name);
            }
        }
        std.mem.sort([]const u8, invariants.items, {}, lessText);
        out.invariants = unique(invariants.items);
        return out;
    }

    /// The digest of everything a compile that reached `reached` (sorted,
    /// unique) consumed of this interface's emission section.
    pub fn digest(self: *const Table, a: std.mem.Allocator, reached: []const []const u8) std.mem.Allocator.Error![32]u8 {
        const interface = self.interface;
        var hash = std.crypto.hash.Blake3.init(.{});
        frame(&hash, version);
        frame(&hash, interface.module);
        frame(&hash, interface.emission.config);
        hash.update(&.{@intFromBool(iface.physicalInputs(interface))});
        const archive = interface.emission.physical;
        count(&hash, archive.records.len);
        for (archive.records) |row| {
            frame(&hash, row.name);
            frame(&hash, row.bytes);
        }
        var modules: std.ArrayList([]const u8) = .empty;
        for (archive.dependencies) |row| {
            const split = std.mem.indexOf(u8, row.name, "::") orelse continue;
            try modules.append(a, row.name[0..split]);
        }
        std.mem.sort([]const u8, modules.items, {}, lessText);
        const named = unique(modules.items);
        count(&hash, named.len);
        for (named) |module| frame(&hash, module);
        const joined = try a.alloc([]const u8, reached.len + self.invariants.len);
        @memcpy(joined[0..reached.len], reached);
        @memcpy(joined[reached.len..], self.invariants);
        std.mem.sort([]const u8, joined, {}, lessText);
        const names = unique(joined);
        count(&hash, names.len);
        for (names) |name| {
            frame(&hash, name);
            if (self.facts.get(name)) |fact| {
                hash.update(&.{ 1, @intFromBool(fact.allocates) });
                flags(&hash, fact.writes);
                flags(&hash, fact.stable);
                hash.update(&fact.physical);
            } else hash.update(&.{0});
            for ([_]?[]const u8{ self.bodies.get(name), self.signatures.get(name) }) |row| {
                if (row) |bytes| {
                    hash.update(&.{1});
                    frame(&hash, bytes);
                } else hash.update(&.{0});
            }
        }
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }
};

/// MODULE-SYMBOL-CUTOFF-5: the digest of what the positions a compile's units
/// took from `interface`'s text through the stretches `indices` read of its
/// positions section: where each stretch up to the last of them lies in the
/// text (which decides the stretch a position falls in), and the source line
/// and column each of those
/// starts at and the text it spans, its blanked gap included. A stretch's
/// byte offset in the source is not read. An index past the last stretch
/// stands for a position no stretch held: every stretch then decides.
pub fn stretchDigest(interface: iface.Interface, indices: []const u32) [32]u8 {
    const origins = interface.positions.origins;
    var hash = std.crypto.hash.Blake3.init(.{});
    frame(&hash, "module-stretches-v1");
    // A position is reported through the first stretch that holds it, so
    // the stretches up to the last one read decide which one that is.
    var last: usize = 0;
    for (indices) |index| last = @max(last, @as(usize, index) + 1);
    const deciding = origins[0..@min(last, origins.len)];
    count(&hash, deciding.len);
    for (deciding) |origin| {
        count(&hash, origin.text);
        count(&hash, @as(usize, origin.len) + origin.gap);
    }
    count(&hash, indices.len);
    for (indices) |index| {
        count(&hash, index);
        if (index >= origins.len) {
            hash.update("missing");
            continue;
        }
        const origin = origins[index];
        count(&hash, origin.line);
        count(&hash, origin.column);
        // The bytes a position's line and column are counted over, the
        // blanked gap's newlines included (the interface hash skips gaps).
        const start = @min(@as(usize, origin.text), interface.text.len);
        frame(&hash, interface.text[start..@min(start + origin.len + origin.gap, interface.text.len)]);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// Drop adjacent repeats from a sorted list, in place.
fn unique(sorted: [][]const u8) []const []const u8 {
    if (sorted.len == 0) return sorted;
    var kept: usize = 1;
    for (sorted[1..]) |name| {
        if (std.mem.eql(u8, name, sorted[kept - 1])) continue;
        sorted[kept] = name;
        kept += 1;
    }
    return sorted[0..kept];
}

fn flags(hash: *std.crypto.hash.Blake3, values: []const bool) void {
    count(hash, values.len);
    for (values) |flag| hash.update(&.{@intFromBool(flag)});
}

fn frame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    count(hash, bytes.len);
    hash.update(bytes);
}

fn count(hash: *std.crypto.hash.Blake3, value: usize) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}

fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

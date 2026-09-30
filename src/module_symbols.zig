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
pub const version = "module-symbols-v2";

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

/// MODULE-SYMBOL-CUTOFF-1: what a compile's output can depend on of its
/// imports' physical rows: the functions it reaches (`reach`) and, since a
/// record row whose name its own catalog already holds adds nothing, the
/// sorted names of every record its check's catalog holds.
pub const Reach = struct { functions: []const []const u8, catalog: []const []const u8 };

/// The sorted, unique names of every record of a catalog.
pub fn catalogNames(a: std.mem.Allocator, records: []const @import("typed.zig").Record) std.mem.Allocator.Error![]const []const u8 {
    const names = try a.alloc([]const u8, records.len);
    for (records, names) |record, *name| name.* = record.name;
    std.mem.sort([]const u8, names, {}, lessText);
    return unique(names);
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

    /// The digest of everything a compile with reach `consumed` consumed of this
    /// interface's emission section.
    pub fn digest(self: *const Table, a: std.mem.Allocator, consumed: Reach) std.mem.Allocator.Error![32]u8 {
        const reached = consumed.functions;
        const interface = self.interface;
        var hash = std.crypto.hash.Blake3.init(.{});
        frame(&hash, version);
        frame(&hash, interface.module);
        frame(&hash, interface.emission.config);
        hash.update(&.{@intFromBool(iface.physicalInputs(interface))});
        const archive = interface.emission.physical;
        // Only a record the compile's catalog lacks is restored into it.
        for (archive.records) |row| {
            if (contains(consumed.catalog, row.name)) continue;
            frame(&hash, row.name);
            frame(&hash, row.bytes);
        }
        hash.update("records-end");
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

/// MODULE-INTERFACE-CUTOFF-1: the digest of everything a reader's lookups
/// into `interface` can find or miss, and of the types it knows from it: the
/// imports its text names, every domain member and every function whose body
/// the text keeps by stable key with whether it is exported, and the
/// fingerprint of each kept body (every reader checks that body, and its
/// record catalog takes in the types it instantiates), every re-exported name
/// with its target's fingerprint, every type declaration with its
/// fingerprint, and every record shape its declarations reach. A member or
/// kept function added, removed, renamed or made public or private, a
/// re-export changed, a kept body edited, or a type changed in any way
/// changes it; a free function whose body is `pass` changes it only through
/// the record shapes its signature reaches.
// twin-drift-ok: an outline is what lookups see (names, kept bodies, types), not the whole interface hash
pub fn outlineDigest(interface: iface.Interface) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    frame(&hash, "module-outline-v1");
    frame(&hash, interface.module);
    count(&hash, interface.imports.len);
    for (interface.imports) |name| frame(&hash, name);
    const declarations = interface.declarations;
    for (declarations.functions) |function| {
        // A body the text keeps is checked, and lowered, by every reader,
        // whose record catalog takes in whatever types it instantiates.
        const kept = function.role.keepsBody() and function.role != .foreign;
        // A free function whose body is `pass` is found only by a lookup
        // that spells it qualified (there is no `from` import): a reader that
        // never used it could not have looked it up and succeeded, and its
        // signature's records are among the shapes below.
        if (!kept and ownerOf(function.key).len == 0) continue;
        frame(&hash, function.key);
        hash.update(&.{ @intFromBool(function.exported), @intFromBool(kept) });
        if (kept) hash.update(&function.fingerprint);
    }
    hash.update("functions-end");
    inline for (.{ declarations.reexports, declarations.types }) |list| {
        count(&hash, list.len);
        for (list) |entry| {
            frame(&hash, entry.name);
            hash.update(&entry.fingerprint);
        }
    }
    count(&hash, declarations.shapes.len);
    for (declarations.shapes) |shape| {
        frame(&hash, shape.name);
        hash.update(&shape.digest);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// MODULE-INTERFACE-CUTOFF-1: the stable key (`fn\x1f<module>\x1f<owner>\x1f<name>`) of the declaration
/// a checked function name (`module::name`, `module::Owner.name`, either with
/// a specialization's `[...]`) comes from.
pub fn stableKey(allocator: std.mem.Allocator, name: []const u8) error{ OutOfMemory, Unnamed }![]const u8 {
    const split = std.mem.indexOf(u8, name, "::") orelse return error.Unnamed;
    const module = name[0..split];
    var rest = name[split + 2 ..];
    if (std.mem.indexOfScalar(u8, rest, '[')) |open| rest = rest[0..open];
    if (module.len == 0 or rest.len == 0) return error.Unnamed;
    if (std.mem.indexOfAny(u8, module, ":@ ") != null or std.mem.indexOfAny(u8, rest, ":@ ") != null) return error.Unnamed;
    const dot = std.mem.indexOfScalar(u8, rest, '.');
    const owner = if (dot) |at| rest[0..at] else "";
    const local = if (dot) |at| rest[at + 1 ..] else rest;
    if (local.len == 0 or std.mem.indexOfScalar(u8, local, '.') != null) return error.Unnamed;
    return std.fmt.allocPrint(allocator, "fn\x1f{s}\x1f{s}\x1f{s}", .{ module, owner, local });
}

/// MODULE-INTERFACE-CUTOFF-1: the fingerprint `interface` states for the
/// declaration a use identity names (`f` and a function's stable key, `t`
/// and a type's name), or null when it declares none such.
pub fn usedFingerprint(interface: iface.Interface, identity: []const u8) ?[32]u8 {
    if (identity.len < 2 or identity[1] != 0x1f) return null;
    const name = identity[2..];
    switch (identity[0]) {
        'f' => for (interface.declarations.functions) |function| if (std.mem.eql(u8, function.key, name)) return function.fingerprint,
        't' => for (interface.declarations.types) |ty| if (std.mem.eql(u8, ty.name, name)) return ty.fingerprint,
        else => {},
    }
    return null;
}

/// MODULE-INTERFACE-CUTOFF-1: the digest of the fingerprints `interface`
/// states for the declarations `used` names (sorted), each or its absence.
pub fn usesDigest(interface: iface.Interface, used: []const []const u8) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    frame(&hash, "module-uses-v1");
    count(&hash, used.len);
    for (used) |identity| {
        frame(&hash, identity);
        if (usedFingerprint(interface, identity)) |fingerprint| hash.update(&fingerprint) else hash.update("missing");
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// The domain owner a stable function key names, empty for a free function.
fn ownerOf(key: []const u8) []const u8 {
    var parts = std.mem.splitScalar(u8, key, 0x1f);
    _ = parts.next();
    _ = parts.next();
    return parts.next() orelse "";
}

/// Whether sorted `names` holds `name`.
fn contains(names: []const []const u8, name: []const u8) bool {
    var low: usize = 0;
    var high = names.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        switch (std.mem.order(u8, names[mid], name)) {
            .eq => return true,
            .lt => low = mid + 1,
            .gt => high = mid,
        }
    }
    return false;
}

/// Drop adjacent repeats from a sorted list of names, in place.
pub fn uniqueNames(sorted: [][]const u8) []const []const u8 {
    return unique(sorted);
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

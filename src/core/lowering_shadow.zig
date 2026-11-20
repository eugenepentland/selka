//! What lowering did, grouped into the units the `unit-lower` kind describes (part 2, G3c; spec §17.2): for each module and each
//! generic instance, the functions lowered or restored with the digest of each artifact in canonical form, and the reads a
//! lowering of the unit from the front end's results would make.
//!
//! This file only computes the answers; the shadow (`frontend_shadow.zig`) hands them to the engine through the kind's data and
//! compares what the engine serves with them. The inputs are what the build has when lowering has finished: the checked program
//! and its merged source, the loaded project (which names the modules and cuts their texts into parts), and the build's record of
//! each function it lowered or restored (`lowering_cache.Observed`).
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const language = @import("selka");
const typed = language.typed;
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const unit_kind = @import("engine/kinds/unit_lower.zig");
const interface_kind = @import("engine/kinds/module_interface.zig");
const lowering_cache = @import("lowering_cache.zig");
const module_parts = @import("module_parts.zig");
const demand_sources = @import("demand_sources.zig");

/// The first line of every unit's payload.
pub const payload_magic = "selka-unit-lower-v1";
/// The prefix of the part a function is published under.
pub const function_prefix = "fn:";

/// One module of the loaded project: where its text is, the `module-check` argument that names it, and how its text is cut.
pub const Module = struct {
    /// The module's name, which prefixes the checked name of every function it declares (`model::answer`).
    name: []const u8,
    path: []const u8,
    key_path: []const u8,
    check: []const u8,
    regions: []const module_parts.Region,
};

/// What a build knows once it has lowered its program.
pub const Input = struct {
    program: typed.Program,
    src: language.source.Source,
    modules: []const Module,
    observed: []const lowering_cache.Observed.Entry,
    drop_debug: bool,
};

/// One unit: the argument it is queried under, the answer the kind returns, and what the old cache did for it.
pub const Unit = struct {
    argument: []const u8,
    answer: unit_kind.Answer,
    /// The functions of the unit lowering restored from the old cache, and those it lowered again.
    restored: u32,
    lowered: u32,
    /// The names, as the module spells them, of the unit's functions and of the functions its lowering made.
    names: []const []const u8,
};

/// A function of a unit, before the unit is cut into parts: its checked name, the name of its `module-check` part (null when
/// the checked name does not say it), and its artifact.
const Member = struct { name: []const u8, raw: []const u8, body: ?[]const u8, artifact: [32]u8, reused: bool };

/// A unit being collected: its members, the module whose text it lowers, the proofs of the files its positions point into, and
/// what it reads of the other modules.
const Collected = struct {
    argument: []const u8,
    owner: usize,
    members: std.ArrayList(Member) = .empty,
    proofs: std.ArrayList(demand_sources.Proof) = .empty,
    made: std.ArrayList([]const u8) = .empty,
    /// Per other module, how many of its regions (parts of its text, in source order) the unit's positions reach into.
    texts: std.StringHashMapUnmanaged(usize) = .empty,
    lookups: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty,
};

/// The module of the merged program whose text holds merged offset `start`, as an index into `Input.modules`.
fn moduleAt(src: language.source.Source, start: usize) ?usize {
    if (src.origins.len == 0) return null;
    const at = src.originalSpan(.{ .start = start, .end = start }) catch return null;
    return at.input;
}

/// The name of the `module-check` part of the body that checked function `name` of `module` was checked from: the checked name
/// without the module's prefix and, for an instance, without its type arguments (the part is the template's). Null when the
/// name does not start with the module's prefix.
fn bodyPart(a: std.mem.Allocator, module: Module, name: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (!std.mem.startsWith(u8, name, module.name) or !std.mem.startsWith(u8, name[module.name.len..], "::")) return null;
    const rest = name[module.name.len + 2 ..];
    const part = try std.fmt.allocPrint(a, "body:{s}", .{rest[0 .. std.mem.indexOfScalar(u8, rest, '[') orelse rest.len]});
    return part;
}

/// The base name of a record: its checked name without the type arguments of a specialization (`Box<i64>` is `Box`).
fn baseName(name: []const u8) []const u8 {
    return name[0 .. std.mem.indexOfScalar(u8, name, '<') orelse name.len];
}

/// The name under which `module`'s interface binds the record called `name`: its checked name without the module's prefix
/// (`mod_a::Big` is `Big`), the type arguments of a specialization (`Box<i64>` is `Box`) and the case a payload record belongs to
/// (`Value.big`, the record of a parenthesized case, is `Value`). An interface part is named by the bound name alone, so a lookup
/// of the qualified checked name reads a part nothing publishes: it reads as absent whatever the declaration holds.
fn interfaceName(module: Module, name: []const u8) []const u8 {
    const prefixed = std.mem.startsWith(u8, name, module.name) and std.mem.startsWith(u8, name[module.name.len..], "::");
    const unqualified = baseName(if (prefixed) name[module.name.len + 2 ..] else name);
    return unqualified[0 .. std.mem.indexOfScalar(u8, unqualified, '.') orelse unqualified.len];
}

/// Add `name` to the names unit `collected` reads of module `path`'s interface.
fn lookup(a: std.mem.Allocator, collected: *Collected, path: []const u8, name: []const u8) std.mem.Allocator.Error!void {
    const slot = try collected.lookups.getOrPut(a, path);
    if (!slot.found_existing) {
        slot.key_ptr.* = try a.dupe(u8, path);
        slot.value_ptr.* = .empty;
    }
    for (slot.value_ptr.items) |known| if (std.mem.eql(u8, known, name)) return;
    try slot.value_ptr.append(a, try a.dupe(u8, name));
}

/// Note the interface names the type arguments of generic instance `function` reach: no body of the instantiating module
/// necessarily names them, and the instance's lowering depends on their layout.
fn noteArguments(a: std.mem.Allocator, input: Input, function: typed.Function, collected: *Collected) std.mem.Allocator.Error!void {
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    var records: std.ArrayList(usize) = .empty;
    for (function.type_arguments) |argument| lowering_cache.reachRecordsOf(a, input.program, argument, &seen, &records) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // The walk reads declarations only; a snapshot it cannot read names no record, so the unit notes fewer names.
        error.InvalidSnapshot => return,
    };
    for (records.items) |index| {
        const declared = input.program.records[index];
        // A builtin record (`bytes`, `float`, a list) is declared nowhere: its span is empty and no interface binds it.
        if (declared.declaration.start == declared.declaration.end) continue;
        const module = moduleAt(input.src, declared.declaration.start) orelse continue;
        if (module >= input.modules.len) continue;
        try lookup(a, collected, input.modules[module].path, try std.fmt.allocPrint(a, "name:{s}", .{interfaceName(input.modules[module], declared.name)}));
    }
}

/// Note how far into other modules' text the positions behind `collected.proofs` reach: the parts that begin before the
/// proof's last line, which are the first of the module's regions. A position in the unit's own module is covered by the
/// module's check.
fn noteTexts(a: std.mem.Allocator, input: Input, collected: *Collected) std.mem.Allocator.Error!void {
    for (collected.proofs.items) |proof| {
        for (input.modules, 0..) |module, at| {
            if (!std.mem.eql(u8, module.key_path, proof.path)) continue;
            if (at == collected.owner) break;
            var reached: usize = 0;
            for (module.regions) |region| reached += @intFromBool(region.begin < proof.length);
            const slot = try collected.texts.getOrPut(a, module.path);
            if (!slot.found_existing or slot.value_ptr.* < reached) slot.value_ptr.* = reached;
            break;
        }
    }
}

fn partBefore(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn memberBefore(_: void, left: Member, right: Member) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn stringBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Group what the build lowered into units and describe each one. Everything is allocated in `a`, which should be an arena.
/// A unit with a function the build lowered or restored without an artifact to describe is left out by the caller counting
/// the entries it did not receive; here every entry describes an artifact.
pub fn compute(a: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]const Unit {
    var units: std.StringHashMapUnmanaged(*Collected) = .empty;
    var order: std.ArrayList(*Collected) = .empty;
    for (input.observed) |entry| {
        const index: usize = @backingInt(entry.id);
        if (index >= input.program.functions.len) continue;
        const function = input.program.functions[index];
        const module = moduleAt(input.src, function.declaration.start) orelse continue;
        if (module >= input.modules.len) continue;
        const instance = function.type_arguments.len != 0;
        const argument = if (instance)
            try unit_kind.instanceArgument(a, function.name, input.drop_debug)
        else
            try unit_kind.moduleArgument(a, input.modules[module].path, input.drop_debug);
        const slot = try units.getOrPut(a, argument);
        if (!slot.found_existing) {
            const made = try a.create(Collected);
            made.* = .{ .argument = argument, .owner = module };
            slot.value_ptr.* = made;
            try order.append(a, made);
            if (instance) try noteArguments(a, input, function, made);
        }
        const collected = slot.value_ptr.*;
        const body = try bodyPart(a, input.modules[module], function.name);
        try collected.members.append(a, .{ .name = lowering_cache.normalizedName(function.name), .raw = function.name, .body = body, .artifact = entry.artifact, .reused = entry.reused });
        try collected.proofs.appendSlice(a, entry.sources);
        try collected.made.appendSlice(a, entry.made);
    }
    const out = try a.alloc(Unit, order.items.len);
    for (order.items, out) |collected, *unit| {
        try noteTexts(a, input, collected);
        unit.* = try cut(a, input, collected);
    }
    return out;
}

/// The answer for one collected unit.
fn cut(a: std.mem.Allocator, input: Input, collected: *Collected) std.mem.Allocator.Error!Unit {
    std.mem.sort(Member, collected.members.items, {}, memberBefore);
    var parts: std.ArrayList(record.Part) = .empty;
    var payload: std.ArrayList(u8) = .empty;
    var restored: u32 = 0;
    var lowered: u32 = 0;
    try payload.print(a, "{s}\n", .{payload_magic});
    var repeat: usize = 0;
    for (collected.members.items, 0..) |member, at| {
        // A name another function of the unit shares (two instances of one template are separate units, but a module can hold
        // two functions of one normalized name) gets an ordinal, so the parts are distinct.
        repeat = if (at != 0 and std.mem.eql(u8, collected.members.items[at - 1].name, member.name)) repeat + 1 else 0;
        const name = if (repeat == 0)
            try std.fmt.allocPrint(a, "{s}{s}", .{ function_prefix, member.name })
        else
            try std.fmt.allocPrint(a, "{s}{s}#{d}", .{ function_prefix, member.name, repeat + 1 });
        try parts.append(a, .{ .name = name, .digest = member.artifact });
        try payload.print(a, "{s} {s}\n", .{ name, digest_rules.hex(member.artifact)[0..16] });
        if (member.reused) restored += 1 else lowered += 1;
    }
    std.mem.sort(record.Part, parts.items, {}, partBefore);
    // Dropping a duplicate part name would hide a function: the ordinals above keep them distinct, so there is none.
    var lookups: std.ArrayList(interface_kind.Lookup) = .empty;
    var names = collected.lookups.iterator();
    while (names.next()) |found| {
        std.mem.sort([]const u8, found.value_ptr.items, {}, stringBefore);
        try lookups.append(a, .{ .path = found.key_ptr.*, .names = found.value_ptr.items });
    }
    std.mem.sort(interface_kind.Lookup, lookups.items, {}, lookupBefore);
    var texts: std.ArrayList(unit_kind.Text) = .empty;
    var reads = collected.texts.iterator();
    while (reads.next()) |found| {
        const module = for (input.modules) |known| {
            if (std.mem.eql(u8, known.path, found.key_ptr.*)) break known;
        } else continue;
        var wanted: std.ArrayList([]const u8) = .empty;
        for (module.regions[0..@min(found.value_ptr.*, module.regions.len)]) |region| try wanted.append(a, region.name);
        try texts.append(a, .{ .path = try a.dupe(u8, module.path), .parts = wanted.items });
    }
    std.mem.sort(unit_kind.Text, texts.items, {}, textBefore);
    const checks = try a.dupe(unit_kind.Check, &.{.{ .argument = input.modules[collected.owner].check, .bodies = try bodiesOf(a, collected) }});
    var owned: std.ArrayList([]const u8) = .empty;
    // The names outlive the build's checked program and the lowering cache's notes (the optimizer's shadow reads them after
    // both are gone), so the unit owns its own copies.
    for (collected.members.items) |member| try owned.append(a, try a.dupe(u8, member.raw));
    for (collected.made.items) |made| try owned.append(a, try a.dupe(u8, made));
    return .{
        .argument = try unit_kind.withDemand(a, collected.argument, try demandOf(a, collected)),
        .answer = .{ .payload = payload.items, .parts = parts.items, .checks = checks, .lookups = lookups.items, .texts = texts.items },
        .restored = restored,
        .lowered = lowered,
        .names = owned.items,
    };
}

/// The digest of what the program demands of the unit: the checked names of the functions it lowers, in sorted order (G-D13).
/// Two programs that lower the same functions of a shared module have the same demand, whatever else they hold.
fn demandOf(a: std.mem.Allocator, collected: *const Collected) std.mem.Allocator.Error![32]u8 {
    const named = try a.alloc([]const u8, collected.members.items.len);
    for (collected.members.items, named) |member, *slot| slot.* = member.raw;
    std.mem.sort([]const u8, named, {}, stringBefore);
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("unit-lower-demand-v1\x00");
    for (named) |name| {
        hash.update(name);
        hash.update("\x00");
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// The names of the `module-check` parts the unit's functions come from, sorted and each once; null when one has no name.
fn bodiesOf(a: std.mem.Allocator, collected: *Collected) std.mem.Allocator.Error!?[]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (collected.members.items) |member| {
        const body = member.body orelse return null;
        var present = false;
        for (names.items) |known| present = present or std.mem.eql(u8, known, body);
        if (!present) try names.append(a, body);
    }
    std.mem.sort([]const u8, names.items, {}, stringBefore);
    return names.items;
}

fn lookupBefore(_: void, left: interface_kind.Lookup, right: interface_kind.Lookup) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

fn textBefore(_: void, left: unit_kind.Text, right: unit_kind.Text) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

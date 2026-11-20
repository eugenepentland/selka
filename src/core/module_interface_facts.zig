//! The interface of each module of a loaded project, as the `module-interface` kind states it (spec §17.2): for every name a
//! module binds, a digest of the declarations the name stands for and of everything they reach, and the names in other
//! modules those declarations looked up to get there.
//!
//! It is built from the front end's own declaration graph (`semantic_key.Surface`): the transitive fingerprint that dependency
//! contexts already fold is the digest of a declaration, and a name's digest is the digest of the fingerprints of the
//! declarations it binds, a facade's re-exports included. So an importer that depends on a name depends on exactly what the
//! front end's own keys depend on for it, but it reads one name of one module at a time. A name nothing binds has no part, and
//! a reader of it reads it as absent, so a module that later declares it changes the answer (the negative lookups the front end
//! keys on).
const std = @import("std");
const language = @import("selka");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const interface_kind = @import("engine/kinds/module_interface.zig");

/// The first line of the payload.
pub const payload_magic = "selka-module-interface-v1";
/// The domain string of a name's digest.
const domain = "selka-interface-name-v1";

/// The prefix of the part a name is published under.
pub const name_prefix = "name:";

/// One module's interface: the answer the kind returns for it.
pub const Interface = struct { path: []const u8, answer: interface_kind.Answer };

fn digestLess(_: void, left: [32]u8, right: [32]u8) bool {
    return std.mem.lessThan(u8, &left, &right);
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn partLess(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// A lookup in module `module` of `name`, before the module is turned into its path.
const Pending = struct { module: usize, key: []const u8 };

fn splitLookup(text: []const u8) ?Pending {
    const at = std.mem.indexOfScalar(u8, text, 0x1f) orelse return null;
    const module = std.fmt.parseInt(usize, text[0..at], 10) catch return null;
    return .{ .module = module, .key = text[at + 1 ..] };
}

/// The interface of every module of `index`'s project, in project module order, over `surface`, the declaration graph of the
/// merged program (made with `initRecording`). Everything is allocated in `a`, which should be an arena.
pub fn compute(a: std.mem.Allocator, surface: *language.semantic_key.Surface, index: *language.interfaces.Index) std.mem.Allocator.Error![]const Interface {
    const modules = index.project.modules.items;
    const out = try a.alloc(Interface, modules.len);
    for (modules, out, 0..) |module, *slot, id| slot.* = .{ .path = module.src.path, .answer = try interfaceOf(a, surface, index, id) };
    return out;
}

/// The interface of module `module`: a digest per name it binds, and the names it looks up elsewhere to get them.
pub fn interfaceOf(a: std.mem.Allocator, surface: *language.semantic_key.Surface, index: *language.interfaces.Index, module: usize) std.mem.Allocator.Error!interface_kind.Answer {
    const modules = index.project.modules.items;
    var parts: std.ArrayList(record.Part) = .empty;
    var lookups: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    var payload: std.ArrayList(u8) = .empty;
    try payload.print(a, "{s}\n{s}\n", .{ payload_magic, modules[module].src.path });
    for (try surface.declaredNames(module)) |key| {
        const bound = surface.named(module, key);
        const fingerprints = try a.alloc([32]u8, bound.len);
        for (bound, fingerprints) |declaration, *slot| {
            slot.* = try surface.fingerprint(declaration);
            try collectLookups(a, surface, module, declaration, &lookups);
        }
        std.mem.sort([32]u8, fingerprints, {}, digestLess);
        var state = std.crypto.hash.Blake3.init(.{});
        state.update(domain);
        state.update("\x00");
        state.update(key);
        for (fingerprints) |fingerprint| state.update(&fingerprint);
        var digest: [32]u8 = undefined;
        state.final(&digest);
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ name_prefix, key });
        try parts.append(a, .{ .name = name, .digest = digest });
        try payload.print(a, "{s} {s}\n", .{ key, digest_rules.hex(digest)[0..16] });
    }
    std.mem.sort(record.Part, parts.items, {}, partLess);
    const evaluated = try surface.evaluatedModules(a, module);
    const paths = try a.alloc([]const u8, evaluated.len);
    for (evaluated, paths) |id, *path| path.* = modules[id].src.path;
    std.mem.sort([]const u8, paths, {}, lessThan);
    return .{ .payload = payload.items, .parts = parts.items, .lookups = try lookupsOf(a, index, &lookups), .evaluated = paths };
}

/// Note the foreign lookups the declaration `declaration`, bound in `module`, makes. A declaration of another module that a
/// name of `module` binds (a facade's re-export) is itself a lookup, of its own name in the module that declares it.
fn collectLookups(a: std.mem.Allocator, surface: *language.semantic_key.Surface, module: usize, declaration: u64, found: *std.StringHashMapUnmanaged(std.ArrayList([]const u8))) std.mem.Allocator.Error!void {
    const declared_in = surface.moduleOfKey(declaration);
    if (declared_in != module) {
        try note(a, found, declared_in, try surface.nameOf(declaration));
        return;
    }
    for ((try surface.own(declaration)).lookups) |text| {
        const lookup = splitLookup(text) orelse continue;
        if (lookup.module != module) try note(a, found, lookup.module, lookup.key);
    }
}

/// Note that a lookup of `key` was made in module `module`, once.
pub fn note(a: std.mem.Allocator, found: *std.StringHashMapUnmanaged(std.ArrayList([]const u8)), module: usize, key: []const u8) std.mem.Allocator.Error!void {
    const text = try std.fmt.allocPrint(a, "{d}", .{module});
    const entry = try found.getOrPut(a, text);
    if (!entry.found_existing) entry.value_ptr.* = .empty;
    for (entry.value_ptr.items) |known| if (std.mem.eql(u8, known, key)) return;
    try entry.value_ptr.append(a, key);
}

/// The lookups grouped by module, one projection read each: the module's path and the names, as the parts they are published as.
pub fn lookupsOf(a: std.mem.Allocator, index: *language.interfaces.Index, found: *std.StringHashMapUnmanaged(std.ArrayList([]const u8))) std.mem.Allocator.Error![]const interface_kind.Lookup {
    const modules = index.project.modules.items;
    var out: std.ArrayList(interface_kind.Lookup) = .empty;
    var iterator = found.iterator();
    while (iterator.next()) |entry| {
        const module = std.fmt.parseInt(usize, entry.key_ptr.*, 10) catch continue;
        if (module >= modules.len) continue;
        const names = try a.alloc([]const u8, entry.value_ptr.items.len);
        for (entry.value_ptr.items, names) |key, *slot| slot.* = try std.fmt.allocPrint(a, "{s}{s}", .{ name_prefix, key });
        std.mem.sort([]const u8, names, {}, lessThan);
        try out.append(a, .{ .path = modules[module].src.path, .names = names });
    }
    std.mem.sort(interface_kind.Lookup, out.items, {}, lookupLess);
    return out.items;
}

fn lookupLess(_: void, left: interface_kind.Lookup, right: interface_kind.Lookup) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

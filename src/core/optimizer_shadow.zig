//! What the optimizer made of each function, digested for the engine's shadow (part 2, G3e; spec §17.2 `unit-optimize`).
//!
//! When the passes have run, each internal function is in its final form: analysed afresh in this build or restored from a stored
//! record, decoded or left as compact metadata. `collect` takes from every function the canonical digest of that final body
//! (`canonical_ir.Canon.plainDigest`: callees by name and signature, types by structure, no function or type position and no
//! source position, so a comment above a function moves nothing; the optimizer's own records use `functionDigest`, which covers
//! source positions), the functions the final body calls or takes by reference, and the
//! functions whose bodies were inlined into it (the inline provenance of `inline_origins.zig`, which already names the callee of
//! every clone). Functions are named by `program_facts_shadow.keysOf`, so a name means the same function in both.
const std = @import("std");
const ir = @import("ir.zig");
const optimization_cache = @import("optimization_cache.zig");
const origins = @import("inline_origins.zig");
const shortcut = @import("optimizer_shortcut.zig");
const facts_shadow = @import("program_facts_shadow.zig");
const observed = @import("optimizer_observed.zig");

pub const Digest = observed.Digest;
pub const Entry = observed.Entry;
pub const Observed = observed.Observed;

/// What `collect` needs besides the module and the cache context: the inline provenance.
pub const Inputs = struct { provenance: *const origins.Table };

/// The functions whose bodies were inlined into each function, from the provenance frames of its blocks and instructions.
fn contributorSets(a: std.mem.Allocator, table: *const origins.Table, count: usize) std.mem.Allocator.Error![]std.AutoHashMapUnmanaged(u32, void) {
    const sets = try a.alloc(std.AutoHashMapUnmanaged(u32, void), count);
    for (sets) |*set| set.* = .empty;
    var blocks = table.blocks.iterator();
    while (blocks.next()) |slot| try noteChain(a, table, sets, @intCast(slot.key_ptr.* >> 32), slot.value_ptr.*);
    var instructions = table.instructions.iterator();
    while (instructions.next()) |slot| if (slot.value_ptr.*) |frame| try noteChain(a, table, sets, @intCast(slot.key_ptr.* >> 32), frame);
    return sets;
}

fn noteChain(a: std.mem.Allocator, table: *const origins.Table, sets: []std.AutoHashMapUnmanaged(u32, void), function: u32, start: u32) std.mem.Allocator.Error!void {
    if (function >= sets.len) return;
    var frame: ?u32 = start;
    while (frame) |id| : (frame = table.frames.items[id].parent) try sets[function].put(a, table.frames.items[id].function, {});
}

fn keyList(a: std.mem.Allocator, keys: []const ?[]const u8, targets: []const u32, own: u32) std.mem.Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (targets) |target| {
        if (target == own or target >= keys.len) continue;
        const key = keys[target] orelse continue;
        var present = false;
        for (out.items) |known| present = present or std.mem.eql(u8, known, key);
        if (!present) try out.append(a, key);
    }
    std.mem.sort([]const u8, out.items, {}, keyBefore);
    return out.items;
}

fn keyBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn entryBefore(_: void, left: Entry, right: Entry) bool {
    return std.mem.lessThan(u8, left.key, right.key);
}

/// Digest the final form of every internal function of `module`. A function whose final body has no canonical digest (unknown
/// metadata) is left out, as the optimizer cache leaves it unkeyed.
pub fn collect(self: *Observed, module: *const ir.Module, context: *optimization_cache.Context, inputs: Inputs) std.mem.Allocator.Error!void {
    const a = self.arena;
    const keys = try facts_shadow.keysOf(a, module);
    const sets = try contributorSets(a, inputs.provenance, module.functions.items.len);
    const fresh = try a.alloc(bool, module.functions.items.len);
    @memset(fresh, false);
    for (self.analysed.items) |index| if (index < fresh.len) {
        fresh[index] = true;
    };
    var entries: std.ArrayList(Entry) = .empty;
    for (keys, 0..) |maybe, index| {
        const key = maybe orelse continue;
        const loaded = context.lazy.loaded.len <= index or context.lazy.loaded[index];
        const metadata: ?optimization_cache.FinalMetadata = if (index < context.lazy.finals.len) context.lazy.finals[index] else null;
        const body: Digest = if (loaded) (try context.plainDigest(@intCast(index)) orelse continue) else (if (metadata) |known| known.body.plain else continue);
        const targets = if (loaded) try shortcut.Index.targets(a, &module.functions.items[index]) else (if (metadata) |known| known.outgoing else continue);
        var inlined: std.ArrayList(u32) = .empty;
        var members = sets[index].keyIterator();
        while (members.next()) |member| try inlined.append(a, member.*);
        try entries.append(a, .{
            .key = key,
            .body = body,
            .fresh = fresh[index],
            .callees = try keyList(a, keys, targets, @intCast(index)),
            .contributors = try keyList(a, keys, inlined.items, @intCast(index)),
        });
    }
    std.mem.sort(Entry, entries.items, {}, entryBefore);
    self.entries = entries.items;
    self.collected = true;
}

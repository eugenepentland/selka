//! The conclusions of the whole-program passes about each function of a module, as the `module-passes` kind states them (spec
//! §17.2): a digest of the function's summary, the cross-function facts the origin passes and the stand-in planning read.
//!
//! They come from the summaries the check just produced (`semantic_summary.Table`), which hold, for every ordinary function, the
//! facts of its body whether the body was checked or stood in for. A module whose `@noalloc` promise is not recorded has no answer:
//! see the kind.
//!
//! A summary also says whether the front end's own stand-in store may use it. `Summary.notes.complete` is the module-local part of
//! that decision (the function was checked, is not the entry point, every diagnostic in it is stored: a function of the module's own
//! reads; a repair or a waived site is kept with a guard over the waivers that decide it) and is part of the digest; the passes stand in for it without the body (G2k).
//! `Summary.stubbable`, the decision to stand in for the body too, is not a conclusion about the function and is left out of the
//! digest. Since G2m it no longer depends on which types the declarations of the whole program already name (a body that names a type
//! interned while it was checked, or a specialization, stands in too: its summary carries the recipes that intern them again), but it
//! still depends on the build before (a stored summary keeps the flag it was made with) and on what the catalog resolves at stand-in
//! time, and no query could read that. Nothing in the engine reads it: a body is skipped when its `module-check` part is valid. The
//! shadow found the flag as seven `module-passes` findings on 31 October, in which a standard-library module's record, made under one
//! entry, differed from the same module's under another in this flag alone.
const std = @import("std");
const language = @import("selka");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const passes_kind = @import("engine/kinds/module_passes.zig");
const check_facts = @import("module_check_facts.zig");
const diagnostics_facts = @import("module_diagnostics_facts.zig");
const noalloc_facts = @import("noalloc_closure_facts.zig");

/// The first line of the payload.
pub const payload_magic = "selka-module-passes-v1";
/// The domain string of a function's digest.
const domain = "selka-module-passes-fact-v4";
/// The prefix of the part a function's facts are published under.
pub const fact_prefix = "fact:";
/// The part a module's diagnostics are published under.
pub const warnings_part = "warnings";

/// What the argument of the program's entry module ends with: its `main` is the entry point, which the stand-in flag the passes state
/// depends on, so the record is another query from that of the same module imported by another program.
pub const entry_marker = "\x00entry";

/// One module's passes: the argument it is queried under (that of its check) and the answer, absent when the module is not recorded.
pub const Passes = struct { argument: []const u8, answer: ?passes_kind.Answer };

fn partLess(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The module name and the display name (`Domain.member` or the bare name) a stable function key names, or null for a key that
/// is not one.
fn splitKey(key: []const u8) ?struct { module: []const u8, name: []const u8, owner: []const u8 } {
    var fields = std.mem.splitScalar(u8, key, 0x1f);
    if (!std.mem.eql(u8, fields.next() orelse return null, "fn")) return null;
    const module = fields.next() orelse return null;
    const owner = fields.next() orelse return null;
    const name = fields.next() orelse return null;
    return .{ .module = module, .name = name, .owner = owner };
}

fn digestOf(summary: language.semantic_summary.Summary) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    state.update("\x00");
    state.update(summary.key);
    state.update("\x00");
    hashPositions(&state, summary.fact.mutates);
    state.update(&.{
        @intFromBool(summary.fact.mutates_unknown),
        @intFromBool(summary.fact.return_origin.unknown),
        @intFromBool(summary.fact.inferred.writes),
        @intFromBool(summary.fact.inferred.external),
        @intFromBool(summary.notes.complete),
    });
    hashPositions(&state, summary.fact.return_origin.positions);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

fn hashPositions(state: *std.crypto.hash.Blake3, positions: []const u16) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, positions.len, .little);
    state.update(&length);
    for (positions) |position| {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, position, .little);
        state.update(&encoded);
    }
}

/// The `noalloc-closure` queries of the promises module `path` declares, or null when one of them is not recorded. A root the front
/// end could not attribute to a module (its module is empty) leaves every module unrecorded.
fn promisesOf(a: std.mem.Allocator, roots: []const noalloc_facts.Root, path: []const u8) std.mem.Allocator.Error!?[]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    for (roots) |root| {
        if (root.module.len == 0) return null;
        if (root.instance or !std.mem.eql(u8, root.module, path)) continue;
        if (root.answer == null) return null;
        try found.append(a, root.argument);
    }
    std.mem.sort([]const u8, found.items, {}, lessThan);
    return found.items;
}

/// What a check ended with: the summaries it produced, its diagnostics in the front end's order, the query flags of its modules
/// (`check_facts.flagsOf`), which a module's passes are queried under as its check is, and the program's `@noalloc` roots.
pub const Ended = struct { produced: language.semantic_summary.Table, items: []const language.diagnostic.Diagnostic, flags: []const u8, roots: []const noalloc_facts.Root, src: language.source.Source };

/// The passes of every module of `index`'s project, in module order, from the summaries `produced` and the diagnostics `items` the
/// check ended with. Everything is allocated in `a`, which should be an arena.
pub fn compute(a: std.mem.Allocator, index: *language.interfaces.Index, ended: Ended) std.mem.Allocator.Error![]const Passes {
    const modules = index.project.modules.items;
    const produced = ended.produced;
    const items = ended.items;
    const flags = ended.flags;
    const out = try a.alloc(Passes, modules.len);
    const located = try diagnostics_facts.group(a, ended.src, index.project.modules.items, items);
    for (modules, out, 0..) |module, *slot, id| {
        const check_argument = try check_facts.moduleArgument(a, index, id, flags);
        // The first module is the program's entry.
        slot.* = .{ .argument = if (id == 0) try std.fmt.allocPrint(a, "{s}{s}", .{ check_argument, entry_marker }) else check_argument, .answer = null };
        const promises = (try promisesOf(a, ended.roots, module.src.path)) orelse continue;
        var parts: std.ArrayList(record.Part) = .empty;
        var bodies: std.ArrayList([]const u8) = .empty;
        var payload: std.ArrayList(u8) = .empty;
        try payload.print(a, "{s}\n{s}\n", .{ payload_magic, module.src.path });
        for (produced.summaries) |summary| {
            const split = splitKey(summary.key) orelse continue;
            if (!std.mem.eql(u8, split.module, module.name)) continue;
            const shown = if (split.owner.len == 0) split.name else try std.fmt.allocPrint(a, "{s}.{s}", .{ split.owner, split.name });
            const digest = digestOf(summary);
            try parts.append(a, .{ .name = try std.fmt.allocPrint(a, "{s}{s}", .{ fact_prefix, shown }), .digest = digest });
            try bodies.append(a, try std.fmt.allocPrint(a, "{s}{s}", .{ check_facts.body_prefix, shown }));
            try payload.print(a, "{s}{s} {s}\n", .{ fact_prefix, shown, digest_rules.hex(digest)[0..16] });
        }
        var warnings = std.crypto.hash.Blake3.init(.{});
        warnings.update(domain);
        warnings.update("\x00warnings\x00");
        for (located[id].lines) |line| {
            try payload.print(a, "warning {s}\n", .{line});
            var length: [8]u8 = undefined;
            std.mem.writeInt(u64, &length, line.len, .little);
            warnings.update(&length);
            warnings.update(line);
        }
        var warnings_digest: [32]u8 = undefined;
        warnings.final(&warnings_digest);
        try parts.append(a, .{ .name = warnings_part, .digest = warnings_digest });
        var texts: std.ArrayList([]const u8) = .empty;
        try texts.append(a, module.src.path);
        try texts.appendSlice(a, located[id].foreign);
        std.mem.sort(record.Part, parts.items, {}, partLess);
        std.mem.sort([]const u8, bodies.items, {}, lessThan);
        for (promises) |root| try payload.print(a, "promise {s}\n", .{root[0..std.mem.indexOfScalar(u8, root, 0).?]});
        slot.answer = .{ .payload = payload.items, .parts = parts.items, .bodies = bodies.items, .texts = texts.items, .noalloc = promises, .check = check_argument };
    }
    return out;
}

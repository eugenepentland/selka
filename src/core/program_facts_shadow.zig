//! The cross-function facts the optimizer joined, digested per function for the engine's shadow (part 2, G3h; spec §17.2, §17.6).
//!
//! The optimizer reads a few facts about the whole program that no single function decides: the interval each parameter ranges
//! over in every call (`parameters`), the interval each function returns, what each function does to its parameters
//! (`effects.Summaries`), the interval of every record field any write stores, whether the program holds a function value, and the
//! runtime helpers it declares. `Observed.collect` digests them once the optimizer has joined them, naming each function by its
//! checked name (never by its place in the function table) and each record by its structure (never by its place in the compound
//! table), so the digests are the same in two programs that differ elsewhere. The shadow (`frontend_shadow.zig`) hands them to the
//! `program-facts` kind, whose parts are these digests.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const effects = @import("effects.zig");
const consume = @import("consume.zig");
const canonical = @import("canonical_ir.zig");
const fast_blake3 = @import("fast_blake3.zig");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const facts_kind = @import("engine/kinds/program_facts.zig");

/// A 32-byte digest.
pub const Digest = [32]u8;

/// The prefix of the part holding a function's parameter hull.
pub const params_prefix = "params:";
/// The prefix of the part holding a function's return interval.
pub const returns_prefix = "returns:";
/// The prefix of the part holding a function's effects.
pub const effects_prefix = "effects:";
/// The first line of the payload.
pub const payload_magic = "selka-program-facts-v1";

/// One function's joined facts, digested.
pub const Entry = struct { key: []const u8, params: Digest, returns: Digest, effects: Digest };

/// What the optimizer joined, once it has: the internal functions' facts, and the program-wide ones.
pub const Observed = struct {
    arena: std.mem.Allocator,
    /// Whether `collect` ran: a mode that runs no facts (the ownership-only passes) leaves this false.
    collected: bool = false,
    functions: []const Entry = &.{},
    fields: Digest = @splat(0),
    closed: bool = true,
    helpers: Digest = @splat(0),
    entry: []const u8 = "",
};

/// The joins the optimizer made: each indexed by physical function.
pub const Joined = struct {
    parameters: []const []const ?facts.Interval,
    returns: []const ?facts.Interval,
    summaries: *const effects.Summaries,
    fields: facts.FieldIntervals,
};

fn put(hash: *fast_blake3.Blake3, comptime T: type, value: T) void {
    var little = std.mem.nativeToLittle(T, value);
    hash.update(std.mem.asBytes(&little));
}

fn interval(hash: *fast_blake3.Blake3, value: ?facts.Interval) void {
    const known = value orelse return hash.update(&.{0});
    hash.update(&.{1});
    put(hash, i128, known.lo);
    put(hash, i128, known.hi);
}

fn paths(hash: *fast_blake3.Blake3, value: effects.Paths) void {
    hash.update(&.{@intFromBool(value.whole)});
    put(hash, u32, @intCast(value.items.items.len));
    for (value.items.items) |path| {
        hash.update(&.{path.len});
        for (path.steps[0..path.len]) |step| put(hash, u16, step);
    }
}

fn effect(hash: *fast_blake3.Blake3, value: effects.Effect) void {
    hash.update(&.{ @intFromBool(value.borrow_only), @intFromBool(value.consumes) });
    paths(hash, value.reads);
    paths(hash, value.writes);
    paths(hash, value.when_true);
    paths(hash, value.when_false);
}

fn final(hash: *fast_blake3.Blake3) Digest {
    var out: Digest = undefined;
    hash.final(&out);
    return out;
}

/// The digest of a function's parameter hull: one interval or none per parameter. A function with no hull (its address is
/// taken, or no call reaches it) digests as the empty list, which is what the passes read it as.
fn paramsDigest(hulls: []const ?facts.Interval) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("params\x00");
    put(&hash, u32, @intCast(hulls.len));
    for (hulls) |hull| interval(&hash, hull);
    return final(&hash);
}

fn returnsDigest(value: ?facts.Interval) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("returns\x00");
    interval(&hash, value);
    return final(&hash);
}

fn effectsDigest(per_param: []const effects.Effect, may: [2]bool) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("effects\x00");
    put(&hash, u32, @intCast(per_param.len));
    for (per_param) |one| effect(&hash, one);
    hash.update(&.{ @intFromBool(may[0]), @intFromBool(may[1]) });
    return final(&hash);
}

/// The digest of a runtime function's declaration: its symbol and its signature with every type by structure.
fn declarationDigest(canon: *canonical.Canon, function: ir.Function) canonical.Error!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("helper\x00");
    hash.update(function.name);
    hash.update("\x00");
    put(&hash, u8, @backingInt(function.signature.linkage));
    put(&hash, u32, @intCast(function.signature.params.len));
    for (function.signature.params) |param| hash.update(&try canon.typeDigest(param));
    hash.update(&try canon.typeDigest(function.signature.ret));
    return final(&hash);
}

fn digestLess(_: void, left: Digest, right: Digest) bool {
    return std.mem.lessThan(u8, &left, &right);
}

/// One record type's field intervals, digested under the structure of the type.
const FieldRow = struct { type_digest: Digest, intervals: Digest };

fn rowLess(_: void, left: FieldRow, right: FieldRow) bool {
    const order = std.mem.order(u8, &left.type_digest, &right.type_digest);
    if (order != .eq) return order == .lt;
    return std.mem.lessThan(u8, &left.intervals, &right.intervals);
}

/// The field intervals of every record type, as one digest: the rows ordered by the structure of their type.
fn fieldsDigest(a: std.mem.Allocator, canon: *canonical.Canon, module: *const ir.Module, table: facts.FieldIntervals) (std.mem.Allocator.Error || canonical.Error)!Digest {
    var rows: std.ArrayList(FieldRow) = .empty;
    for (table.types, 0..) |maybe, at| {
        const fields = maybe orelse continue;
        var hash = fast_blake3.Blake3.init(.{});
        put(&hash, u32, @intCast(fields.len));
        for (fields) |field| interval(&hash, field);
        const ty: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + at));
        if (at >= module.compounds.items.len) continue;
        try rows.append(a, .{ .type_digest = try canon.typeDigest(ty), .intervals = final(&hash) });
    }
    std.mem.sort(FieldRow, rows.items, {}, rowLess);
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("fields\x00");
    for (rows.items) |row| {
        hash.update(&row.type_digest);
        hash.update(&row.intervals);
    }
    return final(&hash);
}

/// The key of each internal function of `module`: its checked name, with `#2`, `#3` for a name another internal function
/// shares. Null for a function that is not internal.
pub fn keysOf(a: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error![]const ?[]const u8 {
    const keys = try a.alloc(?[]const u8, module.functions.items.len);
    var seen: std.StringHashMapUnmanaged(u32) = .empty;
    for (module.functions.items, keys) |function, *key| {
        if (function.signature.linkage != .internal) {
            key.* = null;
            continue;
        }
        const slot = try seen.getOrPut(a, function.name);
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
        key.* = if (slot.value_ptr.* == 1) function.name else try std.fmt.allocPrint(a, "{s}#{d}", .{ function.name, slot.value_ptr.* });
    }
    return keys;
}

fn entryLess(_: void, left: Entry, right: Entry) bool {
    return std.mem.lessThan(u8, left.key, right.key);
}

/// Digest what the optimizer joined over `module`, which the joins index. Everything is allocated in the observation's arena.
pub fn collect(self: *Observed, module: *const ir.Module, canon: *canonical.Canon, joined: Joined) (std.mem.Allocator.Error || canonical.Error)!void {
    const a = self.arena;
    const keys = try keysOf(a, module);
    var entries: std.ArrayList(Entry) = .empty;
    for (keys, 0..) |maybe, index| {
        const key = maybe orelse continue;
        const hull: []const ?facts.Interval = if (index < joined.parameters.len) joined.parameters[index] else &.{};
        const returned: ?facts.Interval = if (index < joined.returns.len) joined.returns[index] else null;
        const per_param: []const effects.Effect = if (index < joined.summaries.params.len) joined.summaries.params[index] else &.{};
        const may: [2]bool = if (index < joined.summaries.may.len) joined.summaries.may[index] else .{ false, false };
        try entries.append(a, .{ .key = key, .params = paramsDigest(hull), .returns = returnsDigest(returned), .effects = effectsDigest(per_param, may) });
    }
    std.mem.sort(Entry, entries.items, {}, entryLess);
    var helpers: std.ArrayList(Digest) = .empty;
    for (module.functions.items) |function| {
        if (function.signature.linkage != .runtime_c) continue;
        try helpers.append(a, try declarationDigest(canon, function));
    }
    std.mem.sort(Digest, helpers.items, {}, digestLess);
    var helper_hash = fast_blake3.Blake3.init(.{});
    helper_hash.update("helpers\x00");
    for (helpers.items) |one| helper_hash.update(&one);
    self.functions = entries.items;
    self.fields = try fieldsDigest(a, canon, module, joined.fields);
    self.closed = consume.closed(module);
    self.helpers = final(&helper_hash);
    self.entry = if (module.entry < keys.len) (keys[module.entry] orelse "") else "";
    self.collected = true;
}

fn partLess(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// The answer of the `program-facts` kind for what the optimizer joined: a part per function and fact, and the program-wide
/// parts. `units` are the `unit-lower` arguments of the program's units, which the record reads.
pub fn answer(a: std.mem.Allocator, observed: *const Observed, units: []const []const u8) std.mem.Allocator.Error!facts_kind.Answer {
    var parts: std.ArrayList(record.Part) = .empty;
    var payload: std.ArrayList(u8) = .empty;
    try payload.print(a, "{s}\n", .{payload_magic});
    for (observed.functions) |one| {
        inline for (.{ .{ params_prefix, "params" }, .{ returns_prefix, "returns" }, .{ effects_prefix, "effects" } }) |fact| {
            const digest = @field(one, fact[1]);
            const name = try std.fmt.allocPrint(a, "{s}{s}", .{ fact[0], one.key });
            try parts.append(a, .{ .name = name, .digest = digest });
            try payload.print(a, "{s} {s}\n", .{ name, digest_rules.hex(digest)[0..16] });
        }
    }
    var closed_hash = fast_blake3.Blake3.init(.{});
    closed_hash.update("closed\x00");
    closed_hash.update(&.{@intFromBool(observed.closed)});
    var entry_hash = fast_blake3.Blake3.init(.{});
    entry_hash.update("entry\x00");
    entry_hash.update(observed.entry);
    const program_wide = [_]record.Part{
        .{ .name = "closed", .digest = final(&closed_hash) },
        .{ .name = "entry", .digest = final(&entry_hash) },
        .{ .name = "fields", .digest = observed.fields },
        .{ .name = "helpers", .digest = observed.helpers },
    };
    for (program_wide) |part| {
        try parts.append(a, part);
        try payload.print(a, "{s} {s}\n", .{ part.name, digest_rules.hex(part.digest)[0..16] });
    }
    std.mem.sort(record.Part, parts.items, {}, partLess);
    return .{ .payload = payload.items, .parts = parts.items, .units = units };
}

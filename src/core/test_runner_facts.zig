//! Canonical pre-pass test facts admitted by validated raw discovery and source keys.
//! Metadata hits keep unrelated instruction payloads unmaterialized.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const ir = @import("ir.zig");
const canonical = @import("canonical_ir.zig");
const identity = @import("test_runner_identity.zig");
const lowering = @import("lowering_cache.zig");
const source_location = @import("source_location.zig");
const stage = @import("stage_store.zig");
const render = @import("build_render.zig");
const test_records = @import("test_records.zig");

/// Unsupported canonical metadata requests complete lowering; lost bodies request retry.
pub const Error = canonical.Error || error{CacheMiss};
/// Work performed by canonical fact extraction and metadata admission.
pub const Metrics = @import("test_runner_work.zig").Facts;
const Ledger = test_records.Ledger;

/// Fresh snapshot indices, their validated stable declaration identities, and the scope every fact of the module is keyed
/// under (`Identities.scope`).
/// `bare` holds each function's `bare` answer, by index.
pub const Result = struct { shared: identity.Shared, identities: []const ?stage.Digest, scope: stage.Digest, bare: []const bool };

const maximum_inline = 512;
const Fact = struct { identity: stage.Digest, digest: stage.Digest, count: u32, edges: []const stage.Digest, chunks: []const stage.Digest, bare: bool };

/// Whether a function's own code lets a test that reaches it share its record across worktrees, as far as the code goes
/// (`test_runner_portable.portableModule` asks it of every function of a test's program): it records no error return trace,
/// and it is either a body of the program or a runtime helper (`myl_core_`), not an extern or a host function.
pub fn bare(function: ir.Function) bool {
    if (function.signature.linkage != .internal and !std.mem.startsWith(u8, function.name, "myl_core_")) return false;
    for (function.insts.items) |inst| if (inst.op == .err_trace) return false;
    return true;
}
const Registry = std.AutoHashMapUnmanaged(stage.Digest, u32);

/// The key of function `index`'s fact, or null when it has none: the function's lowering key as lowering recorded it
/// (`Deferred.tables.unmixed`, before `prepare` mixed in where the function's sites are), and `scope`, the digest of the
/// lowered module's function table (`Identities.scope`). The fact's digest is position-free (`Canon.plainDigest`), so where
/// the function is enters neither (D-T1-1 and D-T2-2 of `experiments/test-keys-20261106/DECISIONS.md`): a lowering key names
/// what the body lowers to wherever it is, and the table names everything module-wide a fact is read against, the identities
/// its edges remap to and the render shapes its digest reads.
pub fn factKey(deferred: *const lowering.Deferred, scope: stage.Digest, index: u32) ?stage.Digest {
    if (index >= deferred.tables.keys.items.len or index >= deferred.tables.unmixed.items.len) return null;
    // A function whose sites the current source no longer proves has no key at all (`Deferred.prepare`).
    if (deferred.tables.keys.items[index] == null) return null;
    const raw = deferred.tables.unmixed.items[index] orelse return null;
    return deferred.store.key("core-test-function-facts-v3", &.{ &raw, &scope });
}

/// Every function's logical identity in a lowered module (null for a render declaration, which nothing calls), and the
/// digest of the whole table (`scope`): the identities in order of their digests, then each render declaration's id and the
/// shape it authorizes.
pub const Identities = struct {
    logical: []?stage.Digest,
    scope: stage.Digest,

    /// The identities of `module`'s functions (`Canon.callee`, and a name-qualified one for a declaration whose identity
    /// another one shares, `distinguish`) and their scope.
    pub fn of(a: std.mem.Allocator, module: *const ir.Module, canon: *canonical.Canon) Error!Identities {
        const identities = try a.alloc(?stage.Digest, module.functions.items.len);
        var shapes: std.ArrayList(stage.Digest) = .empty;
        for (module.functions.items, identities, 0..) |function, *logical, index| {
            logical.* = null;
            if (function.signature.linkage == .runtime_c and std.mem.startsWith(u8, function.name, render.declaration_prefix)) {
                try shapes.append(a, try shapeDigest(module, function.name));
                continue;
            }
            logical.* = try canon.callee(@intCast(index));
        }
        try distinguish(a, module, identities);
        var known: std.ArrayList(stage.Digest) = .empty;
        for (identities) |logical| if (logical) |value| try known.append(a, value);
        std.mem.sort(stage.Digest, known.items, {}, lessDigest);
        std.mem.sort(stage.Digest, shapes.items, {}, lessDigest);
        var hash = fast_blake3.Blake3.init(.{});
        hash.update("core-test-function-scope-v1");
        for ([_][]const stage.Digest{ known.items, shapes.items }) |part| {
            hash.update(&std.mem.toBytes(std.mem.nativeToLittle(u64, part.len)));
            for (part) |digest| hash.update(&digest);
        }
        var scope: stage.Digest = undefined;
        hash.final(&scope);
        return .{ .logical = identities, .scope = scope };
    }
};

/// A render declaration (`myl_core_render_shape_<string>_<id>`) as its id and the text of the shape it authorizes.
fn shapeDigest(module: *const ir.Module, name: []const u8) Error!stage.Digest {
    const authority = name[render.declaration_prefix.len..];
    const split = std.mem.indexOfScalar(u8, authority, '_') orelse return error.UnknownMetadata;
    const index = std.fmt.parseInt(usize, authority[0..split], 10) catch return error.UnknownMetadata;
    if (index >= module.strings.items.len) return error.UnknownMetadata;
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(authority[split + 1 ..]);
    hash.update("\x00");
    hash.update(module.strings.items[index]);
    var digest: stage.Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn lessDigest(_: void, left: stage.Digest, right: stage.Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

/// The variable that turns the facts' group records off (`0` or `off`): every function's fact is then read by its own key, as
/// before stage 4 of the test-loop plan. The facts are the same either way; only how many records a run reads differs.
pub const groups_variable = "SELKA_TEST_FACT_GROUPS";

/// Whether a run reads its facts by group records: unless `groups_variable` is `0` or `off`.
pub fn groupsFacts(environment: *const std.process.Environ.Map) bool {
    const value = environment.get(groups_variable) orelse return true;
    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

/// What `buildWith` reads: the lowered module, where its sites are, its deferred lowering, the engine's records, and whether
/// the facts are read by group records (`groupsFacts`) before each function's own.
pub const Input = struct { module: *ir.Module, locator: source_location.Locator, deferred: *lowering.Deferred, records: test_records.Records, grouped: bool = true };

/// Reuse complete digest/edge records after header discovery validates their inputs, reading them by group records.
/// A miss materializes only its own function, using the uncached canonical contract.
pub fn build(a: std.mem.Allocator, module: *ir.Module, locator: source_location.Locator, deferred: *lowering.Deferred, records: test_records.Records, metrics: *Metrics) Error!Result {
    return buildWith(a, .{ .module = module, .locator = locator, .deferred = deferred, .records = records }, metrics);
}

/// `build` with the group records on or off (`Input.grouped`). The functions with a fact key are cut into groups (`groups`),
/// each stored as one record of its members' facts under the digest of their keys, so a group with no changed function is one
/// record read; a group whose record is missing or does not describe its members reads each member's own record, recomputes
/// the ones that miss, and records the group again. The result is the same with groups or without.
pub fn buildWith(a: std.mem.Allocator, input: Input, metrics: *Metrics) Error!Result {
    const module = input.module;
    const deferred = input.deferred;
    const records = input.records;
    const ledger: Ledger = .{ .store = deferred.store, .records = records };
    var canon = try canonical.Canon.prepare(a, module, input.locator);
    var registry: Registry = .empty;
    defer registry.deinit(a);
    const table = try Identities.of(a, module, &canon);
    const identities = table.logical;
    for (identities, 0..) |logical, index| {
        const value = logical orelse continue;
        const entry = try registry.getOrPut(a, value);
        if (entry.found_existing) return error.UnknownMetadata;
        entry.value_ptr.* = @intCast(index);
    }
    const keys = try a.alloc(?stage.Digest, identities.len);
    for (identities, keys, 0..) |logical, *key, index| key.* = if (logical != null) factKey(deferred, table.scope, @intCast(index)) else null;
    // `held` is a member's fact as its group's record gave it, `kept` the fact each function ends with (what its group records).
    const held = try a.alloc(?Fact, identities.len);
    const kept = try a.alloc(?Fact, identities.len);
    const served = try a.alloc(bool, identities.len);
    @memset(held, null);
    @memset(kept, null);
    @memset(served, false);
    const sets = if (input.grouped) try groups(a, deferred.store, module, keys) else &.{};
    const loaded = try a.alloc(bool, sets.len);
    for (sets, loaded) |set, *found| found.* = try serve(a, records, set, held, metrics);
    const digests = try a.alloc(stage.Digest, identities.len);
    const callees = try a.alloc([]const u32, identities.len);
    const plain = try a.alloc(bool, identities.len);
    for (identities, keys, digests, callees, plain, 0..) |logical, key, *digest, *edges, *own, index| {
        const physical: u32 = @intCast(index);
        var stale = false;
        const found: ?Fact = held[index] orelse if (key) |address| try records.loadValue(a, a, .facts, &address, Fact) else null;
        if (found) |fact| {
            if (held[index] == null) metrics.decoded += 1;
            stale = true;
            if (std.mem.eql(u8, &fact.identity, &logical.?)) if (try recall(a, ledger, fact, &registry, metrics)) |targets| {
                digest.* = fact.digest;
                edges.* = targets;
                own.* = fact.bare;
                metrics.reused += 1;
                kept[index] = fact;
                served[index] = held[index] != null;
                continue;
            };
        }
        if (module.functions.items[index].signature.linkage == .internal) metrics.fallback += 1;
        try deferred.context.ensureRaw(physical);
        digest.* = try canon.plainDigest(physical);
        edges.* = try identity.calls(a, module.functions.items[index]);
        own.* = bare(module.functions.items[index]);
        metrics.fresh += 1;
        for (edges.*) |target| if (target >= identities.len or identities[target] == null) return error.UnknownMetadata;
        const made: Fact = .{ .identity = logical orelse continue, .digest = digest.*, .count = @intCast(edges.*.len), .edges = &.{}, .chunks = &.{}, .bare = own.* };
        if (key) |address| kept[index] = try remember(a, ledger, .{ .key = address, .replace = stale }, made, edges.*, identities);
    }
    for (sets, loaded) |set, found| try regroup(a, records, set, .{ .kept = kept, .served = served, .found = found });
    return .{ .shared = .{ .digests = digests, .callees = callees }, .identities = identities, .scope = table.scope, .bare = plain };
}

/// About how many functions share a group record. A group is recorded again whole when any member changes, and a run reads one
/// record per group, as the optimizer's chunks are (`optimizer_chunks.rows_per_chunk`).
const members_per_group = 6;

/// One group of a module's keyed functions: the digest of its members' fact keys (its record's key) and its members, ordered by
/// fact key and then by name (two functions can share a lowering key; their names tell them apart).
pub const Group = struct { key: stage.Digest, members: []const u32 };

/// The groups of the functions with a fact key (`keys`, by index; null for none): a function's group is a hash of its name among
/// the smallest power of two of groups that leaves at most `members_per_group` functions in one on average, so an edit that
/// changes a function's key changes only its group's record, and adding functions moves every group only when the count passes
/// a power of two. A group's record is keyed by its members' keys alone, which carry the module's function table
/// (`Identities.scope`), so the same functions in another tree or entry name the same record.
pub fn groups(a: std.mem.Allocator, store: *const stage.Store, module: *const ir.Module, keys: []const ?stage.Digest) std.mem.Allocator.Error![]const Group {
    var keyed: usize = 0;
    for (keys) |key| keyed += @intFromBool(key != null);
    var buckets: usize = 1;
    while (buckets * members_per_group < keyed) buckets *= 2;
    const lists = try a.alloc(std.ArrayList(u32), buckets);
    @memset(lists, .empty);
    for (keys, 0..) |key, index| if (key != null) {
        const bucket = std.hash.Wyhash.hash(0, module.functions.items[index].name) % buckets;
        try lists[bucket].append(a, @intCast(index));
    };
    var found: std.ArrayList(Group) = .empty;
    for (lists) |list| {
        if (list.items.len == 0) continue;
        std.mem.sort(u32, list.items, Order{ .keys = keys, .module = module }, Order.less);
        const bytes = try a.alloc(u8, list.items.len * 32);
        for (list.items, 0..) |index, at| @memcpy(bytes[at * 32 ..][0..32], &keys[index].?);
        try found.append(a, .{ .key = store.key("core-test-function-fact-group-v1", &.{bytes}), .members = list.items });
    }
    return found.items;
}

/// The order of a group's members: by fact key, then by name.
const Order = struct {
    keys: []const ?stage.Digest,
    module: *const ir.Module,

    fn less(self: Order, left: u32, right: u32) bool {
        switch (std.mem.order(u8, &self.keys[left].?, &self.keys[right].?)) {
            .lt => return true,
            .gt => return false,
            .eq => return std.mem.order(u8, self.module.functions.items[left].name, self.module.functions.items[right].name) == .lt,
        }
    }
};

/// Read `set`'s record and give each member its fact (`held`), when the record holds one fact for each member; whether the
/// engine held a record under the group's key. A member whose fact does not describe it is found stale when it is used.
fn serve(a: std.mem.Allocator, records: test_records.Records, set: Group, held: []?Fact, metrics: *Metrics) std.mem.Allocator.Error!bool {
    const stored = try records.loadValue(a, a, .facts, &set.key, []const Fact) orelse return false;
    metrics.decoded += 1;
    if (stored.len != set.members.len) return true;
    for (set.members, stored) |index, fact| held[index] = fact;
    metrics.groups += 1;
    return true;
}

/// What a run ended with, for recording the groups again: each function's fact, whether its group's record gave the fact the
/// run used, and whether the engine held a record under the group's key.
const Outcome = struct { kept: []const ?Fact, served: []const bool, found: bool };

/// Record `set` again unless its record gave every member the fact the run used: the members' facts in the group's order, in
/// place of a record that did not describe them.
fn regroup(a: std.mem.Allocator, records: test_records.Records, set: Group, outcome: Outcome) std.mem.Allocator.Error!void {
    var whole = true;
    for (set.members) |index| whole = whole and outcome.served[index];
    if (whole) return;
    const value = try a.alloc(Fact, set.members.len);
    for (set.members, value) |index, *fact| fact.* = outcome.kept[index] orelse return;
    try records.storeValue(a, .{ .which = .facts, .key = &set.key, .replace = outcome.found }, []const Fact, value);
}

/// Give each declaration that shares its canonical identity with another one (two owned-copy helpers of records of one
/// structure, which copy alike) an identity qualified by its name, so a stored edge finds the function it named. Only
/// declarations without a body are qualified: they have no callees, and their names are stable keys
/// (`stable_names.helperName`). Two bodies with one identity, or a qualified name that still collides, leave the duplicate,
/// which the registry refuses.
fn distinguish(a: std.mem.Allocator, module: *const ir.Module, identities: []?stage.Digest) std.mem.Allocator.Error!void {
    var counts: std.AutoHashMapUnmanaged(stage.Digest, u32) = .empty;
    defer counts.deinit(a);
    for (identities) |logical| if (logical) |value| {
        const entry = try counts.getOrPut(a, value);
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    };
    for (identities, module.functions.items) |*logical, function| {
        const value = logical.* orelse continue;
        if (counts.get(value).? < 2 or function.signature.linkage == .internal) continue;
        var hash = fast_blake3.Blake3.init(.{});
        hash.update("core-test-function-identity-named-v1");
        hash.update(&value);
        hash.update(function.name);
        var named: stage.Digest = undefined;
        hash.final(&named);
        logical.* = named;
    }
}

fn recall(a: std.mem.Allocator, ledger: Ledger, fact: Fact, registry: *const Registry, metrics: *Metrics) std.mem.Allocator.Error!?[]const u32 {
    if (fact.count > registry.count()) return null;
    if (fact.count <= maximum_inline) {
        if (fact.edges.len != fact.count or fact.chunks.len != 0) return null;
        return remap(a, fact.edges, registry);
    }
    if (fact.edges.len != 0 or fact.chunks.len != (fact.count + maximum_inline - 1) / maximum_inline) return null;
    const logical = try a.alloc(stage.Digest, fact.count);
    var offset: usize = 0;
    for (fact.chunks) |key| {
        const chunk = try ledger.records.loadValue(a, a, .facts, &key, []const stage.Digest) orelse return null;
        metrics.decoded += 1;
        if (chunk.len != @min(maximum_inline, logical.len - offset)) return null;
        if (!std.mem.eql(u8, &key, &chunkKey(ledger.store, chunk))) return null;
        @memcpy(logical[offset..][0..chunk.len], chunk);
        offset += chunk.len;
    }
    return remap(a, logical, registry);
}

fn remap(a: std.mem.Allocator, logical: []const stage.Digest, registry: *const Registry) std.mem.Allocator.Error!?[]const u32 {
    const indices = try a.alloc(u32, logical.len);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(a);
    for (logical, indices) |value, *index| {
        index.* = registry.get(value) orelse return null;
        const found = try seen.getOrPut(a, index.*);
        if (found.found_existing) return null;
    }
    return indices;
}

fn chunkKey(store: *const stage.Store, values: []const stage.Digest) stage.Digest {
    return store.key("core-test-function-edges-v1", &.{std.mem.sliceAsBytes(values)});
}

/// Where a fact goes: its key, and whether it replaces a record found under the key that did not describe the function (a
/// key that held nothing is a plain save, which touches no other store).
const Place = struct { key: stage.Digest, replace: bool };

/// Record a fresh fact (and its edge chunks) at `place`; the fact as recorded, which its group records too.
fn remember(a: std.mem.Allocator, ledger: Ledger, place: Place, value: Fact, indices: []const u32, identities: []const ?stage.Digest) std.mem.Allocator.Error!Fact {
    var fact = value;
    const logical = try a.alloc(stage.Digest, indices.len);
    for (indices, logical) |index, *edge| edge.* = identities[index].?;
    if (logical.len <= maximum_inline) {
        fact.edges = logical;
    } else {
        const keys = try a.alloc(stage.Digest, (logical.len + maximum_inline - 1) / maximum_inline);
        for (keys, 0..) |*address, index| {
            const start = index * maximum_inline;
            const chunk = logical[start..@min(logical.len, start + maximum_inline)];
            address.* = chunkKey(ledger.store, chunk);
            try ledger.records.storeValue(a, .{ .which = .facts, .key = address, .replace = place.replace }, []const stage.Digest, chunk);
        }
        fact.chunks = keys;
    }
    // A fact is recorded only after the lookup missed or found a record that did not describe the function; only the second
    // replaces a record (a chunk is checked against its key when it loads, so a damaged one makes its fact stale).
    try ledger.records.storeValue(a, .{ .which = .facts, .key = &place.key, .replace = place.replace }, Fact, fact);
    return fact;
}

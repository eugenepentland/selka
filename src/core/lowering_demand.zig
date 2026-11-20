//! A compact bridge from validated semantic summaries to raw lowering artifacts.
//! The frontend may omit a tree only when this entry has a previous body digest
//! or completed discovery proved that its declaration was unreachable.
//! Lowering still validates its exact catalog, discovery order and artifact; any
//! missing artifact asks the pipeline to repeat with complete checked trees.
//!
//! Each receipt is a record keyed by its own inputs: the entry and debug policy, the function's key, its dependency digest and its
//! region. A receipt is therefore found by the inputs it was made for and by nothing else, so no generation names it, and a build
//! writes only the receipts it did not find (`publish`).
const std = @import("std");
const language = @import("selka");
const stage = @import("stage_store.zig");
const sources = @import("demand_sources.zig");

/// A receipt as lowering names it in this build: the function's identity and the value it lowered to.
const Receipt = struct {
    key: []const u8,
    context: stage.Digest,
    region: stage.Digest,
    kind: Kind,
    sources: []const sources.Proof = &.{},
    /// The ordinary instance, when the receipt belongs to a function of this build's program (a module record is written from these).
    instance: ?u32 = null,
};
/// What a stored record holds: the lowered body's digest, or that the declaration was unreachable, with the source proofs.
const Kind = union(enum) { lowered: stage.Digest, @"unreachable" };
const Value = struct { kind: Kind, sources: []const sources.Proof = &.{} };
/// One member of a module record: the value of the function's receipt, or no receipt.
const Member = struct { present: bool, value: Value };
/// A module's receipts as one record (G2p): the value of each ordinary function of the module in program order, found by the module's
/// signature and file digest. It holds what the per-function receipts hold, so a build that finds it reads one record for the module
/// instead of one for each of its functions.
const ModuleValue = struct { members: []const Member };
/// What a build read of one module's record: its members, and which of them hold (their receipt exists and its source proofs stand).
const ModuleRecord = struct { members: []const Member, held: []const bool };
const Inputs = struct {
    prepared: ?language.semantic_summary.Prepared = null,
    omitted: []const bool = &.{},
    reached: ?[]const bool = null,
};

/// One build's receipts and selected checked-body omissions. All memory belongs to the build arena; no function tree is stored
/// in this index.
pub const Context = struct {
    arena: std.mem.Allocator,
    store: *const stage.Store,
    /// The scope of this build's receipts: the debug policy and the ownership mode. The entry joins it once a source is bound.
    policy: stage.Digest,
    /// What this build read: a function receipt by record key (a null value is a record that is not stored), and a module's record by
    /// module name (a group that has none reads its functions' receipts one by one).
    read: struct {
        receipts: std.AutoHashMapUnmanaged(stage.Digest, ?Value) = .empty,
        modules: std.StringHashMapUnmanaged(ModuleRecord) = .empty,
    } = .{},
    input: Inputs = .{},
    next: std.ArrayList(Receipt) = .empty,
    sources: sources.Cache,

    /// The receipts of this debug policy and ownership mode. Nothing is read until a lookup asks for a receipt.
    pub fn init(arena: std.mem.Allocator, store: *const stage.Store, drop_debug: bool) std.mem.Allocator.Error!Context {
        const parts: []const []const u8 = &.{ &.{@intFromBool(drop_debug)}, @import("ownership_mode.zig").name };
        return .{ .arena = arena, .store = store, .policy = store.key(record_scope, parts), .sources = .{ .arena = arena } };
    }

    /// Offer constant-time receipt lookup to the frontend's dependency planner.
    /// Keep this context at a stable address until checking finishes.
    pub fn callback(self: *const Context) language.semantic_summary.Demand {
        // A lowered function reads its callees' signatures, never their bodies (`FnBuilder.call`: the checked signature,
        // `declared_mutates`, `policy`), and the receipt is keyed by the function's own body part: a callee's body edit does not
        // stale its callers' artifacts. The allocation contracts that do read callee bodies keep theirs concrete on their own
        // (`Plan.requireAllocationBodies`).
        return .{ .context = self, .allow = allows, .allow_module = allowsModule, .prepare_sources = prepareSources, .body_dependencies = false, .facts_unread = true };
    }

    fn prepareSources(context: *const anyopaque, source: language.source.Source) std.mem.Allocator.Error!void {
        const self: *Context = @ptrCast(@alignCast(@constCast(context)));
        self.sources.bind(source);
    }

    fn allows(context: *const anyopaque, key: []const u8, dependency: stage.Digest, region: stage.Digest) bool {
        const self: *Context = @ptrCast(@alignCast(@constCast(context)));
        return self.admitted(key, dependency, region) != null;
    }

    fn allowsModule(context: *const anyopaque, group: language.semantic_key.ModuleGroup, out: []bool) bool {
        const self: *Context = @ptrCast(@alignCast(@constCast(context)));
        return self.readModule(group, out);
    }

    /// The record key of a module's receipts: the scope of the per-function receipts, and the module's signature and file digest, which
    /// decide every function of it and every source proof of its own file.
    fn moduleKey(self: *const Context, group: language.semantic_key.ModuleGroup) ?stage.Digest {
        const bound = self.sources.identity orelse return null;
        return self.store.key(module_scope, &.{ &self.policy, &bound, group.module, &group.signature, &group.file });
    }

    /// Read the record of one module's receipts and say which functions it admits: the receipt exists and every source proof of a file other than
    /// the module's own still holds (the module's file is in the key). False when the build holds no record for this signature and file.
    fn readModule(self: *Context, group: language.semantic_key.ModuleGroup, out: []bool) bool {
        const digest = self.moduleKey(group) orelse return false;
        const stored = (self.store.loadValue(self.arena, digest, ModuleValue) catch null) orelse return false;
        if (stored.members.len != group.members.len or out.len != group.members.len) return false;
        const held = self.arena.alloc(bool, stored.members.len) catch return false;
        for (stored.members, held, out) |member, *holds, *bit| {
            holds.* = member.present and self.foreignProofsHold(member.value.sources, group.path);
            bit.* = holds.*;
        }
        self.read.modules.put(self.arena, group.module, .{ .members = stored.members, .held = held }) catch return false;
        return true;
    }

    /// Whether every proof of a file other than `own` still holds; a proof of the module's own file holds by the module's key.
    fn foreignProofsHold(self: *Context, proofs: []const sources.Proof, own: []const u8) bool {
        for (proofs) |proof| {
            if (std.mem.eql(u8, proof.path, own)) continue;
            if (!(self.sources.matches(&.{proof}) catch return false)) return false;
        }
        return true;
    }

    /// The value the module record read in this build holds for function `id`, when it admits it.
    fn memberValue(self: *const Context, id: language.typed.FunctionId) ?Value {
        const prepared = self.input.prepared orelse return null;
        const index = @backingInt(id);
        if (index >= prepared.grouping.module_of.len) return null;
        const group = prepared.grouping.module_of[index];
        if (group >= prepared.grouping.modules.len) return null;
        const read = self.read.modules.get(prepared.grouping.modules[group].module) orelse return null;
        const at = prepared.grouping.ordinal_of[index];
        if (at >= read.members.len or !read.held[at]) return null;
        return read.members[at].value;
    }

    /// Whether this build already holds the receipt of function `index` through a module record, so there is nothing to write for it.
    fn recordedByModule(self: *const Context, index: u32) bool {
        const prepared = self.input.prepared orelse return false;
        if (index >= prepared.grouping.module_of.len) return false;
        const group = prepared.grouping.module_of[index];
        if (group >= prepared.grouping.modules.len) return false;
        const read = self.read.modules.get(prepared.grouping.modules[group].module) orelse return false;
        const at = prepared.grouping.ordinal_of[index];
        return at < read.members.len and read.held[at];
    }

    /// The record key of one receipt: its scope, the entry it was lowered for (its key name, `demand_sources.Cache.identity`),
    /// and the three things a receipt is valid for. Null before a source is bound, so an unbound build neither reads nor writes
    /// a receipt. The entry's bytes are not in the key: the function's region holds its own bytes, and every position outside
    /// it carries the digest of its original file as a source proof.
    fn recordKey(self: *const Context, key: []const u8, context: stage.Digest, region: stage.Digest) ?stage.Digest {
        const bound = self.sources.identity orelse return null;
        return self.store.key(record_scope, &.{ &self.policy, &bound, key, &context, &region });
    }

    /// The stored value of the receipt made for these inputs, read once per build; an allocation failure reads as absent.
    fn lookup(self: *Context, key: []const u8, context: stage.Digest, region: stage.Digest) ?Value {
        const digest = self.recordKey(key, context, region) orelse return null;
        if (self.read.receipts.get(digest)) |known| return known;
        const loaded = self.store.loadValue(self.arena, digest, Value) catch null;
        self.read.receipts.put(self.arena, digest, loaded) catch return null;
        return loaded;
    }

    /// The stored receipt for these inputs when its source proofs still match the current files; null otherwise.
    fn admitted(self: *Context, key: []const u8, context: stage.Digest, region: stage.Digest) ?Value {
        const value = self.lookup(key, context, region) orelse return null;
        if (!(self.sources.matches(value.sources) catch return null)) return null;
        return value;
    }

    /// Bind the source a build lowers, so its receipts are keyed by that entry. A build with no source binds nothing, and
    /// its receipts are neither read nor written.
    pub fn bindSource(self: *Context, source: ?language.source.Source) void {
        if (source) |bound| self.sources.bind(bound);
    }

    /// Attach fresh declaration identities and the bodies actually omitted by
    /// checking, after its dependency and cross-function consistency checks.
    pub fn attach(self: *Context, prepared: language.semantic_summary.Prepared, skipped: []const bool) void {
        self.input = .{ .prepared = prepared, .omitted = skipped };
    }

    /// Whether this function has no checked body and must restore raw lowering
    /// if discovery reaches it, or request a complete frontend retry.
    pub fn omitted(self: *const Context, id: language.typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.input.omitted.len and self.input.omitted[index];
    }

    /// Number of checked trees the frontend avoided materializing in this build.
    pub fn count(self: *const Context) usize {
        var result: usize = 0;
        for (self.input.omitted) |value| result += @intFromBool(value);
        return result;
    }

    /// The previously computed typed-tree digest, after semantic validation.
    pub fn body(self: *Context, id: language.typed.FunctionId) ?stage.Digest {
        if (!self.omitted(id)) return null;
        const current = self.identity(id) orelse return null;
        const value = self.memberValue(id) orelse self.admitted(current.key, current.context, current.region) orelse return null;
        return switch (value.kind) {
            .lowered => |digest| digest,
            .@"unreachable" => null,
        };
    }

    fn identity(self: *const Context, id: language.typed.FunctionId) ?Receipt {
        const prepared = self.input.prepared orelse return null;
        const index = @backingInt(id);
        if (index >= prepared.ordinary_ast.len) return null;
        const ast = prepared.ordinary_ast[index];
        return .{ .key = prepared.keys[ast], .context = prepared.contexts[ast], .region = prepared.recalled.digests[ast], .kind = .@"unreachable", .instance = @intCast(index) };
    }

    /// Remember only a body with relocatable local positions. Nonordinary and
    /// unsupported summaries remain on the complete checked-tree path.
    pub fn record(self: *Context, id: language.typed.FunctionId, digest: stage.Digest) std.mem.Allocator.Error!void {
        var receipt = self.identity(id) orelse return;
        receipt.kind = .{ .lowered = digest };
        if (self.omitted(id)) if (self.memberValue(id) orelse self.lookup(receipt.key, receipt.context, receipt.region)) |previous| {
            receipt.sources = previous.sources;
        };
        try self.next.append(self.arena, receipt);
    }

    /// Add authority for both checked-tree and synthesized lowering sites.
    pub fn addSources(self: *Context, id: language.typed.FunctionId, proofs: []const sources.Proof) std.mem.Allocator.Error!void {
        const identity_value = self.identity(id) orelse return;
        if (self.next.items.len == 0) return;
        const receipt = &self.next.items[self.next.items.len - 1];
        if (!std.mem.eql(u8, receipt.key, identity_value.key)) return;
        receipt.sources = try mergeProofs(self.arena, receipt.sources, proofs);
    }

    /// Discard the current receipt if lowering discovered source metadata that
    /// cannot be reconstructed from the declaration and fresh function catalog.
    pub fn reject(self: *Context, id: language.typed.FunctionId) void {
        const receipt = self.identity(id) orelse return;
        if (self.next.items.len == 0) return;
        if (std.mem.eql(u8, self.next.items[self.next.items.len - 1].key, receipt.key)) _ = self.next.pop();
    }

    /// Capture every typed declaration reached by successful lowering discovery.
    /// Reached declarations without safe body receipts must remain unavailable.
    pub fn recordReachable(self: *Context, ids: []const language.typed.FunctionId) std.mem.Allocator.Error!void {
        const prepared = self.input.prepared orelse return;
        const reached = try self.arena.alloc(bool, prepared.ordinary_ast.len);
        @memset(reached, false);
        for (ids) |id| {
            const index = @backingInt(id);
            if (index < reached.len) reached[index] = true;
        }
        self.input.reached = reached;
    }

    /// Publish only after every reachable function restored or lowered safely.
    /// An absent completed-discovery mask never admits an unknown declaration.
    pub fn finish(self: *Context) std.mem.Allocator.Error!void {
        if (self.input.reached) |reached| {
            for (reached, 0..) |visited, index| {
                if (visited) continue;
                const receipt = self.identity(@fromBackingInt(@intCast(index))) orelse continue;
                try self.next.append(self.arena, receipt);
            }
        }
        var saves: std.ArrayList(stage.Save) = .empty;
        for (self.next.items) |receipt| {
            if (receipt.instance) |instance| if (self.recordedByModule(instance)) continue;
            if (try self.pending(receipt)) |save| try saves.append(self.arena, save);
        }
        try self.moduleSaves(&saves);
        _ = try self.store.saveAll(saves.items);
    }

    /// The records of the modules whose receipts changed in this build: a module with no record under this build's signature and file, or
    /// with a function the record did not admit. Each holds the receipt of every function the build lowered or restored.
    fn moduleSaves(self: *Context, saves: *std.ArrayList(stage.Save)) std.mem.Allocator.Error!void {
        const prepared = self.input.prepared orelse return;
        if (prepared.grouping.modules.len == 0) return;
        const slots = try self.arena.alloc(u32, prepared.grouping.module_of.len);
        @memset(slots, no_receipt);
        for (self.next.items, 0..) |receipt, at| if (receipt.instance) |instance| {
            if (instance < slots.len) slots[instance] = @intCast(at);
        };
        for (prepared.grouping.modules) |group| {
            const previous = self.read.modules.get(group.module);
            if (previous != null and allHeld(previous.?.held)) continue;
            const digest = self.moduleKey(group) orelse continue;
            const members = try self.arena.alloc(Member, group.members.len);
            for (group.members, members) |instance, *member| {
                const at = slots[instance];
                member.* = if (at == no_receipt)
                    .{ .present = false, .value = .{ .kind = .@"unreachable" } }
                else
                    .{ .present = true, .value = .{ .kind = self.next.items[at].kind, .sources = self.next.items[at].sources } };
            }
            // A function that never has a receipt keeps its module record from being all held; the record is not written again for it. A
            // module nobody asked about this build (no function of it stood in) is compared with the store's record, as `pending` does.
            if (previous) |read| {
                if (sameMembers(read.members, members)) continue;
            } else if (try self.store.contains(digest)) {
                if (try self.store.loadValue(self.arena, digest, ModuleValue)) |stored| if (sameMembers(stored.members, members)) continue;
            }
            var writer = language.persist_codec.Writer.init(self.arena);
            try writer.write(ModuleValue, .{ .members = members });
            try saves.append(self.arena, .{ .key = digest, .payload = writer.bytes.items });
        }
    }

    /// The record of `receipt` to write, or null when the store already holds this value under its key. A record this build
    /// read is compared with what it read; a record it did not read is compared with the store only when one is catalogued,
    /// so a fresh receipt costs a write and an unchanged one none.
    fn pending(self: *Context, receipt: Receipt) std.mem.Allocator.Error!?stage.Save {
        const digest = self.recordKey(receipt.key, receipt.context, receipt.region) orelse return null;
        const value: Value = .{ .kind = receipt.kind, .sources = receipt.sources };
        if (self.read.receipts.get(digest)) |known| if (known) |stored| if (sameValue(stored, value)) return null;
        if (try self.store.contains(digest)) {
            if (try self.store.loadValue(self.arena, digest, Value)) |stored| if (sameValue(stored, value)) return null;
        }
        var writer = language.persist_codec.Writer.init(self.arena);
        try writer.write(Value, value);
        return .{ .key = digest, .payload = writer.bytes.items };
    }
};

/// `held` and `given` as one proof per file, the longer prefix where both name a file. The result and the paths in it belong to
/// `arena`: the caller's proofs may live in memory it frees before the receipt is published (a restored artifact's, decoded in a
/// scratch arena).
fn mergeProofs(arena: std.mem.Allocator, held: []const sources.Proof, given: []const sources.Proof) std.mem.Allocator.Error![]const sources.Proof {
    var combined: std.ArrayList(sources.Proof) = .empty;
    try combined.appendSlice(arena, held);
    for (given) |each| {
        var proof = each;
        proof.path = try arena.dupe(u8, each.path);
        // A proof of a longer prefix of a file holds for the shorter one as well, so one proof per file is kept.
        var found = false;
        for (combined.items) |*existing| if (std.mem.eql(u8, existing.path, proof.path)) {
            found = true;
            if (existing.length < proof.length) existing.* = proof;
            break;
        };
        if (!found) try combined.append(arena, proof);
    }
    return combined.items;
}

/// The scope of the module records (`Context.moduleKey`).
const module_scope = "lowering-module-receipts-v1";
/// A function with no receipt in this build's list.
const no_receipt = std.math.maxInt(u32);

/// Whether two module records hold the same receipts.
fn sameMembers(a: []const Member, b: []const Member) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left.present != right.present) return false;
        if (left.present and !sameValue(left.value, right.value)) return false;
    }
    return true;
}

/// Whether a module record admitted every function it covers.
fn allHeld(held: []const bool) bool {
    for (held) |each| if (!each) return false;
    return true;
}

/// The scope of the receipt records (`Context.recordKey`). `v6`: the scope names the entry by its key name, not its bytes; a
/// receipt's own region, context and source proofs carry the content it depends on. `v7`: a source proof names its file by key
/// path and covers the file only as far as the receipt's last position.
const record_scope = "lowering-receipt-v7";

/// Whether two stored values name the same lowered body (or unreachable declaration) and the same source proofs.
fn sameValue(a: Value, b: Value) bool {
    switch (a.kind) {
        .lowered => |digest| switch (b.kind) {
            .lowered => |other| if (!std.mem.eql(u8, &digest, &other)) return false,
            .@"unreachable" => return false,
        },
        .@"unreachable" => switch (b.kind) {
            .lowered => return false,
            .@"unreachable" => {},
        },
    }
    if (a.sources.len != b.sources.len) return false;
    for (a.sources, b.sources) |left, right| {
        if (left.length != right.length) return false;
        if (!std.mem.eql(u8, left.path, right.path)) return false;
        if (!std.mem.eql(u8, &left.digest, &right.digest)) return false;
    }
    return true;
}

fn testDigest(n: u8) stage.Digest {
    var digest: stage.Digest = @splat(0);
    digest[0] = n;
    return digest;
}

/// A receipt context whose entry is bound to a source named `name` with the bytes `bytes`, as checking binds it.
fn boundContext(a: std.mem.Allocator, storage: *const stage.Store, name: []const u8, bytes: []const u8) std.mem.Allocator.Error!Context {
    var context = try Context.init(a, storage, false);
    context.sources.entry_name = name;
    context.sources.bind(.{ .path = name, .bytes = bytes, .line_starts = &.{} });
    return context;
}

test "a receipt key is scoped by the entry's key name and the debug policy, not by the entry's bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const first = try boundContext(a, &storage, "app/main.selka", "func main() -> int:\n    return 0\n");
    const edited = try boundContext(a, &storage, "app/main.selka", "func main() -> int:\n    return 1\n");
    const other_name = try boundContext(a, &storage, "other/main.selka", "func main() -> int:\n    return 0\n");
    var debug_bound = try Context.init(a, &storage, true);
    debug_bound.sources.entry_name = "app/main.selka";
    debug_bound.sources.bind(.{ .path = "app/main.selka", .bytes = "func main() -> int:\n    return 0\n", .line_starts = &.{} });
    const key = first.recordKey("f", testDigest(1), testDigest(2)).?;
    // The entry's bytes are not in the scope: the receipts of its unchanged functions survive an edit to the entry. A
    // receipt's own inputs carry what it depends on (its region, its context and the proofs of its spans).
    try std.testing.expectEqualSlices(u8, &key, &edited.recordKey("f", testDigest(1), testDigest(2)).?);
    try std.testing.expect(!std.mem.eql(u8, &key, &other_name.recordKey("f", testDigest(1), testDigest(2)).?));
    try std.testing.expect(!std.mem.eql(u8, &key, &debug_bound.recordKey("f", testDigest(1), testDigest(2)).?));
    const unbound = try Context.init(a, &storage, false);
    try std.testing.expectEqual(@as(?stage.Digest, null), unbound.recordKey("f", testDigest(1), testDigest(2)));
}

test "a receipt is written once: a build writes only the receipts the store does not hold with the same value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var first = try boundContext(a, &storage, "main.selka", "main");
    try first.next.append(a, .{ .key = "f", .context = testDigest(1), .region = testDigest(2), .kind = .{ .lowered = testDigest(3) } });
    try first.next.append(a, .{ .key = "g", .context = testDigest(1), .region = testDigest(2), .kind = .@"unreachable" });
    try first.finish();
    const written = storage.statistics().publication.records_saved;
    try std.testing.expectEqual(@as(u64, 2), written);
    // The same receipts again: the store holds both with the same value, so nothing is written.
    var again = try boundContext(a, &storage, "main.selka", "main");
    try again.next.append(a, .{ .key = "f", .context = testDigest(1), .region = testDigest(2), .kind = .{ .lowered = testDigest(3) } });
    try again.next.append(a, .{ .key = "g", .context = testDigest(1), .region = testDigest(2), .kind = .@"unreachable" });
    try again.finish();
    try std.testing.expectEqual(written, storage.statistics().publication.records_saved);
    // A changed lowered body under the same inputs is a new value: its record is written again.
    var changed = try boundContext(a, &storage, "main.selka", "main");
    try changed.next.append(a, .{ .key = "f", .context = testDigest(1), .region = testDigest(2), .kind = .{ .lowered = testDigest(4) } });
    try changed.finish();
    try std.testing.expectEqual(written + 1, storage.statistics().publication.records_saved);
    // The same name with different bytes is a different scope, so the same receipt is not held for it.
    var other = try boundContext(a, &storage, "main.selka", "main, edited");
    try other.next.append(a, .{ .key = "f", .context = testDigest(1), .region = testDigest(2), .kind = .{ .lowered = testDigest(3) } });
    try other.finish();
    try std.testing.expectEqual(written + 2, storage.statistics().publication.records_saved);
}

/// A program of one module `m` with two ordinary functions, `f` and `g`, as the planner groups it.
const TwoFunctions = struct {
    keys: [2][]const u8 = .{ "fn\x1fm\x1f\x1ff", "fn\x1fm\x1f\x1fg" },
    contexts: [2][32]u8 = .{ testDigest(1), testDigest(2) },
    digests: [2][32]u8 = .{ testDigest(3), testDigest(4) },
    ordinary: [2]usize = .{ 0, 1 },
    members: [2]u32 = .{ 0, 1 },
    module_of: [2]u32 = .{ 0, 0 },
    ordinal_of: [2]u32 = .{ 0, 1 },
    groups: [1]language.semantic_key.ModuleGroup = undefined,

    fn prepared(self: *TwoFunctions, signature: stage.Digest, file: stage.Digest) language.semantic_summary.Prepared {
        self.groups[0] = .{ .module = "m", .path = "m.selka", .file = file, .signature = signature, .members = &self.members };
        const grouping: language.semantic_key.Grouping = .{ .modules = &self.groups, .module_of = &self.module_of, .ordinal_of = &self.ordinal_of };
        return .{
            .bodies = &.{},
            .regions = &.{},
            .keys = &self.keys,
            .contexts = &self.contexts,
            .ordinary_ast = &self.ordinary,
            .recalled = .{ .digests = &self.digests },
            .grouping = grouping,
        };
    }
};

test "G2p a module's receipts are one record found by the module's signature and file, and a foreign proof that no longer holds is a miss for its function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var program: TwoFunctions = .{};
    var first = try boundContext(a, &storage, "main.selka", "main");
    first.attach(program.prepared(testDigest(8), testDigest(9)), &.{});
    // `f` was lowered with a proof of its own file; `g` with one of another file, which the bound source does not hold.
    try first.record(@fromBackingInt(0), testDigest(5));
    try first.addSources(@fromBackingInt(0), &.{.{ .path = "m.selka", .length = 3, .digest = testDigest(6) }});
    try first.record(@fromBackingInt(1), testDigest(7));
    try first.addSources(@fromBackingInt(1), &.{.{ .path = "other.selka", .length = 3, .digest = testDigest(6) }});
    try first.finish();
    const written = storage.statistics().publication.records_saved;
    // 2 receipts and the module's record.
    try std.testing.expectEqual(@as(u64, 3), written);
    var again = try boundContext(a, &storage, "main.selka", "main");
    var out = [2]bool{ false, false };
    try std.testing.expect(again.readModule(program.groups[0], &out));
    try std.testing.expectEqualSlices(bool, &.{ true, false }, &out);
    // Another signature, another file: no record.
    var moved = try boundContext(a, &storage, "main.selka", "main");
    var none = [2]bool{ false, false };
    var other = program.groups[0];
    other.signature = testDigest(10);
    try std.testing.expect(!moved.readModule(other, &none));
    other = program.groups[0];
    other.file = testDigest(11);
    try std.testing.expect(!moved.readModule(other, &none));
    try std.testing.expectEqualSlices(bool, &.{ false, false }, &none);
    // The function receipts a module record covers are not written again, and an unchanged build writes nothing.
    var repeat = try boundContext(a, &storage, "main.selka", "main");
    repeat.attach(program.prepared(testDigest(8), testDigest(9)), &.{ true, false });
    var again_out = [2]bool{ false, false };
    try std.testing.expect(repeat.readModule(program.groups[0], &again_out));
    try repeat.record(@fromBackingInt(0), testDigest(5));
    try repeat.record(@fromBackingInt(1), testDigest(7));
    try repeat.addSources(@fromBackingInt(1), &.{.{ .path = "other.selka", .length = 3, .digest = testDigest(6) }});
    try repeat.finish();
    try std.testing.expectEqual(written, storage.statistics().publication.records_saved);
}

test "a damaged receipt reads as absent, so its function is lowered again" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var context = try boundContext(a, &storage, "main.selka", "main");
    _ = try storage.save(context.recordKey("f", testDigest(1), testDigest(2)).?, "damaged");
    try std.testing.expect(context.lookup("f", testDigest(1), testDigest(2)) == null);
}

test "merged proofs keep one proof per file, the longer, and a copy of each path the caller may free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scratch = [_]u8{ 'l', 'i', 'b', '.', 's', 'e', 'l', 'k', 'a' };
    const given: []const sources.Proof = &.{.{ .path = &scratch, .length = 10, .digest = testDigest(1) }};
    const first = try mergeProofs(a, &.{}, given);
    @memset(&scratch, 'x');
    try std.testing.expectEqualStrings("lib.selka", first[0].path);
    const longer: []const sources.Proof = &.{ .{ .path = "lib.selka", .length = 30, .digest = testDigest(2) }, .{ .path = "other.selka", .length = 5, .digest = testDigest(3) } };
    const second = try mergeProofs(a, first, longer);
    try std.testing.expectEqual(@as(usize, 2), second.len);
    try std.testing.expectEqual(@as(u32, 30), second[0].length);
    try std.testing.expectEqual(testDigest(2), second[0].digest);
    try std.testing.expectEqualStrings("other.selka", second[1].path);
}

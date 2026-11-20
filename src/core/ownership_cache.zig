//! Successful ownership checks share semantic function identities. A body is
//! omitted only after the semantic planner validates its dependencies and this
//! cache proves that the same body passed the selected ownership contract.
//!
//! The proofs are the engine's: one `ownership-proof` record for each module of an entry (`ownership_proofs.zig`), a table of
//! the digests of the inputs each function was checked under. A function is proven while the record holds the digest this run
//! computed from its own planning state, so a stale record cannot be served for it. The cache decides and publishes; the store of
//! packs it replaced is gone.
const std = @import("std");
const language = @import("selka");
const contract = @import("single_owner.zig");
const lowering = @import("lowering_cache.zig");
const facts = @import("ownership_proof_facts.zig");
const proofs_rules = @import("ownership_proofs.zig");
const engine_command = @import("engine/command.zig");
const entry_name = @import("entry_name.zig");

/// The digest type of a receipt's parts.
const Digest = [32]u8;

const Receipt = struct {
    key: []const u8,
    context: Digest,
    region: Digest,
};

/// Actual ownership work, separate from semantic body checking.
pub const Work = struct { checked: usize = 0, reused: usize = 0 };

/// The scope the proofs of the entry file at `path` are kept under: its realpath relative to the project root (the directory of the
/// nearest `selka.json` above it, else the working directory), never the spelling the command gave (`entry_name.zig`). The same
/// project checked from another worktree, or by an absolute path, then finds the proofs the first check made (G4c, spec G-D11).
pub fn scopeOf(a: std.mem.Allocator, io: std.Io, path: []const u8) error{OutOfMemory}![]const u8 {
    const configured = language.project_config.discover(a, io, path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    const root = if (configured) |found| std.fs.path.dirname(found) orelse "" else "";
    return entry_name.of(a, io, root, path);
}

/// Whether the receipt route of a session that keeps every tree is on (`Cache.configure`): unless `SELKA_OWNERSHIP_RECEIPTS` is `0`.
pub fn receiptsFrom(environment: *const std.process.Environ.Map) bool {
    const value = environment.get("SELKA_OWNERSHIP_RECEIPTS") orelse return true;
    return !std.mem.eql(u8, value, "0");
}

/// Stable mode identity shared by ownership proofs and frontend verdicts.
pub const modeName = @import("ownership_mode.zig").name;

/// One entry's successful functions. The arena and semantic request outlive validation; the proofs belong to the engine.
pub const Cache = struct {
    arena: std.mem.Allocator,
    /// The engine's proofs of this work directory, null when the engine could not start (every function is then checked).
    proofs: ?*proofs_rules.Proofs,
    /// The entry the proofs are scoped to, empty before `open` names one.
    entry: []const u8 = "",
    /// Proofs whose semantic callback this build reached: only those may omit a body (`selectConcrete`).
    validated: std.AutoHashMapUnmanaged(Digest, void) = .empty,
    policy: struct {
        request: ?*language.semantic_summary.Request = null,
        downstream: ?language.semantic_summary.Demand = null,
        subjects: []facts.Subject = &.{},
        /// Verify mode checks one proven function in this many anyway (one whose body is present: a body the planner stood in
        /// for is not materialized), and a refusal of one is an internal error; 0 turns it off.
        verify_every: u32 = 0,
        /// Whether a session with no lowering host that keeps every tree still finds held proofs by their receipts
        /// (`configure`); `SELKA_OWNERSHIP_RECEIPTS=0` turns it off, the oracle the route is tested against.
        receipts: bool = true,
        /// Set by `configure` for such a session: the planner is asked about every unchanged body, so a receipt can be formed,
        /// but `allows` lets none be left out.
        keep_trees: bool = false,
        /// The judgments of generic templates at their declaration this run asked about (W3 step 2, `judged`).
        templates: Templates = .{},
    } = .{},
    work: Work = .{},
    /// The general-purpose allocator the cache was opened with: `validate` makes each function's transient ownership work in it
    /// (`single_owner.Every.work`), since the allocator a caller passes is often an arena.
    backing: std.mem.Allocator,

    /// The proofs of the work directory `root`, in the engine's store beside the other records.
    pub fn init(arena: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, root: []const u8) error{OutOfMemory}!Cache {
        return .{ .arena = arena, .backing = backing, .proofs = proofs_rules.Proofs.open(backing, io, root) };
    }

    /// Release the engine; proof memory belongs to the caller arena.
    pub fn deinit(self: *Cache) void {
        if (self.proofs) |proofs| proofs.close();
        self.proofs = null;
    }

    /// Share the proofs through the compiler store at `directory`, when there is one (G4c, `engine_sharing.zig`).
    pub fn share(self: *Cache, directory: ?[]const u8) void {
        if (self.proofs) |proofs| proofs.share(directory);
    }

    /// Set verify mode from the environment: `SELKA_ENGINE_VERIFY`, and one in 64 in a Debug compiler; and the receipt route of a
    /// session that keeps every tree (`SELKA_OWNERSHIP_RECEIPTS`, on unless `0`).
    pub fn verifyFrom(self: *Cache, environment: *const std.process.Environ.Map) void {
        self.policy.verify_every = engine_command.verifyEvery(environment);
        self.policy.receipts = receiptsFrom(environment);
    }

    /// A different entry never inherits another entry's omitted-function proof: the entry names the scope of its proofs.
    pub fn open(self: *Cache, entry: []const u8) error{OutOfMemory}!void {
        self.entry = try self.arena.dupe(u8, entry);
        self.validated.clearRetainingCapacity();
    }

    /// The proofs, once an entry is open.
    fn live(self: *const Cache) ?*proofs_rules.Proofs {
        return if (self.entry.len == 0) null else self.proofs;
    }

    /// Whether verify mode checks a function whose proof is held under `digest` anyway.
    fn sampled(self: *const Cache, digest: Digest) bool {
        return self.policy.verify_every != 0 and std.mem.readInt(u32, digest[0..4], .little) % self.policy.verify_every == 0;
    }

    /// Validation needs ownership proof alone; a build additionally needs its
    /// lowering host's artifact proof. Without either route, keep full trees.
    pub fn configure(self: *Cache, request: *language.semantic_summary.Request, downstream: ?language.semantic_summary.Demand, validation_only: bool) void {
        self.policy.request = request;
        self.policy.templates = .{};
        if (downstream) |demand| {
            if (demand.context != @as(*const anyopaque, self)) self.policy.downstream = demand;
        } else self.policy.downstream = null;
        request.body_policy = .concrete;
        // A session with no lowering host that validates as well as lowers (a test run's check, a build without demand) keeps every
        // tree. It still asks the planner about each unchanged body, which forms the body's receipt (its prepared key, dependency
        // context and region) once the planner has held its summary against its dependencies; a proof held under that receipt is
        // reused as `check` reuses it, and no body is left out (`allows`, `Policy.restores_trees`). A function whose receipt the
        // planner does not form is proven by its tree's reach digest, as before.
        self.policy.keep_trees = downstream == null and !validation_only;
        if (self.policy.keep_trees and !self.policy.receipts) return;
        if (self.policy.keep_trees) request.policy.restores_trees = true;
        request.policy.demand = .{
            .context = self,
            .allow = allows,
            .allow_module = if (self.policy.keep_trees) null else allowsModule,
            .prepare_sources = prepareSources,
            .judged = judged,
            .body_dependencies = if (self.policy.downstream) |demand| demand.body_dependencies else false,
            .facts_unread = if (self.policy.downstream) |demand| demand.facts_unread else false,
            .allocation_contracts = if (self.policy.downstream) |demand| demand.allocation_contracts else (!validation_only and !self.policy.keep_trees),
        };
    }

    fn prepareSources(pointer: *const anyopaque, source: language.source.Source) error{OutOfMemory}!void {
        const self: *Cache = @ptrCast(@alignCast(@constCast(pointer)));
        self.validated.clearRetainingCapacity();
        if (self.policy.downstream) |downstream| if (downstream.prepare_sources) |prepare| try prepare(downstream.context, source);
    }

    /// Whether the judgment of the generic template keyed `key` at its declaration is proven under the inputs this run computed
    /// (W3 step 2): a proof part of the template's module under `key` and the receipt digest of `dependency` (the template's
    /// context folded with the judgment's rule) and `region`. The proof is the one `remember` publishes after a check that
    /// passed, so a template is proven only when every stand-in of it was accepted. A template not held, and one verify mode
    /// samples, is judged; the second is remembered so that its refusal is `E_ENGINE_VERIFY`.
    fn judged(pointer: *const anyopaque, key: []const u8, dependency: Digest, region: Digest) bool {
        const self: *Cache = @ptrCast(@alignCast(@constCast(pointer)));
        const proofs = self.live() orelse return false;
        const module = facts.moduleOfKey(key) orelse return false;
        const digest = facts.receiptDigest(key, dependency, region);
        const held = proofs.held(self.entry, module, key, digest) == .same;
        self.policy.templates.asked.append(self.arena, .{ .module = module, .ident = key, .digest = digest, .held = held }) catch return false;
        if (!held) return false;
        if (self.sampled(digest)) {
            self.policy.templates.sampled.append(self.arena, key) catch return false;
            return false;
        }
        return true;
    }

    fn allows(pointer: *const anyopaque, key: []const u8, dependency: Digest, region: Digest) bool {
        const self: *Cache = @ptrCast(@alignCast(@constCast(pointer)));
        const proofs = self.live() orelse return false;
        const module = facts.moduleOfKey(key) orelse return false;
        const digest = facts.receiptDigest(key, dependency, region);
        if (proofs.held(self.entry, module, key, digest) != .same) return false;
        // This callback is reached only after semantic dependency, touched-shape
        // and consumer checks; validation-only fact changes force a full retry.
        // Ownership may reuse the proof when lowering needs a concrete tree.
        self.validated.put(self.arena, digest, {}) catch return false;
        if (self.policy.keep_trees) return false;
        if (self.policy.downstream) |downstream| return downstream.allow(downstream.context, key, dependency, region);
        return true;
    }

    /// The answer for a whole module: the functions the module's marker says were proven under its signature, which the downstream host also
    /// admits. A marker is the proof record's own statement that each function it names holds a proof under the digest this signature gives it,
    /// so a set bit is what `allows` would answer for that function.
    fn allowsModule(pointer: *const anyopaque, group: language.semantic_key.ModuleGroup, out: []bool) bool {
        const self: *Cache = @ptrCast(@alignCast(@constCast(pointer)));
        const proofs = self.live() orelse return false;
        if (!proofs.heldModule(self.entry, group.module, group.signature, out)) return false;
        const downstream = self.policy.downstream orelse return true;
        const ask = downstream.allow_module orelse return false;
        const other = self.arena.alloc(bool, out.len) catch return false;
        @memset(other, false);
        if (!ask(downstream.context, group, other)) return false;
        for (out, other) |*bit, also| bit.* = bit.* and also;
        return true;
    }

    /// Cache only successes. Refusals are freshly rendered with current source
    /// locations and fixes; missing or damaged proofs merely force body checks.
    pub fn validate(self: *Cache, a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{ OutOfMemory, InternalError }!bool {
        const selected = try a.alloc(bool, program.functions.len);
        defer a.free(selected);
        @memset(selected, true);
        if (self.policy.request) |request| if (request.policy.demand) |demand| {
            // Only this cache's callback authorizes ownership omission.
            if (demand.context == @as(*const anyopaque, self)) for (demand.omitted, 0..) |omitted, index| {
                if (index < selected.len and omitted) selected[index] = false;
            };
        };
        try self.selectConcrete(program, selected);
        self.work = .{};
        for (selected) |check| {
            if (check) self.work.checked += 1 else self.work.reused += 1;
        }
        var every: contract.Every = .{ .work = self.backing };
        try contract.checkEvery(a, program, selected, source, &every);
        if (every.failures.items.len != 0) {
            if (try self.sampledTemplateRefused(program, every.rejected.items)) |name| {
                try report.print(a, "error[E_ENGINE_VERIFY]: ownership-proof: the judgment of the generic body of {s} was refused although a proof of it was recorded under the digest this run computed\n", .{name});
                return error.InternalError;
            }
            for (every.rejected.items) |at| if (at < self.policy.subjects.len and self.policy.subjects[at].sampled) {
                try report.print(a, "error[E_ENGINE_VERIFY]: ownership-proof: the check of {s} was refused although a proof of it was recorded under the digest this run computed\n", .{program.functions[at].name});
                return error.InternalError;
            };
            try contract.judgeStandIns(a, program, source, &every);
            try contract.renderEvery(a, source, &every, format, report);
            return false;
        }
        self.remember(a);
        return true;
    }

    /// Stubbable ordinary functions already have a semantic body digest. A full
    /// retry clears the demand policy, so earlier callback admissions cannot leak
    /// into a request whose cross-function facts invalidated the plan.
    fn semanticReceipt(self: *const Cache, index: usize) ?Receipt {
        const request = self.policy.request orelse return null;
        const demand = request.policy.demand orelse return null;
        if (demand.context != @as(*const anyopaque, self)) return null;
        const prepared = request.prepared orelse return null;
        const produced = request.produced orelse return null;
        if (index >= prepared.ordinary_ast.len or index >= produced.summaries.len) return null;
        if (!produced.summaries[index].stubbable) return null;
        const ast = prepared.ordinary_ast[index];
        if (!std.mem.eql(u8, produced.summaries[index].key, prepared.keys[ast])) return null;
        return .{ .key = prepared.keys[ast], .context = prepared.contexts[ast], .region = prepared.recalled.digests[ast] };
    }

    /// Complete trees need no omission proof. This also caches main, generic
    /// instances, headerless programs and library checks without summaries. Every function that has a proof input digest gets a
    /// subject (`policy.subjects`), checked or not; a function with a semantic receipt is omitted when the planner admitted it
    /// and the record holds its digest, any other when the record holds the digest of its body and reach.
    fn selectConcrete(self: *Cache, program: language.typed.Program, selected: []bool) error{OutOfMemory}!void {
        self.policy.subjects = try self.arena.alloc(facts.Subject, program.functions.len);
        @memset(self.policy.subjects, .{});
        const proofs = self.live() orelse return;
        var reach: ?lowering.OwnershipReach = null;
        var scratch = std.heap.ArenaAllocator.init(proofs.machine.gpa);
        defer scratch.deinit();
        var repeats: std.StringHashMapUnmanaged(u32) = .empty;
        for (program.functions, selected, self.policy.subjects, 0..) |function, *check, *subject, index| {
            if (!check.*) continue;
            if (self.semanticReceipt(index)) |receipt| {
                const module = facts.moduleOfKey(receipt.key) orelse continue;
                const digest = facts.receiptDigest(receipt.key, receipt.context, receipt.region);
                subject.* = .{ .module = module, .ident = receipt.key, .digest = digest, .receipt = true };
                if (!self.validated.contains(digest)) continue;
                if (proofs.held(self.entry, module, receipt.key, digest) != .same) continue;
                subject.held = true;
                if (self.sampled(digest)) subject.sampled = true else check.* = false;
                continue;
            }
            if (reach == null) reach = try lowering.OwnershipReach.init(self.arena, program);
            _ = scratch.reset(.retain_capacity);
            const found = reach.?.digest(scratch.allocator(), function) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const whole = found orelse continue;
            const times = try repeats.getOrPut(self.arena, function.name);
            times.value_ptr.* = if (times.found_existing) times.value_ptr.* + 1 else 1;
            const ident = if (times.value_ptr.* == 1)
                try std.fmt.allocPrint(self.arena, "{s}{s}", .{ facts.typed_prefix, function.name })
            else
                try std.fmt.allocPrint(self.arena, "{s}{s}#{d}", .{ facts.typed_prefix, function.name, times.value_ptr.* });
            const digest = facts.reachDigest(function.name, whole);
            const module = facts.moduleOf(function.name);
            subject.* = .{ .module = module, .ident = ident, .digest = digest };
            if (proofs.held(self.entry, module, ident, digest) != .same) continue;
            subject.held = true;
            if (self.sampled(digest)) subject.sampled = true else check.* = false;
        }
    }

    /// Record the proof of every function this build proved that the record does not hold yet: the groups whose table the run
    /// changes are published, and an unchanged build writes nothing.
    /// The name of a template verify mode sampled whose generic instance the check refused: a judgment held under this run's
    /// inputs that no longer holds. A refused instance names its template by its declaration, which lies in the template's
    /// declaration region.
    fn sampledTemplateRefused(self: *const Cache, program: language.typed.Program, rejected: []const usize) error{OutOfMemory}!?[]const u8 {
        if (self.policy.templates.sampled.items.len == 0) return null;
        const request = self.policy.request orelse return null;
        const prepared = request.prepared orelse return null;
        for (rejected) |index| {
            if (index >= program.functions.len or program.functions[index].type_arguments.len == 0) continue;
            const at = program.functions[index].declaration;
            for (prepared.regions, prepared.keys) |region, key| {
                if (at.start < region.start or at.end > region.end) continue;
                for (self.policy.templates.sampled.items) |sampled_key| if (std.mem.eql(u8, sampled_key, key)) return program.functions[index].name;
            }
        }
        return null;
    }

    fn remember(self: *Cache, a: std.mem.Allocator) void {
        const proofs = self.live() orelse return;
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        const added = self.markers(scratch.allocator(), proofs) catch return;
        // The check passed, so every template it judged had every stand-in accepted: its judgment is proven (W3 step 2).
        const subjects = std.mem.concat(scratch.allocator(), facts.Subject, &.{ self.policy.subjects, self.policy.templates.asked.items }) catch return;
        const groups = facts.groupsWith(scratch.allocator(), self.entry, subjects, added) catch return;
        proofs.publish(scratch.allocator(), self.entry, groups);
    }

    /// The module markers this build adds: for each module of the program whose record does not yet say what this build proved of it, the
    /// functions that were proven (left out because their proof was held, or checked and passed now) under the module's signature. Every
    /// function of a build that reaches here passed the check, so a function with a receipt digest is proven.
    fn markers(self: *Cache, a: std.mem.Allocator, proofs: *proofs_rules.Proofs) std.mem.Allocator.Error![]const facts.Marker {
        const request = self.policy.request orelse return &.{};
        const prepared = request.prepared orelse return &.{};
        const demand = request.policy.demand orelse return &.{};
        const omitted_here = demand.context == @as(*const anyopaque, self);
        var found: std.ArrayList(facts.Marker) = .empty;
        for (prepared.grouping.modules) |group| {
            const proven = try a.alloc(bool, group.members.len);
            var any = false;
            for (group.members, proven) |instance, *bit| {
                const subject = if (instance < self.policy.subjects.len) self.policy.subjects[instance] else facts.Subject{};
                const left_out = omitted_here and instance < demand.omitted.len and demand.omitted[instance];
                bit.* = left_out or (subject.receipt and subject.digest != null);
                any = any or bit.*;
            }
            if (!any) continue;
            const known = try a.alloc(bool, group.members.len);
            if (proofs.heldModule(self.entry, group.module, group.signature, known) and covers(known, proven)) continue;
            try found.append(a, .{ .module = group.module, .part = try facts.markerName(a, group.signature, proven), .digest = group.signature });
        }
        return found.items;
    }
};

/// The generic templates a check asked to judge at their declaration, and those verify mode sampled (W3 step 2).
const Templates = struct {
    /// Each template asked about, as a proof subject: published after a check that passed (`remember`).
    asked: std.ArrayList(facts.Subject) = .empty,
    /// The stable keys of the templates whose held proof verify mode judged anyway.
    sampled: std.ArrayList([]const u8) = .empty,
};

/// Whether every member `proven` marks is also marked in `known`.
fn covers(known: []const bool, proven: []const bool) bool {
    for (known, proven) |have, want| if (want and !have) return false;
    return true;
}

test "G4c an entry is scoped by its path under the project's selka.json, whichever way the command spells it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "project/app");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "project/selka.json", .data = "{\"version\": 1}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "project/app/main.selka", .data = "func main() -> int:\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, "project", a);
    const direct = try std.fs.path.join(a, &.{ root, "app", "main.selka" });
    const detour = try std.fs.path.join(a, &.{ root, "app", "..", "app", "main.selka" });
    try std.testing.expectEqualStrings("app/main.selka", try scopeOf(a, std.testing.io, direct));
    try std.testing.expectEqualStrings("app/main.selka", try scopeOf(a, std.testing.io, detour));
}

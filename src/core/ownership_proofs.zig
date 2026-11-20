//! The ownership cache's proofs on the engine (part 2, G1c; spec §14, §17.2): the `ownership-proof` records of one work
//! directory, read a module at a time and replaced when a run proves something new.
//!
//! A group is the record of one module under one entry: a table of proofs (`ownership_proof_facts`). The first question about a
//! module reads its record (`Engine.peek`, which never computes), and the table is kept for the rest of the process, so a run
//! costs one record open for each module it asks about. A question is whether the table holds a proof of one function under the
//! digest the caller computed in this run; the table is never asked for a digest to stand for one. After a check that passed, a
//! group whose table differs from the one the record holds is published (`Engine.forget` and a query that runs the kind, which
//! returns the answer handed to it here).
const std = @import("std");
const engine = @import("engine/engine.zig");
const engine_kinds = @import("engine/kinds.zig");
const engine_sharing = @import("engine_sharing.zig");
const compiler_records = @import("engine/compiler_records.zig");
const context_rules = @import("engine/context.zig");
const os_world = @import("engine/os_world.zig");
const record = @import("engine/record.zig");
const proof_kind = @import("engine/kinds/ownership_proof.zig");
const facts = @import("ownership_proof_facts.zig");

/// The machine the engine reads: an environment of its own, which the kind never consults.
const Machine = struct { gpa: std.mem.Allocator, io: std.Io, environment: std.process.Environ.Map, os: os_world.OsWorld, work: []const u8, records: ?compiler_records.Records = null };

/// A group's argument and its table as this process last saw it.
const Slot = struct { argument: []const u8, parts: []const record.Part };

/// The answer being published, for the one argument it belongs to.
const Pending = struct { argument: []const u8, answer: proof_kind.Answer };

/// The proofs of one work directory. Heap-allocated: the engine points into it and must not move.
pub const Proofs = struct {
    machine: Machine,
    runner: engine.Engine,
    kind: context_rules.Kind,
    source: proof_kind.Source,
    /// The answer for the argument being published, null at every other time.
    pending: ?Pending = null,
    /// The groups this process has read or published, by `entry`, a zero byte and the module.
    groups: std.StringHashMapUnmanaged(Slot) = .empty,
    /// The buffer part names are built in.
    scratch: std.ArrayList(u8) = .empty,

    /// The proofs under `work`, or null when the engine cannot start.
    pub fn open(gpa: std.mem.Allocator, io: std.Io, work: []const u8) ?*Proofs {
        const self = gpa.create(Proofs) catch return null;
        const kept = gpa.dupe(u8, work) catch {
            gpa.destroy(self);
            return null;
        };
        self.* = .{
            .machine = .{ .gpa = gpa, .io = io, .environment = .init(gpa), .os = undefined, .work = kept },
            .runner = undefined,
            .kind = engine_kinds.ownership_proof,
            .source = .{ .context = self, .answer = answerFor },
        };
        self.machine.os = .{ .io = io, .environment = &self.machine.environment, .work = kept };
        self.kind.data = &self.source;
        self.runner = engine.Engine.init(gpa, io, self.machine.os.world(), .{ .work = kept }) catch return abandon(self);
        self.runner.register(&self.kind) catch {
            self.runner.deinit();
            return abandon(self);
        };
        return self;
    }

    /// Share the proofs across worktrees through the compiler store at `directory`, when there is one: another tree's record for a
    /// module is read and validated here exactly as a local one is, and a record this run publishes is offered to the others. Call
    /// it before the first question.
    pub fn share(self: *Proofs, directory: ?[]const u8) void {
        if (self.machine.records != null) return;
        self.machine.records = engine_sharing.open(self.machine.gpa, self.machine.io, directory);
        const records = if (self.machine.records) |*opened| opened else return;
        self.runner.setShared(records.tier());
        self.runner.share(&self.kind, null);
    }

    fn abandon(self: *Proofs) ?*Proofs {
        const gpa = self.machine.gpa;
        self.machine.environment.deinit();
        gpa.free(self.machine.work);
        gpa.destroy(self);
        return null;
    }

    /// Free everything.
    pub fn close(self: *Proofs) void {
        const gpa = self.machine.gpa;
        var slots = self.groups.iterator();
        while (slots.next()) |slot| {
            gpa.free(slot.key_ptr.*);
            gpa.free(slot.value_ptr.argument);
        }
        self.groups.deinit(gpa);
        self.scratch.deinit(gpa);
        self.runner.deinit();
        if (self.machine.records) |*records| records.deinit();
        self.machine.environment.deinit();
        gpa.free(self.machine.work);
        gpa.destroy(self);
    }

    /// What the record of `module` under `entry` holds for the function `ident` under `digest`. A module the record does not
    /// know, and any failure of the engine, hold nothing.
    pub fn held(self: *Proofs, entry: []const u8, module: []const u8, ident: []const u8, digest: [32]u8) facts.Held {
        const slot = self.group(entry, module) orelse return .absent;
        const gpa = self.machine.gpa;
        return facts.held(slot.parts, &self.scratch, gpa, ident, digest) catch .absent;
    }

    /// Which functions of `module` the record of `entry` says were proven under the module signature `signature` (G2p): `out[i]` is set for
    /// each member `i` a marker names. False when the record holds no marker for the signature, and `out` is then untouched.
    pub fn heldModule(self: *Proofs, entry: []const u8, module: []const u8, signature: [32]u8, out: []bool) bool {
        const slot = self.group(entry, module) orelse return false;
        return facts.heldMarkers(slot.parts, &self.scratch, self.machine.gpa, signature, out) catch false;
    }

    /// The group of `module` under `entry`, read from the engine on the first question about it.
    fn group(self: *Proofs, entry: []const u8, module: []const u8) ?*Slot {
        const gpa = self.machine.gpa;
        var buffer: [512]u8 = undefined;
        const heap = entry.len + module.len + 1 > buffer.len;
        const key = if (heap) std.fmt.allocPrint(gpa, "{s}\x00{s}", .{ entry, module }) catch return null else std.fmt.bufPrint(&buffer, "{s}\x00{s}", .{ entry, module }) catch return null;
        defer if (heap) gpa.free(key);
        if (self.groups.getPtr(key)) |known| return known;
        const argument = facts.argumentOf(gpa, entry, module) catch return null;
        const asked = self.runner.peek(&self.kind, argument) catch null;
        const parts: []const record.Part = if (asked) |answer| answer.result.parts else &.{};
        const owned = gpa.dupe(u8, key) catch {
            gpa.free(argument);
            return null;
        };
        self.groups.put(gpa, owned, .{ .argument = argument, .parts = parts }) catch {
            gpa.free(owned);
            gpa.free(argument);
            return null;
        };
        return self.groups.getPtr(owned);
    }

    /// Publish what a run proved: for each of `groups` whose table, merged with the record's, differs from the record's, replace
    /// the record. A failure leaves the old record, which is as valid as it was.
    pub fn publish(self: *Proofs, a: std.mem.Allocator, entry: []const u8, runs: []const facts.Group) void {
        for (runs) |run| {
            const module = facts.moduleOfArgument(run.argument);
            const slot = self.group(entry, module) orelse continue;
            const answer = facts.answerOf(a, run, slot.parts) catch continue;
            if (facts.sameParts(slot.parts, answer.parts)) continue;
            self.runner.forget(&self.kind, slot.argument);
            self.pending = .{ .argument = slot.argument, .answer = answer };
            defer self.pending = null;
            const stored = self.runner.answer(&self.kind, slot.argument) catch continue;
            slot.parts = stored.result.parts;
        }
    }
};

fn answerFor(raw: *anyopaque, argument: []const u8) ?proof_kind.Answer {
    const self: *Proofs = @ptrCast(@alignCast(raw));
    const pending = self.pending orelse return null;
    return if (std.mem.eql(u8, pending.argument, argument)) pending.answer else null;
}

test "a group published by one process is held by the next, only under the digest it holds, and only for its entry" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const first = facts.receiptDigest("fn\x1fm\x1f\x1ff", @splat(1), @splat(1));
    const edited = facts.receiptDigest("fn\x1fm\x1f\x1ff", @splat(1), @splat(2));
    const subjects = [_]facts.Subject{.{ .module = "m", .ident = "fn\x1fm\x1f\x1ff", .digest = first }};
    const writer = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    try std.testing.expectEqual(facts.Held.absent, writer.held("app", "m", "fn\x1fm\x1f\x1ff", first));
    writer.publish(a, "app", try facts.groupsOf(a, "app", &subjects));
    try std.testing.expectEqual(facts.Held.same, writer.held("app", "m", "fn\x1fm\x1f\x1ff", first));
    writer.close();
    const reader = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer reader.close();
    try std.testing.expectEqual(facts.Held.same, reader.held("app", "m", "fn\x1fm\x1f\x1ff", first));
    // The digest this run computes is another: the record's is not taken for it.
    try std.testing.expectEqual(facts.Held.other, reader.held("app", "m", "fn\x1fm\x1f\x1ff", edited));
    try std.testing.expectEqual(facts.Held.absent, reader.held("other", "m", "fn\x1fm\x1f\x1ff", first));
}

test "G2p a module marker is published with the proofs, held under its signature in the next process, and the marker of another signature does not answer" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const signature: [32]u8 = @splat(4);
    const proof = facts.receiptDigest("fn\x1fm\x1f\x1ff", @splat(1), @splat(1));
    const subjects = [_]facts.Subject{.{ .module = "m", .ident = "fn\x1fm\x1f\x1ff", .digest = proof }};
    const markers = [_]facts.Marker{.{ .module = "m", .part = try facts.markerName(a, signature, &.{ true, false }), .digest = signature }};
    const writer = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    var out: [2]bool = @splat(false);
    try std.testing.expect(!writer.heldModule("app", "m", signature, &out));
    writer.publish(a, "app", try facts.groupsWith(a, "app", &subjects, &markers));
    try std.testing.expect(writer.heldModule("app", "m", signature, &out));
    writer.close();
    const reader = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer reader.close();
    out = @splat(false);
    try std.testing.expect(reader.heldModule("app", "m", signature, &out));
    try std.testing.expectEqualSlices(bool, &.{ true, false }, &out);
    try std.testing.expect(!reader.heldModule("app", "m", @splat(5), &out));
    try std.testing.expect(!reader.heldModule("other", "m", signature, &out));
}

/// The subject of the function `f` of module `m` in its state `tag`, proven under a digest of the state.
fn stateOf(tag: u8) facts.Subject {
    const ident = "fn\x1fm\x1f\x1ff";
    return .{ .module = "m", .ident = ident, .digest = facts.receiptDigest(ident, @splat(tag), @splat(tag)) };
}

/// The marker that says the function of `m` is proven under the module signature `tag`.
fn markerOf(a: std.mem.Allocator, tag: u8) std.mem.Allocator.Error!facts.Marker {
    return .{ .module = "m", .part = try facts.markerName(a, @splat(tag), &.{true}), .digest = @splat(tag) };
}

/// The comparison the planner makes in a Debug compiler: a module answer under the signature `tag` is never more than the answer for the
/// function it covers.
fn answerNeverExceeds(proofs: *Proofs, subject: facts.Subject, tag: u8) bool {
    var out: [1]bool = .{false};
    if (!proofs.heldModule("app", "m", @splat(tag), &out)) return true;
    return !out[0] or proofs.held("app", "m", subject.ident, subject.digest.?) == .same;
}

/// Publish the states 1 to `count` of the function, each with its proof and its marker, and after each publication hold the module answer
/// of every one of the states against the function's.
fn publishStates(a: std.mem.Allocator, proofs: *Proofs, count: u8) !void {
    for (1..@as(usize, count) + 1) |tag| {
        proofs.publish(a, "app", try facts.groupsWith(a, "app", &.{stateOf(@intCast(tag))}, &.{try markerOf(a, @intCast(tag))}));
        for (1..@as(usize, count) + 1) |earlier| try std.testing.expect(answerNeverExceeds(proofs, stateOf(@intCast(earlier)), @intCast(earlier)));
    }
}

/// How many markers and how many proofs a record holds.
const HeldCount = struct { markers: usize, proofs: usize };

/// How many of the states 1 to `count` have a marker held, and how many a proof.
fn heldStates(proofs: *Proofs, count: u8) HeldCount {
    var out: [1]bool = .{false};
    var found: HeldCount = .{ .markers = 0, .proofs = 0 };
    for (1..@as(usize, count) + 1) |tag| {
        const state = stateOf(@intCast(tag));
        found.markers += @intFromBool(proofs.heldModule("app", "m", @splat(@intCast(tag)), &out));
        found.proofs += @intFromBool(proofs.held("app", "m", state.ident, state.digest.?) == .same);
    }
    return found;
}

test "G2p a module marker goes with the proofs it speaks for: a record that lets go of a proof keeps no stale marker, and one that is lost holds neither" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const states = facts.max_variants + 1;
    const writer = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    // Up to `max_variants` states the record keeps every proof and every marker; the next state lets one proof go, and with it every marker
    // but the one the run publishes. At every step no marker says more than the proofs beside it.
    try publishStates(a, writer, facts.max_variants);
    const full = heldStates(writer, facts.max_variants);
    try std.testing.expectEqual(@as(usize, facts.max_variants), full.markers);
    try std.testing.expectEqual(@as(usize, facts.max_variants), full.proofs);
    try publishStates(a, writer, states);
    const outgrown = heldStates(writer, states);
    try std.testing.expectEqual(@as(usize, 1), outgrown.markers);
    try std.testing.expectEqual(@as(usize, facts.max_variants), outgrown.proofs);
    writer.close();
    // The record is lost: neither the proofs nor the markers are held.
    try temporary.dir.deleteTree(std.testing.io, "engine-v1/records/ownership-proof");
    const reader = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer reader.close();
    const lost = heldStates(reader, states);
    try std.testing.expectEqual(@as(usize, 0), lost.markers + lost.proofs);
    try std.testing.expect(answerNeverExceeds(reader, stateOf(1), 1));
}

test "publishing what the record already holds writes nothing, and a second state of a function is added beside the first" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const proofs = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer proofs.close();
    const ident = "fn\x1fm\x1f\x1ff";
    const first = facts.receiptDigest(ident, @splat(1), @splat(1));
    const second = facts.receiptDigest(ident, @splat(1), @splat(2));
    proofs.publish(a, "app", try facts.groupsOf(a, "app", &.{.{ .module = "m", .ident = ident, .digest = first }}));
    const written = proofs.runner.snapshot(&proofs.kind).?.count(.recomputed);
    proofs.publish(a, "app", try facts.groupsOf(a, "app", &.{.{ .module = "m", .ident = ident, .digest = first }}));
    try std.testing.expectEqual(written, proofs.runner.snapshot(&proofs.kind).?.count(.recomputed));
    proofs.publish(a, "app", try facts.groupsOf(a, "app", &.{.{ .module = "m", .ident = ident, .digest = second }}));
    try std.testing.expectEqual(written + 1, proofs.runner.snapshot(&proofs.kind).?.count(.recomputed));
    try std.testing.expectEqual(facts.Held.same, proofs.held("app", "m", ident, first));
    try std.testing.expectEqual(facts.Held.same, proofs.held("app", "m", ident, second));
}

/// `count` subjects of the module `big`, one proof each.
fn bigModule(a: std.mem.Allocator, count: usize) ![]facts.Subject {
    const subjects = try a.alloc(facts.Subject, count);
    for (subjects, 0..) |*subject, index| {
        const ident = try std.fmt.allocPrint(a, "fn\x1fbig\x1f\x1ffunction_{d}", .{index});
        subject.* = .{ .module = "big", .ident = ident, .digest = facts.receiptDigest(ident, @splat(1), @splat(1)) };
    }
    return subjects;
}

/// How many of `subjects` the proofs hold under the digest they carry.
fn provenCount(proofs: *Proofs, subjects: []const facts.Subject) usize {
    var proven: usize = 0;
    for (subjects) |subject| {
        if (proofs.held("app", subject.module, subject.ident, subject.digest.?) == .same) proven += 1;
    }
    return proven;
}

test "G1c a run that asks about every function of a module opens the module's record once and reads no object" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const subjects = try bigModule(a, 400);
    const writer = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    writer.publish(a, "app", try facts.groupsOf(a, "app", subjects));
    writer.close();
    const reader = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer reader.close();
    try std.testing.expectEqual(@as(usize, 400), provenCount(reader, subjects));
    // Four hundred proofs in one record: one record served, no object read, nothing recomputed.
    const numbers = reader.runner.snapshot(&reader.kind).?;
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_reads));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
    // A run that asks about no function opens no record.
    const idle = Proofs.open(std.testing.allocator, std.testing.io, work).?;
    defer idle.close();
    try std.testing.expectEqual(@as(u64, 0), idle.runner.snapshot(&idle.kind).?.count(.served));
}

test "G4c the proofs one work directory published are held by another through the compiler store, a module's record with its object, and a foreign digest is not taken for them" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "first");
    try temporary.dir.createDirPath(std.testing.io, "second");
    var environment: std.process.Environ.Map = .init(a);
    try environment.put(@import("selka").shared_artifact_store.environment_variable, try std.fs.path.join(a, &.{ root, "store" }));
    const subjects = try bigModule(a, 400);
    const writer = Proofs.open(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "first" })).?;
    writer.share(engine_sharing.explicit(&environment));
    writer.publish(a, "app", try facts.groupsOf(a, "app", subjects));
    try std.testing.expectEqual(@as(u64, 1), writer.runner.snapshot(&writer.kind).?.count(.shared_published));
    writer.close();
    // Another work directory, another tree: nothing local, and the record is served from the tier.
    const reader = Proofs.open(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "second" })).?;
    defer reader.close();
    reader.share(engine_sharing.explicit(&environment));
    try std.testing.expectEqual(@as(usize, 400), provenCount(reader, subjects));
    const numbers = reader.runner.snapshot(&reader.kind).?;
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_reads));
    const edited = facts.receiptDigest(subjects[0].ident, @splat(1), @splat(2));
    try std.testing.expectEqual(facts.Held.other, reader.held("app", "big", subjects[0].ident, edited));
    // A work directory with sharing off does not see the tier.
    const alone = Proofs.open(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "alone" })).?;
    defer alone.close();
    try std.testing.expectEqual(@as(usize, 0), provenCount(alone, subjects));
}

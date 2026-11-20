//! The ownership proofs of a program, grouped by module, as the `ownership-proof` kind states them (spec §14, §17.2).
//!
//! The ownership cache decides, function by function, whether the ownership check may be omitted. This file turns what it holds
//! when it decides into the groups the engine records: one per module, with one part per proof, so that opening one record
//! answers for every function of a module. A function belongs to the module of its stable key (`fn`, module, owner, name) when
//! the semantic planner stands in for it, else to the module its qualified name (`module::name`) names, and to the program's own
//! group (`""`) when its name has none, as a headerless program's does.
//!
//! A proof is a part named `proof:<ident>@<16 hex digits of its digest>` holding the whole digest. A function can have up to
//! `max_variants` proofs at once, one for each state of its inputs that was checked and passed (an edit and its revert, the two
//! sessions of one entry), so a record keeps what an alternation needs instead of flipping.
const std = @import("std");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const proof_kind = @import("engine/kinds/ownership_proof.zig");
const mode_rules = @import("ownership_mode.zig");

/// The first line of the payload.
pub const payload_magic = "selka-ownership-proof-v2";
/// The prefix of the part a proof is published under.
pub const part_prefix = "proof:";
/// How many proofs of one function a record keeps.
pub const max_variants = 4;
/// The domain of a proof input digest built from a semantic receipt.
const receipt_domain = "selka-ownership-proof-receipt-v1";
/// The domain of a proof input digest built from a body and its reach.
const reach_domain = "selka-ownership-proof-reach-v1";
/// The prefix of the ident of a function with no semantic receipt.
pub const typed_prefix = "typed\x00";

/// One function as the ownership cache holds it when it decides what to check: where its proof belongs, what names it there, and
/// the digest of the inputs it is checked under in this run.
pub const Subject = struct {
    /// The module group the proof belongs to.
    module: []const u8 = "",
    /// What names the function inside its group: a semantic receipt's key, or `typed_prefix` and the qualified name (with `#2`,
    /// `#3` for a name that repeats within a program).
    ident: []const u8 = "",
    /// The digest of the function's proof inputs in this run, or null when it has none (it is always checked).
    digest: ?[32]u8 = null,
    /// Verify mode samples this function: its proof is held and its check is made anyway.
    sampled: bool = false,
    /// The record already holds the proof under this digest, so a run has nothing to add for the function.
    held: bool = false,
    /// The digest is a semantic receipt's: the function stands in for itself in the planner, so a module marker may say it is proven.
    receipt: bool = false,
};

/// The prefix of a module marker's part name (G2p).
pub const marker_prefix = "module:";

/// A module marker to publish: the part naming the module's signature and which of its functions were proven under it.
pub const Marker = struct { module: []const u8, part: []const u8, digest: [32]u8 };

/// Write the prefix every marker of `signature` has into `out`, replacing what it held.
fn markerPrefix(out: *std.ArrayList(u8), a: std.mem.Allocator, signature: [32]u8) std.mem.Allocator.Error!void {
    out.clearRetainingCapacity();
    try out.appendSlice(a, marker_prefix);
    try out.appendSlice(a, digest_rules.hex(signature)[0..16]);
    try out.append(a, ':');
}

/// The part that says the functions `proven` marks (in program order) were proven under the module `signature`: `module:<16 hex digits of
/// the signature>:<count>:<mask as hex>`, holding the whole signature. The signature is a digest of every member's key, dependency context and
/// region, so each member's proof input digest (`receiptDigest`) is a function of it, and a function proven under that digest is proven
/// whenever the signature is the same. Allocated in `a`.
pub fn markerName(a: std.mem.Allocator, signature: [32]u8, proven: []const bool) std.mem.Allocator.Error![]const u8 {
    var name: std.ArrayList(u8) = .empty;
    try markerPrefix(&name, a, signature);
    try name.print(a, "{d}:", .{proven.len});
    var at: usize = 0;
    while (at < proven.len) : (at += 4) {
        var nibble: u8 = 0;
        for (proven[at..@min(at + 4, proven.len)], 0..) |bit, shift| nibble |= @as(u8, @intFromBool(bit)) << @intCast(shift);
        try name.append(a, "0123456789abcdef"[nibble]);
    }
    return name.items;
}

/// Set `out[i]` for each member `i` that a marker in `served` for `signature` says was proven, and say whether the record holds any marker for
/// it. `out` is untouched when none. A marker whose count is not `out.len` is another module's shape and is ignored.
pub fn heldMarkers(served: []const record.Part, scratch: *std.ArrayList(u8), a: std.mem.Allocator, signature: [32]u8, out: []bool) std.mem.Allocator.Error!bool {
    try markerPrefix(scratch, a, signature);
    var at = std.sort.lowerBound(record.Part, served, scratch.items, partOrder);
    var found = false;
    while (at < served.len and std.mem.startsWith(u8, served[at].name, scratch.items)) : (at += 1) {
        if (!std.mem.eql(u8, &served[at].digest, &signature)) continue;
        const rest = served[at].name[scratch.items.len..];
        const colon = std.mem.indexOfScalar(u8, rest, ':') orelse continue;
        const count = std.fmt.parseInt(usize, rest[0..colon], 10) catch continue;
        const mask = rest[colon + 1 ..];
        if (count != out.len or mask.len != (count + 3) / 4) continue;
        if (!found) @memset(out, false);
        found = true;
        for (out, 0..) |*bit, member| {
            const nibble = std.fmt.charToDigit(mask[member / 4], 16) catch continue;
            if ((nibble >> @intCast(member % 4)) & 1 != 0) bit.* = true;
        }
    }
    return found;
}

/// One proof in a group.
pub const Member = struct {
    /// The part's name.
    part: []const u8,
    /// The digest of the function's proof inputs in this run.
    digest: [32]u8,
};

/// The proofs of one module and the argument the engine is asked for them under.
pub const Group = struct { argument: []const u8, members: []const Member };

/// The digest of a semantic receipt: the function's stable key, the digest of its dependency context and the digest of the
/// region of source it was checked from.
pub fn receiptDigest(key: []const u8, context_digest: [32]u8, region: [32]u8) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(receipt_domain);
    state.update("\x00");
    state.update(mode_rules.name);
    state.update("\x00");
    state.update(key);
    state.update("\x00");
    state.update(&context_digest);
    state.update(&region);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

/// The digest of a function's body and reach (`lowering_cache.OwnershipReach`), under the function's stable name.
pub fn reachDigest(name: []const u8, reach: [32]u8) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(reach_domain);
    state.update("\x00");
    state.update(mode_rules.name);
    state.update("\x00");
    state.update(name);
    state.update("\x00");
    state.update(&reach);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

/// The module a function name belongs to: what comes before the first `::`, looked for before any type arguments (`[`). A
/// name with none belongs to the program's own group, `""`.
pub fn moduleOf(name: []const u8) []const u8 {
    const head = name[0 .. std.mem.indexOfScalar(u8, name, '[') orelse name.len];
    const at = std.mem.indexOf(u8, head, "::") orelse return "";
    return head[0..at];
}

/// The module a semantic function key names: `fn`, the module, the owner and the name, each after a unit separator. Null for
/// a key that is not one.
pub fn moduleOfKey(key: []const u8) ?[]const u8 {
    var fields = std.mem.splitScalar(u8, key, 0x1f);
    if (!std.mem.eql(u8, fields.next() orelse return null, "fn")) return null;
    return fields.next();
}

/// The argument the engine is asked for `module`'s proofs under, for the entry `entry`: the entry, the ownership mode and the
/// module, each followed by a zero byte but the last.
pub fn argumentOf(a: std.mem.Allocator, entry: []const u8, module: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00{s}\x00{s}", .{ entry, mode_rules.name, module });
}

/// The module part of an argument.
pub fn moduleOfArgument(argument: []const u8) []const u8 {
    const last = std.mem.lastIndexOfScalar(u8, argument, 0) orelse return argument;
    return argument[last + 1 ..];
}

/// Write the name of the part holding the proof of `ident` under `digest` into `out`, replacing what it held.
pub fn partName(out: *std.ArrayList(u8), a: std.mem.Allocator, ident: []const u8, digest: [32]u8) std.mem.Allocator.Error!void {
    out.clearRetainingCapacity();
    try out.appendSlice(a, part_prefix);
    try out.appendSlice(a, ident);
    try out.append(a, '@');
    try out.appendSlice(a, digest_rules.hex(digest)[0..16]);
}

/// The ident a part name carries: what lies between the prefix and the last `@`. Null for a name that is not a proof's.
pub fn identOfPart(part: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, part, part_prefix)) return null;
    const at = std.mem.lastIndexOfScalar(u8, part, '@') orelse return null;
    if (at < part_prefix.len) return null;
    return part[part_prefix.len..at];
}

fn memberBefore(_: void, left: Member, right: Member) bool {
    return std.mem.lessThan(u8, left.part, right.part);
}

fn groupBefore(_: void, left: Group, right: Group) bool {
    return std.mem.lessThan(u8, left.argument, right.argument);
}

/// The groups of `subjects` for the entry `entry`: one for every module with at least one subject that has a digest and that the
/// record does not already hold, in byte order of their arguments, each with its members in byte order of their part names. A
/// run that adds nothing to a module has no group for it, so an unchanged build names no part. Allocated in `a`.
pub fn groupsOf(a: std.mem.Allocator, entry: []const u8, subjects: []const Subject) std.mem.Allocator.Error![]const Group {
    return groupsWith(a, entry, subjects, &.{});
}

/// `groupsOf`, with the module markers the run adds: a module with a marker to publish has a group even when no proof of it is new.
pub fn groupsWith(a: std.mem.Allocator, entry: []const u8, subjects: []const Subject, markers: []const Marker) std.mem.Allocator.Error![]const Group {
    var buckets: std.array_hash_map.String(std.ArrayList(Member)) = .empty;
    var name: std.ArrayList(u8) = .empty;
    for (markers) |marker| {
        const bucket = try buckets.getOrPut(a, marker.module);
        if (!bucket.found_existing) bucket.value_ptr.* = .empty;
        try bucket.value_ptr.append(a, .{ .part = marker.part, .digest = marker.digest });
    }
    for (subjects) |subject| {
        if (subject.held) continue;
        const digest = subject.digest orelse continue;
        try partName(&name, a, subject.ident, digest);
        const bucket = try buckets.getOrPut(a, subject.module);
        if (!bucket.found_existing) bucket.value_ptr.* = .empty;
        try bucket.value_ptr.append(a, .{ .part = try a.dupe(u8, name.items), .digest = digest });
    }
    const groups = try a.alloc(Group, buckets.count());
    for (groups, buckets.keys(), buckets.values()) |*slot, module, *members| {
        std.mem.sort(Member, members.items, {}, memberBefore);
        slot.* = .{ .argument = try argumentOf(a, entry, module), .members = members.items };
    }
    std.mem.sort(Group, groups, {}, groupBefore);
    return groups;
}

/// The parts a record holds after a run that proved `group` and found the record holding `previous`: every proof of the record
/// and of the run, at most `max_variants` for each function, and the run's own always. A function that stays under the limit
/// keeps all it had; one over it keeps the run's proofs and the first of the others in byte order of their names. The payload
/// names the module and counts the proofs. Allocated in `a`.
pub fn answerOf(a: std.mem.Allocator, group: Group, previous: []const record.Part) std.mem.Allocator.Error!proof_kind.Answer {
    var parts: std.ArrayList(record.Part) = .empty;
    var run_at: usize = 0;
    var old_at: usize = 0;
    // The proofs of each function's ident are adjacent in both lists, in byte order of their names, so the merge walks both.
    while (run_at < group.members.len or old_at < previous.len) {
        const take_run = old_at >= previous.len or (run_at < group.members.len and !std.mem.lessThan(u8, previous[old_at].name, group.members[run_at].part));
        if (take_run) {
            const member = group.members[run_at];
            run_at += 1;
            if (old_at < previous.len and std.mem.eql(u8, previous[old_at].name, member.part)) old_at += 1;
            try parts.append(a, .{ .name = member.part, .digest = member.digest });
        } else {
            try parts.append(a, previous[old_at]);
            old_at += 1;
        }
    }
    // The module markers sort before the proofs. A marker says its members were proven, which the proofs beside it must be able to bear
    // out, so a record that lets go of a proof (more than `max_variants` of a function) keeps only the markers of this run.
    var markers_end: usize = 0;
    while (markers_end < parts.items.len and std.mem.startsWith(u8, parts.items[markers_end].name, marker_prefix)) markers_end += 1;
    const proofs = try limited(a, parts.items[markers_end..], group.members);
    const markers = try limitedMarkers(a, parts.items[0..markers_end], group.members, proofs.len < parts.items.len - markers_end);
    const kept = try std.mem.concat(a, record.Part, &.{ markers, proofs });
    return .{ .payload = try std.fmt.allocPrint(a, "{s}\n{s}\n{d}\n", .{ payload_magic, moduleOfArgument(group.argument), proofs.len }), .parts = kept };
}

/// How many module markers a record keeps: one for each recent state of the module's signature.
pub const max_markers = 8;

/// The markers of `merged` a record keeps: the run's own, then at most `max_markers` in all of the others in byte order of their names,
/// and none of the others when the record let go of a proof.
fn limitedMarkers(a: std.mem.Allocator, merged: []const record.Part, run: []const Member, evicted: bool) std.mem.Allocator.Error![]const record.Part {
    var kept: std.ArrayList(record.Part) = .empty;
    for (merged) |part| if (inRun(run, part.name)) try kept.append(a, part);
    if (!evicted) for (merged) |part| if (kept.items.len < max_markers and !inRun(run, part.name)) try kept.append(a, part);
    std.mem.sort(record.Part, kept.items, {}, partBefore);
    return kept.items;
}

/// `merged` (in byte order of the part names) with at most `max_variants` proofs of each function: the run's own proofs first,
/// then the others as they come.
fn limited(a: std.mem.Allocator, merged: []const record.Part, run: []const Member) std.mem.Allocator.Error![]const record.Part {
    var kept: std.ArrayList(record.Part) = .empty;
    var at: usize = 0;
    while (at < merged.len) {
        const ident = identOfPart(merged[at].name) orelse "";
        var end = at + 1;
        while (end < merged.len and std.mem.eql(u8, identOfPart(merged[end].name) orelse "", ident)) end += 1;
        const first = kept.items.len;
        if (end - at <= max_variants) {
            try kept.appendSlice(a, merged[at..end]);
        } else {
            var room: usize = max_variants;
            for (merged[at..end]) |part| if (inRun(run, part.name)) {
                try kept.append(a, part);
                room -|= 1;
            };
            for (merged[at..end]) |part| if (room > 0 and !inRun(run, part.name)) {
                try kept.append(a, part);
                room -= 1;
            };
            std.mem.sort(record.Part, kept.items[first..], {}, partBefore);
        }
        at = end;
    }
    return kept.items;
}

fn partBefore(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

fn inRun(run: []const Member, name: []const u8) bool {
    return std.sort.binarySearch(Member, run, name, memberOrder) != null;
}

fn memberOrder(name: []const u8, member: Member) std.math.Order {
    return std.mem.order(u8, name, member.part);
}

/// What the parts `served` hold for one proof.
pub const Held = enum {
    /// No proof of the function at all.
    absent,
    /// Proofs of the function, none under the digest this run computed.
    other,
    /// A proof under the digest this run computed: the function is proven.
    same,
};

/// What the parts `served` hold for the function `ident` under `digest`. `scratch` is a buffer the name is built in.
pub fn held(served: []const record.Part, scratch: *std.ArrayList(u8), a: std.mem.Allocator, ident: []const u8, digest: [32]u8) std.mem.Allocator.Error!Held {
    try partName(scratch, a, ident, digest);
    if (std.sort.binarySearch(record.Part, served, scratch.items, partOrder)) |at| {
        return if (std.mem.eql(u8, &served[at].digest, &digest)) .same else .other;
    }
    // Another proof of the same function: the first part at or after `proof:<ident>@` that still starts with it.
    scratch.items.len -= 16;
    const lower = std.sort.lowerBound(record.Part, served, scratch.items, partOrder);
    return if (lower < served.len and std.mem.startsWith(u8, served[lower].name, scratch.items)) .other else .absent;
}

fn partOrder(name: []const u8, part: record.Part) std.math.Order {
    return std.mem.order(u8, name, part.name);
}

/// Whether two part tables hold the same parts with the same digests.
pub fn sameParts(left: []const record.Part, right: []const record.Part) bool {
    if (left.len != right.len) return false;
    for (left, right) |was, is| {
        if (!std.mem.eql(u8, was.name, is.name) or !std.mem.eql(u8, &was.digest, &is.digest)) return false;
    }
    return true;
}

fn proofSubject(module: []const u8, ident: []const u8, tag: u8) Subject {
    return .{ .module = module, .ident = ident, .digest = receiptDigest(ident, @splat(tag), @splat(tag)) };
}

test "a function belongs to the module its key or its qualified name names, looked for before its type arguments" {
    try std.testing.expectEqualStrings("util", moduleOf("util::make"));
    try std.testing.expectEqualStrings("util", moduleOf("util::first[main::Rec]"));
    try std.testing.expectEqualStrings("", moduleOf("main"));
    try std.testing.expectEqualStrings("", moduleOf("pick_first[aggregate_refs::Point]"));
    try std.testing.expectEqualStrings("@std:strings", moduleOf("@std:strings::split"));
    try std.testing.expectEqualStrings("util", moduleOfKey("fn\x1futil\x1f\x1fmake").?);
    try std.testing.expectEqual(@as(?[]const u8, null), moduleOfKey("\x00typed/0/main"));
}

test "G2p a module marker names the signature and the proven members, is held under that signature only, and two markers add up" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: [32]u8 = @splat(7);
    const first = try markerName(a, signature, &.{ true, false, true, true, false });
    const second = try markerName(a, signature, &.{ false, true, false, false, false });
    const parts = [_]record.Part{
        .{ .name = first, .digest = signature },
        .{ .name = second, .digest = signature },
        .{ .name = "proof:fn\x1fm\x1f\x1ff@0123456789abcdef", .digest = @splat(1) },
    };
    var sorted = parts;
    std.mem.sort(record.Part, &sorted, {}, struct {
        fn before(_: void, left: record.Part, right: record.Part) bool {
            return std.mem.lessThan(u8, left.name, right.name);
        }
    }.before);
    var scratch: std.ArrayList(u8) = .empty;
    var out: [5]bool = @splat(false);
    try std.testing.expect(try heldMarkers(&sorted, &scratch, a, signature, &out));
    try std.testing.expectEqualSlices(bool, &.{ true, true, true, true, false }, &out);
    // Another signature has no marker, and a module of another size does not read this one's.
    var untouched: [5]bool = @splat(true);
    try std.testing.expect(!try heldMarkers(&sorted, &scratch, a, @splat(8), &untouched));
    try std.testing.expectEqualSlices(bool, &.{ true, true, true, true, true }, &untouched);
    var fewer: [4]bool = @splat(false);
    try std.testing.expect(!try heldMarkers(&sorted, &scratch, a, signature, &fewer));
    // A marker whose digest is not the signature it names is not evidence.
    var forged = sorted;
    forged[0].digest = @splat(9);
    forged[1].digest = @splat(9);
    try std.testing.expect(!try heldMarkers(&forged, &scratch, a, signature, &out));
}

test "G2p a module with a marker to publish has a group though none of its proofs is new" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var held_one = proofSubject("util", "fn\x1futil\x1f\x1fsum", 1);
    held_one.held = true;
    const marker: Marker = .{ .module = "util", .part = try markerName(a, @splat(5), &.{true}), .digest = @splat(5) };
    try std.testing.expectEqual(@as(usize, 0), (try groupsOf(a, "app", &.{held_one})).len);
    const groups = try groupsWith(a, "app", &.{held_one}, &.{marker});
    try std.testing.expectEqual(@as(usize, 1), groups.len);
    try std.testing.expectEqualStrings(marker.part, groups[0].members[0].part);
    try std.testing.expectEqual(@as(?[]const u8, null), identOfPart(marker.part));
}

/// A record's parts: four states of one function's proof and a marker for each of `markers` signatures, in byte order.
fn recordWith(a: std.mem.Allocator, markers: usize) std.mem.Allocator.Error![]const record.Part {
    var parts: std.ArrayList(record.Part) = .empty;
    var name: std.ArrayList(u8) = .empty;
    for (1..max_variants + 1) |variant| {
        const digest: [32]u8 = @splat(@intCast(variant));
        try partName(&name, a, "fn\x1fm\x1f\x1ff", digest);
        try parts.append(a, .{ .name = try a.dupe(u8, name.items), .digest = digest });
    }
    for (1..markers + 1) |at| try parts.append(a, .{ .name = try markerName(a, @splat(@intCast(at)), &.{true}), .digest = @splat(@intCast(at)) });
    std.mem.sort(record.Part, parts.items, {}, partBefore);
    return parts.items;
}

/// How many markers and how many proofs `parts` holds.
fn countParts(parts: []const record.Part) struct { markers: usize, proofs: usize } {
    var found: @TypeOf(countParts(&.{})) = .{ .markers = 0, .proofs = 0 };
    for (parts) |part| {
        found.markers += @intFromBool(std.mem.startsWith(u8, part.name, marker_prefix));
        found.proofs += @intFromBool(identOfPart(part.name) != null);
    }
    return found;
}

test "G2p a record that lets go of a proof keeps only this run's module markers, and otherwise at most max_markers of them" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const run_marker = try markerName(a, @splat(9), &.{true});
    // A fifth state of the function: one proof is let go, and the markers of the other states with it.
    var name: std.ArrayList(u8) = .empty;
    try partName(&name, a, "fn\x1fm\x1f\x1ff", @splat(5));
    var members = [_]Member{ .{ .part = run_marker, .digest = @splat(9) }, .{ .part = name.items, .digest = @splat(5) } };
    std.mem.sort(Member, &members, {}, memberBefore);
    const letting_go = countParts((try answerOf(a, .{ .argument = "app\x00m", .members = &members }, try recordWith(a, 3))).parts);
    try std.testing.expectEqual(@as(usize, 1), letting_go.markers);
    try std.testing.expectEqual(@as(usize, max_variants), letting_go.proofs);
    // Without a proof to let go of, the markers add up to the cap, the run's own among them.
    var only_marker = [_]Member{.{ .part = run_marker, .digest = @splat(9) }};
    const capped = try answerOf(a, .{ .argument = "app\x00m", .members = &only_marker }, try recordWith(a, 12));
    try std.testing.expectEqual(@as(usize, max_markers), countParts(capped.parts).markers);
    try std.testing.expectEqual(@as(usize, max_variants), countParts(capped.parts).proofs);
    var out: [1]bool = .{false};
    var scratch: std.ArrayList(u8) = .empty;
    try std.testing.expect(try heldMarkers(capped.parts, &scratch, a, @splat(9), &out));
}

test "a subject the record already holds adds no group, and a module with one new proof names only that proof" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var held_one = proofSubject("util", "fn\x1futil\x1f\x1fsum", 1);
    held_one.held = true;
    var held_two = proofSubject("main", "typed\x00main::main", 2);
    held_two.held = true;
    const fresh = proofSubject("util", "fn\x1futil\x1f\x1fmake", 3);
    try std.testing.expectEqual(@as(usize, 0), (try groupsOf(a, "app", &.{ held_one, held_two })).len);
    const groups = try groupsOf(a, "app", &.{ held_one, held_two, fresh });
    try std.testing.expectEqual(@as(usize, 1), groups.len);
    try std.testing.expectEqualStrings("util", moduleOfArgument(groups[0].argument));
    try std.testing.expectEqual(@as(usize, 1), groups[0].members.len);
    try std.testing.expectEqualStrings("fn\x1futil\x1f\x1fmake", identOfPart(groups[0].members[0].part).?);
}

test "groups are per module and sorted, and the part name carries the ident and a prefix of the digest" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const subjects = [_]Subject{
        proofSubject("util", "fn\x1futil\x1f\x1fsum", 1),
        proofSubject("main", "typed\x00main::main", 2),
        proofSubject("util", "fn\x1futil\x1f\x1fmake", 3),
        .{ .module = "util", .ident = "fn\x1futil\x1f\x1funproven", .digest = null },
    };
    const groups = try groupsOf(a, "app", &subjects);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    try std.testing.expectEqualStrings("app\x00zero-rc\x00main", groups[0].argument);
    try std.testing.expectEqualStrings("app\x00zero-rc\x00util", groups[1].argument);
    try std.testing.expectEqual(@as(usize, 2), groups[1].members.len);
    try std.testing.expect(std.mem.startsWith(u8, groups[1].members[0].part, "proof:fn\x1futil\x1f\x1fmake@"));
    try std.testing.expectEqualStrings("fn\x1futil\x1f\x1fmake", identOfPart(groups[1].members[0].part).?);
    try std.testing.expectEqual(@as(usize, 16), groups[1].members[0].part.len - "proof:fn\x1futil\x1f\x1fmake@".len);
}

test "a proof is held only while the digest the run computes is the digest the record holds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scratch: std.ArrayList(u8) = .empty;
    const ident = "fn\x1fm\x1f\x1ff";
    const first = receiptDigest(ident, @splat(1), @splat(2));
    const groups = try groupsOf(a, "app", &.{.{ .module = "m", .ident = ident, .digest = first }});
    const published = try answerOf(a, groups[0], &.{});
    try std.testing.expectEqual(Held.same, try held(published.parts, &scratch, a, ident, first));
    // The function's region changed: the digest this run computes is another, and the record's is not taken for it.
    const edited = receiptDigest(ident, @splat(1), @splat(3));
    try std.testing.expectEqual(Held.other, try held(published.parts, &scratch, a, ident, edited));
    try std.testing.expectEqual(Held.absent, try held(published.parts, &scratch, a, "fn\x1fm\x1f\x1fg", first));
    try std.testing.expectEqual(Held.absent, try held(&.{}, &scratch, a, ident, first));
}

test "a record keeps the variants of a function that earlier runs proved, up to the limit, and never drops this run's" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scratch: std.ArrayList(u8) = .empty;
    const ident = "fn\x1fm\x1f\x1ff";
    var held_parts: []const record.Part = &.{};
    var digests: [6][32]u8 = undefined;
    for (&digests, 0..) |*slot, at| {
        slot.* = receiptDigest(ident, @splat(@intCast(at)), @splat(0));
        const run = try groupsOf(a, "app", &.{.{ .module = "m", .ident = ident, .digest = slot.* }});
        held_parts = (try answerOf(a, run[0], held_parts)).parts;
        try std.testing.expectEqual(Held.same, try held(held_parts, &scratch, a, ident, slot.*));
        try std.testing.expect(held_parts.len <= max_variants);
    }
    // The first two variants fell out; the last is the one the latest run proved.
    try std.testing.expectEqual(@as(usize, max_variants), held_parts.len);
    try std.testing.expectEqual(Held.same, try held(held_parts, &scratch, a, ident, digests[5]));
}

test "a function this run did not compute keeps its proofs, and the others' stay sorted" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try answerOf(a, (try groupsOf(a, "app", &.{ proofSubject("m", "a", 1), proofSubject("m", "c", 1) }))[0], &.{});
    const now = (try groupsOf(a, "app", &.{ proofSubject("m", "b", 1), proofSubject("m", "c", 2) }))[0];
    const merged = try answerOf(a, now, before.parts);
    try std.testing.expectEqual(@as(usize, 4), merged.parts.len);
    try std.testing.expect(std.mem.startsWith(u8, merged.parts[0].name, "proof:a@"));
    try std.testing.expect(std.mem.startsWith(u8, merged.parts[1].name, "proof:b@"));
    try std.testing.expect(std.mem.startsWith(u8, merged.parts[2].name, "proof:c@"));
    try std.testing.expect(std.mem.startsWith(u8, merged.parts[3].name, "proof:c@"));
    try std.testing.expect(sameParts(merged.parts, merged.parts));
    try std.testing.expect(!sameParts(merged.parts, before.parts));
}

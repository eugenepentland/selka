//! `--verify-cache` for the stage records: what a build made of the records the stage store served must equal what a build
//! that served none makes.
//!
//! A `--verify-cache` build runs two passes. The first is an ordinary build up to its emitted units: it reads the work
//! directory's stage records and the shared stage store, so lowered functions, optimizer bodies and emitted units come from
//! the records whose keys match, and it stops before the link. `collect` keeps the name of each unit it emitted and the digest
//! of its LLVM text. The second pass is the uncached build that `--verify-cache` always ran (no front-end cache, no stage
//! record, every served object recompiled); `differences` compares the text digest of each unit it emitted with the first
//! pass's and names every unit that differs. A record whose key does not cover everything its content depends on shows here as
//! a unit the first pass made differently, however many stages stood between the stale record and the unit's text.
//!
//! The digest covers the whole text, the linkage keyword of a source function's definition included. Spec section 17.5 gives a function
//! `internal` linkage when the check found it private to its module, and a check served from the front-end cache must find the same
//! functions private as a full check does: a function that a body which stood in names as a value is visible, as it is when the body is
//! checked (`Uses.values`). Until 8 November 2026 the digest took every `define internal fastcc` as `define hidden fastcc`, because the two
//! checks disagreed; the disagreement showed only as an undefined hidden symbol at the link, from the unit that named the function.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const emit_units = @import("emit_units.zig");

/// The digest of a unit's LLVM text.
pub const Digest = [32]u8;

/// One emitted unit as the verification sees it: its name (a generic or helper unit's name holds the digest of its text), the kind
/// of unit and the source file it belongs to, and the digest of its text, null when the build kept none (a unit served as a native
/// handle holds no text).
pub const Entry = struct { name: []const u8, kind: emit_units.Kind, source_path: []const u8, text: ?Digest };

/// The units the stage-served pass emitted, in emission order.
pub const Served = struct { entries: []const Entry = &.{} };

/// What a pass of a `--verify-cache` build does with the units it emitted: the first keeps their digests and stops before the
/// link, the second compares its own with the first's.
pub const Probe = union(enum) { collect: *Served, compare: *const Served };

/// What `differences` found: the units whose text differs or that only one pass emitted, and the units whose text it compared.
pub const Found = struct { differing: usize = 0, compared: u32 = 0 };

/// The digest of the LLVM text `text`.
pub fn digestOf(text: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(text);
    var out: Digest = undefined;
    hash.final(&out);
    return out;
}

/// The digest of `unit`'s LLVM text, or null when the unit holds none.
pub fn textDigest(unit: emit_units.Unit) ?Digest {
    return if (unit.llvm.len == 0) null else digestOf(unit.llvm);
}

/// The name, kind, source file and text digest of each of `units`, allocated in `a`.
pub fn collect(a: std.mem.Allocator, units: []const emit_units.Unit) std.mem.Allocator.Error!Served {
    const entries = try a.alloc(Entry, units.len);
    for (units, entries) |unit, *slot| slot.* = .{ .name = try a.dupe(u8, unit.name), .kind = unit.kind, .source_path = try a.dupe(u8, unit.source_path), .text = textDigest(unit) };
    return .{ .entries = entries };
}

/// One line per unit whose text differs between the stage-served pass and `units`, or that only one of them emitted, appended
/// to `report`; the number of such units, and the number of units whose text was compared. `served` and `units` may list the
/// units in any order. A unit that either pass kept no text for is not compared.
pub fn differences(a: std.mem.Allocator, report: *std.ArrayList(u8), served: Served, units: []const emit_units.Unit) std.mem.Allocator.Error!Found {
    var found: Found = .{};
    for (units) |unit| {
        const held = find(served, unit.name) orelse {
            try report.print(a, "error: --verify-cache: {s} unit {s} ({s}) was emitted by the fresh build and not by the build that served the stage records\n", .{ @tagName(unit.kind), unit.name, unit.source_path });
            found.differing += 1;
            continue;
        };
        const fresh = textDigest(unit) orelse continue;
        const cached = held.text orelse continue;
        found.compared += 1;
        if (std.mem.eql(u8, &cached, &fresh)) continue;
        const cached_text = std.fmt.bytesToHex(cached[0..8].*, .lower);
        const fresh_text = std.fmt.bytesToHex(fresh[0..8].*, .lower);
        try report.print(a, "error: --verify-cache: {s} unit {s} ({s}) is emitted from the cached stages as text {s}, and from a fresh build as text {s}\n", .{
            @tagName(unit.kind), unit.name, unit.source_path, &cached_text, &fresh_text,
        });
        found.differing += 1;
    }
    for (served.entries) |held| {
        const present = for (units) |unit| {
            if (std.mem.eql(u8, unit.name, held.name)) break true;
        } else false;
        if (present) continue;
        try report.print(a, "error: --verify-cache: {s} unit {s} ({s}) was emitted by the build that served the stage records and not by the fresh build\n", .{ @tagName(held.kind), held.name, held.source_path });
        found.differing += 1;
    }
    return found;
}

/// The entry of `served` named `name`, or null.
fn find(served: Served, name: []const u8) ?Entry {
    for (served.entries) |held| if (std.mem.eql(u8, held.name, name)) return held;
    return null;
}

/// The closing line of a failed verification: how many units differed and which stage store to remove to build from scratch.
pub fn closing(a: std.mem.Allocator, report: *std.ArrayList(u8), differing: usize, cache: []const u8) std.mem.Allocator.Error!void {
    try report.print(a, "error: --verify-cache: {d} unit(s) built from the stage records differ from a fresh build: a stage record was served under a key " ++
        "that does not cover its inputs; remove {s}/stages-packed-v1 (and the shared stage store) to build from scratch, and report the program\n", .{ differing, cache });
}

fn release(a: std.mem.Allocator, served: Served) void {
    for (served.entries) |entry| {
        a.free(entry.name);
        a.free(entry.source_path);
    }
    a.free(served.entries);
}

fn fakeUnit(name: []const u8, text: []const u8) emit_units.Unit {
    return .{ .name = name, .source_path = "main.selka", .kind = .module, .llvm = text, .dependencies = .{} };
}

test "units with the same text agree and a unit whose text differs is named" {
    const a = std.testing.allocator;
    const first = [_]emit_units.Unit{ fakeUnit("module-a", "define a"), fakeUnit("module-b", "define b") };
    const served = try collect(a, &first);
    defer release(a, served);
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    const same = try differences(a, &report, served, &first);
    try std.testing.expectEqual(@as(usize, 0), same.differing);
    try std.testing.expectEqual(@as(u32, 2), same.compared);
    try std.testing.expectEqualStrings("", report.items);
    const second = [_]emit_units.Unit{ fakeUnit("module-b", "define b"), fakeUnit("module-a", "define a2") };
    const other = try differences(a, &report, served, &second);
    try std.testing.expectEqual(@as(usize, 1), other.differing);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "module unit module-a (main.selka) is emitted from the cached stages as text") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "module-b") == null);
}

test "a unit only one pass emitted is named, and a unit with no text is not compared" {
    const a = std.testing.allocator;
    const first = [_]emit_units.Unit{ fakeUnit("module-a", "define a"), fakeUnit("module-d", "") };
    const served = try collect(a, &first);
    defer release(a, served);
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    const other = [_]emit_units.Unit{ fakeUnit("module-c", "define c"), fakeUnit("module-d", "define d") };
    const found = try differences(a, &report, served, &other);
    try std.testing.expectEqual(@as(usize, 2), found.differing);
    try std.testing.expectEqual(@as(u32, 0), found.compared);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "module unit module-c (main.selka) was emitted by the fresh build and not by") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "module unit module-a (main.selka) was emitted by the build that served the stage records and not by the fresh build") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "module-d") == null);
}

test "the linkage keyword of a source function's definition moves the digest, as does any other change" {
    const hidden = "declare void @f()\ndefine hidden fastcc i1 @\"my.m::f\"(i64 %p0) {\n}\ndefine internal i64 @helper() {\n}\n";
    const internal = "declare void @f()\ndefine internal fastcc i1 @\"my.m::f\"(i64 %p0) {\n}\ndefine internal i64 @helper() {\n}\n";
    const renamed = "declare void @f()\ndefine hidden fastcc i1 @\"my.m::g\"(i64 %p0) {\n}\ndefine internal i64 @helper() {\n}\n";
    try std.testing.expectEqualSlices(u8, &digestOf(hidden), &digestOf(hidden));
    try std.testing.expect(!std.mem.eql(u8, &digestOf(hidden), &digestOf(internal)));
    try std.testing.expect(!std.mem.eql(u8, &digestOf(hidden), &digestOf(renamed)));
}

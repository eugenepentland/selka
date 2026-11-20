//! The test vectors of spec §15, checked in under `test/engine/vectors/` and frozen: key derivations, record bytes, and
//! validation scenarios over an in-memory filesystem. The Selka port reads and writes the same bytes and passes the same
//! files.
//!
//! `keys.json`, `records.json` and `records2.json` are generated from the definitions below: run this test with
//! `SELKA_ENGINE_WRITE_VECTORS=test/engine/vectors` to write them, review the diff, and commit. A change to the bytes
//! of any is a format change and needs a version bump. `validation.json` and `parts.json` are written by hand.
//!
//! `records.json` and `validation.json` are record format 1 and are frozen; `records2.json` (format 2: the parts table and
//! the projection read, tag 7) and `parts.json` (scenarios that read parts) are the format 2 vectors. A format 2 reader
//! passes both sets: format 1 records decode as records with no parts.
const std = @import("std");
const digest_rules = @import("digest.zig");
const record_rules = @import("record.zig");
const world_rules = @import("world.zig");
const script = @import("kinds/script.zig");
const fixture_rules = @import("fixture_test.zig");
const paths = @import("core_test_options");
const Digest = digest_rules.Digest;
const Fixture = fixture_rules.Fixture;

const directory = "test/engine/vectors";
const write_variable = "SELKA_ENGINE_WRITE_VECTORS";
const format_name = "selka-engine-vectors-v1";
const format_two_name = "selka-engine-vectors-v2";

/// Why a vector check could not finish: a file, a parse, a mismatch or the allocator.
const Failure = fixture_rules.Failure || record_rules.EncodeError || std.json.ParseError(std.json.Scanner) || std.Io.Dir.ReadFileAllocError || std.Io.Dir.WriteFileError ||
    error{ TestExpectedEqual, TestUnexpectedResult, Malformed, UnknownFormat };

fn hexText(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{x}", .{bytes});
}

fn fromHex(a: std.mem.Allocator, text: []const u8) Failure![]u8 {
    const out = try a.alloc(u8, text.len / 2);
    _ = std.fmt.hexToBytes(out, text) catch return error.TestUnexpectedResult;
    return out;
}

fn digestOf(text: []const u8) Failure!Digest {
    return digest_rules.parseHex(text) orelse error.TestUnexpectedResult;
}

/// The bytes the files hold now, or a mismatch with `produced`; when `SELKA_ENGINE_WRITE_VECTORS` names a directory the
/// produced text is written there instead.
fn checkOrWrite(a: std.mem.Allocator, name: []const u8, produced: []const u8) Failure!void {
    if (paths.lookup(std.testing.environ, write_variable)) |target| {
        const path = try std.fs.path.join(a, &.{ target, name });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = produced });
        return;
    }
    const path = try std.fs.path.join(a, &.{ directory, name });
    const frozen = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20));
    if (!std.mem.eql(u8, frozen, produced)) return error.TestExpectedEqual;
}

fn render(a: std.mem.Allocator, value: anytype) Failure![]const u8 {
    const text = try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2, .emit_null_optional_fields = false });
    return std.fmt.allocPrint(a, "{s}\n", .{text});
}

// ---------------------------------------------------------------------------------------------------- keys

const Pattern = struct { generator: []const u8, length: usize };

const KeyVector = struct {
    name: []const u8,
    kind: []const u8,
    identity_hex: []const u8,
    argument_hex: ?[]const u8 = null,
    argument_pattern: ?Pattern = null,
    key_hex: []const u8,
};

const ListingVector = struct { names: []const []const u8, digest_hex: []const u8 };

const KeyFile = struct { format: []const u8, keys: []const KeyVector, listings: []const ListingVector };

const pattern_name = "byte_i_mod_251";

fn patternBytes(a: std.mem.Allocator, pattern: Pattern) Failure![]u8 {
    if (!std.mem.eql(u8, pattern.generator, pattern_name)) return error.TestUnexpectedResult;
    const out = try a.alloc(u8, pattern.length);
    for (out, 0..) |*byte, at| byte.* = @intCast(at % 251);
    return out;
}

fn argumentOf(a: std.mem.Allocator, vector: KeyVector) Failure![]const u8 {
    if (vector.argument_pattern) |pattern| return patternBytes(a, pattern);
    return fromHex(a, vector.argument_hex orelse return error.TestUnexpectedResult);
}

fn keyVector(a: std.mem.Allocator, name: []const u8, kind: []const u8, identity: Digest, argument: ?[]const u8, pattern: ?Pattern) Failure!KeyVector {
    var vector: KeyVector = .{ .name = name, .kind = kind, .identity_hex = &digest_rules.hex(identity), .key_hex = "" };
    vector.identity_hex = try a.dupe(u8, vector.identity_hex);
    if (pattern) |described| vector.argument_pattern = described else vector.argument_hex = try hexText(a, argument.?);
    const bytes = try argumentOf(a, vector);
    vector.key_hex = try a.dupe(u8, &digest_rules.hex(digest_rules.key(kind, identity, bytes)));
    return vector;
}

fn sequence(first: u8) Digest {
    var out: Digest = undefined;
    for (&out, 0..) |*byte, at| byte.* = first +% @as(u8, @intCast(at));
    return out;
}

fn producedKeys(a: std.mem.Allocator) Failure![]const u8 {
    const keys = try a.alloc(KeyVector, 3);
    keys[0] = try keyVector(a, "an empty argument", "test-plan", sequence(1), "", null);
    keys[1] = try keyVector(a, "a path as the argument", "test-exec", digest_rules.hash("selka-vector-identity"), "tests/lang/strings.selka::test_split", null);
    keys[2] = try keyVector(a, "a one mebibyte argument", "engine-probe", @splat(0xff), null, .{ .generator = pattern_name, .length = 1 << 20 });
    const listings = try a.alloc(ListingVector, 2);
    listings[0] = try listingVector(a, &.{});
    listings[1] = try listingVector(a, &.{ "main.selka", "helpers.selka", "Zeta.selka" });
    return render(a, KeyFile{ .format = format_name, .keys = keys, .listings = listings });
}

fn listingVector(a: std.mem.Allocator, names: []const []const u8) Failure!ListingVector {
    const digest = try digest_rules.listingDigest(a, names);
    return .{ .names = names, .digest_hex = try a.dupe(u8, &digest_rules.hex(digest)) };
}

test "the key vectors are reproduced: three keys and two listing digests" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try checkOrWrite(arena.allocator(), "keys.json", try producedKeys(arena.allocator()));
}

test "the checked-in key vectors derive the keys they list" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, directory ++ "/keys.json", a, .limited(1 << 20));
    const file = try std.json.parseFromSliceLeaky(KeyFile, a, text, .{});
    try std.testing.expectEqualStrings(format_name, file.format);
    try std.testing.expectEqual(@as(usize, 3), file.keys.len);
    try std.testing.expectEqual(@as(usize, 0), (try argumentOf(a, file.keys[0])).len);
    try std.testing.expectEqual(@as(usize, 1 << 20), (try argumentOf(a, file.keys[2])).len);
    try std.testing.expectEqualStrings(file.keys[1].key_hex, &digest_rules.hex(digest_rules.key(file.keys[1].kind, try digestOf(file.keys[1].identity_hex), try argumentOf(a, file.keys[1]))));
    try std.testing.expectEqualStrings(file.keys[2].key_hex, &digest_rules.hex(digest_rules.key(file.keys[2].kind, try digestOf(file.keys[2].identity_hex), try argumentOf(a, file.keys[2]))));
    try std.testing.expectEqualStrings(file.keys[0].key_hex, &digest_rules.hex(digest_rules.key(file.keys[0].kind, try digestOf(file.keys[0].identity_hex), "")));
    try std.testing.expectEqualStrings(file.listings[1].digest_hex, &digest_rules.hex(try digest_rules.listingDigest(a, file.listings[1].names)));
}

// ------------------------------------------------------------------------------------------------- records

const StatJson = struct { inode: u64, size: u64, mtime: i64, ctime: i64 };

const PartSightJson = struct { name: []const u8, present: bool, digest_hex: []const u8 };

const PartJson = struct { name: []const u8, digest_hex: []const u8 };

const ReadJson = struct {
    tag: []const u8,
    path: ?[]const u8 = null,
    name: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    present: ?bool = null,
    set: ?bool = null,
    opened: ?bool = null,
    placement: ?bool = null,
    filter: ?u8 = null,
    value: ?[]const u8 = null,
    digest_hex: ?[]const u8 = null,
    key_hex: ?[]const u8 = null,
    stat: ?StatJson = null,
    parts: ?[]const PartSightJson = null,
};

const PayloadJson = struct { inline_hex: ?[]const u8 = null, object_hex: ?[]const u8 = null };

const RecordVector = struct {
    name: []const u8,
    kind: []const u8,
    identity_hex: []const u8,
    key_hex: []const u8,
    argument_hex: []const u8,
    result_hex: []const u8,
    payload: PayloadJson,
    parts: ?[]const PartJson = null,
    reads: []const ReadJson,
    bytes_hex: []const u8,
};

const RecordFile = struct { format: []const u8, records: []const RecordVector };

fn readToJson(a: std.mem.Allocator, read: record_rules.Read) Failure!ReadJson {
    switch (read) {
        .file => |file| return .{
            .tag = "file",
            .path = file.path,
            .present = file.present,
            .digest_hex = try a.dupe(u8, &digest_rules.hex(file.digest)),
            .stat = .{ .inode = file.stat.inode, .size = file.stat.size, .mtime = file.stat.mtime, .ctime = file.stat.ctime },
        },
        .exists => |probe| return .{ .tag = "exists", .path = probe.path, .present = probe.present },
        .listing => |listing| return .{ .tag = "listing", .path = listing.path, .filter = listing.filter, .opened = listing.opened, .digest_hex = try a.dupe(u8, &digest_rules.hex(listing.digest)) },
        .variable => |variable| return .{ .tag = "variable", .name = variable.name, .set = variable.set, .value = variable.value, .placement = variable.placement },
        .tool => |tool| return .{ .tag = "tool", .path = tool.path, .digest_hex = try a.dupe(u8, &digest_rules.hex(tool.identity)) },
        .query => |query| return .{ .tag = "query", .kind = query.kind, .key_hex = try a.dupe(u8, &digest_rules.hex(query.key)), .digest_hex = try a.dupe(u8, &digest_rules.hex(query.result)) },
        .part => |part| {
            const sights = try a.alloc(PartSightJson, part.parts.len);
            for (part.parts, sights) |sight, *json| json.* = .{ .name = sight.name, .present = sight.present, .digest_hex = try a.dupe(u8, &digest_rules.hex(sight.digest)) };
            return .{ .tag = "part", .kind = part.kind, .key_hex = try a.dupe(u8, &digest_rules.hex(part.key)), .parts = sights };
        },
    }
}

fn readFromJson(a: std.mem.Allocator, json: ReadJson) Failure!record_rules.Read {
    if (std.mem.eql(u8, json.tag, "file")) {
        const stat = json.stat orelse return error.TestUnexpectedResult;
        return .{ .file = .{
            .path = json.path orelse return error.TestUnexpectedResult,
            .present = json.present orelse return error.TestUnexpectedResult,
            .digest = try digestOf(json.digest_hex orelse return error.TestUnexpectedResult),
            .stat = .{ .inode = stat.inode, .size = stat.size, .mtime = stat.mtime, .ctime = stat.ctime },
        } };
    }
    if (std.mem.eql(u8, json.tag, "exists")) return .{ .exists = .{ .path = json.path orelse return error.TestUnexpectedResult, .present = json.present orelse return error.TestUnexpectedResult } };
    if (std.mem.eql(u8, json.tag, "listing")) return .{ .listing = .{
        .path = json.path orelse return error.TestUnexpectedResult,
        .filter = json.filter orelse return error.TestUnexpectedResult,
        .opened = json.opened orelse return error.TestUnexpectedResult,
        .digest = try digestOf(json.digest_hex orelse return error.TestUnexpectedResult),
    } };
    if (std.mem.eql(u8, json.tag, "variable")) return .{ .variable = .{
        .name = json.name orelse return error.TestUnexpectedResult,
        .set = json.set orelse return error.TestUnexpectedResult,
        .value = json.value orelse return error.TestUnexpectedResult,
        .placement = json.placement orelse return error.TestUnexpectedResult,
    } };
    if (std.mem.eql(u8, json.tag, "tool")) return .{ .tool = .{ .path = json.path orelse return error.TestUnexpectedResult, .identity = try digestOf(json.digest_hex orelse return error.TestUnexpectedResult) } };
    if (std.mem.eql(u8, json.tag, "query")) return .{ .query = .{
        .kind = json.kind orelse return error.TestUnexpectedResult,
        .key = try digestOf(json.key_hex orelse return error.TestUnexpectedResult),
        .result = try digestOf(json.digest_hex orelse return error.TestUnexpectedResult),
    } };
    if (std.mem.eql(u8, json.tag, "part")) {
        const named = json.parts orelse return error.TestUnexpectedResult;
        const sights = try a.alloc(record_rules.PartSight, named.len);
        for (named, sights) |item, *sight| sight.* = .{ .name = item.name, .present = item.present, .digest = try digestOf(item.digest_hex) };
        return .{ .part = .{
            .kind = json.kind orelse return error.TestUnexpectedResult,
            .key = try digestOf(json.key_hex orelse return error.TestUnexpectedResult),
            .parts = sights,
        } };
    }
    return error.TestUnexpectedResult;
}

fn recordOf(a: std.mem.Allocator, vector: RecordVector) Failure!record_rules.Record {
    const reads = try a.alloc(record_rules.Read, vector.reads.len);
    for (vector.reads, reads) |json, *read| read.* = try readFromJson(a, json);
    const payload: record_rules.Payload = if (vector.payload.inline_hex) |text|
        .{ .inline_bytes = try fromHex(a, text) }
    else
        .{ .object = try digestOf(vector.payload.object_hex orelse return error.TestUnexpectedResult) };
    const named = vector.parts orelse &.{};
    const parts = try a.alloc(record_rules.Part, named.len);
    for (named, parts) |item, *part| part.* = .{ .name = item.name, .digest = try digestOf(item.digest_hex) };
    return .{
        .parts = parts,
        .kind = vector.kind,
        .identity = try digestOf(vector.identity_hex),
        .key = try digestOf(vector.key_hex),
        .argument = try fromHex(a, vector.argument_hex),
        .result = try digestOf(vector.result_hex),
        .payload = payload,
        .reads = reads,
    };
}

/// The vector of `source` written in format `version`. A format 1 vector has no `parts` field; a format 2 vector always has.
fn vectorOf(a: std.mem.Allocator, name: []const u8, source: record_rules.Record, version: u32) Failure!RecordVector {
    const bytes = try record_rules.encodeFormat(a, source, version);
    const reads = try a.alloc(ReadJson, source.reads.len);
    for (source.reads, reads) |read, *json| json.* = try readToJson(a, read);
    var parts: ?[]PartJson = null;
    if (version >= 2) {
        const named = try a.alloc(PartJson, source.parts.len);
        for (source.parts, named) |part, *json| json.* = .{ .name = part.name, .digest_hex = try a.dupe(u8, &digest_rules.hex(part.digest)) };
        parts = named;
    }
    return .{
        .parts = parts,
        .name = name,
        .kind = source.kind,
        .identity_hex = try a.dupe(u8, &digest_rules.hex(source.identity)),
        .key_hex = try a.dupe(u8, &digest_rules.hex(source.key)),
        .argument_hex = try hexText(a, source.argument),
        .result_hex = try a.dupe(u8, &digest_rules.hex(source.result)),
        .payload = switch (source.payload) {
            .inline_bytes => |inline_bytes| .{ .inline_hex = try hexText(a, inline_bytes) },
            .object => |object| .{ .object_hex = try a.dupe(u8, &digest_rules.hex(object)) },
        },
        .reads = reads,
        .bytes_hex = try hexText(a, bytes),
    };
}

// The record builders copy their read and part lists into `a`: a `&.{ ... }` list with run-time digests is a
// temporary of the builder's own frame, so a record returned with it would point into a dead frame (until
// 4 November the checked-in records2.json held a digest partly overwritten that way, which only a build with
// another stack layout, the edit check's coverage variant, did not reproduce).

/// A record with one read of every tag and an inline payload.
fn everyTag(a: std.mem.Allocator, identity: Digest) Failure!record_rules.Record {
    const argument = "tests/lang/strings.selka::test_split";
    const verdict = "verdict:pass\n";
    return .{
        .kind = "test-exec",
        .identity = identity,
        .key = digest_rules.key("test-exec", identity, argument),
        .argument = argument,
        .result = digest_rules.hash(verdict),
        .payload = .{ .inline_bytes = verdict },
        .reads = try a.dupe(record_rules.Read, &.{
            .{ .file = .{ .path = "tests/lang/strings.selka", .present = true, .digest = digest_rules.hash("source"), .stat = .{ .inode = 4123, .size = 6, .mtime = 1_761_800_000_123_456_789, .ctime = 1_761_800_000_234_567_890 } } },
            .{ .file = .{ .path = "tests/lang/missing.selka", .present = false, .digest = @splat(0), .stat = world_rules.Stat.none } },
            .{ .exists = .{ .path = "tests/lang/selka.json", .present = false } },
            .{ .listing = .{ .path = "tests/lang", .filter = 1, .opened = true, .digest = digest_rules.hash("listing") } },
            .{ .listing = .{ .path = "tests/nowhere", .filter = 0, .opened = false, .digest = @splat(0) } },
            .{ .variable = .{ .name = "SOURCE_DATE_EPOCH", .set = true, .value = "1761800000", .placement = false } },
            .{ .variable = .{ .name = "TMPDIR", .set = false, .value = "", .placement = true } },
            .{ .tool = .{ .path = "zig", .identity = digest_rules.hash("toolchain") } },
            .{ .query = .{ .kind = "test-plan", .key = digest_rules.hash("plan key"), .result = digest_rules.hash("plan result") } },
        }),
    };
}

/// A record whose payload is an object, with a result identity that is not the payload's digest.
fn withObject(a: std.mem.Allocator, identity: Digest) Failure!record_rules.Record {
    return .{
        .kind = "engine-probe",
        .identity = identity,
        .key = digest_rules.key("engine-probe", identity, ""),
        .argument = "",
        .result = digest_rules.hash("a smaller identity of the result"),
        .payload = .{ .object = digest_rules.hash("the payload bytes") },
        .reads = try a.dupe(record_rules.Read, &.{
            .{ .file = .{ .path = "big.bin", .present = true, .digest = digest_rules.hash("big"), .stat = .{ .inode = 9, .size = 5000, .mtime = 5, .ctime = 6 } } },
        }),
    };
}

fn producedRecords(a: std.mem.Allocator) Failure![]const u8 {
    const records = try a.alloc(RecordVector, 2);
    records[0] = try vectorOf(a, "one read of every tag and an inline payload", try everyTag(a, sequence(1)), 1);
    records[1] = try vectorOf(a, "an object payload and a result identity of its own", try withObject(a, @splat(0xab)), 1);
    return render(a, RecordFile{ .format = format_name, .records = records });
}

test "the record vectors are reproduced: every tag with an inline payload, and an object payload" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try checkOrWrite(arena.allocator(), "records.json", try producedRecords(arena.allocator()));
}

/// Check one checked-in record: its fields encode to its bytes in format `version`, and its bytes decode to its fields.
fn checkRecord(a: std.mem.Allocator, vector: RecordVector, version: u32) Failure!void {
    const bytes = try fromHex(a, vector.bytes_hex);
    const encoded = try record_rules.encodeFormat(a, try recordOf(a, vector), version);
    if (!std.mem.eql(u8, bytes, encoded)) return error.TestExpectedEqual;
    const decoded = try record_rules.decode(a, bytes);
    const again = try vectorOf(a, vector.name, decoded, version);
    if (!std.mem.eql(u8, try render(a, again), try render(a, vector))) return error.TestExpectedEqual;
}

test "the checked-in record vectors decode to their fields and encode to their bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, directory ++ "/records.json", a, .limited(1 << 20));
    const file = try std.json.parseFromSliceLeaky(RecordFile, a, text, .{});
    try std.testing.expectEqual(@as(usize, 2), file.records.len);
    try std.testing.expectEqual(@as(usize, 9), file.records[0].reads.len);
    try checkRecord(a, file.records[0], 1);
    try checkRecord(a, file.records[1], 1);
    // A format 2 reader reads them as records with no parts.
    try std.testing.expectEqual(@as(usize, 0), (try record_rules.decode(a, try fromHex(a, file.records[0].bytes_hex))).parts.len);
    try std.testing.expectEqual(@as(usize, 0), (try record_rules.decode(a, try fromHex(a, file.records[1].bytes_hex))).parts.len);
    // Every digest in the file is the hash its builder names, never bytes of a dead frame.
    const first = try record_rules.decode(a, try fromHex(a, file.records[0].bytes_hex));
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("source"), &first.reads[0].file.digest);
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("plan result"), &first.reads[8].query.result);
}

// ------------------------------------------------------------------------------------------- records, format 2

/// A record with a parts table, a projection read of two named parts (one the dependency does not publish), a whole-result
/// read of the same dependency and a file read.
fn withParts(a: std.mem.Allocator, identity: Digest) Failure!record_rules.Record {
    const argument = "src/lexer.selka";
    const payload = "interface of src/lexer.selka";
    const seen = try a.dupe(record_rules.PartSight, &.{
        .{ .name = "decl:Token", .present = true, .digest = digest_rules.hash("record Token") },
        .{ .name = "decl:next_token", .present = true, .digest = digest_rules.hash("func next_token") },
        .{ .name = "decl:retired", .present = false, .digest = @splat(0) },
    });
    return .{
        .kind = "module-interface",
        .identity = identity,
        .key = digest_rules.key("module-interface", identity, argument),
        .argument = argument,
        .result = digest_rules.hash(payload),
        .payload = .{ .inline_bytes = payload },
        .parts = try a.dupe(record_rules.Part, &.{
            .{ .name = "decl:Token", .digest = digest_rules.hash("record Token") },
            .{ .name = "decl:next_token", .digest = digest_rules.hash("func next_token") },
            .{ .name = "imports", .digest = digest_rules.hash("[]") },
        }),
        .reads = try a.dupe(record_rules.Read, &.{
            .{ .file = .{ .path = "src/lexer.selka", .present = true, .digest = digest_rules.hash("source"), .stat = .{ .inode = 77, .size = 6, .mtime = 1_761_800_000_000_000_001, .ctime = 1_761_800_000_000_000_002 } } },
            .{ .part = .{ .kind = "module-syntax", .key = digest_rules.hash("syntax key"), .parts = seen } },
            .{ .query = .{ .kind = "module-syntax", .key = digest_rules.hash("syntax key"), .result = digest_rules.hash("syntax result") } },
            .{ .part = .{ .kind = "module-syntax", .key = digest_rules.hash("other key"), .parts = &.{} } },
        }),
    };
}

/// A format 2 record that holds nothing new: an empty parts table and no projection read.
fn withoutParts(a: std.mem.Allocator, identity: Digest) Failure!record_rules.Record {
    return .{
        .kind = "engine-probe",
        .identity = identity,
        .key = digest_rules.key("engine-probe", identity, ""),
        .argument = "",
        .result = digest_rules.hash("x"),
        .payload = .{ .inline_bytes = "x" },
        .reads = try a.dupe(record_rules.Read, &.{.{ .exists = .{ .path = "selka.json", .present = true } }}),
    };
}

/// A format 2 record with an object payload, a parts table and no reads.
fn objectWithParts(a: std.mem.Allocator, identity: Digest) Failure!record_rules.Record {
    return .{
        .kind = "module-check",
        .identity = identity,
        .key = digest_rules.key("module-check", identity, "src/main.selka"),
        .argument = "src/main.selka",
        .result = digest_rules.hash("a smaller identity of the checked bodies"),
        .payload = .{ .object = digest_rules.hash("the checked bodies") },
        .parts = try a.dupe(record_rules.Part, &.{.{ .name = "body:main", .digest = digest_rules.hash("main body") }}),
        .reads = &.{},
    };
}

fn producedRecordsTwo(a: std.mem.Allocator) Failure![]const u8 {
    const records = try a.alloc(RecordVector, 3);
    records[0] = try vectorOf(a, "a parts table, a projection read of present and absent parts, and a whole-result read", try withParts(a, sequence(1)), 2);
    records[1] = try vectorOf(a, "an empty parts table", try withoutParts(a, @splat(0xcd)), 2);
    records[2] = try vectorOf(a, "an object payload with a parts table and no reads", try objectWithParts(a, @splat(0xef)), 2);
    return render(a, RecordFile{ .format = format_two_name, .records = records });
}

test "the format 2 record vectors are reproduced: a parts table, a projection read, an empty table, an object payload" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try checkOrWrite(arena.allocator(), "records2.json", try producedRecordsTwo(arena.allocator()));
}

test "the checked-in format 2 record vectors decode to their fields and encode to their bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, directory ++ "/records2.json", a, .limited(1 << 20));
    const file = try std.json.parseFromSliceLeaky(RecordFile, a, text, .{});
    try std.testing.expectEqualStrings(format_two_name, file.format);
    try std.testing.expectEqual(@as(usize, 3), file.records.len);
    try std.testing.expectEqual(@as(usize, 4), file.records[0].reads.len);
    try std.testing.expectEqual(@as(usize, 3), file.records[0].parts.?.len);
    for (file.records) |vector| {
        try checkRecord(a, vector, 2);
        const bytes = try fromHex(a, vector.bytes_hex);
        try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bytes[record_rules.magic.len..][0..4], .little));
    }
    // The projection read keeps what it saw of a part that was not there.
    const decoded = try record_rules.decode(a, try fromHex(a, file.records[0].bytes_hex));
    try std.testing.expect(!decoded.reads[1].part.parts[2].present);
    try std.testing.expectEqual(@as(usize, 0), decoded.reads[3].part.parts.len);
    // Every digest in the file is the hash its builder names, never bytes of a dead frame.
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("source"), &decoded.reads[0].file.digest);
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("record Token"), &decoded.reads[1].part.parts[0].digest);
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("[]"), &decoded.parts[2].digest);
    const object = try record_rules.decode(a, try fromHex(a, file.records[2].bytes_hex));
    try std.testing.expectEqualSlices(u8, &digest_rules.hash("main body"), &object.parts[0].digest);
}

// ------------------------------------------------------------------------------------------------ validation

const Edit = struct {
    write: ?[2][]const u8 = null,
    touch: ?[]const u8 = null,
    replace: ?[2][]const u8 = null,
    remove: ?[]const u8 = null,
    set_variable: ?[2][]const u8 = null,
    unset_variable: ?[]const u8 = null,
    advance_ms: ?i64 = null,
};

const Expect = struct { recomputed: u64, served: u64, early_cutoffs: u64, reads: u64 };

const Step = struct { edits: []const Edit, query: []const u32, results: []const []const u8, expect: Expect };

const Scenario = struct { name: []const u8, graph: script.Graph, steps: []const Step };

const ScenarioFile = struct { format: []const u8, about: []const u8, scenarios: []const Scenario };

fn applyEdit(fx: *Fixture, edit: Edit) Failure!void {
    if (edit.write) |pair| try fx.files.write(pair[0], pair[1]);
    if (edit.touch) |path| fx.files.touch(path);
    if (edit.replace) |pair| try fx.files.replace(pair[0], pair[1]);
    if (edit.remove) |path| fx.files.remove(path);
    if (edit.set_variable) |pair| try fx.files.setVariable(pair[0], pair[1]);
    if (edit.unset_variable) |name| fx.files.unsetVariable(name);
    if (edit.advance_ms) |milliseconds| fx.files.advance(milliseconds * std.time.ns_per_ms);
}

/// Run one scenario; the message names the first step that disagrees with its expectation and what it saw, or null when all
/// steps agree.
fn runScenario(gpa: std.mem.Allocator, a: std.mem.Allocator, scenario: Scenario) Failure!?[]const u8 {
    const fx = try Fixture.create(gpa, scenario.graph);
    defer fx.destroy();
    for (scenario.steps, 0..) |step, at| {
        try fx.restart(.{});
        for (step.edits) |edit| try applyEdit(fx, edit);
        fx.files.resetCounters();
        for (step.query, step.results) |node, want| {
            const got = try fx.run(node);
            if (!std.mem.eql(u8, got, want)) {
                const message = try std.fmt.allocPrint(a, "{s}, step {d}: node {d} gave \"{s}\", the file says \"{s}\"", .{ scenario.name, at, node, got, want });
                return message;
            }
        }
        const numbers = fx.numbers();
        const seen: Expect = .{
            .recomputed = numbers.count(.recomputed),
            .served = numbers.count(.served),
            .early_cutoffs = numbers.count(.early_cutoffs),
            .reads = fx.files.count("reads"),
        };
        if (!std.meta.eql(seen, step.expect)) {
            const message = try std.fmt.allocPrint(a, "{s}, step {d}: recomputed {d}, served {d}, early cutoffs {d}, reads {d}; the file says {d}, {d}, {d}, {d}", .{
                scenario.name,          at,                 seen.recomputed,           seen.served,       seen.early_cutoffs, seen.reads,
                step.expect.recomputed, step.expect.served, step.expect.early_cutoffs, step.expect.reads,
            });
            return message;
        }
    }
    return null;
}

/// The first disagreement of any scenario of `file`, as a message, or null when all agree.
fn firstDisagreement(gpa: std.mem.Allocator, a: std.mem.Allocator, file: ScenarioFile) Failure!?[]const u8 {
    for (file.scenarios) |scenario| {
        if (try runScenario(gpa, a, scenario)) |message| return message;
    }
    return null;
}

test "every validation scenario of the checked-in vectors behaves as it says" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, directory ++ "/validation.json", a, .limited(1 << 20));
    const file = try std.json.parseFromSliceLeaky(ScenarioFile, a, text, .{});
    try std.testing.expectEqualStrings(format_name, file.format);
    try std.testing.expect(file.scenarios.len >= 10);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstDisagreement(std.testing.allocator, a, file));
}

test "every projection-read scenario of the format 2 vectors behaves as it says" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, directory ++ "/parts.json", a, .limited(1 << 20));
    const file = try std.json.parseFromSliceLeaky(ScenarioFile, a, text, .{});
    try std.testing.expectEqualStrings(format_two_name, file.format);
    try std.testing.expect(file.scenarios.len >= 6);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstDisagreement(std.testing.allocator, a, file));
}

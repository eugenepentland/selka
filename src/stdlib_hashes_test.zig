//! BLAKE3 digests run in the prebuilt Zig runtime; these programs pin the vectors and the `Digest` value from the host side.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const operations = @import("buffer_operations.zig");

test "blake3 matches the reference vectors for bytes, text and a borrowed slice" {
    try fixture.run(t.allocator, "import hashes\n" ++
        "import hex\n" ++
        "func main() -> int:\n" ++
        "    if hashes.hex(hashes.blake3(b\"\")) != \"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262\":\n" ++
        "        return 1\n" ++
        "    const abc = \"6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85\"\n" ++
        "    if hashes.hex(hashes.blake3(b\"abc\")) != abc or hashes.hex(hashes.blake3_text(\"abc\")) != abc:\n" ++
        "        return 2\n" ++
        "    const wide = b\"xxabcxx\"\n" ++
        "    if hashes.hex(hashes.blake3(wide[2:5])) != abc:\n" ++
        "        return 3\n" ++
        "    if len(hashes.blake3_bytes(wide)) != 32 or hex.encode(hashes.blake3_bytes(wide)) == abc:\n" ++
        "        return 4\n" ++
        "    return 42\n", 42);
}

test "a digest is a value: equality, dictionary key, byte and hex round trips" {
    try fixture.run(t.allocator, "import hashes\n" ++
        "func main() -> int:\n" ++
        "    const digest = hashes.blake3(b\"abc\")\n" ++
        "    mut seen: dict[hashes.Digest, int] = {}\n" ++
        "    seen[digest] = 7\n" ++
        "    if seen[hashes.blake3_text(\"abc\")] != 7 or digest == hashes.blake3(b\"abd\"):\n" ++
        "        return 1\n" ++
        "    match hashes.from_bytes(hashes.to_bytes(digest)):\n" ++
        "        case Ok(again):\n" ++
        "            if again != digest:\n" ++
        "                return 2\n" ++
        "        case Err(_):\n" ++
        "            return 3\n" ++
        "    match hashes.from_hex(\"00\"):\n" ++
        "        case Ok(_):\n" ++
        "            return 4\n" ++
        "        case Err(_):\n" ++
        "            return 42\n", 42);
}

test "sha256 matches Zig's Sha256 for every length from 0 to 200 and for large inputs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = try digestTable(a);
    const source = try std.fmt.allocPrint(a, "import hashes\n" ++
        "func pattern(length: int) -> bytes:\n" ++
        "    mut octets: int[] = []\n" ++
        "    for index in range(length):\n" ++
        "        append(mut octets, (index * 7 + 3) % 256)\n" ++
        "    return bytes(octets)\n" ++
        "func main() -> int:\n" ++
        "    const expected: str[] = [{s}]\n" ++
        "    mut at = 0\n" ++
        "    for length in range(201):\n" ++
        "        if hashes.sha256(pattern(length)) != expected[at]:\n" ++
        "            return 1\n" ++
        "        at += 1\n" ++
        "    for length in [255, 256, 257, 1000, 4096, 65537, 1000000]:\n" ++
        "        if hashes.sha256(pattern(length)) != expected[at]:\n" ++
        "            return 2\n" ++
        "        at += 1\n" ++
        "    return 42\n", .{table});
    try fixture.run(a, source, 42);
}

/// The quoted SHA-256 digests, from Zig's `Sha256`, of the pattern inputs the guest program hashes: every length from 0 to 200, then the large ones.
fn digestTable(a: std.mem.Allocator) ![]const u8 {
    const lengths = [_]usize{ 255, 256, 257, 1000, 4096, 65537, 1000000 };
    var table: std.ArrayList(u8) = .empty;
    const data = try a.alloc(u8, 1000000);
    for (data, 0..) |*octet, index| octet.* = @intCast((index * 7 + 3) % 256);
    for (0..201) |length| try appendDigest(a, &table, data[0..length]);
    for (lengths) |length| try appendDigest(a, &table, data[0..length]);
    return table.items;
}

fn appendDigest(a: std.mem.Allocator, table: *std.ArrayList(u8), input: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    try table.print(a, "\"{x}\", ", .{digest});
}

test "the sha256 buffer operation kind keeps its number, and the bounded find_any comes after it in the syntax payload" {
    const names = @typeInfo(operations.Kind).@"enum".field_names;
    try t.expectEqualStrings("find_any_range", names[names.len - 1]);
    try t.expectEqual(@as(usize, 116), @backingInt(operations.Kind.sha256));
    try t.expectEqual(@as(usize, 25), @backingInt(operations.Kind.blake3));
    try t.expectEqual(operations.Kind.sha256, operations.method("sha256").?);
}

// FR7 (F-31): SHA-1, written in Selka, against Zig's `Sha1` for every length from 0 to 130 (one, two and three blocks,
// the padding's edge at 55 and 56 octets), and FIPS 180's million `a`. A test program here has no step budget; the
// guest tests in `tests/lang/hashes_sha1.selka` pin the short vectors.
test "sha1 matches Zig's Sha1 for every length from 0 to 130 and for a million a" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = try sha1Table(a);
    const source = try std.fmt.allocPrint(a, "import byte_builder\n" ++
        "import hashes\n" ++
        "func pattern(length: int) -> bytes:\n" ++
        "    mut octets: int[] = []\n" ++
        "    for index in range(length):\n" ++
        "        append(mut octets, (index * 7 + 3) % 256)\n" ++
        "    return bytes(octets)\n" ++
        "func main() -> int:\n" ++
        "    const expected: str[] = [{s}]\n" ++
        "    for length in range(131):\n" ++
        "        if hashes.sha1(pattern(length)) != expected[length]:\n" ++
        "            return length + 1\n" ++
        "    if hashes.sha1(byte_builder.repeat(b\"a\", 1000000)) != expected[131]:\n" ++
        "        return 200\n" ++
        "    if hashes.sha1(b\"a\") != \"86f7e437faa5a7fce15d1ddcb9eaeaea377667b8\" or len(hashes.sha1_bytes(b\"a\")) != 20:\n" ++
        "        return 201\n" ++
        "    return 42\n", .{table});
    try fixture.run(a, source, 42);
}

/// The quoted SHA-1 digests, from Zig's `Sha1`, of the pattern inputs of lengths 0 to 130 and of a million `a`.
fn sha1Table(a: std.mem.Allocator) ![]const u8 {
    var table: std.ArrayList(u8) = .empty;
    const data = try a.alloc(u8, 131);
    for (data, 0..) |*octet, index| octet.* = @intCast((index * 7 + 3) % 256);
    for (0..131) |length| try appendSha1(a, &table, data[0..length]);
    const million = try a.alloc(u8, 1000000);
    @memset(million, 'a');
    try appendSha1(a, &table, million);
    return table.items;
}

fn appendSha1(a: std.mem.Allocator, table: *std.ArrayList(u8), input: []const u8) !void {
    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &digest, .{});
    try table.print(a, "\"{x}\", ", .{digest});
}

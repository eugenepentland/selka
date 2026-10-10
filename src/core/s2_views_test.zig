//! Wave S2 split cursors, offset lists, parse spans and byte-slice lifetime checks.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const modes = [_][]const []const u8{ &.{}, &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--optimize-debug", "--verify-facts" } };

fn check(allocator: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    try checkRun(allocator, source, expected, "");
}

fn checkRun(allocator: std.mem.Allocator, source: []const u8, expected: []const u8, trap: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "s2.my", .data = source });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const input = try std.fmt.allocPrint(a, "{s}/s2.my", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/program", .{root});
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{root});
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for (modes) |flags| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", input, "-o", output, "--cache-dir", cache });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("{s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
        try std.testing.expectEqualStrings(expected, ran.stdout);
        if (trap.len == 0) try std.testing.expectEqualStrings("", ran.stderr) else try std.testing.expect(std.mem.indexOf(u8, ran.stderr, trap) != null);
        try std.testing.expect(ran.term == .exited and ran.term.exited == @as(u8, if (trap.len == 0) 0 else 1));
    }
}

const split_source =
    \\func sizes(text: str, sep: str) -> int:
    \\    mut total = 0
    \\    for part in text.split(sep):
    \\        total += len(part) + 1
    \\    return total
    \\func kept(text: str) -> str[]:
    \\    mut result: str[] = []
    \\    for part in text.split(","):
    \\        result.append(part)
    \\    return result
    \\func main(out: Stream) -> int:
    \\    out.print(sizes(",a,,é,", ","), sizes("", ","), sizes("ababa", "aba"))
    \\    out.print("|".join(kept("a,,é,")))
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-1
test "S2 lazy split keeps empty pieces unicode and escaped values" {
    try expectIr(std.testing.allocator, split_source, "myl_core_split_end", "");
    try check(std.testing.allocator, split_source, "7 1 4\na||é|\n");
}

const fields_source =
    \\func fields(text: str, out: Stream) -> int:
    \\    mut parts = text.split(",")
    \\    out.print(len(parts), len(parts[-1]), parts[0].endswith("7"), parse_int(parts[1]))
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    _ = fields("item7,12,é😀", out)
    \\    _ = fields("x, -9_223_372_036_854_775_808 ,", out)
    \\    _ = fields("x,9223372036854775808,", out)
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-2
test "S2 private split offsets preserve indexed checks and integer grammar" {
    try expectIr(std.testing.allocator, fields_source, "myl_core_str_split_offsets", "");
    try check(std.testing.allocator, fields_source, "3 2 True Some(12)\n3 0 False Some(-9223372036854775808)\n3 0 False None\n");
}

const keys_source =
    \\func count_words(text: str) -> dict[str, int]:
    \\    mut counts: dict[str, int] = {}
    \\    for part in text.split():
    \\        counts[part] = counts.get(part, 0) + 1
    \\    return counts
    \\func main(out: Stream) -> int:
    \\    mut d = count_words("hé a hé b a")
    \\    out.print(d["hé"], d["a"], d["b"])
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-3
test "S2 whitespace split insertion reuses the view probe" {
    try expectIr(std.testing.allocator, keys_source, "str_from_view", "");
    try check(std.testing.allocator, keys_source, "2 2 1\n");
}

const bytes_source =
    \\func scan(data: bytes, lo: int, hi: int, out: Stream) -> int:
    \\    mut part = data[lo:hi]
    \\    out.print(len(part), part == b"\xffb", part.endswith(b"b"), b"b" in part)
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    _ = scan(b"a\xffbc", 1, -1, out)
    \\    _ = scan(b"abc", 5, -8, out)
    \\    return 0
;

// spec: NEW-CORE-S2-VIEW-1
test "S2 byte string views clamp octets and preserve nonunicode values" {
    try expectIr(std.testing.allocator, bytes_source, "str_slice_view", "call bytes myl_core_bytes_slice");
    try check(std.testing.allocator, bytes_source, "2 True True True\n0 False False False\n");
}

fn expectIr(allocator: std.mem.Allocator, source: []const u8, present: []const u8, absent: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, present) != null);
    if (absent.len != 0) try std.testing.expect(std.mem.indexOf(u8, text, absent) == null);
}

const trap_source =
    \\func bad(text: str, sep: str, out: Stream) -> int:
    \\    out.print("before")
    \\    mut parts = text.split(sep)
    \\    out.print("after")
    \\    mut total = 0
    \\    for part in parts:
    \\        total += len(part)
    \\        if total > 0:
    \\            break
    \\    return total
    \\func main(out: Stream) -> int:
    \\    _ = bad("abc", "x"[0:0], out)
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-1
test "S2 empty separator traps before intervening effects or an early loop exit" {
    try checkRun(std.testing.allocator, trap_source, "before\n", "R_EMPTY_SEPARATOR");
}

const bounds_source =
    \\func pick(text: str, index: int) -> int:
    \\    mut parts = text.split(",")
    \\    return len(parts[index])
    \\func main(out: Stream) -> int:
    \\    out.print(pick("a,b", -3))
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-2
test "S2 offset list reads preserve failing negative index traps" {
    try checkRun(std.testing.allocator, bounds_source, "", "R_LIST_BOUNDS");
}

const search_source =
    \\func probe(text: str, needle: str, out: Stream):
    \\    out.print(text.find(needle), text.count(needle), text.startswith(needle), text.endswith(needle), needle in text, text.replace(needle, "Z"))
    \\func main(out: Stream) -> int:
    \\    probe("é😀é", "é", out)
    \\    probe("aaaaaa", "aa", out)
    \\    probe("aaaaaaaaaaaaaaaaaaaaaaaaab", "aaaab", out)
    \\    probe("abc", "z", out)
    \\    out.print("é😀é".find("é", 1, 3), "é😀é".count("", 1, 3), "abc".startswith("", 4))
    \\    return 0
;

// spec: NEW-CORE-S2-SEARCH-1
test "S2 bounded search paths preserve scalar windows and nonoverlapping matches" {
    try check(std.testing.allocator, search_source, "0 2 True True True Z😀Z\n0 3 True True True ZZZ\n21 1 False True True aaaaaaaaaaaaaaaaaaaaaZ\n-1 0 False False False abc\n2 3 False\n");
}

const substring_source =
    \\record Piece:
    \\    value: bytes
    \\func saved(data: bytes) -> Piece:
    \\    mut first = data[1:-1]
    \\    return Piece(value=first[1:4])
    \\func make() -> Piece:
    \\    return saved(b"a" + b"bcdef")
    \\func main(out: Stream) -> int:
    \\    mut p = make()
    \\    mut alias = p.value
    \\    mut d: dict[bytes, int] = {}
    \\    d[p.value] = 7
    \\    out.print(p.value, len(p.value), p.value[0], p.value[-1], p.value == b"cde", d[b"cde"])
    \\    out.print(p.value.hex(), p.value * 2, p.value + b"!", p.value.find(b"d"), p.value < b"zzz")
    \\    out.print(alias[1:], p.value[9:1], p.value.decode())
    \\    return 0
;

// spec: NEW-CORE-S2-VIEW-2
test "S2 stored byte substrings own their parent across nested slices and aliases" {
    try check(std.testing.allocator, substring_source, "b'cde' 3 99 101 True 7\n636465 b'cdecde' b'cde!' 1 True\nb'de' b'' Ok('cde')\n");
}

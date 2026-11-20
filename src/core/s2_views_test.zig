//! Wave S2 split cursors, offset lists, parse spans and byte-slice lifetime checks.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{ "--optimize-debug", "--verify-facts" }, &.{"--release"}, &.{ "--release", "--verify-facts" } };

fn check(allocator: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    try checkRun(allocator, source, expected, "");
}

fn checkRun(allocator: std.mem.Allocator, source: []const u8, expected: []const u8, trap: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = stable_dir.tmpDir(a, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "s2.selka", .data = source });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const input = try std.fmt.allocPrint(a, "{s}/s2.selka", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/program", .{root});
    const cache = try options.suiteCache(a, @src());
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for (modes) |flags| {
        try support.requireReleaseArgs(flags);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", output, "--cache-dir", cache });
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
    \\import strings
    \\
    \\func sizes(text: str, sep: str) -> int:
    \\    mut total = 0
    \\    for part in strings.split(text, sep):
    \\        total += strings.char_count(part) + 1
    \\    return total
    \\func kept(text: str) -> str[]:
    \\    mut result: str[] = []
    \\    for part in strings.split(text, ","):
    \\        append(mut result, copy(part))
    \\    return result
    \\func main(out: Stream) -> int:
    \\    print(out, sizes(",a,,é,", ","), sizes("", ","), sizes("ababa", "aba"))
    \\    print(out, strings.join(kept("a,,é,"), "|"))
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-1
test "S2 lazy split keeps empty pieces unicode and escaped values" {
    try expectIr(std.testing.allocator, split_source, "myl_core_span_split_end", "");
    try check(std.testing.allocator, split_source, "7 1 4\na||é|\n");
}

const fields_source =
    \\import strings
    \\
    \\func fields(text: str, out: Stream) -> int:
    \\    mut parts = strings.split(text, ",")
    \\    print(out, len(parts), strings.char_count(parts[len(parts) - 1]), strings.ends_with(parts[0], "7"), parse_int(parts[1]))
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    _ = fields("item7,12,é😀", out)
    \\    _ = fields("x, -9_223_372_036_854_775_808 ,", out)
    \\    _ = fields("x,9223372036854775808,", out)
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-2
test "S2 private split offsets preserve indexed checks and integer grammar" {
    try expectIr(std.testing.allocator, fields_source, "myl_core_span_split_offsets", "");
    try check(std.testing.allocator, fields_source, "3 2 True Some(12)\n3 0 False Some(-9223372036854775808)\n3 0 False None\n");
}

const keys_source =
    \\import dicts
    \\import strings
    \\
    \\func count_words(text: str) -> dict[str, int]:
    \\    mut counts: dict[str, int] = {}
    \\    for part in strings.words(text):
    \\        counts[copy(part)] = dicts.get(counts, part, 0) + 1
    \\    return counts
    \\func main(out: Stream) -> int:
    \\    mut d = count_words("hé a hé b a")
    \\    print(out, d["hé"], d["a"], d["b"])
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-3
test "S2 whitespace split insertion reuses the view probe" {
    try expectIr(std.testing.allocator, keys_source, "str_from_view", "");
    try check(std.testing.allocator, keys_source, "2 2 1\n");
}

const bytes_source =
    \\import bytes
    \\
    \\func scan(data: bytes, lo: int, hi: int, out: Stream) -> int:
    \\    const part = data[lo:hi]
    \\    print(out, len(part), part == b"\xffb", bytes.ends_with(part, b"b"), b"b" in part)
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    _ = scan(b"a\xffbc", 1, -1, out)
    \\    _ = scan(b"abc", 5, -8, out)
    \\    return 0
;

// spec: NEW-CORE-S2-VIEW-1
test "S2 byte string views clamp octets and preserve nonunicode values" {
    // A slice of the plain `bytes` parameter is a view of a view (`myl_core_view_slice`), not an owned slice (C9 bytes).
    try expectIr(std.testing.allocator, bytes_source, "myl_core_view_slice", "call bytes myl_core_bytes_slice");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `import` comes first, so the clip helper joins between the header and the body.
    const header = "import bytes\n\n";
    const normalized = try std.mem.replaceOwned(u8, a, bytes_source[header.len..], "data[lo:hi]", "data[clip(lo, len(data)):clip(hi, len(data))]");
    const modern = try std.mem.concat(a, u8, &.{
        header,
        "func clip(index: int, size: int) -> int:\n    if index < 0:\n        return max(size + index, 0)\n    return min(index, size)\n\n",
        normalized,
    });
    try expectIr(a, modern, "myl_core_view_slice", "call bytes myl_core_bytes_slice");
    // Original computed negative bounds now trap; retain that source unchanged.
    try checkRun(std.testing.allocator, bytes_source, "", "negative indexes are not allowed");
    try check(a, modern, "2 True True True\n0 False False False\n");
}

fn expectIr(allocator: std.mem.Allocator, source: []const u8, present: []const u8, absent: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const text = try support.optimizedTextOfProject(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, present) != null);
    if (absent.len != 0) try std.testing.expect(std.mem.indexOf(u8, text, absent) == null);
}

const trap_source =
    \\import strings
    \\
    \\func bad(text: str, sep: str, out: Stream) -> int:
    \\    print(out, "before")
    \\    mut parts = strings.split(text, sep)
    \\    print(out, "after")
    \\    mut total = 0
    \\    for part in parts:
    \\        total += strings.char_count(part)
    \\        if total > 0:
    \\            break
    \\    return total
    \\func main(out: Stream) -> int:
    \\    _ = bad("abc", strings.char_slice("x", 0, 0), out)
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-1
test "S2 empty separator traps before intervening effects or an early loop exit" {
    try checkRun(std.testing.allocator, trap_source, "before\n", "R_EMPTY_SEPARATOR");
}

const bounds_source =
    \\import strings
    \\
    \\func pick(text: str, index: int) -> int:
    \\    mut parts = strings.split(text, ",")
    \\    return strings.char_count(parts[index])
    \\func main(out: Stream) -> int:
    \\    print(out, pick("a,b", -3))
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-2
test "S2 offset list reads preserve failing negative index traps" {
    try checkRun(std.testing.allocator, bounds_source, "", "R_LIST_BOUNDS");
}

const search_source =
    \\import strings
    \\
    \\func probe(text: str, needle: str, out: Stream):
    \\    print(out, strings.char_find(text, needle), strings.count(text, needle), strings.starts_with(text, needle), strings.ends_with(text, needle), needle in text, strings.replace(text, needle, "Z"))
    \\func main(out: Stream) -> int:
    \\    probe("é😀é", "é", out)
    \\    probe("aaaaaa", "aa", out)
    \\    probe("aaaaaaaaaaaaaaaaaaaaaaaaab", "aaaab", out)
    \\    probe("abc", "z", out)
    \\    print(out, strings.char_find("é😀é", "é", 1, 3), strings.char_count_of("é😀é", "", 1, 3), strings.char_startswith("abc", "", 4))
    \\    return 0
;

// spec: NEW-CORE-S2-SEARCH-1
test "S2 bounded search paths preserve scalar windows and nonoverlapping matches" {
    try check(std.testing.allocator, search_source, "0 2 True True True Z😀Z\n0 3 True True True ZZZ\n21 1 False True True aaaaaaaaaaaaaaaaaaaaaZ\n-1 0 False False False abc\n2 3 False\n");
}

const substring_source =
    \\import byte_builder
    \\import bytes
    \\import hex
    \\import strings
    \\
    \\record Piece:
    \\    value: bytes
    \\func saved(data: bytes) -> Piece:
    \\    mut first = copy(data[1:max(len(data) - 1, 0)])
    \\    # A stored byte slice is a view, so the piece takes its copy (wave 3, D43).
    \\    return Piece(value=copy(first[1:4]))
    \\func make() -> Piece:
    \\    return saved(b"a" + b"bcdef")
    \\func main(out: Stream) -> int:
    \\    mut p = make()
    \\    mut alias = copy(p.value)
    \\    mut d: dict[bytes, int] = {}
    \\    d[copy(p.value)] = 7
    \\    print(out, p.value, len(p.value), p.value[0], p.value[len(p.value) - 1], p.value == b"cde", d[b"cde"])
    \\    print(out, hex.encode(p.value), byte_builder.repeat(p.value, 2), p.value + b"!", bytes.find(p.value, b"d"), p.value < b"zzz")
    \\    print(out, alias[1:], p.value[9:1], strings.decode(p.value))
    \\    return 0
;

// spec-case: NEW-CORE-S2-VIEW-1
test "S2 escaped byte slices preserve nested values and aliases" {
    try check(std.testing.allocator, substring_source, "b'cde' 3 99 101 True 7\n636465 b'cdecde' b'cde!' 1 True\nb'de' b'' Ok('cde')\n");
}

const prefix_source =
    \\import strings
    \\
    \\func inspect(text: str, out: Stream):
    \\    mut fields = strings.split(text, ",")
    \\    print(out, parse_int(fields[1]), strings.char_count(fields[2]), strings.ends_with(fields[0], "7"))
    \\func main(out: Stream) -> int:
    \\    inspect("item7,12,é😀,ignored,tail", out)
    \\    inspect("x,3,", out)
    \\    return 0
;

// spec: NEW-CORE-S2-SPLIT-4
// spec: NEGATIVE-SPLIT-PREFIX-1
test "S2 fixed nonnegative split indices use a stack offset prefix" {
    try expectIr(std.testing.allocator, prefix_source, "myl_core_span_split_prefix_3", "myl_core_span_split_offsets");
    try check(std.testing.allocator, prefix_source, "Some(12) 2 True\nSome(3) 0 False\n");
}

const prefix_bounds =
    \\import strings
    \\
    \\func pick(text: str, out: Stream) -> int:
    \\    mut fields = strings.split(text, ",")
    \\    print(out, "before")
    \\    return strings.char_count(fields[2])
    \\func main(out: Stream) -> int:
    \\    print(out, pick("a,b", out))
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-4
test "S2 stack split prefixes retain a short input's original located bound check" {
    try checkRun(std.testing.allocator, prefix_bounds, "before\n", "R_LIST_BOUNDS");
}

const substring_sort_source =
    \\import byte_builder
    \\func pieces() -> bytes[]:
    \\    mut parent = byte_builder.repeat(b"z", 20) + byte_builder.repeat(b"a", 20) + byte_builder.repeat(b"m", 20)
    \\    # A stored byte slice is a view, so each piece takes its copy (wave 3, D43).
    \\    return [copy(parent[0:20]), copy(parent[20:40]), copy(parent[40:60]), copy(parent[20:40])]
    \\func key(value: bytes) -> bytes:
    \\    return copy(value)
    \\func main(out: Stream) -> int:
    \\    mut values = pieces()
    \\    sort(mut values)
    \\    print(out, values[0] == byte_builder.repeat(b"a", 20), values[1] == byte_builder.repeat(b"a", 20), values[3] == byte_builder.repeat(b"z", 20))
    \\    sort(mut values, reverse=True)
    \\    print(out, values[0] == byte_builder.repeat(b"z", 20), values[3] == byte_builder.repeat(b"a", 20))
    \\    sort(mut values, key=key)
    \\    print(out, values[0] == byte_builder.repeat(b"a", 20), values[2] == byte_builder.repeat(b"m", 20), values[3] == byte_builder.repeat(b"z", 20))
    \\    sort(mut values, key=key, reverse=True)
    \\    print(out, values[0] == byte_builder.repeat(b"z", 20), values[3] == byte_builder.repeat(b"a", 20))
    \\    return 0
;

// spec-case: NEW-CORE-S2-VIEW-1
test "S2 escaped long byte slices sort by values with normal reverse and keyed order" {
    try check(std.testing.allocator, substring_sort_source, "True True True\nTrue True\nTrue True True\nTrue True\n");
}

const substring_numbers =
    \\import bytes
    \\
    \\func token(source: bytes) -> bytes:
    \\    return copy(source[1:max(len(source) - 1, 0)])
    \\func main(out: Stream) -> int:
    \\    mut a = token(b"<" + b"1.25>")
    \\    mut b = token(b"<" + b"-123>")
    \\    print(out, bytes.parse_float(a), bytes.parse_float_range(a, 0, 3), bytes.parse_int(b), bytes.parse_int_range(b, 1, 4))
    \\    return 0
;

// spec-case: NEW-CORE-S2-VIEW-1
test "S2 escaped byte slices parse numeric values and bounded numeric ranges" {
    try check(std.testing.allocator, substring_numbers, "Some(1.25) Some(1.2) Some(-123) Some(123)\n");
}

const split_declarations =
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut counts: dict[str, int] = {}
    \\    for word in strings.words("one two"):
    \\        counts[copy(word)] = 1
    \\    for word in strings.split("one,two", ","):
    \\        print(out, strings.char_count(word))
    \\    return 0
;

// spec-case: NEW-CORE-S2-SPLIT-1
test "S2 split declarations keep whitespace authorization beside explicit cursor lowering" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.projectModule(arena, split_declarations, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, "myl_core_str_split_whitespace")) function.signature.linkage = .extern_c;
    }
    _ = try support.runPasses(arena, &module, .trusted);
    const text = try @import("print.zig").module(arena, &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_split_ws_start") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_str_split_whitespace") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_split_start") != null);
}

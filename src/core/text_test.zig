//! Differential fixture gate for S2 UTF-8 text and byte operations.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;
const cache_argument = "--cache-dir";
const leak_check = "SELKA_CORE_LEAKCHECK";

fn qualified(arena: std.mem.Allocator) !bool {
    const source = try std.fmt.allocPrint(arena, "{s}/t_text.selka", .{options.fixtures});
    const cache = try options.suiteCache(arena, @src());
    var environment = try options.privateEnvironment(arena);
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.corePath(), "test", "--force", source, "--json", cache_argument, cache });
        try argv.appendSlice(arena, mode);
        const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1) {
            report("text fixture failed: {s}{s}\n", .{ result.stdout, result.stderr });
            return false;
        }
        const parsed = try std.json.parseFromSlice(std.json.Value, arena, result.stdout, .{});
        if (parsed.value.object.get("passed").?.integer != 8 or parsed.value.object.get("unsupported").?.integer != 0 or parsed.value.object.get("failed").?.integer != 2) {
            report("text fixture incomplete: {s}\n", .{result.stdout});
            return false;
        }
    }
    return true;
}

// spec: NEW-CORE-TEXT-BYTES-1
test "text and bytes preserve Unicode scalars, empty pieces, shared appends and byte XOR at every core mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try qualified(arena.allocator()));
}

// spec: PY-SET-OPS-1
const octet_reduction =
    \\import strings
    \\
    \\func score(text: str) -> int:
    \\    mut total = 0
    \\    for octet in strings.encode(text):
    \\        total += bit_xor(octet, 7)
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, score("01230123012301230123012301230123"))
    \\    return 0
    \\
;

// spec: NEW-CORE-TEXT-BYTES-2
test "bounded byte XOR reductions widen octets and preserve the scalar remainder" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const llvm = try @import("test_support.zig").releaseLlvmText(arena.allocator(), octet_reduction);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "xor <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "[ %vc") != null);
}

const fast_paths =
    \\import strings
    \\
    \\func repeated_piece(piece: str, count: int) -> str:
    \\    mut pieces: str[] = []
    \\    for _ in range(count):
    \\        append(mut pieces, copy(piece))
    \\    return strings.join(pieces, "")
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut long_a = repeated_piece("é", 200)
    \\    mut long_b = repeated_piece("é", 199) + "ê"
    \\    mut long_c = "ê" + repeated_piece("é", 199)
    \\    mut long_d = repeated_piece("é", 200)
    \\    mut middle_a = repeated_piece("ab", 60)
    \\    mut middle_b = repeated_piece("ab", 59) + "aB"
    \\    print(out, long_a == long_b, long_a == long_c, long_a == long_d, middle_a == middle_b, middle_a == repeated_piece("ab", 60))
    \\    print(out, "abcdefghij" == "abcdefghiJ", "abcdefghij" == "Abcdefghij", "abc" == "abc", "ab" == "aB", "é" == "é", "" == "")
    \\    mut hay = repeated_piece("a", 300) + ";café;needle;"
    \\    mut front = "né" + repeated_piece("a", 300)
    \\    print(out, strings.char_find(hay, "needle"), strings.char_find(hay, "é"), strings.char_find(hay, ";c"), strings.char_find(hay, "absent"), strings.char_find(hay, "aa"), strings.char_find(front, "é"), strings.char_find(front, "aaa"), strings.char_find(hay, "a;"))
    \\    return 0
    \\
;

/// Build `fast_paths` with the new core in `mode` and run it; its standard output.
fn fastPathsOutput(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/fast.selka", .{root});
    const output = try std.fmt.allocPrint(arena, "{s}/fast-{d}", .{ root, mode.len });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, cache_argument, cache });
    try argv.appendSlice(arena, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("text build failed: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put(leak_check, "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    return ran.stdout;
}

// spec: NEW-CORE-TEXT-2
test "equality checks the ends of long equal-length texts first and find counts scalars from the nearer end, as the old core answers" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fast.selka", .data = fast_paths });
    // The old core's output for the same program.
    const expected = "False False True False True\nFalse False True False True True\n306 304 300 -1 0 1 2 299\n";
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{}));
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{"--release"}));
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{ "--release", "--verify-facts" }));
}

fn methodsRun(allocator: std.mem.Allocator, mode: []const []const u8) !void {
    var environment = try options.privateEnvironment(allocator);
    try environment.put(leak_check, "1");
    const source = try std.fs.path.join(allocator, &.{ options.fixtures, "t_methods.selka" });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ options.corePath(), "test", "--force", source, "--json", cache_argument, try options.suiteCache(allocator, @src()) });
    try argv.appendSlice(allocator, mode);
    try support.requireReleaseArgs(mode);
    const result = try std.process.run(allocator, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("", result.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    try std.testing.expectEqual(@as(i64, 7), parsed.value.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("failed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_SUBSTRING_NOT_FOUND") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_TEXT_SCALAR") != null);
}

// spec: NEW-CORE-TEXT-S3-1
test "remaining text methods preserve exact scalar and octet semantics with checked failures in every mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try methodsRun(arena.allocator(), &.{});
    try methodsRun(arena.allocator(), &.{"--release"});
    try methodsRun(arena.allocator(), &.{ "--release", "--verify-facts" });
}

const extended_list =
    \\import lists
    \\
    \\func main() -> int:
    \\    mut xs = ["a", "é"]
    \\    mut saved = copy(xs)
    \\    lists.extend(mut xs, copy(xs))
    \\    lists.reverse(mut xs)
    \\    return len(saved) + len(xs)
    \\
;

// spec: NEW-CORE-LIST-S3-1
test "self extension and reverse build list updates whose ownership preserves the captured source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try @import("test_support.zig").irText(arena.allocator(), extended_list);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_push") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "phi list[str]") != null);
}

const split_keys =
    \\import dicts
    \\import strings
    \\
    \\func counts(text: str) -> dict[str, int]:
    \\    mut result: dict[str, int] = {}
    \\    for word in strings.words(text):
    \\        if word in result:
    \\            result[copy(word)] = result[word] + 1
    \\        else:
    \\            result[copy(word)] = 1
    \\    return result
    \\
    \\func rebound(source: str) -> dict[str, int]:
    \\    mut text = copy(source)
    \\    mut result: dict[str, int] = {}
    \\    for word in strings.words(text):
    \\        text = "changed"
    \\        result[copy(word)] = 1
    \\        if len(result) == 2:
    \\            continue
    \\        if len(result) == 3:
    \\            break
    \\    return result
    \\
    \\func main(out: Stream) -> int:
    \\    mut empty = counts(" \t\n\r\x0b\x0c")
    \\    mut unicode = counts("é\t😀\né\rnaïve\x0bcafé\x0cx\u00a0y")
    \\    mut many = counts(strings.join(["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "alpha", "abcdefghijklmnopabcdefghijklmnop", "abcdefghijklmnopabcdefghijklmnop"], " "))
    \\    mut saved = copy(many)
    \\    many["alpha"] = 9
    \\    mut snapshot = rebound(strings.join(["a", "b", "c", "d"], " "))
    \\    mut deleted = counts("a b c")
    \\    _ = dicts.pop(mut deleted, "b")
    \\    for word in strings.words("a b d"):
    \\        deleted[copy(word)] = 2
    \\    mut collided = counts("collision002553 collision005a0e collision002553")
    \\    mut sources = [strings.join(["a", "b", "c"], " ")]
    \\    mut from_list: dict[str, int] = {}
    \\    for word in strings.words(sources[0]):
    \\        sources[0] = "changed"
    \\        from_list[copy(word)] = 1
    \\    mut source_dict: dict[str, str] = {"input": strings.join(["a", "b", "c"], " ")}
    \\    mut from_dict: dict[str, int] = {}
    \\    for word in strings.words(source_dict["input"]):
    \\        source_dict["input"] = "changed"
    \\        from_dict[copy(word)] = 1
    \\    print(out, len(empty), len(unicode), unicode["é"], unicode["x\u00a0y"], unicode["😀"])
    \\    print(out, len(saved), saved["alpha"], many["alpha"], saved["abcdefghijklmnopabcdefghijklmnop"])
    \\    print(out, len(snapshot), snapshot["a"], snapshot["b"], snapshot["c"])
    \\    print(out, len(deleted), deleted["a"], deleted["b"], deleted["c"], deleted["d"])
    \\    print(out, len(collided), collided["collision002553"], collided["collision005a0e"])
    \\    print(out, len(from_list), from_list["a"], from_list["b"], from_list["c"])
    \\    print(out, len(from_dict), from_dict["a"], from_dict["b"], from_dict["c"])
    \\    return 0
    \\
;

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private split dictionary keys preserve whitespace, UTF8, source snapshots, insertion ownership and captured dictionaries" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fast.selka", .data = split_keys });
    const expected = "0 5 2 1 1\n13 2 9 2\n3 1 1 1\n4 2 2 1 2\n2 2 1\n3 1 1 1\n3 1 1 1\n";
    const text = try @import("test_support.zig").optimizedText(arena, split_keys);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_view_of") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_from_view") != null);
    const llvm = try @import("test_support.zig").releaseLlvmText(arena, split_keys);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_split_ws_start") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_split_ws_end") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%splitnonnegative") != null);
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, mode));
    }
}

const escaped_split =
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut words = strings.words("one two")
    \\    mut keys: dict[str, int] = {}
    \\    for word in words:
    \\        keys[copy(word)] = 1
    \\    print(out, len(words), words[0])
    \\    return 0
    \\
;

const escaped_word =
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    mut words: str[] = []
    \\    for word in strings.words("one two"):
    \\        keys[copy(word)] = 1
    \\        append(mut words, copy(word))
    \\    print(out, words)
    \\    return 0
    \\
;

const indexed_word =
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    for index, word in enumerate(strings.words("one two")):
    \\        keys[copy(word)] = index
    \\    print(out, keys["two"])
    \\    return 0
    \\
;

const called_word =
    \\import strings
    \\
    \\func inspect(word: str) -> int:
    \\    return strings.char_count(word)
    \\
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    for word in strings.words("one two"):
    \\        keys[copy(word)] = inspect(word)
    \\    print(out, keys["two"])
    \\    return 0
    \\
;

const phi_word =
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    mut saved = ""
    \\    for word in strings.words("one two"):
    \\        keys[copy(word)] = 1
    \\        saved = copy(word)
    \\    print(out, saved)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private split fusion refuses observable lists, indices, ordinary calls and escaping words or phis" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ escaped_split, escaped_word, indexed_word, called_word, phi_word }) |source| {
        const text = try @import("test_support.zig").optimizedText(arena.allocator(), source);
        try std.testing.expect(std.mem.indexOf(u8, text, "call list[str] myl_core_str_split_whitespace") != null);
        try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_split_ws_start") == null);
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private split fusion requires the authorized runtime declaration even with an identical extern name and signature" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try @import("test_support.zig").buildSource(arena, split_keys, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, "myl_core_str_split_whitespace")) function.signature.linkage = .extern_c;
    }
    _ = try @import("test_support.zig").runPasses(arena, &module, .trusted);
    const text = try @import("print.zig").module(arena, &module);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_split_ws_start") == null);
}

const moving_scans =
    \\import strings
    \\func appended(n: int) -> str:
    \\    mut out = ""
    \\    for i in range(n):
    \\        out += strings.char_at("é€", i % 2)
    \\    return out
    \\
    \\func scan(s: str) -> int:
    \\    mut n = strings.char_count(s)
    \\    mut total = 0
    \\    mut start = 0
    \\    while strings.char_find(s, "é", start) >= 0:
    \\        start = strings.char_index(s, "é", start) + 1
    \\        total += start
    \\    mut end = n
    \\    while strings.char_rfind(s, "é", 0, end) >= 0:
    \\        end = strings.char_rfind(s, "é", 0, end)
    \\        total += end
    \\    mut i = n - 1
    \\    while i >= 0:
    \\        total += ord(strings.char_at(s, i)) + strings.char_count(strings.char_slice(s, i, i + 2))
    \\        i -= 1
    \\    total += ord(strings.char_at(strings.char_stride(s, None, None, -1), 0)) + strings.char_count(strings.char_stride(s, None, None, -3))
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, scan(strings.repeat("é", 20000)), scan(appended(20000)))
    \\    return 0
    \\
;

/// Build `moving_scans` in `mode`, run it with the walk report on, and return the
/// octets its scalar lookups walked after checking its output against the old core's.
fn movingScanWalk(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) !u64 {
    const output = try std.fmt.allocPrint(arena, "{s}/scan-{d}", .{ root, mode.len });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", try std.fmt.allocPrint(arena, "{s}/scan.selka", .{root}), "-o", output, cache_argument, try options.suiteCache(arena, @src()) });
    try argv.appendSlice(arena, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("scan build failed: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_TEXTWALK", "1");
    try environment.put(leak_check, "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    // The old core's output for the same program.
    try std.testing.expectEqualStrings("404706899 286015030\n", ran.stdout);
    const prefix = "myl-core textwalk: ";
    try std.testing.expect(std.mem.startsWith(u8, ran.stderr, prefix));
    return std.fmt.parseInt(u64, std.mem.trimEnd(u8, ran.stderr[prefix.len..], " octets\n"), 10);
}

// spec: NEW-CORE-TEXT-CURSOR-1
test "scalar lookups that move through non-ASCII text either way walk only the distance moved" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "scan.selka", .data = moving_scans });
    // The two texts hold 90,000 octets; the scans walk about 1.6 million in all. A
    // lookup that walked from the start of the text would walk hundreds of millions.
    try std.testing.expect(try movingScanWalk(arena, root, &.{}) < 4_000_000);
    try std.testing.expect(try movingScanWalk(arena, root, &.{"--unoptimized"}) < 4_000_000);
    try std.testing.expect(try movingScanWalk(arena, root, &.{"--release"}) < 4_000_000);
}

// spec-case: NEW-CORE-TEXT-CURSOR-1
test "A04 repeated text retains cursor capacity and byte terminator storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = @embedFile("a04_repeat_cursor_fixture.c");
    var fixture = try @import("native_fixture.zig").Fixture.init(a, root, source, .{});
    defer fixture.environment.deinit();
    const ran = try fixture.run("boundaries", "1");
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// Each walk shape scans 20,000 `é` (40,002 octets) by its char count and `char_at` in turn: a linear walk
// moves a few times the text's octets, and a walk from the start of the text moves about 400 million.
const walk_owned_source =
    \\import strings
    \\func walk(s: str) -> int:
    \\    mut total = 0
    \\    for i in range(strings.char_count(s)):
    \\        total += ord(strings.char_at(s, i))
    \\    return total
    \\func main(out: Stream) -> int:
    \\    print(out, walk(strings.repeat("é", 20000)))
    \\    return 0
;

const walk_slice_source =
    \\import strings
    \\func walk(s: str) -> int:
    \\    mut total = 0
    \\    for i in range(strings.char_count(s)):
    \\        total += ord(strings.char_at(s, i))
    \\    return total
    \\func main(out: Stream) -> int:
    \\    const big = strings.repeat("é", 20001)
    \\    print(out, walk(big[2:40002]))
    \\    return 0
;

const walk_forwarded_source =
    \\import strings
    \\func walk(s: str) -> int:
    \\    mut total = 0
    \\    for i in range(strings.char_count(s)):
    \\        total += ord(strings.char_at(s, i))
    \\    return total
    \\func hop(s: str) -> int:
    \\    return walk(s)
    \\func main(out: Stream) -> int:
    \\    print(out, hop(strings.repeat("é", 20000)))
    \\    return 0
;

/// The octets one native run of `source` walks: its stdout must be `4660000` (20,000 `é`), and its walk
/// counter is read from the textwalk report on stderr.
fn walkOctets(arena: std.mem.Allocator, root: []const u8, source_name: []const u8, mode: []const []const u8) !u64 {
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}", .{ root, source_name, mode.len });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ root, source_name }), "-o", output, cache_argument, try options.suiteCache(arena, @src()) });
    try argv.appendSlice(arena, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("walk build failed: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_TEXTWALK", "1");
    try environment.put(leak_check, "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("4660000\n", ran.stdout);
    const prefix = "myl-core textwalk: ";
    try std.testing.expect(std.mem.startsWith(u8, ran.stderr, prefix));
    return std.fmt.parseInt(u64, std.mem.trimEnd(u8, ran.stderr[prefix.len..], " octets\n"), 10);
}

// spec: NEW-CORE-C9-WALK-1
test "a char_count and char_at walk over an owned argument stays within the walk bound" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "walk_owned.selka", .data = walk_owned_source });
    try std.testing.expect(try walkOctets(arena, root, "walk_owned", &.{}) < 4_000_000);
    try std.testing.expect(try walkOctets(arena, root, "walk_owned", &.{"--release"}) < 4_000_000);
}

// spec: NEW-CORE-C9-WALK-2
test "a char_count and char_at walk over a slice argument stays within the walk bound" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "walk_slice.selka", .data = walk_slice_source });
    try std.testing.expect(try walkOctets(arena, root, "walk_slice", &.{}) < 4_000_000);
    try std.testing.expect(try walkOctets(arena, root, "walk_slice", &.{"--release"}) < 4_000_000);
}

// spec: NEW-CORE-C9-WALK-3
test "a char_count and char_at walk over a parameter forwarded through one hop stays within the walk bound" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "walk_forwarded.selka", .data = walk_forwarded_source });
    try std.testing.expect(try walkOctets(arena, root, "walk_forwarded", &.{}) < 4_000_000);
    try std.testing.expect(try walkOctets(arena, root, "walk_forwarded", &.{"--release"}) < 4_000_000);
}

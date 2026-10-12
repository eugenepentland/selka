//! Differential fixture gate for S2 UTF-8 text and byte operations.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;
const cache_argument = "--cache-dir";
const cache_pattern = "{s}/cache";
const leak_check = "MYL_CORE_LEAKCHECK";

fn qualified(arena: std.mem.Allocator) !bool {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source = try std.fmt.allocPrint(arena, "{s}/t_text.my", .{options.fixtures});
    const cache = try std.fmt.allocPrint(arena, cache_pattern, .{root});
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.corePath(), "test", source, "--json", cache_argument, cache });
        try argv.appendSlice(arena, mode);
        const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
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

const octet_reduction =
    \\func score(text: str) -> int:
    \\    mut total = 0
    \\    for octet in text.encode():
    \\        total += octet ^ 7
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(score("01230123012301230123012301230123"))
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
    \\func main(out: Stream) -> int:
    \\    mut long_a = "".join([for j in range(200) yield "é"])
    \\    mut long_b = "".join([for j in range(199) yield "é"]) + "ê"
    \\    mut long_c = "ê" + "".join([for j in range(199) yield "é"])
    \\    mut long_d = "".join([for j in range(200) yield "é"])
    \\    mut middle_a = "".join([for j in range(60) yield "ab"])
    \\    mut middle_b = "".join([for j in range(59) yield "ab"]) + "aB"
    \\    out.print(long_a == long_b, long_a == long_c, long_a == long_d, middle_a == middle_b, middle_a == "".join([for j in range(60) yield "ab"]))
    \\    out.print("abcdefghij" == "abcdefghiJ", "abcdefghij" == "Abcdefghij", "abc" == "abc", "ab" == "aB", "é" == "é", "" == "")
    \\    mut hay = "".join([for j in range(300) yield "a"]) + ";café;needle;"
    \\    mut front = "né" + "".join([for j in range(300) yield "a"])
    \\    out.print(hay.find("needle"), hay.find("é"), hay.find(";c"), hay.find("absent"), hay.find("aa"), front.find("é"), front.find("aaa"), hay.find("a;"))
    \\    return 0
    \\
;

/// Build `fast_paths` with the new core in `mode` and run it; its standard output.
fn fastPathsOutput(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/fast.my", .{root});
    const output = try std.fmt.allocPrint(arena, "{s}/fast-{d}", .{ root, mode.len });
    const cache = try std.fmt.allocPrint(arena, cache_pattern, .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, cache_argument, cache });
    try argv.appendSlice(arena, mode);
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
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fast.my", .data = fast_paths });
    // The old core's output for the same program.
    const expected = "False False True False True\nFalse False True False True True\n306 304 300 -1 0 1 2 299\n";
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{}));
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{"--release"}));
    try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, &.{ "--release", "--verify-facts" }));
}

fn methodsRun(allocator: std.mem.Allocator, mode: []const []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    var environment = try std.testing.environ.createMap(allocator);
    try environment.put(leak_check, "1");
    const source = try std.fs.path.join(allocator, &.{ options.fixtures, "t_methods.my" });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ options.corePath(), "test", source, "--json", cache_argument, root });
    try argv.appendSlice(allocator, mode);
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
    \\func main() -> int:
    \\    mut xs = ["a", "é"]
    \\    mut saved = xs
    \\    xs.extend(xs)
    \\    xs.reverse()
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
    \\func counts(text: str) -> dict[str, int]:
    \\    mut result: dict[str, int] = {}
    \\    for word in text.split():
    \\        result[word] = if (word in result) then (result[word] + 1) else (1)
    \\    return result
    \\
    \\func rebound(source: str) -> dict[str, int]:
    \\    mut text = source
    \\    mut result: dict[str, int] = {}
    \\    for word in text.split():
    \\        text = "changed"
    \\        result[word] = 1
    \\        if len(result) == 2:
    \\            continue
    \\        if len(result) == 3:
    \\            break
    \\    return result
    \\
    \\func main(out: Stream) -> int:
    \\    mut empty = counts(" \t\n\r\x0b\x0c")
    \\    mut unicode = counts("é\t😀\né\rnaïve\x0bcafé\x0cx\u00a0y")
    \\    mut many = counts(" ".join(["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "alpha", "abcdefghijklmnopabcdefghijklmnop", "abcdefghijklmnopabcdefghijklmnop"]))
    \\    mut saved = many
    \\    many["alpha"] = 9
    \\    mut snapshot = rebound(" ".join(["a", "b", "c", "d"]))
    \\    mut deleted = counts("a b c")
    \\    _ = deleted.pop("b")
    \\    for word in "a b d".split():
    \\        deleted[word] = 2
    \\    mut collided = counts("collision002553 collision005a0e collision002553")
    \\    mut sources = [" ".join(["a", "b", "c"])]
    \\    mut from_list: dict[str, int] = {}
    \\    for word in sources[0].split():
    \\        sources[0] = "changed"
    \\        from_list[word] = 1
    \\    mut source_dict: dict[str, str] = {"input": " ".join(["a", "b", "c"])}
    \\    mut from_dict: dict[str, int] = {}
    \\    for word in source_dict["input"].split():
    \\        source_dict["input"] = "changed"
    \\        from_dict[word] = 1
    \\    out.print(len(empty), len(unicode), unicode["é"], unicode["x\u00a0y"], unicode["😀"])
    \\    out.print(len(saved), saved["alpha"], many["alpha"], saved["abcdefghijklmnopabcdefghijklmnop"])
    \\    out.print(len(snapshot), snapshot["a"], snapshot["b"], snapshot["c"])
    \\    out.print(len(deleted), deleted["a"], deleted["b"], deleted["c"], deleted["d"])
    \\    out.print(len(collided), collided["collision002553"], collided["collision005a0e"])
    \\    out.print(len(from_list), from_list["a"], from_list["b"], from_list["c"])
    \\    out.print(len(from_dict), from_dict["a"], from_dict["b"], from_dict["c"])
    \\    return 0
    \\
;

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private split dictionary keys preserve whitespace, UTF8, source snapshots, insertion ownership and captured dictionaries" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "fast.my", .data = split_keys });
    const expected = "0 5 2 1 1\n13 2 9 2\n3 1 1 1\n4 2 2 1 2\n2 2 1\n3 1 1 1\n3 1 1 1\n";
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try std.testing.expectEqualStrings(expected, try fastPathsOutput(arena, root, mode));
    }
    const text = try @import("test_support.zig").optimizedText(arena, split_keys);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_view_of") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_from_view") != null);
    const llvm = try @import("test_support.zig").releaseLlvmText(arena, split_keys);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_split_ws_start") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_split_ws_end") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%splitnonnegative") != null);
}

const escaped_split =
    \\func main(out: Stream) -> int:
    \\    mut words = "one two".split()
    \\    mut keys: dict[str, int] = {}
    \\    for word in words:
    \\        keys[word] = 1
    \\    out.print(len(words), words[0])
    \\    return 0
    \\
;

const escaped_word =
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    mut words: str[] = []
    \\    for word in "one two".split():
    \\        keys[word] = 1
    \\        words.append(word)
    \\    out.print(words)
    \\    return 0
    \\
;

const indexed_word =
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    for index, word in enumerate("one two".split()):
    \\        keys[word] = index
    \\    out.print(keys["two"])
    \\    return 0
    \\
;

const called_word =
    \\func inspect(word: str) -> int:
    \\    return len(word)
    \\
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    for word in "one two".split():
    \\        keys[word] = inspect(word)
    \\    out.print(keys["two"])
    \\    return 0
    \\
;

const phi_word =
    \\func main(out: Stream) -> int:
    \\    mut keys: dict[str, int] = {}
    \\    mut saved = ""
    \\    for word in "one two".split():
    \\        keys[word] = 1
    \\        saved = word
    \\    out.print(saved)
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
    \\func appended(n: int) -> str:
    \\    mut out = ""
    \\    for i in range(n):
    \\        out += "é€"[i % 2]
    \\    return out
    \\
    \\func scan(s: str) -> int:
    \\    mut n = len(s)
    \\    mut total = 0
    \\    mut start = 0
    \\    while s.find("é", start) >= 0:
    \\        start = s.index("é", start) + 1
    \\        total += start
    \\    mut end = n
    \\    while s.rfind("é", 0, end) >= 0:
    \\        end = s.rfind("é", 0, end)
    \\        total += end
    \\    mut i = n - 1
    \\    while i >= 0:
    \\        total += ord(s[i]) + len(s[i:i + 2])
    \\        i -= 1
    \\    total += ord(s[::-1][0]) + len(s[::-3])
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(scan("é" * 20000), scan(appended(20000)))
    \\    return 0
    \\
;

/// Build `moving_scans` in `mode`, run it with the walk report on, and return the
/// octets its scalar lookups walked after checking its output against the old core's.
fn movingScanWalk(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) !u64 {
    const output = try std.fmt.allocPrint(arena, "{s}/scan-{d}", .{ root, mode.len });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", try std.fmt.allocPrint(arena, "{s}/scan.my", .{root}), "-o", output, cache_argument, try std.fmt.allocPrint(arena, cache_pattern, .{root}) });
    try argv.appendSlice(arena, mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("scan build failed: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_TEXTWALK", "1");
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
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "scan.my", .data = moving_scans });
    // The two texts hold 90,000 octets; the scans walk about 1.6 million in all. A
    // lookup that walked from the start of the text would walk hundreds of millions.
    try std.testing.expect(try movingScanWalk(arena, root, &.{}) < 4_000_000);
    try std.testing.expect(try movingScanWalk(arena, root, &.{"--release"}) < 4_000_000);
}

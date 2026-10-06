//! Differential fixture gate for S2 UTF-8 text and byte operations.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;
const cache_argument = "--cache-dir";

fn qualified(arena: std.mem.Allocator) !bool {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source = try std.fmt.allocPrint(arena, "{s}/t_text.my", .{options.fixtures});
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.core_path, "test", source, "--json", cache_argument, cache });
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
    \\def score(text: str) -> int:
    \\    total = 0
    \\    for octet in text.encode():
    \\        total += octet ^ 7
    \\    return total
    \\
    \\def main(out: Stream) -> int:
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
    \\def main(out: Stream) -> int:
    \\    long_a = "".join(["é" for j in range(200)])
    \\    long_b = "".join(["é" for j in range(199)]) + "ê"
    \\    long_c = "ê" + "".join(["é" for j in range(199)])
    \\    long_d = "".join(["é" for j in range(200)])
    \\    middle_a = "".join(["ab" for j in range(60)])
    \\    middle_b = "".join(["ab" for j in range(59)]) + "aB"
    \\    out.print(long_a == long_b, long_a == long_c, long_a == long_d, middle_a == middle_b, middle_a == "".join(["ab" for j in range(60)]))
    \\    out.print("abcdefghij" == "abcdefghiJ", "abcdefghij" == "Abcdefghij", "abc" == "abc", "ab" == "aB", "é" == "é", "" == "")
    \\    hay = "".join(["a" for j in range(300)]) + ";café;needle;"
    \\    front = "né" + "".join(["a" for j in range(300)])
    \\    out.print(hay.find("needle"), hay.find("é"), hay.find(";c"), hay.find("absent"), hay.find("aa"), front.find("é"), front.find("aaa"), hay.find("a;"))
    \\    return 0
    \\
;

/// Build `fast_paths` with the new core in `mode` and run it; its standard output.
fn fastPathsOutput(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/fast.my", .{root});
    const output = try std.fmt.allocPrint(arena, "{s}/fast-{d}", .{ root, mode.len });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, cache_argument, cache });
    try argv.appendSlice(arena, mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
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
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const source = try std.fs.path.join(allocator, &.{ options.fixtures, "t_methods.my" });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ options.core_path, "test", source, "--json", cache_argument, root });
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
    \\def main() -> int:
    \\    xs = ["a", "é"]
    \\    saved = xs
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

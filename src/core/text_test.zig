//! Differential fixture gate for S2 UTF-8 text and byte operations.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(arena: std.mem.Allocator) !bool {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source = try std.fmt.allocPrint(arena, "{s}/t_text.my", .{options.fixtures});
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.core_path, "test", source, "--json", "--cache-dir", cache });
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
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load <16 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "xor <16 x i16>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "[ %vc") != null);
}

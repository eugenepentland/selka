//! Dictionary SSA lowering and differential fixture qualification.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const source =
    \\def main() -> int:
    \\    d: dict[int, int] = {1: 7}
    \\    key = 2
    \\    d[key] = d.get(key, 0) + 9
    \\    return d[key]
;

const exposed_view =
    \\record Holder:
    \\    mapping: dict[int, int]
    \\def main() -> int:
    \\    d = {1: 7}
    \\    holder = Holder(d)
    \\    view = d.values()
    \\    d[1] = 9
    \\    return list(view)[0] + holder.mapping[1]
;

fn fixturesAgree(arena: std.mem.Allocator) !bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source_path = try std.fmt.allocPrint(arena, "{s}/d_collections.my", .{options.fixtures});
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.core_path, "test", source_path, "--json", "--cache-dir", root });
        try argv.appendSlice(arena, mode);
        var environment = try std.testing.environ.createMap(arena);
        defer environment.deinit();
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1) {
            report("dict fixture unexpected exit: {s}{s}\n", .{ result.stdout, result.stderr });
            return false;
        }
        const json = try std.json.parseFromSlice(std.json.Value, arena, result.stdout, .{});
        if (json.value.object.get("unsupported").?.integer != 0 or std.mem.indexOf(u8, result.stdout, "leak:") != null or std.mem.indexOf(u8, result.stderr, "leakcheck") != null) return false;
        const tests = json.value.object.get("tests").?.array.items;
        for (tests) |test_result| {
            const name = test_result.object.get("name").?.string;
            const verdict = test_result.object.get("status").?.string;
            if (std.mem.endsWith(u8, name, "test_missing_key_trap")) {
                if (!std.mem.eql(u8, verdict, "failed")) return false;
            } else if (!std.mem.eql(u8, verdict, "passed")) return false;
        }
    }
    return true;
}

// spec: NEW-CORE-DICT-1
test "dictionary lowering uses pure find and consuming insertion or value replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, "dict_find") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dict_insert") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dict_set_value") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, text, "dict_find i64"));
}

// spec-case: NEW-CORE-DICT-1
test "dictionary and set fixtures preserve COW, order, tombstones, nested managed places and missing-key traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try fixturesAgree(arena.allocator()));
}

// spec-case: NEW-CORE-DICT-1
test "persistent view identity refuses an ordinary aggregate alias of its mapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), exposed_view, &refusal));
    try std.testing.expectEqualStrings("aggregate or captured dictionary alias combined with a live view", refusal.reason);
}

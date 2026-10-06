//! Dictionary SSA lowering and differential fixture qualification.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
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

// Source-level dict.copy is a value alias; exercise the actual IR copy transfer.
fn unknownCopyLength(arena: std.mem.Allocator) !facts.Interval {
    var module: ir.Module = .{};
    const dictionary = try module.intern(arena, .{ .dict = .{ .key = .i64, .value = .i64 } });
    var hand = try support.Hand.init(arena, &module, "copy_loop", .{ .params = &.{ dictionary, .bool }, .ret = .u64 });
    const input = try hand.param(0);
    const condition = try hand.param(1);
    const empty = try hand.emit(.{ .op = .dict_new, .ty = dictionary, .a = try hand.int(.u64, 0) });
    const header = try hand.newBlock();
    const body = try hand.newBlock();
    const exit = try hand.newBlock();
    try hand.jump(header);
    hand.block = header;
    const incoming = try hand.extra(&.{ empty, .none });
    const joined = try hand.emit(.{ .op = .phi, .ty = dictionary, .data = incoming });
    try hand.branch(condition, body, exit);
    hand.block = body;
    const copied = try hand.emit(.{ .op = .dict_copy, .ty = dictionary, .a = input });
    try hand.jump(header);
    hand.function.extra.items[ir.ExtraSlice.unpack(incoming).start + 1] = copied;
    hand.block = exit;
    const length = try hand.emit(.{ .op = .dict_len, .ty = .u64, .a = joined });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = length });
    _ = try hand.finish();
    try support.verified(arena, &module, &.{});
    const known = try facts.analyze(arena, &module.functions.items[0], .{});
    return known.ranges[length.index()].?;
}

fn fixturesAgree(arena: std.mem.Allocator, fixture: []const u8, expected_exit: u8) !bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ options.fixtures, fixture });
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.core_path, "test", source_path, "--json", "--cache-dir", root });
        try argv.appendSlice(arena, mode);
        var environment = try std.testing.environ.createMap(arena);
        defer environment.deinit();
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != expected_exit) {
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
    try std.testing.expect(try fixturesAgree(arena.allocator(), "d_collections.my", 1));
}

// spec-case: NEW-CORE-DICT-1
test "unknown dictionary inputs settle through copy and updates before loop joins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try fixturesAgree(arena.allocator(), "d_fact_inputs.my", 0));
}

// spec-case: NEW-CORE-DICT-1
test "a dictionary copy of an unknown parameter weakens an empty loop entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(facts.Interval{ .lo = 0, .hi = facts.max_list_length }, try unknownCopyLength(arena.allocator()));
}

// spec-case: NEW-CORE-DICT-1
test "persistent view identity refuses an ordinary aggregate alias of its mapping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), exposed_view, &refusal));
    try std.testing.expectEqualStrings("aggregate or captured dictionary alias combined with a live view", refusal.reason);
}

// spec-case: NEW-CORE-DICT-1
test "fixed arrays refuse stored live dictionary views precisely" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const stored_view = "def main() -> int:\n    d = {1: 7}\n    views: [1]DictValues[int, int] = [d.values()]\n    d[1] = 9\n    return list(views[0])[0]\n";
    try std.testing.expectError(error.Unsupported, support.buildSource(arena.allocator(), stored_view, &refusal));
    try std.testing.expectEqualStrings("fixed array storage of live dictionary views", refusal.reason);
}

const small_tables =
    \\def main(out: Stream) -> int:
    \\    counts: dict[str, int] = {}
    \\    for word in "the cat and the hat and the bat".split(" "):
    \\        if word in counts:
    \\            counts[word] = counts[word] + 1
    \\        else:
    \\            counts[word] = 1
    \\    numbers: dict[int, int] = {}
    \\    for j in range(6):
    \\        numbers[j * 7] = j
    \\    _ = numbers.pop(14)
    \\    numbers[100] = 9
    \\    out.print(counts["the"], counts["and"], counts.get("dog", -1), len(counts))
    \\    out.print(numbers.get(14, -1), numbers.get(21, -1), numbers.get(100, -1), numbers.get(5, -1), len(numbers))
    \\    return 0
    \\
;

/// Build `small_tables` with the new core in `mode` and run it; its standard output.
fn smallTablesOutput(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) ![]const u8 {
    const program = try std.fmt.allocPrint(arena, "{s}/small.my", .{root});
    const output = try std.fmt.allocPrint(arena, "{s}/small-{d}", .{ root, mode.len });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", program, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, mode);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    return ran.stdout;
}

// spec: NEW-CORE-DICT-SMALL-1
test "a probe scans an index-less table's cached hashes inline, and a table that lost an entry asks the runtime, as the old core answers" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const llvm = try support.releaseLlvmText(arena, small_tables);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%sh_hit = icmp eq i64 %sh, %hash") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "br i1 %clean, label %scan, label %slow") != null);
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "small.my", .data = small_tables });
    // The old core's output for the same program.
    const expected = "3 2 -1 5\n-1 3 9 -1 6\n";
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{}));
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{"--release"}));
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{ "--release", "--verify-facts" }));
}

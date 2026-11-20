//! Dictionary SSA lowering and differential fixture qualification.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const source =
    \\import dicts
    \\
    \\func main() -> int:
    \\    mut d: dict[int, int] = {1: 7}
    \\    mut key = 2
    \\    d[key] = dicts.get(d, key, 0) + 9
    \\    return d[key]
;

// migrate-embedded: skip intentional stored dictionary view negative
const exposed_view =
    \\record Holder:
    \\    mapping: dict[int, int]
    \\func main() -> int:
    \\    mut d = {1: 7}
    \\    mut holder = Holder(mapping=d)
    \\    mut view = d.values()
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
    const source_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ options.fixtures, fixture });
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.corePath(), "test", "--force", source_path, "--json", "--cache-dir", try options.suiteCache(arena, @src()) });
        try argv.appendSlice(arena, mode);
        var environment = try options.privateEnvironment(arena);
        defer environment.deinit();
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
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
    try std.testing.expect(try fixturesAgree(arena.allocator(), "d_collections.selka", 1));
}

// spec-case: NEW-CORE-DICT-1
test "unknown dictionary inputs settle through copy and updates before loop joins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try fixturesAgree(arena.allocator(), "d_fact_inputs.selka", 0));
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
    try std.testing.expectError(error.SourceError, support.buildSource(arena.allocator(), exposed_view, &refusal));
}

// spec-case: NEW-CORE-DICT-1
test "materialized dictionary values remain independent of copied aggregate mappings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owned = try std.mem.replaceOwned(u8, a, exposed_view, "Holder(mapping=d)", "Holder(mapping=copy(d))");
    const snapshot = try std.mem.replaceOwned(u8, a, owned, "mut view = d.values()", "mut view = list(dicts.values(d))");
    for ([_]bool{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = try support.buildSource(a, try std.fmt.allocPrint(a, "import dicts\n\n{s}", .{snapshot}), &refusal);
        const ran = try support.runOwned(a, &module, .{ .release = optimized, .verify = optimized });
        try std.testing.expectEqual(@as(u8, 14), ran.status);
        try std.testing.expectEqualStrings("", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

// spec-case: NEW-CORE-DICT-1
test "fixed arrays refuse stored live dictionary views precisely" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const stored_view = "func main() -> int:\n    mut d = {1: 7}\n    mut views: FixedArray[DictValues[int, int], 1] = [d.values()]\n    d[1] = 9\n    return list(views[0])[0]\n";
    try std.testing.expectError(error.SourceError, support.buildSource(arena.allocator(), stored_view, &refusal));
}

const small_tables =
    \\import dicts
    \\import strings
    \\
    \\func main(out: Stream) -> int:
    \\    mut counts: dict[str, int] = {}
    \\    for word in strings.split("the cat and the hat and the bat", " "):
    \\        if word in counts:
    \\            counts[copy(word)] = counts[word] + 1
    \\        else:
    \\            counts[copy(word)] = 1
    \\    mut numbers: dict[int, int] = {}
    \\    for j in range(6):
    \\        numbers[j * 7] = j
    \\    _ = dicts.pop(mut numbers, 14)
    \\    numbers[100] = 9
    \\    print(out, counts["the"], counts["and"], dicts.get(counts, "dog", -1), len(counts))
    \\    print(out, dicts.get(numbers, 14, -1), dicts.get(numbers, 21, -1), dicts.get(numbers, 100, -1), dicts.get(numbers, 5, -1), len(numbers))
    \\    return 0
    \\
;

/// Build `small_tables` with the new core in `mode` and run it; its standard output.
fn smallTablesOutput(arena: std.mem.Allocator, root: []const u8, mode: []const []const u8) ![]const u8 {
    const program = try std.fmt.allocPrint(arena, "{s}/small.selka", .{root});
    const output = try std.fmt.allocPrint(arena, "{s}/small-{d}", .{ root, mode.len });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", program, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, mode);
    try support.requireReleaseArgs(mode);
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
    const llvm = try support.releaseLlvmTextOfProject(arena, small_tables);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%sh_hit = icmp eq i64 %sh, %hash") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "br i1 %clean, label %scan, label %slow") != null);
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "small.selka", .data = small_tables });
    // The old core's output for the same program.
    const expected = "3 2 -1 5\n-1 3 9 -1 6\n";
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{}));
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{"--release"}));
    try std.testing.expectEqualStrings(expected, try smallTablesOutput(arena, root, &.{ "--release", "--verify-facts" }));
}

// spec-case: NEW-CORE-DICT-1
test "gap_dict copy sinks only across safe scalar update regions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (0..8) |variant| {
        var module: ir.Module = .{};
        const list = try module.intern(a, .{ .list = .str });
        const dict = try module.intern(a, .{ .dict = .{ .key = .str, .value = .i64 } });
        try module.functions.append(a, .{ .name = "myl_core_owned_octets_copy", .signature = .{ .params = &.{.str}, .ret = .str, .linkage = if (variant == 1) .extern_c else .runtime_c } });
        var hand = try support.Hand.init(a, &module, "update", .{ .params = &.{ list, dict }, .ret = dict });
        const source_list = try hand.param(0);
        const mapping = try hand.param(1);
        const zero = try hand.int(.i64, 0);
        const key = try hand.emit(.{ .op = .list_get, .ty = .str, .a = source_list, .b = zero });
        const copied = try hand.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(@as(u32, 0)), .data = try hand.extra(&.{key}) });
        if (variant == 2) _ = try hand.emit(.{ .op = .list_copy, .ty = list, .a = source_list });
        if (variant == 3) _ = try hand.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(@as(u32, 0)), .data = try hand.extra(&.{key}) });
        if (variant == 4) _ = try hand.emit(.{ .op = .list_push, .ty = list, .a = source_list, .b = copied });
        const probe = try hand.emit(.{ .op = .dict_find, .ty = .i64, .a = mapping, .b = copied });
        const found = try hand.newBlock();
        const missing = try hand.newBlock();
        const condition = try hand.emit(.{ .op = .cmp, .ty = .bool, .a = probe, .b = zero, .data = @backingInt(ir.Predicate.ge) });
        try hand.branch(condition, found, missing);
        hand.block = found;
        const updated = try hand.emit(.{ .op = .dict_set_value, .ty = dict, .a = mapping, .b = probe, .data = try hand.extra(&.{zero}) });
        _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = updated });
        hand.block = missing;
        if (variant == 6) {
            const insert_block = try hand.newBlock();
            try hand.branch(condition, missing, insert_block);
            hand.block = insert_block;
        }
        if (variant == 7) _ = try hand.emit(.{ .op = .dict_find, .ty = .i64, .a = mapping, .b = copied });
        if (variant == 5) _ = try hand.emit(.{ .op = .list_set, .ty = list, .a = source_list, .b = zero, .data = try hand.extra(&.{key}) });
        const inserted = try hand.emit(.{ .op = .dict_insert, .ty = dict, .a = mapping, .b = probe, .data = try hand.extra(&.{ copied, zero }) });
        _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = inserted });
        const changed = try @import("fuse_dict.zig").updateCopies(a, &module, &hand.function);
        try std.testing.expectEqual(@as(u32, if (variant == 0) 1 else 0), changed);
        if (variant == 0) {
            try std.testing.expectEqual(ir.Op.copy, hand.function.inst(copied).op);
            const owned_key = hand.function.operands(hand.function.inst(inserted).data)[0];
            try std.testing.expectEqual(ir.Op.call, hand.function.inst(owned_key).op);
            try std.testing.expectEqual(key, hand.function.operands(hand.function.inst(owned_key).data)[0]);
            try std.testing.expectEqual(owned_key, hand.function.blocks.items[missing.index()].insts.items[0]);
        }
    }
}

// spec-case: NEW-CORE-DICT-1
test "gap_dict native inserted keys survive source replacement and early exits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program_source =
        \\import dicts
        \\import lists
        \\
        \\func fill(stop: bool) -> int:
        \\    mut keys = ["alpha-" + str(1), "beta-" + str(2)]
        \\    mut counts: dict[str, int] = {}
        \\    for i in range(200):
        \\        mut key = copy(keys[i % 2])
        \\        counts[own key] = dicts.get(counts, key, 0) + 1
        \\        if stop and i == 17:
        \\            return counts["alpha-1"] + counts["beta-2"]
        \\    keys[0] = "replacement-" + str(3)
        \\    lists.clear(mut keys)
        \\    return counts["alpha-1"] + counts["beta-2"]
        \\func main(out: Stream) -> int:
        \\    print(out, fill(False), fill(True))
        \\    mut keys = ["saved-" + str(1)]
        \\    mut counts: dict[str, int] = {}
        \\    mut key = copy(keys[0])
        \\    keys[0] = "changed-" + str(2)
        \\    counts[own key] = dicts.get(counts, key, 0) + 1
        \\    lists.clear(mut keys)
        \\    print(out, counts["saved-1"])
        \\    append(mut keys, "managed-" + str(1))
        \\    mut managed: dict[str, str] = {}
        \\    for i in range(20):
        \\        mut managed_key = copy(keys[0])
        \\        managed[own managed_key] = "value-" + str(i)
        \\    keys[0] = "other-" + str(2)
        \\    lists.clear(mut keys)
        \\    print(out, managed["managed-1"])
        \\    return 0
    ;
    const program = try support.checkedProgram(a, program_source);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").check(a, program, &failure);
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{
            .program = program,
        }, &refusal);
        const result = if (optimized) try @import("passes.zig").run(a, &module, .verify) else try @import("passes.zig").debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result), .main = .{ .parameters = &.{"out"}, .capabilities = &.{0} } });
        if (run.status != 0) report("gap_dict native: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("200 18\n1\nvalue-19\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
    }
}

// spec-case: NEW-CORE-DICT-1
test "gap_dict large functions conservatively retain copies within analysis budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module: ir.Module = .{};
    var f: ir.Function = .{ .name = "large", .signature = .{ .params = &.{}, .ret = .void } };
    try f.insts.resize(arena.allocator(), 4097);
    @memset(f.insts.items, .{ .op = .undef, .ty = .void });
    try std.testing.expectEqual(@as(u32, 0), try @import("fuse_dict.zig").updateCopies(arena.allocator(), &module, &f));
}

// spec-case: NEW-CORE-DICT-1
test "gap_dict original migrated source exposes the local update shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\import dicts
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    mut keys: str[] = []
        \\    for i in range(1000):
        \\        append(mut keys, "key" + str(i))
        \\    mut counts: dict[str, int] = {}
        \\    for i in range(2000000):
        \\        mut key = copy(keys[(i * 7919) % 1000])
        \\        counts[own key] = dicts.get(counts, key, 0) + 1
        \\    mut total = 0
        \\    for name in keys:
        \\        total = (total + counts[name] * strings.char_count(name)) % 1000003
        \\    print(out, total)
        \\    return 0
    ;
    const checked = try support.checkSource(a, text);
    try std.testing.expect(checked.passed);
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(a, .{
        .program = checked.program.?,
    }, &refusal);
    try gapDictMissPlacement(&module);
    try support.verified(a, &module, &.{});
}

fn gapDictMissPlacement(module: *const ir.Module) !void {
    var misses: usize = 0;
    for (module.functions.items) |f| for (f.blocks.items) |block| for (block.insts.items, 0..) |ref, at| {
        const inst = f.inst(ref);
        if (inst.op != .dict_insert) continue;
        const key = f.resolve(f.operands(inst.data)[0]);
        try std.testing.expect(f.inst(key).op == .call);
        try std.testing.expect(at >= 2 and block.insts.items[at - 2] == key);
        try std.testing.expectEqual(ir.Op.dict_find, f.inst(block.insts.items[at - 1]).op);
        misses += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), misses);
}

const borrowed_key_store =
    \\func collect(names: str[]) -> int:
    \\    mut d: dict[str, int] = {}
    \\    for n in names:
    \\        d[n] = 1
    \\    return len(d)
    \\
    \\func main() -> int:
    \\    return collect(["a", "b", "a"])
;

/// What the lowering gave the two edges of a store: the calls on the edge that replaces a value, the key copies on the edge
/// that inserts, and whether the insertion stores the copy under a probe of the copy.
const EdgeCopies = struct { replacing_calls: usize = 0, inserting_copies: usize = 0, probes_the_copy: bool = false };

fn edgeCopies(module: *const ir.Module, function: *const ir.Function) EdgeCopies {
    var found: EdgeCopies = .{};
    for (function.blocks.items) |block| {
        var replaces = false;
        var calls: usize = 0;
        var insert: ?ir.Ref = null;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            replaces = replaces or inst.op == .dict_set_value;
            if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_owned_octets_copy")) calls += 1;
            if (inst.op == .dict_insert) insert = ref;
        }
        if (replaces) found.replacing_calls += calls;
        const stored = insert orelse continue;
        found.inserting_copies += calls;
        const key = function.operands(function.inst(stored).data)[0];
        const probe = function.inst(function.resolve(function.inst(stored).b));
        found.probes_the_copy = function.inst(key).op == .call and probe.op == .dict_find and function.resolve(probe.b) == key;
    }
    return found;
}

// spec-case: NEW-CORE-DICT-1
test "a store with a borrowed key copies it on the inserting edge, probes the copy, and replaces the value on the other edge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, borrowed_key_store, &refusal);
    var collect: ?*const ir.Function = null;
    for (module.functions.items) |*function| {
        if (std.mem.endsWith(u8, function.name, "collect")) collect = function;
    }
    const found = edgeCopies(&module, collect.?);
    try std.testing.expectEqual(@as(usize, 0), found.replacing_calls);
    try std.testing.expectEqual(@as(usize, 1), found.inserting_copies);
    try std.testing.expect(found.probes_the_copy);
}

const borrowed_record_probe =
    \\record Pair:
    \\    name: str
    \\    slot: int
    \\
    \\func probe(pairs: Pair[], d: dict[Pair, int]) -> int:
    \\    mut total = 0
    \\    for i in range(len(pairs)):
    \\        const p = pairs[i]
    \\        if p in d:
    \\            total += d[p]
    \\    return total
    \\
    \\func store(pairs: Pair[]) -> int:
    \\    mut d: dict[Pair, int] = {}
    \\    for i in range(len(pairs)):
    \\        const p = pairs[i]
    \\        d[p] = i
    \\    return len(d)
    \\
    \\func main() -> int:
    \\    const pairs: Pair[] = [Pair(name="a", slot=1)]
    \\    const d: dict[Pair, int] = {Pair(name="a", slot=1): 5}
    \\    return probe(pairs, d) + store(pairs)
;

// spec-case: NEW-CORE-DICT-1
test "a lookup or store keyed by a const bound to an element probes the key in its storage layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, borrowed_record_probe, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    try std.testing.expect(result.known.len != 0);
}

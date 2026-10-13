//! Explicit split counts and bounded scalar-reader inlining preserve owned escapes.
const std = @import("std");
const ir = @import("ir.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const reader = @import("inline_reader.zig");
const store = @import("stage_store.zig");
const cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const emitter = @import("emit_llvm.zig");
const fixture_name = "textgap_split.my";

fn checked(a: std.mem.Allocator) !ir.Module {
    const path = try std.fs.path.join(a, &.{ options.fixtures, fixture_name });
    const fixture = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    var unit = try @import("mylang").Compilation.init(a, fixture_name, fixture);
    try unit.check();
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
}

fn named(module: *ir.Module, name: []const u8) ?*ir.Function {
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

// spec-case: NEW-CORE-S2-SPLIT-2
test "textgap_split count observation retains private offsets and scalar readers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try checked(a);
    try @import("fuse_text_split.zig").run(a, &module);
    try @import("split_views.zig").run(a, &module);
    try std.testing.expect(named(&module, "fold") != null);
    const fold = named(&module, "fold").?;
    var counts: usize = 0;
    var materialized: usize = 0;
    for (fold.insts.items) |inst| {
        if (inst.op == .str_from_view) materialized += 1;
        if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split_offsets")) counts += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), counts);
    try std.testing.expectEqual(@as(usize, 1), materialized);
    try support.verified(a, &module, &.{});
    _ = try @import("fuse_encode.zig").runRecording(a, &module, null);
    try std.testing.expect(named(&module, "score") != null);
    const function = named(&module, "score").?;
    try std.testing.expect(reader.qualifies(&module, function));
    const signature = function.signature;
    function.signature.owned = 1;
    try std.testing.expect(!reader.qualifies(&module, function));
    function.signature.owned = 2;
    try std.testing.expect(!reader.qualifies(&module, function));
    function.signature = signature;
    function.signature.ret = .str;
    try std.testing.expect(!reader.qualifies(&module, function));
    function.signature = signature;
    const last = function.blocks.items[function.blocks.items.len - 1].insts.items;
    const ref = last[last.len - 1];
    const original = function.inst(ref);
    function.insts.items[ref.index()].op = .print;
    try std.testing.expect(!reader.qualifies(&module, function));
    function.insts.items[ref.index()] = original;
}

fn locate(_: *const anyopaque, offset: u32) emitter.Location {
    return .{ .line = 1, .column = offset + 1, .path = fixture_name };
}

const Produced = struct { llvm: []const u8, statistics: cache.Statistics };

fn compile(a: std.mem.Allocator, scratch: std.mem.Allocator, storage: ?*store.Store) !Produced {
    var module = try checked(a);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    var context: cache.Context = undefined;
    if (storage) |s| context = cache.Context.init(s, try snapshot.Context.init(a, &module, null), locator);
    const result = if (storage != null) try passes.runCached(a, scratch, &module, .trusted, &context) else try passes.runWithScratch(a, scratch, &module, .trusted);
    try support.verified(a, &module, result.plans);
    var found = false;
    for (module.functions.items) |function| if (std.mem.eql(u8, function.name, "fold")) {
        found = true;
        for (function.insts.items) |inst| try std.testing.expect(inst.op != .str_from_view);
    };
    try std.testing.expect(found);
    const llvm = try emitter.emitModule(a, &module, .{ .locator = locator, .source_path = fixture_name, .main = .{ .parameters = &.{"out"}, .capabilities = &.{0} }, .analysis = support.analysis(&result) });
    try std.testing.expect(@import("zero_rc.zig").emittedClean(llvm));
    return .{ .llvm = llvm, .statistics = if (storage != null) context.statistics else .{} };
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S2-SPLIT-2
test "textgap_split cold warm cached reader cleanup equals uncached LLVM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try dir.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const uncached = try compile(a, std.testing.allocator, null);
    const cold = try compile(a, std.testing.allocator, &storage);
    const warm = try compile(a, std.testing.allocator, &storage);
    try std.testing.expectEqualStrings(uncached.llvm, cold.llvm);
    try std.testing.expectEqualStrings(cold.llvm, warm.llvm);
    try std.testing.expect(warm.statistics.hits[@backingInt(cache.Stage.inline_cfg)] > 0);
    try std.testing.expectEqual(@as(u64, 0), warm.statistics.misses[@backingInt(cache.Stage.inline_cfg)]);
}

// spec-case: NEW-CORE-S2-SPLIT-2
test "textgap_split five native modes preserve lengths Unicode escapes and early traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--unoptimized"}, &.{"--release"}, &.{"--verify-facts"}, &.{ "--release", "--verify-facts" } }) |flags| {
        for ([_][]const u8{ fixture_name, "textgap_split_empty.my", "textgap_split_reader_trap.my" }, 0..) |name, index| {
            var argv: std.ArrayList([]const u8) = .empty;
            try argv.appendSlice(a, &.{ options.corePath(), "run", try std.fs.path.join(a, &.{ options.fixtures, name }), "--cache-dir", root, "--experimental-zero-rc" });
            try argv.appendSlice(a, flags);
            const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
            if (index == 0) {
                if (ran.term != .exited or ran.term.exited != 0) std.debug.print("{s}{s}\n", .{ ran.stdout, ran.stderr });
                try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
                try std.testing.expectEqualStrings("7 492 1077 304\n318 318\n", ran.stdout);
                try std.testing.expectEqualStrings("", ran.stderr);
            } else {
                try std.testing.expect(ran.term == .exited and ran.term.exited != 0);
                try std.testing.expectEqualStrings("before\n", ran.stdout);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, if (index == 1) "R_EMPTY_SEPARATOR" else "R_LIST_BOUNDS") != null);
                if (index == 2) try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "read_past") != null);
            }
        }
    }
}

// spec-case: NEW-CORE-S2-SPLIT-2
test "textgap_split reader runtime signature authority and cloned module targets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    const signature: ir.Signature = .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 1 };
    try module.functions.append(a, .{ .name = "myl_core_span_bytes_index_offset", .signature = signature });
    var hand = try support.Hand.init(a, &module, "offset_reader", .{ .params = &.{ .str, .i64 }, .ret = .u64 });
    const text = try hand.param(0);
    const at = try hand.param(1);
    const offset = try hand.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(0), .data = try hand.extra(&.{ text, at }) });
    const tail = try hand.newBlock();
    try hand.jump(tail);
    hand.block = tail;
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = offset });
    const callee = try hand.finish();
    try std.testing.expect(reader.qualifies(&module, &module.functions.items[callee]));
    module.zero_rc = false;
    try std.testing.expect(!reader.qualifies(&module, &module.functions.items[callee]));
    module.zero_rc = true;
    for ([_]ir.Signature{
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .extern_c, .views = 1 },
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c },
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 3 },
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 1, .owned = 1 },
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 1, .consumes = 1 },
    }) |near_miss| {
        module.functions.items[0].signature = near_miss;
        try std.testing.expect(!reader.qualifies(&module, &module.functions.items[callee]));
    }
    module.functions.items[0].signature = signature;
    var main = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const output = try main.param(0);
    try module.strings.append(a, "abc");
    const value = try main.loose(.{ .op = .str_const, .ty = .str });
    const index = try main.int(.i64, 1);
    const read = try main.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(@as(u32, @intCast(callee))), .data = try main.extra(&.{ value, index }) });
    try main.printValues(output, &.{read});
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    module.entry = try main.finish();
    const result = try passes.run(a, &module, .trusted);
    try support.verified(a, &module, result.plans);
    const ran = try support.runOwned(a, &module, .{ .own = false, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("1\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S2-SPLIT-2
test "textgap_split bounded reserve clamps overflow inputs and sparse long spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const harness_path = try std.fs.path.join(a, &.{ options.fixtures, "../../experiments/text-gaps-20261012/split/reserve-harness.c" });
    const harness = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, harness_path, a, .limited(1 << 20));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "core_rt.c", .data = @import("driver.zig").runtime_source });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "harness.c", .data = harness });
    var environment = try std.testing.environ.createMap(a);
    const zig = environment.get("ZIG") orelse "zig";
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const source = try std.fs.path.join(a, &.{ root, "harness.c" });
    const binary = try std.fs.path.join(a, &.{ root, "harness" });
    const built = try std.process.run(a, std.testing.io, .{ .argv = &.{ zig, "cc", "-O2", "-std=c11", "-pthread", "-o", binary, source }, .environ_map = &environment });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    try std.testing.expectEqualStrings("", built.stderr);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary} });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("1 128 8192\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

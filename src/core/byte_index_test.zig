//! Byte index normalization keeps its signed semantics and source ABI authority.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;
const ir = @import("ir.zig");
const signed_min_text = "-9223372036854775808";
const signed_max_text = "9223372036854775807";
const facts = @import("facts.zig");
const byte_index = @import("byte_index.zig");

const program =
    \\func indexed(raw: bytes, index: int) -> int:
    \\    return raw[index]
    \\func mutable_indexed(raw: byte_buffer, index: int) -> int:
    \\    return raw[index]
    \\func main(args: str[], out: Stream) -> int:
    \\    mut index = 0
    \\    match parse_int(args[0]):
    \\        case Some(value):
    \\            index = value
    \\        case None:
    \\            return 2
    \\    if args[1] == "bytes":
    \\        out.print(indexed(b"abc", index))
    \\    elif args[1] == "buffer":
    \\        out.print(mutable_indexed(byte_buffer([97, 98, 99]), index))
    \\    else:
    \\        out.print(indexed(b"", index))
    \\    return 0
;

// spec-case: NEW-CORE-LLVM-1
test "byte index runtime adapters inline modular negative normalization with the bounds check retained" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const llvm = try support.llvmText(state.allocator(), program);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "select i1 %bynegative") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, " = add i64 %p1, %bylen") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call void @myl_core_trap") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "a source extern byte index lookalike is rejected by the reserved runtime namespace rule" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const source =
        \\extern func myl_core_bytes_index_offset(host: Host, raw: int, index: int) -> u64 effects(host)
        \\func main(host: Host, out: Stream) -> int:
        \\    out.print(myl_core_bytes_index_offset(host, 3, 1))
        \\    return 0
    ;
    var unit = try @import("mylang").Compilation.init(state.allocator(), "lookalike.my", source);
    defer unit.deinit();
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", unit.diagnostics.items[0].code);
}

// spec-case: NEW-CORE-LLVM-1
test "an extern C call with the exact byte adapter ABI lacks compiler runtime authority" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, "myl_core_bytes_index_offset")) function.signature.linkage = .extern_c;
    }
    try support.verified(a, &module, &.{});
    const context: u8 = 0;
    const llvm = try @import("emit_llvm.zig").emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "authority.my",
        .main = .{ .parameters = &.{ "args", "out" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%bynegative") == null);
}

fn location(_: *const anyopaque, _: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = 1 };
}

fn nativeIndices(a: std.mem.Allocator, root: []const u8, mode: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/index.my", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/index", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, output: []const u8, normalized: []const u8 }{
        .{ .index = "-1", .output = "99\n", .normalized = "" },
        .{ .index = "-3", .output = "97\n", .normalized = "" },
        .{ .index = "0", .output = "97\n", .normalized = "" },
        .{ .index = "2", .output = "99\n", .normalized = "" },
        .{ .index = "-4", .output = "", .normalized = "-4" },
        .{ .index = "3", .output = "", .normalized = "3" },
        .{ .index = signed_min_text, .output = "", .normalized = signed_min_text },
        .{ .index = signed_max_text, .output = "", .normalized = signed_max_text },
    };
    for ([_][]const u8{ "bytes", "buffer" }) |receiver| {
        for (cases) |case| {
            const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, case.index, receiver }, .environ_map = &environment });
            try std.testing.expect(ran.term == .exited);
            try std.testing.expectEqualStrings(case.output, ran.stdout);
            if (case.normalized.len == 0) {
                try std.testing.expectEqual(@as(u8, 0), ran.term.exited);
                try std.testing.expectEqualStrings("", ran.stderr);
            } else {
                try std.testing.expectEqual(@as(u8, 1), ran.term.exited);
                const bounds = try std.fmt.allocPrint(a, "error[R_LIST_BOUNDS]: native execution failed (index {s}, length 3)", .{case.normalized});
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, bounds) != null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "MYLANG-TRAP") != null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "leak") == null);
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_FACT") == null);
            }
        }
    }
    const empty = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, "-1", "empty" }, .environ_map = &environment });
    try std.testing.expect(empty.term == .exited and empty.term.exited == 1);
    try std.testing.expectEqualStrings("", empty.stdout);
    try std.testing.expect(std.mem.indexOf(u8, empty.stderr, "index -1, length 0") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "bytes and buffers normalize negative and extreme signed indices before their located bounds trap in every mode" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "index.my", .data = program });
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| try nativeIndices(a, root, mode);
}

const reduction =
    \\func total(raw: bytes) -> int:
    \\    mut value = 0
    \\    for index in range(len(raw)):
    \\        value += raw[index]
    \\    return value
    \\func main(out: Stream) -> int:
    \\    out.print(total(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
    \\    return 0
;

// spec-case: NEW-CORE-VECTOR-3
test "proven counted byte indices expose the original cursor to existing narrow vector planning" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    const llvm = try support.releaseLlvmText(a, reduction);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.x86.avx2.psad.bw") != null);
    // Verify still normalizes every access, but asserts the exact counter fact
    // used to forward the trusted adapter: its derived signed interval starts at 0.
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, reduction, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    var checked = false;
    const context: u8 = 0;
    const verified = try @import("emit_llvm.zig").emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "verify-index.my",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
        .verify = true,
    });
    for (module.functions.items, result.known) |*function, maybe| {
        const known = maybe orelse continue;
        for (function.insts.items) |inst| {
            if (!byte_index.adapter(&module, inst)) continue;
            const raw = function.resolve(function.operands(inst.data)[1]);
            const range = facts.valueRange(&known, function, raw) orelse continue;
            if (range.lo < 0 or function.inst(raw).op != .phi) continue;
            const lower_check = try std.fmt.allocPrint(a, "icmp slt i64 %v{d}, 0", .{raw.index()});
            try std.testing.expect(std.mem.indexOf(u8, verified, lower_check) != null);
            checked = true;
        }
    }
    try std.testing.expect(checked);
    try std.testing.expect(std.mem.indexOf(u8, verified, "select i1 %bynegative") != null);
    try std.testing.expect(std.mem.indexOf(u8, verified, "load <32 x i8>") == null);
}

fn adapterModule(a: std.mem.Allocator, raw: ?i64, return_offset: bool, linkage: ir.Linkage) !ir.Module {
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "myl_core_bytes_index_offset", .signature = .{ .params = &.{ .bytes, .i64 }, .ret = .u64, .linkage = linkage } });
    var hand = try support.Hand.init(a, &module, "read", .{ .params = &.{ .bytes, .i64 }, .ret = if (return_offset) .u64 else .i64 });
    const receiver = try hand.param(0);
    const index = if (raw) |value| try hand.int(.i64, value) else try hand.param(1);
    const offset = try hand.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(0), .data = try hand.extra(&.{ receiver, index }) });
    const result = if (return_offset) offset else result: {
        const read = try hand.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = offset, .check = .exact });
        break :result try hand.emit(.{ .op = .convert, .ty = .i64, .a = read });
    };
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = result });
    module.entry = try hand.finish();
    try support.verified(a, &module, &.{});
    return module;
}

// spec-case: NEW-CORE-LLVM-1
test "byte index forwarding excludes negative unknown foreign and non-index adapter uses" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    const cases = [_]struct { raw: ?i64, returns: bool = false, linkage: ir.Linkage = .runtime_c }{
        .{ .raw = -1 }, .{ .raw = null }, .{ .raw = 1, .returns = true }, .{ .raw = 1, .linkage = .extern_c },
    };
    for (cases) |case| {
        var module = try adapterModule(a, case.raw, case.returns, case.linkage);
        const function = &module.functions.items[module.entry];
        const known = try facts.analyze(a, function, .{ .fold = false });
        try std.testing.expectEqual(@as(u32, 0), byte_index.forward(&module, function, &known));
        try std.testing.expectEqual(.call, function.insts.items[2].op);
        try support.verified(a, &module, &.{});
    }
}

// spec-case: NEW-CORE-VERIFY-1
test "the exact nonnegative byte index premise traps R_CORE_FACT when an injected interval excludes a valid negative input" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    const source =
        \\func read(raw: bytes, initial: int) -> int:
        \\    mut index = initial
        \\    for ignored in range(1):
        \\        index += 0
        \\    return raw[index]
        \\func main(out: Stream) -> int:
        \\    out.print(read(b"abc", -1))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    var injected = false;
    for (module.functions.items, result.known) |function, *maybe| {
        if (function.signature.linkage != .internal or function.signature.params.len != 2) continue;
        if (function.signature.params[0] != .bytes or function.signature.params[1] != .i64) continue;
        for (function.insts.items, 0..) |inst, index| {
            if (inst.op != .param or inst.data != 1) continue;
            maybe.*.?.ranges[index] = .{ .lo = 0, .hi = std.math.maxInt(i64) };
            injected = true;
        }
    }
    try std.testing.expect(injected);
    const ran = try support.runOwned(a, &module, .{ .own = false, .verify = true, .release = true, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("", ran.stdout);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "error[R_CORE_FACT]: native execution failed (range [0, 9223372036854775807]: value -1") != null);
}

const span_fixture = "textgap_span_index.my";
const emitter = @import("emit_llvm.zig");
const cache_store = @import("stage_store.zig");
const optimizer_cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const passes = @import("passes.zig");

fn spanModule(a: std.mem.Allocator, raw: ?i64, returns: bool, other: bool, extra: bool) !ir.Module {
    var module: ir.Module = .{ .zero_rc = true };
    try module.strings.append(a, "abc");
    try module.functions.append(a, .{ .name = "myl_core_span_bytes_index_offset", .signature = .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 1 } });
    var h = try support.Hand.init(a, &module, "read", .{ .params = &.{.i64}, .ret = if (returns) .u64 else .i64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const start = try h.int(.u64, 0);
    const width = try h.extra(&.{try h.int(.u64, 3)});
    const view = try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = text, .b = start, .data = width });
    const receiver = if (other) try h.emit(.{ .op = .str_view_of, .ty = .str_view, .a = text, .b = start, .data = width }) else view;
    const index = if (raw) |value| try h.int(.i64, value) else try h.param(0);
    const offset = try h.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(0), .data = try h.extra(&.{ view, index }) });
    if (extra) _ = try h.emit(.{ .op = .cmp, .ty = .bool, .a = offset, .b = start, .data = @backingInt(ir.Predicate.eq) });
    const result = if (returns) offset else result: {
        const read = try h.emit(.{ .op = .list_get, .ty = .u8, .a = receiver, .b = offset, .check = .exact });
        break :result try h.emit(.{ .op = .convert, .ty = .i64, .a = read });
    };
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = result });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    return module;
}

const SpanCase = enum { valid, negative, unknown, escaped, other, extra, foreign, symbol, views, owned, consumes, layout, result, flag, raw_type, ordinary };

fn qualifySpan(a: std.mem.Allocator, case: SpanCase) !void {
    var module = try spanModule(a, if (case == .unknown) null else if (case == .negative) -1 else 1, case == .escaped, case == .other, case == .extra);
    const function = &module.functions.items[module.entry];
    switch (case) {
        .foreign => module.functions.items[0].signature.linkage = .extern_c,
        .symbol => module.functions.items[0].name = "myl_core_span_bytes_index_offset_other",
        .views => module.functions.items[0].signature.views = 0,
        .owned => module.functions.items[0].signature.owned = 1,
        .consumes => module.functions.items[0].signature.consumes = 1,
        .layout => module.functions.items[0].signature.params = &.{ .bytes, .i64 },
        .result => module.functions.items[0].signature.ret = .i64,
        .flag => for (function.insts.items) |*inst| {
            if (inst.op == .list_get) inst.data = 1;
        },
        .raw_type => for (function.insts.items) |inst| {
            if (inst.op == .call) function.insts.items[function.resolve(function.operands(inst.data)[1]).index()].ty = .u64;
        },
        .ordinary => module.zero_rc = false,
        else => {},
    }
    const known = try facts.analyze(a, function, .{ .fold = false });
    try std.testing.expectEqual(@as(u32, if (case == .valid) 1 else 0), byte_index.forward(&module, function, &known));
}

// spec-case: NEW-CORE-LLVM-1
// spec-case: NEW-CORE-S1-VIEW-4
test "span byte index forwarding requires exact authority receiver and complete read-only result use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (std.enums.values(SpanCase)) |case| try qualifySpan(arena.allocator(), case);
}

fn spanSource(a: std.mem.Allocator) !ir.Module {
    const path = try std.fs.path.join(a, &.{ options.fixtures, span_fixture });
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    var unit = try @import("mylang").Compilation.init(a, span_fixture, source);
    try unit.check();
    var refusal: @import("build.zig").Refusal = .{};
    return @import("build.zig").buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
}

const SpanCompiled = struct { llvm: []const u8, statistics: optimizer_cache.Statistics };

fn compileSpan(a: std.mem.Allocator, scratch: std.mem.Allocator, storage: ?*cache_store.Store) !SpanCompiled {
    var module = try spanSource(a);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = location };
    var context: optimizer_cache.Context = undefined;
    if (storage) |s| context = optimizer_cache.Context.init(s, try snapshot.Context.init(a, &module, null), locator);
    const result = if (storage != null) try passes.runCached(a, scratch, &module, .trusted, &context) else try passes.runWithScratch(a, scratch, &module, .trusted);
    try support.verified(a, &module, result.plans);
    var walks: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.eql(u8, function.name, "walk") and !std.mem.eql(u8, function.name, "at_zero")) continue;
        walks += 1;
        for (function.insts.items) |inst| {
            if (inst.op != .call) continue;
            try std.testing.expect(!std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_span_bytes_index_offset"));
        }
    }
    try std.testing.expectEqual(@as(usize, 2), walks);
    const llvm = try emitter.emitModule(a, &module, .{ .locator = locator, .source_path = span_fixture, .main = .{ .parameters = &.{ "args", "out" }, .capabilities = &.{ 0, 0 } }, .analysis = support.analysis(&result) });
    return .{ .llvm = llvm, .statistics = if (storage != null) context.statistics else .{} };
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S1-VIEW-4
test "span byte index forwarding agrees in uncached cold and warm final cache artifacts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var storage = try cache_store.Store.init(std.testing.allocator, std.testing.io, try dir.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const uncached = try compileSpan(a, std.testing.allocator, null);
    const cold = try compileSpan(a, std.testing.allocator, &storage);
    const warm = try compileSpan(a, std.testing.allocator, &storage);
    try std.testing.expectEqualStrings(uncached.llvm, cold.llvm);
    try std.testing.expectEqualStrings(cold.llvm, warm.llvm);
    try std.testing.expect(warm.statistics.hits[@backingInt(optimizer_cache.Stage.final)] > 0);
    try std.testing.expectEqual(@as(u64, 0), warm.statistics.misses[@backingInt(optimizer_cache.Stage.final)]);
}

fn nativeSpan(a: std.mem.Allocator, root: []const u8, mode: []const []const u8) !void {
    const output = try std.fs.path.join(a, &.{ root, "span-index" });
    const source = try std.fs.path.join(a, &.{ options.fixtures, span_fixture });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", root, "--experimental-zero-rc" });
    try argv.appendSlice(a, mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("span build flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ mode, built.term, built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, value: ?[]const u8, source: []const u8 = "aé🙂", length: u32 = 7, sum: []const u8 = "1143" }{
        .{ .index = "0", .value = "97\n" },                                      .{ .index = "6", .value = "130\n" }, .{ .index = "-1", .value = "130\n" }, .{ .index = "-7", .value = "97\n" },
        .{ .index = "0", .value = null, .source = "", .length = 0, .sum = "0" }, .{ .index = "7", .value = null },    .{ .index = "-8", .value = null },    .{ .index = signed_max_text, .value = null },
        .{ .index = signed_min_text, .value = null },
    };
    for (cases) |case| {
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, case.index, case.source }, .environ_map = &environment });
        const wanted: u8 = if (case.value != null) 0 else 1;
        if (ran.term != .exited or ran.term.exited != wanted) report("span run index {s}, flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ case.index, mode, ran.term, ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited);
        const expected = try std.mem.concat(a, u8, &.{ "before ", case.sum, "\n", case.value orelse "" });
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqual(@as(u8, if (case.value != null) 0 else 1), ran.term.exited);
        if (case.value != null) {
            try std.testing.expectEqualStrings("", ran.stderr);
        } else {
            const bounds = try std.fmt.allocPrint(a, "index {s}, length {d}", .{ case.index, case.length });
            try std.testing.expect(std.mem.indexOf(u8, ran.stderr, bounds) != null);
            try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_LIST_BOUNDS") != null);
            try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "leak") == null);
        }
    }
}

// spec-case: NEW-CORE-S1-VIEW-4
test "span byte index cases preserve Unicode negative extreme and ordered bounds traps in seven native modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{}, &.{"--unoptimized"}, &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--no-facts" }, &.{"--verify-facts"}, &.{ "--release", "--verify-facts" } }) |mode| try nativeSpan(a, root, mode);
}

// spec-case: NEW-CORE-LLVM-1
test "span byte index work cap preserves existing owned-byte forwarding for large bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var span = try spanModule(a, 1, false, false, false);
    const view = &span.functions.items[span.entry];
    try view.insts.appendNTimes(a, .{ .op = .undef, .ty = .i64 }, 4097);
    const view_known = try facts.analyze(a, view, .{ .fold = false });
    try std.testing.expectEqual(@as(u32, 0), byte_index.forward(&span, view, &view_known));
    var owned = try adapterModule(a, 1, false, .runtime_c);
    const bytes = &owned.functions.items[owned.entry];
    try bytes.insts.appendNTimes(a, .{ .op = .undef, .ty = .i64 }, 4097);
    const owned_known = try facts.analyze(a, bytes, .{ .fold = false });
    try std.testing.expectEqual(@as(u32, 1), byte_index.forward(&owned, bytes, &owned_known));
}

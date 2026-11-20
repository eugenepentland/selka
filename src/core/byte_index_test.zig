//! Byte indexes retain written signed values and source ABI authority.
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
    \\        print(out, indexed(b"abc", index))
    \\    elif args[1] == "buffer":
    \\        print(out, mutable_indexed(byte_buffer([97, 98, 99]), index))
    \\    else:
    \\        print(out, indexed(b"", index))
    \\    return 0
;

// spec-case: NEW-CORE-LLVM-1
test "byte index runtime adapters preserve written indexes with the bounds check retained" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const llvm = try support.llvmText(state.allocator(), program);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "select i1 %bynegative") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, " = add i64 %p1, 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call void @myl_core_trap") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "a source extern byte index lookalike is rejected by the reserved runtime namespace rule" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const source =
        // migrate-embedded: skip intentional original effects-removal witness
        \\extern func myl_core_bytes_index_offset(host: Host, raw: int, index: int) -> u64 effects(host)
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, myl_core_bytes_index_offset(host, 3, 1))
        \\    return 0
    ;
    var unit = try @import("selka").Compilation.init(state.allocator(), "lookalike.selka", source);
    defer unit.deinit();
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expectEqualStrings("E_EFFECTS_REMOVED", unit.diagnostics.items[0].code);
    const modern = try std.mem.replaceOwned(u8, state.allocator(), source, " effects(host)", "");
    var foreign = try @import("selka").Compilation.init(state.allocator(), "lookalike-modern.selka", modern);
    defer foreign.deinit();
    try std.testing.expectError(error.SourceError, foreign.check());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", foreign.diagnostics.items[0].code);
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
        .source_path = "authority.selka",
        .main = .{ .parameters = &.{ "args", "out" } },
    });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_bytes_index_offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "%bynegative") == null);
}

fn location(_: *const anyopaque, _: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = 1 };
}

fn nativeIndices(a: std.mem.Allocator, root: []const u8, mode: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/index.selka", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/index", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, output: []const u8, normalized: []const u8 }{
        .{ .index = "-1", .output = "", .normalized = "-1" },
        .{ .index = "-3", .output = "", .normalized = "-3" },
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
                try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "SELKA-TRAP") != null);
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
test "bytes and buffers trap on negative and extreme signed indexes in every mode" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "index.selka", .data = program });
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| try nativeIndices(a, root, mode);
}

const reduction =
    \\func total(raw: bytes) -> int:
    \\    mut value = 0
    \\    for index in range(len(raw)):
    \\        value += raw[index]
    \\    return value
    \\func main(out: Stream) -> int:
    \\    print(out, total(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
    \\    return 0
;

/// The span form of the index offset adapter a plain bytes parameter's read calls (C9 bytes).
fn spanOffsetCall(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.a.index() >= module.functions.items.len) return false;
    return std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_span_bytes_index_offset");
}

// spec-case: NEW-CORE-VECTOR-3
test "proven counted byte indices expose the original cursor to existing narrow vector planning" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    const llvm = try support.releaseLlvmText(a, reduction);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "load <32 x i8>") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@llvm.x86.avx2.psad.bw") != null);
    // Verify preserves every written index and asserts the exact counter fact
    // used to forward the trusted adapter: its derived signed interval starts at 0.
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, reduction, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    var checked = false;
    const context: u8 = 0;
    const verified = try @import("emit_llvm.zig").emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "verify-index.selka",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
        .verify = true,
    });
    for (module.functions.items, result.known) |*function, maybe| {
        const known = maybe orelse continue;
        for (function.insts.items) |inst| {
            if (!byte_index.adapter(&module, inst) and !spanOffsetCall(&module, inst)) continue;
            const raw = function.resolve(function.operands(inst.data)[1]);
            const range = facts.valueRange(&known, function, raw) orelse continue;
            if (range.lo < 0 or function.inst(raw).op != .phi) continue;
            const lower_check = try std.fmt.allocPrint(a, "icmp slt i64 %v{d}, 0", .{raw.index()});
            try std.testing.expect(std.mem.indexOf(u8, verified, lower_check) != null);
            checked = true;
        }
    }
    try std.testing.expect(checked);
    try std.testing.expect(std.mem.indexOf(u8, verified, "select i1 %bynegative") == null);
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
        \\func pick(raw: bytes, index: int) -> int:
        \\    return raw[index]
        \\func read(raw: bytes, initial: int) -> int:
        \\    mut index = initial
        \\    for ignored in range(1):
        \\        index += 0
        \\    return pick(raw, index)
        \\func main(out: Stream) -> int:
        \\    print(out, read(b"abc", -1))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    var injected = false;
    for (module.functions.items, result.known) |function, *maybe| {
        if (function.signature.linkage != .internal or function.signature.params.len != 2) continue;
        // A plain `bytes` parameter is a bytes view (C9 bytes): its index is the view's offset adapter.
        if (function.signature.params[0] != .bytes_view or function.signature.params[1] != .i64) continue;
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

const span_fixture = "textgap_span_index.selka";
const emitter = @import("emit_llvm.zig");
const cache_store = @import("stage_store.zig");
const optimizer_cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const passes = @import("passes.zig");

fn spanModule(a: std.mem.Allocator, raw: ?i64, returns: bool, other: bool, extra: bool) !ir.Module {
    var module: ir.Module = .{};
    try module.strings.append(a, "abc");
    try module.functions.append(a, .{ .name = "myl_core_span_bytes_index_offset", .signature = .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .passing = .{ .views = 1 } } });
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

const SpanCase = enum { valid, negative, unknown, escaped, other, extra, foreign, symbol, views, owned, consumes, layout, result, flag, raw_type };

fn qualifySpan(a: std.mem.Allocator, case: SpanCase) !void {
    var module = try spanModule(a, if (case == .unknown) null else if (case == .negative) -1 else 1, case == .escaped, case == .other, case == .extra);
    const function = &module.functions.items[module.entry];
    switch (case) {
        .foreign => module.functions.items[0].signature.linkage = .extern_c,
        .symbol => module.functions.items[0].name = "myl_core_span_bytes_index_offset_other",
        .views => module.functions.items[0].signature.passing.views = 0,
        .owned => module.functions.items[0].signature.passing.owned = 1,
        .consumes => module.functions.items[0].signature.passing.consumes = 1,
        .layout => module.functions.items[0].signature.params = &.{ .bytes, .i64 },
        .result => module.functions.items[0].signature.ret = .i64,
        .flag => for (function.insts.items) |*inst| {
            if (inst.op == .list_get) inst.data = 1;
        },
        .raw_type => for (function.insts.items) |inst| {
            if (inst.op == .call) function.insts.items[function.resolve(function.operands(inst.data)[1]).index()].ty = .u64;
        },
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
    // The fixture imports `strings` (W13-S5: `source.encode()` is refused), so it is checked as an embedded project.
    const checked = try support.checkedProgram(a, source);
    var refusal: @import("build.zig").Refusal = .{};
    return @import("build.zig").buildExecutable(a, .{
        .program = checked,
    }, &refusal);
}

/// Whether `name` is the entry module's function `function`, bare or qualified by the module (`main.walk`, `main::walk`).
fn entryFunction(name: []const u8, function: []const u8) bool {
    if (std.mem.eql(u8, name, function)) return true;
    if (!std.mem.endsWith(u8, name, function) or name.len == function.len) return false;
    const separator = name[name.len - function.len - 1];
    return separator == '.' or separator == ':';
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
        // The fixture is an embedded project's entry module, whose functions carry its module's name.
        if (!entryFunction(function.name, "walk") and !entryFunction(function.name, "at_zero")) continue;
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
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("span build flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ mode, built.term, built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, value: ?[]const u8, source: []const u8 = "aé🙂", length: u32 = 7, sum: []const u8 = "1143" }{
        .{ .index = "0", .value = "97\n" },                                      .{ .index = "6", .value = "130\n" }, .{ .index = "-1", .value = null }, .{ .index = "-7", .value = null },
        .{ .index = "0", .value = null, .source = "", .length = 0, .sum = "0" }, .{ .index = "7", .value = null },    .{ .index = "-8", .value = null }, .{ .index = signed_max_text, .value = null },
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
test "span byte index cases preserve Unicode reads and negative extreme ordered bounds traps in seven native modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{ &.{}, &.{"--optimize-debug"}, &.{"--verify-facts"}, &.{"--release"}, &.{ "--release", "--no-facts" }, &.{ "--release", "--verify-facts" } }) |mode| try nativeSpan(a, root, mode);
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

const unproven =
    \\func step(i: int) -> int:
    \\    return i + 1
    \\func view_total(raw: bytes) -> int:
    \\    mut index = 0
    \\    mut total = 0
    \\    while index < len(raw):
    \\        total += raw[index]
    \\        index = step(index)
    \\    return total
    \\func text_total(own text: str) -> int:
    \\    mut index = 0
    \\    mut total = 0
    \\    while index < len(text):
    \\        total += text[index]
    \\        index = step(index)
    \\    return total
    \\func main(out: Stream) -> int:
    \\    print(out, view_total(b"abc"), text_total(copy("abc")))
    \\    return 0
;

fn noIndexCalls(llvm: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_span_bytes_index_offset") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call i64 @myl_core_ir_str_byte") == null);
    // The guard that precedes each read, and its located trap, are still emitted; the read is a plain load.
    try std.testing.expect(std.mem.indexOf(u8, llvm, "icmp uge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "call void @myl_core_trap") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, " = zext i8 ") != null);
}

// spec-case: NEW-CORE-LLVM-1
test "a bytes view index and an owned text read of an unproven index lower without a runtime call" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    try noIndexCalls(try support.llvmText(a, unproven));
    try noIndexCalls(try support.releaseLlvmText(a, unproven));
}

fn strByteModule(a: std.mem.Allocator, result: ir.Type) !ir.Module {
    var module: ir.Module = .{};
    try module.strings.append(a, "abc");
    try module.functions.append(a, .{ .name = "myl_core_ir_str_byte", .signature = .{ .params = &.{ .str, .i64 }, .ret = result, .linkage = .extern_c, .passing = .{ .views = 1 } } });
    var h = try support.Hand.init(a, &module, "read", .{ .params = &.{}, .ret = .i64 });
    const text = try h.loose(.{ .op = .str_const, .ty = .str });
    const index = try h.int(.i64, 1);
    const octet = try h.emit(.{ .op = .call, .ty = result, .a = @fromBackingInt(0), .data = try h.extra(&.{ text, index }) });
    const wide = if (result == .i64) octet else try h.emit(.{ .op = .convert, .ty = .i64, .a = octet });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = wide });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    return module;
}

fn emitHand(a: std.mem.Allocator, module: *const ir.Module) ![]const u8 {
    const context: u8 = 0;
    return emitter.emitModule(a, module, .{ .locator = .{ .context = &context, .locate = location }, .source_path = "hand.selka", .main = .{ .parameters = &.{} } });
}

// spec-case: NEW-CORE-LLVM-1
test "only the builder's exact owned text byte helper is lowered to a load" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    const exact = try emitHand(a, &(try strByteModule(a, .i64)));
    try std.testing.expect(std.mem.indexOf(u8, exact, "call i64 @myl_core_ir_str_byte") == null);
    try std.testing.expect(std.mem.indexOf(u8, exact, " = zext i8 ") != null);
    // The same name with another result type is not the builder's helper and keeps its call.
    const other = try emitHand(a, &(try strByteModule(a, .u64)));
    try std.testing.expect(std.mem.indexOf(u8, other, "call i64 @myl_core_ir_str_byte") != null);
    try std.testing.expect(std.mem.indexOf(u8, other, " = zext i8 ") == null);
}

// spec-case: NEW-CORE-LLVM-1
test "only the exact runtime span adapter is lowered to its identity" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var runtime = try spanModule(a, 5, false, false, false);
    runtime.functions.items[runtime.entry].signature.params = &.{};
    const lowered = try emitHand(a, &runtime);
    try std.testing.expect(std.mem.indexOf(u8, lowered, "call i64 @myl_core_span_bytes_index_offset") == null);
    try std.testing.expect(std.mem.indexOf(u8, lowered, " = add i64 5, 0") != null);
    var foreign = try spanModule(a, 5, false, false, false);
    foreign.functions.items[foreign.entry].signature.params = &.{};
    foreign.functions.items[0].signature.linkage = .extern_c;
    const kept = try emitHand(a, &foreign);
    try std.testing.expect(std.mem.indexOf(u8, kept, "call i64 @myl_core_span_bytes_index_offset") != null);
}

const text_program =
    \\func owned_at(own text: str, index: int) -> int:
    \\    return text[index]
    \\func main(args: str[], out: Stream) -> int:
    \\    match parse_int(args[0]):
    \\        case Some(index):
    \\            print(out, owned_at(copy("h\u00e9llo"), index))
    \\            return 0
    \\        case None:
    \\            return 2
;

fn nativeTextIndices(a: std.mem.Allocator, root: []const u8, mode: []const []const u8) !void {
    const source = try std.fmt.allocPrint(a, "{s}/text_index.selka", .{root});
    const output = try std.fmt.allocPrint(a, "{s}/text_index", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", output, "--cache-dir", root });
    try argv.appendSlice(a, mode);
    try support.requireReleaseArgs(mode);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const cases = [_]struct { index: []const u8, output: []const u8 }{
        .{ .index = "0", .output = "104\n" },        .{ .index = "1", .output = "195\n" },        .{ .index = "5", .output = "111\n" },
        .{ .index = "6", .output = "" },             .{ .index = "-1", .output = "" },            .{ .index = "-7", .output = "" },
        .{ .index = signed_max_text, .output = "" }, .{ .index = signed_min_text, .output = "" },
    };
    for (cases) |case| {
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ output, case.index }, .environ_map = &environment });
        try std.testing.expect(ran.term == .exited);
        try std.testing.expectEqualStrings(case.output, ran.stdout);
        if (case.output.len != 0) {
            try std.testing.expectEqual(@as(u8, 0), ran.term.exited);
            try std.testing.expectEqualStrings("", ran.stderr);
            continue;
        }
        try std.testing.expectEqual(@as(u8, 1), ran.term.exited);
        const bounds = try std.fmt.allocPrint(a, "error[R_TEXT_BOUNDS]: native execution failed (index {s}, length 6)", .{case.index});
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, bounds) != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "leak") == null);
    }
}

// spec-case: NEW-CORE-LLVM-1
test "an owned text read traps on past-the-end negative and extreme indexes in every mode" {
    var state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer state.deinit();
    const a = state.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "text_index.selka", .data = text_program });
    for ([_][]const []const u8{ &.{}, &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| try nativeTextIndices(a, root, mode);
}

//! Tests of the in-process LLVM translator (LLVM-ZIG-1): the retired Python
//! adapter's translations replayed byte for byte, refusals, the runtime
//! helper registry, float and integer literal spellings, and the clang command
//! the build derives from `zig cc -###`.
const std = @import("std");
const bundled = @import("qbe_build_assets");
const llvm = @import("qbe_build_llvm.zig");
const emit = @import("qbe_build_llvm_emit.zig");
const il = @import("qbe_build_llvm_il.zig");
const compile = @import("qbe_build_llvm_compile.zig");

/// The golden corpus `experiments/llvm-zig-20260924/pack_fixtures.py` wrote
/// from the retired adapter: its own unit tests' translations plus units of
/// real `--release` builds.
const corpus_path = "test/fixtures/llvm-translate/adapter-corpus.json";

/// The runtime registry every build reads: the bundled runtime tree's top level.
fn bundledTable(arena: std.mem.Allocator) !llvm.RuntimeTable {
    var sources: std.ArrayList(llvm.RuntimeSource) = .empty;
    for (bundled.files) |file| {
        if (std.mem.indexOfScalar(u8, file.path, '/') != null) continue;
        try sources.append(arena, .{ .name = file.path, .bytes = file.bytes });
    }
    std.mem.sort(llvm.RuntimeSource, sources.items, {}, struct {
        fn less(_: void, left: llvm.RuntimeSource, right: llvm.RuntimeSource) bool {
            return std.mem.lessThan(u8, left.name, right.name);
        }
    }.less);
    return llvm.RuntimeTable.read(arena, sources.items);
}

/// How a replay of the corpus went: cases whose IR matched, cases both sides
/// refused, and the name of the first case that did neither.
const Replay = struct { identical: usize = 0, refused: usize = 0, cases: usize = 0, first_difference: []const u8 = "" };

fn replayCorpus(arena: std.mem.Allocator) !Replay {
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, corpus_path, arena, .limited(16 << 20));
    const cases = try std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
    const table = try bundledTable(arena);
    var replay: Replay = .{ .cases = cases.array.items.len };
    for (cases.array.items) |case| {
        const produced = translateCase(arena, case, &table) catch |err| switch (err) {
            error.TranslationFailed => null,
            else => return err,
        };
        const expected = case.object.get("expected").?;
        const same = if (produced) |ir| expected == .string and std.mem.eql(u8, ir, expected.string) else expected == .null;
        if (same and produced == null) replay.refused += 1 else if (same) replay.identical += 1;
        if (!same and replay.first_difference.len == 0) replay.first_difference = case.object.get("name").?.string;
    }
    return replay;
}

fn translateCase(arena: std.mem.Allocator, case: std.json.Value, table: *const llvm.RuntimeTable) !?[]const u8 {
    const fields = case.object;
    var signatures: llvm.Signatures = .empty;
    var entries = fields.get("signatures").?.object.iterator();
    while (entries.next()) |entry| {
        const parameters = entry.value_ptr.object.get("parameters").?.array.items;
        const letters = try arena.alloc([]const u8, parameters.len);
        for (parameters, letters) |parameter, *letter| letter.* = parameter.string;
        const result = entry.value_ptr.object.get("result").?;
        try signatures.put(arena, entry.key_ptr.*, .{ .parameters = letters, .result = if (result == .string) result.string else null });
    }
    const switches = fields.get("switches").?.object;
    const options: llvm.Options = .{
        .signatures = &signatures,
        .runtime = table,
        .target_cpu = fields.get("target_cpu").?.string,
        .target_features = fields.get("target_features").?.string,
        .alias = on(switches, "MYLANG_QBE_LLVM_ALIAS"),
        .element_gep = on(switches, "MYLANG_QBE_LLVM_ELEMENT_GEP"),
        .sticky = on(switches, "MYLANG_QBE_LLVM_STICKY"),
    };
    var diagnostic: llvm.Diagnostic = .{ .unit = fields.get("name").?.string };
    const translated = try llvm.translate(arena, fields.get("ssa").?.string, options, &diagnostic);
    return translated;
}

fn on(switches: std.json.ObjectMap, name: []const u8) bool {
    const value = switches.get(name) orelse return true;
    return !std.mem.eql(u8, value.string, "0");
}

// spec: LLVM-ZIG-1
test "the in-process translator reproduces the retired Python adapter's IR for its whole golden corpus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const replay = try replayCorpus(arena.allocator());
    // Every case matched byte for byte, or was refused by both translators.
    try std.testing.expectEqualStrings("", replay.first_difference);
    try std.testing.expectEqual(replay.cases, replay.identical + replay.refused);
    try std.testing.expect(replay.identical >= 100);
    try std.testing.expect(replay.refused >= 1);
}

const refused_unit =
    \\export function l $myl_f_bad(l %ctx) {
    \\@start
    \\ %v =l vaarg %ctx
    \\ ret %v
    \\}
;

// spec-case: LLVM-ZIG-1
test "a construct the translator does not know is refused with a diagnostic naming the unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures: llvm.Signatures = .empty;
    const table: llvm.RuntimeTable = .{};
    var diagnostic: llvm.Diagnostic = .{ .unit = "bad-unit" };
    const options: llvm.Options = .{ .signatures = &signatures, .runtime = &table };
    try std.testing.expectError(error.TranslationFailed, llvm.translate(a, refused_unit, options, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bad-unit") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "unsupported opcode") != null);
    // An undeclared runtime helper is refused rather than declared from its call site.
    const helper = "export function l $f(l %ctx) {\n@start\n %v =l call $myl_qbe_no_such_helper(l %ctx)\n ret %v\n}\n";
    diagnostic = .{ .unit = "helper-unit" };
    try std.testing.expectError(error.TranslationFailed, llvm.translate(a, helper, options, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "has no checked C signature") != null);
}

// spec-case: LLVM-ZIG-1
test "the runtime registry reads helpers from headers and Zig exports and refuses unknown types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sources = [_]llvm.RuntimeSource{
        .{ .name = "a.h", .bytes = "/* skipped(int x); */\nint32_t myl_native_sum(const void *heap,\n    int64_t count); // tail\nuint8_t myl_qbe_byte(int x);\nvoid *myl_qbe_where(void);\n" },
        .{ .name = "b.zig", .bytes = "comptime {\n    @export(&twice, .{ .name = \"myl_native_twice\" });\n}\npub fn twice(heap: ?*anyopaque, value: u32) callconv(.c) f64 {\n    return 0;\n}\n" },
    };
    const table = try llvm.RuntimeTable.read(arena.allocator(), &sources);
    const sum = table.signature("myl_native_sum").?;
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{ "ptr", "i64" }), sum.parameters);
    try std.testing.expectEqualStrings("i32", sum.result);
    try std.testing.expectEqualStrings("ptr", table.signature("myl_qbe_where").?.result);
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{ "ptr", "i32" }), table.signature("myl_native_twice").?.parameters);
    try std.testing.expectEqualStrings("double", table.signature("myl_native_twice").?.result);
    // `uint8_t` is not a type the registry spells, so the helper stays unknown.
    try std.testing.expectEqual(@as(?llvm.RuntimeSignature, null), table.signature("myl_qbe_byte"));
    // The curated table and the generated renderer shape need no source at all.
    try std.testing.expectEqualStrings("void", table.signature("myl_r_anything").?.result);
    try std.testing.expectEqualStrings("ptr", table.signature("myl_qbe_heap").?.result);
}

// spec-case: LLVM-ZIG-1
test "float and integer literals are spelled as the adapter's Python spelled them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("1.5", try emit.pythonRepr(a, 1.5));
    try std.testing.expectEqualStrings("100.0", try emit.pythonRepr(a, 100.0));
    try std.testing.expectEqualStrings("-0.0", try emit.pythonRepr(a, -0.0));
    try std.testing.expectEqualStrings("0.0001", try emit.pythonRepr(a, 0.0001));
    try std.testing.expectEqualStrings("1e-05", try emit.pythonRepr(a, 0.00001));
    try std.testing.expectEqualStrings("1234567890123456.0", try emit.pythonRepr(a, 1234567890123456.0));
    try std.testing.expectEqualStrings("1e+16", try emit.pythonRepr(a, 1e16));
    try std.testing.expectEqualStrings("1.2345678901234568e+16", try emit.pythonRepr(a, 12345678901234567.0));
    try std.testing.expectEqual(@as(?u64, 31), il.pythonInt("0x1F"));
    try std.testing.expectEqual(@as(?u64, 1000), il.pythonInt("1_000"));
    try std.testing.expectEqual(@as(?u64, std.math.maxInt(u64)), il.pythonInt("-1"));
    try std.testing.expectEqual(@as(?u64, null), il.pythonInt("010"));
    try std.testing.expectEqual(@as(?u64, 0), il.pythonInt("00"));
}

// spec-case: LLVM-ZIG-1
test "the clang command of an LLVM unit is the cc1 line of zig cc's own listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const listing =
        \\clang version 22.1.8
        \\ (in-process)
        \\ "/opt/zig/zig" "-cc1" "-triple" "x86_64-unknown-linux-gnu" "-O2" "-emit-llvm-bc" "-flto=full" "-main-file-name" "object.o.ll" "-D" "A=\"b\\c\"" "-o" "/w/object.o" "-x" "ir" "/w/object.o.ll"
        \\
    ;
    const argv = (try compile.commandLine(arena.allocator(), .{ .zig = "/tools/zig", .front = "-cc1" }, listing)).?;
    try std.testing.expectEqualStrings("/tools/zig", argv[0]);
    try std.testing.expectEqualStrings("clang", argv[1]);
    try std.testing.expectEqualStrings("-cc1", argv[2]);
    try std.testing.expectEqualStrings("A=\"b\\c\"", argv[11]);
    try std.testing.expectEqualStrings("/w/object.o.ll", argv[argv.len - 1]);
    try std.testing.expectEqual(@as(?[]const []const u8, null), try compile.commandLine(arena.allocator(), .{ .zig = "/tools/zig", .front = "-cc1" }, "no command here\n"));
}

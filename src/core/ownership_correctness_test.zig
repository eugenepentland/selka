//! Recursive equality borrows physical values without allocating owning wrappers.
const std = @import("std");
const report = std.debug.print;
const ir = @import("ir.zig");
const equality = @import("build_equality.zig");
const canonical = @import("canonical_ir.zig");
const llvm = @import("emit_llvm.zig");
const verify = @import("verify_ir.zig");
const cost = @import("cost.zig");
const markers = @import("marker_validation.zig");

fn helper(a: std.mem.Allocator, ty: ir.Type) !ir.Function {
    return .{ .name = try @import("test_support.zig").fixtureName(a, equality.prefix, ty), .signature = .{ .params = try a.dupe(ir.Type, &.{ ty, ty }), .ret = .bool, .linkage = .runtime_c } };
}

fn rejects(a: std.mem.Allocator, module: *ir.Module, bad: ir.Function) !void {
    module.functions.items[0] = bad;
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, module));
    try std.testing.expectError(error.UnsupportedInstruction, llvm.emitModule(a, module, .{ .locator = locator, .source_path = "equality.selka", .main = .{} }));
    var failure: verify.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, module, &failure));
}

fn rejectsOwnership(a: std.mem.Allocator, module: *ir.Module, good: ir.Function) !void {
    inline for (.{ "owned", "consumes", "views" }) |field| {
        var bad = good;
        @field(bad.signature.passing, field) = 1;
        try rejects(a, module, bad);
    }
}

// spec-case: VALUE-EQUALITY-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership correctness equality validates exact borrowed declarations and descriptor graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ty = try module.intern(a, .{ .record = &.{ .str, .i64 } });
    const good = try helper(a, ty);
    try module.functions.append(a, good);
    try equality.validateModule(a, &module);
    try std.testing.expect(try equality.declaration(&module, &good));
    for ([_][]const u8{ equality.prefix, equality.prefix ++ "00", equality.prefix ++ "-1", equality.prefix ++ "999999999999999", equality.prefix ++ "16_more", equality.prefix ++ "99999" }) |name| {
        var bad = good;
        bad.name = name;
        try rejects(a, &module, bad);
    }
    try rejectsOwnership(a, &module, good);
    var bad = good;
    bad.signature.linkage = .extern_c;
    try rejects(a, &module, bad);
    bad = good;
    bad.signature.ret = .i64;
    try rejects(a, &module, bad);
    bad = good;
    bad.signature.params = &.{ ty, .i64 };
    try rejects(a, &module, bad);
    bad = good;
    bad.span = 1;
    try rejects(a, &module, bad);
    bad = good;
    try bad.insts.append(a, .{ .op = .ret, .ty = .void });
    try rejects(a, &module, bad);
    bad = good;
    try bad.blocks.append(a, .{});
    try rejects(a, &module, bad);
    bad = good;
    try bad.extra.append(a, .none);
    try rejects(a, &module, bad);
    bad = good;
    try bad.loops.append(a, .{ .id = 0, .header = @fromBackingInt(0), .body = @fromBackingInt(0), .latch = @fromBackingInt(0), .exit = @fromBackingInt(0) });
    try rejects(a, &module, bad);
    module.functions.items[0] = good;
    try std.testing.expectError(error.UnsupportedInstruction, equality.reference(&module, .{ .op = .func_ref, .ty = ty, .data = 0 }));
    module.compounds.items[0] = .{ .record = &.{.str_view} };
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &module));
    module.compounds.items[0] = .{ .record = &.{ty} };
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &module));
    module.compounds.items[0] = .{ .record = &.{@fromBackingInt(99999)} };
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &module));
}

// spec-case: VALUE-EQUALITY-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership correctness equality rejects physical layout overflow before descriptor sizing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ty = try module.intern(a, .{ .array = .{ .elem = .u64, .n = std.math.maxInt(u32) } });
    const good = try helper(a, ty);
    try module.functions.append(a, good);
    try rejects(a, &module, good);
    module.compounds.items[0] = .{ .array = .{ .elem = .u64, .n = 0 } };
    try equality.validateModule(a, &module);
    module.compounds.items[0] = .{ .array = .{ .elem = .u8, .n = std.math.maxInt(u32) - 7 } };
    try equality.validateModule(a, &module);
    const record = try module.intern(a, .{ .record = &.{ ty, .u64 } });
    module.functions.items[0] = try helper(a, record);
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &module));
    module.compounds.items[1] = .{ .@"union" = &.{ ty, .void } };
    try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &module));
}

fn locate(_: *const anyopaque, _: u32) llvm.Location {
    return .{ .path = "equality.selka", .line = 1, .column = 1 };
}
const context: u8 = 0;
const locator: llvm.Locator = .{ .context = &context, .locate = locate };

// spec-case: NEW-CORE-TEST-KEYS-1
test "ownership correctness equality canonical identities ignore relocated recursive type indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t0: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const t1: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    const t2: ir.Type = @fromBackingInt(ir.Type.first_compound + 2);
    var first: ir.Module = .{};
    try first.compounds.appendSlice(a, &.{ .{ .@"union" = &.{ .str, t1 } }, .{ .box = t0 } });
    try first.functions.append(a, try helper(a, t0));
    var second: ir.Module = .{};
    try second.compounds.appendSlice(a, &.{ .{ .list = .i32 }, .{ .@"union" = &.{ .str, t2 } }, .{ .box = t1 } });
    try second.functions.append(a, try helper(a, t1));
    var one = try canonical.Canon.prepare(a, &first, locator);
    var two = try canonical.Canon.prepare(a, &second, locator);
    const expected = try one.callee(0);
    try std.testing.expectEqualSlices(u8, &expected, &try two.callee(0));
    second.compounds.items[1] = .{ .@"union" = &.{ .i64, t2 } };
    var different = try canonical.Canon.prepare(a, &second, locator);
    try std.testing.expect(!std.mem.eql(u8, &expected, &try different.callee(0)));
    second.functions.items[0].signature.passing.owned = 1;
    try std.testing.expectError(error.UnknownMetadata, canonical.Canon.prepare(a, &second, locator));
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: FRONTEND-CORE-NOALLOC-1
test "ownership correctness equality rejects malformed restored calls and preserves native allocation cost" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ty = try module.intern(a, .{ .record = &.{ .str, .i64 } });
    try module.functions.append(a, try helper(a, ty));
    var function: ir.Function = .{ .name = "comparison", .signature = .{ .params = &.{ty}, .ret = .bool } };
    try function.insts.append(a, .{ .op = .param, .ty = ty });
    try function.extra.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(0) });
    const good: ir.Inst = .{ .op = .call, .ty = .bool, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 2 }).pack() };
    try std.testing.expect(try equality.call(&module, &function, good));
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, good));
    var bad = good;
    bad.data = (ir.ExtraSlice{ .start = 1, .len = 2 }).pack();
    try std.testing.expectError(error.UnsupportedInstruction, equality.call(&module, &function, bad));
    bad = good;
    bad.ty = .i64;
    try std.testing.expectError(error.UnsupportedInstruction, equality.call(&module, &function, bad));
    function.extra.items[1] = @fromBackingInt(1234);
    try function.insts.append(a, good);
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(a, &module, &function));
    module.functions.items[0].signature.passing.owned = 1;
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &function, good));
}

const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const source =
    \\record Node:
    \\    text: str
    \\    next: Node?
    \\enum Tree:
    \\    leaf(value: float)
    \\    branch(left: Tree, right: Tree)
    \\func chain(n: int) -> Node?:
    \\    mut result: Node? = None
    \\    for i in range(n):
    \\        result = Some(Node(text="value-" + str(i), next=own result))
    \\    return result
    \\func compare(left: Node?, right: Node?) -> bool:
    \\    return left == right
    \\func main(out: Stream) -> int:
    \\    mut left = chain(300)
    \\    mut right = chain(300)
    \\    const different = chain(299)
    \\    assert compare(left, right) and compare(left, left)
    \\    assert not compare(left, different)
    \\    const rows = [copy(left), copy(different)]
    \\    assert rows[0] == right and rows[1] == different
    \\    const mapping = {"one": copy(left), "two": copy(different)}
    \\    const reordered = {"two": copy(different), "one": copy(right)}
    \\    assert mapping == reordered
    \\    mut nan = Tree.leaf(value=0.0 / 0.0)
    \\    mut negative = Tree.leaf(value=-0.0)
    \\    mut positive = Tree.leaf(value=0.0)
    \\    for i in range(20):
    \\        nan = Tree.branch(left=own nan, right=Tree.leaf(value=1.0))
    \\        negative = Tree.branch(left=own negative, right=Tree.leaf(value=1.0))
    \\        positive = Tree.branch(left=own positive, right=Tree.leaf(value=1.0))
    \\    assert nan != nan and negative == positive
    \\    left = None
    \\    assert right == rows[0] and mapping["one"] == right
    \\    right = None
    \\    assert mapping["one"] == rows[0]
    \\    print(out, "equality passed")
    \\    return 0
;

fn count(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

fn inspect(a: std.mem.Allocator, binary: []const u8, llvm_path: []const u8) !void {
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("SELKA_COUNTERS", path);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("equality run: {s}{s}\n", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("equality passed\n", ran.stdout);
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)), .{});
    try std.testing.expectEqual(@as(i64, 0), count(counts, &.{ "totals", "live_bytes_at_exit" }));
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
        try std.testing.expect(counts.object.get("totals").?.object.get(name) == null);
    for ([_][]const u8{ "retain", "release", "release_unique", "unique_test" }) |name|
        try std.testing.expect(counts.object.get("kinds").?.object.get(name) == null);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm_path, a, .limited(16 << 20));
    try std.testing.expect(zero.emittedClean(text));
    try std.testing.expect(std.mem.indexOf(u8, text, "call zeroext i1 @myl_core_values_equal") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, equality.prefix) == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_equal_") == null);
    const symbols = try std.process.run(a, std.testing.io, .{ .argv = &.{ "nm", binary } });
    try std.testing.expect(symbols.term == .exited and symbols.term.exited == 0);
    for ([_][]const u8{ "myl_core_retain", "myl_core_release", "myl_core_share", "count_retain", "count_release", "count_is_unique" }) |legacy|
        try std.testing.expect(std.mem.indexOf(u8, symbols.stdout, legacy) == null);
}

// spec-case: VALUE-EQUALITY-1
// spec-case: NEW-CORE-S3-VALUES-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership correctness equality borrows recursive operands with independent cleanup in five modes and AddressSanitizer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "equality.selka", .data = source });
    const input = try std.fs.path.join(a, &.{ root, "equality.selka" });
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    const modes = [_][]const []const u8{ &.{"--unoptimized"}, &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" }, &.{"--release"} };
    for (modes, 0..) |flags, index| {
        try support.requireReleaseArgs(flags);
        if (index == modes.len - 1) try environment.put("SELKA_CORE_SANITIZE", "address");
        const binary = try std.fmt.allocPrint(a, "{s}/equality-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", input, "-o", binary, "--cache-dir", root, "--counters", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (built.term != .exited or built.term.exited != 0) report("equality build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try inspect(a, binary, llvm_path);
    }
}

// spec-case: NEW-CORE-TEST-KEYS-1
test "ownership correctness equality cyclic type keys do not depend on prior canonical queries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const record: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const box: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    var module: ir.Module = .{};
    try module.compounds.appendSlice(a, &.{ .{ .record = &.{ .i64, box } }, .{ .box = record } });
    var first = try canonical.Canon.prepare(a, &module, locator);
    _ = try first.typeDigest(record);
    const after = try first.typeDigest(box);
    var fresh = try canonical.Canon.prepare(a, &module, locator);
    const before = try fresh.typeDigest(box);
    try std.testing.expectEqualSlices(u8, &before, &after);
}

// spec: ASAN-BUILD-1
test "ownership correctness address instrumentation covers definitions and stays idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\declare ptr @external(ptr)
        \\define internal fastcc { i64, ptr } @task(ptr %env) nounwind !dbg !12 {
        \\  ret { i64, ptr } zeroinitializer
        \\}
        \\define i32 @main() sanitize_address {
        \\  ret i32 0
        \\}
    ;
    const sanitizer = @import("sanitize_llvm.zig");
    const emitted = try sanitizer.address(arena.allocator(), input);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, emitted, " sanitize_address"));
    try std.testing.expect(std.mem.indexOf(u8, emitted, "nounwind sanitize_address !dbg !12 {") != null);
    try std.testing.expect(std.mem.startsWith(u8, emitted, "declare ptr @external(ptr)\n"));
    try std.testing.expectEqualStrings(emitted, try sanitizer.address(arena.allocator(), emitted));
}

fn refusesBorrow(gpa: std.mem.Allocator, source_text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    // A fixture that imports a standard module is checked as an embedded project.
    const checked = try @import("test_support.zig").checkSource(a, source_text);
    if (!checked.passed) {
        try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
        return;
    }
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(@import("selka").ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
}

fn refusesCore(gpa: std.mem.Allocator, body: []const u8, expected: @import("selka").ownership_rules.Refusal) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const source_text = try std.mem.concat(a, u8, &.{ resource_schema, "\n", body, "\nfunc main() -> int:\n    return 0\n" });
    const checked = try @import("test_support.zig").checkSource(a, source_text);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
}

// spec: OWNERSHIP-ADVERSARIAL-1
test "ownership correctness refuses borrowed index field and callback escapes" {
    // The direct indexed return is a valid borrow; an owned callback cannot carry it.
    try refusesBorrow(std.testing.allocator,
        \\func escaped(values: int[][]) -> int[] from values:
        \\    return values[0]
        \\func main() -> int:
        \\    const callback: func(int[][]) -> int[] = escaped
        \\    return len(callback([[1]]))
    , "E_VIEW_FUNCTION_VALUE");
}

// spec-case: OWNERSHIP-ADVERSARIAL-1
// spec-case: ASAN-BUILD-1
test "ownership correctness copied borrow adversaries pass leakcheck and AddressSanitizer" {
    try nativeAdversaries(std.testing.allocator, "test/core/ownership_correctness.selka", 3);
}

fn nativeAdversaries(gpa: std.mem.Allocator, fixture: []const u8, expected: i64) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    for ([_]bool{ false, true }) |address| {
        if (address) try environment.put("SELKA_CORE_SANITIZE", "address");
        const argv = [_][]const u8{ options.corePath(), "test", fixture, "--release", "--force", "--json", "--jobs", "1", "--max-memory", "0", "--cache-dir", root };
        try support.requireReleaseArgs(&argv);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("borrow adversaries (ASan={}): {s}{s}\n", .{ address, ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        const result = try std.json.parseFromSliceLeaky(std.json.Value, a, ran.stdout, .{});
        try std.testing.expectEqual(expected, result.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), result.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), result.object.get("unsupported").?.integer);
    }
}

// spec-case: ASAN-BUILD-1
test "ownership correctness AddressSanitizer catches an instrumented foreign overflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "asan_control.selka", .data =
        \\extern func asan_fault(host: Host, index: int) -> int
        \\func main(host: Host) -> int:
        \\    return asan_fault(host, 8)
    });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "asan_control.c", .data =
        \\#include <stdint.h>
        \\#include <stdlib.h>
        \\int64_t asan_fault(int64_t index) {
        \\    volatile unsigned char *value = malloc(1);
        \\    value[index] = 42;
        \\    free((void *)value);
        \\    return 0;
        \\}
    });
    const input = try std.fs.path.join(a, &.{ root, "asan_control.selka" });
    const foreign = try std.fs.path.join(a, &.{ root, "asan_control.c" });
    const binary = try std.fs.path.join(a, &.{ root, "asan_control" });
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_SANITIZE", "address");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    try support.requireRelease();
    const built = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "build", input, "--release", "--link", foreign, "-o", binary, "--cache-dir", root }, .environ_map = &environment });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited != 0);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "AddressSanitizer: heap-buffer-overflow") != null);
}

// spec-case: OWNERSHIP-ADVERSARIAL-1
test "ownership correctness scalar argument loans still refuse mutation and borrowed escape" {
    try refusesBorrow(std.testing.allocator,
        \\func mutate(mut values: int[]) -> int:
        \\    append(mut values, 9)
        \\    return 0
        \\func put(mut values: int[], index: int) -> Unit:
        \\    values[index] = 7
        \\func main() -> int:
        \\    mut values = [1]
        \\    put(mut values, mutate(mut values))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func put(mut values: int[], borrowed: int[]) -> Unit:
        \\    append(mut values, len(borrowed))
        \\func main() -> int:
        \\    mut values = [1]
        \\    put(mut values, values)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func mutate(mut values: int[]) -> int:
        \\    append(mut values, 9)
        \\    return 0
        \\func put(mut values: int[], index: int) -> Unit:
        \\    values[index] = 7
        \\func main() -> int:
        \\    const callback: func(mut int[]) -> int = mutate
        \\    mut values = [1]
        \\    put(mut values, callback(mut values))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: ASAN-BUILD-1
test "ownership correctness address runtime changes only configured tool identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "owned identity fixture" });
    try directory.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    var environment = std.process.Environ.Map.init(a);
    defer environment.deinit();
    const identity = @import("tool_identity.zig");
    const request: identity.Request = .{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = try std.fs.path.join(a, &.{ root, "zig" }), .cache = root };
    const ordinary = try identity.capture(request);
    try environment.put("SELKA_CORE_SANITIZE", "thread");
    const thread = try identity.capture(request);
    try std.testing.expectEqual(ordinary.digest, thread.digest);
    try std.testing.expectEqual(ordinary.generation, thread.generation);
    try environment.put("SELKA_CORE_SANITIZE", "address");
    try std.testing.expect(!try identity.unchanged(request, ordinary));
    const address = try identity.capture(request);
    try std.testing.expectEqual(ordinary.inputs + 1, address.inputs);
    try std.testing.expect(!std.mem.eql(u8, &ordinary.digest, &address.digest));
    try std.testing.expect(!std.mem.eql(u8, &ordinary.generation, &address.generation));
    try std.testing.expect(try identity.unchanged(request, address));
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    try std.testing.expect(!try identity.unchanged(request, address));
    const restored = try identity.capture(request);
    try std.testing.expectEqual(ordinary.digest, restored.digest);
    try std.testing.expectEqual(ordinary.generation, restored.generation);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness disjoint argument proof rejects same dynamic prefix and mutated paths" {
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], mut rows[0])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func index() -> int:
        \\    return 1
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], mut rows[index()])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut whole: int[][], mut part: int[]) -> Unit:
        \\    append(mut whole, [7])
        \\    append(mut part, 9)
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows, mut rows[0])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\import lists
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func select(mut rows: int[][]) -> int:
        \\    lists.clear(mut rows)
        \\    return 1
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], mut rows[select(mut rows)])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: OWNERSHIP-CONTRACT-1
// spec-case: ASAN-BUILD-1
test "ownership correctness scalar arguments finish before mutation under leakcheck and AddressSanitizer" {
    try nativeAdversaries(std.testing.allocator, "test/core/ownership_argument_reads.selka", 3);
}

const resource_schema =
    \\resource File: filesystem
    \\record Failure:
    \\    code: int
    \\    resource: File
    \\result Finish:
    \\    ok: bool,
    \\    err: Failure
;

fn refusesResource(gpa: std.mem.Allocator, body: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const source_text = try std.mem.concat(a, u8, &.{ resource_schema, "\n", body, "\nfunc main() -> int:\n    return 0\n" });
    try refusesBorrow(a, source_text, code);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness affine extraction consumes its carrier and rejects aliases and borrowed iteration" {
    try refusesCore(std.testing.allocator,
        \\func rejected(own failure: Failure) -> Finish:
        \\    _ = complete_resource[Finish](own failure.resource)
        \\    return complete_resource[Finish](own failure.resource)
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
    try refusesCore(std.testing.allocator,
        \\func rejected(own failure: Failure) -> Finish:
        \\    const alias = own failure
        \\    _ = complete_resource[Finish](own alias.resource)
        \\    return complete_resource[Finish](own failure.resource)
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
    try refusesResource(std.testing.allocator,
        \\func rejected(failures: Failure[]) -> Unit:
        \\    for failure in failures:
        \\        _ = complete_resource[Finish](own failure.resource)
    , "E_GENERIC_REQUIREMENT");
    // O4 drops the independent managed sibling when the selected resource leaves its carrier.
    try acceptsOwnership(std.testing.allocator, resource_schema ++ "\n" ++
        \\record Outer:
        \\    failure: Failure
        \\    values: str[]
        \\func accepted(own owner: Outer) -> Finish:
        \\    return complete_resource[Finish](own owner.failure.resource)
        \\func main() -> int:
        \\    return 0
    );
    try refusesCore(std.testing.allocator,
        \\record Outer:
        \\    failure: Failure
        \\    values: str[]
        \\func rejected(own owner: Outer) -> int:
        \\    _ = complete_resource[Finish](own owner.failure.resource)
        \\    return len(owner.values)
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 });
}

// spec-case: OWNERSHIP-CONTRACT-1
// spec-case: ASAN-BUILD-1
test "ownership correctness affine resource field cleanup passes leakcheck and AddressSanitizer" {
    try nativeAdversaries(std.testing.allocator, "test/core/ownership_affine_arguments.selka", 2);
}

// spec-case: OWNERSHIP-CONTRACT-1
// spec-case: ASAN-BUILD-1
test "ownership correctness disjoint mutable arguments pass leakcheck and AddressSanitizer" {
    try nativeAdversaries(std.testing.allocator, "test/core/ownership_disjoint_arguments.selka", 15);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness disjoint argument proof rejects borrowed carriers and read siblings that may be the element" {
    // A read element at a different literal index is as disjoint as a mutable one (G3).
    try acceptsOwnership(std.testing.allocator,
        \\func pair(mut left: int[], right: int[]) -> Unit:
        \\    append(mut left, len(right))
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], rows[1])
        \\    pair(mut rows[1], rows[0])
        \\    return 0
    );
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], right: int[]) -> Unit:
        \\    append(mut left, len(right))
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows[0], rows[0])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], right: int[]) -> Unit:
        \\    append(mut left, len(right))
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    const at = 1
        \\    pair(mut rows[0], rows[at])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut whole: int[][], part: int[]) -> Unit:
        \\    append(mut whole, copy(part))
        \\func main() -> int:
        \\    mut rows = [[1], [2]]
        \\    pair(mut rows, rows[1])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\record Item:
        \\    tags: int[]
        \\func pair(mut tags: int[], other: Item) -> Unit:
        \\    append(mut tags, len(other.tags))
        \\func main() -> int:
        \\    mut items = [Item(tags=[1]), Item(tags=[2])]
        \\    pair(mut items[0].tags, items[1])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func rejected(rows: int[][]) -> Unit:
        \\    pair(mut rows[0], mut rows[1])
        \\func main() -> int:
        \\    rejected([[1], [2]])
        \\    return 0
    , "E_IMMUTABLE");
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness disjoint argument proof keeps non-list families refused" {
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut rows = FixedArray[int[], 2]([[1], [2]])
        \\    pair(mut rows[0], mut rows[1])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refusesBorrow(std.testing.allocator,
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut rows: dict[int, int[]] = {0: [1], 1: [2]}
        \\    pair(mut rows[0], mut rows[1])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    // Distinct literal elements of a list held in a record field are disjoint, as the elements of a local list are (G3);
    // the same element, and a field inside an element, are not.
    try acceptsOwnership(std.testing.allocator,
        \\record Owner:
        \\    rows: int[][]
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut owner = Owner(rows=[[1], [2]])
        \\    pair(mut owner.rows[0], mut owner.rows[1])
        \\    return 0
    );
    try refusesBorrow(std.testing.allocator,
        \\record Owner:
        \\    rows: int[][]
        \\func pair(mut left: int[], mut right: int[]) -> Unit:
        \\    append(mut left, 7)
        \\    append(mut right, 9)
        \\func main() -> int:
        \\    mut owner = Owner(rows=[[1], [2]])
        \\    pair(mut owner.rows[0], mut owner.rows[0])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

/// Check a program that must be accepted by the front end and the ownership
/// contract, returning nothing.
fn acceptsOwnership(gpa: std.mem.Allocator, source_text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try @import("test_support.zig").checkSource(a, source_text);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try ownership.check(a, checked.program.?, &failure);
}

/// The first ownership refusal of a program that checks, with its message.
fn refusesBorrowWithMessage(gpa: std.mem.Allocator, source_text: []const u8, code: []const u8, wanted: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try @import("test_support.zig").checkSource(a, source_text);
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, wanted) != null);
    try std.testing.expect(failure.repair == .own_parameter);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness own parameter takes its argument and refuses a later use" {
    try refusesBorrow(std.testing.allocator,
        \\record State:
        \\    keys: int[]
        \\func make(own keys: int[]) -> State:
        \\    return State(keys=own keys)
        \\func main() -> int:
        \\    mut samples = [1, 2]
        \\    const held = make(own samples)
        \\    samples[0] = 3
        \\    return held.keys[0]
    , "E_SINGLE_OWNER_MOVED");
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness own parameter stores and returns its value without a copy" {
    const fixture =
        \\record State:
        \\    keys: int[]
        \\func make(own keys: int[]) -> State:
        \\    return State(keys=own keys)
        \\func counted(own keys: int[]) -> int:
        \\    return len(keys)
        \\func main() -> int:
        \\    mut samples = [1, 2]
        \\    const held = make(own samples)
        \\    mut other = [3]
        \\    return held.keys[0] + counted(own other)
    ;
    try acceptsOwnership(std.testing.allocator, fixture);
    // No copy is inserted where the old path copied: the own callee stores
    // `param0` itself, while the explicit-copy form runs `list_copy`.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try @import("test_support.zig").irText(a, fixture);
    try std.testing.expect(std.mem.indexOf(u8, text, "fn make") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_copy") == null);
    const copied = try @import("test_support.zig").irText(a,
        \\record State:
        \\    keys: int[]
        \\func make(keys: int[]) -> State:
        \\    return State(keys=copy(keys))
        \\func main() -> int:
        \\    mut samples = [1, 2]
        \\    return make(samples).keys[0]
    );
    try std.testing.expect(std.mem.indexOf(u8, copied, "list_copy") != null);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness a mut resource parameter is an exclusive borrow" {
    try acceptsOwnership(std.testing.allocator,
        \\import network
        \\record Holder:
        \\    listener: network.Listener
        \\func peek(mut listener: network.Listener) -> int:
        \\    match accept_resource[network.Accepted](listener):
        \\        case Ok(connection):
        \\            _ = own connection
        \\            return 0
        \\        case Err(code):
        \\            return 0 - code
        \\func accept_twice(mut listener: network.Listener) -> int:
        \\    const first = peek(mut listener)
        \\    const second = peek(mut listener)
        \\    return first + second
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.listen(scoped):
        \\            case ok(owned):
        \\                mut bound = own owned
        \\                const checked = accept_twice(mut bound)
        \\                const again = accept_twice(mut bound)
        \\                return checked + again
        \\            case err(code):
        \\                return 0 - code
    );
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness a mut resource that is stored asks to be own" {
    try refusesBorrowWithMessage(std.testing.allocator,
        \\import network
        \\record Holder:
        \\    listener: network.Listener
        \\func my_take(mut listener: network.Listener) -> Holder:
        \\    return Holder(listener=listener)
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.listen(scoped):
        \\            case ok(owned):
        \\                mut live = own owned
        \\                const held = my_take(mut live)
        \\                _ = held
        \\                return 0
        \\            case err(code):
        \\                return 0 - code
    , "E_SINGLE_OWNER_BORROW", "declare the parameter `own`");
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness an own resource parameter transfers the handle" {
    try acceptsOwnership(std.testing.allocator,
        \\import network
        \\record Holder:
        \\    listener: network.Listener
        \\func my_take(own listener: network.Listener) -> Holder:
        \\    return Holder(listener=own listener)
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.listen(scoped):
        \\            case ok(owned):
        \\                mut live = own owned
        \\                const held = my_take(own live)
        \\                _ = own held
        \\                return 0
        \\            case err(code):
        \\                return 0 - code
    );
}

const tree_schema =
    \\record Node:
    \\    kind: int
    \\    children: int[]
    \\record Tree:
    \\    nodes: Node[]
    \\    roots: int[]
    \\func add_child(mut node: Node, child: int):
    \\    append(mut node.children, child)
    \\func touch(mut tree: Tree):
    \\    append(mut tree.roots, 0)
    \\func link(mut parent: Node, child: Node):
    \\    append(mut parent.children, child.kind)
    \\
;

fn treeProgram(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ tree_schema, "func main() -> int:\n    mut tree = Tree(nodes=[Node(kind=1, children=[]), Node(kind=2, children=[])], roots=[0])\n", body, "\n    return 0\n" });
}

fn acceptsTree(gpa: std.mem.Allocator, body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    try acceptsOwnership(gpa, try treeProgram(arena.allocator(), body));
}

fn refusesTree(gpa: std.mem.Allocator, body: []const u8, rule: @import("selka").ownership_rules.Rule) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try @import("test_support.zig").checkSource(a, try treeProgram(a, body));
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness an iteration borrows the field it reads, so a sibling path may change (R7, G1)" {
    try acceptsTree(std.testing.allocator,
        \\    for root in tree.roots:
        \\        append(mut tree.nodes[root].children, 1)
        \\    for root in tree.roots:
        \\        add_child(mut tree.nodes[root], 1)
        \\    for node in tree.nodes:
        \\        append(mut tree.roots, node.kind)
        \\    for outer in tree.roots:
        \\        for inner in tree.roots:
        \\            add_child(mut tree.nodes[outer], inner)
        \\    for root in tree.roots:
        \\        if root > 0:
        \\            append(mut tree.nodes[root].children, 1)
        \\        else:
        \\            add_child(mut tree.nodes[0], 1)
    );
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness an iteration still borrows the field itself, a prefix of it and an element of it (R7, G1)" {
    // The iterated field.
    try refusesTree(std.testing.allocator,
        \\    for root in tree.roots:
        \\        append(mut tree.roots, root)
    , .R7);
    // A prefix: the record that holds it.
    try refusesTree(std.testing.allocator,
        \\    for root in tree.roots:
        \\        touch(mut tree)
    , .R7);
    // The iterated list's own elements, through a path and through a callee.
    try refusesTree(std.testing.allocator,
        \\    for node in tree.nodes:
        \\        append(mut tree.nodes[0].children, node.kind)
    , .R7);
    try refusesTree(std.testing.allocator,
        \\    for node in tree.nodes:
        \\        add_child(mut tree.nodes[0], node.kind)
    , .R7);
    // The loan survives a branch inside the loop and a nested loop over the same field.
    try refusesTree(std.testing.allocator,
        \\    for root in tree.roots:
        \\        if root > 0:
        \\            append(mut tree.nodes[root].children, 1)
        \\        append(mut tree.roots, root)
    , .R7);
    try refusesTree(std.testing.allocator,
        \\    for outer in tree.roots:
        \\        for inner in tree.roots:
        \\            append(mut tree.nodes[outer].children, inner)
        \\        append(mut tree.roots, outer)
    , .R7);
    // An element of an element list read as the iterated place: a sibling element keeps its field inside an element.
    try refusesTree(std.testing.allocator,
        \\    for child in tree.nodes[0].children:
        \\        add_child(mut tree.nodes[1], child)
    , .R7);
    try refusesTree(std.testing.allocator,
        \\    const at = 1
        \\    for child in tree.nodes[at].children:
        \\        append(mut tree.nodes[0].children, child)
    , .R7);
}

fn refusesElementArgument(gpa: std.mem.Allocator, body: []const u8, wanted: []const u8, unwanted: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try @import("test_support.zig").checkSource(a, try treeProgram(a, body));
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.M5, failure.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, wanted) != null);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, unwanted) == null);
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness a read element beside a mutable one at another literal index is disjoint (M5, G3)" {
    try acceptsTree(std.testing.allocator,
        \\    link(mut tree.nodes[0], tree.nodes[1])
        \\    link(mut tree.nodes[1], tree.nodes[0])
    );
    try refusesElementArgument(std.testing.allocator,
        \\    link(mut tree.nodes[0], tree.nodes[0])
    , "may be the same list element", "fields of one record");
    try refusesElementArgument(std.testing.allocator,
        \\    const p = 0
        \\    const c = 1
        \\    link(mut tree.nodes[p], tree.nodes[c])
    , "separate storage only when both indices are distinct literals", "fields of one record");
    try refusesElementArgument(std.testing.allocator,
        \\    const c = 1
        \\    link(mut tree.nodes[0], tree.nodes[c])
    , "pass the list `mut` and index both elements inside the callee", "fields of one record");
}

// spec-case: OWNERSHIP-CONTRACT-1
test "ownership correctness the record-field message stays where fields are the overlap (M5)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try @import("test_support.zig").checkSource(a,
        \\record Pair:
        \\    left: int[]
        \\    right: int[]
        \\func fill(mut pair: Pair, other: int[]):
        \\    append(mut pair.left, len(other))
        \\func main() -> int:
        \\    mut pair = Pair(left=[], right=[])
        \\    fill(mut pair, pair.right)
        \\    return 0
    );
    try std.testing.expect(checked.passed);
    const ownership = @import("single_owner.zig");
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.check(a, checked.program.?, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failure.code);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "list element") == null);
}

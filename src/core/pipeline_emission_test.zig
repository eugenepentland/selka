//! Shared release analysis reaches split units, whole output and native receipts.
const std = @import("std");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const pipeline = @import("pipeline.zig");
const driver = @import("driver.zig");
const support = @import("test_support.zig");

const app = "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.origin(mut xs, 2)\n";
// Keep a genuine consuming CFG after negative-index normalization is removed.
const leaf = "public func origin(mut xs: int[], x: int) -> int:\n    append(mut xs, 2)\n    if x == 0:\n        return xs[0]\n    return xs[x]\n";

fn snapshot(a: std.mem.Allocator, scratch: std.mem.Allocator, mode: @import("build_mode.zig").Mode, whole: bool) !pipeline.Emission {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = app });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "leaf.selka", .data = leaf });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = frontend.Session.init(a, std.testing.io, root);
    defer session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "app", &report);
    var refusal: build.Refusal = .{};
    var module = try build.buildModuleSource(a, checked.program, checked.src, &refusal);
    const emitted = try pipeline.emittedWithScratch(a, scratch, &module, .{ .src = checked.src, .source_path = "app.selka", .main = .{} }, .{
        .zig = "unused",
        .mode = mode,
        .show = .{ .llvm = if (whole) "unused" else null, .stats = true },
    }, &report);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report.items, "selka-core: inlined "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report.items, "selka-core: ownership: "));
    return emitted;
}

// spec-case: NEW-CORE-S4-UNITS-1
test "pipeline emitted optional whole output preserves every native unit and cloned source frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (.{ .debug, .optimized_debug, .lean_debug, .release }) |mode| {
        if (mode == .release) try support.requireRelease();
        const split = try snapshot(a, std.testing.allocator, mode, false);
        const both = try snapshot(a, std.testing.allocator, mode, true);
        try std.testing.expect(split.whole == null);
        try std.testing.expectEqual(split.units.len, both.units.len);
        if (mode == .optimized_debug or mode == .lean_debug) try std.testing.expect(split.units.len > 1);
        for (split.units, both.units) |left, right| {
            try std.testing.expectEqualStrings(left.name, right.name);
            try std.testing.expectEqualStrings(left.llvm, right.llvm);
        }
        try std.testing.expect(std.mem.indexOf(u8, both.whole.?, "!DIFile(filename: \"leaf.selka\"") != null);
        if (mode != .debug) try std.testing.expect(std.mem.indexOf(u8, both.whole.?, "inlinedAt:") != null);
    }
}

fn native(a: std.mem.Allocator, emission: pipeline.Emission, split: bool, mode: @import("build_mode.zig").Mode) !std.process.RunResult {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const output = try std.fs.path.join(a, &.{ root, "program" });
    var report: std.ArrayList(u8) = .empty;
    _ = try driver.link(a, std.testing.io, &environment, .{
        .zig = environment.get("SELKA_ZIG") orelse "zig",
        .work = try @import("core_test_options").suiteCache(a, @src()),
        .output = output,
        .family = .{ .mode = mode },
        .links = &.{},
        .units = if (split) emission.units else &.{driver.wholeUnit(emission.whole.?)},
    }, &report);
    return std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
}

// spec-case: NEW-CORE-S4-SITES-1
test "pipeline emitted split and whole native traps preserve exact consuming callee and caller frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const development = try native(a, try snapshot(a, std.testing.allocator, .optimized_debug, false), true, .optimized_debug);
    try std.testing.expectEqual(@as(u8, 1), development.term.exited);
    try support.requireRelease();
    const emission = try snapshot(a, std.testing.allocator, .release, true);
    const split = try native(a, emission, true, .release);
    const whole = try native(a, emission, false, .release);
    try std.testing.expectEqual(@as(u8, 1), split.term.exited);
    try std.testing.expectEqual(@as(u8, 1), whole.term.exited);
    try std.testing.expectEqualStrings("", split.stdout);
    try std.testing.expectEqualStrings(split.stdout, whole.stdout);
    try std.testing.expectEqualStrings(split.stderr, whole.stderr);
    try std.testing.expect(std.mem.indexOf(u8, split.stderr, "in leaf::origin at leaf.selka:5:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, split.stderr, "in app::main at app.selka:4:12") != null);
    try std.testing.expectEqualStrings(whole.stdout, development.stdout);
    try std.testing.expectEqualStrings(whole.stderr, development.stderr);
}

/// Expect the lean build's units to be the -O0 build's, byte for byte, and to mark no function `optnone`.
fn expectSameTextNoOptnone(plain: pipeline.Emission, lean: pipeline.Emission) !void {
    try std.testing.expectEqual(plain.units.len, lean.units.len);
    for (plain.units, lean.units) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.llvm, right.llvm);
        try std.testing.expect(std.mem.indexOf(u8, right.llvm, "optnone") == null);
    }
}

// spec-case: DEBUG-OPTIMIZE-1
test "the lean debug build emits the -O0 build's text with no optnone, and its native trap matches -O0's report and lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try snapshot(a, std.testing.allocator, .optimized_debug, false);
    const lean = try snapshot(a, std.testing.allocator, .lean_debug, false);
    try expectSameTextNoOptnone(plain, lean);
    const at_o0 = try native(a, plain, true, .optimized_debug);
    const at_lean = try native(a, lean, true, .lean_debug);
    try std.testing.expectEqual(@as(u8, 1), at_o0.term.exited);
    try std.testing.expectEqual(at_o0.term, at_lean.term);
    try std.testing.expectEqualStrings(at_o0.stdout, at_lean.stdout);
    try std.testing.expectEqualStrings(at_o0.stderr, at_lean.stderr);
    try std.testing.expect(std.mem.indexOf(u8, at_lean.stderr, "in leaf::origin at leaf.selka:5:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, at_lean.stderr, "in app::main at app.selka:4:12") != null);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "the IR verifier runs under --verify-facts in every compiler build" {
    // X6: a ReleaseFast compiler catches invalid Core IR before clang when the
    // build asks for facts to be verified; a debug compiler always checks.
    const debug = @import("builtin").mode == .debug;
    var options: pipeline.Options = .{ .zig = "zig" };
    try std.testing.expectEqual(debug, pipeline.checksIr(options));
    options.facts = .verify;
    try std.testing.expect(pipeline.checksIr(options));
    options.facts = .off;
    try std.testing.expectEqual(debug, pipeline.checksIr(options));
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "an ownership refusal renders a located E_CORE_UNSUPPORTED" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try @import("selka").source.Source.init(a, "main.selka", "func main() -> int:\n    return 0\n");
    var report: std.ArrayList(u8) = .empty;
    var refusal: @import("own.zig").Refusal = .{ .function = "main", .operation = "call", .span = 7, .rule = .Z3 };
    try pipeline.reportOwnershipRefusal(a, source, refusal, .text, &report);
    const text = report.items;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "ownership rule Z3"));
    try std.testing.expect(std.mem.indexOf(u8, text, "error[E_CORE_UNSUPPORTED]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "in main") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "schedule a call") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "main.selka:1:") != null);
    // A refusal with no span still names the function rather than printing nothing.
    report.clearRetainingCapacity();
    refusal = .{ .function = "leaf", .operation = "phi", .span = 0, .rule = .Z3 };
    try pipeline.reportOwnershipRefusal(a, source, refusal, .text, &report);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "in leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "error[E_CORE_UNSUPPORTED]") != null);
    // A refusal that names no operation reads as a noun phrase, never "a ownership".
    report.clearRetainingCapacity();
    refusal = .{ .function = "leaf", .operation = "", .span = 0, .rule = .Z3 };
    try pipeline.reportOwnershipRefusal(a, source, refusal, .text, &report);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "cannot schedule the value's owner in leaf") != null);
}

test "an ownership refusal that names the other place says how they conflict and notes where the other place is read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try @import("selka").source.Source.init(a, "main.selka", "func f(mut c: Ctx):\n    g(mut c.a, mut c.b.x)\n");
    var report: std.ArrayList(u8) = .empty;
    const refusal: @import("own.zig").Refusal = .{ .function = "f", .operation = "call", .span = 24, .rule = .Z3, .conflict = .{ .kind = .takes_borrowed, .place = 35, .depth = 2, .caller = "main" } };
    try pipeline.reportOwnershipRefusal(a, source, refusal, .text, &report);
    try std.testing.expectEqualStrings(
        \\main.selka:2:5: error[E_CORE_UNSUPPORTED]: the ownership pass cannot schedule a call in f (inlined into main): it takes ownership of `c.b.x` (line 2), which is a borrowed part of `c` at that point, not an owner; this shape has no safe destruction schedule
        \\  note: ownership rule Z3
        \\  note: main.selka:2:16: `c.b.x` is read here as a borrow of `c`
        \\
    , report.items);
}

test "an ownership refusal whose other place has no position names no line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try @import("selka").source.Source.init(a, "main.selka", "func f():\n    g()\n");
    var report: std.ArrayList(u8) = .empty;
    const refusal: @import("own.zig").Refusal = .{ .function = "f", .operation = "jump", .span = 14, .rule = .Z3, .conflict = .{ .kind = .edge_live } };
    try pipeline.reportOwnershipRefusal(a, source, refusal, .text, &report);
    try std.testing.expectEqualStrings(
        \\main.selka:2:5: error[E_CORE_UNSUPPORTED]: the ownership pass cannot schedule jump in f: a branch hands on a value while the code it branches to still reads it; this shape has no safe destruction schedule
        \\  note: ownership rule Z3
        \\
    , report.items);
}

test "a refusal's place is the path at its span, without its marker, cut to the depth the pass saw" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = @import("ownership_refusal_text.zig");
    const source = try @import("selka").source.Source.init(arena.allocator(), "m.selka", "f(mut ctx.block.rules, own xs[i + 1].name)\n");
    try std.testing.expectEqualStrings("ctx.block.rules", text.place(source, 2, 0));
    try std.testing.expectEqualStrings("ctx.block", text.place(source, 2, 1));
    try std.testing.expectEqualStrings("xs[i + 1].name", text.place(source, 23, 0));
    try std.testing.expectEqualStrings("xs", text.owner(text.place(source, 23, 0)));
    try std.testing.expectEqualStrings("the value", text.place(source, 0, 0));
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "ownership refusals preserve selected rules in JSON and leave backend refusals unlabeled" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try @import("selka").source.Source.init(a, "main.selka", "func main() -> int:\n    return 0\n");
    var report: std.ArrayList(u8) = .empty;
    try pipeline.reportOwnershipRefusal(a, source, .{ .function = "main", .operation = "call", .span = 7, .rule = .Z3 }, .json, &report);
    const owned = try std.json.parseFromSlice(std.json.Value, a, report.items, .{});
    try std.testing.expectEqualStrings("Z3", owned.value.object.get("diagnostic").?.object.get("rule").?.string);
    report.clearRetainingCapacity();
    try pipeline.reportOwnershipRefusal(a, source, .{ .function = "malformed", .operation = "invalid marker", .span = 7 }, .json, &report);
    const malformed = try std.json.parseFromSlice(std.json.Value, a, report.items, .{});
    try std.testing.expect(malformed.value.object.get("diagnostic").?.object.get("rule") == null);
    report.clearRetainingCapacity();
    try pipeline.reportBuildRefusal(a, source, .{ .reason = "an ownership limit", .span = 7, .rule = .Z3 }, .json, &report);
    const builder = try std.json.parseFromSlice(std.json.Value, a, report.items, .{});
    try std.testing.expectEqualStrings("Z3", builder.value.object.get("diagnostic").?.object.get("rule").?.string);
    report.clearRetainingCapacity();
    try pipeline.reportBuildRefusal(a, source, .{ .reason = "an unsupported ABI", .span = 7 }, .json, &report);
    const backend = try std.json.parseFromSlice(std.json.Value, a, report.items, .{});
    try std.testing.expect(backend.value.object.get("diagnostic").?.object.get("rule") == null);
    report.clearRetainingCapacity();
    try pipeline.reportBuildRefusal(a, source, .{ .reason = "an unsupported ABI", .span = 7 }, .text, &report);
    try std.testing.expectEqualStrings("main.selka:1:8: error[E_CORE_UNSUPPORTED]: the new core does not support an unsupported ABI yet\n", report.items);
    report.clearRetainingCapacity();
    try pipeline.reportBuildRefusal(a, source, .{ .reason = "an ownership limit", .span = 7, .rule = .Z3 }, .text, &report);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report.items, "ownership rule Z3"));
    // A refusal that carries a hint says what to do after the sentence, so the report is one sentence and one clause.
    report.clearRetainingCapacity();
    try pipeline.reportBuildRefusal(a, source, .{ .reason = "a slice of bytes given to a task", .span = 7, .hint = "a slice has no owner to lend, so copy it into a local first" }, .text, &report);
    try std.testing.expectEqualStrings("main.selka:1:8: error[E_CORE_UNSUPPORTED]: the new core does not support a slice of bytes given to a task yet: a slice has no owner to lend, so copy it into a local first\n", report.items);
}

//! Unit purity, stable names and native linking across actual source modules.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const language = @import("selka");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const emitter = @import("emit_llvm.zig");
const units = @import("emit_units.zig");
const driver = @import("driver.zig");
const ir = @import("ir.zig");
const constants = @import("emit_constants.zig");
const support = @import("test_support.zig");
const report = std.debug.print;
const stage_roots = @import("stage_roots.zig");
const stage_pack = @import("stage_pack.zig");

const app = "import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    print(out, leaf.compute(7), other.compute(3))\n    return 0\n";
const leaf = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    return total\n";
const other = "\npublic func compute(x: int) -> int:\n    return x + 1\n";
const Mode = enum { debug, release, verify, optimized };

fn releaseUnits(a: std.mem.Allocator, emitted: []units.Unit) void {
    for (emitted) |unit| {
        a.free(unit.name);
        a.free(unit.source_path);
        a.free(unit.llvm);
    }
    a.free(emitted);
}

fn fixedLocation(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "lifetime.selka", .line = 1, .column = 1 };
}

fn unitLifetimeModule(a: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    for (0..32) |index| {
        var hand = try support.Hand.init(a, &module, try std.fmt.allocPrint(a, "function[{d}]", .{index}), .{ .params = &.{}, .ret = .i64 });
        _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, @intCast(index)) });
        _ = try hand.finish();
    }
    return module;
}

fn unitArtifactBytes(emitted: []const units.Unit) usize {
    var bytes: usize = 0;
    for (emitted) |unit| bytes += unit.name.len + unit.source_path.len + unit.llvm.len;
    return std.mem.alignForward(usize, bytes, @alignOf(units.Unit)) + @sizeOf(units.Unit) * emitted.len;
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 unit emission releases partition and catalog scratch and retains independent output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try unitLifetimeModule(arena.allocator());
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{} };
    const first = try units.emitWithScratch(std.testing.allocator, std.testing.allocator, &module, options);
    defer releaseUnits(std.testing.allocator, first);
    // An arena caller can hold exactly two sets of finished artifacts. No
    // partition, descriptor catalog, seed text or growing output list fits.
    const storage = try std.testing.allocator.alignedAlloc(u8, .of(units.Unit), unitArtifactBytes(first) * 2);
    defer std.testing.allocator.free(storage);
    var caller = std.heap.FixedBufferAllocator.init(storage);
    const repeated = try units.emitWithScratch(caller.allocator(), std.testing.allocator, &module, options);
    _ = try units.emitWithScratch(caller.allocator(), std.testing.allocator, &module, options);
    try std.testing.expectEqual(storage.len, caller.end_index);
    try std.testing.expectEqual(@as(usize, 33), first.len);
    try std.testing.expectEqual(first.len, repeated.len);
    for (first, repeated) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings("lifetime.selka", left.source_path);
        try std.testing.expectEqualStrings(left.llvm, right.llvm);
    }
    const whole = try units.wholeWithScratch(std.testing.allocator, std.testing.allocator, &module, options);
    defer releaseUnits(std.testing.allocator, whole);
    try std.testing.expectEqual(@as(usize, 1), whole.len);
    try std.testing.expectEqualStrings("program", whole[0].name);
    try std.testing.expectEqualStrings("lifetime.selka", whole[0].source_path);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 descriptor closure normalizes each appended fragment with exact first-use IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var catalog: constants.Catalog = .{ .prelude = "%myl.value = type { ptr }\n" };
    const definitions = [_][]const u8{
        "@myl.render.91 = private constant ptr @myl.render.children.91",
        "@myl.value.42 = private constant ptr @myl.value.name.42.0",
        "@myl.render.children.91 = private constant ptr @myl.render.92",
        "@myl.value.name.42.0 = private constant [15 x i8] c\"@myl.value.999\\00\"",
        "@myl.render.92 = private constant ptr @myl.value.42",
    };
    for (definitions) |definition| {
        var symbols: constants.Symbols = .{ .text = definition };
        try catalog.globals.put(a, symbols.next().?, definition);
    }
    const body = "@r = private constant ptr @myl.render.91\n@v = private constant ptr @myl.value.42\n";
    const expected =
        "@r = private constant ptr @myl.render.0\n@v = private constant ptr @myl.value.0\n" ++
        "%myl.value = type { ptr }\n" ++
        "@myl.render.0 = private constant ptr @myl.render.children.0\n" ++
        "@myl.value.0 = private constant ptr @myl.value.name.0.0\n" ++
        "@myl.render.children.0 = private constant ptr @myl.render.1\n" ++
        "@myl.value.name.0.0 = private constant [15 x i8] c\"@myl.value.999\\00\"\n" ++
        "@myl.render.1 = private constant ptr @myl.value.0\n";
    try std.testing.expectEqualStrings(expected, try catalog.finish(a, body));
}

fn locate(context: *const anyopaque, offset: u32) emitter.Location {
    const src: *const language.source.Source = @ptrCast(@alignCast(context));
    const at = frontend.position(src.*, .{ .start = offset, .end = offset });
    return .{ .path = at.path, .line = at.line, .column = at.column };
}

fn snapshot(a: std.mem.Allocator, sources: [3][]const u8, release: bool) ![]units.Unit {
    return snapshotFor(a, sources, if (release) .release else .debug);
}

fn snapshotFor(a: std.mem.Allocator, sources: [3][]const u8, mode: Mode) ![]units.Unit {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const names = [_][]const u8{ "app.selka", "leaf.selka", "other.selka" };
    for (names, sources) |name, text| try dir.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = text });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = frontend.Session.init(a, std.testing.io, root);
    defer session.deinit();
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = session.check(a, "app", &diagnostics) catch |err| {
        report("unit fixture: {s}\n", .{diagnostics.items});
        return err;
    };
    var refusal: build.Refusal = .{};
    var module = try build.buildModuleSource(a, checked.program, checked.src, &refusal);
    const result = if (mode != .debug) try passes.run(a, &module, if (mode == .verify) .verify else .trusted) else passes.Result{ .known = &.{}, .plans = &.{} };
    if (mode == .debug) _ = try passes.ownership(a, &module);
    const main = checked.program.functions[@backingInt(checked.program.main)];
    const shape = language.typed.resultShape(main.signature.return_type, checked.program.records);
    const options: emitter.Options = .{
        .locator = .{ .context = &checked.src, .locate = locate },
        .source_path = "app.selka",
        .main = .{ .parameters = &.{"out"}, .result = if (shape) |s| .{ .ok_tag = @intCast(s.ok_tag), .error_tag = @intCast(s.error_tag) } else null },
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance },
        .verify = mode == .verify,
    };
    // S4-1a: release and verify builds are one whole-program unit, as the pipeline emits them. Debug and
    // optimized (trusted passes, one unit per module) builds keep module units.
    return if (mode == .debug or mode == .optimized) units.emit(a, &module, options) else units.whole(a, &module, options);
}

fn programText(emitted: []const units.Unit) ![]const u8 {
    if (emitted.len != 1 or emitted[0].kind != .program) return error.MissingUnit;
    return emitted[0].llvm;
}

fn textOf(emitted: []const units.Unit, path: []const u8) ![]const u8 {
    for (emitted) |unit| if (unit.kind == .module and std.mem.eql(u8, unit.source_path, path)) return unit.llvm;
    return error.MissingUnit;
}

fn expectRenderingNumberDependency(emitted: []const units.Unit, path: []const u8) !void {
    var found = false;
    for (emitted) |unit| {
        const owns_render = unit.kind == .module and std.mem.eql(u8, unit.source_path, path);
        try std.testing.expectEqual(owns_render, unit.dependencies.number);
        if (!owns_render) continue;
        found = true;
        try std.testing.expect(std.mem.indexOf(u8, unit.llvm, "call ptr @myl_core_values_render(") != null);
        try std.testing.expect(std.mem.indexOf(u8, unit.llvm, "= private constant %myl.value { i32 2,") != null);
        try std.testing.expect(std.mem.indexOf(u8, unit.llvm, "declare ptr @myl_core_str_from_f64(") != null);
    }
    try std.testing.expect(found);
}

fn entryText(emitted: []const units.Unit) ![]const u8 {
    for (emitted) |unit| if (unit.kind == .entry) return unit.llvm;
    return error.MissingUnit;
}

fn changed(before: []const units.Unit, after: []const units.Unit, expected: []const []const u8) !void {
    try std.testing.expectEqual(before.len, after.len);
    for (before) |unit| {
        var found = false;
        for (after) |next| {
            if (!std.mem.eql(u8, unit.name, next.name)) continue;
            const same = std.mem.eql(u8, unit.llvm, next.llvm);
            var should_change = false;
            for (expected) |path| if ((std.mem.eql(u8, unit.source_path, path) and unit.kind == .module) or
                (std.mem.eql(u8, path, "<entry>") and unit.kind == .entry))
            {
                should_change = true;
            };
            try std.testing.expectEqual(!should_change, same);
            found = true;
        }
        try std.testing.expect(found);
    }
}

// spec: NEW-CORE-S4-UNITS-1
test "S4 units repeat exactly and body, checked-operation and line edits affect only the owning module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try snapshot(a, .{ app, leaf, other }, false);
    try std.testing.expectError(error.MissingUnit, textOf(first, "missing.selka"));
    try changed(first, try snapshot(a, .{ app, leaf, other }, false), &.{});
    const body = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i * 2\n    return total\n";
    try changed(first, try snapshot(a, .{ app, body, other }, false), &.{"leaf.selka"});
    const check = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    assert total >= 0, \"sum\"\n    return total\n";
    try changed(first, try snapshot(a, .{ app, check, other }, false), &.{"leaf.selka"});
    const shifted = "\n\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    return total\n";
    try changed(first, try snapshot(a, .{ app, shifted, other }, false), &.{"leaf.selka"});
    const leaf_text = try textOf(first, "leaf.selka");
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "!DIFile(filename: \"leaf.selka\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "@myl_core_sites") == null);
}

const linkage_app = "import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    print(out, leaf.entry_point(7), other.compute(3))\n    return 0\n";
const linkage_leaf = "\npublic func shared(x: int) -> int:\n    return x + 1\n\npublic func entry_point(x: int) -> int:\n    return shared(x) + helper(x)\n\nfunc helper(x: int) -> int:\n    return x * 3\n";
const linkage_other_calls = "import leaf\n\npublic func compute(x: int) -> int:\n    return leaf.shared(x)\n";
const linkage_other_alone = "\npublic func compute(x: int) -> int:\n    return x + 1\n";

// spec-case: NEW-CORE-S4-UNITS-1
test "a module's unit text follows from its own source: another module calling or not calling its public function leaves it equal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const calling = try snapshot(a, .{ linkage_app, linkage_leaf, linkage_other_calls }, false);
    const alone = try snapshot(a, .{ linkage_app, linkage_leaf, linkage_other_alone }, false);
    const leaf_text = try textOf(calling, "leaf.selka");
    try std.testing.expectEqualStrings(leaf_text, try textOf(alone, "leaf.selka"));
    // The public function is hidden whether or not anyone calls it from another unit; the private one stays internal.
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define hidden fastcc i64 @\"my.leaf::shared\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define hidden fastcc i64 @\"my.leaf::entry_point\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define internal fastcc i64 @\"my.leaf::helper\"") != null);
}

/// The debug units of the project made of `names`/`sources`, built from module `entry`.
fn projectUnits(a: std.mem.Allocator, names: []const []const u8, sources: []const []const u8, entry: []const u8) ![]units.Unit {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    for (names, sources) |name, text| try dir.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = text });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = frontend.Session.init(a, std.testing.io, root);
    defer session.deinit();
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = session.check(a, entry, &diagnostics) catch |err| {
        report("project fixture: {s}\n", .{diagnostics.items});
        return err;
    };
    var refusal: build.Refusal = .{};
    var module = try build.buildModuleSource(a, checked.program, checked.src, &refusal);
    _ = try passes.ownership(a, &module);
    const options: emitter.Options = .{ .locator = .{ .context = &checked.src, .locate = locate }, .source_path = "app.selka", .main = .{ .parameters = &.{"out"} } };
    return units.emit(a, &module, options);
}

const scanner_source = "\n\nfunc helper() -> int:\n    return 7\n\npublic func scan() -> int:\n    return helper()\n";
const scanner_user = "import scanner\n\nfunc main(out: Stream) -> int:\n    print(out, scanner.scan())\n    return 0\n";
const scanner_tests = "import scanner\n\nfunc main(out: Stream) -> int:\n    print(out, scanner.helper())\n    return 0\n\npublic func test_helper() -> bool:\n    return scanner.helper() == scanner.scan()\n";

// spec-case: NEW-CORE-S4-UNITS-1
test "a private function is internal in its unit, and hidden when the module's test file is in the build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try projectUnits(a, &.{ "app.selka", "scanner.selka" }, &.{ scanner_user, scanner_source }, "app");
    try std.testing.expect(std.mem.indexOf(u8, try textOf(plain, "scanner.selka"), "define internal fastcc i64 @\"my.scanner::helper\"") != null);
    const tested = try projectUnits(a, &.{ "scanner_test.selka", "scanner.selka" }, &.{ scanner_tests, scanner_source }, "scanner_test");
    const text = try textOf(tested, "scanner.selka");
    try std.testing.expect(std.mem.indexOf(u8, text, "define hidden fastcc i64 @\"my.scanner::helper\"") != null);
}

fn namedFunction(a: std.mem.Allocator, module: *ir.Module, name: []const u8) !void {
    var hand = try support.Hand.init(a, module, name, .{ .params = &.{}, .ret = .i64 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, @intCast(name.len * 7)) });
    _ = try hand.finish();
}

fn namedModule(a: std.mem.Allocator, names: []const []const u8, entry: u32) !ir.Module {
    var module: ir.Module = .{};
    for (names) |name| try namedFunction(a, &module, name);
    module.entry = entry;
    return module;
}

// spec-case: NEW-CORE-S4-UNITS-1
test "a unit's functions and the units themselves are ordered by name, whatever order lowering found them in" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{} };
    const forward = [_][]const u8{ "alpha", "beta", "gamma", "delta[int]", "epsilon[int]" };
    const backward = [_][]const u8{ "epsilon[int]", "delta[int]", "gamma", "beta", "alpha" };
    const first = try namedModule(a, &forward, 0);
    const second = try namedModule(a, &backward, 4);
    const left = try units.emit(a, &first, options);
    const right = try units.emit(a, &second, options);
    try std.testing.expectEqual(left.len, right.len);
    for (left, right) |before, after| {
        try std.testing.expectEqualStrings(before.name, after.name);
        try std.testing.expectEqualStrings(before.llvm, after.llvm);
    }
    // The module unit comes before the generic instances, and the functions inside it follow their names.
    try std.testing.expectEqual(units.Kind.module, left[0].kind);
    const text = left[0].llvm;
    const alpha = std.mem.indexOf(u8, text, "@\"my.alpha\"").?;
    const beta = std.mem.indexOf(u8, text, "@\"my.beta\"").?;
    const gamma = std.mem.indexOf(u8, text, "@\"my.gamma\"").?;
    try std.testing.expect(alpha < beta and beta < gamma);
}

// spec: NEW-CORE-S4-RELEASE-1
test "S4 a release build is one whole-program unit and a debug build one unit per module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const release = try snapshot(a, .{ app, leaf, other }, true);
    const text = try programText(release);
    try std.testing.expect(std.mem.indexOf(u8, text, "@\"my.leaf::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@\"my.other::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "available_externally") == null);
    try std.testing.expectEqualStrings(text, try programText(try snapshot(a, .{ app, leaf, other }, true)));
    const updated = "\npublic func compute(x: int) -> int:\n    return x + 2\n";
    try std.testing.expect(!std.mem.eql(u8, text, try programText(try snapshot(a, .{ app, leaf, updated }, true))));
    const debug = try snapshot(a, .{ app, leaf, other }, false);
    try std.testing.expectError(error.MissingUnit, programText(debug));
    for ([_][]const u8{ "app.selka", "leaf.selka", "other.selka" }) |path| _ = try textOf(debug, path);
    _ = try entryText(debug);
    const result = try native(a, release);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("21 4\n", result.stdout);
}

fn native(a: std.mem.Allocator, emitted: []const units.Unit) !std.process.RunResult {
    return nativeArgs(a, emitted, &.{});
}

fn nativeArgs(a: std.mem.Allocator, emitted: []const units.Unit, arguments: []const []const u8) !std.process.RunResult {
    try support.requireRelease();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const counter_path = try std.fs.path.join(a, &.{ root, "counters.json" });
    try environment.put("SELKA_COUNTERS", counter_path);
    const output = try std.fs.path.join(a, &.{ root, "program" });
    var log: std.ArrayList(u8) = .empty;
    const work = try @import("core_test_options").suiteCache(a, @src());
    _ = driver.link(a, std.testing.io, &environment, .{ .zig = environment.get("ZIG") orelse "zig", .work = work, .output = output, .family = .{ .mode = .release }, .links = &.{}, .units = emitted }, &log) catch |err| {
        report("unit native build: {s}\n", .{log.items});
        return err;
    };
    const argv = try a.alloc([]const u8, arguments.len + 1);
    argv[0] = output;
    @memcpy(argv[1..], arguments);
    const result = try std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
    for (emitted) |unit| if (unit.dependencies.counting) {
        const bytes = try dir.dir.readFileAlloc(std.testing.io, "counters.json", a, .limited(1 << 20));
        const Exit = struct { totals: struct { live_bytes_at_exit: u64 } };
        const counters = try std.json.parseFromSlice(Exit, a, bytes, .{ .ignore_unknown_fields = true });
        defer counters.deinit();
        try std.testing.expectEqual(@as(u64, 0), counters.value.totals.live_bytes_at_exit);
        break;
    };
    return result;
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 numeric buffer operations declare reached helpers in owner and imported units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main(out: Stream) -> int:\n    for i in range(1):\n" ++
        "        const buffer = leaf.formatted()\n        print(out, len(buffer), buffer[0], buffer[1], buffer[2], buffer[3], buffer[4])\n    return 0\n";
    const formatted = "import buffers\n\npublic func formatted() -> byte_buffer:\n    mut empty: int[] = []\n" ++
        "    mut buffer = byte_buffer(empty)\n    buffers.append_int(mut buffer, -7)\n    buffers.append_float(mut buffer, 1.5)\n    return buffer\n";
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const emitted = try snapshotFor(a, .{ caller, formatted, other }, mode);
        for (emitted) |unit| if (std.mem.eql(u8, unit.source_path, "other.selka")) try std.testing.expect(!unit.dependencies.number);
        const result = try native(a, emitted);
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("5 45 55 49 46 53\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
    }
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 integer-only numeric buffer operations avoid the float helper dependency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const integer_caller = "import leaf\nfunc main(out: Stream) -> int:\n" ++
        "    const buffer = leaf.formatted()\n    print(out, len(buffer), buffer[0], buffer[1])\n    return 0\n";
    const integer = "import buffers\n\npublic func formatted() -> byte_buffer:\n    mut empty: int[] = []\n" ++
        "    mut buffer = byte_buffer(empty)\n    buffers.append_int(mut buffer, -7)\n    return buffer\n";
    const emitted = try snapshot(a, .{ integer_caller, integer, other }, false);
    for (emitted) |unit| try std.testing.expect(!unit.dependencies.number);
    const result = try native(a, emitted);
    try std.testing.expectEqualStrings("2 45 55\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
}

// spec: NEW-CORE-S4-SITES-1
test "S4 native cross-unit traps carry their source path and callers through all compile units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failing = "\npublic func compute(x: int) -> int:\n    assert x == 0, \"leaf check\"\n    return x\n";
    const result = try native(a, try snapshot(a, .{ app, failing, other }, false));
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.selka:3:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.selka:5:") != null);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 a release tail-position cross-unit trap retains its caller frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> int:\n    return leaf.compute(7)\n";
    const failing = "public func compute(x: int) -> int:\n    assert x == 0, \"leaf check\"\n    return x\n";
    const result = try native(a, try snapshot(a, .{ caller, failing, other }, true));
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.selka:2:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.selka:3:12") != null);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 an inlined cross-module Result origin retains its source function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> Result[int, str]:\n    mut value = try leaf.origin()\n    return Ok(value)\n";
    const failing = "public func origin() -> int fails str:\n    fail \"leaf failure\"\n";
    for ([_]bool{ false, true }) |release| {
        const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("error: leaf failure\n  leaf.selka:2:5  leaf::origin  Err(...) created\n  app.selka:3:17  app::main     try propagated\n", result.stderr);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 Result origins distinguish specializations sharing one declaration and body span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import strings\nimport leaf\nfunc main(args: str[]) -> int fails str:\n" ++
        "    if len(args) == 0:\n        const integer = try leaf.origin[int](1)\n        return integer\n" ++
        "    const text = try leaf.origin[str](\"x\")\n    return strings.char_count(text)\n";
    const failing = "public func origin[T](x: T) -> T fails str:\n    fail \"leaf failure\"\n";
    for ([_]bool{ false, true }) |release| {
        const emitted = try snapshot(a, .{ caller, failing, other }, release);
        for ([_][]const []const u8{ &.{}, &.{"string"} }, [_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }) |arguments, function| {
            const result = try nativeArgs(a, emitted, arguments);
            try std.testing.expect(result.term == .exited and result.term.exited == 1);
            if (std.mem.indexOf(u8, result.stderr, function) == null) report("specialization origin expected {s}: {s}", .{ function, result.stderr });
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, function) != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.selka:2:5") != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "app::main") != null);
        }
    }
}

fn preserved(before: []const units.Unit, after: []const units.Unit, path: []const u8) !void {
    try std.testing.expectEqualStrings(try textOf(before, path), try textOf(after, path));
    for (before) |old| {
        if (old.kind != .helper) continue;
        var matched = false;
        for (after) |next| {
            if (!std.mem.eql(u8, old.name, next.name)) continue;
            try std.testing.expectEqualStrings(old.llvm, next.llvm);
            matched = true;
        }
        try std.testing.expect(matched);
    }
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 unrelated render graphs, types and literal IDs leave reached descriptor units byte-identical" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rendering = "import strings\n\nrecord RenderKey:\n    first: int\n    second: int\n" ++
        "public func compute(x: int) -> int:\n    mut values = {RenderKey(first=1, second=2): [3.5, 4.25]}\n" ++
        "    return strings.char_count(f\"{values}\") + x\n";
    const before = try snapshot(a, .{ app, rendering, other }, false);
    const noise =
        \\import strings
        \\record NoiseKey:
        \\    label: str
        \\    number: int
        \\record NoiseValue:
        \\    flag: bool
        \\    number: int
        \\    text: str
        \\public func identity[T](x: T) -> T:
        \\    return x
        \\public func compute(x: int) -> int:
        \\    mut values = {NoiseKey(label="@myl.value.999", number=x): [NoiseValue(flag=True, number=x, text="noise")]}
        \\    mut text = f"{values}"
        \\    assert strings.char_count(text) > 0
        \\    return identity[int](x) + 1
    ;
    const after = try snapshot(a, .{ app, rendering, noise }, false);
    try preserved(before, after, "leaf.selka");
    try std.testing.expectEqualStrings(try textOf(before, "app.selka"), try textOf(after, "app.selka"));
    const noisy = try textOf(after, "other.selka");
    try std.testing.expect(std.mem.indexOf(u8, noisy, "c\"@myl.value.999") != null);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 a float renderer outside entry carries the formatter link dependency on its source unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rendering = "import strings\n\npublic func compute(x: int) -> int:\n    mut values = [1.25, 2.5]\n    return strings.char_count(f\"{values}\") + x\n";
    const emitted = try snapshot(a, .{ app, rendering, other }, false);
    try expectRenderingNumberDependency(emitted, "leaf.selka");
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("18 4\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 identical record renderers in separate modules share one native helper unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nimport other\nfunc main(out: Stream) -> int:\n    print(out, leaf.render(1), other.render(2))\n    return 0\n";
    const left = "public record Cell:\n    value: int\npublic func render(x: int) -> str:\n    return f\"{Cell(value=x)}\"\n";
    const right = "public record Cell:\n    value: int\npublic func render(x: int) -> str:\n    return f\"{Cell(value=x)}\"\n";
    const emitted = try snapshot(a, .{ caller, left, right }, false);
    for (emitted, 0..) |unit, index| {
        for (emitted[index + 1 ..]) |next| try std.testing.expect(!std.mem.eql(u8, unit.name, next.name));
    }
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("Cell(value=1) Cell(value=2)\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 direct and indirect cross-unit fastcc calls preserve the aggregate sret ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller =
        \\import leaf
        \\import other
        \\func main(out: Stream) -> int:
        \\    mut value = other.apply(leaf.grow, leaf.make(7))
        \\    print(out, value.a, value.f)
        \\    return 0
    ;
    const aggregate =
        \\public record Big:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\    f: int
        \\public func make(x: int) -> Big:
        \\    return Big(a=x, b=2, c=3, d=4, e=5, f=6)
        \\public func grow(value: Big) -> Big:
        \\    return Big(a=value.a + 1, b=value.b, c=value.c, d=value.d, e=value.e, f=value.f)
    ;
    const indirect =
        \\import leaf
        \\public func apply(callback: func(leaf.Big) -> leaf.Big, value: leaf.Big) -> leaf.Big:
        \\    return callback(value)
    ;
    const emitted = try snapshot(a, .{ caller, aggregate, indirect }, false);
    const body = try textOf(emitted, "other.selka");
    try std.testing.expect(std.mem.indexOf(u8, body, "call fastcc void %p0(ptr sret([48 x i8])") != null);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("8 6\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 an inlined Result origin retains its callee path and function inside a counted loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> Result[int, str]:\n" ++
        "    for i in range(2):\n        const value = try leaf.origin(i)\n        assert value >= 0\n    return Ok(0)\n";
    const failing = "public func origin(x: int) -> int fails str:\n    fail \"loop failure\"\n";
    const emitted = try snapshot(a, .{ caller, failing, other }, true);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("error: loop failure\n  leaf.selka:2:5  leaf::origin  Err(...) created\n  app.selka:4:23  app::main     try propagated\n", result.stderr);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 unsafe leaf arithmetic retains its source callee and caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failures = [_]struct { arguments: []const u8, parameters: []const u8, expression: []const u8 }{
        .{ .arguments = "9223372036854775807", .parameters = "x: int", .expression = "x + 1" },
        .{ .arguments = "7, 0", .parameters = "x: int, y: int", .expression = "x // y" },
        .{ .arguments = "-9223372036854775808, -1", .parameters = "x: int, y: int", .expression = "x // y" },
        .{ .arguments = "1, 64", .parameters = "x: int, y: int", .expression = "shift_left(x, y)" },
        .{ .arguments = "256", .parameters = "x: int", .expression = "int(u8(x))" },
    };
    for (failures) |failure| {
        const caller = try std.fmt.allocPrint(a, "import leaf\nfunc main() -> int:\n    return leaf.origin({s})\n", .{failure.arguments});
        const failing = try std.fmt.allocPrint(a, "public func origin({s}) -> int:\n    return {s}\n", .{ failure.parameters, failure.expression });
        for ([_]bool{ false, true }) |release| {
            const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
            try std.testing.expect(result.term == .exited and result.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in leaf::origin at leaf.selka:2:") != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.selka:3:12") != null);
        }
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 consuming CFG clones retain exact callee and original call frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { argument: []const u8, body: []const u8, expected: []const u8 }{
        .{
            .argument = "2",
            // Keep a real consuming CFG after index normalization is removed.
            .body = "    if x == 0:\n        return xs[0]\n    return xs[x]\n",
            .expected = "leaf.selka:5:12: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n" ++
                "  in leaf::origin at leaf.selka:5:12\n  in app::main at app.selka:4:12\n" ++
                "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"index\",\"index\":2,\"length\":2}\n",
        },
        .{
            .argument = "1",
            .body = "    assert x == 0, \"mut check\"\n    return x\n",
            .expected = "leaf.selka:3:12: error[R_ASSERT]: native execution failed: mut check\n" ++
                "  in leaf::origin at leaf.selka:3:12\n  in app::main at app.selka:4:12\n" ++
                "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"mut check\"}\n",
        },
        .{
            .argument = "9223372036854775807",
            .body = "    if x < 0:\n        return 0\n    return x + 1\n",
            .expected = "leaf.selka:5:14: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 1, width 64)\n" ++
                "  in leaf::origin at leaf.selka:5:14\n  in app::main at app.selka:4:12\n" ++
                "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":1,\"width\":64}\n",
        },
    };
    for (cases) |case| {
        const caller = try std.fmt.allocPrint(a, "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.origin(mut xs, {s})\n", .{case.argument});
        const callee = try std.fmt.allocPrint(a, "public func origin(mut xs: int[], x: int) -> int:\n    append(mut xs, 2)\n{s}", .{case.body});
        const emitted = try snapshot(a, .{ caller, callee, other }, true);
        try std.testing.expect(std.mem.indexOf(u8, try programText(emitted), "inlinedAt:") != null);
        const ran = try native(a, emitted);
        try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
        try std.testing.expectEqualStrings("", ran.stdout);
        try std.testing.expectEqualStrings(case.expected, ran.stderr);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 consuming generic clones distinguish shared spans and two original call sites" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main(args: str[]) -> int:\n    mut xs = [1]\n" ++
        "    if len(args) == 0:\n        return leaf.origin[int](mut xs, 1, 2)\n    return leaf.origin[str](mut xs, \"x\", 2)\n";
    const callee = "public func origin[T](mut xs: int[], tag: T, x: int) -> int:\n    append(mut xs, 2)\n    return xs[x]\n";
    for ([_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }, [_][]const []const u8{ &.{}, &.{"text"} }, [_][]const u8{ "app.selka:5:16", "app.selka:6:12" }) |name, arguments, position| {
        const ran = try nativeArgs(a, try snapshot(a, .{ caller, callee, other }, true), arguments);
        try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, name) != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "at leaf.selka:3:12") != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, position) != null);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 nested consuming helpers retain all frames under fact verification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.middle(mut xs, 2)\n";
    const callee = "public func origin(mut xs: int[], x: int) -> int:\n    append(mut xs, 2)\n    return xs[x]\n" ++
        "public func middle(mut xs: int[], x: int) -> int:\n    if x < 0:\n        return 0\n    return origin(mut xs, x)\n";
    const ran = try native(a, try snapshotFor(a, .{ caller, callee, other }, .verify));
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::origin at leaf.selka:3:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::middle at leaf.selka:7:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in app::main at app.selka:4:12") != null);
}

const stages = @import("stage_store.zig");
const optimization = @import("optimization_cache.zig");
const inline_origins = @import("inline_origins.zig");
const emission_cache = @import("emission_cache.zig");
const emission_key = @import("emission_key.zig");
const deferred_facts = @import("deferred_facts.zig");
const fact_tables = @import("facts.zig");

fn encodedFacts(a: std.mem.Allocator, known: []const ?fact_tables.Facts) !deferred_facts.Table {
    const table = try deferred_facts.Table.init(a, known.len);
    for (known, table.entries) |slot, *entry| if (slot) |value| {
        entry.* = try deferred_facts.encode(a, value);
    };
    return table;
}

fn durableFacts(a: std.mem.Allocator, store: *const stages.Store, table: *deferred_facts.Table) !void {
    for (table.entries, 0..) |entry, index| if (entry) |artifact| {
        const key = store.key("emission-durable-facts-test", &.{&artifact.digest});
        try std.testing.expect(try store.save(key, artifact.bytes));
        try table.deferArtifact(a, index, store, key, artifact);
    };
}

fn loseDurableFacts(a: std.mem.Allocator, store: *const stages.Store, table: *const deferred_facts.Table) !void {
    var seen: std.AutoHashMapUnmanaged(deferred_facts.Digest, void) = .empty;
    defer seen.deinit(a);
    for (table.handles) |entry| if (entry) |handle| {
        if ((try seen.getOrPut(a, handle.key)).found_existing) continue;
        try stage_loss.remove(a, store, handle.key);
    };
}

fn sameUnits(expected: []const units.Unit, actual: []const units.Unit) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.source_path, right.source_path);
        try std.testing.expectEqualStrings(left.llvm, right.llvm);
        try std.testing.expectEqual(left.kind, right.kind);
        try std.testing.expectEqual(left.dependencies.number, right.dependencies.number);
        try std.testing.expectEqual(left.dependencies.math, right.dependencies.math);
        try std.testing.expectEqual(left.dependencies.counting, right.dependencies.counting);
    }
}

// spec: NEW-CORE-STAGE-CACHE-5
test "S4 cached emission matches fresh output and renders only the changed unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    const module = try unitLifetimeModule(a);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{} };
    const fresh = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    var cold: emission_cache.Counts = .{};
    const first = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .lanes = 4, .counts = &cold });
    try sameUnits(fresh, first);
    try std.testing.expectEqual(@as(u32, 33), cold.rendered);
    try std.testing.expectEqual(@as(u32, 4), cold.workers);
    var warm: emission_cache.Counts = .{};
    const repeated = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .lanes = 1, .counts = &warm });
    try sameUnits(fresh, repeated);
    try std.testing.expectEqual(@as(u32, 33), warm.reused);
    try std.testing.expectEqual(@as(u32, 0), warm.rendered);
    module.functions.items[7].insts.items[0].data = 81;
    var edited: emission_cache.Counts = .{};
    const changed_units = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .lanes = 4, .counts = &edited });
    try sameUnits(try units.emitWithScratch(a, std.testing.allocator, &module, options), changed_units);
    try std.testing.expectEqual(@as(u32, 32), edited.reused);
    try std.testing.expectEqual(@as(u32, 1), edited.rendered);
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 generated helper seeds and completed units survive scratch and cache hits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, "func main(out: Stream) -> int:\n    const values = [1.25, 2.5]\n    print(out, f\"{values}\")\n    return 0\n", &refusal);
    var wave = try support.Hand.init(a, &module, "wave", .{ .params = &.{.f64}, .ret = .f64 });
    const sine = try wave.emit(.{ .op = .float_unary, .ty = .f64, .a = try wave.param(0), .data = @backingInt(ir.FloatUnary.sin) });
    _ = try wave.emit(.{ .op = .ret, .ty = .void, .a = sine });
    _ = try wave.finish();
    _ = try passes.ownership(a, &module);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{ .parameters = &.{"out"} }, .counters = true };
    const fresh = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    const source = try language.source.Source.init(a, "lifetime.selka", "helper source");
    var loader: FinalLoaderFixture = .{ .module = &module, .bodies = try a.dupe(ir.Function, module.functions.items) };
    const receipt_context: emission_cache.ReceiptContext = .{
        .finals = try receiptFinals(a, &module, options.locator),
        .source = &source,
        .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
    };
    var cold: emission_cache.Counts = .{};
    const first = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .lanes = 2, .counts = &cold, .receipts = receipt_context });
    try sameUnits(fresh, first);
    try std.testing.expect(cold.seeds_rendered > 0);
    var warm: emission_cache.Counts = .{};
    const repeated = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .lanes = 3, .counts = &warm, .receipts = receipt_context });
    try sameUnits(fresh, repeated);
    try std.testing.expectEqual(cold.seeds_rendered, warm.seeds_reused);
    try std.testing.expectEqual(@as(u32, 0), warm.seeds_rendered);
    try std.testing.expectEqual(@as(u32, 0), warm.rendered);
    try expectRenderingNumberDependency(repeated, "lifetime.selka");
    var math = false;
    var counting = false;
    for (repeated) |emitted| {
        math = math or emitted.dependencies.math;
        counting = counting or emitted.dependencies.counting;
    }
    try std.testing.expect(math);
    try std.testing.expect(counting);
    var native_counts: emission_cache.Counts = .{};
    const native_units = try units.emitCached(a, std.testing.allocator, &module, options, .{
        .store = &store,
        .counts = &native_counts,
        .receipts = receipt_context,
        .native_handles = true,
    });
    try sameNativeHandles(fresh, native_units);
    try std.testing.expectEqual(warm.seeds_reused, native_counts.seeds_reused);
    try std.testing.expectEqual(@as(u64, 0), native_counts.work.llvm_loaded_bytes);
    // The cached native handles must carry the formatter object into the link,
    // even though rendering now executes in its descriptor-owning source unit.
    const result = try native(a, native_units);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("[1.25, 2.5]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 deferred fact bytes share eager cache keys and render equal LLVM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, "func my_sum(xs: int[]) -> int:\n    mut total = 0\n    for x in xs:\n        total += x\n    return total\n\nfunc main() -> int:\n    return my_sum([1, 2, 3])\n", &refusal);
    const result = try passes.runWithScratch(a, std.testing.allocator, &module, .trusted);
    const context: u8 = 0;
    var options: emitter.Options = .{
        .locator = .{ .context = &context, .locate = fixedLocation },
        .source_path = "lifetime.selka",
        .main = .{},
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance },
    };
    const fresh = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    const eager = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store });
    try sameUnits(fresh, eager);
    var table = try encodedFacts(a, result.known);
    try durableFacts(a, &store, &table);
    options.analysis.facts = &.{};
    var warm: emission_cache.Counts = .{};
    const reused = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .deferred = &table, .counts = &warm });
    try sameUnits(fresh, reused);
    try std.testing.expectEqual(@as(u32, 0), warm.rendered);
    try std.testing.expectEqual(@as(u32, @intCast(fresh.len)), warm.reused);
    var empty = try stages.Store.init(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "empty" }));
    defer empty.deinit();
    const rendered = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &empty, .deferred = &table, .lanes = 2 });
    try sameUnits(fresh, rendered);
    // An orphaned literal is never rendered, but unknown metadata makes the
    // canonical input policy select uncached emission. Facts must still load.
    try module.functions.items[module.entry].insts.append(a, .{ .op = .str_const, .ty = .str, .data = std.math.maxInt(u64) });
    options.analysis.facts = result.known;
    const fallback_oracle = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    options.analysis.facts = &.{};
    const fallback = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .deferred = &table });
    try sameUnits(fallback_oracle, fallback);
    try loseDurableFacts(a, &store, &table);
    try std.testing.expectError(error.CacheMiss, units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &empty, .deferred = &table }));
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 emission admission bounds concurrent estimated scratch and admits an oversized unit alone" {
    try std.testing.expectEqual(@as(usize, 0), emission_cache.batch(&.{}, 4, 100));
    try std.testing.expectEqual(@as(usize, 2), emission_cache.batch(&.{ 40, 50, 60 }, 4, 100));
    try std.testing.expectEqual(@as(usize, 1), emission_cache.batch(&.{ 400, 40, 50 }, 4, 100));
    try std.testing.expectEqual(@as(usize, 1), emission_cache.batch(&.{ 40, 50, 60 }, 1, 100));
    try std.testing.expectEqual(@as(usize, 1), emission_cache.batch(&.{ 40, 50 }, 0, 0));
    try std.testing.expectEqual(@as(usize, 4096), emission_cache.weight(0));
    try std.testing.expectEqual(std.math.maxInt(usize), emission_cache.weight(std.math.maxInt(usize)));
}

const KeyFixture = struct { module: ir.Module, root: u32, callee: u32 };

fn keyFixture(a: std.mem.Allocator, shifted: bool) !KeyFixture {
    var module: ir.Module = .{};
    if (shifted) {
        try module.compounds.append(a, .{ .box = .str });
        try module.strings.append(a, "unrelated");
        var padding = try support.Hand.init(a, &module, "unused", .{ .params = &.{}, .ret = .i64 });
        _ = try padding.emit(.{ .op = .ret, .ty = .void, .a = try padding.int(.i64, 0) });
        _ = try padding.finish();
    }
    const list = try module.intern(a, .{ .list = .i64 });
    const string = module.strings.items.len;
    try module.strings.append(a, "stable");
    var target = try support.Hand.init(a, &module, "leaf::identity", .{ .params = &.{.i64}, .ret = .i64 });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = try target.param(0) });
    const callee = try target.finish();
    var caller = try support.Hand.init(a, &module, "app::main", .{ .params = &.{}, .ret = .i64 });
    _ = try caller.loose(.{ .op = .undef, .ty = list });
    _ = try caller.loose(.{ .op = .str_const, .ty = .str, .data = string });
    const number = try caller.int(.i64, 19);
    const call = try caller.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(callee), .data = try caller.extra(&.{number}), .span = if (shifted) 111 else 11 });
    _ = try caller.emit(.{ .op = .ret, .ty = .void, .a = call });
    const root = try caller.finish();
    module.entry = root;
    return .{ .module = module, .root = root, .callee = callee };
}

fn fixtureKey(a: std.mem.Allocator, fixture: KeyFixture, given: emitter.Options) !emission_key.Digest {
    var options = given;
    const catalog = try constants.Catalog.init(a, &fixture.module);
    const summaries = try @import("effects.zig").analyze(a, &fixture.module);
    if (options.analysis.effects == null) options.analysis.effects = &summaries;
    var prepared = try emission_key.Prepared.init(a, &fixture.module, options, &catalog);
    const exported = try a.alloc(bool, fixture.module.functions.items.len);
    @memset(exported, true);
    const symbols = try a.alloc(?[]const u8, exported.len);
    @memset(symbols, null);
    return prepared.key(a, .{ .functions = &.{fixture.root}, .exported = exported, .symbols = symbols, .source_path = options.source_path, .constants = &catalog });
}

const AllocationFeatureKeys = struct { split: emission_key.Digest, whole: emission_key.Digest, compact: emission_key.Digest };

fn allocationFeatureKeys(a: std.mem.Allocator, fixture: *KeyFixture, store: *const stages.Store) !AllocationFeatureKeys {
    const module = &fixture.module;
    const catalog = try constants.Catalog.init(a, module);
    const summaries = try @import("effects.zig").analyze(a, module);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{}, .analysis = .{ .effects = &summaries } };
    var prepared = try emission_key.Prepared.init(a, module, options, &catalog);
    const exported = try a.alloc(bool, module.functions.items.len);
    @memset(exported, true);
    const symbols = try a.alloc(?[]const u8, exported.len);
    @memset(symbols, null);
    const split: emitter.Selection = .{ .functions = &.{fixture.root}, .exported = exported, .symbols = symbols, .source_path = options.source_path, .constants = &catalog };
    const whole: emitter.Selection = .{ .functions = &.{ fixture.callee, fixture.root }, .exported = exported, .symbols = symbols, .source_path = options.source_path, .constants = &catalog, .entry = true };
    const source = try language.source.Source.init(a, "lifetime.selka", "stable source\n");
    var loader: FinalLoaderFixture = .{ .module = module, .bodies = module.functions.items };
    var compact = (try emission_key.Compact.init(a, module, options, &prepared.canon, .{
        .store = store,
        .receipts = .{
            .finals = try receiptFinals(a, module, options.locator),
            .source = &source,
            .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
        },
    })).?;
    return .{ .split = try prepared.key(a, split), .whole = try prepared.key(a, whole), .compact = (try compact.key(a, module, options, split)).? };
}

test "O4 allocation instrumentation rekeys unchanged split whole and compact emission inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var fixture = try keyFixture(a, false);
    const before = try allocationFeatureKeys(a, &fixture, &store);
    const testcount = @import("testcount_runtime.zig");
    try std.testing.expect(!testcount.needed(&fixture.module));
    _ = try @import("test_builder.zig").helper(a, &fixture.module, "unrelated_runtime", &.{}, .i64);
    const unrelated = try allocationFeatureKeys(a, &fixture, &store);
    try std.testing.expect(!testcount.needed(&fixture.module));
    try std.testing.expectEqual(before.split, unrelated.split);
    try std.testing.expectEqual(before.whole, unrelated.whole);
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &fixture.module, .{ .context = &context, .locate = fixedLocation });
    const body = try canon.functionDigest(fixture.root);
    // A testing import adds this declaration without changing the workload IR.
    _ = try @import("test_builder.zig").helper(a, &fixture.module, "myl_core_test_allocations", &.{.bool}, .i64);
    try std.testing.expect(testcount.needed(&fixture.module));
    const measured = try allocationFeatureKeys(a, &fixture, &store);
    try std.testing.expectEqual(body, try canon.functionDigest(fixture.root));
    try std.testing.expect(!std.mem.eql(u8, &unrelated.split, &measured.split));
    try std.testing.expect(!std.mem.eql(u8, &unrelated.whole, &measured.whole));
    try std.testing.expect(!std.mem.eql(u8, &unrelated.compact, &measured.compact));
    try std.testing.expectEqualDeep(measured, try allocationFeatureKeys(a, &fixture, &store));
}

test "O4 cached unchanged workload units adopt allocation counting after a testing import" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, "func main() -> int:\n    mut values = [1, 2]\n    return len(values)\n", &refusal);
    _ = try passes.ownership(a, &module);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{} };
    var cold: emission_cache.Counts = .{};
    const baseline = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .counts = &cold });
    try std.testing.expect(std.mem.indexOf(u8, try textOf(baseline, "lifetime.selka"), "%empty = icmp eq ptr %head, null") != null);
    var warm: emission_cache.Counts = .{};
    try sameUnits(baseline, try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .counts = &warm }));
    try std.testing.expectEqual(cold.units, warm.reused);
    try std.testing.expectEqual(@as(u32, 0), warm.rendered);
    _ = try @import("test_builder.zig").helper(a, &module, "myl_core_test_allocations", &.{.bool}, .i64);
    var changed_counts: emission_cache.Counts = .{};
    const changed_units = try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .counts = &changed_counts });
    try std.testing.expectEqual(@as(u32, 0), changed_counts.reused);
    try std.testing.expectEqual(changed_counts.units, changed_counts.rendered);
    try sameUnits(try units.emitWithScratch(a, std.testing.allocator, &module, options), changed_units);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(changed_units, "lifetime.selka"), "%empty = icmp eq ptr %head, null") == null);
    var counted_warm: emission_cache.Counts = .{};
    try sameUnits(changed_units, try units.emitCached(a, std.testing.allocator, &module, options, .{ .store = &store, .counts = &counted_warm }));
    try std.testing.expectEqual(changed_counts.units, counted_warm.reused);
    try std.testing.expectEqual(@as(u32, 0), counted_warm.rendered);
    const whole = try units.wholeWithScratch(a, std.testing.allocator, &module, options);
    try std.testing.expect(std.mem.indexOf(u8, try programText(whole), "%empty = icmp eq ptr %head, null") == null);
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 emission inputs canonicalize global identities and invalidate effect and inline ancestry changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try keyFixture(a, false);
    const shifted = try keyFixture(a, true);
    const context: u8 = 0;
    var options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{} };
    const first = try fixtureKey(a, original, options);
    try std.testing.expectEqual(first, try fixtureKey(a, shifted, options));
    const changed_effects = try @import("effects.zig").analyze(a, &original.module);
    changed_effects.may[original.callee][0] = !changed_effects.may[original.callee][0];
    options.analysis.effects = &changed_effects;
    try std.testing.expect(!std.mem.eql(u8, &first, &try fixtureKey(a, original, options)));
    options.analysis.effects = null;
    var ancestry: inline_origins.Table = .{};
    try ancestry.frames.append(a, .{ .function = original.callee, .call_span = 11, .parent = null });
    try ancestry.setBlock(a, original.root, 0, 0);
    options.analysis.provenance = &ancestry;
    const inlined = try fixtureKey(a, original, options);
    try std.testing.expect(!std.mem.eql(u8, &first, &inlined));
    try ancestry.frames.append(a, .{ .function = original.root, .call_span = 21, .parent = null });
    ancestry.frames.items[0].parent = 1;
    try std.testing.expect(!std.mem.eql(u8, &inlined, &try fixtureKey(a, original, options)));
}

const FinalLoaderFixture = struct {
    module: *ir.Module,
    bodies: []const ir.Function,
    restored: usize = 0,
    fn ensure(pointer: *anyopaque, index: u32) @import("demand_ir.zig").Error!void {
        const self: *FinalLoaderFixture = @ptrCast(@alignCast(pointer));
        if (self.module.functions.items[index].blocks.items.len != 0) return;
        self.module.functions.items[index] = self.bodies[index];
        self.restored += 1;
    }
    fn restoreAll(self: *FinalLoaderFixture) void {
        for (self.module.functions.items, self.bodies) |*function, body| function.* = body;
    }
    fn hide(self: *FinalLoaderFixture) void {
        self.restored = 0;
        for (self.module.functions.items) |*function| {
            function.insts = .empty;
            function.blocks = .empty;
            function.extra = .empty;
            function.loops = .empty;
        }
    }
};

fn receiptFinals(a: std.mem.Allocator, module: *const ir.Module, locator: emitter.Locator) ![]?optimization.FinalMetadata {
    const finals = try a.alloc(?optimization.FinalMetadata, module.functions.items.len);
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, module, locator);
    for (finals, 0..) |*final, index| {
        const digest = try canon.functionDigest(@intCast(index));
        final.* = .{
            .key = digest,
            .body = .{ .positioned = digest, .plain = digest },
            .render = .{ .ancestry = @splat(0), .scopes = &.{} },
            .outgoing = try @import("optimizer_shortcut.zig").Index.targets(a, &module.functions.items[index]),
            .analysis = .{ .digest = @splat(0), .loop_ids = &.{} },
            .state = .{ .known = null, .plans = &.{}, .counts = .{}, .own = .{} },
        };
    }
    return finals;
}

fn removeExactEmissionArtifacts(a: std.mem.Allocator, artifacts: []const units.Unit, store: *const stages.Store) !void {
    try std.testing.expect(artifacts.len != 0);
    for (artifacts) |unit| try stage_loss.remove(a, store, unit.artifact.?.key);
}

fn sameNativeHandles(expected: []const units.Unit, actual: []const units.Unit) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |left, right| {
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.source_path, right.source_path);
        try std.testing.expectEqual(left.kind, right.kind);
        try std.testing.expectEqualDeep(left.dependencies, right.dependencies);
        try std.testing.expectEqual(@as(usize, 0), right.llvm.len);
        try std.testing.expect(right.artifact != null);
    }
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 emissionJob compact emission receipts leave untouched bodies deferred across unrelated source edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var module = try unitLifetimeModule(a);
    const bodies = try a.dupe(ir.Function, module.functions.items);
    var loader: FinalLoaderFixture = .{ .module = &module, .bodies = bodies };
    const location: u8 = 0;
    const summaries = try @import("effects.zig").analyze(a, &module);
    const options: emitter.Options = .{ .locator = .{ .context = &location, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{}, .analysis = .{ .effects = &summaries } };
    var source = try language.source.Source.init(a, "lifetime.selka", "stable source\n");
    const finals = try receiptFinals(a, &module, options.locator);
    var context: emission_cache.Context = .{
        .store = &store,
        .receipts = .{
            .finals = finals,
            .source = &source,
            .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
        },
        .lanes = 4,
    };
    const expected = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    loader.hide();
    var cold: emission_cache.Counts = .{};
    context.counts = &cold;
    context.native_handles = true;
    try sameUnits(expected, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(usize, 32), loader.restored);
    try std.testing.expectEqual(@as(u32, 33), cold.work.keys_built);
    try std.testing.expect(cold.work.llvm_loaded_bytes > 0);
    context.native_handles = false;
    loader.hide();
    var warm: emission_cache.Counts = .{};
    context.counts = &warm;
    try sameUnits(expected, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
    try std.testing.expectEqual(@as(u32, 0), warm.work.keys_built);
    try std.testing.expectEqual(@as(u32, 33), warm.work.receipts_checked);
    try std.testing.expectEqual(@as(u32, 33), warm.reused);
    bodies[7].insts.items[0].data = 81;
    finals[7].?.key[0] ^= 1;
    finals[7].?.body.positioned[0] ^= 1;
    loader.hide();
    var edited_counts: emission_cache.Counts = .{};
    context.counts = &edited_counts;
    const edited = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(@as(usize, 1), loader.restored);
    try std.testing.expectEqual(@as(u32, 1), edited_counts.work.keys_built);
    try std.testing.expectEqual(@as(u32, 32), edited_counts.reused);
    loader.restoreAll();
    try sameUnits(try units.emitWithScratch(a, std.testing.allocator, &module, options), edited);
    loader.hide();
    source = try language.source.Source.init(a, "lifetime.selka", "edited source\n");
    var moved: emission_cache.Counts = .{};
    context.counts = &moved;
    _ = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
    try std.testing.expectEqual(@as(u32, 0), moved.work.keys_built);
    // Remove exact artifacts while keeping compact receipts. A receipt cannot authorize rendering an empty body, and a
    // receipt whose artifact is gone is a miss, not a failure: the unit is emitted again, in a lazy build (which restores
    // the bodies it needs) as in an eager one, and its artifact is stored again.
    context.native_handles = true;
    const physical = try units.emitCached(a, std.testing.allocator, &module, options, context);
    context.native_handles = false;
    try removeExactEmissionArtifacts(a, physical, &store);
    loader.restoreAll();
    const fresh = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    loader.hide();
    var rebuilt: emission_cache.Counts = .{};
    context.counts = &rebuilt;
    try sameUnits(fresh, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expect(loader.restored > 0);
    try std.testing.expectEqual(@as(u32, 33), rebuilt.rendered);
    loader.hide();
    context.native_handles = true;
    var native_counts: emission_cache.Counts = .{};
    context.counts = &native_counts;
    const handles = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try sameNativeHandles(edited, handles);
    try std.testing.expectEqual(@as(u32, 33), native_counts.work.native_handles);
    try std.testing.expectEqual(@as(u64, 0), native_counts.work.llvm_loaded_bytes);
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
    // A build every receipt answers starts no worker thread and renders no descriptor catalog: nothing in it reads either.
    try std.testing.expectEqual(@as(u32, 0), native_counts.workers);
    try std.testing.expectEqual(@as(u32, 0), native_counts.work.catalogs_built);
    try std.testing.expectEqual(@as(u32, 33), native_counts.reused);
    // One unit whose compact receipt misses (its body is the one the exact key already holds, so it is served and not rendered) is the
    // only job that waits for a worker, and the catalog is rendered once, for its exact key.
    finals[7].?.key[0] ^= 2;
    finals[7].?.body.positioned[0] ^= 2;
    loader.hide();
    var one_miss: emission_cache.Counts = .{};
    context.counts = &one_miss;
    const after_miss = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(handles.len, after_miss.len);
    try std.testing.expectEqual(@as(u32, 1), one_miss.workers);
    try std.testing.expectEqual(@as(u32, 1), one_miss.work.catalogs_built);
    try std.testing.expectEqual(@as(u32, 33), one_miss.reused);
    try std.testing.expectEqual(@as(u32, 0), one_miss.rendered);
    try std.testing.expectEqual(@as(u32, 1), one_miss.work.keys_built);
    try std.testing.expectEqual(@as(u32, 1), cold.work.catalogs_built);
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 compaction after a native-handle build keeps the artifacts the receipts it keeps name, so a later build that needs the text finds them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(io, ".", a);
    var module = try unitLifetimeModule(a);
    const bodies = try a.dupe(ir.Function, module.functions.items);
    var loader: FinalLoaderFixture = .{ .module = &module, .bodies = bodies };
    const location: u8 = 0;
    const summaries = try @import("effects.zig").analyze(a, &module);
    const options: emitter.Options = .{ .locator = .{ .context = &location, .locate = fixedLocation }, .source_path = "lifetime.selka", .main = .{}, .analysis = .{ .effects = &summaries } };
    var source = try language.source.Source.init(a, "lifetime.selka", "stable source\n");
    const finals = try receiptFinals(a, &module, options.locator);
    var context: emission_cache.Context = .{
        .store = undefined,
        .receipts = .{
            .finals = finals,
            .source = &source,
            .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
        },
        .lanes = 4,
        .native_handles = true,
    };
    const expected = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    // The first lazy build stores every artifact and receipt.
    loader.hide();
    {
        var first = try stages.Store.init(std.testing.allocator, io, root);
        defer first.deinit();
        context.store = &first;
        _ = try units.emitCached(a, std.testing.allocator, &module, options, context);
    }
    // A later lazy build is served by the receipts alone: it never loads an artifact.
    loader.hide();
    {
        var warm = try stages.Store.init(std.testing.allocator, io, root);
        defer warm.deinit();
        context.store = &warm;
        var counts: emission_cache.Counts = .{};
        context.counts = &counts;
        _ = try units.emitCached(a, std.testing.allocator, &module, options, context);
        try std.testing.expectEqual(@as(u32, 33), counts.work.native_handles);
        try std.testing.expectEqual(@as(u64, 0), counts.work.llvm_loaded_bytes);
        stage_roots.retain(&warm, a, io, "session", 0);
    }
    // Compaction keeps what that build's roots name, and nothing else.
    {
        var compactor = try stages.Store.init(std.testing.allocator, io, root);
        defer compactor.deinit();
        const ranks = try stage_roots.rank(a, io, root, try std.fs.path.join(a, &.{ root, "stages-packed-v1" }));
        try std.testing.expect((try compactor.storage.compactLive(&ranks, stage_pack.default_band_bytes)) != null);
    }
    // A build that needs the text (the eager retry of a lost native object, or a verifying build) still finds it.
    loader.hide();
    var later = try stages.Store.init(std.testing.allocator, io, root);
    defer later.deinit();
    context.store = &later;
    context.native_handles = false;
    var needed: emission_cache.Counts = .{};
    context.counts = &needed;
    try sameUnits(expected, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(u32, 33), needed.reused);
    try std.testing.expectEqual(@as(u32, 0), needed.rendered);
}

fn scopeReceiptFinals(a: std.mem.Allocator, context: *optimization.Context, options: emitter.Options) ![]?optimization.FinalMetadata {
    const finals = try receiptFinals(a, context.source.module, options.locator);
    for (finals, 0..) |*metadata, index| {
        metadata.*.?.render = try context.renderMetadata(a, @intCast(index), options.analysis.provenance.?);
        try std.testing.expect(metadata.*.?.render != null);
    }
    return finals;
}

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 emissionJob compact receipts track inline declaration locations ancestry and malformed scope IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var module = try unitLifetimeModule(a);
    module.functions.items[2].span = 8;
    const bodies = try a.dupe(ir.Function, module.functions.items);
    var loader: FinalLoaderFixture = .{ .module = &module, .bodies = bodies };
    var source = try language.source.Source.init(a, "lifetime.selka", "aaaaaaaabbbbbbbb\n");
    var ancestry: inline_origins.Table = .{};
    try ancestry.frames.append(a, .{ .function = 2, .call_span = 1, .parent = null });
    try ancestry.setBlock(a, 7, 0, 0);
    const summaries = try @import("effects.zig").analyze(a, &module);
    const options: emitter.Options = .{
        .locator = .{ .context = &source, .locate = locate },
        .source_path = "lifetime.selka",
        .main = .{},
        .analysis = .{ .effects = &summaries, .provenance = &ancestry },
    };
    var optimizer = optimization.Context.init(&store, try @import("ir_snapshot.zig").Context.init(a, &module, source), options.locator);
    try optimizer.prepare(a);
    const finals = try scopeReceiptFinals(a, &optimizer, options);
    var context: emission_cache.Context = .{
        .store = &store,
        .receipts = .{
            .finals = finals,
            .source = &source,
            .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
        },
        .lanes = 2,
    };
    const cold = try units.emitCached(a, std.testing.allocator, &module, options, context);
    loader.hide();
    try sameUnits(cold, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
    // Only the declaration at offset8 moves; the inline call at offset1 stays put.
    source = try language.source.Source.init(a, "lifetime.selka", "aaaa\naaaabbbbbbb\n");
    optimizer.source.source = source;
    loader.hide();
    var moved: emission_cache.Counts = .{};
    context.counts = &moved;
    const relocated = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(@as(usize, 2), loader.restored);
    try std.testing.expectEqual(@as(u32, 2), moved.work.keys_built);
    loader.restoreAll();
    try sameUnits(try units.emitWithScratch(a, std.testing.allocator, &module, options), relocated);
    // A new parent changes debug ancestry even when instructions and source stay put.
    try ancestry.frames.append(a, .{ .function = 3, .call_span = 1, .parent = null });
    ancestry.frames.items[0].parent = 1;
    finals[7].?.render = try optimizer.renderMetadata(a, 7, &ancestry);
    loader.hide();
    var parent: emission_cache.Counts = .{};
    context.counts = &parent;
    const nested = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(@as(usize, 1), loader.restored);
    try std.testing.expectEqual(@as(u32, 1), parent.work.keys_built);
    loader.restoreAll();
    try sameUnits(try units.emitWithScratch(a, std.testing.allocator, &module, options), nested);
    // Malformed compact metadata must fall back to a real body before exact-key reuse.
    finals[7].?.render.?.scopes = &.{std.math.maxInt(u32)};
    loader.hide();
    var invalid: emission_cache.Counts = .{};
    context.counts = &invalid;
    try sameUnits(nested, try units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(usize, 1), loader.restored);
    try std.testing.expectEqual(@as(u32, 1), invalid.work.keys_built);
}

const dict_app =
    \\import leaf
    \\import other
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, leaf.tally(), other.probe("bravo"))
    \\    return 0
    \\
;

const dict_leaf =
    \\
    \\public func tally() -> int:
    \\    mut counts: dict[str, int] = {}
    \\    counts["alpha"] = 1
    \\    return len(counts)
    \\
;

const dict_other =
    \\
    \\public func probe(seq: str) -> int:
    \\    mut counts: dict[str, int] = {}
    \\    counts[copy(seq)] = 1
    \\    if seq[0:2] in counts:
    \\        return 1
    \\    return 0
    \\
;

/// The `find_span` definitions and call sites in one unit's text.
const SpanUses = struct { defined: usize = 0, called: usize = 0 };

fn spanUses(text: []const u8) SpanUses {
    var uses: SpanUses = .{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, ".find_span(ptr ") == null) continue;
        if (std.mem.startsWith(u8, line, "define ")) uses.defined += 1 else uses.called += 1;
    }
    return uses;
}

test "a unit defines a dictionary's span helper only when its own code looks a borrowed span up" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Both modules use one dictionary type; only `other` probes it with a borrowed slice.
    const emitted = try snapshotFor(a, .{ dict_app, dict_leaf, dict_other }, .optimized);
    const leaf_uses = spanUses(try textOf(emitted, "leaf.selka"));
    try std.testing.expectEqual(@as(usize, 0), leaf_uses.defined);
    try std.testing.expectEqual(@as(usize, 0), leaf_uses.called);
    const other_uses = spanUses(try textOf(emitted, "other.selka"));
    try std.testing.expectEqual(@as(usize, 1), other_uses.defined);
    try std.testing.expect(other_uses.called >= 1);
}

test "a unit's link dependencies follow the symbols its text names, found in one scan" {
    const math = @import("emit_units.zig").unit("m", "m.selka", .module, "  %x = call double @llvm.sin.f64(double %y)\n");
    try std.testing.expect(math.dependencies.math);
    try std.testing.expect(!math.dependencies.counting);
    const counting = @import("emit_units.zig").unit("c", "c.selka", .module, "declare i64 @myl_count_current()\n");
    try std.testing.expect(counting.dependencies.counting);
    try std.testing.expect(!counting.dependencies.math);
    const counted = @import("emit_units.zig").unit("t", "t.selka", .module, "  call void @myl_core_test_allocations()\n");
    try std.testing.expect(counted.dependencies.test_counts);
    const plain = @import("emit_units.zig").unit("p", "p.selka", .module, "define i32 @main() { ret i32 0 }\n");
    try std.testing.expect(!plain.dependencies.math and !plain.dependencies.counting and !plain.dependencies.test_counts);
}

/// A module of `app::main` and two functions a device hook can bind, made in `names` order: the hook `start` binds the one at index 1.
fn hookedModule(a: std.mem.Allocator, names: [2][]const u8) !ir.Module {
    var module: ir.Module = .{};
    var main = try support.Hand.init(a, &module, "app::main", .{ .params = &.{}, .ret = .i64 });
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    module.entry = try main.finish();
    for (names) |name| {
        var hook = try support.Hand.init(a, &module, name, .{ .params = &.{.i64}, .ret = .i64 });
        _ = try hook.emit(.{ .op = .ret, .ty = .void, .a = try hook.param(0) });
        _ = try hook.finish();
    }
    return module;
}

const EntryKeys = struct { exact: emission_key.Digest, compact: emission_key.Digest };

/// The exact key and the compact receipt of the entry unit of `module` (the functions in name order, as the partition lists them)
/// when the device binds the hooks named `hooks`.
fn entryKeys(a: std.mem.Allocator, module: *ir.Module, hooks: []const []const u8, store: *const stages.Store) !EntryKeys {
    const catalog = try constants.Catalog.init(a, module);
    const summaries = try @import("effects.zig").analyze(a, module);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "board.selka", .main = .{ .hooks = hooks }, .analysis = .{ .effects = &summaries } };
    var prepared = try emission_key.Prepared.init(a, module, options, &catalog);
    const exported = try a.alloc(bool, module.functions.items.len);
    @memset(exported, true);
    const symbols = try a.alloc(?[]const u8, exported.len);
    @memset(symbols, null);
    const by_name = try a.dupe(u32, &.{ 0, 1, 2 });
    std.mem.sort(u32, by_name, module, struct {
        fn before(m: *ir.Module, left: u32, right: u32) bool {
            return std.mem.lessThan(u8, m.functions.items[left].name, m.functions.items[right].name);
        }
    }.before);
    const selection: emitter.Selection = .{ .functions = by_name, .exported = exported, .symbols = symbols, .source_path = options.source_path, .constants = &catalog, .entry = true };
    const source = try language.source.Source.init(a, "board.selka", "stable source\n");
    var loader: FinalLoaderFixture = .{ .module = module, .bodies = module.functions.items };
    var compact = (try emission_key.Compact.init(a, module, options, &prepared.canon, .{
        .store = store,
        .receipts = .{
            .finals = try receiptFinals(a, module, options.locator),
            .source = &source,
            .loader = .{ .pointer = &loader, .ensure_fn = FinalLoaderFixture.ensure },
        },
    })).?;
    return .{ .exact = try prepared.key(a, selection), .compact = (try compact.key(a, module, options, selection)).? };
}

test "the function a device hook binds is an input of the entry unit's key and its compact receipt, and a program without hooks keys the same" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stages.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    // The same three functions in two orders: the hook `start` binds `board::start_a` in one program and `board::start_b` in the other.
    var first = try hookedModule(a, .{ "board::start_a", "board::start_b" });
    var second = try hookedModule(a, .{ "board::start_b", "board::start_a" });
    const unhooked = try entryKeys(a, &first, &.{}, &store);
    try std.testing.expectEqualDeep(unhooked, try entryKeys(a, &second, &.{}, &store));
    const bound_first = try entryKeys(a, &first, &.{"start"}, &store);
    const bound_second = try entryKeys(a, &second, &.{"start"}, &store);
    try std.testing.expect(!std.mem.eql(u8, &bound_first.exact, &bound_second.exact));
    try std.testing.expect(!std.mem.eql(u8, &bound_first.compact, &bound_second.compact));
    try std.testing.expect(!std.mem.eql(u8, &bound_first.exact, &unhooked.exact));
    try std.testing.expectEqualDeep(bound_first, try entryKeys(a, &first, &.{"start"}, &store));
}

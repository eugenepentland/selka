//! Unit purity, stable names and native linking across actual source modules.
const std = @import("std");
const language = @import("mylang");
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

const app = "import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    out.print(leaf.compute(7), other.compute(3))\n    return 0\n";
const leaf = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    return total\n";
const other = "\npublic func compute(x: int) -> int:\n    return x + 1\n";
const Mode = enum { debug, release, verify };

fn releaseUnits(a: std.mem.Allocator, emitted: []units.Unit) void {
    for (emitted) |unit| {
        a.free(unit.name);
        a.free(unit.source_path);
        a.free(unit.llvm);
    }
    a.free(emitted);
}

fn fixedLocation(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "lifetime.my", .line = 1, .column = 1 };
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
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.my", .main = .{} };
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
        try std.testing.expectEqualStrings("lifetime.my", left.source_path);
        try std.testing.expectEqualStrings(left.llvm, right.llvm);
    }
    const whole = try units.wholeWithScratch(std.testing.allocator, std.testing.allocator, &module, options);
    defer releaseUnits(std.testing.allocator, whole);
    try std.testing.expectEqual(@as(usize, 1), whole.len);
    try std.testing.expectEqualStrings("program", whole[0].name);
    try std.testing.expectEqualStrings("lifetime.my", whole[0].source_path);
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
    const names = [_][]const u8{ "app.my", "leaf.my", "other.my" };
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
        .source_path = "app.my",
        .main = .{ .parameters = &.{"out"}, .result = if (shape) |s| .{ .ok_tag = @intCast(s.ok_tag), .error_tag = @intCast(s.error_tag) } else null },
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance },
        .verify = mode == .verify,
    };
    // S4-1a: release and verify builds are one whole-program unit, as the pipeline emits them.
    return if (mode == .debug) units.emit(a, &module, options) else units.whole(a, &module, options);
}

fn programText(emitted: []const units.Unit) ![]const u8 {
    if (emitted.len != 1 or emitted[0].kind != .program) return error.MissingUnit;
    return emitted[0].llvm;
}

fn textOf(emitted: []const units.Unit, path: []const u8) ![]const u8 {
    for (emitted) |unit| if (unit.kind == .module and std.mem.eql(u8, unit.source_path, path)) return unit.llvm;
    return error.MissingUnit;
}

fn numericHelper(emitted: []const units.Unit) bool {
    for (emitted) |unit| if (unit.kind == .helper and unit.dependencies.number) return true;
    return false;
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
    try std.testing.expectError(error.MissingUnit, textOf(first, "missing.my"));
    try changed(first, try snapshot(a, .{ app, leaf, other }, false), &.{});
    const body = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i * 2\n    return total\n";
    try changed(first, try snapshot(a, .{ app, body, other }, false), &.{"leaf.my"});
    const check = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    assert total >= 0, \"sum\"\n    return total\n";
    try changed(first, try snapshot(a, .{ app, check, other }, false), &.{"leaf.my"});
    const shifted = "\n\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    return total\n";
    try changed(first, try snapshot(a, .{ app, shifted, other }, false), &.{"leaf.my"});
    const leaf_text = try textOf(first, "leaf.my");
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "!DIFile(filename: \"leaf.my\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "@myl_core_sites") == null);
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
    for ([_][]const u8{ "app.my", "leaf.my", "other.my" }) |path| _ = try textOf(debug, path);
    _ = try entryText(debug);
    const result = try native(a, release);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("21 4\n", result.stdout);
}

fn native(a: std.mem.Allocator, emitted: []const units.Unit) !std.process.RunResult {
    return nativeArgs(a, emitted, &.{});
}

fn nativeArgs(a: std.mem.Allocator, emitted: []const units.Unit, arguments: []const []const u8) !std.process.RunResult {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const output = try std.fs.path.join(a, &.{ root, "program" });
    var log: std.ArrayList(u8) = .empty;
    _ = driver.link(a, std.testing.io, &environment, .{ .zig = environment.get("ZIG") orelse "zig", .work = root, .output = output, .mode = .release, .links = &.{}, .units = emitted }, &log) catch |err| {
        report("unit native build: {s}\n", .{log.items});
        return err;
    };
    const argv = try a.alloc([]const u8, arguments.len + 1);
    argv[0] = output;
    @memcpy(argv[1..], arguments);
    return std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 numeric buffer operations declare reached helpers in owner and imported units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main(out: Stream) -> int:\n    for i in range(1):\n" ++
        "        const buffer = leaf.formatted()\n        out.print(len(buffer), buffer[0], buffer[1], buffer[2], buffer[3], buffer[4])\n    return 0\n";
    const formatted = "public func formatted() -> byte_buffer:\n    mut empty: int[] = []\n" ++
        "    mut buffer = byte_buffer(empty)\n    _ = buffer.append_int(-7)\n    _ = buffer.append_float(1.5)\n    return buffer\n";
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const emitted = try snapshotFor(a, .{ caller, formatted, other }, mode);
        const result = try native(a, emitted);
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("5 45 55 49 46 53\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        for (emitted) |unit| if (std.mem.eql(u8, unit.source_path, "other.my")) try std.testing.expect(!unit.dependencies.number);
    }
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 integer-only numeric buffer operations avoid the float helper dependency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const integer_caller = "import leaf\nfunc main(out: Stream) -> int:\n" ++
        "    const buffer = leaf.formatted()\n    out.print(len(buffer), buffer[0], buffer[1])\n    return 0\n";
    const integer = "public func formatted() -> byte_buffer:\n    mut empty: int[] = []\n" ++
        "    mut buffer = byte_buffer(empty)\n    _ = buffer.append_int(-7)\n    return buffer\n";
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:3:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:5:") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:2:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:3:12") != null);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 an inlined cross-module Result origin retains its source function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> Result[int, str]:\n    mut value = try leaf.origin()\n    return Ok(value)\n";
    const failing = "public func origin() -> Result[int, str]:\n    return Err(\"leaf failure\")\n";
    for ([_]bool{ false, true }) |release| {
        const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("error: leaf failure\n  leaf.my:2:12  leaf::origin  Err(...) created\n  app.my:3:17   app::main     try propagated\n", result.stderr);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 Result origins distinguish specializations sharing one declaration and body span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main(args: str[]) -> Result[int, str]:\n" ++
        "    if len(args) == 0:\n        const integer = try leaf.origin[int](1)\n        return Ok(integer)\n" ++
        "    const text = try leaf.origin[str](\"x\")\n    return Ok(len(text))\n";
    const failing = "public func origin[T](x: T) -> Result[T, str]:\n    return Err(\"leaf failure\")\n";
    for ([_]bool{ false, true }) |release| {
        const emitted = try snapshot(a, .{ caller, failing, other }, release);
        for ([_][]const []const u8{ &.{}, &.{"string"} }, [_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }) |arguments, function| {
            const result = try nativeArgs(a, emitted, arguments);
            try std.testing.expect(result.term == .exited and result.term.exited == 1);
            if (std.mem.indexOf(u8, result.stderr, function) == null) report("specialization origin expected {s}: {s}", .{ function, result.stderr });
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, function) != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:2:12") != null);
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
    const rendering = "\npublic func compute(x: int) -> int:\n    mut values = {(1, 2): [3.5, 4.25]}\n    return len(f\"{values}\") + x\n";
    const before = try snapshot(a, .{ app, rendering, other }, false);
    const noise =
        \\public func identity[T](x: T) -> T:
        \\    return x
        \\public func compute(x: int) -> int:
        \\    mut values = {("@myl.value.999", x): [(True, x, "noise")]}
        \\    mut text = f"{values}"
        \\    assert len(text) > 0
        \\    return identity[int](x) + 1
    ;
    const after = try snapshot(a, .{ app, rendering, noise }, false);
    try preserved(before, after, "leaf.my");
    try std.testing.expectEqualStrings(try textOf(before, "app.my"), try textOf(after, "app.my"));
    const noisy = try textOf(after, "other.my");
    try std.testing.expect(std.mem.indexOf(u8, noisy, "c\"@myl.value.999") != null);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 a float renderer outside entry carries the formatter link dependency on its helper unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rendering = "\npublic func compute(x: int) -> int:\n    mut values = [1.25, 2.5]\n    return len(f\"{values}\") + x\n";
    const emitted = try snapshot(a, .{ app, rendering, other }, false);
    var helper_number = false;
    for (emitted) |unit| {
        helper_number = helper_number or (unit.kind == .helper and unit.dependencies.number);
    }
    try std.testing.expect(helper_number);
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
    const caller = "import leaf\nimport other\nfunc main(out: Stream) -> int:\n    out.print(leaf.render(1), other.render(2))\n    return 0\n";
    const left = "public record Cell:\n    value: int\npublic func render(x: int) -> str:\n    return f\"{Cell(value=x)}\"\n";
    const right = "public record Cell:\n    value: int\npublic func render(x: int) -> str:\n    return f\"{Cell(value=x)}\"\n";
    const emitted = try snapshot(a, .{ caller, left, right }, false);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("Cell(value=1) Cell(value=2)\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    for (emitted, 0..) |unit, index| {
        for (emitted[index + 1 ..]) |next| try std.testing.expect(!std.mem.eql(u8, unit.name, next.name));
    }
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
        \\    out.print(value.a, value.f)
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
    const body = try textOf(emitted, "other.my");
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
    const failing = "public func origin(x: int) -> Result[int, str]:\n    return Err(\"loop failure\")\n";
    const emitted = try snapshot(a, .{ caller, failing, other }, true);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("error: loop failure\n  leaf.my:2:12  leaf::origin  Err(...) created\n  app.my:4:23   app::main     try propagated\n", result.stderr);
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
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in leaf::origin at leaf.my:2:") != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:3:12") != null);
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
            .body = "    return xs[x]\n",
            .expected = "leaf.my:3:12: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n" ++
                "  in leaf::origin at leaf.my:3:12\n  in app::main at app.my:4:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":2,\"length\":2}\n",
        },
        .{
            .argument = "1",
            .body = "    assert x == 0, \"mut check\"\n    return x\n",
            .expected = "leaf.my:3:12: error[R_ASSERT]: native execution failed: mut check\n" ++
                "  in leaf::origin at leaf.my:3:12\n  in app::main at app.my:4:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"mut check\"}\n",
        },
        .{
            .argument = "9223372036854775807",
            .body = "    if x < 0:\n        return 0\n    return x + 1\n",
            .expected = "leaf.my:5:14: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 1, width 64)\n" ++
                "  in leaf::origin at leaf.my:5:14\n  in app::main at app.my:4:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":1,\"width\":64}\n",
        },
    };
    for (cases) |case| {
        const caller = try std.fmt.allocPrint(a, "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.origin(mut xs, {s})\n", .{case.argument});
        const callee = try std.fmt.allocPrint(a, "public func origin(mut xs: int[], x: int) -> int:\n    xs.append(2)\n{s}", .{case.body});
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
    const callee = "public func origin[T](mut xs: int[], tag: T, x: int) -> int:\n    xs.append(2)\n    return xs[x]\n";
    for ([_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }, [_][]const []const u8{ &.{}, &.{"text"} }, [_][]const u8{ "app.my:5:16", "app.my:6:12" }) |name, arguments, position| {
        const ran = try nativeArgs(a, try snapshot(a, .{ caller, callee, other }, true), arguments);
        try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, name) != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "at leaf.my:3:12") != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, position) != null);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 nested consuming helpers retain all frames under fact verification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.middle(mut xs, 2)\n";
    const callee = "public func origin(mut xs: int[], x: int) -> int:\n    xs.append(2)\n    return xs[x]\n" ++
        "public func middle(mut xs: int[], x: int) -> int:\n    if x < 0:\n        return 0\n    return origin(mut xs, x)\n";
    const ran = try native(a, try snapshotFor(a, .{ caller, callee, other }, .verify));
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::origin at leaf.my:3:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::middle at leaf.my:7:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in app::main at app.my:4:12") != null);
}

const stages = @import("stage_store.zig");
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
        const path = try std.fmt.allocPrint(a, "{s}/{s}.stage", .{ store.root, std.fmt.bytesToHex(handle.key, .lower) });
        try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
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
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.my", .main = .{} };
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
    var module = try support.buildSource(a, "func main(out: Stream) -> int:\n    const values = [1.25, 2.5]\n    out.print(f\"{values}\")\n    return 0\n", &refusal);
    var wave = try support.Hand.init(a, &module, "wave", .{ .params = &.{.f64}, .ret = .f64 });
    const sine = try wave.emit(.{ .op = .float_unary, .ty = .f64, .a = try wave.param(0), .data = @backingInt(ir.FloatUnary.sin) });
    _ = try wave.emit(.{ .op = .ret, .ty = .void, .a = sine });
    _ = try wave.finish();
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.my", .main = .{ .parameters = &.{"out"} }, .counters = true };
    const fresh = try units.emitWithScratch(a, std.testing.allocator, &module, options);
    const source = try language.source.Source.init(a, "lifetime.my", "helper source");
    var loader: FinalLoaderFixture = .{ .module = &module, .bodies = try a.dupe(ir.Function, module.functions.items) };
    const receipt_context: emission_cache.ReceiptContext = .{
        .finals = try receiptFinals(a, &module, options.locator),
        .source = &source,
        .layout = try @import("ir_snapshot.zig").layout(a, try @import("ir_snapshot.zig").Context.init(a, &module, source)),
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
    try std.testing.expect(numericHelper(repeated));
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
    var module = try support.buildSource(a, "func sum(xs: int[]) -> int:\n    mut total = 0\n    for x in xs:\n        total += x\n    return total\n\nfunc main() -> int:\n    return sum([1, 2, 3])\n", &refusal);
    const result = try passes.runWithScratch(a, std.testing.allocator, &module, .trusted);
    const context: u8 = 0;
    var options: emitter.Options = .{
        .locator = .{ .context = &context, .locate = fixedLocation },
        .source_path = "lifetime.my",
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

// spec-case: NEW-CORE-STAGE-CACHE-5
test "S4 emission inputs canonicalize global identities and invalidate effect and inline ancestry changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try keyFixture(a, false);
    const shifted = try keyFixture(a, true);
    const context: u8 = 0;
    var options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "lifetime.my", .main = .{} };
    const first = try fixtureKey(a, original, options);
    try std.testing.expectEqual(first, try fixtureKey(a, shifted, options));
    const changed_effects = try @import("effects.zig").analyze(a, &original.module);
    changed_effects.may[original.callee][0] = !changed_effects.may[original.callee][0];
    options.analysis.effects = &changed_effects;
    try std.testing.expect(!std.mem.eql(u8, &first, &try fixtureKey(a, original, options)));
    options.analysis.effects = null;
    var ancestry: @import("inline_origins.zig").Table = .{};
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

fn receiptFinals(a: std.mem.Allocator, module: *const ir.Module, locator: emitter.Locator) ![]?@import("optimization_cache.zig").FinalMetadata {
    const finals = try a.alloc(?@import("optimization_cache.zig").FinalMetadata, module.functions.items.len);
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, module, locator);
    for (finals, 0..) |*final, index| {
        const digest = try canon.functionDigest(@intCast(index));
        final.* = .{
            .key = digest,
            .body = digest,
            .outgoing = try @import("optimizer_shortcut.zig").Index.targets(a, &module.functions.items[index]),
            .analysis = .{ .digest = @splat(0), .loop_ids = &.{} },
            .state = .{ .known = null, .plans = &.{}, .counts = .{}, .own = .{} },
        };
    }
    return finals;
}

fn removeExactEmissionArtifacts(a: std.mem.Allocator, directory: std.Io.Dir, store: *const stages.Store) !void {
    var files = try directory.openDir(std.testing.io, "stages-v1", .{ .iterate = true });
    defer files.close(std.testing.io);
    var iterator = files.iterate();
    var removals: std.ArrayList([]const u8) = .empty;
    while (try iterator.next(std.testing.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".stage")) continue;
        var digest: stages.Digest = undefined;
        _ = try std.fmt.hexToBytes(&digest, entry.name[0..64]);
        if (try store.loadValue(a, digest, emission_cache.Receipt) == null)
            try removals.append(a, try a.dupe(u8, entry.name));
    }
    try std.testing.expect(removals.items.len != 0);
    for (removals.items) |name| try files.deleteFile(std.testing.io, name);
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
test "S4 emissionJob compact emission receipts leave untouched final bodies deferred and reject changed source" {
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
    const options: emitter.Options = .{ .locator = .{ .context = &location, .locate = fixedLocation }, .source_path = "lifetime.my", .main = .{}, .analysis = .{ .effects = &summaries } };
    var source = try language.source.Source.init(a, "lifetime.my", "stable source\n");
    const finals = try receiptFinals(a, &module, options.locator);
    var context: emission_cache.Context = .{
        .store = &store,
        .receipts = .{
            .finals = finals,
            .source = &source,
            .layout = try @import("ir_snapshot.zig").layout(a, try @import("ir_snapshot.zig").Context.init(a, &module, source)),
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
    finals[7].?.body[0] ^= 1;
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
    source = try language.source.Source.init(a, "lifetime.my", "edited source\n");
    var moved: emission_cache.Counts = .{};
    context.counts = &moved;
    _ = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try std.testing.expectEqual(@as(usize, 32), loader.restored);
    try std.testing.expectEqual(@as(u32, 32), moved.work.keys_built);
    // Remove exact artifacts while keeping compact receipts. A receipt cannot
    // authorize rendering an empty body: the coordinator must retry eagerly.
    try removeExactEmissionArtifacts(a, directory.dir, &store);
    loader.hide();
    try std.testing.expectError(error.CacheMiss, units.emitCached(a, std.testing.allocator, &module, options, context));
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
    context.native_handles = true;
    var native_counts: emission_cache.Counts = .{};
    context.counts = &native_counts;
    const handles = try units.emitCached(a, std.testing.allocator, &module, options, context);
    try sameNativeHandles(edited, handles);
    try std.testing.expectEqual(@as(u32, 33), native_counts.work.native_handles);
    try std.testing.expectEqual(@as(u64, 0), native_counts.work.llvm_loaded_bytes);
    try std.testing.expectEqual(@as(usize, 0), loader.restored);
}

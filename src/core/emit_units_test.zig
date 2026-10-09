//! Unit purity, stable names and native linking across actual source modules.
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const emitter = @import("emit_llvm.zig");
const units = @import("emit_units.zig");
const driver = @import("driver.zig");
const report = std.debug.print;

const app = "import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    out.print(leaf.compute(7), other.compute(3))\n    return 0\n";
const leaf = "\npublic func compute(x: int) -> int:\n    mut total = 0\n    for i in range(x):\n        total += i\n    return total\n";
const other = "\npublic func compute(x: int) -> int:\n    return x + 1\n";
const Mode = enum { debug, release, verify };

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
    for (emitted) |unit| if (unit.kind == .helper and unit.number) return true;
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
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
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
        for (emitted) |unit| if (std.mem.eql(u8, unit.source_path, "other.selka")) try std.testing.expect(!unit.number);
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
    for (emitted) |unit| try std.testing.expect(!unit.number);
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
    const failing = "public func origin() -> Result[int, str]:\n    return Err(\"leaf failure\")\n";
    for ([_]bool{ false, true }) |release| {
        const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("error: leaf failure\n  leaf.selka:2:12  leaf::origin  Err(...) created\n  app.selka:3:17   app::main     try propagated\n", result.stderr);
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
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.selka:2:12") != null);
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
    try preserved(before, after, "leaf.selka");
    try std.testing.expectEqualStrings(try textOf(before, "app.selka"), try textOf(after, "app.selka"));
    const noisy = try textOf(after, "other.selka");
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
        helper_number = helper_number or (unit.kind == .helper and unit.number);
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
    const failing = "public func origin(x: int) -> Result[int, str]:\n    return Err(\"loop failure\")\n";
    const emitted = try snapshot(a, .{ caller, failing, other }, true);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("error: loop failure\n  leaf.selka:2:12  leaf::origin  Err(...) created\n  app.selka:4:23   app::main     try propagated\n", result.stderr);
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
            .body = "    return xs[x]\n",
            .expected = "leaf.selka:3:12: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n" ++
                "  in leaf::origin at leaf.selka:3:12\n  in app::main at app.selka:4:12\n" ++
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
    const callee = "public func origin(mut xs: int[], x: int) -> int:\n    xs.append(2)\n    return xs[x]\n" ++
        "public func middle(mut xs: int[], x: int) -> int:\n    if x < 0:\n        return 0\n    return origin(mut xs, x)\n";
    const ran = try native(a, try snapshotFor(a, .{ caller, callee, other }, .verify));
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::origin at leaf.selka:3:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::middle at leaf.selka:7:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in app::main at app.selka:4:12") != null);
}

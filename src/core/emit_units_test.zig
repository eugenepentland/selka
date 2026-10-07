//! Unit purity, stable names and native linking across actual source modules.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const emitter = @import("emit_llvm.zig");
const units = @import("emit_units.zig");
const driver = @import("driver.zig");
const report = std.debug.print;

const app = "module app\nimport leaf\nimport other\n\ndef main(out: Stream) -> int:\n    out.print(leaf.compute(7), other.compute(3))\n    return 0\n";
const leaf = "module leaf\n\npublic def compute(x: int) -> int:\n    total = 0\n    for i in range(x):\n        total += i\n    return total\n";
const other = "module other\n\npublic def compute(x: int) -> int:\n    return x + 1\n";

fn locate(context: *const anyopaque, offset: u32) emitter.Location {
    const src: *const language.source.Source = @ptrCast(@alignCast(context));
    const at = frontend.position(src.*, .{ .start = offset, .end = offset });
    return .{ .path = at.path, .line = at.line, .column = at.column };
}

fn snapshot(a: std.mem.Allocator, sources: [3][]const u8, release: bool) ![]units.Unit {
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
    const result = if (release) try passes.run(a, &module, .trusted) else passes.Result{ .known = &.{}, .plans = &.{} };
    if (!release) _ = try passes.ownership(a, &module);
    const main = checked.program.functions[@backingInt(checked.program.main)];
    const shape = language.typed.resultShape(main.signature.return_type, checked.program.records);
    return units.emit(a, &module, .{
        .locator = .{ .context = &checked.src, .locate = locate },
        .source_path = "app.my",
        .main = .{ .parameters = &.{"out"}, .result = if (shape) |s| .{ .ok_tag = @intCast(s.ok_tag), .error_tag = @intCast(s.error_tag) } else null },
        .facts = result.known,
        .vectors = result.plans,
    });
}

fn textOf(emitted: []const units.Unit, path: []const u8) ![]const u8 {
    for (emitted) |unit| if (unit.kind == .module and std.mem.eql(u8, unit.source_path, path)) return unit.llvm;
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
            for (expected) |path| if (std.mem.eql(u8, unit.source_path, path) and unit.kind == .module) {
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
    const body = "module leaf\n\npublic def compute(x: int) -> int:\n    total = 0\n    for i in range(x):\n        total += i * 2\n    return total\n";
    try changed(first, try snapshot(a, .{ app, body, other }, false), &.{"leaf.my"});
    const check = "module leaf\n\npublic def compute(x: int) -> int:\n    total = 0\n    for i in range(x):\n        total += i\n    assert total >= 0, \"sum\"\n    return total\n";
    try changed(first, try snapshot(a, .{ app, check, other }, false), &.{"leaf.my"});
    const shifted = "module leaf\n\n\npublic def compute(x: int) -> int:\n    total = 0\n    for i in range(x):\n        total += i\n    return total\n";
    try changed(first, try snapshot(a, .{ app, shifted, other }, false), &.{"leaf.my"});
    const leaf_text = try textOf(first, "leaf.my");
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "define hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "!DIFile(filename: \"leaf.my\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, leaf_text, "@myl_core_sites") == null);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 an inlined public helper changes its own unit and caller with no unrelated text ripple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try snapshot(a, .{ app, leaf, other }, true);
    const updated = "module other\n\npublic def compute(x: int) -> int:\n    return x + 2\n";
    try changed(first, try snapshot(a, .{ app, leaf, updated }, true), &.{ "app.my", "other.my" });
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
    driver.link(a, std.testing.io, &environment, .{ .zig = environment.get("ZIG") orelse "zig", .work = root, .output = output, .release = true, .links = &.{}, .units = emitted }, &log) catch |err| {
        report("unit native build: {s}\n", .{log.items});
        return err;
    };
    const argv = try a.alloc([]const u8, arguments.len + 1);
    argv[0] = output;
    @memcpy(argv[1..], arguments);
    return std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
}

// spec: NEW-CORE-S4-SITES-1
test "S4 native cross-unit traps carry their source path and callers through all compile units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failing = "module leaf\n\npublic def compute(x: int) -> int:\n    assert x == 0, \"leaf check\"\n    return x\n";
    const result = try native(a, try snapshot(a, .{ app, failing, other }, false));
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:4:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:6:") != null);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 a release tail-position cross-unit trap retains its caller frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main() -> int:\n    return leaf.compute(7)\n";
    const failing = "module leaf\npublic def compute(x: int) -> int:\n    assert x == 0, \"leaf check\"\n    return x\n";
    const result = try native(a, try snapshot(a, .{ caller, failing, other }, true));
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:3:12: error[R_ASSERT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:4:12") != null);
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 an inlined cross-module Result origin retains its source function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main() -> Result[int, str]:\n    value = leaf.origin()?\n    return Ok(value)\n";
    const failing = "module leaf\npublic def origin() -> Result[int, str]:\n    return Err(\"leaf failure\")\n";
    for ([_]bool{ false, true }) |release| {
        const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("error: leaf failure\n  leaf.my:3:12  leaf::origin  Err(...) created\n  app.my:4:13   app::main     ? propagated\n", result.stderr);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 Result origins distinguish specializations sharing one declaration and body span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main(args: list[str]) -> Result[int, str]:\n" ++
        "    if len(args) == 0:\n        integer = leaf.origin[int](1)?\n        return Ok(integer)\n" ++
        "    text = leaf.origin[str](\"x\")?\n    return Ok(len(text))\n";
    const failing = "module leaf\npublic def origin[T](x: T) -> Result[T, str]:\n    return Err(\"leaf failure\")\n";
    for ([_]bool{ false, true }) |release| {
        const emitted = try snapshot(a, .{ caller, failing, other }, release);
        for ([_][]const []const u8{ &.{}, &.{"string"} }, [_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }) |arguments, function| {
            const result = try nativeArgs(a, emitted, arguments);
            try std.testing.expect(result.term == .exited and result.term.exited == 1);
            if (std.mem.indexOf(u8, result.stderr, function) == null) report("specialization origin expected {s}: {s}", .{ function, result.stderr });
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, function) != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "leaf.my:3:12") != null);
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
    const rendering = "module leaf\n\npublic def compute(x: int) -> int:\n    values = {(1, 2): [3.5, 4.25]}\n    return len(f\"{values}\") + x\n";
    const before = try snapshot(a, .{ app, rendering, other }, false);
    const noise =
        \\module other
        \\public def identity[T](x: T) -> T:
        \\    return x
        \\public def compute(x: int) -> int:
        \\    values = {("@myl.value.999", x): [(True, x, "noise")]}
        \\    text = f"{values}"
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
    const rendering = "module leaf\n\npublic def compute(x: int) -> int:\n    values = [1.25, 2.5]\n    return len(f\"{values}\") + x\n";
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
    const caller = "module app\nimport leaf\nimport other\ndef main(out: Stream) -> int:\n    out.print(leaf.render(1), other.render(2))\n    return 0\n";
    const left = "module leaf\npublic record Cell:\n    value: int\npublic def render(x: int) -> str:\n    return f\"{Cell(x)}\"\n";
    const right = "module other\npublic record Cell:\n    value: int\npublic def render(x: int) -> str:\n    return f\"{Cell(x)}\"\n";
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
        \\module app
        \\import leaf
        \\import other
        \\def main(out: Stream) -> int:
        \\    value = other.apply(leaf.grow, leaf.make(7))
        \\    out.print(value.a, value.f)
        \\    return 0
    ;
    const aggregate =
        \\module leaf
        \\public record Big:
        \\    a: int
        \\    b: int
        \\    c: int
        \\    d: int
        \\    e: int
        \\    f: int
        \\public def make(x: int) -> Big:
        \\    return Big(x, 2, 3, 4, 5, 6)
        \\public def grow(value: Big) -> Big:
        \\    return Big(value.a + 1, value.b, value.c, value.d, value.e, value.f)
    ;
    const indirect =
        \\module other
        \\import leaf
        \\public def apply(callback: def(leaf.Big) -> leaf.Big, value: leaf.Big) -> leaf.Big:
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

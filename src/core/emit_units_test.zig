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
    return units.emit(a, &module, .{
        .locator = .{ .context = &checked.src, .locate = locate },
        .source_path = "app.my",
        .main = .{ .parameters = &.{"out"}, .result = if (shape) |s| .{ .ok_tag = @intCast(s.ok_tag), .error_tag = @intCast(s.error_tag) } else null },
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance },
        .verify = mode == .verify,
    });
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

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 numeric buffer operations declare reached helpers in owner and imported units" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main(out: Stream) -> int:\n    for i in range(1):\n" ++
        "        buffer = leaf.formatted()\n        out.print(len(buffer), buffer[0], buffer[1], buffer[2], buffer[3], buffer[4])\n    return 0\n";
    const formatted = "module leaf\npublic def formatted() -> byte_buffer:\n    empty: list[int] = []\n" ++
        "    buffer = byte_buffer(empty)\n    _ = buffer.append_int(-7)\n    _ = buffer.append_float(1.5)\n    return buffer\n";
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const emitted = try snapshotFor(a, .{ caller, formatted, other }, mode);
        const result = try native(a, emitted);
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("5 45 55 49 46 53\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        for (emitted) |unit| if (std.mem.eql(u8, unit.source_path, "other.my")) try std.testing.expect(!unit.number);
    }
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-BUFFER-S4-1
test "S4 integer-only numeric buffer operations avoid the float helper dependency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const integer_caller = "module app\nimport leaf\ndef main(out: Stream) -> int:\n" ++
        "    buffer = leaf.formatted()\n    out.print(len(buffer), buffer[0], buffer[1])\n    return 0\n";
    const integer = "module leaf\npublic def formatted() -> byte_buffer:\n    empty: list[int] = []\n" ++
        "    buffer = byte_buffer(empty)\n    _ = buffer.append_int(-7)\n    return buffer\n";
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

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 release loop imports include the bounded entry consumed closure and stable ripple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller =
        \\module app
        \\import leaf
        \\def main(out: Stream) -> int:
        \\    total = leaf.cold(2)
        \\    for i in range(3):
        \\        total += leaf.compute(i)
        \\    j = 0
        \\    while j < 2:
        \\        total += leaf.compute(2)
        \\        j += 1
        \\    out.print(total)
        \\    return 0
    ;
    const source = leaf ++ "\npublic def cold(x: int) -> int:\n    if x > 0:\n        return x\n    return 0\n";
    const first = try snapshot(a, .{ caller, source, other }, true);
    const body = try textOf(first, "app.my");
    try std.testing.expect(std.mem.indexOf(u8, body, "define available_externally hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, ") nounwind uwtable alwaysinline !dbg") != null);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(first, "leaf.my"), ") nounwind uwtable alwaysinline !dbg") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "define available_externally hidden fastcc i64 @\"my.leaf::cold\"") == null);
    const entry_body = try entryText(first);
    try std.testing.expect(std.mem.indexOf(u8, entry_body, "define internal fastcc i64 @\"my.app::main.s4.entry.clone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry_body, "define internal fastcc i64 @\"my.leaf::cold.s4.entry.clone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry_body, ") nounwind uwtable alwaysinline !dbg") == null);
    try changed(first, try snapshot(a, .{ caller, source, other }, true), &.{});
    const hot = try std.mem.replaceOwned(u8, a, source, "total += i", "total += i * 2");
    try changed(first, try snapshot(a, .{ caller, hot, other }, true), &.{ "app.my", "leaf.my", "<entry>" });
    const cold = try std.mem.replaceOwned(u8, a, source, "return x\n", "return x + 1\n");
    try changed(first, try snapshot(a, .{ caller, cold, other }, true), &.{ "leaf.my", "<entry>" });
    const changed_caller = try std.mem.replaceOwned(u8, a, caller, "total = leaf.cold(2)", "total = leaf.cold(3)");
    try changed(first, try snapshot(a, .{ changed_caller, source, other }, true), &.{ "app.my", "<entry>" });
    const debug = try snapshot(a, .{ caller, source, other }, false);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(debug, "app.my"), "available_externally") == null);
    try std.testing.expect(std.mem.indexOf(u8, try entryText(debug), "available_externally") == null);
    try changed(debug, try snapshot(a, .{ caller, hot, other }, false), &.{"leaf.my"});
    // Native linking needs the entry, caller, imported closure and cold owner once each.
    for ([_][]const units.Unit{ first, debug }) |emitted| {
        const result = try native(a, emitted);
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("5\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
    }
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 entry imports refuse non-loop entries and over-budget loop dispatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ordinary = try snapshot(a, .{ app, leaf, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try entryText(ordinary), "available_externally") == null);
    const large = try std.mem.replaceOwned(u8, a, try branchLoop(a, 36), "module leaf\npublic def compute(x: int) -> int:\n", "module app\nimport leaf\ndef main(args: list[str]) -> int:\n    x = len(args)\n");
    const first = try snapshot(a, .{ large, leaf, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try entryText(first), "available_externally") == null);
    const updated = try std.mem.replaceOwned(u8, a, large, "return 36", "return 37");
    try changed(first, try snapshot(a, .{ updated, leaf, other }, true), &.{"app.my"});
    const result = try native(a, first);
    try std.testing.expect(result.term == .exited and result.term.exited == 2);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
// spec-case: NEW-CORE-S4-SITES-1
test "S4 a loop body called outside a caller loop imports with its source frame and stable ripple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main() -> int:\n    return leaf.compute(9223372036854775807)\n";
    const callee = "module leaf\npublic def compute(x: int) -> int:\n    total = 0\n    for i in range(2):\n        total += x\n    return total\n";
    const first = try snapshot(a, .{ caller, callee, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(first, "app.my"), "define available_externally hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try changed(first, try snapshot(a, .{ caller, callee, other }, true), &.{});
    const changed_body = try std.mem.replaceOwned(u8, a, callee, "total += x", "total += x + 1");
    try changed(first, try snapshot(a, .{ caller, changed_body, other }, true), &.{ "app.my", "leaf.my" });
    const result = try native(a, first);
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("leaf.my:5:15: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 9223372036854775807, width 64)\n" ++
        "  in leaf::compute at leaf.my:5:15\n  in app::main at app.my:4:12\n" ++
        "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":9223372036854775807,\"width\":64}\n", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 imports bounded branch-heavy loops and refuses larger bodies without caller ripple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main(args: list[str], out: Stream) -> int:\n    out.print(leaf.compute(len(args)))\n    return 0\n";
    const bounded = try branchLoop(a, 16);
    const first = try snapshot(a, .{ caller, bounded, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(first, "app.my"), "define available_externally hidden fastcc i64 @\"my.leaf::compute\"") != null);
    try changed(first, try snapshot(a, .{ caller, bounded, other }, true), &.{});
    const result = try native(a, first);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("2\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    const large = try branchLoop(a, 36);
    const refused = try snapshot(a, .{ caller, large, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(refused, "app.my"), "available_externally") == null);
    const updated = try std.mem.replaceOwned(u8, a, large, "return 36", "return 37");
    try changed(refused, try snapshot(a, .{ caller, updated, other }, true), &.{"leaf.my"});
}

fn branchLoop(a: std.mem.Allocator, branches: usize) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, "module leaf\npublic def compute(x: int) -> int:\n");
    for (0..branches) |index| try source.print(a, "    if x == {d}:\n        return {d}\n", .{ index + 1, index + 1 });
    try source.appendSlice(a, "    total = 0\n    for i in range(2):\n        total += x + 1\n    return total\n");
    return source.toOwnedSlice(a);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 branch-heavy non-loop callees retain their owner when called inside a loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main(args: list[str], out: Stream) -> int:\n" ++
        "    total = 0\n    for i in range(2):\n        total += leaf.compute(len(args)) + i\n    out.print(total)\n    return 0\n";
    const source = try std.mem.replaceOwned(u8, a, try branchLoop(a, 16), "    total = 0\n    for i in range(2):\n        total += x + 1\n    return total\n", "    return x + 1\n");
    const first = try snapshot(a, .{ caller, source, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(first, "app.my"), "available_externally") == null);
    const update = try std.mem.replaceOwned(u8, a, source, "return 16", "return 17");
    try changed(first, try snapshot(a, .{ caller, update, other }, true), &.{"leaf.my"});
    const result = try native(a, first);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("3\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 imported aggregate bodies close rendering dependencies and export excluded private callees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller =
        \\module app
        \\import leaf
        \\def main(out: Stream) -> int:
        \\    total = 0
        \\    for i in range(3):
        \\        value = leaf.compute(i)
        \\        total += value.a + value.f
        \\    out.print(total)
        \\    return 0
    ;
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, "module leaf\npublic record Big:\n    a: int\n    b: int\n    c: int\n    d: int\n    e: int\n    f: int\n");
    try source.appendSlice(a, "public def compute(x: int) -> Big:\n    return Big(callee(x), 2, 3, 4, 5, len(f\"{[float(x) + 1.25]}\"))\ndef callee(x: int) -> int:\n");
    for (0..40) |index| try source.print(a, "    if x == -{d}:\n        return 0\n", .{index + 1});
    try source.appendSlice(a, "    return x + 1\n");
    const emitted = try snapshot(a, .{ caller, source.items, other }, true);
    const body = try textOf(emitted, "app.my");
    try std.testing.expect(std.mem.indexOf(u8, body, "define available_externally hidden fastcc void @\"my.leaf::compute\"(ptr noalias sret([48 x i8])") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "define available_externally hidden fastcc i64 @\"my.leaf::callee\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(emitted, "leaf.my"), "define hidden fastcc i64 @\"my.leaf::callee\"") != null);
    const entry_body = try entryText(emitted);
    try std.testing.expect(std.mem.indexOf(u8, entry_body, "define internal fastcc void @\"my.leaf::compute.s4.entry.clone\"(ptr noalias sret([48 x i8])") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry_body, "declare hidden fastcc i64 @\"my.leaf::callee\"") != null);
    try std.testing.expect(numericHelper(emitted));
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("24\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 private entry bodies keep addressed and recursive callees at their real symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller =
        \\module app
        \\import leaf
        \\import other
        \\def main(args: list[str], out: Stream) -> int:
        \\    f = other.pick(args)
        \\    total = 0
        \\    for i in range(3):
        \\        total += leaf.closed(i)
        \\        total += other.apply(f, i)
        \\        total += leaf.recursive(i)
        \\    out.print(total)
        \\    return 0
    ;
    const source =
        \\module leaf
        \\public def closed(x: int) -> int:
        \\    total = 0
        \\    for i in range(2):
        \\        total += x
        \\    return total
        \\public def addressed(x: int) -> int:
        \\    total = 0
        \\    for i in range(2):
        \\        total += x + 1
        \\    return total
        \\public def alternate(x: int) -> int:
        \\    total = 0
        \\    for i in range(3):
        \\        total += x
        \\    return total
        \\public def recursive(x: int) -> int:
        \\    if x == 0:
        \\        return 0
        \\    return x + partner(x - 1)
        \\def partner(x: int) -> int:
        \\    if x == 0:
        \\        return 0
        \\    return x + recursive(x - 1)
    ;
    // The addresses appear only in another Core owner, never in main's own IR.
    const callback = "module other\nimport leaf\npublic def pick(args: list[str]) -> def(int) -> int:\n" ++
        "    return leaf.addressed if len(args) == 0 else leaf.alternate\n" ++
        "public def apply(f: def(int) -> int, x: int) -> int:\n    return f(x)\n";
    const emitted = try snapshot(a, .{ caller, source, callback }, true);
    const body = try entryText(emitted);
    try std.testing.expect(std.mem.indexOf(u8, body, "define internal fastcc i64 @\"my.leaf::closed.s4.entry.clone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "my.leaf::addressed.s4.entry.clone") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "my.leaf::recursive.s4.entry.clone") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "my.leaf::partner.s4.entry.clone") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "@\"my.leaf::addressed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "define available_externally hidden fastcc i64 @\"my.leaf::recursive\"") != null);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("22\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

// spec-case: NEW-CORE-S4-UNITS-1
test "S4 private body classification handles a deep call graph without native recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ir = @import("ir.zig");
    var module: ir.Module = .{};
    const n = 6000;
    for (0..n) |index| {
        var function: ir.Function = .{ .name = try std.fmt.allocPrint(a, "chain{d}", .{index}), .signature = .{ .params = &.{}, .ret = .i64 } };
        try function.insts.append(a, if (index + 1 < n) .{ .op = .call, .ty = .i64, .a = @fromBackingInt(@intCast(index + 1)) } else .{ .op = .iconst, .ty = .i64, .data = 1 });
        try function.insts.append(a, .{ .op = .ret, .ty = .void, .a = @fromBackingInt(0) });
        try function.blocks.append(a, .{});
        try function.blocks.items[0].insts.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(1) });
        try module.functions.append(a, function);
    }
    const selected = [_]u32{ 20, 0, n - 1 };
    const policy = @import("emit_clone_policy.zig");
    try std.testing.expectEqualSlices(u32, &selected, try policy.privateBodies(a, &module, &selected));
    const callback = try module.intern(a, .{ .@"fn" = .{ .params = &.{}, .ret = .i64 } });
    // The only address is in a different function, outside the selected caller.
    try module.functions.items[n - 1].insts.append(a, .{ .op = .func_ref, .ty = callback, .data = 20 });
    try std.testing.expectEqualSlices(u32, &.{ 0, n - 1 }, try policy.privateBodies(a, &module, &selected));
    module.functions.items[n - 1].insts.items[0] = .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0) };
    try std.testing.expectEqualSlices(u32, &.{}, try policy.privateBodies(a, &module, &selected));
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 an imported Result origin retains its callee path and function inside a counted loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main() -> Result[int, str]:\n" ++
        "    for i in range(2):\n        value = leaf.origin(i)?\n        assert value >= 0\n    return Ok(0)\n";
    const failing = "module leaf\npublic def origin(x: int) -> Result[int, str]:\n    return Err(\"loop failure\")\n";
    const emitted = try snapshot(a, .{ caller, failing, other }, true);
    try std.testing.expect(std.mem.indexOf(u8, try textOf(emitted, "app.my"), "define available_externally hidden fastcc") != null);
    const result = try native(a, emitted);
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("error: loop failure\n  leaf.my:3:12  leaf::origin  Err(...) created\n  app.my:5:17   app::main     ? propagated\n", result.stderr);
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
        const caller = try std.fmt.allocPrint(a, "module app\nimport leaf\ndef main() -> int:\n    return leaf.origin({s})\n", .{failure.arguments});
        const failing = try std.fmt.allocPrint(a, "module leaf\npublic def origin({s}) -> int:\n    return {s}\n", .{ failure.parameters, failure.expression });
        for ([_]bool{ false, true }) |release| {
            const result = try native(a, try snapshot(a, .{ caller, failing, other }, release));
            try std.testing.expect(result.term == .exited and result.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in leaf::origin at leaf.my:3:") != null);
            try std.testing.expect(std.mem.indexOf(u8, result.stderr, "in app::main at app.my:4:12") != null);
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
            .expected = "leaf.my:4:12: error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)\n" ++
                "  in leaf::origin at leaf.my:4:12\n  in app::main at app.my:5:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":2,\"length\":2}\n",
        },
        .{
            .argument = "1",
            .body = "    assert x == 0, \"mut check\"\n    return x\n",
            .expected = "leaf.my:4:12: error[R_ASSERT]: native execution failed: mut check\n" ++
                "  in leaf::origin at leaf.my:4:12\n  in app::main at app.my:5:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"mut check\"}\n",
        },
        .{
            .argument = "9223372036854775807",
            .body = "    if x < 0:\n        return 0\n    return x + 1\n",
            .expected = "leaf.my:6:14: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 1, width 64)\n" ++
                "  in leaf::origin at leaf.my:6:14\n  in app::main at app.my:5:12\n" ++
                "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":1,\"width\":64}\n",
        },
    };
    for (cases) |case| {
        const caller = try std.fmt.allocPrint(a, "module app\nimport leaf\ndef main() -> int:\n    xs = [1]\n    return leaf.origin(mut xs, {s})\n", .{case.argument});
        const callee = try std.fmt.allocPrint(a, "module leaf\npublic def origin(xs: mut list[int], x: int) -> int:\n    xs.append(2)\n{s}", .{case.body});
        const emitted = try snapshot(a, .{ caller, callee, other }, true);
        try std.testing.expect(std.mem.indexOf(u8, try textOf(emitted, "app.my"), "inlinedAt:") != null);
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
    const caller = "module app\nimport leaf\ndef main(args: list[str]) -> int:\n    xs = [1]\n" ++
        "    if len(args) == 0:\n        return leaf.origin[int](mut xs, 1, 2)\n    return leaf.origin[str](mut xs, \"x\", 2)\n";
    const callee = "module leaf\npublic def origin[T](xs: mut list[int], tag: T, x: int) -> int:\n    xs.append(2)\n    return xs[x]\n";
    for ([_][]const u8{ "leaf::origin[i64]", "leaf::origin[str]" }, [_][]const []const u8{ &.{}, &.{"text"} }, [_][]const u8{ "app.my:6:16", "app.my:7:12" }) |name, arguments, position| {
        const ran = try nativeArgs(a, try snapshot(a, .{ caller, callee, other }, true), arguments);
        try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, name) != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "at leaf.my:4:12") != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, position) != null);
    }
}

// spec-case: NEW-CORE-S4-SITES-1
test "S4 nested consuming helpers retain all frames under fact verification" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const caller = "module app\nimport leaf\ndef main() -> int:\n    xs = [1]\n    return leaf.middle(mut xs, 2)\n";
    const callee = "module leaf\npublic def origin(xs: mut list[int], x: int) -> int:\n    xs.append(2)\n    return xs[x]\n" ++
        "public def middle(xs: mut list[int], x: int) -> int:\n    if x < 0:\n        return 0\n    return origin(mut xs, x)\n";
    const ran = try native(a, try snapshotFor(a, .{ caller, callee, other }, .verify));
    try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::origin at leaf.my:4:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in leaf::middle at leaf.my:8:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in app::main at app.my:5:12") != null);
}

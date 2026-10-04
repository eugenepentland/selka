//! Invariant dispatch copies preserve every original checked effect and refusal.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_execute.zig");
const rewrite = @import("qbe_loop_unswitch_text.zig");
const model = @import("qbe_loop_unswitch_model.zig");
const sites = @import("qbe_rc_sites.zig");
const native_types = @import("native_types.zig");
const source =
    \\def dispatch(kind: int, count: int, seed: int, raw: mut list[int], out: Stream) -> int:
    \\    total = seed
    \\    for i in range(count):
    \\        out.print(i)
    \\        if kind == 0:
    \\            total += raw[i]
    \\        elif kind == 1:
    \\            raw.append(i)
    \\            total += i
    \\        elif kind == 2:
    \\            total += 1 // (i - 2)
    \\        else:
    \\            total -= raw[i]
    \\    return total
    \\def changed(kind: int, count: int) -> int:
    \\    selector = kind
    \\    total = 0
    \\    for i in range(count):
    \\        if selector == 0:
    \\            total += i
    \\        else:
    \\            total -= i
    \\        selector += 1
    \\    return total
;
const main_source =
    \\def parsed(args: list[str], index: int) -> int:
    \\    match int(args[index]):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\def main(args: list[str], out: Stream) -> int:
    \\    kind = parsed(args, 0)
    \\    count = parsed(args, 1)
    \\    total = parsed(args, 2)
    \\    raw = [1, 2, 3]
    \\    for i in range(count):
    \\        out.print(i)
    \\        if kind == 0:
    \\            total += raw[i]
    \\        elif kind == 1:
    \\            raw.append(i)
    \\            total += i
    \\        elif kind == 2:
    \\            total += 1 // (i - 2)
    \\        else:
    \\            total -= raw[i]
    \\    out.print(len(raw))
    \\    return total
;
const gc_source =
    \\def parsed(args: list[str], index: int) -> int:
    \\    match int(args[index]):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\def main(args: list[str], out: Stream) -> int:
    \\    kind = parsed(args, 0)
    \\    count = parsed(args, 1)
    \\    total = parsed(args, 2)
    \\    raw = [1, 2, 3]
    \\    for i in range(count):
    \\        out.print(i)
    \\        raw.append(i)
    \\        if kind == 0:
    \\            total += raw[i]
    \\        else:
    \\            total -= raw[i]
    \\    out.print(len(raw))
    \\    return total
;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn emitted(steps: bool, frames: bool) !std.json.Parsed(Manifest) {
    return emittedInput(source ++ "\n" ++ main_source, steps, frames);
}
fn emittedInput(input: []const u8, steps: bool, frames: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "unswitch.my", input);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = frames });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, name, function.name)) return function.il;
    return error.TestUnexpectedResult;
}
fn sameOutcome(kind: i64, count: i64, seed: i64) !void {
    return sameInputOutcome(source ++ "\n" ++ main_source, kind, count, seed);
}
fn sameInputOutcome(input: []const u8, kind: i64, count: i64, seed: i64) !void {
    const args = [_][]const u8{
        try std.fmt.allocPrint(t.allocator, "{d}", .{kind}),
        try std.fmt.allocPrint(t.allocator, "{d}", .{count}),
        try std.fmt.allocPrint(t.allocator, "{d}", .{seed}),
    };
    defer for (args) |arg| t.allocator.free(arg);
    const argv = [_][]const u8{ "--", args[0], args[1], args[2] };
    var compilation = try compiler.Compilation.init(t.allocator, "unswitch_boundary.my", input);
    defer compilation.deinit();
    const ordinary = try native.runWithOptions(&compilation, .{ .arguments = &argv });
    const fast = try native.runUnaccounted(&compilation, .{ .arguments = &argv });
    try t.expectEqual(ordinary.failed, fast.failed);
    try t.expectEqual(ordinary.value, fast.value);
    try t.expectEqual(ordinary.status, fast.status);
    try t.expectEqualDeep(ordinary.trap, fast.trap);
    try t.expectEqualStrings(ordinary.stdout, fast.stdout);
    try t.expectEqualStrings(ordinary.stderr, fast.stderr);
    // All zero-trip fixtures return the seed (Boolean fixtures use seed zero).
    // An equal pair of usage failures must never count as a successful replay.
    if (count == 0) {
        try t.expect(!fast.failed);
        try t.expectEqual(seed, fast.value);
        try t.expectEqual(@as(u8, @truncate(@as(u64, @bitCast(seed)))), fast.status);
        try t.expect(fast.stdout.len != 0);
    }
}
fn outcomes() !void {
    for ([_]i64{ -1, 0, 1, 2, 3, 99 }) |kind| {
        try sameOutcome(kind, 0, 13);
        try sameOutcome(kind, 3, 0);
    }
    try sameOutcome(0, 4, 0);
    try sameOutcome(1, 3, std.math.maxInt(i64) - 1);
    try sameOutcome(0, 3, std.math.maxInt(i64) - 1);
    try sameOutcome(3, 3, std.math.minInt(i64));
}

// spec-case: QBE-LOOP-UNSWITCH-1
test "invariant loop guest argv reaches a successful three-element fold" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "unswitch_boundary.my", source ++ "\n" ++ main_source);
    defer compilation.deinit();
    const run = try native.runWithOptions(&compilation, .{ .arguments = &.{ "--", "0", "3", "0" } });
    try t.expect(!run.failed);
    try t.expectEqual(@as(i64, 6), run.value);
    try t.expectEqual(@as(u8, 6), run.status);
    try t.expectEqualStrings("0\n1\n2\n3\n", run.stdout);
}

fn booleanJoins() !void {
    const start = std.mem.indexOf(u8, main_source, "def main(") orelse return error.TestUnexpectedResult;
    const body =
        \\def main(args: list[str], out: Stream) -> int:
        \\    kind = parsed(args, 0)
        \\    count = parsed(args, 1)
        \\    seed = parsed(args, 2)
        \\    total = 0
        \\    for i in range(count):
        \\        if kind == 2:
        \\            total += 1
        \\        out.print(i)
        \\        if CONDITION:
        \\            total += 3
        \\        else:
        \\            total += 7
        \\    out.print(total)
        \\    return total
    ;
    for ([_][]const u8{
        "kind == 2 or kind == 3",
        "kind == 2 and kind != 3",
        "(kind == 2 or kind == 3) and i < seed",
        "i < seed and (kind == 2 or kind == 3)",
        "(kind == 2 if i < seed else kind == 3)",
        "kind == 2 or 1 // (seed - i) > 0",
        "i < seed or kind == 2",
        "(seed if i < 1 else kind) == 2",
    }) |condition| {
        const replaced = try std.mem.replaceOwned(u8, t.allocator, body, "CONDITION", condition);
        defer t.allocator.free(replaced);
        const input = try std.mem.concat(t.allocator, u8, &.{ main_source[0..start], replaced });
        defer t.allocator.free(input);
        var emitted_join = try emittedInput(input, false, false);
        defer emitted_join.deinit();
        const admitted = std.mem.indexOf(u8, try named(emitted_join.value, "main"), "QBE-LOOP-UNSWITCH-1") != null;
        try t.expect(admitted);
        for ([_]i64{ 2, 3, 99 }) |kind| {
            try sameInputOutcome(input, kind, 3, 1);
        }
        try sameInputOutcome(input, 2, 0, 0);
        try sameInputOutcome(input, 2, 3, 0);
    }
}

// spec-case: QBE-LOOP-UNSWITCH-1
test "invariant loop comparison joins preserve short circuit and conditional values" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try booleanJoins();
}

fn literalLimit() !void {
    var input: std.Io.Writer.Allocating = .init(t.allocator);
    defer input.deinit();
    try input.writer.writeAll("def wide(kind: int, count: int) -> int:\n    total = 0\n    for i in range(count):\n");
    for (0..17) |value| {
        try input.writer.print("        {s} kind == {d}:\n            total += i + {d}\n", .{ if (value == 0) "if" else "elif", value, value });
    }
    try input.writer.writeAll("        else:\n            total -= i\n    return total\ndef main() -> int:\n    return wide(1, 32)\n");
    var compilation = try compiler.Compilation.init(t.allocator, "unswitch_literals.my", input.written());
    defer compilation.deinit();
    const il = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(il);
    try t.expect(std.mem.indexOf(u8, il, "QBE-LOOP-UNSWITCH-1") == null);
}

// spec: QBE-LOOP-UNSWITCH-1
test "invariant loop dispatch specializes every literal and preserves checked callback mutation traps" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false, false);
    defer fast.deinit();
    const il = try named(fast.value, "main");
    try t.expect(std.mem.indexOf(u8, il, "QBE-LOOP-UNSWITCH-1") != null);
    try t.expect(std.mem.indexOf(u8, il, "literals=3") != null);
    try t.expect(std.mem.indexOf(u8, il, "_original_") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_normalized_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_division") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_overflow_op") != null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "changed"), "QBE-LOOP-UNSWITCH-1") == null);
    var steps = try emitted(true, false);
    defer steps.deinit();
    try t.expect(std.mem.indexOf(u8, try named(steps.value, "main"), "QBE-LOOP-UNSWITCH-1") == null);
    var frames = try emitted(false, true);
    defer frames.deinit();
    try t.expect(std.mem.indexOf(u8, try named(frames.value, "main"), "QBE-LOOP-UNSWITCH-1") == null);
    try outcomes();
    try literalLimit();
    runtime.set(.gc);
    var gc = try emittedInput(gc_source, false, false);
    defer gc.deinit();
    try t.expect(std.mem.indexOf(u8, try named(gc.value, "main"), "QBE-LOOP-UNSWITCH-1") != null);
    try sameInputOutcome(gc_source, 0, 3, 0);
    try sameInputOutcome(gc_source, 99, 3, 0);
    try sameInputOutcome(gc_source, 0, 0, 13);
    try sameInputOutcome(gc_source, 0, 3, std.math.maxInt(i64) - 1);
}

const il_source =
    \\export function l $sample(l %l0) {
    \\@entry
    \\ jmp @i0
    \\@i0
    \\ jnz %counter, @i4, @i9
    \\@i4
    \\ jnz %condition, @yes, @i7
    \\@yes
    \\ storel 5, %position
    \\ call $myl_qbe_rc_scope_begin(l %ctx, l 0)
    \\ jmp @i8
    \\@i7
    \\ storel 7, %position
    \\ call $myl_qbe_rc_scope_end(l %ctx, l 0)
    \\ jmp @i8
    \\@i8
    \\ jmp @i0
    \\@i9
    \\ ret 0
    \\}
    \\
;
fn certificate() model.Certificate {
    var result: model.Certificate = .{ .head = 0, .back = 8, .slot = 0, .conditions = .{}, .values = .{} };
    result.conditions.items[0] = .{ .pc = 4, .value = 0, .predicate = .eq, .target = 7 };
    result.conditions.len = 1;
    result.values.items[0] = 0;
    result.values.len = 1;
    return result;
}
fn refusals() !void {
    const entered = try std.mem.replaceOwned(u8, t.allocator, il_source, "jmp @i0", "jmp @i7");
    defer t.allocator.free(entered);
    const refused = try rewrite.rewrite(t.allocator, entered, certificate());
    defer t.allocator.free(refused);
    try t.expectEqualStrings(entered, refused);
    const padding = try t.allocator.alloc(u8, 65537);
    defer t.allocator.free(padding);
    @memset(padding, 'x');
    const split = std.mem.indexOf(u8, il_source, "\n@i4\n").? + 1;
    const large = try std.fmt.allocPrint(t.allocator, "{s}\n # {s}\n{s}", .{ il_source[0..split], padding, il_source[split..] });
    defer t.allocator.free(large);
    const unchanged = try rewrite.rewrite(t.allocator, large, certificate());
    defer t.allocator.free(unchanged);
    try t.expectEqualStrings(large, unchanged);
}

// spec-case: QBE-LOOP-UNSWITCH-1
test "invariant loop CFG copies prune only certified arms and refuse native entries and code growth" {
    const output = try rewrite.rewrite(t.allocator, il_source, certificate());
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "@us0_0_yes") != null);
    try t.expect(std.mem.indexOf(u8, output, "@us0_0_i7") == null);
    try t.expect(std.mem.indexOf(u8, output, "@us0_original_i7") != null);
    try t.expect(std.mem.indexOf(u8, output, "jmp @us0_0_i0") != null);
    try refusals();
}

// spec-case: QBE-LOOP-UNSWITCH-1
test "invariant loop duplicated sites retain original stored PC and unique symbols" {
    const output = try rewrite.rewrite(t.allocator, il_source, certificate());
    defer t.allocator.free(output);
    var catalog = try native_types.Catalog.initRecords(t.allocator, &.{});
    defer catalog.deinit();
    const instrumented = try sites.instrument(t.allocator, output, .{ .unit = "myl_f_dispatch", .layouts = &catalog });
    defer t.allocator.free(instrumented.text);
    defer t.allocator.free(instrumented.markers);
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, instrumented.markers, "# myl-rcsite "));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, instrumented.markers, " 5 myl_qbe_rc_scope_begin -"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, instrumented.markers, " 7 myl_qbe_rc_scope_end -"));
    try t.expect(std.mem.indexOf(u8, instrumented.markers, "myl_f_dispatch_rcsite0 ") != null);
    try t.expect(std.mem.indexOf(u8, instrumented.markers, "myl_f_dispatch_rcsite1 ") != null);
    try t.expect(std.mem.indexOf(u8, instrumented.markers, "myl_f_dispatch_rcsite2 ") != null);
}

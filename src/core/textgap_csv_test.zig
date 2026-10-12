//! Immortal-prefix appends allocate their final independent owner directly.
const std = @import("std");
const language = @import("mylang");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;
const Lane = struct { release: bool, mode: ?passes.Mode };
const lanes = [_]Lane{
    .{ .release = true, .mode = .trusted },
    .{ .release = false, .mode = null },
    .{ .release = true, .mode = .verify },
    .{ .release = false, .mode = .trusted },
    .{ .release = true, .mode = .off },
};

fn execute(a: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var unit = try language.Compilation.init(a, "append.my", source);
    try unit.check();
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true);
    for ([_]bool{ true, false }) |checked| {
        for (lanes) |lane| {
            var refusal: build.Refusal = .{};
            var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = checked, .zero_rc = checked }, &refusal);
            const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
            const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
            if (run.status != 0) report("static append: {s}{s}\n", .{ run.stdout, run.stderr });
            try std.testing.expectEqual(@as(u8, 0), run.status);
            try std.testing.expectEqualStrings(expected, run.stdout);
            try std.testing.expectEqualStrings("", run.stderr);
            if (checked) try std.testing.expect(zero.emittedClean(run.llvm));
        }
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_csv static append keeps Unicode literals snapshots self appends and empty values independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func modify() -> str:
        \\    mut value = "é€🙂"
        \\    value += ""
        \\    value += "!"
        \\    return value
        \\func main(out: Stream) -> int:
        \\    out.print(modify(), modify(), "é€🙂")
        \\    mut text = "abc"
        \\    const snapshot = text.copy()
        \\    text += text
        \\    text += ""
        \\    out.print(text, snapshot, "abc")
        \\    mut empty = ""
        \\    empty += ""
        \\    const saved = empty.copy()
        \\    empty += "\0🙂"
        \\    out.print(len(empty), len(saved))
        \\    mut dynamic = "é" + str(1)
        \\    const old = dynamic.copy()
        \\    dynamic += "€🙂"
        \\    out.print(dynamic, old)
        \\    return 0
    , "é€🙂! é€🙂! é€🙂\nabcabc abc abc\n2 0\né1€🙂 é1\n");
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_csv character collectors preserve delimiter resets UTF8 and early exits across growth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func fields(source: str) -> str[]:
        \\    mut output: str[] = []
        \\    mut field = ""
        \\    for ch in source:
        \\        if ch == ";":
        \\            output.append(field)
        \\            field = ""
        \\        else:
        \\            field += ch
        \\    output.append(field)
        \\    return output
        \\func first(source: str) -> str:
        \\    mut output = ""
        \\    for ch in source:
        \\        output += ch
        \\        return output
        \\    return output
        \\func main(out: Stream) -> int:
        \\    mut parsed = fields(";é;abc;;🙂;")
        \\    out.print(":".join(parsed), first("€abc"), first(""))
        \\    mut long = ""
        \\    for i in range(1027):
        \\        long += "é"
        \\    mut chunks = fields(long)
        \\    out.print(len(chunks), len(chunks[0]), long == chunks[0])
        \\    return 0
    , ":é:abc::🙂: € \n1 1027 True\n");
}

// spec-case: NEW-CORE-TEXT-CURSOR-1
test "textgap_csv cursor traversal preserves source update after traversal and character early return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func count(mut source: str) -> int:
        \\    mut total = 0
        \\    for ch in source:
        \\        total += len(ch)
        \\    source += "🙂"
        \\    return total
        \\func first(source: str) -> str:
        \\    mut output = ""
        \\    for ch in source:
        \\        output += ch
        \\        return output
        \\    return output
        \\func main(out: Stream) -> int:
        \\    mut source = "é€x"
        \\    out.print(count(mut source), source, first("🙂more"), first(""))
        \\    return 0
    , "3 é€x🙂 🙂 \n");
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_csv ASCII append invalidates cached scalar lengths and hashes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func collect(source: str) -> str:
        \\    mut output = "é"
        \\    for ch in source:
        \\        const before = len(output)
        \\        output += ch
        \\        if len(output) != before + 1:
        \\            return "bad"
        \\    return output
        \\func main(out: Stream) -> int:
        \\    mut value = collect("abc")
        \\    mut keys: dict[str, int] = {}
        \\    keys["éabc"] = 7
        \\    const cached = keys[value]
        \\    const prior = value.copy()
        \\    value += value[1]
        \\    keys["éabca"] = 9
        \\    out.print(value, prior, len(value), cached, keys[value])
        \\    return 0
    , "éabca éabc 5 7 9\n");
}

// Direct native helper contract: explicit destruction, no ownership rewrite.
// Source ownership need not admit this same-owner fused instruction shape.
// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_csv append helper captures same-owner scalars before growth and rejects invalid offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ir = @import("ir.zig");
    for ([_]bool{ false, true }) |invalid| {
        for ([_]support.RunOptions{ .{ .own = false }, .{ .own = false, .release = true }, .{ .own = false, .release = true, .verify = true } }) |mode| {
            var module: ir.Module = .{ .zero_rc = true };
            try module.strings.append(a, "éabc");
            var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
            const literal = try h.loose(.{ .op = .str_const, .ty = .str });
            var text = try h.emit(.{ .op = .str_append_char, .ty = .str, .a = literal, .b = literal, .data = try h.extra(&.{try h.int(.u64, 0)}) });
            text = try h.emit(.{ .op = .str_append_char, .ty = .str, .a = text, .b = text, .data = try h.extra(&.{try h.int(.u64, if (invalid) -1 else 2)}) });
            try h.printValues(try h.param(0), &.{text});
            _ = try h.emit(.{ .op = .release, .ty = .void, .a = text, .data = @import("own.zig").unique_release });
            _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
            _ = try h.finish();
            var options = mode;
            options.leakcheck = !invalid;
            const run = try support.runOwned(a, &module, options);
            try std.testing.expectEqual(@as(u8, if (invalid) 1 else 0), run.status);
            try std.testing.expectEqualStrings(if (invalid) "" else "éabcéa\n", run.stdout);
            try std.testing.expectEqualStrings(if (invalid) "error[E_CORE_UNSUPPORTED]: S2 IR operation -1 is not implemented\n" else "", run.stderr);
            try std.testing.expect(zero.emittedClean(run.llvm));
        }
    }
}

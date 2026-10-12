//! Immutable byte literals keep their static storage through checked ownership.
const std = @import("std");
const report = std.debug.print;
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn buildSource(a: std.mem.Allocator, input: []const u8) !ir.Module {
    var unit = try @import("mylang").Compilation.init(a, "literal.my", input);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |d| report("{s}\n", .{try d.render(a, unit.src)});
        return err;
    };
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
}

const source =
    \\func literal() -> bytes:
    \\    return b"A\x00\xffZ"
    \\func main(out: Stream) -> int:
    \\    mut data = literal()
    \\    const saved = data.copy()
    \\    mut rows = [b"abc", b"", b"\xc3\xa9"]
    \\    mut named: dict[str, bytes] = {"key": b"abc"}
    \\    mut buffer = byte_buffer([])
    \\    assert buffer.append_range(data, 0, len(data))
    \\    data = b"changed"
    \\    rows[0] = b"new"
    \\    named["key"] = b"other"
    \\    assert buffer.append_byte(66)
    \\    out.print(len(saved), saved[0], saved[1], saved[2], saved[-1], buffer[-1])
    \\    out.print(len(rows[1]), len(rows[2]), len(named["key"]), len(data))
    \\    match b"\xff".decode():
    \\        case Ok(_):
    \\            return 1
    \\        case Err(_):
    \\            out.print("invalid")
    \\    match b"abc".decode():
    \\        case Ok(text):
    \\            out.print(text, "abc", len(b"abc"))
    \\        case Err(_):
    \\            return 2
    \\    return 0
;

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_literal immutable raw literals have static byte IR without runtime encoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const module = try buildSource(arena.allocator(), source);
    var found = false;
    for (module.functions.items) |f| {
        try std.testing.expect(!std.mem.eql(u8, f.name, "myl_core_text_encode"));
        for (f.insts.items) |inst| {
            if (inst.op == .str_const and inst.ty == .bytes) found = true;
        }
    }
    try std.testing.expect(found);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_literal native raw values copies replacements and mutable buffers stay independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Lane = struct { release: bool, mode: ?passes.Mode };
    for ([_]Lane{
        .{ .release = true, .mode = .trusted },
        .{ .release = false, .mode = null },
        .{ .release = true, .mode = .verify },
        .{ .release = false, .mode = .trusted },
        .{ .release = true, .mode = .off },
    }) |lane| {
        var module = try buildSource(a, source);
        const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
        if (run.status != 0) report("literal: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("4 65 0 255 90 66\n0 2 5 7\ninvalid\nabc abc 3\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_text_encode(") == null);
    }
}

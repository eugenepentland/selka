//! Immutable byte literals keep their static storage through checked ownership.
const std = @import("std");
const report = std.debug.print;
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

fn buildSource(a: std.mem.Allocator, input: []const u8) !ir.Module {
    const program = try support.checkedProgram(a, input);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").check(a, program, &failure);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{
        .program = program,
    }, &refusal);
}

const source =
    \\import buffers
    \\import strings
    \\
    \\func literal() -> bytes:
    \\    return b"A\x00\xffZ"
    \\func main(out: Stream) -> int:
    \\    mut data = literal()
    \\    const saved = copy(data)
    \\    mut rows = [b"abc", b"", b"\xc3\xa9"]
    \\    mut named: dict[str, bytes] = {"key": b"abc"}
    \\    mut buffer = byte_buffer([])
    \\    assert buffers.append_range(mut buffer, data, 0, len(data))
    \\    data = b"changed"
    \\    rows[0] = b"new"
    \\    named["key"] = b"other"
    \\    assert buffers.append_byte(mut buffer, 66)
    \\    print(out, len(saved), saved[0], saved[1], saved[2], saved[len(saved) - 1], buffer[len(buffer) - 1])
    \\    print(out, len(rows[1]), len(rows[2]), len(named["key"]), len(data))
    \\    match strings.decode(b"\xff"):
    \\        case Ok(_):
    \\            return 1
    \\        case Err(_):
    \\            print(out, "invalid")
    \\    match strings.decode(b"abc"):
    \\        case Ok(text):
    \\            print(out, text, "abc", len(b"abc"))
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
        .{ .release = false, .mode = null },
        .{ .release = false, .mode = .trusted },
        .{ .release = true, .mode = .trusted },
        .{ .release = true, .mode = .verify },
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

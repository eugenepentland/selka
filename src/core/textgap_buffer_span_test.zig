//! Whole-use proof for local octet encodings and independent-owner fallback.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const report = std.debug.print;
const fusion = @import("fuse_encode.zig");

fn buildSource(a: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) !ir.Module {
    var unit = try @import("mylang").Compilation.init(a, "encode.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |d| report("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    return build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, refusal);
}

fn count(module: *const ir.Module, op: ir.Op) usize {
    var n: usize = 0;
    for (module.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op == op) n += 1;
    };
    return n;
}
const Lane = struct { release: bool, mode: ?passes.Mode };
const lanes = [_]Lane{
    .{ .release = true, .mode = .trusted },
    .{ .release = false, .mode = null },
    .{ .release = true, .mode = .verify },
    .{ .release = false, .mode = .trusted },
    .{ .release = true, .mode = .off },
};

fn execute(a: std.mem.Allocator, source: []const u8, expected: []const u8, borrow: bool) !void {
    var unit = try @import("mylang").Compilation.init(a, "encode.my", source);
    try unit.check();
    const program = unit.program.?;
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, program, &failure, true);
    for (lanes) |lane| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = program, .single_owner = true, .zero_rc = true }, &refusal);
        const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
        if (run.status != 0) report("encode run: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        if (lane.mode != null) {
            try std.testing.expect((std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_text_encode(") == null) == borrow);
            if (borrow) try std.testing.expect(std.mem.indexOf(u8, run.llvm, "extractvalue { ptr, i64 }") != null);
        }
    }
}
// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_buffer_span append borrows encoded octets with valid invalid growth and independent output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func collect(text: str) -> bytes:
        \\    mut data = text.encode()
        \\    mut out = byte_buffer([])
        \\    assert out.append_range(data, 0, 0)
        \\    assert not out.append_range(data, -1, 1)
        \\    assert not out.append_range(data, 0, len(data) + 1)
        \\    assert not out.append_range(data, 2, 1)
        \\    assert not out.append_range(data, -9223372036854775808, 9223372036854775807)
        \\    for i in range(17):
        \\        assert out.append_range(data, 0, len(data))
        \\    assert out.append_range(data, 1, 2)
        \\    return bytes(out)
        \\func main(out: Stream) -> int:
        \\    mut text = "é🙂" + str(1)
        \\    const saved = collect(text)
        \\    text += "changed"
        \\    out.print(len(saved), saved[0], saved[-1], len(text))
        \\    return 0
    , "120 195 169 10\n", true);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_buffer_span rejects forged helper contracts and parent replacement" {
    const source =
        \\func collect(text: str) -> bytes:
        \\    const raw = text.encode()
        \\    mut buffer = byte_buffer([])
        \\    _ = buffer.append_range(raw, 0, len(raw))
        \\    return bytes(buffer)
        \\func main() -> int:
        \\    return len(collect("abc"))
    ;
    for (0..6) |variant| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: build.Refusal = .{};
        var module = try buildSource(a, source, &refusal);
        for (module.functions.items) |*f| {
            if (!std.mem.eql(u8, f.name, "myl_core_buffer_append_checked")) continue;
            switch (variant) {
                0 => f.signature.linkage = .extern_c,
                1 => f.signature.owned = 0,
                2 => f.signature.consumes = 2,
                3 => f.signature.views = 2,
                4 => f.signature.params = &.{ .byte_buffer, .str, .i64, .i64 },
                else => {},
            }
        }
        if (variant == 5) try module.functions.append(a, .{ .name = "myl_core_buffer_append_span_checked", .signature = .{ .params = &.{ .byte_buffer, .str, .i64, .i64 }, .ret = .byte_buffer, .linkage = .runtime_c, .owned = 1 } });
        try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func collect(mut texts: str[]) -> bytes:
        \\    const raw = texts[0].encode()
        \\    texts[0] = "changed"
        \\    mut buffer = byte_buffer([])
        \\    _ = buffer.append_range(raw, 0, len(raw))
        \\    return bytes(buffer)
        \\func main(out: Stream) -> int:
        \\    mut texts = ["abc" + str(7)]
        \\    const result = collect(mut texts)
        \\    out.print(len(result), result[0], result[-1], texts[0])
        \\    return 0
    , "4 97 55 changed\n", false);
}

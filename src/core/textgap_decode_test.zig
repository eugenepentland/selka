//! UTF-8 decoding borrows private byte slices and returns independent text owners.
const std = @import("std");
const report = std.debug.print;
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const fusion = @import("fuse_slice_key.zig");

const slice_source =
    \\import strings
    \\
    \\func part(raw: bytes, start: int, end: int) -> str:
    \\    match strings.decode(raw[start:end]):
    \\        case Ok(text):
    \\            return text
    \\        case Err(_):
    \\            return "invalid"
    \\func main(out: Stream) -> int:
    \\    mut raw = b"A\xc3\xa9\xf0\x9f\x99\x82Z"
    \\    const saved = part(raw, 1, 7)
    \\    print(out, saved, part(raw, -1, 99), part(raw, 0, 0))
    \\    print(out, part(raw, 2, 3), part(raw, 0, 2))
    \\    print(out, part(raw, -9223372036854775808, 9223372036854775807))
    \\    raw = b"replacement"
    \\    print(out, saved, part(raw, 0, 3))
    \\    return 0
;

fn buildSource(a: std.mem.Allocator, source: []const u8) !ir.Module {
    // The fixtures import `strings` (W13-S5: `raw.decode()` is refused), so they are checked as embedded projects.
    const program = try support.checkedProgram(a, source);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").check(a, program, &failure);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{
        .program = program,
    }, &refusal);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_decode private slice borrows for validation and independently owned output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try buildSource(a, slice_source);
    // The parameter's slice is built as a view, so the fusion has no owned slice left to borrow (C9 bytes).
    try std.testing.expectEqual(@as(u32, 0), try fusion.run(a, &module));
    try support.verified(a, &module, &.{});
    for ([_][]const u8{ "myl_core_span_utf8_count", "myl_core_span_decode_text" }) |name| {
        var found = false;
        for (module.functions.items) |f| {
            if (!std.mem.eql(u8, f.name, name)) continue;
            found = true;
            try std.testing.expectEqual(@as(u64, 1), f.signature.passing.views);
            const contract = @import("zero_rc.zig").contract(name).?;
            try std.testing.expectEqual(@as(u64, 1), contract.views);
            try std.testing.expectEqual(@as(u64, 0), contract.owned);
        }
        try std.testing.expect(found);
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_decode untrusted or conflicting helper declarations cannot borrow slices" {
    for (0..6) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module = try buildSource(a, slice_source);
        for (module.functions.items) |*f| {
            if (!std.mem.eql(u8, f.name, "myl_core_bytes_decode_text")) continue;
            switch (mode) {
                0 => f.signature.linkage = .extern_c,
                1 => f.signature.passing.owned = 1,
                2 => f.signature.passing.consumes = 1,
                3 => f.signature.passing.views = 1,
                4 => f.signature.params = &.{.str},
                else => {},
            }
        }
        if (mode == 5) try module.functions.append(a, .{
            .name = "myl_core_span_decode_text",
            .signature = .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c },
        });
        try std.testing.expectEqual(@as(u32, 0), try fusion.run(a, &module));
    }
}

const Lane = struct { release: bool, mode: ?passes.Mode };
const lanes = [_]Lane{
    .{ .release = false, .mode = null },
    .{ .release = false, .mode = .trusted },
    .{ .release = true, .mode = .trusted },
    .{ .release = true, .mode = .verify },
    .{ .release = true, .mode = .off },
};

fn execute(a: std.mem.Allocator, source: []const u8, expected: []const u8, borrowed: bool) !void {
    for (lanes) |lane| {
        var module = try buildSource(a, source);
        const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
        if (run.status != 0) report("decode: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        if (lane.mode != null) {
            try std.testing.expectEqual(borrowed, std.mem.indexOf(u8, run.llvm, "call ptr @myl_core_span_decode_text(") != null);
        }
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_decode native Unicode invalid boundaries and replaced input keep independent results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Keep the original Unicode/alias workload bytes; normalize bounds explicitly
    // only in its modern runtime counterpart.
    const normalized = try std.mem.replaceOwned(u8, a, slice_source, "raw[start:end]", "raw[clip(start, len(raw)):clip(end, len(raw))]");
    // The helper goes after the fixture's `import` line, which must stay first.
    const modern = try std.mem.replaceOwned(u8, a, normalized, "import strings\n\n", "import strings\n\n" ++
        "func clip(index: int, size: int) -> int:\n    if index < 0:\n        return max(size + index, 0)\n    return min(index, size)\n\n");
    var module = try buildSource(a, slice_source);
    const rejected = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 1), rejected.status);
    try std.testing.expectEqualStrings("", rejected.stdout);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "index -1, length 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "negative indexes are not allowed") != null);
    try execute(a, modern, "é🙂 Z \ninvalid invalid\nAé🙂Z\né🙂 rep\n", true);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "textgap_decode mutated bytes and escaping snapshot retain original bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\import strings
        \\
        \\func snapshot(raw: bytes) -> bytes:
        \\    return copy(raw[0:3])
        \\func alter(mut buffers: bytes[]) -> str:
        \\    const selected = copy(buffers[0][0:3])
        \\    buffers[0] = b"replaced"
        \\    match strings.decode(selected):
        \\        case Ok(text):
        \\            return text
        \\        case Err(_):
        \\            return "invalid"
        \\func main(out: Stream) -> int:
        \\    mut raw = b"abcXYZ"
        \\    const saved = snapshot(raw)
        \\    raw = b"other"
        \\    mut buffers = [copy(saved)]
        \\    print(out, alter(mut buffers), len(buffers[0]), saved[0], len(raw))
        \\    return 0
    , "abc 8 97 5\n", false);
}

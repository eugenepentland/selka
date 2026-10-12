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
// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow reads UTF8 octets with lengths and negative indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try buildSource(a,
        \\func score(text: str) -> int:
        \\    mut raw = text.encode()
        \\    mut sum = len(raw)
        \\    for b in raw:
        \\        sum += b
        \\    if len(raw) > 0:
        \\        sum += raw[-1]
        \\    return sum
        \\func main() -> int:
        \\    return score("é🙂") + score("")
    , &refusal);
    module.zero_rc = true;
    _ = try fusion.runRecording(a, &module, null);
    try std.testing.expect(count(&module, .str_view_of) > 0);
    try support.verified(a, &module, &.{});
}
// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow preserves return store opaque call and source mutation ownership" {
    const cases = [_][]const u8{
        "func test(text: str) -> bytes:\n    return text.encode()\n",
        "func test(text: str) -> int:\n    mut raw = text.encode()\n    const stored = [raw]\n    return len(stored[0])\n",
        "func use(raw: bytes) -> int:\n    return len(raw)\nfunc test(text: str) -> int:\n    mut raw = text.encode()\n    return use(raw)\n",
        "func test(mut text: str) -> int:\n    mut raw = text.encode()\n    text += \"x\"\n    return len(raw)\n",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: build.Refusal = .{};
        const entry = if (std.mem.indexOf(u8, source, "-> bytes:") != null)
            "func main() -> int:\n    return len(test(\"é\"))\n"
        else if (std.mem.indexOf(u8, source, "mut text:") != null)
            "func main() -> int:\n    mut text = \"é\"\n    return test(mut text)\n"
        else
            "func main() -> int:\n    return test(\"é\")\n";
        const complete = try std.mem.concat(a, u8, &.{ source, entry });
        var module = try buildSource(a, complete, &refusal);
        module.zero_rc = true;
        try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
        try support.verified(a, &module, &.{});
    }
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
test "encode borrow native UTF8 empty invalid octets owner replacement early return vector and tail cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func score(text: str) -> int:
        \\    mut raw = text.encode()
        \\    mut sum = len(raw)
        \\    for value in raw:
        \\        sum += value
        \\    return sum
        \\func first(text: str) -> int:
        \\    mut raw = text.encode()
        \\    if len(raw) == 0:
        \\        return 0
        \\    return raw[-1]
        \\func main(out: Stream) -> int:
        \\    mut text = "é🙂" + str(1)
        \\    out.print(score(text), score(""), first(text), first(""))
        \\    mut long = ""
        \\    for i in range(1027):
        \\        long += "a"
        \\    out.print(score(long))
        \\    mut old = "ab" + str(1)
        \\    mut raw = old.encode()
        \\    old = "replacement"
        \\    out.print(len(raw), raw[0], raw[-1], len(old))
        \\    mut invalid = b"\xff\x80\x00"
        \\    out.print(len(invalid), invalid[0], invalid[-1])
        \\    return 0
    , "1102 0 49 0\n100646\n3 97 49 11\n3 255 0\n", true);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow native located bounds preserve written extreme indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "3", "-4", "9223372036854775807", "-9223372036854775808" }) |index| {
        const source = try std.fmt.allocPrint(a, "func read(text: str, index: int) -> int:\n    mut raw = text.encode()\n    return raw[index]\nfunc main(out: Stream) -> int:\n    out.print(read(\"abc\", {s}))\n    return 0\n", .{index});
        var unit = try @import("mylang").Compilation.init(a, "encode.my", source);
        try unit.check();
        for (lanes) |lane| {
            var refusal: build.Refusal = .{};
            var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
            const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
            const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
            try std.testing.expectEqual(@as(u8, 1), run.status);
            try std.testing.expectEqualStrings("", run.stdout);
            const message = try std.fmt.allocPrint(a, "error[R_LIST_BOUNDS]: native execution failed (index {s}, length 3)", .{index});
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, message) != null);
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, "MYL_CORE_LEAKCHECK") == null);
        }
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow refuses extern lookalikes and malformed runtime signatures" {
    const source =
        \\func main() -> int:
        \\    mut raw = "é".encode()
        \\    return len(raw)
    ;
    for (0..5) |variant| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: build.Refusal = .{};
        var module = try buildSource(a, source, &refusal);
        module.zero_rc = true;
        var found = false;
        for (module.functions.items) |*f| {
            if (!std.mem.eql(u8, f.name, "myl_core_text_encode")) continue;
            found = true;
            f.signature.linkage = .runtime_c;
            switch (variant) {
                0 => f.signature.linkage = .extern_c,
                1 => f.signature.params = &.{.bytes},
                2 => f.signature.owned = 1,
                3 => f.signature.views = 1,
                4 => f.signature.consumes = 1,
                else => unreachable,
            }
        }
        try std.testing.expect(found);
        try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
        try std.testing.expectEqual(@as(usize, 0), count(&module, .str_view_of));
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow native escaping bytes remain independent after source update" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try execute(arena.allocator(),
        \\func encoded(text: str) -> bytes:
        \\    return text.encode()
        \\func score(raw: bytes) -> int:
        \\    mut sum = len(raw)
        \\    for value in raw:
        \\        sum += value
        \\    return sum
        \\func main(out: Stream) -> int:
        \\    mut text = "é" + str(1)
        \\    mut returned = encoded(text)
        \\    mut local = text.encode()
        \\    mut saved = [local]
        \\    text += "changed"
        \\    out.print(score(returned), score(saved[0]), len(text))
        \\    return 0
    , "416 416 9\n", false);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow refuses malformed existing span helper without duplicate native declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try buildSource(a,
        \\func main() -> int:
        \\    mut raw = "é".encode()
        \\    return len(raw)
    , &refusal);
    try module.functions.append(a, .{ .name = "myl_core_span_bytes_index_offset", .signature = .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .extern_c } });
    const before = module.functions.items.len;
    try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
    try std.testing.expectEqual(before, module.functions.items.len);
    try std.testing.expectEqual(@as(usize, 0), count(&module, .str_view_of));
}

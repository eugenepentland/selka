//! Whole-use proof for local octet encodings and independent-owner fallback.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const report = std.debug.print;
const fusion = @import("fuse_encode.zig");

/// Check `source` (an embedded project when it imports `strings`, W13-S5) and build its executable module.
fn buildSource(a: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) !ir.Module {
    return build.buildExecutable(a, .{
        .program = try support.checkedProgram(a, source),
    }, refusal);
}

fn count(module: *const ir.Module, op: ir.Op) usize {
    var n: usize = 0;
    for (module.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op == op) n += 1;
    };
    return n;
}

/// Preserve old negative-index fixtures as removal regressions while executing
/// modern counterparts with the same explicit from-end intent.
fn modernNegativeIndexes(a: std.mem.Allocator, legacy: []const u8) ![]const u8 {
    const checked = try support.checkSource(a, legacy);
    try std.testing.expect(!checked.passed);
    var removed = false;
    for (checked.diagnostics) |diagnostic| {
        if (std.mem.startsWith(u8, diagnostic.code, "E_")) {
            try std.testing.expectEqualStrings("E_NEGATIVE_INDEX_REMOVED", diagnostic.code);
            removed = true;
        }
    }
    try std.testing.expect(removed);
    const raw = try std.mem.replaceOwned(u8, a, legacy, "raw[-1]", "raw[len(raw) - 1]");
    return std.mem.replaceOwned(u8, a, raw, "invalid[-1]", "invalid[len(invalid) - 1]");
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow reads UTF8 octets with lengths and explicit from-end indexes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    // migrate-embedded: skip intentional removed negative indexes
    const legacy_source =
        \\import strings
        \\
        \\func score(text: str) -> int:
        \\    mut raw = strings.encode(text)
        \\    mut sum = len(raw)
        \\    for b in raw:
        \\        sum += b
        \\    if len(raw) > 0:
        \\        sum += raw[-1]
        \\    return sum
        \\func main() -> int:
        \\    return score("é🙂") + score("")
    ;
    const source = try modernNegativeIndexes(a, legacy_source);
    var module = try buildSource(a, source, &refusal);
    _ = try fusion.runRecording(a, &module, null);
    try std.testing.expect(count(&module, .str_view_of) > 0);
    try support.verified(a, &module, &.{});
}
// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow preserves return store and opaque call ownership" {
    const cases = [_][]const u8{
        "import strings\n\nfunc test(text: str) -> bytes:\n    return strings.encode(text)\n",
        "import strings\n\nfunc test(text: str) -> int:\n    mut raw = strings.encode(text)\n    const stored = [raw]\n    return len(stored[0])\n",
        "import strings\n\nfunc use(raw: bytes) -> int:\n    return len(raw)\nfunc test(text: str) -> int:\n    mut raw = strings.encode(text)\n    return use(raw)\n",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: build.Refusal = .{};
        const entry = if (std.mem.indexOf(u8, source, "-> bytes:") != null)
            "func main() -> int:\n    return len(test(\"é\"))\n"
        else
            "func main() -> int:\n    return test(\"é\")\n";
        const complete = try std.mem.concat(a, u8, &.{ source, entry });
        var module = try buildSource(a, complete, &refusal);
        try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
        try support.verified(a, &module, &.{});
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow keeps original octets alive across independent append ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const original = "import strings\n\nfunc test(mut text: str) -> int:\n    mut raw = strings.encode(text)\n    text += \"x\"\n    return len(raw)\n";
    const complete = try std.mem.concat(a, u8, &.{ original, "func main() -> int:\n    mut text = \"é\"\n    return test(mut text)\n" });
    var module = try buildSource(a, complete, &refusal);
    // Addition owns an independent left operand; the encoded view retains its
    // original source until its final read, including after copy donation.
    try std.testing.expectEqual(@as(u32, 1), try fusion.runRecording(a, &module, null));
    try std.testing.expectEqual(@as(usize, 1), count(&module, .str_view_of));
    try support.verified(a, &module, &.{});
    try execute(a,
        \\import strings
        \\
        \\func observe(mut text: str, out: Stream) -> int:
        \\    mut raw = strings.encode(text)
        \\    text += " changed"
        \\    print(out, len(raw), raw[0], raw[1], raw[2], text)
        \\    return 0
        \\func main(out: Stream) -> int:
        \\    mut text = "é" + str(1)
        \\    return observe(mut text, out)
    , "3 195 169 49 é1 changed\n", true);
}

const Lane = struct { release: bool, mode: ?passes.Mode };
const lanes = [_]Lane{
    .{ .release = false, .mode = null },
    .{ .release = false, .mode = .trusted },
    .{ .release = true, .mode = .trusted },
    .{ .release = true, .mode = .verify },
    .{ .release = true, .mode = .off },
};

fn execute(a: std.mem.Allocator, source: []const u8, expected: []const u8, borrow: bool) !void {
    const program = try support.checkedProgram(a, source);
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").check(a, program, &failure);
    for (lanes) |lane| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{
            .program = program,
        }, &refusal);
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
    // migrate-embedded: skip intentional removed negative indexes
    const legacy_source =
        \\import strings
        \\
        \\func score(text: str) -> int:
        \\    mut raw = strings.encode(text)
        \\    mut sum = len(raw)
        \\    for value in raw:
        \\        sum += value
        \\    return sum
        \\func first(text: str) -> int:
        \\    mut raw = strings.encode(text)
        \\    if len(raw) == 0:
        \\        return 0
        \\    return raw[-1]
        \\func main(out: Stream) -> int:
        \\    mut text = "é🙂" + str(1)
        \\    print(out, score(text), score(""), first(text), first(""))
        \\    mut long = ""
        \\    for i in range(1027):
        \\        long += "a"
        \\    print(out, score(long))
        \\    mut old = "ab" + str(1)
        \\    mut raw = strings.encode(old)
        \\    old = "replacement"
        \\    print(out, len(raw), raw[0], raw[-1], strings.char_count(old))
        \\    mut invalid = b"\xff\x80\x00"
        \\    print(out, len(invalid), invalid[0], invalid[-1])
        \\    return 0
    ;
    const source = try modernNegativeIndexes(arena.allocator(), legacy_source);
    try execute(arena.allocator(), source, "1102 0 49 0\n100646\n3 97 49 11\n3 255 0\n", true);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow native located bounds preserve written extreme indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "3", "-4", "9223372036854775807", "-9223372036854775808" }) |index| {
        const reader = "import strings\n\nfunc read(text: str, index: int) -> int:\n    mut raw = strings.encode(text)\n    return raw[index]\n";
        const source = try std.fmt.allocPrint(a, reader ++ "func main(out: Stream) -> int:\n    print(out, read(\"abc\", {s}))\n    return 0\n", .{index});
        const program = try support.checkedProgram(a, source);
        for (lanes) |lane| {
            var refusal: build.Refusal = .{};
            var module = try build.buildExecutable(a, .{
                .program = program,
            }, &refusal);
            const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
            const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
            try std.testing.expectEqual(@as(u8, 1), run.status);
            try std.testing.expectEqualStrings("", run.stdout);
            const message = try std.fmt.allocPrint(a, "error[R_LIST_BOUNDS]: native execution failed (index {s}, length 3)", .{index});
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, message) != null);
            try std.testing.expect(std.mem.indexOf(u8, run.stderr, "SELKA_CORE_LEAKCHECK") == null);
        }
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "encode borrow refuses extern lookalikes and malformed runtime signatures" {
    const source =
        \\import strings
        \\
        \\func main() -> int:
        \\    mut raw = strings.encode("é")
        \\    return len(raw)
    ;
    for (0..5) |variant| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: build.Refusal = .{};
        var module = try buildSource(a, source, &refusal);
        var found = false;
        for (module.functions.items) |*f| {
            if (!std.mem.eql(u8, f.name, "myl_core_text_encode")) continue;
            found = true;
            f.signature.linkage = .runtime_c;
            switch (variant) {
                0 => f.signature.linkage = .extern_c,
                1 => f.signature.params = &.{.bytes},
                2 => f.signature.passing.owned = 1,
                3 => f.signature.passing.views = 1,
                4 => f.signature.passing.consumes = 1,
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
        \\import strings
        \\
        \\func encoded(text: str) -> bytes:
        \\    return strings.encode(text)
        \\func score(raw: bytes) -> int:
        \\    mut sum = len(raw)
        \\    for value in raw:
        \\        sum += value
        \\    return sum
        \\func main(out: Stream) -> int:
        \\    mut text = "é" + str(1)
        \\    mut returned = encoded(text)
        \\    mut local = strings.encode(text)
        \\    mut saved = [own local]
        \\    text += "changed"
        \\    print(out, score(returned), score(saved[0]), strings.char_count(text))
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
        \\import strings
        \\
        \\func main() -> int:
        \\    mut raw = strings.encode("é")
        \\    return len(raw)
    , &refusal);
    try module.functions.append(a, .{ .name = "myl_core_span_bytes_index_offset", .signature = .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .extern_c } });
    const before = module.functions.items.len;
    try std.testing.expectEqual(@as(u32, 0), try fusion.runRecording(a, &module, null));
    try std.testing.expectEqual(before, module.functions.items.len);
    try std.testing.expectEqual(@as(usize, 0), count(&module, .str_view_of));
}

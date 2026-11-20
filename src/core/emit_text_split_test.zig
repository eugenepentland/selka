//! Private cursor emission preserves signed boundaries and runtime authority.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const cursor = @import("emit_text_split.zig");

// spec-case: NEW-CORE-S2-SPLIT-3
test "private text view stability accounts for managed phi ownership transfers" {
    for ([_]ir.Type{ .str, .bytes, .i64 }) |ty| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module: ir.Module = .{};
        var hand = try support.Hand.init(a, &module, "joined", .{ .params = &.{ ty, .bool }, .ret = .void });
        const source = try hand.param(0);
        const condition = try hand.param(1);
        const left = try hand.newBlock();
        const right = try hand.newBlock();
        const joined = try hand.newBlock();
        try hand.branch(condition, left, right);
        hand.block = left;
        try hand.jump(joined);
        hand.block = right;
        try hand.jump(joined);
        hand.block = joined;
        _ = try hand.emit(.{ .op = .phi, .ty = ty, .data = try hand.extra(&.{ source, source }) });
        _ = try hand.emit(.{ .op = .ret, .ty = .void });
        _ = try hand.finish();
        try support.verified(a, &module, &.{});
        try std.testing.expectEqual(ty != .i64, try @import("fuse_slice_key.zig").updated(a, &module.functions.items[0], &module, source));
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private whitespace cursor emission requires exact runtime authority and signature masks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const signature: ir.Signature = .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c };
    try module.functions.append(a, .{ .name = "myl_core_split_ws_start", .signature = signature });
    const call: ir.Inst = .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0) };
    try std.testing.expectEqual(@as(?bool, true), cursor.adapter(&module, call));
    module.functions.items[0].name = "myl_core_split_ws_end";
    try std.testing.expectEqual(@as(?bool, false), cursor.adapter(&module, call));
    for ([_]ir.Signature{
        .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .extern_c },
        .{ .params = &.{ .str, .i64 }, .ret = .i64 },
        .{ .params = &.{ .bytes, .i64 }, .ret = .i64, .linkage = .runtime_c },
        .{ .params = &.{ .str, .u64 }, .ret = .i64, .linkage = .runtime_c },
        .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c },
        .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c, .passing = .{ .owned = 1 } },
        .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c, .passing = .{ .views = 1 } },
    }) |near_miss| {
        module.functions.items[0].signature = near_miss;
        try std.testing.expectEqual(@as(?bool, null), cursor.adapter(&module, call));
    }
    module.functions.items[0].signature = signature;
    module.functions.items[0].name = "ordinary_cursor";
    try std.testing.expectEqual(@as(?bool, null), cursor.adapter(&module, call));
}

const Case = struct { bytes: []const u8, offsets: []const i64, output: []const u8 };
const boundaries = [_]Case{
    .{ .bytes = "", .offsets = &.{ 0, -1, std.math.maxInt(i64) }, .output = "0 0\n-1 -1\n9223372036854775807 9223372036854775807\n" },
    .{ .bytes = " \t\n\r\x0b\x0c", .offsets = &.{ 0, 6 }, .output = "6 0\n6 6\n" },
    .{ .bytes = " \t\n\r\x0b\x0cé\xc2\xa0x\t😀\n", .offsets = &.{ 0, 6, 11, 12, 16, 17, 18, -1, std.math.minInt(i64) }, .output = "6 0\n6 11\n12 11\n12 16\n17 16\n17 17\n18 18\n-1 -1\n-9223372036854775808 -9223372036854775808\n" },
};

fn handModule(a: std.mem.Allocator, linkage: ir.Linkage) !ir.Module {
    var module: ir.Module = .{};
    for (boundaries) |case| try module.strings.append(a, case.bytes);
    for ([_][]const u8{ "myl_core_split_ws_start", "myl_core_split_ws_end" }) |name| {
        try module.functions.append(a, .{ .name = name, .signature = .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = linkage } });
    }
    var hand = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const output = try hand.param(0);
    for (boundaries, 0..) |case, index| {
        const text = try hand.loose(.{ .op = .str_const, .ty = .str, .data = index });
        for (case.offsets) |offset| {
            const at = try hand.int(.i64, offset);
            const args = try hand.extra(&.{ text, at });
            const start = try hand.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = args });
            const end = try hand.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(1), .data = args });
            try hand.printValues(output, &.{ start, end });
        }
    }
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, 0) });
    module.entry = try hand.finish();
    return module;
}

fn nativeBoundaries(a: std.mem.Allocator, linkage: ir.Linkage) !void {
    var expected: std.ArrayList(u8) = .empty;
    for (boundaries) |case| try expected.appendSlice(a, case.output);
    for ([_]support.RunOptions{ .{}, .{ .release = true }, .{ .release = true, .verify = true } }) |mode| {
        var module = try handModule(a, linkage);
        const result = try support.runOwned(a, &module, mode);
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings(expected.items, result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        const has_call = std.mem.indexOf(u8, result.llvm, "call i64 @myl_core_split_ws_start") != null;
        try std.testing.expectEqual(linkage == .extern_c, has_call);
        try std.testing.expectEqual(linkage == .runtime_c, std.mem.indexOf(u8, result.llvm, "%splitnonnegative") != null);
    }
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "private whitespace cursor LLVM guards negative empty Unicode and past-end inputs in every mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeBoundaries(arena.allocator(), .runtime_c);
}

// spec-case: NEW-CORE-TEXT-BYTES-1
test "extern whitespace cursor calls retain their C boundary implementation in every mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try nativeBoundaries(arena.allocator(), .extern_c);
}

// spec-case: NEW-CORE-S2-SPLIT-3
test "private whitespace split defers checked key copies and refuses escaping copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const build = @import("build.zig");
    const fusion = @import("fuse_text_split.zig");
    const source =
        \\import dicts
        \\import strings
        \\
        \\func words(s: str) -> dict[str, int]:
        \\    mut counts: dict[str, int] = {}
        \\    for word in strings.words(s):
        \\        counts[copy(copy(word))] = dicts.get(counts, word, 0) + 1
        \\    return counts
        \\func escaped(s: str) -> str[]:
        \\    mut result: str[] = []
        \\    for word in strings.words(s):
        \\        append(mut result, copy(word))
        \\    return result
        \\func changed(s: str) -> dict[str, int]:
        \\    mut source = copy(s)
        \\    mut counts: dict[str, int] = {}
        \\    for word in strings.words(source):
        \\        source += "x"
        \\        counts[copy(word)] = 1
        \\    return counts
        \\func separator_changed(s: str) -> int:
        \\    mut separator = ","
        \\    mut total = 0
        \\    for part in strings.split(s, separator):
        \\        total += strings.char_count(part)
        \\        separator += "x"
        \\    return total
        \\func main(out: Stream) -> int:
        \\    mut counts = words("a b a")
        \\    print(out, counts["a"], escaped("x y"), len(changed("a b")), separator_changed("a,b"))
        \\    return 0
    ;
    var refusal: build.Refusal = .{};
    var module = try support.projectModule(a, source, &refusal);
    try fusion.run(a, &module);
    var authorized_copy = false;
    var words_views: usize = 0;
    var words_copies: usize = 0;
    var escaped_splits: usize = 0;
    var changed_splits: usize = 0;
    var separator_splits: usize = 0;
    for (module.functions.items) |function| {
        if (std.mem.eql(u8, function.name, "myl_core_owned_octets_copy")) {
            try std.testing.expectEqual(.runtime_c, function.signature.linkage);
            try std.testing.expectEqual(@as(u64, 0), function.signature.passing.owned);
            try std.testing.expectEqual(@as(u64, 0), function.signature.passing.consumes);
            authorized_copy = true;
        }
        for (function.insts.items) |inst| {
            if (std.mem.eql(u8, function.name, "main::words")) {
                if (inst.op == .str_view_of) words_views += 1;
                if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_owned_octets_copy")) words_copies += 1;
            }
            if (std.mem.eql(u8, function.name, "main::separator_changed") and inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split")) separator_splits += 1;
            if (std.mem.eql(u8, function.name, "main::changed") and inst.op == .call and isWhitespaceSplit(module.functions.items[inst.a.index()].name)) changed_splits += 1;
            if (std.mem.eql(u8, function.name, "main::escaped") and inst.op == .call and isWhitespaceSplit(module.functions.items[inst.a.index()].name)) escaped_splits += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), words_views);
    try std.testing.expect(authorized_copy);
    try std.testing.expectEqual(@as(usize, 0), words_copies);
    try std.testing.expectEqual(@as(usize, 1), escaped_splits);
    try std.testing.expectEqual(@as(usize, 1), changed_splits);
    try std.testing.expectEqual(@as(usize, 1), separator_splits);
    try support.verified(a, &module, &.{});
}

// spec-case: NEW-CORE-S2-SPLIT-3
test "private whitespace split copy recognition requires runtime authority and borrowing signature" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const build = @import("build.zig");
    const source =
        \\import strings
        \\
        \\func words(s: str) -> dict[str, int]:
        \\    mut counts: dict[str, int] = {}
        \\    for word in strings.words(s):
        \\        counts[copy(word)] = 1
        \\    return counts
        \\func main(out: Stream) -> int:
        \\    mut counts = words("a b")
        \\    print(out, len(counts))
        \\    return 0
    ;
    // The fixture imports `strings` for `strings.words` (W13-S5), so it is checked as an embedded project.
    const program = try support.checkedProgram(a, source);
    for ([_]ir.Signature{
        .{ .params = &.{.str}, .ret = .str, .linkage = .extern_c },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .passing = .{ .owned = 1 } },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .passing = .{ .consumes = 1 } },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .passing = .{ .views = 1 } },
    }) |signature| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{
            .program = program,
        }, &refusal);
        for (module.functions.items) |*function| {
            if (std.mem.eql(u8, function.name, "myl_core_owned_octets_copy")) function.signature = signature;
        }
        try @import("fuse_text_split.zig").run(a, &module);
        var splits: usize = 0;
        for (module.functions.items) |function| {
            for (function.insts.items) |inst| {
                if (inst.op == .call and isWhitespaceSplit(module.functions.items[inst.a.index()].name)) splits += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), splits);
    }
}

/// The whitespace split's two forms (`copy_sites.isWhitespaceSplit`).
fn isWhitespaceSplit(name: []const u8) bool {
    return @import("copy_sites.zig").isWhitespaceSplit(name);
}

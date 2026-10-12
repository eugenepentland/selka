//! Private cursor emission preserves signed boundaries and runtime authority.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const cursor = @import("emit_text_split.zig");

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
        .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c, .owned = 1 },
        .{ .params = &.{ .str, .i64 }, .ret = .i64, .linkage = .runtime_c, .views = 1 },
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
    const language = @import("mylang");
    const build = @import("build.zig");
    const fusion = @import("fuse_text_split.zig");
    const source =
        \\func words(s: str) -> dict[str, int]:
        \\    mut counts: dict[str, int] = {}
        \\    for word in s.split():
        \\        counts[word.copy().copy()] = counts.get(word, 0) + 1
        \\    return counts
        \\func escaped(s: str) -> str[]:
        \\    mut result: str[] = []
        \\    for word in s.split():
        \\        result.append(word.copy())
        \\    return result
        \\func changed(s: str) -> dict[str, int]:
        \\    mut source = s.copy()
        \\    mut counts: dict[str, int] = {}
        \\    for word in source.split():
        \\        source += "x"
        \\        counts[word.copy()] = 1
        \\    return counts
        \\func separator_changed(s: str) -> int:
        \\    mut separator = ","
        \\    mut total = 0
        \\    for part in s.split(separator):
        \\        total += len(part)
        \\        separator += "x"
        \\    return total
        \\func main(out: Stream) -> int:
        \\    mut counts = words("a b a")
        \\    out.print(counts["a"], escaped("x y"), len(changed("a b")), separator_changed("a,b"))
        \\    return 0
    ;
    var unit = try language.Compilation.init(a, "words.my", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    try fusion.run(a, &module);
    var words_views: usize = 0;
    var words_copies: usize = 0;
    var escaped_splits: usize = 0;
    var changed_splits: usize = 0;
    var separator_splits: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| {
            if (std.mem.eql(u8, function.name, "words")) {
                if (inst.op == .str_view_of) words_views += 1;
                if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_owned_octets_copy")) words_copies += 1;
            }
            if (std.mem.eql(u8, function.name, "separator_changed") and inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split")) separator_splits += 1;
            if (std.mem.eql(u8, function.name, "changed") and inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split_whitespace")) changed_splits += 1;
            if (std.mem.eql(u8, function.name, "escaped") and inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split_whitespace")) escaped_splits += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), words_views);
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
    const language = @import("mylang");
    const build = @import("build.zig");
    const source =
        \\func words(s: str) -> dict[str, int]:
        \\    mut counts: dict[str, int] = {}
        \\    for word in s.split():
        \\        counts[word.copy()] = 1
        \\    return counts
        \\func main(out: Stream) -> int:
        \\    mut counts = words("a b")
        \\    out.print(len(counts))
        \\    return 0
    ;
    var unit = try language.Compilation.init(a, "words.my", source);
    try unit.check();
    for ([_]ir.Signature{
        .{ .params = &.{.str}, .ret = .str, .linkage = .extern_c },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .owned = 1 },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .consumes = 1 },
        .{ .params = &.{.str}, .ret = .str, .linkage = .runtime_c, .views = 1 },
    }) |signature| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
        for (module.functions.items) |*function| {
            if (std.mem.eql(u8, function.name, "myl_core_owned_octets_copy")) function.signature = signature;
        }
        try @import("fuse_text_split.zig").run(a, &module);
        var splits: usize = 0;
        for (module.functions.items) |function| {
            for (function.insts.items) |inst| {
                if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_split_whitespace")) splits += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), splits);
    }
}

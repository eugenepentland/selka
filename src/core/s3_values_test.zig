//! Deep shared value graphs, rendering and repeat snapshot qualification.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn location(_: *const anyopaque, offset: u32) @import("emit_llvm.zig").Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn qualified(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const fixture = try std.fmt.allocPrint(a, "{s}/m_recursive_values.selka", .{options.fixtures});
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "test", fixture, "--json", "--cache-dir", root });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 0 or result.stderr.len != 0)
            report("S3 values fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 10), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
    }
}

// spec: NEW-CORE-S3-VALUES-1
test "S3 values preserve source shapes unit payloads marker data and ancestor supersession" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}

// spec-case: NEW-CORE-S3-VALUES-1
test "a named unit used after an indexed-place join remains a valid record replacement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\record Holder:
        \\    value: Unit
        \\func main() -> int:
        \\    mut empty: Unit = ()
        \\    mut values = [Holder(value=empty)]
        \\    values[0].value = empty
        \\    return len(values)
    ;
    var refusal: @import("build.zig").Refusal = .{};
    const module = try @import("test_support.zig").buildSource(arena.allocator(), source, &refusal);
    var replaced = false;
    for (module.functions.items[module.entry].insts.items) |inst| {
        if (inst.op == .phi) try std.testing.expect(inst.ty != .void);
        replaced = replaced or inst.op == .record_set;
    }
    try std.testing.expect(replaced);
}

// spec-case: NEW-CORE-S3-VALUES-1
test "S3 value adapter names in source extern declarations confer no compiler authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ir = @import("ir.zig");
    const emit = @import("emit_llvm.zig");
    const support = @import("test_support.zig");
    var module: ir.Module = .{};
    for ([_][]const u8{ "myl_core_equal_77", "myl_core_show_77", "myl_core_render_shape_0_77" }) |name| {
        try module.functions.append(a, .{ .name = name, .signature = .{ .params = &.{.i64}, .ret = .i64, .linkage = .extern_c } });
    }
    var hand = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .i64 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, 7) });
    module.entry = try hand.finish();
    try support.verified(a, &module, &.{});
    const context: u8 = 0;
    const llvm = try emit.emitModule(a, &module, .{ .locator = .{ .context = &context, .locate = location }, .source_path = "authority.selka", .main = .{ .parameters = &.{} } });
    try std.testing.expect(std.mem.indexOf(u8, llvm, "declare i64 @myl_core_equal_77(i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "declare i64 @myl_core_show_77(i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "declare i64 @myl_core_render_shape_0_77(i64)") != null);
    try module.strings.append(a, "\x00myl.core.render.source.77|not-json");
    try module.functions.append(a, .{ .name = "myl_core_render_shape_0_77", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } });
    var descriptors: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.UnsupportedInstruction, @import("emit_render.zig").descriptors(a, &module, &descriptors));
}

// spec-case: NEW-CORE-MUT-1
test "S3 mut places refuse unmodeled selection and interior ancestor pin cases with locations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const selection =
        \\func replace_index(mut rows: int[][]) -> int:
        \\    rows = [[8]]
        \\    return 0
        \\func add(mut row: int[], ignored: int) -> Unit:
        \\    row.append(9)
        \\func main() -> int:
        \\    mut rows = [[1]]
        \\    add(mut rows[replace_index(mut rows)], 0)
        \\    return len(rows)
    ;
    const interior =
        \\func tick(mut parent: int[][]) -> int:
        \\    parent.append([7])
        \\    return 0
        \\func add(mut row: int[], ignored: int) -> Unit:
        \\    row.append(9)
        \\func main() -> int:
        \\    mut rows = [[[1]], [[2]]]
        \\    add(mut rows[1][0], tick(mut rows[1]))
        \\    return len(rows)
    ;
    const cases = [_]struct { source: []const u8, reason: []const u8 }{
        .{ .source = selection, .reason = "interior mut place changed while its index or key was evaluated" },
        .{ .source = interior, .reason = "interior mut argument ancestor changed by a later interior write" },
    };
    for (cases) |case| {
        var refusal: @import("build.zig").Refusal = .{};
        try std.testing.expectError(error.Unsupported, @import("test_support.zig").buildSource(a, case.source, &refusal));
        try std.testing.expectEqualStrings(case.reason, refusal.reason);
        try std.testing.expect(refusal.span > 0);
    }
}

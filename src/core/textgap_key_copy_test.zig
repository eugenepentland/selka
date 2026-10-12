//! Local independent key snapshots borrow only when their complete lifetime is read-only.
const std = @import("std");
const report = std.debug.print;
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const source =
    \\func add(mut values: dict[str, int], texts: str[]):
    \\    for text in texts:
    \\        const key = text.copy()
    \\        values[key] = values.get(key, 0) + 1
    \\func replace(mut values: dict[str, int], mut texts: str[]):
    \\    const key = texts[0].copy()
    \\    texts[0] = "new"
    \\    values[key] = values.get(key, 0) + 1
    \\func main(out: Stream) -> int:
    \\    mut texts = ["é" + str(7), "é" + str(7), "🙂" + str(8)]
    \\    mut values: dict[str, int] = {}
    \\    add(mut values, texts)
    \\    add(mut values, texts)
    \\    replace(mut values, mut texts)
    \\    texts[1] = "changed"
    \\    out.print(values["é7"], values["🙂8"], texts[0], len(values))
    \\    return 0
;

fn buildSource(a: std.mem.Allocator) !ir.Module {
    var unit = try @import("mylang").Compilation.init(a, "keys.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |d| report("{s}\n", .{try d.render(a, unit.src)});
        return err;
    };
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
}

fn copies(module: *const ir.Module, name: []const u8) usize {
    var result: usize = 0;
    for (module.functions.items) |*f| {
        if (!std.mem.eql(u8, f.name, name)) continue;
        for (f.blocks.items) |block| for (block.insts.items) |ref| {
            if (@import("inline_snapshot.zig").source(module, f, f.inst(ref)) != null) result += 1;
        };
    }
    return result;
}

// spec-case: NEW-CORE-S1-VIEW-1
test "textgap_key_copy borrows stable lookup keys but retains replaced parent snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try buildSource(a);
    try std.testing.expect(copies(&module, "add") != 0);
    try std.testing.expect(copies(&module, "replace") != 0);
    _ = try passes.run(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), copies(&module, "add"));
    try std.testing.expect(copies(&module, "replace") != 0);
}

// spec-case: NEW-CORE-S1-VIEW-1
test "textgap_key_copy native misses own keys and hits borrow through Unicode and replacement" {
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
        var module = try buildSource(a);
        const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
        if (run.status != 0) report("keys: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("5 2 new 2\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
    }
}

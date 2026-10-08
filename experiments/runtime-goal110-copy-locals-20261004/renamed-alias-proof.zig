//! Copy to the worktree root before zig test so relative src imports stay in one module.
const std = @import("std");
const il = @import("src/qbe_build_llvm_il.zig");
const emit = @import("src/qbe_build_llvm_emit.zig");
const classes = @import("src/qbe_build_llvm_classes.zig");
const runtime = @import("src/qbe_build_llvm_runtime.zig");
const sticky = @import("src/qbe_build_llvm_sticky.zig");

test "actual before, rejected and renamed LLVM alias facts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var output: std.Io.Writer.Allocating = .init(a);
    try output.writer.writeAll("arm\ttemporary\tdefinitions_after_sticky\tclass\tload_store_alias_suffix\n");
    const signatures: emit.Signatures = .empty;
    const table: runtime.Table = .{};
    const cases = [_][]const u8{ "before", "rejected", "renamed" };
    var baseline: ?emit.Emitter = null;
    var losses: std.Io.Writer.Allocating = .init(a);
    try losses.writer.writeAll("arm\ttemporary\tdefinitions_after_sticky\tbefore_class\tafter_class\n");
    const names = [_][]const u8{ "ctx", "s0", "s1", "l86", "l89", "l90", "v8324", "v8326", "v8327", "v8343", "v8332", "v8370", "v8484", "u4_v8324", "u4_v8326", "u4_v8370" };
    for (cases) |arm| {
        const path = if (std.mem.eql(u8, arm, "renamed")) "experiments/runtime-goal110-copy-locals-20261004/candidate-actual-main.ssa" else try std.fmt.allocPrint(a, "experiments/runtime-goal110-calls-20261004/{s}-actual-main.ssa", .{if (std.mem.eql(u8, arm, "before")) "before" else "candidate"});
        const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(4 << 20));
        var diagnostic: il.Diagnostic = .{};
        const unit = try il.parse(a, text, &diagnostic);
        try sticky.versionLoops(a, unit, &diagnostic);
        const counts = try classes.definitionCounts(a, &unit.function);
        var e = try emit.Emitter.prepare(a, unit, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
        if (baseline) |*original| {
            var known = original.facts.memory.?.classes.keyIterator();
            while (known.next()) |key| {
                const operand: il.Operand = .{ .temp = .{ .name = key.* } };
                const before = original.facts.memory.?.accessClass(operand).?;
                const after = e.facts.memory.?.accessClass(operand);
                if (after != null and before.eql(after.?)) continue;
                try losses.writer.print("{s}\t{s}\t{d}\t{s}\t{s}\n", .{ arm, key.*, counts.get(key.*) orelse 0, @tagName(before), if (after) |class| @tagName(class) else "unknown" });
            }
        } else baseline = e;
        for (names) |name| {
            const operand: il.Operand = .{ .temp = .{ .name = name } };
            const class = e.facts.memory.?.accessClass(operand);
            const class_name = if (class) |known| @tagName(known) else "unknown";
            try output.writer.print("{s}\t{s}\t{d}\t{s}\t{s}\n", .{ arm, name, counts.get(name) orelse 0, class_name, try e.aliasOf(operand) });
        }
    }
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = "experiments/runtime-goal110-copy-locals-20261004/alias-facts.tsv", .data = output.written() });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = "experiments/runtime-goal110-copy-locals-20261004/remaining-fact-losses.tsv", .data = losses.written() });
}

//! Copy to the worktree root before testing so source imports stay in one module.
const std = @import("std");
const il = @import("src/qbe_build_llvm_il.zig");
const classes = @import("src/qbe_build_llvm_classes.zig");
const slots = @import("src/qbe_build_llvm_slots.zig");
const sticky = @import("src/qbe_build_llvm_sticky.zig");

test "actual compute scalar slot admission after sticky rewriting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = ".mylang-cache/goal110-scalar-slots-guests/llvm-dump/myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5.ssa";
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(4 << 20));
    var diagnostic: il.Diagnostic = .{};
    const unit = try il.parse(a, source, &diagnostic);
    try sticky.versionLoops(a, unit, &diagnostic);
    const counts = try classes.definitionCounts(a, &unit.function);
    const plan = try slots.find(a, &unit.function, &counts);
    var output: std.Io.Writer.Allocating = .init(a);
    try output.writer.writeAll("temporary\tallocation_block\tposition\tsize\tdefinitions\tadmitted\n");
    for (unit.function.blocks.items) |block| for (block.instructions.items, 0..) |instruction, position| {
        if (instruction.opcode != .alloc4 and instruction.opcode != .alloc8 and instruction.opcode != .alloc16) continue;
        const name = instruction.dest orelse continue;
        const size = if (instruction.args[0] == .constant) instruction.args[0].constant.text else "dynamic";
        try output.writer.print("{s}\t{s}\t{d}\t{s}\t{d}\t{}\n", .{ name, block.label, position, size, counts.get(name) orelse 0, plan.contains(name) });
    };
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = "experiments/runtime-goal110-scalar-slots-20261004/actual-compute-admissions.tsv", .data = output.written() });
}

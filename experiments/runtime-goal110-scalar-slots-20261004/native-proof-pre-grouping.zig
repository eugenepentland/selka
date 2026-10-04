//! Copy to the worktree root before testing so source imports remain in one module.
const std = @import("std");
const llvm = @import("src/qbe_build_llvm.zig");

const bodies = [_][]const u8{
    " %cell =l alloc8 8\n %index =l alloc8 8\n storel %seed, %cell\n storel 0, %index\n jmp @condition\n@condition\n %i =l loadl %index\n %again =l csltl %i, %count\n jnz %again, @loop, @done\n@loop\n %value =l loadl %cell\n %next =l add %value, %i\n storel %next, %cell\n %increment =l add %i, 1\n storel %increment, %index\n jmp @condition\n@done\n %result =l loadl %cell\n ret %result",
    " %total =l alloc8 8\n %index =l alloc8 8\n storel %seed, %total\n storel 0, %index\n jmp @condition\n@condition\n %i =l loadl %index\n %again =l csltl %i, %count\n jnz %again, @loop, @done\n@loop\n %cell =l alloc8 8\n %value =l loadl %total\n %next =l add %value, %i\n storel %next, %cell\n %read =l loadl %cell\n storel %read, %total\n %increment =l add %i, 1\n storel %increment, %index\n jmp @condition\n@done\n %result =l loadl %total\n ret %result",
    " %cell =l alloc8 8\n storel %seed, %cell\n call $poke(l %cell, l %seed)\n %result =l loadl %cell\n ret %result",
    " %cell =l alloc8 8\n %alias =l add %cell, 0\n %next =l add %seed, 99\n storel %next, %alias\n %result =l loadl %cell\n ret %result",
    " %one =l alloc8 8\n %two =l alloc16 8\n storel %seed, %one\n storel %count, %two\n %first =l loadl %one\n %next =l add %first, 1\n storel %next, %one\n %a =l loadl %one\n %b =l loadl %two\n %result =l add %a, %b\n ret %result",
    " %positive =l csgtl %count, 0\n jnz %positive, @left, @right\n@left\n %cell =l alloc8 8\n %a =l add %seed, 3\n storel %a, %cell\n jmp @join\n@right\n %cell =l alloc8 8\n %b =l add %seed, 7\n storel %b, %cell\n jmp @join\n@join\n %result =l loadl %cell\n ret %result",
};

test "default scalar-slot LLVM and legacy pointer LLVM native inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var signatures: llvm.Signatures = .empty;
    try signatures.put(a, "poke", .{ .parameters = &.{ "l", "l" }, .result = null });
    const table: llvm.RuntimeTable = .{};
    for (bodies, 0..) |body, ordinal| for ([_]bool{ true, false }) |direct| {
        const variant = if (direct) "default" else "legacy";
        const source = try std.fmt.allocPrint(a, "export function l $slot_{d}_{s}(l %count, l %seed) {{\n@start\n{s}\n}}\n", .{ ordinal, variant, body });
        var diagnostic: llvm.Diagnostic = .{};
        const ir = if (direct) try llvm.translate(a, source, .{ .signatures = &signatures, .runtime = &table }, &diagnostic) else try llvm.translate(a, source, .{ .signatures = &signatures, .runtime = &table, .scalar_slots = false }, &diagnostic);
        if (ordinal == 0 or ordinal == 4) {
            try std.testing.expectEqual(if (direct) @as(usize, 0) else 2, std.mem.count(u8, ir, " = ptrtoint ptr "));
        } else if (ordinal == 1) {
            try std.testing.expectEqual(if (direct) @as(usize, 1) else 3, std.mem.count(u8, ir, " = ptrtoint ptr "));
        } else {
            try std.testing.expect(std.mem.count(u8, ir, " = ptrtoint ptr ") != 0);
        }
        const path = try std.fmt.allocPrint(a, "experiments/runtime-goal110-scalar-slots-20261004/slot-{d}-{s}.ll", .{ ordinal, variant });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = ir });
    };
}

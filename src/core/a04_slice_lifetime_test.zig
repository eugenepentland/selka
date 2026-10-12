//! Slice-copy elimination preserves the owner required by an implicit borrow.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const fusion = @import("fuse_slice_key.zig");

fn lowered(a: std.mem.Allocator, source: []const u8) !ir.Module {
    var unit = try language.Compilation.init(a, "slice.my", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .zero_rc = true, .single_owner = true }, &refusal);
}

fn count(module: ir.Module, name: []const u8, op: ir.Op) usize {
    var result: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        for (function.insts.items) |inst| {
            if (inst.op == op) result += 1;
        }
    }
    return result;
}

const moved =
    \\func moved(source: str) -> bool:
    \\    mut owner = source + "!"
    \\    const head = owner[0:3]
    \\    mut values: str[] = []
    \\    values.append(owner)
    \\    values[0] += "?"
    \\    return head == "abc" and len(values) == 1
    \\func main() -> int:
    \\    return if moved("abcdef") then 0 else 1
;

// spec-case: NEW-CORE-S1-VIEW-4
test "A04 slice lifetime keeps a snapshot when its owner moves into storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try lowered(arena.allocator(), moved);
    _ = try fusion.run(arena.allocator(), &module);
    try std.testing.expectEqual(@as(usize, 1), count(module, "moved", .str_slice));
    try std.testing.expectEqual(@as(usize, 0), count(module, "moved", .str_slice_view));
}

// spec-case: NEW-CORE-S1-VIEW-1
test "A04 slice lifetime tracks replacement of a borrowed element parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try lowered(arena.allocator(),
        \\func replace(mut values: str[]) -> bool:
        \\    const head = values[0][0:3]
        \\    values[0] = "replacement"
        \\    return head == "abc"
        \\func main() -> int:
        \\    mut values = ["abc" + str(7)]
        \\    return if replace(mut values) then 0 else 1
    );
    _ = try fusion.run(arena.allocator(), &module);
    try std.testing.expectEqual(@as(usize, 1), count(module, "replace", .str_slice));
    try std.testing.expectEqual(@as(usize, 0), count(module, "replace", .str_slice_view));
}

// spec-case: NEW-CORE-S1-VIEW-4
test "A04 slice lifetime keeps a materialized span before its owner moves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try lowered(arena.allocator(),
        \\func main() -> int:
        \\    mut owner = "abc" + str(7)
        \\    const view = owner.borrow(0, 3)
        \\    const saved = view.copy()
        \\    mut values: str[] = []
        \\    values.append(owner)
        \\    values[0] += "!"
        \\    return if saved == "abc" and len(values) == 1 then 0 else 1
    );
    canonicalCopies(&module);
    const copied = count(module, "main", .str_from_view);
    try std.testing.expect(copied > 0);
    _ = try fusion.run(arena.allocator(), &module);
    try std.testing.expectEqual(copied, count(module, "main", .str_from_view));
}

// spec-case: NEW-CORE-S1-VIEW-4
test "A04 slice lifetime preserves readonly slice fusion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try lowered(arena.allocator(),
        \\func reads(source: str) -> bool:
        \\    const head = source[0:3]
        \\    return head == "abc" and len(head) == 3
        \\func main() -> int:
        \\    return if reads("abc" + str(7)) then 0 else 1
    );
    _ = try fusion.run(arena.allocator(), &module);
    try std.testing.expectEqual(@as(usize, 0), count(module, "reads", .str_slice));
    try std.testing.expectEqual(@as(usize, 1), count(module, "reads", .str_slice_view));
}

fn canonicalCopies(module: *ir.Module) void {
    // Split lowering uses this canonical materialization; exercise the same
    // ownership boundary without depending on whether split fusion fired first.
    for (module.functions.items) |*function| for (function.insts.items) |*inst| {
        if (inst.op != .call) continue;
        const target = module.functions.items[inst.a.index()];
        if (!std.mem.eql(u8, target.name, "myl_core_view_copy_text")) continue;
        inst.* = .{ .op = .str_from_view, .ty = .str, .a = function.operands(inst.data)[0], .span = inst.span };
    };
}

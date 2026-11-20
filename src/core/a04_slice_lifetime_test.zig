//! Slice-copy elimination preserves the owner required by an implicit borrow.
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const build = @import("build.zig");
const fusion = @import("fuse_slice_key.zig");
const single_owner = @import("single_owner.zig");
const support = @import("test_support.zig");

fn lowered(a: std.mem.Allocator, source: []const u8) !ir.Module {
    var unit = try language.Compilation.init(a, "slice.selka", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{
        .program = unit.program.?,
    }, &refusal);
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

/// Calls in `name` whose callee is the function called `callee` (a runtime helper the lowering names).
fn countCalls(module: ir.Module, name: []const u8, callee: []const u8) usize {
    var result: usize = 0;
    for (module.functions.items) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        for (function.insts.items) |inst| {
            if (inst.op != .call or inst.a.index() >= module.functions.items.len) continue;
            if (std.mem.eql(u8, module.functions.items[inst.a.index()].name, callee)) result += 1;
        }
    }
    return result;
}

const moved =
    \\func moved(source: str) -> bool:
    \\    mut owner = source + "!"
    \\    const head = strings.char_slice(owner, 0, 3)
    \\    mut values: str[] = []
    \\    append(mut values, own owner)
    \\    values[0] += "?"
    \\    return head == "abc" and len(values) == 1
    \\func main() -> int:
    \\    if moved("abcdef"):
    \\        return 0
    \\    else:
    \\        return 1
;

/// `moved` with the copy written: the snapshot the move needs is the program's own copy.
const repaired_moved =
    \\func moved(source: str) -> bool:
    \\    mut owner = source + "!"
    \\    const head = copy(strings.char_slice(owner, 0, 3))
    \\    mut values: str[] = []
    \\    append(mut values, own owner)
    \\    values[0] += "?"
    \\    return head == "abc" and len(values) == 1
    \\func main() -> int:
    \\    if moved("abcdef"):
    \\        return 0
    \\    else:
    \\        return 1
;

// spec-case: NEW-CORE-S1-VIEW-4
test "A04 slice lifetime keeps a snapshot when its owner moves into storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The implicit borrow is refused: the owner moves into `values` while the view is still read.
    const implicit = try std.mem.concat(a, u8, &.{ moved, "\n" });
    var failure: single_owner.Failure = .{};
    try std.testing.expectError(error.Rejected, single_owner.check(a, try support.checkedProgram(a, implicit), &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    // The repaired program is accepted: the snapshot is written and the owner is given away with `own`.
    var repaired_failure: single_owner.Failure = .{};
    try single_owner.check(a, try support.checkedProgram(a, repaired_moved), &repaired_failure);
    // The written form is one owned snapshot. Its one view is read only by that snapshot, which is
    // taken before the move, so no view outlives the move.
    var module = try lowered(a, repaired_moved);
    _ = try fusion.run(a, &module);
    // Two owned copies: the snapshot, and the copy that `source + "!"` makes of the view parameter (a str_from_view of param0).
    try std.testing.expectEqual(@as(usize, 2), count(module, "moved", .str_slice) + count(module, "moved", .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), count(module, "moved", .str_slice_view));
}

// spec-case: NEW-CORE-S1-VIEW-1
test "A04 slice lifetime tracks replacement of a borrowed element parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The implicit borrow is refused: the element is replaced while the view is still read.
    const implicit =
        \\func replace(mut values: str[]) -> bool:
        \\    const head = strings.char_slice(values[0], 0, 3)
        \\    values[0] = "replacement"
        \\    return head == "abc"
        \\func main() -> int:
        \\    mut values = ["abc" + str(7)]
        \\    if replace(mut values):
        \\        return 0
        \\    else:
        \\        return 1
    ;
    var failure: single_owner.Failure = .{};
    try std.testing.expectError(error.Rejected, single_owner.check(a, try support.checkedProgram(a, implicit), &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    // The written form takes one owned snapshot before the replacement; its view is read only by it.
    var module = try lowered(a,
        \\func replace(mut values: str[]) -> bool:
        \\    const head = copy(strings.char_slice(values[0], 0, 3))
        \\    values[0] = "replacement"
        \\    return head == "abc"
        \\func main() -> int:
        \\    mut values = ["abc" + str(7)]
        \\    if replace(mut values):
        \\        return 0
        \\    else:
        \\        return 1
    );
    _ = try fusion.run(a, &module);
    try std.testing.expectEqual(@as(usize, 1), count(module, "replace", .str_slice) + count(module, "replace", .str_from_view));
    try std.testing.expectEqual(@as(usize, 1), count(module, "replace", .str_slice_view));
}

// spec-case: NEW-CORE-S1-VIEW-4
test "A04 slice lifetime preserves readonly slice fusion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try lowered(arena.allocator(),
        \\func reads(source: str) -> bool:
        \\    const head = strings.char_slice(source, 0, 3)
        \\    return head == "abc" and strings.char_count(head) == 3
        \\func main() -> int:
        \\    if reads("abc" + str(7)):
        \\        return 0
        \\    else:
        \\        return 1
    );
    _ = try fusion.run(arena.allocator(), &module);
    try std.testing.expectEqual(@as(usize, 0), count(module, "reads", .str_slice));
    try std.testing.expectEqual(@as(usize, 1), countCalls(module, "reads", "myl_core_xc_slice"));
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

/// Require the source-ownership verdict of a program that imports `strings`: `code`, or accepted when `code` is "".
fn expectTrimVerdict(allocator: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = try support.checkedProgram(arena.allocator(), source);
    var failure: single_owner.Failure = .{};
    single_owner.check(arena.allocator(), program, &failure) catch |err| {
        try std.testing.expectEqual(error.Rejected, err);
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    try std.testing.expectEqualStrings(code, "");
}

test "a text trim lends its text as its declared `from text` says, though its call is the operation (W13-S3)" {
    // `strings.strip`, `lstrip` and `rstrip` are `builtin func` homes since W13-S3, so a call is the native trim, not
    // a call of a function declared `-> str from text`; every verdict that declaration gave is kept.
    const head = "import strings\n\nfunc eat(own text: str) -> int:\n    return len(text)\n\n\nfunc main() -> int:\n    mut s = \"  ab \"\n";
    const a = std.testing.allocator;
    try expectTrimVerdict(a, head ++ "    const view = strings.strip(s)\n    return len(view) + len(strings.lstrip(s))\n", "");
    try expectTrimVerdict(a, head ++ "    mut xs: str[] = []\n    append(mut xs, strings.strip(s))\n    return len(xs)\n", "E_SLICE_ESCAPES");
    try expectTrimVerdict(a, head ++ "    mut xs: str[] = []\n    append(mut xs, strings.strip(\" a \"))\n    return len(xs)\n", "E_SLICE_ESCAPES");
    try expectTrimVerdict(a, head ++ "    return eat(strings.strip(s))\n", "E_SINGLE_OWNER_BORROW");
    try expectTrimVerdict(a, head ++ "    const view = strings.rstrip(s)\n    s = \"x\"\n    return len(view)\n", "E_SINGLE_OWNER_OVERLAP");
}

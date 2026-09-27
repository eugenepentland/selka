//! Plain aggregate updates must avoid ownership helpers without weakening copies.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn edit(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    var compilation = try compiler.Compilation.init(a, "plain.my", source);
    defer compilation.deinit();
    const output = try compilation.emitQbeWithOptions(a, .{ .step_checks = false, .frame_checks = true });
    defer a.free(output);
    var manifest = try std.json.parseFromSlice(Manifest, a, output, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| if (std.mem.eql(u8, function.name, "edit")) return a.dupe(u8, function.il);
    return error.TestUnexpectedResult;
}

// spec: RC-PLAIN-AGGREGATE-1
test "RC-PLAIN-AGGREGATE-1 plain record field updates retain bounds without owning helpers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try edit(t.allocator,
        \\record Body:
        \\    x: float
        \\    y: float
        \\def edit(items: mut list[Body], index: int) -> None:
        \\    items[index].x = items[index].y + 1.0
        \\def main() -> int:
        \\    values = [Body(1.0, 2.0)]
        \\    edit(mut values, 0)
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_native_copy") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_list_set") == null);
    try t.expect(std.mem.indexOf(u8, output, "# RC-GLUE-1 list_set") == null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: RC-PLAIN-AGGREGATE-1
test "RC-PLAIN-AGGREGATE-1 managed aggregate fields retain transactional publication" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try edit(t.allocator,
        \\record Owned:
        \\    items: list[int]
        \\def edit(values: mut list[Owned]) -> None:
        \\    values[0].items = [9]
        \\def main() -> int:
        \\    values = [Owned([1])]
        \\    edit(mut values)
        \\    return 0
    );
    defer t.allocator.free(output);
    // The element replacement stages, retains and drops inside its glue.
    try t.expect(std.mem.indexOf(u8, output, "# RC-GLUE-1 list_set") != null);
    try t.expect(std.mem.indexOf(u8, output, "# RC-GLUE-1 retain") != null);
}

// spec-case: RC-PLAIN-AGGREGATE-1
test "RC-PLAIN-AGGREGATE-1 zero sized aggregate elements keep established storage" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try edit(t.allocator,
        \\def edit(values: mut list[[0]int], replacement: [0]int) -> None:
        \\    values[0] = replacement
        \\def main() -> int:
        \\    empty: [0]int = []
        \\    values: list[[0]int] = [empty]
        \\    edit(mut values, empty)
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_rc_list_set") != null);
}

// spec: RC-SCALAR-REPLACE-1
test "RC-SCALAR-REPLACE-1 scalar field stores do not publish a dead pending token" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try edit(t.allocator,
        \\record Body:
        \\    x: float
        \\    enabled: bool
        \\    small: i8
        \\def edit(values: mut list[Body]) -> None:
        \\    values[0].x = 1.25
        \\    values[0].enabled = True
        \\    values[0].small = -7i8
        \\def main() -> int:
        \\    values = [Body(0.0, False, 1i8)]
        \\    edit(mut values)
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, output, " storew 1,"));
    try t.expect(std.mem.indexOf(u8, output, " storeb ") != null);
    try t.expect(std.mem.indexOf(u8, output, "call $myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: RC-SCALAR-REPLACE-1
test "RC-SCALAR-REPLACE-1 aggregate and zero sized field replacements keep pending staging" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    const output = try edit(t.allocator,
        \\record Plain:
        \\    row: [2]int
        \\    empty: None
        \\def edit(values: mut list[Plain], row: [2]int) -> None:
        \\    values[0].row = row
        \\    values[0].empty = None
        \\def main() -> int:
        \\    row: [2]int = [1, 2]
        \\    values = [Plain(row, None)]
        \\    edit(mut values, row)
        \\    return 0
    );
    defer t.allocator.free(output);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, output, " storew 1,"));
    try t.expect(std.mem.indexOf(u8, output, "blit ") != null);
}

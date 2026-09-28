//! A field read out of a dead record local moves its tokens instead of copying.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-DEAD-FIELD-MOVE-1";
const source =
    \\record Box:
    \\    tag: int
    \\    items: list[int]
    \\union Slot:
    \\    empty,
    \\    full: Box
    \\def fresh(n: int) -> Box:
    \\    return Box(n, [0, 0, 0])
    \\def local_move(n: int) -> int:
    \\    box = fresh(n)
    \\    items = box.items
    \\    items[0] = n
    \\    return len(items) + items[0]
    \\def binding_move(n: int) -> int:
    \\    slot = Slot.full(fresh(n))
    \\    match slot:
    \\        case Slot.full(box):
    \\            tag = box.tag
    \\            items = box.items
    \\            items[1] = n
    \\            return items[1] + tag
    \\        case _:
    \\            return 0
    \\def read_after(n: int) -> int:
    \\    box = fresh(n)
    \\    items = box.items
    \\    items[0] = n
    \\    return len(box.items) + items[0]
    \\def parameter_source(box: Box, n: int) -> int:
    \\    items = box.items
    \\    items[0] = n
    \\    return items[0]
    \\def looped(n: int) -> int:
    \\    box = fresh(n)
    \\    total = 0
    \\    i = 0
    \\    while i < 3:
    \\        items = box.items
    \\        items[0] = i
    \\        total += items[0]
    \\        i += 1
    \\    return total
    \\def touch(box: mut Box):
    \\    box.tag += 1
    \\def referenced(n: int) -> int:
    \\    box = fresh(n)
    \\    touch(mut box)
    \\    items = box.items
    \\    items[0] = n
    \\    return items[0]
    \\def main() -> int:
    \\    return local_move(1) + binding_move(2) + read_after(3) + parameter_source(fresh(4), 4) + looped(5) + referenced(6)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_dead_field.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: RC-DEAD-FIELD-MOVE-1
test "RC moves a field out of a dead record local and keeps copies elsewhere" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const expected = [_]struct { []const u8, bool }{
        .{ "local_move", true },        .{ "binding_move", true }, .{ "read_after", false },
        .{ "parameter_source", false }, .{ "looped", false },      .{ "referenced", false },
    };
    for (expected) |case| try t.expectEqual(case[1], contains(try named(manifest.value, case[0]), marker));
}

// spec-case: RC-DEAD-FIELD-MOVE-1
test "RC dead field move tests the source's role and GC lowering is unchanged" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "local_move");
    const moved = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    try t.expect(contains(il[moved..], "@rcdeadmove"));
    try t.expect(contains(il[moved..], "@rcdeadcopy"));
    runtime.set(.gc);
    var collected = try emitted();
    defer collected.deinit();
    try t.expect(!contains(try named(collected.value, "local_move"), marker));
}

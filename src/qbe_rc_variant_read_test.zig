//! Adjacent matches keep the selected payload's ordinary snapshot publication.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-ADJACENT-VARIANT-READ-1";
const source =
    \\record Payload:
    \\    items: list[int]
    \\    other: list[int]
    \\union Item:
    \\    empty,
    \\    value: Payload
    \\record Pool:
    \\    items: list[Item]
    \\def selected(pool: Pool, at: int) -> Payload:
    \\    match pool.items[at]:
    \\        case Item.value(payload):
    \\            return payload
    \\        case _:
    \\            return Payload([], [])
    \\def escaped(pool: Pool, at: int) -> Payload:
    \\    saved = pool.items[at]
    \\    match saved:
    \\        case Item.value(payload):
    \\            return payload
    \\        case _:
    \\            return Payload([], [])
    \\record Held:
    \\    view: DictValues[int, int]
    \\union HeldItem:
    \\    empty,
    \\    value: Held
    \\def held(rows: list[HeldItem]) -> int:
    \\    match rows[0]:
    \\        case HeldItem.value(payload):
    \\            return len(payload.view)
    \\        case _:
    \\            return 0
    \\record CallbackPayload:
    \\    run: def(int) -> int
    \\    items: list[int]
    \\union CallbackItem:
    \\    empty,
    \\    value: CallbackPayload
    \\def callback_payload(rows: list[CallbackItem]) -> int:
    \\    match rows[0]:
    \\        case CallbackItem.value(payload):
    \\            return len(payload.items)
    \\        case _:
    \\            return 0
    \\def change(pool: mut Pool) -> int:
    \\    pool.items.clear()
    \\    return 0
    \\def callback(pool: mut Pool) -> Payload:
    \\    match pool.items[change(mut pool)]:
    \\        case Item.value(payload):
    \\            return payload
    \\        case _:
    \\            return Payload([], [])
    \\def main() -> int:
    \\    return len(selected(Pool([Item.value(Payload([3], [7]))]), -1).items)
;

fn emitted(mode: runtime.Selection, steps: bool) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(mode);
    var compilation = try compiler.Compilation.init(t.allocator, "variant_read.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}
fn body(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-ADJACENT-VARIANT-READ-1
test "RC adjacent variant read has a concrete guard and complete slow fallback" {
    var result = try emitted(.rc, false);
    defer result.deinit();
    const il = try body(result.value, "selected");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, il, marker));
    const at = std.mem.indexOf(u8, il, marker).?;
    const fallback = std.mem.indexOf(u8, il[at..], "# RC-GLUE-1 loan") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[at..][0..fallback], " =w loaduw ") != null);
    try t.expect(std.mem.indexOf(u8, il[at..][0..fallback], ", 16\n") != null);
    try t.expect(std.mem.indexOf(u8, il[at..][0..fallback], "@rcvariantslow") != null);
    try t.expect(std.mem.indexOf(u8, il[at..], "# RC-GLUE-1 retain") != null);
    try t.expect(std.mem.indexOf(u8, il[0..at], "call $myl_qbe_fail_normalized_index_bounds") != null);
}

// spec-case: RC-ADJACENT-VARIANT-READ-1
test "RC adjacent variant read refuses escaped variants held fields and scoped callbacks" {
    var result = try emitted(.rc, false);
    defer result.deinit();
    for ([_][]const u8{ "escaped", "held", "callback", "callback_payload" }) |name|
        try t.expect(std.mem.indexOf(u8, try body(result.value, name), marker) == null);
}

// spec-case: RC-ADJACENT-VARIANT-READ-1
test "RC adjacent variant read preserves the separate switch step boundary" {
    var result = try emitted(.rc, true);
    defer result.deinit();
    const il = try body(result.value, "selected");
    const at = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    const retain = std.mem.indexOf(u8, il[at..], "# RC-GLUE-1 retain") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[at..][0..retain], ", @step_limit,") != null);
    var gc = try emitted(.gc, true);
    defer gc.deinit();
    try t.expect(std.mem.indexOf(u8, try body(gc.value, "selected"), marker) == null);
}

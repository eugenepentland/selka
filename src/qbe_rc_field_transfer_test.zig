//! Physical field movement requires a complete closed source interval.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-CLOSED-FIELD-TRANSFER-1";
const source =
    \\record Holder:
    \\    items: list[int]
    \\    scalar: int
    \\def push(items: mut list[int], value: int):
    \\    items.append(value)
    \\def closed(holder: mut Holder, value: int):
    \\    items = holder.items
    \\    push(mut items, value)
    \\    holder.items = items
    \\def observed(holder: mut Holder, value: int):
    \\    items = holder.items
    \\    push(mut items, value)
    \\    assert len(holder.items) == 1
    \\    holder.items = items
    \\def surviving(holder: mut Holder, value: int):
    \\    items = holder.items
    \\    push(mut items, value)
    \\    holder.items = items
    \\    push(mut items, 9)
    \\def two_roots(holder: mut Holder, other: mut Holder):
    \\    items = holder.items
    \\    push(mut items, 3)
    \\    assert len(other.items) == 1
    \\    holder.items = items
    \\    other.scalar += 1
    \\def early(holder: mut Holder, stop: bool):
    \\    items = holder.items
    \\    push(mut items, 3)
    \\    if stop:
    \\        return
    \\    holder.items = items
    \\def borrowed(holder: Holder) -> Holder:
    \\    items = holder.items
    \\    push(mut items, 3)
    \\    holder.items = items
    \\    return holder
    \\def arena_change(holder: mut Holder):
    \\    items = holder.items
    \\    with arena():
    \\        push(mut items, 3)
    \\    holder.items = items
    \\record ObservedHolder:
    \\    items: list[int]
    \\    view: DictValues[int, int]
    \\def held_root(holder: mut ObservedHolder):
    \\    items = holder.items
    \\    push(mut items, 3)
    \\    holder.items = items
    \\def initialized(holder: mut Holder):
    \\    items = [8, 9]
    \\    items = holder.items
    \\    push(mut items, 3)
    \\    holder.items = items
    \\record AuthorityHolder:
    \\    items: list[def(int) -> int effects()]
    \\def wipe(items: mut list[def(int) -> int effects()]):
    \\    items.clear()
    \\def authority(holder: mut AuthorityHolder):
    \\    items = holder.items
    \\    wipe(mut items)
    \\    holder.items = items
    \\def indirect(holder: mut Holder):
    \\    items = holder.items
    \\    action = push
    \\    action(mut items, 3)
    \\    holder.items = items
    \\def main() -> int:
    \\    holder = Holder([1], 7)
    \\    closed(mut holder, 2)
    \\    return len(holder.items)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_field.my", source);
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

// spec: RC-CLOSED-FIELD-TRANSFER-1
test "RC closed field owner moves only with complete physical source and commit proof" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "closed");
    const moved = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    try t.expect(!contains(il[0..moved], "call $myl_rc_native_loan"));
    try t.expect(!contains(il[0..moved], "call $myl_rc_native_retain"));
    try t.expect(contains(il, "myl_qbe_rc_unique_local"));
    try t.expect(contains(il, "myl_qbe_rc_frame_enter"));
    try t.expect(!contains(try named(manifest.value, "observed"), marker));
    try t.expect(!contains(try named(manifest.value, "surviving"), marker));
    try t.expect(!contains(try named(manifest.value, "two_roots"), marker));
    try t.expect(!contains(try named(manifest.value, "early"), marker));
    try t.expect(!contains(try named(manifest.value, "borrowed"), marker));
    try t.expect(!contains(try named(manifest.value, "arena_change"), marker));
    try t.expect(!contains(try named(manifest.value, "held_root"), marker));
    try t.expect(contains(try named(manifest.value, "initialized"), marker));
    try t.expect(!contains(try named(manifest.value, "authority"), marker));
    try t.expect(!contains(try named(manifest.value, "indirect"), marker));
}

// spec-case: RC-CLOSED-FIELD-TRANSFER-1
test "GC closed field shares keep their existing physical lowering" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(!contains(try named(manifest.value, "closed"), marker));
    try t.expect(!contains(try named(manifest.value, "closed"), "myl_qbe_rc_frame_enter"));
}

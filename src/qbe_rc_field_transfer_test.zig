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
    try t.expect(!contains(il[0..moved], "# RC-GLUE-1 loan"));
    try t.expect(!contains(il[0..moved], "# RC-GLUE-1 retain"));
    try t.expect(contains(il, "myl_qbe_rc_unique_local"));
    try t.expect(contains(il, "# rc-frame"));
    try t.expect(!contains(try named(manifest.value, "observed"), marker));
    try t.expect(!contains(try named(manifest.value, "surviving"), marker));
    try t.expect(!contains(try named(manifest.value, "two_roots"), marker));
    try t.expect(!contains(try named(manifest.value, "early"), marker));
    try t.expect(!contains(try named(manifest.value, "borrowed"), marker));
    try t.expect(!contains(try named(manifest.value, "arena_change"), marker));
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
    try t.expect(!contains(try named(manifest.value, "closed"), "# rc-frame"));
}

const writeback_source =
    \\record Rt:
    \\    objects: list[int]
    \\    count: int
    \\record Outer:
    \\    rt: Rt
    \\    tag: str
    \\record Note:
    \\    words: list[str]
    \\def push(rt: mut Rt, value: int):
    \\    rt.objects.append(value)
    \\def peek(rt: Rt) -> int:
    \\    return len(rt.objects)
    \\def inspect(holder: Outer) -> int:
    \\    return len(holder.rt.objects)
    \\def owned_local(n: int) -> int:
    \\    it = Outer(Rt([], 0), "t")
    \\    i = 0
    \\    while i < n:
    \\        wb = it.rt
    \\        push(mut wb, i)
    \\        it.rt = wb
    \\        i += 1
    \\    return len(it.rt.objects)
    \\def caller_record(holder: mut Outer, note: Note, value: int):
    \\    wb = holder.rt
    \\    push(mut wb, value + len(note.words) + peek(wb))
    \\    holder.rt = wb
    \\def branched(holder: mut Outer, flag: bool):
    \\    wb = holder.rt
    \\    if flag:
    \\        push(mut wb, 1)
    \\    else:
    \\        push(mut wb, 2)
    \\    holder.rt = wb
    \\def looped(holder: mut Outer, n: int):
    \\    wb = holder.rt
    \\    i = 0
    \\    while i < n:
    \\        push(mut wb, i)
    \\        i += 1
    \\    holder.rt = wb
    \\def sibling_read(holder: mut Outer):
    \\    wb = holder.rt
    \\    push(mut wb, len(holder.tag))
    \\    holder.rt = wb
    \\def field_read(holder: mut Outer):
    \\    wb = holder.rt
    \\    push(mut wb, len(holder.rt.objects))
    \\    holder.rt = wb
    \\def whole_passed(holder: mut Outer):
    \\    wb = holder.rt
    \\    push(mut wb, inspect(holder))
    \\    holder.rt = wb
    \\def partial(holder: mut Outer, flag: bool):
    \\    wb = holder.rt
    \\    push(mut wb, 1)
    \\    if flag:
    \\        holder.rt = wb
    \\def breaking(holder: mut Outer, n: int):
    \\    i = 0
    \\    while i < n:
    \\        wb = holder.rt
    \\        push(mut wb, i)
    \\        if i == 3:
    \\            break
    \\        holder.rt = wb
    \\        i += 1
    \\def looped_back(holder: mut Outer, n: int):
    \\    wb = holder.rt
    \\    i = 0
    \\    while i < n:
    \\        push(mut wb, i)
    \\        holder.rt = wb
    \\        i += 1
    \\def iterated(holder: mut Outer):
    \\    for x in holder.rt.objects:
    \\        wb = holder.rt
    \\        push(mut wb, x)
    \\        holder.rt = wb
    \\def main() -> int:
    \\    holder = Outer(Rt([1], 0), "t")
    \\    caller_record(mut holder, Note(["a"]), 2)
    \\    return owned_local(3) + len(holder.rt.objects)
;

fn emittedWriteback() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_writeback.my", writeback_source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

// spec: RC-CLOSED-FIELD-TRANSFER-2
test "RC closed field transfer moves record fields of owned locals across closed regions" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emittedWriteback();
    defer manifest.deinit();
    const owned = try named(manifest.value, "owned_local");
    const moved = std.mem.indexOf(u8, owned, marker) orelse return error.TestUnexpectedResult;
    const projection = std.mem.lastIndexOf(u8, owned[0..moved], "@step") orelse return error.TestUnexpectedResult;
    try t.expect(!contains(owned[projection..moved], "call $myl_rc_native_loan"));
    try t.expect(!contains(owned[projection..moved], "call $myl_rc_native_retain"));
    // The moved-from field is cleared (RC-INLINE-ZERO-1: inline stores).
    try t.expect(contains(owned[moved..], " storel 0, %v") or contains(owned[moved..], "call $memset"));
    const restored = std.mem.indexOf(u8, owned, "# RC-CLOSED-FIELD-TRANSFER-2 store-back") orelse return error.TestUnexpectedResult;
    try t.expect(!contains(owned[moved..restored], "call $myl_rc_native_take"));
    try t.expect(!contains(owned[moved..restored], "call $myl_rc_native_retain"));
    const expected = [_]struct { []const u8, bool }{
        .{ "caller_record", true }, .{ "branched", true },      .{ "looped", true },   .{ "sibling_read", true },
        .{ "field_read", false },   .{ "whole_passed", false }, .{ "partial", false }, .{ "breaking", false },
        // D1-LIVE-PLACE: the back edge re-reads the restored field after
        // the closed interval, allowing the existing store-back transfer.
        .{ "iterated", true },      .{ "looped_back", false },
    };
    for (expected) |case| try t.expectEqual(case[1], contains(try named(manifest.value, case[0]), marker));
}

// spec-case: RC-CLOSED-FIELD-TRANSFER-2
test "GC lowering of generalized closed field transfers is unchanged" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var manifest = try emittedWriteback();
    defer manifest.deinit();
    for (manifest.value.functions) |function| try t.expect(!contains(function.il, marker));
}

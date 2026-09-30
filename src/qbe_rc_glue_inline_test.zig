//! Inline publication of list pointers and flat record drops (RC-GLUE-1 fast paths).
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\record Frame:
    \\    constants: list[int]
    \\    code: list[int]
    \\    names: list[str]
    \\    ip: int
    \\record Wide:
    \\    a: list[int]
    \\    b: list[int]
    \\    c: list[int]
    \\    d: list[int]
    \\    e: list[int]
    \\record Bulky:
    \\    a: list[int]
    \\    b: list[int]
    \\    p1: int
    \\    p2: int
    \\    p3: int
    \\    p4: int
    \\    p5: int
    \\    p6: int
    \\    p7: int
    \\union Choice:
    \\    none,
    \\    some: list[int]
    \\record Holder:
    \\    frame: Frame
    \\    items: list[int]
    \\def load(holder: Holder) -> Frame:
    \\    return Frame(holder.frame.constants, holder.items, holder.frame.names, 1)
    \\def swap(frame: Frame, holder: Holder) -> int:
    \\    current = frame
    \\    current = load(holder)
    \\    return len(current.code)
    \\def wide(value: Wide) -> int:
    \\    local = value
    \\    local = Wide([1], [2], [3], [4], [5])
    \\    return len(local.e)
    \\def bulky(value: Bulky) -> int:
    \\    local = value
    \\    local = Bulky([1], [2], 0, 0, 0, 0, 0, 0, 0)
    \\    return len(local.b)
    \\def choice(value: Choice) -> int:
    \\    local = value
    \\    local = Choice.none
    \\    match local:
    \\        case Choice.some(items):
    \\            return len(items)
    \\        case _:
    \\            return 0
    \\def main() -> int:
    \\    holder = Holder(Frame([1], [2], ["a"], 0), [3])
    \\    return swap(load(holder), holder) + wide(Wide([1], [2], [3], [4], [5])) + choice(Choice.some([1])) + bulky(Bulky([1], [2], 0, 0, 0, 0, 0, 0, 0))
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_glue_inline.my", source);
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

// spec: RC-PUBLISH-FAST-1
test "RC list publications run inline with the glue as their slow path" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "load");
    try t.expect(contains(il, "@rcgpublishmode"));
    try t.expect(contains(il, "_rcg_publish("));
    runtime.set(.rc_counting);
    var counted = try emitted();
    defer counted.deinit();
    try t.expect(!contains(try named(counted.value, "load"), "@rcgpublishmode"));
}

// spec: RC-FLAT-DROP-1
test "RC flat records of a few list leaves drop inline and other shapes call their glue" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(contains(try named(manifest.value, "swap"), "# RC-FLAT-DROP-1"));
    try t.expect(!contains(try named(manifest.value, "wide"), "# RC-FLAT-DROP-1"));
    try t.expect(!contains(try named(manifest.value, "choice"), "# RC-FLAT-DROP-1"));
    try t.expect(!contains(try named(manifest.value, "bulky"), "# RC-FLAT-DROP-1"));
    runtime.set(.rc_counting);
    var counted = try emitted();
    defer counted.deinit();
    try t.expect(!contains(try named(counted.value, "swap"), "# RC-FLAT-DROP-1"));
}

// spec-case: RC-FLAT-DROP-1
test "RC flat drops inline only a local's replaced value" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    // The stores into `current` replace a frame inline; the return's exit
    // drops of the same type keep their glue calls.
    const il = try named(manifest.value, "swap");
    const exit = std.mem.indexOf(u8, il, "# rc-exit") orelse return error.TestUnexpectedResult;
    try t.expect(contains(il[0..exit], "# RC-FLAT-DROP-1"));
    try t.expect(!contains(il[exit..], "# RC-FLAT-DROP-1"));
    try t.expect(contains(il[exit..], "_rcg_drop("));
}

// spec: RC-PUBLISH-ACQUIRE-1
test "RC-PUBLISH-ACQUIRE-1 ordinary publication admits and acquires before history or destination stores" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "load");
    const capacity = std.mem.indexOf(u8, il, "\n@rcgpublishcapacity") orelse return error.TestUnexpectedResult;
    const acquire = capacity + (std.mem.indexOf(u8, il[capacity..], "\n@rcgpublishacquire") orelse return error.TestUnexpectedResult);
    const store = acquire + (std.mem.indexOf(u8, il[acquire..], " storel ") orelse return error.TestUnexpectedResult);
    const mark = store + (std.mem.indexOf(u8, il[store..], "\n@rcgpublishmarkcheck") orelse return error.TestUnexpectedResult);
    const publish_at = mark + (std.mem.indexOf(u8, il[mark..], "\n@rcgpublishstore") orelse return error.TestUnexpectedResult);
    const slow = publish_at + (std.mem.indexOf(u8, il[publish_at..], "\n@rcgpublishslow") orelse return error.TestUnexpectedResult);
    try t.expect(capacity < acquire and acquire < store and store < mark and mark < publish_at and publish_at < slow);
    try t.expect(!contains(il[capacity..store], " storel "));
    try t.expect(!contains(il[store..slow], " call $"));
    try t.expect(!contains(il[publish_at..slow], " =l loadl "));
}

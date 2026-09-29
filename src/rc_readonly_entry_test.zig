//! Public borrowed ABI and physical readonly entry admission remain separate.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const calls = @import("rc_readonly_calls.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const source =
    \\record Item:
    \\    text: bytes
    \\    number: int
    \\def pick(items: list[Item], index: int) -> Item:
    \\    return items[index]
    \\def selected(items: list[Item]) -> int:
    \\    saved = pick(items, 0)
    \\    current = pick(items, 1)
    \\    return saved.number + current.number
    \\def main() -> int:
    \\    return selected([Item(b"left", 3), Item(b"right", 7)])
;
const Change = enum { none, parameter, shape, dependency };
const Witness = struct { public: bool, ordinary: bool, raw: bool };
fn witness(text: []const u8, change: Change) !Witness {
    var compilation = try compiler.Compilation.init(t.allocator, "readonly_entry.my", text);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(t.allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(t.allocator, &layouts);
    defer catalog.deinit();
    for (program.functions) |function| if (std.mem.eql(u8, function.name, "pick")) {
        const certificate = try @import("rc_calls.zig").borrowedIn(t.allocator, &catalog, program.functions, function, "rc-v4");
        var result: Witness = .{ .public = certificate != null, .ordinary = (try calls.identity(&catalog, program.functions, function, "rc-v4")) != null, .raw = false };
        var supplied = certificate orelse return result;
        switch (change) {
            .none => {},
            .parameter => supplied.parameter += 1,
            .shape => supplied.shape_identity[0] ^= 1,
            .dependency => supplied.dependency_identity[0] ^= 1,
        }
        if (try calls.borrowedEntry(&catalog, program.functions, function, "rc-v4", supplied)) |raw| {
            defer t.allocator.free(raw.calls);
            result.raw = true;
            try t.expect(raw.entry != null);
        }
        return result;
    };
    return error.TestUnexpectedResult;
}

// spec: RC-BORROWED-READONLY-ENTRY-1
test "RC raw borrowed entry requires matching public certificate and root boundary" {
    const valid = try witness(source, .none);
    try t.expect(valid.public and valid.raw and !valid.ordinary);
    try t.expect(!(try witness(source, .parameter)).raw);
    try t.expect(!(try witness(source, .shape)).raw);
    try t.expect(!(try witness(source, .dependency)).raw);
}

// spec-case: RC-BORROWED-READONLY-ENTRY-1
test "RC raw borrowed entry refuses fresh results recursion and return tracing" {
    try t.expect(!(try witness(
        \\def pick(items: list[int]) -> list[int]:
        \\    return [items[0]]
        \\def main() -> int:
        \\    return 0
    , .none)).raw);
    try t.expect(!(try witness(
        \\def pick(items: list[int], n: int) -> list[int]:
        \\    if n > 0:
        \\        return pick(items, n - 1)
        \\    return items
        \\def main() -> int:
        \\    return 0
    , .none)).raw);
    const traced = try witness(
        \\def pick(value: Result[bytes, bytes]) -> Result[bytes, bytes]:
        \\    return value
        \\def main() -> int:
        \\    return 0
    , .none);
    try t.expect(traced.public and !traced.raw);
}

const Manifest = struct { functions: []const struct { name: []const u8, symbol: []const u8, il: []const u8 } };
fn emission(text: []const u8) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "readonly_entry.my", text);
    defer compilation.deinit();
    const encoded = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(encoded);
    return std.json.parseFromSlice(Manifest, t.allocator, encoded, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8, borrowed: bool) ![]const u8 {
    for (manifest.functions) |function| {
        if (!std.mem.eql(u8, function.name, name)) continue;
        if (std.mem.endsWith(u8, function.symbol, "_rc_borrow") == borrowed) return function.il;
    }
    return error.TestUnexpectedResult;
}

// spec-case: RC-BORROWED-READONLY-ENTRY-1
test "RC raw borrowed entry removes only alternate journal and retains checked ABI" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try emission(source);
    defer output.deinit();
    const owned = try named(output.value, "pick", false);
    const borrowed = try named(output.value, "pick", true);
    const caller = try named(output.value, "selected", false);
    try t.expect(std.mem.indexOf(u8, owned, "# rc-frame") != null);
    try t.expect(std.mem.indexOf(u8, borrowed, "# rc-frame") == null);
    try t.expect(std.mem.indexOf(u8, borrowed, "%rcg0") == null);
    try t.expect(std.mem.indexOf(u8, borrowed, "myl_qbe_fail_normalized_index_bounds") != null);
    try t.expect(std.mem.indexOf(u8, borrowed, "myl_qbe_fail_frame") != null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, caller, "_rc_borrow(l %ctx"));
}

const large_source =
    \\record Item:
    \\    text: bytes
    \\    number: int
    \\record Big:
    \\    text: bytes
    \\    padding: [600]int
    \\    number: int
    \\record Huge:
    \\    text: bytes
    \\    padding: [6000]int
    \\    number: int
    \\def pick(items: list[Big], index: int) -> Big:
    \\    return items[index]
    \\record Holder:
    \\    huge: Huge
    \\def small_heap(items: list[Holder], index: int) -> Item:
    \\    current = items[index].huge
    \\    return Item(current.text, current.number)
    \\def selected(items: list[Big]) -> int:
    \\    saved = pick(items, 0)
    \\    current = pick(items, 1)
    \\    return saved.number + current.number + saved.padding[599]
    \\def main() -> int:
    \\    return 0
;

// `small_heap` copies a field of an element, which keeps the frame copy that
// makes the frame heap-backed (an element read straight into a local would
// lend its address instead, RC-ELEMENT-BORROW-3).
// spec-case: RC-BORROWED-READONLY-ENTRY-1
test "RC raw borrowed entry copies hidden and small heap-frame results before release" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try emission(large_source);
    defer output.deinit();
    const large = try named(output.value, "pick", true);
    const small = try named(output.value, "small_heap", true);
    const caller = try named(output.value, "selected", false);
    try t.expect(std.mem.indexOf(u8, large, "# rc-frame") == null);
    try t.expect(std.mem.indexOf(u8, large, ", %out, 4816\n") != null);
    try t.expect(std.mem.indexOf(u8, small, "# rc-frame") == null);
    const copied = std.mem.indexOf(u8, small, ", %return_storage, 16\n") orelse return error.TestUnexpectedResult;
    const released = std.mem.indexOf(u8, small, "call $myl_qbe_frame_release") orelse return error.TestUnexpectedResult;
    try t.expect(copied < released);
    try t.expect(std.mem.indexOf(u8, small, "myl_qbe_fail_frame") != null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, caller, "_rc_borrow(l %ctx, l %aux"));
    try t.expect(std.mem.count(u8, caller, ", 4816\n") >= 2);
}

//! Scalar helper composition binds proof and caller-cache identities together.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const calls = @import("rc_readonly_calls.zig");
const cache = @import("qbe_rc_cache.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Witness = struct { admitted: bool, key: [32]u8 };
const prefix =
    \\record Item:
    \\    text: bytes
    \\    number: int
;
const suffix =
    \\def selected(items: list[Item]) -> int:
    \\    total = 0
    \\    i = 0
    \\    while i < len(items):
    \\        item = items[i]
    \\        total += middle(items, i) + item.number
    \\        i += 1
    \\    return total
    \\def middle(items: list[Item], i: int) -> int:
    \\    return leaf(items, i)
    \\def main() -> int:
    \\    return selected([Item(b"a", 3), Item(b"b", 7)])
;

fn witness(allocator: std.mem.Allocator, leaf: []const u8) !Witness {
    const source = try std.mem.concat(allocator, u8, &.{ prefix, "\n", leaf, "\n", suffix });
    defer allocator.free(source);
    return witnessSource(allocator, source);
}

fn witnessSource(allocator: std.mem.Allocator, source: []const u8) !Witness {
    var compilation = try compiler.Compilation.init(allocator, "readonly_calls.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const program = compilation.code.?;
    var layouts = try native.Catalog.initRecords(allocator, program.records);
    defer layouts.deinit();
    var catalog = try shapes.Catalog.init(allocator, &layouts);
    defer catalog.deinit();
    for (program.functions, 0..) |function, index| if (std.mem.eql(u8, function.name, "selected")) {
        return .{
            .admitted = (try calls.identity(&catalog, program.functions, function, "rc-v3")) != null,
            .key = try cache.key(allocator, program, &layouts, index, @splat(1)),
        };
    };
    return error.TestUnexpectedResult;
}

fn dependencySource(allocator: std.mem.Allocator, count: usize, chain: bool) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    errdefer source.deinit(allocator);
    try source.appendSlice(allocator, prefix);
    try source.appendSlice(allocator, "\ndef selected(items: list[Item]) -> int:\n    total = 0\n");
    for (0..if (chain) 1 else count) |index| {
        const line = try std.fmt.allocPrint(allocator, "    total += helper{d}(items, 0)\n", .{index});
        defer allocator.free(line);
        try source.appendSlice(allocator, line);
    }
    try source.appendSlice(allocator, "    return total\n");
    for (0..count) |index| {
        const header = try std.fmt.allocPrint(allocator, "def helper{d}(items: list[Item], i: int) -> int:\n", .{index});
        defer allocator.free(header);
        try source.appendSlice(allocator, header);
        const result = if (chain and index + 1 < count)
            try std.fmt.allocPrint(allocator, "    return helper{d}(items, i)\n", .{index + 1})
        else
            try allocator.dupe(u8, "    return items[i].number\n");
        defer allocator.free(result);
        try source.appendSlice(allocator, result);
    }
    try source.appendSlice(allocator, "def main() -> int:\n    return selected([Item(b\"a\", 3)])\n");
    return source.toOwnedSlice(allocator);
}

fn dependencyWitness(count: usize, chain: bool) !Witness {
    const source = try dependencySource(t.allocator, count, chain);
    defer t.allocator.free(source);
    return witnessSource(t.allocator, source);
}

const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn emitted() !std.json.Parsed(Manifest) {
    const source = try dependencySource(t.allocator, 2, true);
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, "readonly_calls.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn rawReader(il: []const u8) bool {
    return std.mem.indexOf(u8, il, "call $myl_qbe_rc_frame_enter") == null and
        std.mem.indexOf(u8, il, "call $myl_rc_native_loan") == null and
        std.mem.indexOf(u8, il, "call $myl_rc_native_retain") == null and
        std.mem.indexOf(u8, il, "call $myl_qbe_fail_frame") != null;
}

// spec: RC-READONLY-CALLS-1
test "RC readonly calls compose scalar helpers and hash transitive body changes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const before = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number
    );
    const after = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number + 1
    );
    try t.expect(before.admitted);
    try t.expect(after.admitted);
    try t.expect(!std.mem.eql(u8, &before.key, &after.key));
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse transitive allocation and managed return helpers" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const allocated = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    other = [items[i].number]
        \\    return len(other)
    );
    const managed = try witness(t.allocator,
        \\def returned(items: list[Item], i: int) -> Item:
        \\    return items[i]
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return returned(items, i).number
    );
    try t.expect(!allocated.admitted);
    try t.expect(!managed.admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly proof keys preserve GC identities" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    const result = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return items[i].number
    );
    const expected: [32]u8 = @splat(1);
    try t.expectEqual(expected, result.key);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse mutual recursion" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const result = try witness(t.allocator,
        \\def leaf(items: list[Item], i: int) -> int:
        \\    return middle(items, i)
    );
    try t.expect(!result.admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls refuse exhausted dependency depth and completion storage" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    try t.expect((try dependencyWitness(15, true)).admitted);
    try t.expect(!(try dependencyWitness(16, true)).admitted);
    try t.expect((try dependencyWitness(15, false)).admitted);
    try t.expect(!(try dependencyWitness(16, false)).admitted);
}

// spec-case: RC-READONLY-CALLS-1
test "RC readonly calls emit raw caller and transitive helpers with checked bounds" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    try t.expect(rawReader(try named(manifest.value, "selected")));
    try t.expect(rawReader(try named(manifest.value, "helper0")));
    try t.expect(rawReader(try named(manifest.value, "helper1")));
    try t.expect(std.mem.indexOf(u8, try named(manifest.value, "helper1"), "call $myl_qbe_fail_normalized_index_bounds") != null);
}

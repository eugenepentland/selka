//! Active plain tags preserve complete value storage and all helper refusals.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const proof = @import("qbe_rc_native_variant.zig");
const execute = @import("native_execute.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const schemas =
    \\union Choice:
    \\    empty,
    \\    number: int,
    \\    items: list[int]
    \\union Managed:
    \\    items: list[int],
    \\    message: bytes
    \\union Large:
    \\    empty,
    \\    items: list[int],
    \\    wide: [8]int
    \\union Many:
    \\    a,
    \\    b,
    \\    c,
    \\    d,
    \\    e,
    \\    items: list[int]
    \\union Crowded:
    \\    empty,
    \\    a: list[int],
    \\    b: list[int],
    \\    c: list[int],
    \\    d: list[int],
    \\    e: list[int],
    \\    f: list[int],
    \\    g: list[int],
    \\    h: list[int]
    \\union Unique:
    \\    empty,
    \\    items: list[int],
    \\    file: File
    \\record Wrapped:
    \\    choice: Choice
    \\def forward(value: Choice) -> Choice:
    \\    return value
    \\def made(value: int) -> Choice:
    \\    return Choice.number(value)
    \\def roundtrip(value: int) -> Choice:
    \\    current = made(value)
    \\    saved = current
    \\    current = Choice.items([value + 1])
    \\    return forward(saved)
    \\def main() -> int:
    \\    match roundtrip(17):
    \\        case Choice.number(value):
    \\            return value
    \\        case _:
    \\            return 0
;

fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "native_variant.my", schemas);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = .qbe_v2 });
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

fn record(catalog: *native.Catalog, name: []const u8) !@import("typed.zig").Type {
    for (catalog.records) |item| if (std.mem.eql(u8, item.name, name)) return item.id;
    return error.TestUnexpectedResult;
}

fn uncertified() ![]const u8 {
    var compilation = try compiler.Compilation.init(t.allocator, "native_variant.my", schemas);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = .qbe_v2 });
    defer t.allocator.free(text);
    var catalog = try native.Catalog.initRecords(t.allocator, compilation.program.?.records);
    defer catalog.deinit();
    return @import("qbe_rc_native_variant_runtime_test.zig").wrappers(&catalog);
}

// spec: RC-NATIVE-VARIANT-1
test "RC-NATIVE-VARIANT-1 proves declared edge-free tags and refuses unsupported layouts" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "native_variant.my", schemas);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = .qbe_v2 });
    defer t.allocator.free(text);
    var catalog = try native.Catalog.initRecords(t.allocator, compilation.program.?.records);
    defer catalog.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &catalog);
    defer facts.deinit();
    const selected = (try proof.plan(&catalog, &facts, try record(&catalog, "Choice"))).?;
    try t.expectEqualSlices(u32, &.{ 0, 1 }, selected.tags[0..selected.len]);
    try t.expectEqual(@as(u64, 16), selected.size);
    for ([_][]const u8{ "Managed", "Large", "Many", "Crowded", "Unique", "Wrapped" }) |name|
        try t.expect(try proof.plan(&catalog, &facts, try record(&catalog, name)) == null);
    try t.expect(try proof.plan(&catalog, &facts, .i64) == null);
}

// spec-case: RC-NATIVE-VARIANT-1
test "RC-NATIVE-VARIANT-1 tagged moves guard overlap before stores and retain helper status mapping" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const text = try uncertified();
    defer t.allocator.free(text);
    const begin = std.mem.indexOf(u8, text, "# RC-NATIVE-VARIANT-1 take") orelse return error.TestUnexpectedResult;
    const fast = begin + (std.mem.indexOf(u8, text[begin..], "\n@rcnativecopy") orelse return error.TestUnexpectedResult);
    const slow = fast + (std.mem.indexOf(u8, text[fast..], "\n@rcnativeslow") orelse return error.TestUnexpectedResult);
    const done = slow + (std.mem.indexOf(u8, text[slow..], "\n@rcnativedone") orelse return error.TestUnexpectedResult);
    try t.expect(contains(text[begin..fast], "=w loaduw") and contains(text[begin..fast], "=w cultl"));
    try t.expect(contains(text[begin..fast], ", 112\n") and contains(text[begin..fast], "=w culew"));
    try t.expect(!contains(text[begin..fast], " blit ") and !contains(text[begin..fast], " store"));
    try t.expect(contains(text[fast..slow], " blit ") and contains(text[fast..slow], " storel 0"));
    try t.expect(!contains(text[fast..slow], "call $"));
    try t.expect(contains(text[slow..done], "_rcg_take("));
    try t.expect(contains(text[slow..done], "call $myl_rc_take_failure") and contains(text[slow..done], "jmp @failure"));
    try t.expect(contains(text, "# RC-NATIVE-VARIANT-1 release"));
}

// spec-case: RC-NATIVE-VARIANT-1
// spec-case: RC-DISJOINT-TAKE-1
test "RC-NATIVE-VARIANT-1 completed constructors and real snapshot copies reuse disjoint proof" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const owned = try named(manifest.value, "made");
    const copied = try named(manifest.value, "forward");
    try t.expect(contains(owned, "# RC-DISJOINT-TAKE-1 native variant"));
    try t.expect(!contains(owned, "=w cultl"));
    try t.expect(contains(owned, "=w culew"));
    try t.expect(contains(copied, "# RC-DISJOINT-TAKE-1 native variant"));
    try t.expect(!contains(copied, "=w cultl"));
    try t.expect(contains(copied, "=w culew"));
}

// spec-case: RC-NATIVE-VARIANT-1
test "RC-NATIVE-VARIANT-1 accounting and tracing keep their existing lowering" {
    const saved = runtime.get();
    defer runtime.set(saved);
    for ([_]runtime.Selection{ .rc_counting, .rc_sites, .gc }) |mode| {
        runtime.set(mode);
        var manifest = try emitted();
        defer manifest.deinit();
        const text = try named(manifest.value, "roundtrip");
        try t.expect(!contains(text, "# RC-NATIVE-VARIANT-1"));
    }
}

const snapshots =
    \\record Fault:
    \\    message: bytes
    \\union Choice:
    \\    empty,
    \\    number: int,
    \\    items: list[int]
    \\def forwarded(value: Choice) -> Choice:
    \\    return value
    \\def result(flag: bool) -> Result[int, Fault]:
    \\    if flag:
    \\        return Ok(17)
    \\    return Err(Fault(bytes([65, 66])))
    \\def retained(items: list[Choice]) -> Choice:
    \\    return items[0]
    \\def main() -> int:
    \\    items = [Choice.items([4]), Choice.empty]
    \\    prior = retained(items)
    \\    copied = forwarded(prior)
    \\    items[0] = Choice.number(99)
    \\    total = 0
    \\    match copied:
    \\        case Choice.items(values):
    \\            changed = values
    \\            changed.append(5)
    \\            total += changed[0] + changed[1]
    \\        case _:
    \\            return -1
    \\    match prior:
    \\        case Choice.items(values):
    \\            total += len(values)
    \\        case _:
    \\            return -2
    \\    match result(True):
    \\        case Ok(value):
    \\            total += value
    \\        case _:
    \\            return -3
    \\    match result(False):
    \\        case Err(fault):
    \\            total += len(fault.message)
    \\        case _:
    \\            return -4
    \\    return total
;

fn exercise(mode: runtime.Selection, stress: bool) !void {
    runtime.set(mode);
    var compilation = try compiler.Compilation.init(t.allocator, "native_variant_snapshots.my", snapshots);
    defer compilation.deinit();
    const outcome = try execute.runUnaccounted(&compilation, .{ .gc_stress = stress });
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 29), outcome.value);
}

// The native test runner currently treats RC count reports as diagnostics.
// Inspect this successful process's complete result and parse its count line.
fn exerciseCounting() !void {
    runtime.set(.rc_counting);
    var compilation = try compiler.Compilation.init(t.allocator, "native_variant_counted.my", snapshots);
    defer compilation.deinit();
    const outcome = try execute.runUnaccounted(&compilation, .{});
    try t.expectEqual(@as(u8, 29), outcome.status);
    try t.expectEqualStrings("29\n", outcome.stdout);
    const prefix = "MYLANG_RC_COUNTS ";
    try t.expect(std.mem.startsWith(u8, outcome.stderr, prefix));
    const line = std.mem.trim(u8, outcome.stderr[prefix.len..], "\n");
    const report = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
    defer report.deinit();
    try t.expectEqual(@as(i64, 1), report.value.object.get("version").?.integer);
}

// spec-case: RC-NATIVE-VARIANT-1
test "RC-NATIVE-VARIANT-1 actual native snapshots retained loans mutations and error tags survive" {
    const saved = runtime.get();
    defer runtime.set(saved);
    try exercise(.rc, false);
    try exerciseCounting();
    try exercise(.gc, true);
}

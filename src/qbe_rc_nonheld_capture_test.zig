//! Exact H-role refinement preserves real iterator and uncertain publications.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-NONHELD-CAPTURE-1";
const source =
    \\def literal(count: int) -> int:
    \\    flags = [True, True]
    \\    for at in range(count):
    \\        flags[0] = False
    \\    total = 0
    \\    for flag in flags:
    \\        if flag:
    \\            total += 1
    \\    return total
    \\def make_flags() -> list[bool]:
    \\    return [True, True]
    \\def returned() -> int:
    \\    flags = make_flags()
    \\    flags[0] = False
    \\    total = 0
    \\    for flag in flags:
    \\        if flag:
    \\            total += 1
    \\    return total
    \\def parameter(flags: mut list[bool]) -> int:
    \\    flags[0] = False
    \\    total = 0
    \\    for flag in flags:
    \\        if flag:
    \\            total += 1
    \\    return total
    \\def repeated(groups: list[list[bool]]) -> int:
    \\    total = 0
    \\    for element in groups:
    \\        flags = element
    \\        flags[0] = False
    \\        for flag in flags:
    \\            if flag:
    \\                total += 1
    \\    return total
    \\def rebound(count: int) -> int:
    \\    flags = [True, True]
    \\    flags = make_flags()
    \\    flags[0] = False
    \\    for flag in flags:
    \\        if flag:
    \\            count += 1
    \\    return count
    \\def change(flags: mut list[bool]) -> int:
    \\    flags.clear()
    \\    flags.append(True)
    \\    return 0
    \\def callback() -> int:
    \\    flags = [True, True]
    \\    mutation_result_58 = change(mut flags)
    \\    flags[mutation_result_58] = False
    \\    total = 0
    \\    for flag in flags:
    \\        if flag:
    \\            total += 1
    \\    return total
    \\def pattern(candidate: Option[list[bool]]) -> int:
    \\    match candidate:
    \\        case Some(flags):
    \\            first = flags[0]
    \\            total = 0
    \\            if first:
    \\                total += 1
    \\            for flag in flags:
    \\                if flag:
    \\                    total += 1
    \\            return total
    \\        case None:
    \\            return 0
    \\def main() -> int:
    \\    return literal(1)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "nonheld.my", source);
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

// spec: RC-NONHELD-CAPTURE-1
test "RC nonheld captures retain actual iterator holds and owner frames" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const literal = try named(manifest.value, "literal");
    try t.expect(contains(literal, marker));
    try t.expect(contains(literal, "# RC-GLUE-1 hold"));
    try t.expect(contains(literal, "# rc-frame"));
    try t.expect(contains(literal, "myl_qbe_rc_unique_local"));
    try t.expect(contains(try named(manifest.value, "returned"), marker));
    try t.expect(!contains(try named(manifest.value, "parameter"), marker));
    try t.expect(!contains(try named(manifest.value, "repeated"), marker));
    try t.expect(!contains(try named(manifest.value, "rebound"), marker));
    // The earlier mut call has finished before the new receiver is captured.
    try t.expect(contains(try named(manifest.value, "callback"), marker));
    try t.expect(!contains(try named(manifest.value, "pattern"), marker));
}

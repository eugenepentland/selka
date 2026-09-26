//! Nested mutable arguments retain their place across reordered call operands.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def change(first: mut dict[int,int], second: mut dict[int,int], source: dict[int,dict[int,int]]) -> int:
    \\    first[1] = 13
    \\    second[1] = 17
    \\    return source[0][1] + source[2][1]
    \\def main() -> int:
    \\    original = {0:{1:7},2:{1:8}}
    \\    return change(second=mut original[2], first=mut original[0], source=original)
;

fn emission(input: []const u8) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "mut_places.my", input);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn mainText(manifest: Manifest) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, "main")) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: COW-MUT-ARGUMENT-1
test "COW-MUT-ARGUMENT-1 named GC places pin before call and restore afterward" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.gc);
    var manifest = try emission(source);
    defer manifest.deinit();
    const text = try mainText(manifest.value);
    const prepare = std.mem.indexOf(u8, text, "call $myl_native_cow_scope_prepare") orelse return error.TestUnexpectedResult;
    const call = std.mem.indexOf(u8, text, "call $myl_f_") orelse return error.TestUnexpectedResult;
    const release = std.mem.indexOf(u8, text[call..], "call $myl_native_cow_scope_release") orelse return error.TestUnexpectedResult;
    try t.expect(prepare < call and release != 0);
}

// spec-case: COW-MUT-ARGUMENT-1
test "COW-MUT-ARGUMENT-1 named RC places keep guarded lifetime holds through call" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var manifest = try emission(source);
    defer manifest.deinit();
    const text = try mainText(manifest.value);
    const pin = std.mem.indexOf(u8, text, "call $myl_qbe_rc_scope_pin") orelse return error.TestUnexpectedResult;
    const call = std.mem.indexOf(u8, text, "call $myl_f_") orelse return error.TestUnexpectedResult;
    try t.expect(pin < call);
    try t.expect(std.mem.count(u8, text[call..], "call $myl_qbe_rc_scope_end") >= 3);
}

// spec-case: COW-MUT-ARGUMENT-1
test "COW-MUT-ARGUMENT-1 indirect mutable calls prepare and release receiver scopes" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_counting);
    var manifest = try emission(
        \\def change(target: mut dict[int,int], source: dict[int,dict[int,int]]) -> int:
        \\    target[1] = 13
        \\    return source[0][1]
        \\def main() -> int:
        \\    original = {0:{1:7}}
        \\    action = change
        \\    return action(mut original[0], original)
    );
    defer manifest.deinit();
    const text = try mainText(manifest.value);
    const call = std.mem.indexOf(u8, text, " call %v") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, text[0..call], "call $myl_qbe_rc_scope_pin") != null);
    try t.expect(std.mem.count(u8, text[call..], "call $myl_qbe_rc_scope_end") >= 2);
}

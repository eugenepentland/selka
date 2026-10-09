//! Front-end contracts for direct C imports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const entry =
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "foreign.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "direct C imports preserve formatting and mark the C ABI" {
    const source =
        \\extern func abs(host: Host, x: i32) -> i32 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return i64(abs(host, -7))
    ;
    var c = try language.Compilation.init(t.allocator, "foreign.my", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "extern func abs") != null);
    try c.check();
    try t.expect(c.program.?.functions[0].policy.c_abi);
}

// spec: C-FFI-1
test "direct C declarations reject unsupported signatures and preserve effect checking" {
    try reject(
        \\extern func f(host: Host, x: Unit) -> i64 effects(host)
    ++ entry, "E_EXTERN_SIGNATURE");
    try reject(
        \\extern func f[T](host: Host, x: T) -> T effects(host)
    ++ entry, "E_HOST_DECLARATION");
    try reject(
        \\extern func f(host: Host) -> i64
    ++ entry, "E_HOST_EFFECTS");
    try reject(
        \\extern func f(host: Host) effects(host)
    ++ entry, "E_EXTERN_SIGNATURE");
    try reject(
        \\extern func myl_intrude(host: Host) -> i64 effects(host)
    ++ entry, "E_EXTERN_SYMBOL");
    try reject(
        \\extern func f(host: Host) -> i64 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64 effects():
        \\    return f(host)
    , "E_EFFECT_BOUND");
}

// spec-case: HOST-CAPABILITY-1
test "foreign declarations require a leading Host capability parameter" {
    try reject(
        \\extern func f(x: i64) -> i64 effects(host)
    ++ entry, "E_HOST_CAPABILITY");
}

//! Frontend and backend contracts for direct C imports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const entry =
    \\def main() -> i64:
    \\    return 0
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "foreign.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "direct C imports preserve formatting and reject VM registry and legacy C emission" {
    const source =
        \\extern def abs(x: i32) -> i32 effects(host)
        \\
        \\
        \\def main() -> i64:
        \\    return i64(abs(-7))
    ;
    var c = try language.Compilation.init(t.allocator, "foreign.my", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "extern fn abs") != null);
    try c.emit();
    try t.expect(c.code.?.functions[0].policy.c_abi);
    var functions = try t.allocator.dupe(language.bytecode.Function, c.code.?.functions);
    defer t.allocator.free(functions);
    functions[0].policy.host = null;
    var forged = c.code.?;
    forged.functions = functions;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, forged));
    try t.expectError(error.ExternRequiresQbe, @import("vm_host.zig").Registry.init(t.allocator, c.code.?));
}
test "direct C supports bool void and binary64 without provider registration" {
    var c = try language.Compilation.init(t.allocator, "foreign.my",
        \\extern def floor(x: float) -> float effects(host)
        \\
        \\
        \\extern def flush() effects(host)
        \\
        \\
        \\extern def invert(x: bool) -> bool effects(host)
    ++ entry);
    defer c.deinit();
    try c.emit();
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    try t.expect(std.mem.indexOf(u8, manifest, "call $floor(d %c0)") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "call $flush()") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "call $invert(ub %a0)") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "\"declarations\":[]") != null);
}

// spec: C-FFI-1
test "direct C declarations reject unsupported signatures and preserve effect checking" {
    try reject(
        \\extern def f(x: None) -> i64 effects(host)
    ++ entry, "E_EXTERN_SIGNATURE");
    try reject(
        \\class R:
        \\    x: i64
        \\
        \\
        \\extern def f(x: R) -> i64 effects(host)
    ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern fn f<T:copy>(x:T)->T effects(host);" ++ entry, "E_HOST_DECLARATION");
    try reject("extern fn f()->i64;" ++ entry, "E_HOST_EFFECTS");
    try reject("extern fn f() effects(host);" ++ entry, "E_EXTERN_SIGNATURE");
    try reject(
        \\extern def myl_intrude() -> i64 effects(host)
    ++ entry, "E_EXTERN_SYMBOL");
    try reject(
        \\extern def f() -> i64 effects(host)
        \\
        \\
        \\def main() -> i64 effects():
        \\    return f()
    , "E_EFFECT_BOUND");
}

test "direct C imports preserve formatting and reject VM registry binding" {
    const source =
        \\extern def abs(x: i32) -> i32 effects(host)
        \\
        \\
        \\def main() -> i64:
        \\    return i64(abs(-7))
    ;
    var c = try language.Compilation.init(t.allocator, "foreign.my", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "extern fn abs") != null);
    try c.emit();
    try t.expect(c.code.?.functions[0].policy.c_abi);
    var functions = try t.allocator.dupe(language.bytecode.Function, c.code.?.functions);
    defer t.allocator.free(functions);
    functions[0].policy.host = null;
    var forged = c.code.?;
    forged.functions = functions;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, forged));
    try t.expectError(error.ExternRequiresQbe, @import("vm_host.zig").Registry.init(t.allocator, c.code.?));
}

//! Source contracts, transitive effects and tooling for explicit host declarations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const effects = @import("effect_set.zig");
const main_source =
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
const declaration =
    \\host def measure(x: i64) -> i64 effects(host)
    \\
    \\
    \\
;
fn reject(bytes: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "host-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "a host call is rejected under an effect bound that withholds host authority" {
    var c = try language.Compilation.init(t.allocator, "host-eval.my", declaration ++
        \\def bounded() -> i64 effects():
        \\    return measure(1)
        \\
        \\
        \\def main() -> i64:
        \\    return bounded()
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", c.diagnostics.items[0].code);
}
test "host declarations preserve contextual names formatting and separate external implementations" {
    const bytes = declaration ++
        \\host def other(x: i64) -> i64 effects(host)
        \\
        \\
        \\def host(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return host(3)
    ;
    var c = try language.Compilation.init(t.allocator, "host-format.my", bytes);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "host-format.my", formatted);
    defer after.deinit();
    const twice = try after.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
    try after.emit();
    const dump = try after.dump(t.allocator);
    defer t.allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "host declaration") != null);
    try t.expect(std.mem.indexOf(u8, dump, "effects {host}") != null);
    var duplicates = try language.duplicates.discover(t.allocator, after.program.?, .{ .min_nodes = 1, .approximate = true });
    defer duplicates.deinit();
    try t.expectEqual(@as(usize, 2), duplicates.functions_examined);
    try t.expectEqual(@as(usize, 0), duplicates.groups.len);
    for (duplicates.approximate.pairs) |pair| {
        try t.expect(after.program.?.functions[@backingInt(pair.left)].policy.host == null);
        try t.expect(after.program.?.functions[@backingInt(pair.right)].policy.host == null);
    }
}
test "host bytecode validation rejects forged bodies signatures entry and effect contracts" {
    var c = try language.Compilation.init(t.allocator, "host-bytecode.my", declaration ++ main_source);
    defer c.deinit();
    try c.emit();
    var functions = try t.allocator.dupe(language.bytecode.Function, c.code.?.functions);
    defer t.allocator.free(functions);
    var code = c.code.?;
    code.functions = functions;
    const original = functions[0];
    for (0..7) |kind| {
        functions[0] = original;
        switch (kind) {
            0 => functions[0].scope.instructions = functions[1].scope.instructions,
            1 => functions[0].policy.host = null,
            2 => functions[0].policy.effects = 0,
            3 => functions[0].policy.effect_bound = null,
            4 => functions[0].policy.effect_bound.?.allowed = effects.bit(.clock),
            5 => functions[0].signature.return_type = .clock_cap,
            6 => functions[0].policy.conversion = true,
            else => unreachable,
        }
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, code));
    }
    functions[0] = original;
    code.main = original.id;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, code));
}
test "host effects propagate through ordinary generic and uncalled helper paths" {
    try reject(declaration ++
        \\def main() -> i64 effects():
        \\    return measure(1)
    , "E_EFFECT_BOUND");
    try reject(declaration ++
        \\def helper() -> i64:
        \\    return measure(1)
        \\
        \\
        \\def f[T](x: T) -> i64 effects():
        \\    _ = x
        \\    return helper()
    ++ main_source, "E_EFFECT_BOUND");
    try reject(
        \\host def read() -> i64 effects(host,filesystem)
        \\
        \\
        \\def main() -> i64 effects(host):
        \\    return read()
    , "E_EFFECT_BOUND");
    try reject(declaration ++
        \\def main() -> i64:
        \\    return measure(True)
    , "E_TYPE");
    try reject(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\host def f() -> R effects(host)
        \\
        \\
        \\def main() -> i64:
        \\    value = f()
        \\    return 0
    , "E_RESULT_UNHANDLED");
}
// spec: HOST-SOURCE-1
test "host source declarations require explicit value signatures effects and guest main" {
    try reject(
        \\host def f() -> i64
    ++ main_source, "E_HOST_EFFECTS");
    try reject(
        \\host def f() -> i64 effects()
    ++ main_source, "E_HOST_EFFECTS");
    try reject(
        \\host def f() -> i64 noalloc
    ++ main_source, "E_HOST_EFFECTS");
    try reject(
        \\host def f[T](x: T) -> T effects(host)
    ++ main_source, "E_HOST_DECLARATION");
    try reject(
        \\host conversion def f(x: i64) -> i64 effects(host)
    ++ main_source, "E_HOST_DECLARATION");
    try reject(
        \\domain D: i64:
        \\    host def f() -> i64 effects(host)
    ++ main_source, "E_HOST_DECLARATION");
    try reject(
        \\host def f() -> clock_cap effects(host)
    ++ main_source, "E_HOST_SIGNATURE");
    try reject(
        \\resource File: filesystem
        \\
        \\
        \\host def f(x: File) -> i64 effects(host)
    ++ main_source, "E_HOST_SIGNATURE");
    try reject(
        \\host def f(x: List[i64]) -> i64 effects(host)
    ++ main_source, "E_HOST_SIGNATURE");
    try reject(
        \\host def f() -> i64 effects(host):
        \\    return 1
    ++ main_source, "E_SYNTAX");
    try reject(
        \\host def main() -> i64 effects(host)
    , "E_MAIN");
}

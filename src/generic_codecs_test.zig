//! Generic callers may use concrete domain codecs without accessing private representation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
// migrate-embedded: skip intentional legacy privacy/codec diagnostic provider
const domain =
    \\public record Wire:
    \\    n: i64
    \\
    \\
    \\public result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\
    \\public domain Positive: i64:
    \\    codec Wire:
    \\        decode: from_wire,
    \\        encode: to_wire
    \\
    \\    private func raw(x: i64) -> Positive:
    \\        return wrap[Positive](x)
    \\
    \\    func from_wire(x: Wire) -> Decoded effects():
    \\        if x.n <= 0:
    \\            return Err(-1)
    \\        return Ok(Positive.raw(x.n))
    \\
    \\    func to_wire(x: Positive) -> Wire effects():
    \\        return Wire(n=unwrap(x))
    \\
    \\
    \\
;
const modern_domain =
    \\public record Wire:
    \\    n: i64
    \\
    \\public result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\public record Positive:
    \\    value: i64
    \\
    \\func raw(x: i64) -> Positive:
    \\    return Positive(value=x)
    \\
    \\public func from_wire(x: Wire) -> Decoded:
    \\    if x.n <= 0:
    \\        return Err(-1)
    \\    return Ok(raw(x.n))
    \\
    \\public func to_wire(x: Positive) -> Wire:
    \\    return Wire(n=x.value)
    \\
    \\
;
const helpers =
    \\func my_round[T](ignored: T, n: i64) -> i64:
    \\    _ = ignored
    \\    match from_wire(Wire(n=n)):
    \\        case ok(x):
    \\            return to_wire(x).n
    \\        case err(e):
    \\            return e
    \\
    \\
    \\
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-codecs.selka", modern_domain ++ helpers ++
        \\func main() -> i64:
        \\    return my_round[bool](False, 7) + my_round[i64](2, 0)
    );
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 6), result.value);
}
// spec: GENERIC-CODEC-1
test "generic codecs execute concrete domain factories and accessors under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(body: []const u8, expected: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{
        domain, body, "\n\n\n",
        \\func main() -> i64:
        \\    return 0
    });
    defer t.allocator.free(text);
    var original = try language.Compilation.init(t.allocator, "original-generic-codecs.selka", text);
    defer original.deinit();
    try t.expectError(error.SourceError, original.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", original.diagnostics.items[0].code);
    const current = try std.mem.replaceOwned(u8, t.allocator, text, " effects()", "");
    defer t.allocator.free(current);
    var compilation = try language.Compilation.init(t.allocator, "bad-generic-codecs.selka", current);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items) |item| {
        if (std.mem.eql(u8, expected, item.code)) return;
    }
    try t.expect(false);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8,
            \\import model as m
            \\
            \\
            \\func f[T](x: T) -> i64:
            \\    _ = x
            \\    match m.from_wire(m.Wire(n=23)):
            \\        case ok(p):
            \\            return m.to_wire(p).n
            \\        case err(e):
            \\            return e
            \\
            \\
            \\func main() -> i64:
            \\    return f[bool](False)
        );
        if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8, "" ++ modern_domain);
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 23), (try native.run(&compilation)).value);
}
test "generic codecs follow imported contracts and declaring domain privacy through module relocation" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "generic codecs preserve domain privacy arity input types and result obligations before calls" {
    try reject(
        \\func f[T](n: i64) -> Positive:
        \\    return wrap[Positive](n)
    , "E_PRIVATE_DOMAIN");
    try reject(
        \\func f[T](x: Positive) -> i64:
        \\    return unwrap(x)
    , "E_PRIVATE_DOMAIN");
    try reject(
        \\func f[T](n: i64) -> Positive:
        \\    return Positive.raw(n)
    , "E_PRIVATE_FUNCTION");
    try reject(
        \\func f[T]() -> Decoded:
        \\    return Positive.from_wire()
    , "E_ARITY");
    try reject(
        \\func f[T](n: T) -> Wire:
        \\    return Positive.to_wire(n)
    , "E_GENERIC_TYPE");
    try reject(
        \\func f[T](n: T) -> T:
        \\    return T.to_wire(n)
    , "E_GENERIC_REQUIREMENT");
}

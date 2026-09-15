//! Generic callers may use concrete domain codecs without accessing private representation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const domain =
    \\class Wire:
    \\    n: i64
    \\
    \\
    \\result Decoded:
    \\    ok: Positive,
    \\    err: i64
    \\
    \\
    \\domain Positive: i64:
    \\    codec Wire:
    \\        decode: from_wire,
    \\        encode: to_wire
    \\
    \\    private def raw(x: i64) -> Positive:
    \\        return wrap[Positive](x)
    \\
    \\    def from_wire(x: Wire) -> Decoded effects():
    \\        if x.n <= 0:
    \\            return Err(-1)
    \\        return Ok(Positive.raw(x.n))
    \\
    \\    def to_wire(x: Positive) -> Wire effects():
    \\        return Wire(n=unwrap(x))
    \\
    \\
    \\
;
const helpers =
    \\def round[T](ignored: T, n: i64) -> i64:
    \\    _ = ignored
    \\    match Positive.from_wire(Wire(n=n)):
    \\        case Decoded.ok(x):
    \\            return Positive.to_wire(x).n
    \\        case Decoded.err(e):
    \\            return e
    \\
    \\
    \\
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic-codecs.my", domain ++ helpers ++
        \\def main() -> i64:
        \\    return round[bool](False, 7) + round[i64](2, 0)
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
        \\def main() -> i64:
        \\    return 0
    });
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "bad-generic-codecs.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import model as m
            \\
            \\
            \\def f[T](x: T) -> i64:
            \\    _ = x
            \\    match m.Positive.from_wire(m.Wire(n=23)):
            \\        case m.Decoded.ok(p):
            \\            return m.Positive.to_wire(p).n
            \\        case m.Decoded.err(e):
            \\            return e
            \\
            \\
            \\def main() -> i64:
            \\    return f[bool](False)
        );
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8, "module model\nexport Wire\nexport Decoded\nexport Positive\n" ++ domain);
        return error.NotFound;
    }
};
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 23), (try native.run(&compilation)).value);
}
test "generic codecs follow imported contracts and declaring domain privacy through module relocation" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "generic codecs preserve domain privacy arity input types and result obligations before calls" {
    try reject(
        \\def f[T](n: i64) -> Positive:
        \\    return wrap[Positive](n)
    , "E_PRIVATE_DOMAIN");
    try reject(
        \\def f[T](x: Positive) -> i64:
        \\    return unwrap(x)
    , "E_PRIVATE_DOMAIN");
    try reject(
        \\def f[T](n: i64) -> Positive:
        \\    return Positive.raw(n)
    , "E_PRIVATE_FUNCTION");
    try reject(
        \\def f[T]() -> Decoded:
        \\    return Positive.from_wire()
    , "E_ARITY");
    try reject(
        \\def f[T](n: T) -> Wire:
        \\    return Positive.to_wire(n)
    , "E_GENERIC_TYPE");
    try reject(
        \\def f[T](n: T) -> T:
        \\    return T.to_wire(n)
    , "E_GENERIC_REQUIREMENT");
}

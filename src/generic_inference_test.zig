//! Omitted generic arguments use the same checked substitutions as explicit calls.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const text =
    \\def id[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\def sum[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return x + sum(x - T(1))
    \\
    \\
    \\def forward[U: integer](x: U) -> U:
    \\    return id(sum(x))
    \\
    \\
    \\def main() -> i64:
    \\    small = forward(4u8)
    \\    wide = forward(5)
    \\    if id(True):
    \\        return i64(small) + wide + sum[i64](2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "inference.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try compilation.execute(allocator)).value);
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-INFERENCE-1
test "generic inferCall allocation failures preserve widths forwarding recursion and instance reuse" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn run(text_input: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "shapes.my", text_input);
    defer compilation.deinit();
    const result = try compilation.execute(t.allocator);
    try t.expectEqual(expected, result.value);
}
test "generic inference follows arrays nominal applications const lengths and callbacks" {
    try run(
        \\def first[T, const N: u64](x: [N]T) -> T:
        \\    return x[0]
        \\
        \\
        \\def forward[U, const M: u64](x: [M]U) -> U:
        \\    return first(x)
        \\
        \\
        \\def main() -> i64:
        \\    values: [2]i64 = [7, 9]
        \\    return forward(values)
    , 7);
    try run(
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def unbox[T](x: Box[T]) -> T:
        \\    return x.value
        \\
        \\
        \\def forward[U](x: Box[U]) -> U:
        \\    return unbox(x)
        \\
        \\
        \\def main() -> i64:
        \\    return forward(Box[i64](value=9))
    , 9);
    try run(
        \\class Chunk[T, const N: u64]:
        \\    items: [N]T
        \\
        \\
        \\def first[T, const N: u64](x: Chunk[T, N]) -> T:
        \\    return x.items[0]
        \\
        \\
        \\def forward[U, const M: u64](x: Chunk[U, M]) -> U:
        \\    return first(x)
        \\
        \\
        \\def main() -> i64:
        \\    return forward(Chunk[i64, 2](items=[8, 9]))
    , 8);
    try run(
        \\def inc(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def apply[T](f: def(T) -> T effects(), x: T) -> T:
        \\    return f(x)
        \\
        \\
        \\def main() -> i64:
        \\    return apply(inc, 4)
    , 5);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import helper as h
            \\
            \\
            \\def main() -> i64:
            \\    values: [2]i64 = [7, 9]
            \\    return h.first(values)
        );
        if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8,
            \\module helper
            \\export first
            \\
            \\
            \\def first[T, const N: u64](x: [N]T) -> T:
            \\    return x[0]
        );
        return error.NotFound;
    }
};
test "generic inference keeps module relocation and formatter source identity" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 7), (try language.vm.run(t.allocator, compilation.code.?)).value);
    var source_compilation = try language.Compilation.init(t.allocator, "format.my", text);
    defer source_compilation.deinit();
    const formatted = try source_compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try run(formatted, 28);
}

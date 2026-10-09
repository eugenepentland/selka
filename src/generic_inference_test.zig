//! Omitted generic arguments use the same checked substitutions as explicit calls.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const text =
    \\func id[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\func sum[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return x + sum(x - T(1))
    \\
    \\
    \\func forward[U: integer](x: U) -> U:
    \\    return id(sum(x))
    \\
    \\
    \\func main() -> i64:
    \\    mut small = forward(4u8)
    \\    mut wide = forward(5)
    \\    if id(True):
    \\        return i64(small) + wide + sum[i64](2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "inference.selka", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try native.run(&compilation)).value);
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-INFERENCE-1
test "generic inferCall allocation failures preserve widths forwarding recursion and instance reuse" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn run(text_input: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "shapes.selka", text_input);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqual(expected, result.value);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, source_names.entry)) return allocator.dupe(u8,
            \\import helper as h
            \\
            \\
            \\func main() -> i64:
            \\    mut values: FixedArray[i64, 2] = FixedArray[i64, 2]([7, 9])
            \\    return h.first(values)
        );
        if (std.mem.eql(u8, path, "helper.selka")) return allocator.dupe(u8,
            \\
            \\
            \\public func first[T, const N: u64](x: [N]T) -> T effects():
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
    try compilation.check();
    try t.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    var source_compilation = try language.Compilation.init(t.allocator, "format.selka", text);
    defer source_compilation.deinit();
    const formatted = try source_compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try run(formatted, 28);
}

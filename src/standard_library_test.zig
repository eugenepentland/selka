//! Builtin modules obey project loading rules and execute generic, non-EDA queries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const source =
    "module main;import std_iter;" ++
    "fn main()->i64{let mut state=std_iter::pairs(4u64);let mut count=0;" ++
    "while !state.done{count+=1;state=std_iter::next_pair(state);}return count;}";
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-MODULES-1
test "standard modules load through embedded providers and execute reserved sources" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = read });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 6), outcome.value);
    try t.expectEqual(@as(usize, 2), program.loaded.modules.items.len);
}
// spec: STANDARD-MODULES-2
test "standard modules remain inside the total project byte budget" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(.{ .context = null, .read = read }, "main", .{ .max_total_bytes = source.len + 1 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", project.problem.?.code);
}

const Fixture = struct {
    text: []const u8,
    fn load(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Fixture = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};
fn runLibrary(text: []const u8, expected: i64) !void {
    var fixture: Fixture = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &fixture, .read = Fixture.load });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(expected, outcome.value);
}
// spec: STANDARD-MODULES-7
test "standard generic results cannot be silently ignored" {
    try t.expectError(error.SourceError, runLibrary(
        "module main;import std_math;fn main()->i64{let forgotten=std_math::to_u64(std_math::from_i64(1));return 0;}",
        0,
    ));
}

// spec: STANDARD-INTEGER-EXTREMA-1
test "integer extrema cover all widths and full signed ranges" {
    try runLibrary(@embedFile("stdlib/fixtures/integer_extrema.my"), 42);
}

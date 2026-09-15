//! Direct import dot syntax preserves module visibility and local method namespaces.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;
const File = language.embedded_project.File;
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};
const api =
    \\module library.api
    \\export Inputs
    \\export Box
    \\export parse
    \\export identity
    \\export Distance
    \\export extra
    \\
    \\
    \\class Inputs:
    \\    value: i64
    \\
    \\
    \\class Box[T]:
    \\    value: T
    \\
    \\
    \\class Hidden:
    \\    value: i64
    \\
    \\
    \\def parse(input: Inputs) -> i64 effects():
    \\    return input.value + 1
    \\
    \\
    \\def identity[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\def extra() -> i64:
    \\    return 1
    \\
    \\
    \\def hidden() -> i64:
    \\    return 99
    \\
    \\
    \\domain Distance: i64:
    \\    private def raw(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\    def make(x: i64) -> Distance:
    \\        return Distance.raw(x)
    \\
    \\    def number(x: Distance) -> i64:
    \\        return unwrap(x)
;

fn scenario(allocator: std.mem.Allocator, main: []const u8, expected_error: ?[]const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main }, .{ .path = "library/api.my", .bytes = api } } };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = language.interfaces.build(&project) catch |err| {
        if (err != error.SourceError) return err;
        if (expected_error) |code| return t.expectEqualStrings(code, project.problem.?.code);
        debug.print("{s}: {s}\n", .{ project.problem.?.code, project.problem.?.message });
        return err;
    };
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.emit() catch |err| {
        if (err != error.SourceError) return err;
        if (expected_error) |code| return t.expectEqualStrings(code, compilation.diagnostics.items.items[0].code);
        for (compilation.diagnostics.items.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(expected_error == null);
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}
const header = "module main\nimport library.api as api\n";
const dotted = header ++
    \\export Sample
    \\
    \\
    \\class Sample:
    \\    input: api.Inputs
    \\
    \\
    \\def main() -> i64:
    \\    values: list[i64] = []
    \\    values.append(40)
    \\    input = api.Inputs(value=values[0])
    \\    boxed = api.Box[api.Inputs](value=input)
    \\    copy = api.identity[api.Inputs](boxed.value)
    \\    distance = api.Distance.make(api.parse(copy))
    \\    return api.Distance.number(distance) + api.extra()
;

// spec: MODULE-DOT-1
test "dotted imports resolve calls types generic records and domains beside list methods" {
    try scenario(t.allocator, dotted, null);
    var compilation = try language.Compilation.init(t.allocator, "main.my", dotted);
    defer compilation.deinit();
    const formatted = try compilation.formatModule(t.allocator);
    defer t.allocator.free(formatted);
    try scenario(t.allocator, formatted, null);
}

// spec: MODULE-DOT-2
test "dotted imports preserve function values and generic body type references" {
    try scenario(t.allocator, header ++
        \\def use[T: copy](unused: T, input: api.Inputs) -> i64:
        \\    return api.parse(input)
        \\
        \\
        \\def main() -> i64:
        \\    parse = api.parse
        \\    input = api.Inputs(value=40)
        \\    return parse(input) + use[i64](0, api.Inputs(value=0))
    , null);
}

// spec: MODULE-DOT-4
test "dotted module parsing and name resolution release every failed allocation" {
    var failures = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(failures.allocator(), scenario, .{ dotted, null });
}

// spec: MODULE-DOT-3
test "dotted imports retain private symbol private domain and alias shadow checks" {
    try scenario(t.allocator, header ++
        \\def main() -> i64:
        \\    return api.hidden()
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\def main() -> i64:
        \\    _ = api.Distance.raw(42)
        \\    return 42
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\export Sample
        \\
        \\
        \\class Sample:
        \\    input: api.Hidden
        \\
        \\
        \\def main() -> i64:
        \\    return 42
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\def main() -> i64:
        \\    api = 42
        \\    return api
    , "E_SHADOWING");
}

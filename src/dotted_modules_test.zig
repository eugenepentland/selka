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
    \\def identity[T](value: T) -> T effects():
    \\    return value
    \\
    \\
    \\def extra() -> i64 effects():
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
    \\    def make(x: i64) -> Distance effects():
    \\        return Distance.raw(x)
    \\
    \\    def number(x: Distance) -> i64 effects():
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

// spec: MODULE-DOT-6
test "unaliased dotted imports resolve the full module path and the trailing alias" {
    const unaliased = "module main\nimport library.api\n\n";
    try scenario(t.allocator, unaliased ++
        \\def main() -> i64:
        \\    return library.api.parse(library.api.Inputs(value=41))
    , null);
    try scenario(t.allocator, unaliased ++
        \\def main() -> i64:
        \\    return api.parse(api.Inputs(value=41))
    , null);
}

// spec-case: MODULE-DOT-6
test "a bare dotted-import prefix stays an ordinary name beside the qualified path" {
    const unaliased = "module main\nimport library.api\n\n";
    // A local may reuse the first segment and read its own fields.
    try scenario(t.allocator, unaliased ++
        \\record Holder:
        \\    value: i64
        \\
        \\
        \\def main() -> i64:
        \\    library = Holder(value=42)
        \\    return library.value
    , null);
    // A parameter may reuse it too.
    try scenario(t.allocator, unaliased ++
        \\def read(library: i64) -> i64:
        \\    return library
        \\
        \\
        \\def main() -> i64:
        \\    return read(42)
    , null);
    // An explicit alias still admits the full dotted module path.
    try scenario(t.allocator, "module main\nimport library.api as api\n\n" ++
        \\def main() -> i64:
        \\    return library.api.parse(library.api.Inputs(value=41))
    , null);
}

/// What one checked module pair reports about unused imports.
const ImportReport = struct { unused: usize, unused_message: []const u8, unused_binding: usize };

/// Check one embedded project and summarize its import warnings. The message is
/// copied because the compilation that owns it is released before returning.
fn checkImports(main: []const u8) !ImportReport {
    const other = "module library.other\n\n\npublic def value() -> i64 effects():\n    return 1\n";
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = main },
        .{ .path = "library/api.my", .bytes = api },
        .{ .path = "library/other.my", .bytes = other },
    } };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    var report: ImportReport = .{ .unused = 0, .unused_message = "", .unused_binding = 0 };
    for (compilation.diagnostics.items.items) |item| {
        if (std.mem.eql(u8, item.code, "W_UNUSED_IMPORT")) {
            report.unused += 1;
            report.unused_message = try t.allocator.dupe(u8, item.message);
        }
        if (std.mem.eql(u8, item.code, "W_UNUSED_BINDING")) report.unused_binding += 1;
    }
    return report;
}

// spec: UNUSED-IMPORT-1
test "an import no resolved reference goes through reports W_UNUSED_IMPORT" {
    const main =
        \\module main
        \\import library.api
        \\import library.other
        \\
        \\
        \\def main() -> i64:
        \\    note = "library.other.value()"
        \\    return library.api.parse(library.api.Inputs(value=41))
    ;
    const report = try checkImports(main);
    defer t.allocator.free(report.unused_message);
    try t.expectEqual(@as(usize, 1), report.unused);
    try t.expectEqualStrings("import `library.other` is never referenced in this module; remove it or use it", report.unused_message);
    // The alias spelling inside a string literal is not a reference.
    try t.expect(report.unused_binding >= 1);
}

// spec-case: UNUSED-IMPORT-1
test "an import a signature or a call resolves through is not unused" {
    const main =
        \\module main
        \\import library.api
        \\
        \\
        \\def read(input: library.api.Inputs) -> i64:
        \\    return input.value
        \\
        \\
        \\def main() -> i64:
        \\    return read(library.api.Inputs(value=41))
    ;
    const report = try checkImports(main);
    try t.expectEqual(@as(usize, 0), report.unused);
}

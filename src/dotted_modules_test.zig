//! Direct import dot syntax preserves module visibility and local method namespaces.
const api_module_path = "library/api.selka";
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
// migrate-embedded: skip intentional legacy private-domain diagnostic provider
const legacy_api =
    \\
    \\
    \\public record Inputs:
    \\    value: i64
    \\
    \\
    \\public record Box[T]:
    \\    value: T
    \\
    \\
    \\record Hidden:
    \\    value: i64
    \\
    \\
    \\public func parse(input: Inputs) -> i64 effects():
    \\    return input.value + 1
    \\
    \\
    \\public func identity[T](value: T) -> T effects():
    \\    return value
    \\
    \\
    \\public func extra() -> i64 effects():
    \\    return 1
    \\
    \\
    \\public func len(value: i64) -> i64 effects():
    \\    return value + 1
    \\
    \\
    \\public func replace(value: i64) -> i64 effects():
    \\    return value
    \\
    \\
    \\func hidden() -> i64:
    \\    return 99
    \\
    \\
    \\public domain Distance: i64:
    \\    private func raw(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\    func make(x: i64) -> Distance effects():
    \\        return Distance.raw(x)
    \\
    \\    func number(x: Distance) -> i64 effects():
    \\        return unwrap(x)
;
const api =
    \\
    \\
    \\public record Inputs:
    \\    value: i64
    \\
    \\
    \\public record Box[T]:
    \\    value: T
    \\
    \\
    \\record Hidden:
    \\    value: i64
    \\
    \\
    \\public func parse(input: Inputs) -> i64:
    \\    return input.value + 1
    \\
    \\
    \\public func identity[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\public func extra() -> i64:
    \\    return 1
    \\
    \\
    \\public func len(value: i64) -> i64:
    \\    return value + 1
    \\
    \\
    \\public func replace(value: i64) -> i64:
    \\    return value
    \\
    \\
    \\func hidden() -> i64:
    \\    return 99
    \\
    \\
    \\public record Distance:
    \\    value: i64
    \\
    \\func raw(x: i64) -> Distance:
    \\    return Distance(value=x)
    \\
    \\public func make(x: i64) -> Distance:
    \\    return raw(x)
    \\
    \\public func number(x: Distance) -> i64:
    \\    return x.value
;

fn scenario(allocator: std.mem.Allocator, main: []const u8, expected_error: ?[]const u8) !void {
    if (expected_error != null) {
        var original_files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = api_module_path, .bytes = legacy_api } } };
        var original = language.project.Project.init(allocator);
        defer original.deinit();
        try original.load(.{ .context = &original_files, .read = Files.read }, "main", .{});
        if (language.interfaces.build(&original)) |_| return error.TestExpectedError else |err| {
            if (err != error.SourceError) return err;
        }
        try t.expectEqualStrings("E_EFFECTS_REMOVED", original.problem.?.code);
        const erased = try std.mem.replaceOwned(u8, allocator, legacy_api, " effects()", "");
        defer allocator.free(erased);
        try scenarioWithProvider(allocator, main, erased, expected_error);
        // A former private domain factory is now a private module function.
        const modern_main = try std.mem.replaceOwned(u8, allocator, main, "api.Distance.raw(", "api.raw(");
        defer allocator.free(modern_main);
        return scenarioWithProvider(allocator, modern_main, api, expected_error);
    }
    return scenarioWithProvider(allocator, main, api, null);
}
fn scenarioWithProvider(allocator: std.mem.Allocator, main: []const u8, provider: []const u8, expected_error: ?[]const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = api_module_path, .bytes = provider } } };
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
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        if (expected_error) |code| {
            for (compilation.diagnostics.items.items) |item| {
                if (std.mem.eql(u8, code, item.code)) return;
            }
            return t.expect(false);
        }
        for (compilation.diagnostics.items.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(expected_error == null);
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}
const header = "import library.api as api\n";
const dotted = header ++
    \\
    \\
    \\public record Sample:
    \\    input: api.Inputs
    \\
    \\
    \\func main() -> i64:
    \\    mut values: i64[] = []
    \\    append(mut values, 40)
    \\    mut input = api.Inputs(value=values[0])
    \\    mut boxed = api.Box[api.Inputs](value=input)
    \\    mut copy = api.identity[api.Inputs](boxed.value)
    \\    mut distance = api.make(api.parse(copy))
    \\    return api.number(distance) + api.extra()
;

// spec-case: PRELUDE-SHADOW-2
test "module builtin callable shadows resolve locally and through imports" {
    try scenario(t.allocator, header ++
        \\func replace(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\func main() -> i64:
        \\    return replace(api.replace(api.len(38))) + len([1, 2])
    , null);
    // The module's `len` is reached only as `api.len` from here; a `len` this module declared and called bare would be
    // refused, since a bare call of a prelude name is always the builtin (W6).
    try scenarioWithProvider(t.allocator, header ++
        \\func len(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\func main() -> i64:
        \\    return api.replace(len(41))
    , api, "E_BUILTIN_FUNCTION_NAME");
}

// spec: MODULE-DOT-1
test "dotted imports resolve calls types generic records and domains beside list methods" {
    try scenario(t.allocator, dotted, null);
    var compilation = try language.Compilation.init(t.allocator, "main.selka", dotted);
    defer compilation.deinit();
    const formatted = try compilation.formatModule(t.allocator);
    defer t.allocator.free(formatted);
    try scenario(t.allocator, formatted, null);
}

// spec: MODULE-DOT-2
test "dotted imports preserve function values and generic body type references" {
    try scenario(t.allocator, header ++
        \\func use[T: copy](unused: T, input: api.Inputs) -> i64:
        \\    return api.parse(input)
        \\
        \\
        \\func main() -> i64:
        \\    mut parse = api.parse
        \\    mut input = api.Inputs(value=40)
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
        \\func main() -> i64:
        \\    return api.hidden()
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\func main() -> i64:
        \\    mut _ = api.Distance.raw(42)
        \\    return 42
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\
        \\
        \\public record Sample:
        \\    input: api.Hidden
        \\
        \\
        \\func main() -> i64:
        \\    return 42
    , "E_PRIVATE_SYMBOL");
    try scenario(t.allocator, header ++
        \\func main() -> i64:
        \\    mut api = 42
        \\    return api
    , "E_SHADOWING");
}

// spec: MODULE-DOT-6
test "unaliased dotted imports resolve the full module path and the trailing alias" {
    const unaliased = "import library.api\n\n";
    try scenario(t.allocator, unaliased ++
        \\func main() -> i64:
        \\    return library.api.parse(library.api.Inputs(value=41))
    , null);
    try scenario(t.allocator, unaliased ++
        \\func main() -> i64:
        \\    return api.parse(api.Inputs(value=41))
    , null);
}

// spec-case: MODULE-DOT-6
test "a bare dotted-import prefix stays an ordinary name beside the qualified path" {
    const unaliased = "import library.api\n\n";
    // A local may reuse the first segment and read its own fields.
    try scenario(t.allocator, unaliased ++
        \\record Holder:
        \\    value: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut library = Holder(value=42)
        \\    return library.value
    , null);
    // A parameter may reuse it too.
    try scenario(t.allocator, unaliased ++
        \\func read(library: i64) -> i64:
        \\    return library
        \\
        \\
        \\func main() -> i64:
        \\    return read(42)
    , null);
    // An explicit alias still admits the full dotted module path.
    try scenario(t.allocator, "import library.api as api\n\n" ++
        \\func main() -> i64:
        \\    return library.api.parse(library.api.Inputs(value=41))
    , null);
}

/// What one checked module pair reports about unused imports.
const ImportReport = struct { unused: usize, unused_message: []const u8, unused_binding: usize };

/// Check one embedded project and summarize its import warnings. The message is
/// copied because the compilation that owns it is released before returning.
fn checkImports(main: []const u8) !ImportReport {
    const other = "\n\npublic func value() -> i64:\n    return 1\n";
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = main },
        .{ .path = api_module_path, .bytes = api },
        .{ .path = "library/other.selka", .bytes = other },
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
        \\import library.api
        \\import library.other
        \\
        \\
        \\func main() -> i64:
        \\    mut note = "library.other.value()"
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
        \\import library.api
        \\
        \\
        \\func read(input: library.api.Inputs) -> i64:
        \\    return input.value
        \\
        \\
        \\func main() -> i64:
        \\    return read(library.api.Inputs(value=41))
    ;
    const report = try checkImports(main);
    try t.expectEqual(@as(usize, 0), report.unused);
}

// spec-case: UNUSED-IMPORT-1
test "qualified variant imports survive header and fallback recovery without bare prefix false positives" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import object
        \\import factory
        \\import library.api
        \\record Holder:
        \\    value: int
        \\func main() -> int:
        \\    const library = Holder(value=0)
        \\    # library.api.parse is not a reference
        \\    const note = 'library.api.parse'
        \\    _ = note
        \\    match factory.make():
        \\        case object.Obj.one(value=n):
        \\            return n + library.value
        \\        case object.Obj.empty:
        \\            return library.value
        \\
        },
        .{ .path = "object.selka", .bytes = "public enum Obj:\n    one(value: int)\n    empty\n" },
        .{ .path = "factory.selka", .bytes = "import object\npublic func make() -> object.Obj:\n    return object.Obj.one(value=1)\n" },
        .{ .path = api_module_path, .bytes = api },
    } };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    const main = project.names.get("main").?;
    try t.expect(project.modules.items[main].imports[0].seen);
    try t.expect(!project.modules.items[main].imports[2].seen);
    var index = try language.interfaces.build(&project);
    for ([_]bool{ true, false }) |header_scanned| {
        project.modules.items[main].header.usage_scanned = header_scanned;
        @memset(index.units[main].import_used, false);
        index.recoverImportUsage(t.allocator);
        try t.expect(index.importUsed(main, 0));
        try t.expect(index.importUsed(main, 1));
        try t.expect(!index.importUsed(main, 2));
    }
}

// spec-case: UNUSED-IMPORT-1
test "qualified import scan prefers longest module and accepts alias and dotted variant owners" {
    const cases = [_]struct { source: []const u8, used: [3]bool }{
        .{ .source = "import object\nimport models.object as obj\nimport library.api\nfunc f() -> int:\n    match 0:\n        case obj.Obj.one(value=n):\n            return n\n", .used = .{ false, true, false } },
        .{ .source = "import object as standalone\nimport models.object\nimport library.api\nfunc f() -> int:\n    match 0:\n        case models.object.Obj.one(value=n):\n            return n\n", .used = .{ false, true, false } },
        .{ .source = "import object\nimport object.extra\nimport library.api\nfunc f() -> int:\n    return object.extra.value()\n", .used = .{ false, true, false } },
    };
    for (cases) |case| {
        var files: Files = .{ .entries = &.{
            .{ .path = "main.selka", .bytes = case.source },
            .{ .path = "object.selka", .bytes = "public enum Obj:\n    one(value: int)\n" },
            .{ .path = "models/object.selka", .bytes = "public enum Obj:\n    one(value: int)\n" },
            .{ .path = "object/extra.selka", .bytes = "public func value() -> int:\n    return 0\n" },
            .{ .path = api_module_path, .bytes = api },
        } };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
        const main = project.names.get("main").?;
        var index = try language.interfaces.build(&project);
        for ([_]bool{ true, false }) |header_scanned| {
            project.modules.items[main].header.usage_scanned = header_scanned;
            @memset(index.units[main].import_used, false);
            index.recoverImportUsage(t.allocator);
            for (case.used, 0..) |used, i| try t.expectEqual(used, index.importUsed(main, i));
        }
    }
}

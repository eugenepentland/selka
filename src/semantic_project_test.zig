//! Import/export and module relocation remain dependencies of semantic body queries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Cache = language.semantic_cache.Cache;
const File = language.embedded_project.File;
const Files = struct {
    entries: []File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};
fn evaluate(files: *Files, cache: ?*Cache) ![]u8 {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.checkWithCache(cache) catch |err| {
        if (err != error.SourceError) return err;
        return language.diagnostic_output.render(t.allocator, compilation.diagnostics.items.items[0], compilation.src, .json);
    };
    try compilation.emit();
    const result = try native.run(&compilation);
    return std.fmt.allocPrint(t.allocator, "value:{d}", .{result.value});
}
fn agree(files: *Files, cache: *Cache) !void {
    const cached = try evaluate(files, cache);
    defer t.allocator.free(cached);
    const fresh = try evaluate(files, null);
    defer t.allocator.free(fresh);
    try t.expectEqualStrings(fresh, cached);
}
// spec: SEMANTIC-CACHE-6
test "semantic project body reuse relocates module spans and invalidates changed imports exports signatures and types" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data
        \\
        \\
        \\def main() -> i64:
        \\    return data.value()
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 41
        },
        .{ .path = "other.my", .bytes =
        \\module other
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 43
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\module data
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\module data
        \\
        \\
        \\public def value() -> bool effects():
        \\    return True
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\module data
        \\
        \\
        \\def value() -> i64:
        \\    return 42
    ;
    try agree(&files, &cache);
    entries[0].bytes =
        \\module main
        \\import other
        \\
        \\
        \\def main() -> i64:
        \\    return other.value()
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
}

// spec: MODULE-DOT-5
test "dotted imported function values keep callback type catalogs fresh across cache requests" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data as d
        \\
        \\
        \\def main() -> i64:
        \\    helper = d.value
        \\    return helper()
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 41
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\module data
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    // Callable values stay on the fresh path for C1; the ordinary `data.value`
    // body still publishes a reusable snapshot.
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
}

/// Check one project without lowering or running it, so tests can read the
/// semantic cache's actual execution-site counters.
fn checkOnly(files: *Files, cache: *Cache) !void {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.checkWithCache(cache);
}

// spec-case: SEMANTIC-CACHE-7
test "module insert and reorder with an unused generic preserve ordinary body reuse" {
    const main_unordered =
        \\module main
        \\import a
        \\
        \\
        \\def main() -> i64:
        \\    return a.first() + a.second()
    ;
    const main_reordered =
        \\module main
        \\import util
        \\import a
        \\
        \\
        \\def main() -> i64:
        \\    return a.first() + a.second()
    ;
    const a =
        \\module a
        \\
        \\
        \\public def first() -> i64 effects():
        \\    return 1
        \\
        \\
        \\public def second() -> i64 effects():
        \\    return 7
        \\
        \\
        \\def unused[T](value: T) -> T:
        \\    return value
    ;
    const util =
        \\module util
        \\
        \\
        \\def unused[T](value: T) -> T:
        \\    return value
    ;
    var base = [_]File{ .{ .path = "main.my", .bytes = main_unordered }, .{ .path = "a.my", .bytes = a } };
    var files: Files = .{ .entries = &base };
    var cache = Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    try checkOnly(&files, &cache);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);

    const before = cache.statistics.reused;
    const before_checked = cache.statistics.checked;
    var edited = [_]File{
        .{ .path = "main.my", .bytes = main_reordered },
        .{ .path = "util.my", .bytes = util },
        .{ .path = "a.my", .bytes = a },
    };
    var reordered: Files = .{ .entries = &edited };
    try checkOnly(&reordered, &cache);
    // Module input positions changed and an unrelated module with an unused
    // generic was added, but every ordinary body is byte-identical.
    try t.expectEqual(before + 3, cache.statistics.reused);
    try t.expectEqual(before_checked, cache.statistics.checked);
}

// spec-case: SEMANTIC-CACHE-7
test "same bare name in two modules resolves to distinct identities" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import a
        \\import b
        \\
        \\
        \\def main() -> i64:
        \\    return a.run() + b.run()
        },
        .{ .path = "a.my", .bytes =
        \\module a
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 1
        \\
        \\
        \\public def run() -> i64 effects():
        \\    return helper()
        },
        .{ .path = "b.my", .bytes =
        \\module b
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 2
        \\
        \\
        \\public def run() -> i64 effects():
        \\    return helper()
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    try checkOnly(&files, &cache);
    try t.expectEqual(@as(usize, 5), cache.statistics.checked);

    entries[1].bytes =
        \\module a
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 11
        \\
        \\
        \\public def run() -> i64 effects():
        \\    return helper()
    ;
    const before = cache.statistics.reused;
    const before_checked = cache.statistics.checked;
    try checkOnly(&files, &cache);
    // `a.helper` changed and only `a.run`'s resolved dependency moved with it;
    // `b.helper`/`b.run` and `main` are untouched even though a bare `helper`
    // is declared twice in the project.
    try t.expectEqual(before + 4, cache.statistics.reused);
    try t.expectEqual(before_checked + 1, cache.statistics.checked);
}

// spec-case: SEMANTIC-CACHE-7
test "adding an unrelated import directive does not invalidate ordinary bodies" {
    const a_base =
        \\module a
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 1
    ;
    const a_imported =
        \\module a
        \\import b
        \\
        \\
        \\public def helper() -> i64 effects():
        \\    return 1
    ;
    var base = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import a
        \\
        \\
        \\def main() -> i64:
        \\    return a.helper()
        },
        .{ .path = "a.my", .bytes = a_base },
    };
    var files: Files = .{ .entries = &base };
    var cache = Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    try checkOnly(&files, &cache);
    try t.expectEqual(@as(usize, 2), cache.statistics.checked);

    const before = cache.statistics.reused;
    var edited = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import a
        \\
        \\
        \\def main() -> i64:
        \\    return a.helper()
        },
        .{ .path = "a.my", .bytes = a_imported },
        .{ .path = "b.my", .bytes =
        \\module b
        \\
        \\
        \\def unused[T](value: T) -> T:
        \\    return value
        },
    };
    var imported: Files = .{ .entries = &edited };
    try checkOnly(&imported, &cache);
    // The import list change is not itself a dependency: only bodies whose
    // resolved references actually changed miss.
    try t.expectEqual(before + 2, cache.statistics.reused);
    try t.expectEqual(@as(usize, 2), cache.statistics.checked);
}

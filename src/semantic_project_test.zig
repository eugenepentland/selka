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
    try compilation.check();
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
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return data.value()
        },
        .{ .path = "data.my", .bytes =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 41
        },
        .{ .path = "other.my", .bytes =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 43
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\
        \\
        \\public func value() -> bool effects():
        \\    return True
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\
        \\
        \\func value() -> i64:
        \\    return 42
    ;
    try agree(&files, &cache);
    entries[0].bytes =
        \\import other
        \\
        \\
        \\func main() -> i64:
        \\    return other.value()
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
}

// spec: MODULE-DOT-5
test "dotted imported function values keep callback type catalogs fresh across cache requests" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\import data as d
        \\
        \\
        \\func main() -> i64:
        \\    mut helper = d.value
        \\    return helper()
        },
        .{ .path = "data.my", .bytes =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 41
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    // The unchanged caller reconstructs the imported callback's current type;
    // the changed implementation is checked again.
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
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
        \\import a
        \\
        \\
        \\func main() -> i64:
        \\    return a.first() + a.second()
    ;
    const main_reordered =
        \\import util
        \\import a
        \\
        \\
        \\func main() -> i64:
        \\    return a.first() + a.second()
    ;
    const a =
        \\
        \\
        \\public func first() -> i64 effects():
        \\    return 1
        \\
        \\
        \\public func second() -> i64 effects():
        \\    return 7
        \\
        \\
        \\func unused[T](value: T) -> T:
        \\    return value
    ;
    const util =
        \\
        \\
        \\func unused[T](value: T) -> T:
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
        \\import a
        \\import b
        \\
        \\
        \\func main() -> i64:
        \\    return a.run() + b.run()
        },
        .{ .path = "a.my", .bytes =
        \\
        \\
        \\public func helper() -> i64 effects():
        \\    return 1
        \\
        \\
        \\public func run() -> i64 effects():
        \\    return helper()
        },
        .{ .path = "b.my", .bytes =
        \\
        \\
        \\public func helper() -> i64 effects():
        \\    return 2
        \\
        \\
        \\public func run() -> i64 effects():
        \\    return helper()
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    try checkOnly(&files, &cache);
    try t.expectEqual(@as(usize, 5), cache.statistics.checked);

    entries[1].bytes =
        \\
        \\
        \\public func helper() -> i64 effects():
        \\    return 11
        \\
        \\
        \\public func run() -> i64 effects():
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
        \\
        \\
        \\public func helper() -> i64 effects():
        \\    return 1
    ;
    const a_imported =
        \\import b
        \\
        \\
        \\public func helper() -> i64 effects():
        \\    return 1
    ;
    var base = [_]File{
        .{ .path = "main.my", .bytes =
        \\import a
        \\
        \\
        \\func main() -> i64:
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
        \\import a
        \\
        \\
        \\func main() -> i64:
        \\    return a.helper()
        },
        .{ .path = "a.my", .bytes = a_imported },
        .{ .path = "b.my", .bytes =
        \\
        \\
        \\func unused[T](value: T) -> T:
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

// spec-case: SEMANTIC-CACHE-12
test "nominal specialization arguments isolate same spelled declarations in different modules" {
    const entry =
        \\import left
        \\import right
        \\
        \\constraint HasValue[T] = copy + field(value: int)
        \\
        \\func read[T: HasValue](x: T) -> int:
        \\    return x.value
        \\
        \\func main() -> int:
        \\    return read[left.Item](left.Item(value=3)) + read[right.Item](right.Item(value=4))
        \\
    ;
    var entries = [_]File{
        .{ .path = "main.my", .bytes = entry },
        .{ .path = "left.my", .bytes = "public record Item:\n    value: int\n" },
        .{ .path = "right.my", .bytes = "public record Item:\n    value: int\n" },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    const before = cache.reuse.specializations.statistics;
    try t.expectEqual(@as(usize, 2), before.checked);
    try t.expectEqual(@as(usize, 2), before.stored);
    entries[0].bytes = "# relocate\n" ++ entry;
    try agree(&files, &cache);
    const moved = cache.reuse.specializations.statistics;
    try t.expectEqual(before.reused + 2, moved.reused);
    try t.expectEqual(before.checked, moved.checked);
    entries[1].bytes = "public record Item:\n    value: int\n    extra: int = 0\n";
    try agree(&files, &cache);
    const changed = cache.reuse.specializations.statistics;
    try t.expectEqual(moved.reused + 1, changed.reused);
    try t.expectEqual(moved.checked + 1, changed.checked);
}

const case_left =
    \\public enum Packet:
    \\    data(value: i64)
    \\    none
    \\
    \\public func value(p: Packet) -> i64:
    \\    match p:
    \\        case Packet.data(value=n):
    \\            return n
    \\        case _:
    \\            return 0
;
const case_right =
    \\public enum Packet:
    \\    data(value: bool)
    \\    none
    \\
    \\public func value(p: Packet) -> i64:
    \\    match p:
    \\        case Packet.data(value=n):
    \\            if n:
    \\                return 2
    \\            return 0
    \\        case _:
    \\            return 0
;
const case_main =
    \\import left
    \\import right
    \\
    \\func main() -> i64:
    \\    return left.value(left.Packet.data(value=40)) + right.value(right.Packet.data(value=True))
;

fn expectCaseIdentity(files: *Files) !void {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    const records = compilation.program.?.records;
    var payloads: [2]?language.typed.Type = .{ null, null };
    for ([_][]const u8{ "left", "right" }, 0..) |module, side| {
        const parent_name = try std.fmt.allocPrint(t.allocator, "{s}::Packet", .{module});
        defer t.allocator.free(parent_name);
        const payload_name = try std.fmt.allocPrint(t.allocator, "{s}.data", .{parent_name});
        defer t.allocator.free(payload_name);
        for (records) |record| {
            if (!std.mem.eql(u8, record.name, parent_name)) continue;
            const variants = record.shape.variants.?;
            try t.expectEqualStrings("data", variants.cases[0].name);
            try t.expect(variants.cases[0].fielded);
            const payload = variants.cases[0].payload.?;
            payloads[side] = payload;
            try t.expectEqualStrings(payload_name, language.typed.typeName(payload, records));
            try t.expectEqualStrings("value", records[payload.recordIndex()].fields[0].name);
        }
        const id = project.names.get(module).?;
        // The synthetic name is a catalog identity, never a source declaration.
        try t.expect(!index.units[id].names.contains("Packet.data"));
    }
    try t.expect(payloads[0] != null and payloads[1] != null);
    try t.expect(payloads[0].? != payloads[1].?);
}

// spec-case: SEMANTIC-CACHE-7
// spec-case: NOMINAL-INSTANCE-1
test "synthetic enum payload identities retain defining modules across warm replay and relocation" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes = case_main },
        .{ .path = "left.my", .bytes = case_left },
        .{ .path = "right.my", .bytes = case_right },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 << 20);
    defer cache.deinit();
    try expectCaseIdentity(&files);
    const initial = try evaluate(&files, null);
    defer t.allocator.free(initial);
    try t.expectEqualStrings("value:42", initial);
    try agree(&files, &cache);
    const checked = cache.statistics.checked;
    try agree(&files, &cache);
    try t.expectEqual(checked, cache.statistics.checked);
    try t.expectEqual(@as(usize, 0), cache.statistics.rejections.total[@backingInt(language.semantic_cache.MissReason.ambiguous_record)]);
    // Input/module ordinals change; the defining enum identities do not.
    entries[0].bytes = "import right\nimport left\n" ++ case_main["import left\nimport right\n".len..];
    entries[1].bytes = "record Unrelated:\n    n: bool\n\n" ++ case_left;
    try expectCaseIdentity(&files);
    try agree(&files, &cache);
    try t.expectEqual(checked, cache.statistics.checked);
    // Changing one provider invalidates its own payload and every real consumer.
    entries[1].bytes = case_right;
    entries[0].bytes = "import left\nimport right\nfunc main() -> i64:\n    return left.value(left.Packet.data(value=True)) + right.value(right.Packet.data(value=True))\n";
    try agree(&files, &cache);
    try t.expect(cache.statistics.checked > checked);
    const value = try evaluate(&files, null);
    defer t.allocator.free(value);
    try t.expectEqualStrings("value:4", value);
}

// spec-case: SEMANTIC-CACHE-7
// spec-case: NOMINAL-INSTANCE-1
test "synthetic enum payload qualification preserves nominal separation and imported privacy" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes = "import left\nimport right\nfunc main() -> i64:\n    return left.value(left.Packet.data(value=40)) + right.value(right.Packet.data(value=2))\n" },
        .{ .path = "left.my", .bytes = case_left },
        .{ .path = "right.my", .bytes = case_left },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 << 20);
    defer cache.deinit();
    try expectCaseIdentity(&files);
    try agree(&files, &cache);
    entries[0].bytes = "import left\nimport right\nfunc main() -> i64:\n    return left.value(right.Packet.data(value=42))\n";
    try agree(&files, &cache);
    const rejected = try evaluate(&files, null);
    defer t.allocator.free(rejected);
    try t.expect(!std.mem.startsWith(u8, rejected, "value:"));
    entries[0].bytes = "import left\nimport right\nfunc main() -> i64:\n    return left.value(left.Packet.data(value=40)) + right.value(right.Packet.data(value=2))\n";
    entries[1].bytes = case_left["public ".len..];
    try t.expectError(error.SourceError, evaluate(&files, &cache));
    try t.expectError(error.SourceError, evaluate(&files, null));
}

//! Project loading tests for dependency graphs, bounded traversal, errors, and stable source receipts.
const std = @import("std");
const t = std.testing;
const p = @import("project.zig");
const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    reads: usize = 0,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) p.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        self.reads += 1;
        for (self.entries) |file| {
            if (!std.mem.eql(u8, file.path, path)) continue;
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        }
        return error.NotFound;
    }
    fn provider(self: *Files) p.Provider {
        return .{ .context = self, .read = read };
    }
};
const diamond = [_]File{
    .{ .path = "main.selka", .bytes =
    \\import left
    \\import right as r
    \\
    \\
    \\func main() -> i64:
    \\    return 1
    },
    .{ .path = "left.selka", .bytes = "import shared . data\n" },
    .{ .path = "right.selka", .bytes = "import shared.data\n" },
    .{ .path = "shared/data.selka", .bytes = "# shared\n" },
};
fn scenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &diamond };
    var project = p.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    try t.expectEqual(@as(usize, 4), files.reads);
    const names = [_][]const u8{ "shared.data", "left", "right", "main" };
    for (project.order.items, names) |id, name| try t.expectEqualStrings(name, project.modules.items[id].name);
    try t.expectEqual(project.modules.items[1].imports[0].target, project.modules.items[3].imports[0].target);
    const rendered = try project.render(allocator);
    defer allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "bodies/exports/types not checked") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "import right as r") != null);
    try t.expectError(error.ProjectAlreadyLoaded, project.load(files.provider(), "main", .{}));
}
// spec: PROJ-1
test "module diamond loads once in dependency order including allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn rejection(entries: []const File, options: p.Options, code: []const u8) !void {
    var files: Files = .{ .entries = entries };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", options));
    try t.expectEqualStrings(code, project.problem.?.code);
    try t.expectError(error.IncompleteProject, project.render(t.allocator));
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
    try t.expect(std.mem.indexOf(u8, message, code) != null);
}
test "module imports reject duplicate aliases duplicate imports and invalid syntax" {
    for ([_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "module other\n", .code = "E_MODULE_HEADER" },
        .{ .text = "import x.a\nimport y.a\n", .code = "E_IMPORT_ALIAS" },
        .{ .text = "import x as a\nimport x as b\n", .code = "E_DUPLICATE_IMPORT" },
        .{ .text = "import ../secret\n", .code = "E_MODULE_HEADER" },
        .{ .text = "import", .code = "E_MODULE_HEADER" },
    }) |case| try rejection(&.{.{ .path = "main.selka", .bytes = case.text }}, .{}, case.code);
}
// spec: PROJ-MODULE-NAME-FIX-1
test "a redundant module name reports an exact header deletion" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import sexpr.parser\n" },
        .{ .path = "sexpr/parser.selka", .bytes = "module parser\n" },
    } };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    try t.expectEqualStrings("E_MODULE_HEADER", project.problem.?.code);
    try t.expectEqualStrings("", project.problem.?.fix.?.text);
    try t.expectEqualStrings("sexpr.parser", project.modules.items[project.problem.?.site.module].name);
}
// spec: PROJ-2
test "module cycles report importing and related file locations" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import child\n" },
        .{ .path = "child.selka", .bytes = "import main\n" },
    } };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    const text = try project.renderProblem(t.allocator);
    defer t.allocator.free(text);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "main -> child -> main", "child.selka:1:", "main.selka:1:" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
    try rejection(&.{.{ .path = "main.selka", .bytes = "import main\n" }}, .{}, "E_IMPORT_CYCLE");
}
/// The message of the `E_IMPORT_CYCLE` that loading `entries` from `main` reports.
fn cycleMessage(entries: []const File) ![]const u8 {
    var files: Files = .{ .entries = entries };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    try t.expectEqualStrings("E_IMPORT_CYCLE", project.problem.?.code);
    return t.allocator.dupe(u8, project.problem.?.message);
}
// F-73: the message names what each module of the cycle uses from the next and says the way out.
test "an import cycle names what each module uses from the other and says the way out (F-73)" {
    const two = try cycleMessage(&.{
        .{ .path = "main.selka", .bytes = "import b\n\npublic func head(title: str) -> str:\n    return title\n\npublic func page(title: str) -> str:\n    return head(title) + b.slot(title)\n" },
        .{ .path = "b.selka", .bytes = "import main\n\npublic func slot(title: str) -> str:\n    return title\n\npublic func way(title: str) -> str:\n    return main.head(title) + slot(title)\n" },
    });
    defer t.allocator.free(two);
    try t.expectEqualStrings("main -> b -> main: `main` uses `b.slot`; `b` uses `main.head`. " ++
        "Two modules may not import each other: move what both need into a module both import", two);
}
test "an import cycle of three modules lists each edge and says the ring's way out (F-73)" {
    const ring = try cycleMessage(&.{
        .{ .path = "main.selka", .bytes = "import one\n\nfunc main() -> int:\n    return one.first(1)\n" },
        .{ .path = "one.selka", .bytes = "import two\n\npublic func first(n: int) -> int:\n    return two.second(n)\n" },
        .{ .path = "two.selka", .bytes = "import main\n\npublic func second(n: int) -> int:\n    return main.main() + n\n" },
    });
    defer t.allocator.free(ring);
    try t.expectEqualStrings("main -> one -> two -> main: `main` uses `one.first`; `one` uses `two.second`; `two` uses `main.main`. " ++
        "Modules may not import each other in a ring: move what they share into a module that each of them imports", ring);
}
test "a module that imports itself is told to remove the import (F-73)" {
    const own = try cycleMessage(&.{.{ .path = "main.selka", .bytes = "import main\n\nfunc main() -> int:\n    return 0\n" }});
    defer t.allocator.free(own);
    try t.expectEqualStrings("main -> main: `main` imports itself; remove `import main`, because a module's own declarations are in scope without an import", own);
}
test "an unused import in a cycle is named, and removing it is the way out (F-73)" {
    const unused = try cycleMessage(&.{
        .{ .path = "main.selka", .bytes = "import b\n\nfunc main() -> int:\n    return b.slot(1)\n" },
        .{ .path = "b.selka", .bytes = "import main\n\npublic func slot(n: int) -> int:\n    return n\n" },
    });
    defer t.allocator.free(unused);
    try t.expectEqualStrings("main -> b -> main: `main` uses `b.slot`; `b` imports `main` and uses nothing from it. " ++
        "Remove `import main` from `b`, which never reads it: that breaks the cycle", unused);
}
test "an import cycle lists three names at most, once each, as they are written, and counts the rest (F-73)" {
    const many = try cycleMessage(&.{
        .{ .path = "main.selka", .bytes = "import b as bee\n\nfunc main() -> int:\n    return bee.one(bee.two(bee.one(1))) + bee.three() + bee.four() + bee.five()\n" },
        .{ .path = "b.selka", .bytes = "import main\n\npublic func one(n: int) -> int:\n    return main.main() + n\n" },
    });
    defer t.allocator.free(many);
    try t.expectEqualStrings("main -> b -> main: `main` uses `bee.one`, `bee.two`, `bee.three` and 2 more; `b` uses `main.main`. " ++
        "Two modules may not import each other: move what both need into a module both import", many);
}
test "an import cycle finds a use inside a format string's hole (F-73)" {
    const hole = try cycleMessage(&.{
        .{ .path = "main.selka", .bytes = "import b\n\nfunc main() -> str:\n    return f\"{b.slot(1)}\"\n" },
        .{ .path = "b.selka", .bytes = "import main\n\npublic func slot(n: int) -> str:\n    return f\"{main.main()}\"\n" },
    });
    defer t.allocator.free(hole);
    try t.expect(std.mem.indexOf(u8, hole, "`main` uses `b.slot`; `b` uses `main.main`.") != null);
}
test "module budgets and missing files fail without a partial report" {
    try rejection(&diamond, .{ .max_modules = 2 }, "E_MODULE_LIMIT");
    try rejection(&diamond, .{ .max_imports = 1 }, "E_IMPORT_LIMIT");
    try rejection(&diamond, .{ .max_file_bytes = 4 }, "E_PROJECT_BYTES");
    try rejection(&diamond, .{ .max_total_bytes = diamond[0].bytes.len }, "E_PROJECT_BYTES");
    try rejection(&.{}, .{}, "E_MODULE_READ");
    try rejection(&.{diamond[0]}, .{}, "E_MODULE_READ");
}
test "the embedded standard library is outside the per-file budget but inside the total one" {
    const entry = "import strings\nimport math\n";
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = entry }} };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    // The per-file budget is exactly the project's own file: math.selka alone is 95,604 bytes, and strings.selka imports it.
    try project.load(files.provider(), "main", .{ .max_file_bytes = entry.len });
    try t.expect(project.counts.bytes > 95_604);
    try t.expectEqual(@as(usize, 1), files.reads);
    // The project's own file is still bounded by it, and the library still counts toward the total (STANDARD-MODULES-2).
    try rejection(&.{.{ .path = "main.selka", .bytes = entry }}, .{ .max_file_bytes = entry.len - 1 }, "E_PROJECT_BYTES");
    var small_total = p.Project.init(t.allocator);
    defer small_total.deinit();
    var again: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = entry }} };
    try t.expectError(error.SourceError, small_total.load(again.provider(), "main", .{ .max_file_bytes = entry.len, .max_total_bytes = entry.len + 1000 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", small_total.problem.?.code);
    try t.expect(std.mem.indexOf(u8, small_total.problem.?.message, "max_total_bytes budget") != null);
}
fn budgetRejection(options: p.Options, expected: []const u8) !void {
    var files: Files = .{ .entries = &diamond };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", options));
    try t.expectEqualStrings("E_PROJECT_BYTES", project.problem.?.code);
    try t.expect(std.mem.indexOf(u8, project.problem.?.message, expected) != null);
}
// spec: PROJ-BUDGET-MESSAGE-1
test "a refused source names the byte budget that ran out and the selka.json field that raises it" {
    try budgetRejection(.{ .max_total_bytes = diamond[0].bytes.len }, "max_total_bytes budget; raise budgets.max_total_bytes in selka.json");
    try budgetRejection(.{ .max_file_bytes = 4 }, "the file exceeds the 4-byte max_file_bytes budget; raise budgets.max_file_bytes in selka.json");
}
// spec: PROJ-6
// spec: PROJ-SCALE-1
test "the default project budgets admit a large module graph" {
    const options: p.Options = .{};
    try t.expectEqual(@as(usize, 16384), options.max_modules);
    try t.expectEqual(@as(usize, 262144), options.max_imports);
    try t.expectEqual(@as(usize, 4 * 1024 * 1024), options.max_file_bytes);
    // A million-line project of the generated scale shape is 35.1 MB of source.
    try t.expectEqual(@as(usize, 64 * 1024 * 1024), options.max_total_bytes);
    try t.expect(options.max_total_bytes > 35_122_778);
}
test "a hidden segment spelled with the reserved prefix reads back as the hidden path" {
    const spelled = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "__hidden_tmp.scratch", .path = ".tmp/scratch.selka" },
        .{ .name = "app.__hidden_cache.deep.more", .path = "app/.cache/deep/more.selka" },
        .{ .name = "__hidden_.x", .path = "__hidden_/x.selka" },
        .{ .name = "plain.name", .path = "plain/name.selka" },
    };
    for (spelled) |case| {
        const path = try p.modulePath(t.allocator, case.name);
        defer t.allocator.free(path);
        try t.expectEqualStrings(case.path, path);
    }
}
test "an import that spells a hidden folder is E_INTERNAL_NAME, while the same name as the entry loads the hidden file" {
    var refused: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import app.__hidden_tmp.x\n" },
        .{ .path = "app/.tmp/x.selka", .bytes = "# scratch\n" },
    } };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(refused.provider(), "main", .{}));
    try t.expectEqualStrings("E_INTERNAL_NAME", project.problem.?.code);
    try t.expect(std.mem.indexOf(u8, project.problem.?.message, "hidden folders cannot be imported") != null);
    try t.expect(std.mem.indexOf(u8, project.problem.?.message, "`app/.tmp/x.selka`") != null);
    try t.expectEqual(@as(usize, 1), refused.reads);
    var entry: Files = .{ .entries = &.{
        .{ .path = ".tmp/x.selka", .bytes = "import helper\n" },
        .{ .path = "helper.selka", .bytes = "# helper\n" },
    } };
    var loaded = p.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(entry.provider(), "__hidden_tmp.x", .{});
    try t.expectEqualStrings(".tmp/x.selka", loaded.modules.items[0].src.path);
    try t.expectEqual(@as(usize, 2), loaded.modules.items.len);
}

test "module paths exclude traversal and incomplete state cannot render" {
    for ([_][]const u8{ "", ".", "..", "a..b", "a/b", "a\\b", "/tmp/a", "a.", "a-b", "1a" }) |name| {
        try t.expect(!p.validName(name));
        try t.expectError(error.InvalidModuleName, p.modulePath(t.allocator, name));
    }
    const path = try p.modulePath(t.allocator, "shared.data");
    defer t.allocator.free(path);
    try t.expectEqualStrings("shared/data.selka", path);
    var files: Files = .{ .entries = &.{} };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.IncompleteProject, project.render(t.allocator));
    try t.expectError(error.InvalidModuleName, project.load(files.provider(), "../x", .{}));
    try t.expectError(error.IncompleteProject, project.render(t.allocator));
    try t.expectEqual(@as(usize, 0), files.reads);
}

fn cycleFailure(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = "import main\n" }} };
    var project = p.Project.init(allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        if (err == error.OutOfMemory) {
            try t.expectError(error.IncompleteProject, project.render(allocator));
            return err;
        }
        try t.expectEqual(error.SourceError, err);
        const text = try project.renderProblem(allocator);
        defer allocator.free(text);
        try t.expect(std.mem.indexOf(u8, text, "E_IMPORT_CYCLE") != null);
        return;
    };
    return error.ExpectedCycle;
}
test "module diagnostics and failed loads withstand every allocation failure" {
    try cycleFailure(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), cycleFailure, .{});
}
test "module graph reports are deterministic and source digests track body edits" {
    var files: Files = .{ .entries = &diamond };
    var first = p.Project.init(t.allocator);
    defer first.deinit();
    var second = p.Project.init(t.allocator);
    defer second.deinit();
    try first.load(files.provider(), "main", .{});
    try second.load(files.provider(), "main", .{});
    const a = try first.render(t.allocator);
    defer t.allocator.free(a);
    const b = try second.render(t.allocator);
    defer t.allocator.free(b);
    try t.expectEqualStrings(a, b);
    var changed_files = diamond;
    changed_files[3].bytes =
        \\
        \\
        \\func helper() -> i64:
        \\    return 42
    ;
    files.entries = &changed_files;
    var changed = p.Project.init(t.allocator);
    defer changed.deinit();
    try changed.load(files.provider(), "main", .{});
    try t.expectEqualSlices(u8, &first.modules.items[0].digest, &changed.modules.items[0].digest);
    try t.expect(!std.mem.eql(u8, &first.modules.items[2].digest, &changed.modules.items[2].digest));
    // The digest is `source_digest.of` the module's bytes, and the SHA-256 a receipt publishes is the standard one.
    for (first.modules.items) |module| {
        var expected: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(module.src.bytes, &expected, .{});
        try t.expectEqualSlices(u8, &@import("source_digest.zig").of(module.src.bytes), &module.digest);
        try t.expectEqualSlices(u8, &expected, &p.sha256Of(module));
        try t.expect(!std.mem.eql(u8, &expected, &module.digest));
    }
}
test "a receipt's SHA-256 is the loaded bytes' when asked for at load and the current bytes' otherwise" {
    var files: Files = .{ .entries = &diamond };
    var asked = p.Project.init(t.allocator);
    defer asked.deinit();
    var lazy = p.Project.init(t.allocator);
    defer lazy.deinit();
    try asked.load(files.provider(), "main", .{ .digests = .with_sha256 });
    try lazy.load(files.provider(), "main", .{});
    var loaded: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(asked.modules.items[0].src.bytes, &loaded, .{});
    try t.expect(asked.modules.items[0].state.sha256 != null);
    try t.expect(lazy.modules.items[0].state.sha256 == null);
    // Replace the bytes in memory after the load: the asked-for hash still names what was read, the other follows the bytes it is given.
    const replaced = try asked.arena.allocator().dupe(u8, "func other() -> i64:\n    return 1\n");
    asked.modules.items[0].src.bytes = replaced;
    lazy.modules.items[0].src.bytes = replaced;
    var current: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(replaced, &current, .{});
    try t.expectEqualSlices(u8, &loaded, &p.sha256Of(asked.modules.items[0]));
    try t.expectEqualSlices(u8, &current, &p.sha256Of(lazy.modules.items[0]));
}
test "module dependency traversal handles a long chain without recursive loading" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const entries = try allocator.alloc(File, 600);
    try fillModuleChain(allocator, entries);
    var files: Files = .{ .entries = entries };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{ .max_modules = entries.len });
    try t.expectEqual(entries.len, files.reads);
    for (project.order.items, 0..) |id, i| try t.expectEqual(entries.len - i - 1, id);
}

const report_identity: @import("source_receipt.zig").Identity = .{ .compiler_sha256 = @splat(1), .zig_version = "test", .architecture = "test", .os = "test", .abi = "test", .optimize = "test" };
fn schemaScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "data.selka", .bytes =
        \\
        \\
        \\public record Point:
        \\    x: u64
        \\    y: FixedArray[bool, 2]
        \\
        \\
        \\public enum Choice:
        \\    empty
        \\    point(value: Point)
        \\
        \\
        \\public record Identity:
        \\    value: i16
        \\
        \\func raw(x: i16) -> Identity:
        \\    return Identity(value=x)
        \\
        \\
        \\public func select(x: Choice) -> Choice:
        \\    return x
        \\
        \\
        \\record Hidden:
        \\    secret: i8
        },
    } };
    var project = p.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try @import("interfaces.zig").build(&project);
    var compilation = try @import("project_compile.zig").Compilation.init(&index);
    const text = try @import("schema.zig").render(allocator, &compilation);
    defer allocator.free(text);
    const again = try @import("schema.zig").render(allocator, &compilation);
    defer allocator.free(again);
    try t.expectEqualStrings(text, again);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("language-schema-v1", parsed.value.object.get("version").?.string);
    for ([_][]const u8{ "Hidden", "secret", "raw", "type#" }) |hidden| try t.expect(std.mem.indexOf(u8, text, hidden) == null);
    // A record publishes its value field and integer payload type.
    try t.expect(std.mem.indexOf(u8, text, "i16") != null);
    try t.expect(std.mem.indexOf(u8, text, "18446744073709551615") != null);
}
test "checked public schemas retain structure and privacy with allocation failure cleanup" {
    try schemaScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), schemaScenario, .{});
}

fn schemaReceiptScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "data.selka", .bytes =
        \\
        \\
        \\public record Item:
        \\    n: u64
        },
    } };
    var project = p.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const expected_bytes = files.entries[1].bytes.len;
    files.entries = &.{}; // Receipt/checking must consume the owned loaded snapshot.
    var index = try @import("interfaces.zig").build(&project);
    var compilation = try @import("project_compile.zig").Compilation.init(&index);
    const text = try @import("schema_report.zig").render(allocator, &compilation, report_identity);
    defer allocator.free(text);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    try t.expectEqual(@as(usize, 2), files.reads);
    try t.expectEqualStrings("schema-report-v1", parsed.value.object.get("version").?.string);
    const sources = parsed.value.object.get("source").?.object.get("sources").?.array.items;
    try t.expectEqual(@as(usize, 2), sources.len);
    try t.expectEqualStrings("data", sources[0].object.get("module").?.string);
    try t.expectEqual(@as(i64, @intCast(expected_bytes)), sources[0].object.get("bytes").?.integer);
}
test "schema receipts retain checked source dependencies with allocation failure cleanup" {
    try schemaReceiptScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), schemaReceiptScenario, .{});
}

fn fillModuleChain(allocator: std.mem.Allocator, entries: []File) !void {
    for (entries, 0..) |*file, i| {
        const name = if (i == 0) "main" else try std.fmt.allocPrint(allocator, "m{d}", .{i});
        file.path = try std.fmt.allocPrint(allocator, "{s}.selka", .{name});
        file.bytes = if (i + 1 == entries.len) try allocator.dupe(u8, "") else try std.fmt.allocPrint(allocator, "import m{d}\n", .{i + 1});
    }
}

test "project lifecycle rejects invalid budgets repeated loading and absent diagnostics" {
    var files: Files = .{ .entries = &diamond };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.NoProblem, project.renderProblem(t.allocator));
    try t.expectError(error.InvalidModuleBudget, project.load(files.provider(), "main", .{ .max_modules = 0 }));
    try t.expectEqual(@as(usize, 0), files.reads);
    try t.expectError(error.ProjectAlreadyLoaded, project.load(files.provider(), "main", .{}));
    try t.expectEqual(@as(usize, 0), files.reads);
}

// spec: SURFACE-STMT-6
test "project discovery respects newline imports exports and multiline declaration signatures" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import helper as h
        \\export h.value
        \\
        \\
        \\public func main() -> i64:
        \\    return h.value()
        },
        .{ .path = "helper.selka", .bytes =
        \\
        \\
        \\public type Number = i64
        \\
        \\
        \\const ANSWER: Number = 42
        \\
        \\
        \\public func value() -> Number:
        \\    return ANSWER
        \\
        \\
        },
    } };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    try t.expectEqual(@as(usize, 2), files.reads);
    try t.expectEqual(@as(usize, 1), project.modules.items[0].imports.len);
    try t.expectEqual(@as(usize, 1), project.modules.items[0].exports.len);
    try t.expectEqualStrings("value", project.modules.items[0].exports[0].name);
    try t.expectEqualStrings("h", project.modules.items[0].exports[0].alias.?);
    try t.expectEqual(@as(usize, 0), project.modules.items[1].exports.len);
}

/// An in-memory record store for the tests: a payload is served back under the key it was stored under.
const MemoryRecords = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMapUnmanaged([32]u8, []u8) = .empty,
    fetches: usize = 0,
    hits: usize = 0,

    fn deinit(self: *MemoryRecords) void {
        var values = self.entries.valueIterator();
        while (values.next()) |bytes| self.allocator.free(bytes.*);
        self.entries.deinit(self.allocator);
    }
    fn fetch(context: ?*anyopaque, allocator: std.mem.Allocator, key: [32]u8) ?[]u8 {
        const self: *MemoryRecords = @ptrCast(@alignCast(context.?));
        self.fetches += 1;
        const stored = self.entries.get(key) orelse return null;
        self.hits += 1;
        return allocator.dupe(u8, stored) catch null;
    }
    fn store(context: ?*anyopaque, key: [32]u8, payload: []const u8) void {
        const self: *MemoryRecords = @ptrCast(@alignCast(context.?));
        const copy = self.allocator.dupe(u8, payload) catch return;
        const found = self.entries.getOrPut(self.allocator, key) catch {
            self.allocator.free(copy);
            return;
        };
        if (found.found_existing) self.allocator.free(found.value_ptr.*);
        found.value_ptr.* = copy;
    }
    fn records(self: *MemoryRecords) @import("module_records.zig").Records {
        return .{ .context = self, .fetch = fetch, .store = store };
    }
};

fn providerWith(files: *Files, store: *MemoryRecords) p.Provider {
    var provider = files.provider();
    provider.records = store.records();
    return provider;
}

const headers = [_]File{
    .{ .path = "main.selka", .bytes =
    \\import left
    \\import right as r
    \\import shared.data
    \\
    \\func main() -> int:
    \\    return left.one() + r.two()
    },
    .{ .path = "left.selka", .bytes = "import shared.data as d\n\nexport d.Item\n\nfunc one() -> int:\n    return embed_bytes(\"table.bin\")\n" },
    .{ .path = "right.selka", .bytes = "import shared.data\n\npublic func two() -> int:\n    return 2\n" },
    .{ .path = "shared/data.selka", .bytes = "# shared\n" },
};

/// The header facts of every module in load order must match between two projects field by field.
fn expectSameHeaders(fresh: *const p.Project, warm: *const p.Project) !void {
    try t.expectEqual(fresh.modules.items.len, warm.modules.items.len);
    try t.expectEqual(fresh.counts.imports, warm.counts.imports);
    for (fresh.modules.items, warm.modules.items) |left, right| {
        try t.expectEqualStrings(left.name, right.name);
        try t.expectEqual(left.header.body_start, right.header.body_start);
        try t.expectEqual(left.header.declaration, right.header.declaration);
        try t.expectEqual(left.header.usage_scanned, right.header.usage_scanned);
        try expectSameImports(left.imports, right.imports);
        try expectSameExports(left.exports, right.exports);
        try expectSameEmbeds(left.src.embeds, right.src.embeds);
    }
}

fn expectSameImports(left: []const p.Import, right: []const p.Import) !void {
    try t.expectEqual(left.len, right.len);
    for (left, right) |a, b| {
        try t.expectEqualStrings(a.name, b.name);
        try t.expectEqualStrings(a.alias, b.alias);
        try t.expectEqual(a.span, b.span);
        try t.expectEqual(a.seen, b.seen);
    }
}

fn expectSameExports(left: []const p.Export, right: []const p.Export) !void {
    try t.expectEqual(left.len, right.len);
    for (left, right) |a, b| {
        try t.expectEqualStrings(a.name, b.name);
        try t.expectEqual(a.span, b.span);
        try t.expectEqualStrings(a.alias orelse "", b.alias orelse "");
        try t.expectEqual(a.alias == null, b.alias == null);
    }
}

fn expectSameEmbeds(left: []const @import("source.zig").Embed, right: []const @import("source.zig").Embed) !void {
    try t.expectEqual(left.len, right.len);
    for (left, right) |a, b| {
        try t.expectEqualStrings(a.path, b.path);
        try t.expectEqual(a.literal, b.literal);
        try t.expectEqual(a.text, b.text);
    }
}

test "a module header restored from its record equals the header a fresh lex produces" {
    var store: MemoryRecords = .{ .allocator = t.allocator };
    defer store.deinit();
    var cold_files: Files = .{ .entries = &headers };
    var cold = p.Project.init(t.allocator);
    defer cold.deinit();
    try cold.load(providerWith(&cold_files, &store), "main", .{});
    try t.expectEqual(@as(usize, 4), store.entries.count());
    try t.expectEqual(@as(usize, 0), store.hits);
    var warm_files: Files = .{ .entries = &headers };
    var warm = p.Project.init(t.allocator);
    defer warm.deinit();
    try warm.load(providerWith(&warm_files, &store), "main", .{});
    try t.expectEqual(@as(usize, 4), store.hits);
    try expectSameHeaders(&cold, &warm);
    try t.expectEqual(@as(usize, 1), warm.modules.items[1].src.embeds.len);
}

const malformed = [_]File{
    .{ .path = "main.selka", .bytes = "import bad\n\nfunc main() -> int:\n    return 0\n" },
    .{ .path = "bad.selka", .bytes = "import left\nimport left\n" },
    .{ .path = "left.selka", .bytes = "# left\n" },
};

/// The one diagnostic a failed load leaves on its project: its code, its site and its related site.
fn expectSameProblem(left: *const p.Project, right: *const p.Project) !void {
    const a = left.problem orelse return error.TestUnexpectedResult;
    const b = right.problem orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(a.code, b.code);
    try t.expectEqualStrings(a.message, b.message);
    try t.expectEqual(a.site, b.site);
    try t.expectEqual(a.related, b.related);
}

test "a malformed header is never recorded and reports the same diagnostic with records" {
    var plain_files: Files = .{ .entries = &malformed };
    var plain = p.Project.init(t.allocator);
    defer plain.deinit();
    try t.expectError(error.SourceError, plain.load(plain_files.provider(), "main", .{}));
    var store: MemoryRecords = .{ .allocator = t.allocator };
    defer store.deinit();
    var first_files: Files = .{ .entries = &malformed };
    var first = p.Project.init(t.allocator);
    defer first.deinit();
    try t.expectError(error.SourceError, first.load(providerWith(&first_files, &store), "main", .{}));
    try expectSameProblem(&plain, &first);
    try t.expectEqual(@as(usize, 1), store.entries.count());
    var second_files: Files = .{ .entries = &malformed };
    var second = p.Project.init(t.allocator);
    defer second.deinit();
    try t.expectError(error.SourceError, second.load(providerWith(&second_files, &store), "main", .{}));
    try expectSameProblem(&plain, &second);
    // The root's valid header is served from its record; the malformed one is never served.
    try t.expectEqual(@as(usize, 1), store.hits);
}

test "a stored header is not restored past the import budget, which reports as a fresh load does" {
    var store: MemoryRecords = .{ .allocator = t.allocator };
    defer store.deinit();
    var stored_files: Files = .{ .entries = &headers };
    var stored = p.Project.init(t.allocator);
    defer stored.deinit();
    try stored.load(providerWith(&stored_files, &store), "main", .{});
    const tight: p.Options = .{ .max_imports = 2 };
    var plain_files: Files = .{ .entries = &headers };
    var plain = p.Project.init(t.allocator);
    defer plain.deinit();
    try t.expectError(error.SourceError, plain.load(plain_files.provider(), "main", tight));
    var warm_files: Files = .{ .entries = &headers };
    var warm = p.Project.init(t.allocator);
    defer warm.deinit();
    try t.expectError(error.SourceError, warm.load(providerWith(&warm_files, &store), "main", tight));
    try expectSameProblem(&plain, &warm);
}

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
    .{ .path = "main.my", .bytes =
    \\import left
    \\import right as r
    \\
    \\
    \\func main() -> i64:
    \\    return 1
    },
    .{ .path = "left.my", .bytes = "import shared . data\n" },
    .{ .path = "right.my", .bytes = "import shared.data\n" },
    .{ .path = "shared/data.my", .bytes = "# shared\n" },
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
    }) |case| try rejection(&.{.{ .path = "main.my", .bytes = case.text }}, .{}, case.code);
}
// spec: PROJ-MODULE-NAME-FIX-1
test "a redundant module name reports an exact header deletion" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "import sexpr.parser\n" },
        .{ .path = "sexpr/parser.my", .bytes = "module parser\n" },
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
        .{ .path = "main.my", .bytes = "import child\n" },
        .{ .path = "child.my", .bytes = "import main\n" },
    } };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    const text = try project.renderProblem(t.allocator);
    defer t.allocator.free(text);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "main -> child -> main", "child.my:1:", "main.my:1:" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
    try rejection(&.{.{ .path = "main.my", .bytes = "import main\n" }}, .{}, "E_IMPORT_CYCLE");
}
test "module budgets and missing files fail without a partial report" {
    try rejection(&diamond, .{ .max_modules = 2 }, "E_MODULE_LIMIT");
    try rejection(&diamond, .{ .max_imports = 1 }, "E_IMPORT_LIMIT");
    try rejection(&diamond, .{ .max_file_bytes = 4 }, "E_PROJECT_BYTES");
    try rejection(&diamond, .{ .max_total_bytes = diamond[0].bytes.len }, "E_PROJECT_BYTES");
    try rejection(&.{}, .{}, "E_MODULE_READ");
    try rejection(&.{diamond[0]}, .{}, "E_MODULE_READ");
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
test "a refused source names the byte budget that ran out and the mylang.json field that raises it" {
    try budgetRejection(.{ .max_total_bytes = diamond[0].bytes.len }, "max_total_bytes budget; raise budgets.max_total_bytes in mylang.json");
    try budgetRejection(.{ .max_file_bytes = 4 }, "the file exceeds the 4-byte max_file_bytes budget; raise budgets.max_file_bytes in mylang.json");
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
test "module paths exclude traversal and incomplete state cannot render" {
    for ([_][]const u8{ "", ".", "..", "a..b", "a/b", "a\\b", "/tmp/a", "a.", "a-b", "1a" }) |name| {
        try t.expect(!p.validName(name));
        try t.expectError(error.InvalidModuleName, p.modulePath(t.allocator, name));
    }
    const path = try p.modulePath(t.allocator, "shared.data");
    defer t.allocator.free(path);
    try t.expectEqualStrings("shared/data.my", path);
    var files: Files = .{ .entries = &.{} };
    var project = p.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.IncompleteProject, project.render(t.allocator));
    try t.expectError(error.InvalidModuleName, project.load(files.provider(), "../x", .{}));
    try t.expectError(error.IncompleteProject, project.render(t.allocator));
    try t.expectEqual(@as(usize, 0), files.reads);
}

fn cycleFailure(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "import main\n" }} };
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
        .{ .path = "main.my", .bytes =
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "data.my", .bytes =
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
        \\public domain Identity: i16:
        \\    private func raw(x: i16) -> Identity:
        \\        return wrap[Identity](x)
        \\
        \\
        \\public func select(x: Choice) -> Choice effects():
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
    for ([_][]const u8{ "Hidden", "secret", "raw", "i16", "type#" }) |hidden| try t.expect(std.mem.indexOf(u8, text, hidden) == null);
    try t.expect(std.mem.indexOf(u8, text, "18446744073709551615") != null);
}
test "checked public schemas retain structure and privacy with allocation failure cleanup" {
    try schemaScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), schemaScenario, .{});
}

fn schemaReceiptScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes =
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "data.my", .bytes =
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
        file.path = try std.fmt.allocPrint(allocator, "{s}.my", .{name});
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
        .{ .path = "main.my", .bytes =
        \\import helper as h
        \\export h.value
        \\
        \\
        \\public func main() -> i64 effects():
        \\    return h.value()
        },
        .{ .path = "helper.my", .bytes =
        \\
        \\
        \\public type Number = i64
        \\
        \\
        \\const ANSWER: Number = 42
        \\
        \\
        \\public func value() -> Number effects():
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

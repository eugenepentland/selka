//! Python named arguments retain declaration identity, source order, and cleanup.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const project_compile = @import("project_compile.zig");

/// One in-memory project file, so a keyword-only rejection can name an
/// imported callee the way its call site spells it.
const ProjectFile = struct { path: []const u8, bytes: []const u8 };
const ProjectFiles = struct {
    entries: []const ProjectFile,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *ProjectFiles = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| if (std.mem.eql(u8, file.path, path)) {
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        };
        return error.NotFound;
    }
    fn provider(self: *ProjectFiles) graph.Provider {
        return .{ .context = self, .read = read };
    }
};

// spec: KEYWORD-ONLY-1
test "keyword-only parameters reject a positional operand with the whole call rewritten" {
    const io_module =
        \\module io
        \\
        \\
        \\public def issue(host: int, *, code: int, file: int, position: int) -> int effects():
        \\    return host + code + file + position
    ;
    const entry =
        \\module main
        \\import io
        \\
        \\
        \\def main() -> int:
        \\    return io.issue(1, 13, 0, 4)
    ;
    var files: ProjectFiles = .{ .entries = &.{
        .{ .path = "io.my", .bytes = io_module },
        .{ .path = "main.my", .bytes = entry },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_KEYWORD_ONLY", compilation.diagnostics.items.items[0].code);
    try t.expectEqualStrings("`code` is keyword-only; write `io.issue(1, code=13, file=0, position=4)`", compilation.diagnostics.items.items[0].message);
}

// spec-case: KEYWORD-ONLY-1
test "a keyword argument already written by name keeps its name in the rewritten call" {
    const text =
        \\def issue(host: int, *, code: int, file: int, position: int) -> int:
        \\    return host + code + file + position
        \\
        \\
        \\def main() -> int:
        \\    return issue(1, 3, code=2, position=4)
    ;
    var c = try language.Compilation.init(t.allocator, "keyword-only.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_KEYWORD_ONLY", c.diagnostics.items[0].code);
    try t.expectEqualStrings("`file` is keyword-only; write `issue(1, file=3, code=2, position=4)`", c.diagnostics.items[0].message);
}

// spec-case: KEYWORD-ONLY-1
test "a positional operand before the keyword-only boundary still binds positionally" {
    const text =
        \\def issue(host: int, port: int, *, code: int) -> int:
        \\    return host + port + code
        \\
        \\
        \\def main() -> int:
        \\    return issue(1, 2, code=3)
    ;
    var c = try language.Compilation.init(t.allocator, "keyword-only.my", text);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(i64, 6), (try native.run(&c)).value);
}

// spec: PYTHON-CALL-2
test "Python calls reject unknown duplicate missing and misplaced arguments and invalid defaults" {
    const header = "def add(a: int, b: int = 2) -> int:\n    return a + b\n\ndef main() -> int:\n    return ";
    for ([_][]const u8{ "add(unknown=1)", "add(a=1, a=2)", "add(1, a=2)", "add()", "add(1, 2, 3)", "add(a=1, 2)" }) |call| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, call, "\n" });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "bad.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}

// spec-case: PYTHON-CALL-2
test "Python defaults reject mutable expressions and mismatched scalar types" {
    for ([_][]const u8{
        "def bad(a: int = True):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: int = 1, b: int):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: list[int] = []):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: int = 1 + 2):\n    pass\n\ndef main() -> int:\n    return 0\n",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "default.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}

// spec: PYTHON-CALL-5
test "Python default changes invalidate checked caller reuse" {
    var cache = language.semantic_cache.Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    for ([_]struct { default: []const u8, expected: i64 }{ .{ .default = "2", .expected = 42 }, .{ .default = "3", .expected = 43 } }) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ "def add(a: int, b: int = ", case.default, ") -> int:\n    return a + b\n\ndef main() -> int:\n    return add(a=40)\n" });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "cached.my", text);
        defer c.deinit();
        try c.checkWithCache(&cache);
        try t.expectEqual(case.expected, (try native.run(&c)).value);
    }
}

// spec-case: PYTHON-CALL-1
test "Python keyword scalar and reference calls emit native source with identical side effects" {
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "test/fixtures/python-calls.my", t.allocator, .limited(8192));
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "native-calls.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 2442), (try native.run(&c)).value);
}

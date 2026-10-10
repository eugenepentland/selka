//! Installed syntax oracle behavior and explicit component selection.
const std = @import("std");
const t = std.testing;
const compiler = @import("test_options").compiler_path;

fn run(environment: *const std.process.Environ.Map, path: []const u8) !std.process.RunResult {
    return std.process.run(t.allocator, t.io, .{ .argv = &.{ compiler, "dump-syntax", path, "--diagnostics=json" }, .environ_map = environment });
}

fn release(result: std.process.RunResult) void {
    t.allocator.free(result.stdout);
    t.allocator.free(result.stderr);
}

// spec: SELFHOST-PARSER-DUMP-1
test "CLI dump-syntax returns a complete module AST without loading imports" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "syntax.my", .data = "import absent\n\npublic func value() -> int:\n    return absent.answer()\n" });
    const path = try temporary.dir.realPathFileAlloc(t.io, "syntax.my", t.allocator);
    defer t.allocator.free(path);
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_LEXER_MODE", "reference");
    try environment.put("MYLANG_PARSER_MODE", "reference");
    const result = try run(&environment, path);
    defer release(result);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try t.expectEqualStrings("", result.stderr);
    try t.expect(std.mem.startsWith(u8, result.stdout, "SLKAST01"));
    try t.expect(result.stdout.len > 16);
}

// spec-case: SELFHOST-PARSER-DUMP-1
test "CLI dump-syntax preserves parser recovery and migration fixes without partial output" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "syntax.my", .data = "func change(xs: int[]) -> Unit mutates(xs):\n    pass\n" });
    const path = try temporary.dir.realPathFileAlloc(t.io, "syntax.my", t.allocator);
    defer t.allocator.free(path);
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_LEXER_MODE", "reference");
    try environment.put("MYLANG_PARSER_MODE", "reference");
    const result = try run(&environment, path);
    defer release(result);
    try t.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try t.expectEqualStrings("", result.stdout);
    try t.expect(std.mem.indexOf(u8, result.stderr, "E_REMOVED_SPELLING") != null);
    try t.expect(std.mem.indexOf(u8, result.stderr, "\"fix\"") != null);
    try t.expect(std.mem.indexOf(u8, result.stderr, "mut ") != null);
}

// spec-case: SELFHOST-PARSER-DUMP-1
test "CLI dump-syntax refuses a missing shadow package after a successful reference run" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "syntax.my", .data = "func value() -> int:\n    return 42\n" });
    const path = try temporary.dir.realPathFileAlloc(t.io, "syntax.my", t.allocator);
    defer t.allocator.free(path);
    const absent = try std.fmt.allocPrint(t.allocator, "{s}.missing", .{path});
    defer t.allocator.free(absent);
    var environment = try std.process.Environ.createMap(t.environ, t.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_LEXER_MODE", "reference");
    try environment.put("MYLANG_PARSER_MODE", "reference");
    const expected = try run(&environment, path);
    defer release(expected);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, expected.term);
    try environment.put("MYLANG_PARSER_MODE", "shadow");
    try environment.put("MYLANG_COMPONENT_DIR", absent);
    const actual = try run(&environment, path);
    defer release(actual);
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, actual.term);
    try t.expectEqualStrings("", actual.stdout);
    try t.expect(std.mem.indexOf(u8, actual.stderr, "ComponentMissing") != null);
}

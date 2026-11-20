//! A test file whose module imports `main` runs (FR19). The runner gives a test file that declares no `main` a stub one, so the
//! file can be checked and built as a program, and the stub's `main` used to meet the file's own `import main`: a refusal
//! (`E_IMPORT_ALIAS`) at a line the file does not have, for `selka test main_test.selka`, for every root a directory run cannot
//! check together, and under `SELKA_TEST_CHILDREN=1`. A `main` the author wrote beside `import main` is still refused.
const std = @import("std");
const testing = std.testing;
const paths = @import("test_paths");

const main_source = "public func double(n: int) -> int:\n    return n * 2\n\n\nfunc main() -> int:\n    return double(21)\n";
const test_source = "import main\n\n\npublic func test_double() -> bool:\n    return main.double(2) == 4\n";
const own_main_test_source = test_source ++ "\n\nfunc main() -> int:\n    return 0\n";

/// Run `selka ARGS` in `directory` with `children` set or not, and answer the exit status and what it printed.
fn run(directory: std.Io.Dir, arguments: []const []const u8, children: bool) !struct { term: std.process.Child.Term, stdout: []u8, stderr: []u8 } {
    var environment = try paths.privateEnvironment(testing.allocator);
    defer environment.deinit();
    if (children) try environment.put("SELKA_TEST_CHILDREN", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, paths.corePath());
    try argv.appendSlice(testing.allocator, arguments);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = directory }, .environ_map = &environment });
    return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr };
}

// spec: TEST-STUB-1
test "a test file that imports main runs alone, in a directory run and with a child per root (FR19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main_test.selka", .data = test_source });
    const cases = [_]struct { arguments: []const []const u8, children: bool }{
        .{ .arguments = &.{ "test", "main_test.selka", "--force" }, .children = false },
        .{ .arguments = &.{ "test", ".", "--force" }, .children = false },
        .{ .arguments = &.{ "test", ".", "--force" }, .children = true },
    };
    for (cases) |case| {
        const ran = try run(temporary.dir, case.arguments, case.children);
        defer testing.allocator.free(ran.stdout);
        defer testing.allocator.free(ran.stderr);
        errdefer std.debug.print("stdout:\n{s}\nstderr:\n{s}\n", .{ ran.stdout, ran.stderr });
        try testing.expect(std.mem.indexOf(u8, ran.stdout, "passed main_test::test_double\n") != null);
        try testing.expect(std.mem.indexOf(u8, ran.stderr, "E_IMPORT_ALIAS") == null);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    }
}

// spec: TEST-STUB-1
test "a main the author wrote beside import main is still refused (FR19)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main_test.selka", .data = own_main_test_source });
    const ran = try run(temporary.dir, &.{ "test", "main_test.selka", "--force" }, false);
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "error[E_IMPORT_ALIAS]: declaration conflicts with an import alias") != null);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "main_test.selka:8:6") != null);
    try testing.expect(ran.term != .exited or ran.term.exited != 0);
}

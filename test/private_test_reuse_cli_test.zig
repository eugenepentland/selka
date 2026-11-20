//! FX10: a test file that calls a private function of the module it tests runs, and passes or fails on its merits, on every
//! run in one work directory, not only on the first (`test/fixtures/private-test-reuse`).
//!
//! A directory run checks its roots together through a generated entry that imports each of them. That entry used to count as
//! an importer of the test file, so the shared check refused the test file's call of `lib.page` and the root ran alone, where it
//! passed. Its checked body was stored, and the next run served it into the shared check, which then passed without resolving
//! the call again but flagged `page` private to its unit; the test's program could not be emitted, the test was reported
//! `unsupported` and the run exited 0, whatever `page` now did. The generated entry no longer counts as an importer, and a
//! test file's checked body and its module's engine record are keyed by the module it tests, so a body checked with that
//! module's private declarations is never served where another module imports the test file.
const std = @import("std");
const testing = std.testing;
const paths = @import("test_paths");

const lib_source = @embedFile("fixtures/private-test-reuse/lib.selka");
const lib_test_source = @embedFile("fixtures/private-test-reuse/lib_test.selka");
const main_source = @embedFile("fixtures/private-test-reuse/main.selka");

/// The summary line of a run in which both tests ran and passed.
const both_passed = "2 passed, 0 cached, 0 failed, 0 skipped\n";

/// What one command printed and how it ended.
const Ran = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: Ran) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

/// The three-file program in a temporary directory `p`, run from that directory's parent, so every command shares one work
/// directory, `.selka-cache` beside `p`.
const Program = struct {
    temporary: testing.TmpDir,
    environment: std.process.Environ.Map,

    fn init() !Program {
        var program: Program = .{ .temporary = testing.tmpDir(.{}), .environment = try paths.privateEnvironment(testing.allocator) };
        errdefer program.deinit();
        try program.temporary.dir.createDir(testing.io, "p", .default_dir);
        try program.write("p/lib.selka", lib_source);
        try program.write("p/lib_test.selka", lib_test_source);
        try program.write("p/main.selka", main_source);
        return program;
    }

    fn deinit(self: *Program) void {
        self.environment.deinit();
        self.temporary.cleanup();
    }

    fn write(self: *Program, path: []const u8, bytes: []const u8) !void {
        try self.temporary.dir.writeFile(testing.io, .{ .sub_path = path, .data = bytes });
    }

    /// Replace the one occurrence of `old` in `p/lib.selka` with `new`.
    fn edit(self: *Program, old: []const u8, new: []const u8) !void {
        const bytes = try self.temporary.dir.readFileAlloc(testing.io, "p/lib.selka", testing.allocator, .limited(1 << 20));
        defer testing.allocator.free(bytes);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, old));
        const edited = try std.mem.replaceOwned(u8, testing.allocator, bytes, old, new);
        defer testing.allocator.free(edited);
        try self.write("p/lib.selka", edited);
    }

    fn run(self: *Program, arguments: []const []const u8) !Ran {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.append(testing.allocator, paths.corePath());
        try argv.appendSlice(testing.allocator, arguments);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temporary.dir }, .environ_map = &self.environment });
        return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr };
    }

    /// Run `selka test p` with `extra` and expect both tests to have run and passed: nothing unsupported, exit 0.
    fn expectBothPass(self: *Program, extra: []const []const u8) !void {
        var arguments: std.ArrayList([]const u8) = .empty;
        defer arguments.deinit(testing.allocator);
        try arguments.appendSlice(testing.allocator, &.{ "test", "p" });
        try arguments.appendSlice(testing.allocator, extra);
        const ran = try self.run(arguments.items);
        defer ran.deinit();
        errdefer std.debug.print("selka test p: {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ ran.term, ran.stdout, ran.stderr });
        try testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
        try testing.expect(std.mem.indexOf(u8, ran.stdout, "passed lib_test::test_the_private_page\n") != null);
        try testing.expect(std.mem.endsWith(u8, ran.stdout, both_passed));
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    }
};

// spec-case: TEST-PRIVATE-ACCESS-1
test "FX10 a test of a private function runs after an edit of its module, and fails when the function breaks" {
    var program = try Program.init();
    defer program.deinit();
    try program.expectBothPass(&.{});
    try program.edit("out.body + \"!\"", "out.body + \"?\"");
    try program.expectBothPass(&.{});
    // An edit that breaks `page`: the test of the private function runs and fails, and so does the run.
    try program.edit("answer(200, body)", "answer(201, body)");
    const ran = try program.run(&.{ "test", "p" });
    defer ran.deinit();
    try testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
    try testing.expect(std.mem.indexOf(u8, ran.stdout, "failed lib_test::test_the_private_page: R_ASSERT: the status") != null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
}

// spec-case: TEST-PRIVATE-ACCESS-1
test "FX10 a test of a private function runs on a second forced run in the same work directory" {
    var program = try Program.init();
    defer program.deinit();
    try program.expectBothPass(&.{"--force"});
    try program.expectBothPass(&.{"--force"});
}

// spec-case: TEST-PRIVATE-ACCESS-1
test "FX10 a test of a private function runs after a build of the program between two runs that reuse no test result" {
    var program = try Program.init();
    defer program.deinit();
    // A variable that can change what the toolchain does makes its identity unprovable, so no test record is reused: the
    // state of a compiler on a machine whose system libraries are not on the reviewed list (`tool_identity.safeEnvironment`).
    try program.environment.put("GLIBC_TUNABLES", "glibc.malloc.perturb=0");
    try program.expectBothPass(&.{});
    const built = try program.run(&.{ "build", "p/main.selka", "-o", "served" });
    defer built.deinit();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try program.expectBothPass(&.{});
}

// spec-case: TEST-PRIVATE-ACCESS-1
test "FX10 a directory check refuses a test file's private call once another module imports the test file, as a fresh check does" {
    var program = try Program.init();
    defer program.deinit();
    const first = try program.run(&.{ "check", "p" });
    defer first.deinit();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    // Imported by a real module, the test file is a library and sees only `lib`'s public surface. The engine's record of the
    // test file and its stored bodies were made under the access, so before FX10 this check was served them and passed.
    try program.write("p/user.selka", "import lib_test\n\n\npublic func user() -> bool:\n    return lib_test.test_the_public_function()\n");
    const second = try program.run(&.{ "check", "p" });
    defer second.deinit();
    const refused = std.mem.indexOf(u8, second.stderr, "error[E_PRIVATE_SYMBOL]") != null or std.mem.indexOf(u8, second.stdout, "error[E_PRIVATE_SYMBOL]") != null;
    try testing.expect(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, second.term);
}

// spec-case: TEST-PRIVATE-ACCESS-1
test "FX10 a directory check refuses a test file's sealed-record build once another module imports the test file" {
    var program = try Program.init();
    defer program.deinit();
    // The sealed records' test grant is the same fact (`sealed_rules.zig` asks `testsModule`): only `seal` and its test file
    // build a `Count`, and only while nothing but a generated entry imports the test file.
    try program.write("p/seal.selka", "@sealed\npublic record Count:\n    value: int = 0\n\npublic func count(n: int) -> Count:\n    return Count(value=n)\n");
    try program.write("p/seal_test.selka", "import seal\n\npublic func test_builds_a_count() -> bool:\n    const made = seal.Count(value=2)\n    return made.value == 2\n");
    const first = try program.run(&.{ "check", "p" });
    defer first.deinit();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    // Before FX10 this check was served the body and the engine record made under the grant, and passed.
    try program.write("p/seal_user.selka", "import seal_test\n\npublic func user() -> bool:\n    return seal_test.test_builds_a_count()\n");
    const second = try program.run(&.{ "check", "p" });
    defer second.deinit();
    const refused = std.mem.indexOf(u8, second.stderr, "error[E_SEALED_RECORD]") != null or std.mem.indexOf(u8, second.stdout, "error[E_SEALED_RECORD]") != null;
    try testing.expect(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, second.term);
}

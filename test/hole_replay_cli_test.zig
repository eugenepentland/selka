//! A debug build keeps a typed hole (`todo[T]()`) as a trap; `check` refuses it with `E_TYPED_HOLE` (lane H, D-G-6). The check
//! summary a debug build publishes must never stand in the body that holds the hole, or a later `check` answers `ok` over a
//! skeleton nobody has filled. These tests run the commands in both orders, in one work directory and in a new one beside a shared
//! compiler store (the store is where the defect was first seen), and after an edit beside the hole.
const std = @import("std");
const testing = std.testing;

/// What one command printed, and how it ended.
const Outcome = struct {
    code: u8,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

const main_text =
    \\import helper
    \\import caller
    \\
    \\
    \\func main() -> int:
    \\    return caller.twice(1)
    \\
    \\
    \\public func test_twice() -> bool:
    \\    return caller.twice(2) == 4
    \\
    \\
    \\public func test_reaches() -> bool:
    \\    return helper.pending() == 1
    \\
;
const helper_text =
    \\public func pending() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func fine(x: int) -> int:
    \\    return x * 2
    \\
;
const caller_text =
    \\import helper
    \\
    \\
    \\public func twice(x: int) -> int:
    \\    return helper.fine(x)
    \\
;

/// A project with one typed hole in `helper`, in a temporary directory, with the shared compiler store beside it.
const Sandbox = struct {
    temporary: testing.TmpDir,
    store: []u8,

    fn init() !Sandbox {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = main_text });
        try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = helper_text });
        try temporary.dir.writeFile(testing.io, .{ .sub_path = "caller.selka", .data = caller_text });
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        defer testing.allocator.free(root);
        return .{ .temporary = temporary, .store = try std.fs.path.join(testing.allocator, &.{ root, "store" }) };
    }

    fn deinit(self: *Sandbox) void {
        testing.allocator.free(self.store);
        self.temporary.cleanup();
    }

    /// Replace a source file of the project.
    fn write(self: *Sandbox, name: []const u8, text: []const u8) !void {
        try self.temporary.dir.writeFile(testing.io, .{ .sub_path = name, .data = text });
    }

    /// `selka ARGS... --cache-dir WORK`, with the shared compiler store on (`shared`) or off.
    fn run(self: *Sandbox, args: []const []const u8, work: []const u8, shared: bool) !Outcome {
        const paths_module = @import("test_paths");
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths_module.corePath(), testing.allocator);
        defer testing.allocator.free(compiler);
        var environment = try paths_module.privateEnvironment(testing.allocator);
        defer environment.deinit();
        if (shared) try environment.put("SELKA_COMPILER_SHARED_CACHE", self.store);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.append(testing.allocator, compiler);
        try argv.appendSlice(testing.allocator, args);
        try argv.appendSlice(testing.allocator, &.{ "--cache-dir", work });
        const result = try std.process.run(testing.allocator, testing.io, .{
            .argv = argv.items,
            .cwd = .{ .dir = self.temporary.dir },
            .environ_map = &environment,
        });
        return .{ .code = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .stdout = result.stdout, .stderr = result.stderr };
    }

    /// A debug build of the project.
    fn build(self: *Sandbox, work: []const u8, shared: bool) !Outcome {
        return self.run(&.{ "build", "main.selka", "-o", "program" }, work, shared);
    }

    /// `check` of the project.
    fn check(self: *Sandbox, work: []const u8, shared: bool) !Outcome {
        return self.run(&.{ "check", "main.selka" }, work, shared);
    }
};

/// Whether `check` refused the hole: exit status 1 and `E_TYPED_HOLE` in its report.
fn refusedHole(outcome: Outcome) bool {
    return outcome.code == 1 and std.mem.indexOf(u8, outcome.stderr, "helper.selka:2:12: error[E_TYPED_HOLE]") != null;
}

test "check refuses a hole in a new work directory after a debug build published to a shared store" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const refused = try sandbox.check("cache-first", true);
    defer refused.deinit();
    const built = try sandbox.build("cache-first", true);
    defer built.deinit();
    const again = try sandbox.check("cache-second", true);
    defer again.deinit();
    try testing.expect(refusedHole(refused));
    try testing.expectEqual(@as(u8, 0), built.code);
    try testing.expect(refusedHole(again));
}

test "check refuses a hole in the work directory a debug build used, with the shared store off" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const built = try sandbox.build("cache", false);
    defer built.deinit();
    const checked = try sandbox.check("cache", false);
    defer checked.deinit();
    const rebuilt = try sandbox.build("cache", false);
    defer rebuilt.deinit();
    const checked_again = try sandbox.check("cache", false);
    defer checked_again.deinit();
    try testing.expectEqual(@as(u8, 0), built.code);
    try testing.expect(refusedHole(checked));
    try testing.expectEqual(@as(u8, 0), rebuilt.code);
    try testing.expect(refusedHole(checked_again));
}

test "a check that refused a hole leaves the next build compiling it as a trap" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const refused = try sandbox.check("cache", true);
    defer refused.deinit();
    const built = try sandbox.build("cache", true);
    defer built.deinit();
    const reaching = try sandbox.run(&.{ "test", "main.selka", "--filter", "reaches" }, "cache", true);
    defer reaching.deinit();
    const passing = try sandbox.run(&.{ "test", "main.selka", "--filter", "twice" }, "cache", true);
    defer passing.deinit();
    const refused_again = try sandbox.check("cache", true);
    defer refused_again.deinit();
    try testing.expect(refusedHole(refused));
    try testing.expectEqual(@as(u8, 0), built.code);
    try testing.expectEqual(@as(u8, 1), reaching.code);
    try testing.expect(std.mem.indexOf(u8, reaching.stdout, "R_TYPED_HOLE") != null);
    try testing.expectEqual(@as(u8, 0), passing.code);
    try testing.expect(refusedHole(refused_again));
}

test "check refuses a hole that a test run kept as a trap, in a new work directory" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const tested = try sandbox.run(&.{ "test", "main.selka", "--filter", "twice" }, "cache-first", true);
    defer tested.deinit();
    const checked = try sandbox.check("cache-second", true);
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), tested.code);
    try testing.expect(refusedHole(checked));
}

test "an edit beside a kept hole does not let check accept it, and filling the hole does" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const built = try sandbox.build("cache", true);
    defer built.deinit();
    try sandbox.write("caller.selka", caller_text ++ "\n\npublic func extra() -> int:\n    return 7\n");
    const edited = try sandbox.check("cache", true);
    defer edited.deinit();
    try sandbox.write("helper.selka", "public func pending() -> int:\n    return 3\n\n\npublic func fine(x: int) -> int:\n    return x * 2\n");
    const filled = try sandbox.check("cache", true);
    defer filled.deinit();
    const rebuilt = try sandbox.build("cache", true);
    defer rebuilt.deinit();
    try sandbox.write("helper.selka", helper_text);
    const restored = try sandbox.check("cache", true);
    defer restored.deinit();
    try testing.expectEqual(@as(u8, 0), built.code);
    try testing.expect(refusedHole(edited));
    try testing.expectEqual(@as(u8, 0), filled.code);
    try testing.expectEqual(@as(u8, 0), rebuilt.code);
    try testing.expect(refusedHole(restored));
}

/// `main.selka` with a `main` that calls the hole.
const main_reaching_text =
    \\import helper
    \\
    \\
    \\func main() -> int:
    \\    return helper.pending()
    \\
;

test "a release build refuses a hole main reaches that a debug build kept, and builds past one it does not, from the same work directory" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    const built = try sandbox.build("cache", true);
    defer built.deinit();
    // `main` calls `caller.twice`, which never reaches `helper.pending`: the release build does not need it.
    const past = try sandbox.run(&.{ "build", "main.selka", "-o", "program-release", "--release" }, "cache", true);
    defer past.deinit();
    // The same project with a `main` that calls the hole: the debug build's records must not stand in for it.
    try sandbox.write("main.selka", main_reaching_text);
    const trapped = try sandbox.build("cache", true);
    defer trapped.deinit();
    const release = try sandbox.run(&.{ "build", "main.selka", "-o", "program-release", "--release" }, "cache", true);
    defer release.deinit();
    try testing.expectEqual(@as(u8, 0), built.code);
    try testing.expectEqual(@as(u8, 0), past.code);
    try testing.expectEqual(@as(u8, 0), trapped.code);
    try testing.expect(refusedHole(release));
}

/// A library whose imports are skeletons: three holes in `stub_a`, two in `stub_b`, and one hole and one type error of its own.
const own_text =
    \\import stub_a
    \\import stub_b
    \\
    \\
    \\public func mine() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func wrong(x: int) -> str:
    \\    return x
    \\
;
const stub_a_text =
    \\public func one() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func two() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func three() -> bool:
    \\    return todo[bool]()
    \\
;
const stub_b_text =
    \\public func one() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func two() -> str:
    \\    return todo[str]()
    \\
;

/// A sandbox holding the skeleton library `own.selka` beside its two stub modules.
fn skeleton() !Sandbox {
    var sandbox = try Sandbox.init();
    errdefer sandbox.deinit();
    try sandbox.write("own.selka", own_text);
    try sandbox.write("stub_a.selka", stub_a_text);
    try sandbox.write("stub_b.selka", stub_b_text);
    return sandbox;
}

test "check-module reports the holes of its file in full and those of other modules as one counted line" {
    var sandbox = try skeleton();
    defer sandbox.deinit();
    const outcome = try sandbox.run(&.{ "check-module", "own.selka" }, "cache", false);
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.code);
    // Its own hole and its own error are printed in full, and the five stub holes are not.
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "own.selka:6:12: error[E_TYPED_HOLE]") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "own.selka:10:5: error[E_TYPE]") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "stub_a.selka") == null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "stub_b.selka") == null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "note: 5 typed holes in 2 other modules (check DIR lists them)\n") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "E_TYPED_HOLE"));
}

test "check-module of a file with no hole of its own says only how many the other modules hold" {
    var sandbox = try skeleton();
    defer sandbox.deinit();
    try sandbox.write("own.selka", "import stub_b\n\n\npublic func fine() -> int:\n    return stub_b.one() + 1\n");
    const outcome = try sandbox.run(&.{ "check-module", "own.selka" }, "cache", false);
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.code);
    try testing.expectEqualStrings("note: 2 typed holes in 1 other module (check DIR lists them)\n", outcome.stderr);
}

test "check of the file, check of the directory and the json form keep listing every hole" {
    var sandbox = try skeleton();
    defer sandbox.deinit();
    const file = try sandbox.run(&.{ "check", "own.selka" }, "cache", false);
    defer file.deinit();
    const directory = try sandbox.run(&.{ "check", "." }, "cache", false);
    defer directory.deinit();
    const json = try sandbox.run(&.{ "check-module", "own.selka", "--diagnostics=json" }, "cache", false);
    defer json.deinit();
    for ([_]Outcome{ file, directory, json }) |outcome| {
        try testing.expectEqual(@as(u8, 1), outcome.code);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "stub_a.selka") != null);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "stub_b.selka") != null);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "other module") == null);
    }
}

test "a typed hole hides neither an unread capability parameter nor a warning of the same module" {
    var sandbox = try Sandbox.init();
    defer sandbox.deinit();
    try sandbox.write("own.selka",
        \\import math
        \\
        \\
        \\func hole() -> int:
        \\    return todo[int]()
        \\
        \\
        \\func case_unused(out: Stream, fs: Filesystem) -> bool:
        \\    return fs.exists("x")
        \\
    );
    const library = try sandbox.run(&.{ "check", "own.selka", "--warnings" }, "cache", false);
    defer library.deinit();
    const module = try sandbox.run(&.{ "check-module", "own.selka", "--warnings" }, "cache", false);
    defer module.deinit();
    for ([_]Outcome{ library, module }) |outcome| {
        try testing.expectEqual(@as(u8, 1), outcome.code);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "own.selka:5:12: error[E_TYPED_HOLE]") != null);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "own.selka:8:18: error[E_UNUSED_CAPABILITY]") != null);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "warning[W_UNUSED_IMPORT]") != null);
    }
}

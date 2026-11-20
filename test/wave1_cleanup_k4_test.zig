//! Definite assignment, capability repairs, and managed path cleanup.
const std = @import("std");
const testing = std.testing;
const check_line = @import("check_line.zig");
/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// One source file of a temporary project.
const File = struct { path: []const u8, data: []const u8 };

/// A temporary project directory and the absolute paths a command needs.
const Project = struct {
    temp: testing.TmpDir,
    root: [:0]const u8,
    cache: []const u8,

    fn init(files: []const File) !Project {
        var temp = testing.tmpDir(.{});
        errdefer temp.cleanup();
        for (files) |file| {
            if (std.fs.path.dirname(file.path)) |directory| try temp.dir.createDirPath(testing.io, directory);
            try temp.dir.writeFile(testing.io, .{ .sub_path = file.path, .data = file.data });
        }
        const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/.cache", .{root});
        return .{ .temp = temp, .root = root, .cache = cache };
    }

    fn deinit(self: *Project) void {
        testing.allocator.free(self.cache);
        testing.allocator.free(self.root);
        self.temp.cleanup();
    }

    /// The absolute path of one file or directory inside the project.
    fn path(self: *const Project, relative: []const u8) ![]const u8 {
        return std.fs.path.join(testing.allocator, &.{ self.root, relative });
    }

    /// One file's current bytes.
    fn read(self: *const Project, relative: []const u8) ![]const u8 {
        return self.temp.dir.readFileAlloc(testing.io, relative, testing.allocator, .limited(1 << 20));
    }

    /// Run `selka COMMAND TARGET ARGS...` from the project directory with this
    /// project's cache, so the paths `fix` prints are project-relative.
    fn run(self: *const Project, command: []const u8, target: []const u8, args: []const []const u8) !Outcome {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
        defer testing.allocator.free(compiler);
        const absolute = try self.path(target);
        defer testing.allocator.free(absolute);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler, command, absolute });
        try argv.appendSlice(testing.allocator, args);
        if (!std.mem.eql(u8, command, "test")) try argv.append(testing.allocator, self.cache);
        var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
        defer environment.deinit();
        try @import("test_paths").privateStores(&environment);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir }, .environ_map = &environment });
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .stdout = result.stdout, .stderr = result.stderr };
    }
};

/// A finished command: exit status and both streams, owned by the testing allocator.
const Outcome = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

// spec: DECL-CONST-DEFINITE-1
test "cleanup k4 const assignments merge continuing branches" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func choose(flag: bool) -> int:
        \\    const result: int
        \\    if flag:
        \\        result = 3
        \\    else:
        \\        result = 4
        \\    return result
        \\func main() -> int:
        \\    assert choose(True) == 3
        \\    assert choose(False) == 4
        \\    return 0
    }});
    defer project.deinit();
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(@as(u8, 0), result.status);
}

fn checked(bytes: []const u8) !Outcome {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = bytes }});
    defer project.deinit();
    return project.run("check", "main.selka", &.{"--diagnostics=json"});
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 const read before assignment names missing path" {
    const result = try checked("func f(flag: bool) -> int:\n    const result: int\n    if flag:\n        result = 1\n    return result\n");
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_UNBOUND") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "control-flow path") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 const cannot assign twice after partial branch" {
    const result = try checked("func f(flag: bool) -> int:\n    const result: int\n    if flag:\n        result = 1\n    result = 2\n    return result\n");
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 initialized const and compound assignment remain immutable" {
    const initialized = try checked("func f() -> int:\n    const result = 1\n    result = 2\n    return result\n");
    defer initialized.deinit();
    try testing.expectEqual(@as(u8, 1), initialized.status);
    try testing.expect(std.mem.indexOf(u8, initialized.stderr, "E_IMMUTABLE") != null);
    const compound = try checked("func f() -> int:\n    const result: int\n    result += 2\n    return result\n");
    defer compound.deinit();
    try testing.expectEqual(@as(u8, 1), compound.status);
    try testing.expect(std.mem.indexOf(u8, compound.stderr, "E_IMMUTABLE") != null);
}

// spec: CAPABILITY-UNUSED-1
test "cleanup k4 unused capability offers certain underscore rename" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = "func callback(out: Stream, value: int) -> int:\n    return value + 1\nfunc main() -> int:\n    return 0\n" }});
    defer project.deinit();
    const before = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer before.deinit();
    try testing.expectEqual(@as(u8, 1), before.status);
    try testing.expect(std.mem.indexOf(u8, before.stderr, "E_UNUSED_CAPABILITY") != null);
    try testing.expect(std.mem.indexOf(u8, before.stderr, "_out") != null);
    try testing.expect(std.mem.indexOf(u8, before.stderr, "edits") != null);
    const fix = try project.run("fix", "main.selka", &.{});
    defer fix.deinit();
    try testing.expectEqual(@as(u8, 0), fix.status);
    const bytes = try project.read("main.selka");
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "callback(_out: Stream") != null);
    const after = try project.run("check", "main.selka", &.{});
    defer after.deinit();
    try check_line.expectPassed(after.stderr);
    try testing.expectEqual(@as(u8, 0), after.status);
}

// spec-case: CAPABILITY-UNUSED-1
test "cleanup k4 underscore capability keeps callback type" {
    const result = try checked("func callback(_out: Stream, value: int) -> int:\n    return value + 1\nfunc apply(out: Stream, action: func(Stream, int) -> int) -> int:\n    return action(out, 4)\nfunc main(out: Stream) -> int:\n    return apply(out, callback)\n");
    defer result.deinit();
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(@as(u8, 0), result.status);
}

// spec: DECL-MANAGED-EARLY-RETURN-1
test "cleanup k4 managed uninitialized locals clean early return under checked ownership" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func text(flag: bool, early: bool) -> str:
        \\    const value: str
        \\    if early:
        \\        return "early" + str(flag)
        \\    if flag:
        \\        value = "yes" + str(flag)
        \\    else:
        \\        value = "no" + str(flag)
        \\    return value
        \\func numbers(flag: bool, early: bool) -> int[]:
        \\    const value: int[]
        \\    if early:
        \\        return [0]
        \\    if flag:
        \\        value = [1, 2]
        \\    else:
        \\        value = [3]
        \\    return value
        \\func main() -> int:
        \\    assert text(True, True) == "earlyTrue"
        \\    assert text(True, False) == "yesTrue"
        \\    assert text(False, False) == "noFalse"
        \\    assert len(numbers(True, True)) == 1
        \\    assert len(numbers(True, False)) == 2
        \\    assert numbers(False, False)[0] == 3
        \\    return 0
    }});
    defer project.deinit();
    const normal = try project.run("run", "main.selka", &.{"--verify-facts"});
    defer normal.deinit();
    try testing.expectEqualStrings("", normal.stderr);
    try testing.expectEqual(@as(u8, 0), normal.status);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 loop backedges and continue reject repeated const assignment" {
    const backedge = try checked("func f(flag: bool) -> int:\n    const result: int\n    while flag:\n        result = 1\n    return 0\n");
    defer backedge.deinit();
    try testing.expectEqual(@as(u8, 1), backedge.status);
    try testing.expect(std.mem.indexOf(u8, backedge.stderr, "E_IMMUTABLE") != null);
    const continuing = try checked("func f(flag: bool) -> int:\n    const result: int\n    while flag:\n        result = 1\n        continue\n    return 0\n");
    defer continuing.deinit();
    try testing.expectEqual(@as(u8, 1), continuing.status);
    try testing.expect(std.mem.indexOf(u8, continuing.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 assigning const then breaking permits one assignment" {
    const result = try checked("func f(flag: bool) -> int:\n    const result: int\n    while True:\n        if flag:\n            result = 1\n        else:\n            result = 2\n        break\n    return result\n");
    defer result.deinit();
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(@as(u8, 0), result.status);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 loop exit possible assignment prevents later const write" {
    const result = try checked("func f(flag: bool) -> int:\n    const result: int\n    while flag:\n        result = 1\n        break\n    result = 2\n    return result\n");
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 generic definite assignment matches concrete branches" {
    const valid = try checked("func choose[T](flag: bool, first: T, second: T) -> T from first, second:\n    const result: T\n    if flag:\n        result = first\n    else:\n        result = second\n    return result\nfunc main() -> int:\n    return choose(True, 3, 4)\n");
    defer valid.deinit();
    try testing.expectEqualStrings("", valid.stderr);
    try testing.expectEqual(@as(u8, 0), valid.status);
    const repeated = try checked("func choose[T](flag: bool, first: T, second: T) -> T:\n    const result: T\n    if flag:\n        result = first\n    result = second\n    return result\nfunc main() -> int:\n    return choose(True, 3, 4)\n");
    defer repeated.deinit();
    try testing.expectEqual(@as(u8, 1), repeated.status);
    try testing.expect(std.mem.indexOf(u8, repeated.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
// The helper is bounded `integer`: a `const` assigned inside `while True` and returned after the loop is refused for `str`
// today (`E_SINGLE_OWNER_MOVED`, also in a non-generic function), so the body is judged for scalars only (W3 step 2).
test "cleanup k4 generic loops honor breaks and reject continuing assignment" {
    const valid = try checked("func choose[T: integer](flag: bool, first: T, second: T) -> T:\n    const result: T\n    while True:\n        if flag:\n            result = first\n        else:\n            result = second\n        break\n    return result\nfunc main() -> int:\n    return choose(True, 3, 4)\n");
    defer valid.deinit();
    try testing.expectEqualStrings("", valid.stderr);
    try testing.expectEqual(@as(u8, 0), valid.status);
    const repeated = try checked("func choose[T](flag: bool, first: T) -> T:\n    const result: T\n    while flag:\n        result = first\n        continue\n    return first\nfunc main() -> int:\n    return choose(True, 3)\n");
    defer repeated.deinit();
    try testing.expectEqual(@as(u8, 1), repeated.status);
    try testing.expect(std.mem.indexOf(u8, repeated.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 nested inner break cannot hide outer continue reassignment" {
    const result = try checked("func f(flag: bool) -> int:\n    const result: int\n    while flag:\n        while True:\n            result = 1\n            break\n        continue\n    return 0\n");
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 native generic invocation specializes const declaration" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func choose[T](flag: bool, first: T, second: T) -> T:
        \\    const result: T
        \\    while True:
        \\        if flag:
        \\            result = first
        \\        else:
        \\            result = second
        \\        break
        \\    return result
        \\func main() -> int:
        \\    assert choose(True, 3, 4) == 3
        \\    assert choose(False, 3, 4) == 4
        \\    return 0
    }});
    defer project.deinit();
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(@as(u8, 0), result.status);
}

fn repairCollision(bytes: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = bytes }});
    defer project.deinit();
    const fix = try project.run("fix", "main.selka", &.{});
    defer fix.deinit();
    try testing.expectEqual(@as(u8, 0), fix.status);
    const repaired = try project.read("main.selka");
    defer testing.allocator.free(repaired);
    try testing.expect(std.mem.indexOf(u8, repaired, "callback(_out_1: Stream") != null);
    const expected = try std.mem.replaceOwned(u8, testing.allocator, bytes, "callback(out:", "callback(_out_1:");
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, repaired);
    const check = try project.run("check", "main.selka", &.{});
    defer check.deinit();
    try check_line.expectPassed(check.stderr);
    try testing.expectEqual(@as(u8, 0), check.status);
}

// spec-case: CAPABILITY-UNUSED-1
test "cleanup k4 capability repair avoids parameter local global and import collisions" {
    try repairCollision("func callback(out: Stream, _out: int) -> int:\n    return _out\nfunc main() -> int:\n    return 0\n");
    try repairCollision("func callback(out: Stream) -> int:\n    const _out = 3\n    return _out\nfunc main() -> int:\n    return 0\n");
    try repairCollision("func _out() -> int:\n    return 3\nfunc callback(out: Stream) -> int:\n    return _out()\nfunc main() -> int:\n    return 0\n");
    try repairCollision("import strings as _out\nfunc callback(out: Stream) -> int:\n    return len(_out.digits())\nfunc main() -> int:\n    return 0\n");
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 match ignores returned arms and unions possible assignment" {
    const valid = try checked("enum Choice:\n    first\n    second\nfunc f(choice: Choice) -> int:\n    const result: int\n    match choice:\n        case first:\n            result = 1\n        case second:\n            return 2\n    return result\n");
    defer valid.deinit();
    try testing.expectEqualStrings("", valid.stderr);
    try testing.expectEqual(@as(u8, 0), valid.status);
    const repeated = try checked("enum Choice:\n    first\n    second\nfunc f(choice: Choice) -> int:\n    const result: int\n    match choice:\n        case first:\n            result = 1\n        case second:\n            pass\n    result = 2\n    return result\n");
    defer repeated.deinit();
    try testing.expectEqual(@as(u8, 1), repeated.status);
    try testing.expect(std.mem.indexOf(u8, repeated.stderr, "E_IMMUTABLE") != null);
}

// spec-case: DECL-CONST-DEFINITE-1
test "cleanup k4 range and collection loops reject repeated outer const initialization" {
    const range = try checked("func f() -> int:\n    const result: int\n    for index in range(0, 3):\n        result = index\n    return 0\n");
    defer range.deinit();
    try testing.expectEqual(@as(u8, 1), range.status);
    try testing.expect(std.mem.indexOf(u8, range.stderr, "E_IMMUTABLE") != null);
    const collection = try checked("func f() -> int:\n    const result: int\n    for item in [1, 2]:\n        result = item\n    return 0\n");
    defer collection.deinit();
    try testing.expectEqual(@as(u8, 1), collection.status);
    try testing.expect(std.mem.indexOf(u8, collection.stderr, "E_IMMUTABLE") != null);
}

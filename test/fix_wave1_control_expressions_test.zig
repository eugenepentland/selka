//! Retirement repairs preserve control flow and evaluation order through the CLI.
const std = @import("std");
const testing = std.testing;
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

fn migrate(project: *Project, path: []const u8, diagnostic_code: []const u8) !void {
    try migrateExpected(project, path, diagnostic_code, null);
}
fn migrateExpected(project: *Project, path: []const u8, diagnostic_code: []const u8, expected: ?[]const u8) !void {
    const before = try project.read(path);
    defer testing.allocator.free(before);
    const preview = try project.run("fix", path, &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const found_code = std.mem.indexOf(u8, preview.stdout, diagnostic_code) != null or std.mem.indexOf(u8, preview.stderr, diagnostic_code) != null;
    if (!found_code) std.debug.print("preview output: {s}\n{s}\n", .{ preview.stdout, preview.stderr });
    try testing.expect(found_code);
    const unchanged = try project.read(path);
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(before, unchanged);
    const fix = try project.run("fix", path, &.{});
    defer fix.deinit();
    if (fix.status != 0) std.debug.print("fix output: {s}\n{s}\n", .{ fix.stdout, fix.stderr });
    try testing.expectEqual(@as(u8, 0), fix.status);
    if (expected) |source| {
        const actual = try project.read(path);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(source, actual);
    }
    const check = try project.run("check", path, &.{});
    defer check.deinit();
    if (check.status != 0) std.debug.print("check output: {s}\n{s}\n", .{ check.stdout, check.stderr });
    try testing.expectEqual(@as(u8, 0), check.status);
    const again = try project.run("fix", path, &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}
// spec: CONTROL-EXPRESSIONS-1
test "wave1 control expressions preview direct inferred managed and contextual repairs" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func choose(flag: bool) -> int[]:
        \\    return [42] if flag else [0]
        \\func main() -> int:
        \\    const values = if True then (choose(True) if True else choose(False)) else choose(False)
        \\    mut small: u8 = 1 if True else 2
        \\    small = if False then 0 else 1
        \\    return values[0] * int(small)
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions match repairs evaluate target once and preserve fail" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\enum Choice:
        \\    first(value: int)
        \\    other
        \\func target(mut calls: int[]) -> Choice:
        \\    calls.append(42)
        \\    return Choice.first(value=calls[0])
        \\func main() -> int:
        \\    mut calls: int[] = []
        \\    const number = match target(mut calls):
        \\        case first(value=value):
        \\            if value > 0:
        \\                yield value
        \\            else:
        \\                yield 0
        \\        case other:
        \\            yield 0
        \\    assert len(calls) == 1
        \\    return number
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_MATCH_EXPRESSION_REMOVED");
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions certain first argument hoist runs selected arm only" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func trap() -> int:
        \\    mut zero = 0
        \\    return 1 // zero
        \\func identity(value: int) -> int:
        \\    return value
        \\func main() -> int:
        \\    return identity(42 if True else trap())
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions uncertain short circuit repeated and preceding read have no fix" {
    const sources = [_][]const u8{
        "func main() -> int:\n    mut flag = False\n    if flag and (True if flag else False):\n        return 42\n    return 0\n",
        "func main() -> int:\n    mut flag = False\n    while True if flag else False:\n        return 42\n    return 0\n",
        "func main() -> int:\n    mut value = 1\n    return value + (42 if True else 0)\n",
    };
    for (sources) |input| {
        var project = try Project.init(&.{.{ .path = "main.selka", .data = input }});
        defer project.deinit();
        const preview = try project.run("fix", "main.selka", &.{"--check"});
        defer preview.deinit();
        try testing.expectEqual(@as(u8, 1), preview.status);
        const fix = try project.run("fix", "main.selka", &.{});
        defer fix.deinit();
        try testing.expectEqual(@as(u8, 1), fix.status);
        const after = try project.read("main.selka");
        defer testing.allocator.free(after);
        try testing.expectEqualStrings(input, after);
    }
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions generic repair remains symbolic for two types and named calls" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func choose[T](flag: bool, first: T, second: T) -> T:
        \\    const selected = first if flag else second
        \\    return selected
        \\func main() -> int:
        \\    const number = choose(flag=True, first=42, second=0)
        \\    const word = choose[str](False, "bad", "ok")
        \\    if word == "ok":
        \\        return number
        \\    return 0
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const source_after = try project.read("main.selka");
    defer testing.allocator.free(source_after);
    try testing.expect(std.mem.indexOf(u8, source_after, "mut selected: T") != null);
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions imported helper repairs agree across independent roots" {
    const shared =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\public func choose[T](flag: bool, first: T, second: T) -> T:
        \\    const selected = first if flag else second
        \\    return selected
        \\public func number() -> int:
        \\    return 1 + (41 if True else 0)
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "padding.selka", .data = "public func number() -> int:\n    return 42\n" },
        .{ .path = "first.selka", .data = "import padding\nimport shared\nfunc main() -> int:\n    return shared.choose(True, shared.number() + padding.number() - 42, 0)\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const text = shared.choose[str](False, \"bad\", \"ok\")\n    if text == \"ok\":\n        return 42\n    return 0\n" },
    };
    var first = try Project.init(&files);
    defer first.deinit();
    const fixed_first = try first.run("fix", "first.selka", &.{});
    defer fixed_first.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_first.status);
    const first_bytes = try first.read("shared.selka");
    defer testing.allocator.free(first_bytes);
    var second = try Project.init(&files);
    defer second.deinit();
    const fixed_second = try second.run("fix", "second.selka", &.{});
    defer fixed_second.deinit();
    try testing.expectEqual(@as(u8, 0), fixed_second.status);
    const second_bytes = try second.read("shared.selka");
    defer testing.allocator.free(second_bytes);
    // Control-expression repairs and generated names agree. The body is judged at its declaration for every kind of
    // argument (W3 step 2), so the scalar root writes the same repair of the borrowed choices as the managed root.
    try testing.expect(std.mem.indexOf(u8, second_bytes, "selected = copy(first)") != null);
    try testing.expect(std.mem.indexOf(u8, second_bytes, "selected = copy(second)") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, second_bytes, "= copy("));
    try testing.expectEqualStrings(first_bytes, second_bytes);
    // Visiting the managed root in the first project converges to exactly the
    // independent managed repair without introducing root-specific names.
    const managed = try first.run("fix", "second.selka", &.{});
    defer managed.deinit();
    try testing.expectEqual(@as(u8, 0), managed.status);
    const converged = try first.read("shared.selka");
    defer testing.allocator.free(converged);
    try testing.expectEqualStrings(second_bytes, converged);
    for ([_][]const u8{ "first.selka", "second.selka" }) |entry| {
        const ran = try first.run("run", entry, &.{});
        defer ran.deinit();
        try testing.expectEqual(@as(u8, 42), ran.status);
    }
    const clean = try first.run("check", "second.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions nested match selection retains failure and managed result handling" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\enum Error:
        \\    failed
        \\enum Choice:
        \\    yes
        \\    no
        \\func selected(flag: bool) -> int[] fails Error:
        \\    const values = match Choice.yes:
        \\        case yes:
        \\            yield [42] if flag else [0]
        \\        case no:
        \\            fail Error.failed
        \\    return values
        \\func main() -> int:
        \\    match selected(True):
        \\        case Ok(values):
        \\            return values[0]
        \\        case Err(_):
        \\            return 0
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.indexOf(u8, after, "fail Error.failed") != null);
    try testing.expect(std.mem.indexOf(u8, after, "yield ") == null);
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-EXPRESSIONS-1
test "wave1 control expressions certain interpolation and operand hoists remain idempotent" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func main() -> int:
        \\    const label = f"selected {42 if True else 0}"
        \\    const size = 1 + (41 if True else 0)
        \\    if label == "selected 42":
        \\        return size
        \\    return 0
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec: CONTROL-COMPOSITION-1
test "wave1 control expressions compose with lambda conditional and match extraction" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\enum Choice:
        \\    first(value: int)
        \\    other
        \\func apply(callback: func(int) -> int) -> int:
        \\    return callback(42)
        \\func main() -> int:
        \\    const selected = apply(lambda value: value if value > 0 else 0)
        \\    const callback: func(int) -> int = lambda value: match Choice.first(value=value):
        \\        case first(value=number):
        \\            yield number
        \\        case other:
        \\            yield 0
        \\    return callback(selected)
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_LAMBDA_REMOVED");
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: CONTROL-COMPOSITION-1
test "wave1 control expressions compose with repeated generic gather output selection" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func choose[T](values: T[], fallback: T, flag: bool) -> T[]:
        \\    return [value if flag else fallback for value in values]
        \\func main() -> int:
        \\    const values = choose([42, 0], 0, True)
        \\    const words = choose[str](["bad"], "ok", False)
        \\    const mapped = [if value > 0 then value else 0 for value in values]
        \\    if words[0] == "ok" and mapped[1] == 0:
        \\        return mapped[0]
        \\    return 0
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_COMPREHENSION_REMOVED");
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.indexOf(u8, after, ": T\n") != null);
    try testing.expect(std.mem.indexOf(u8, after, ", own gather_value_") != null);
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}

test "O4 generic comprehension results move into wrappers and owning calls while readers borrow" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional O4 retired comprehension migration before-source
        \\func my_take[T](own values: T[]) -> int:
        \\    return len(values)
        \\func wrapped[T](values: T[]) -> T[]?:
        \\    return Some([value for value in values])
        \\func main() -> int:
        \\    match wrapped[int]([1]):
        \\        case Some(values):
        \\            assert values[0] == 1
        \\        case None:
        \\            return 0
        \\    match wrapped[str](["text"]):
        \\        case Some(words):
        \\            assert words[0] == "text"
        \\        case None:
        \\            return 0
        \\    const first = my_take[int]([value for value in [1, 2]])
        \\    const second = my_take[str]([copy(value) for value in ["a", "b"]])
        \\    const read = len([value for value in [3, 4]])
        \\    return first + second + read
    }});
    defer project.deinit();
    try migrate(&project, "main.selka", "E_COMPREHENSION_REMOVED");
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.indexOf(u8, after, "Some(own gather_result_") != null);
    try testing.expect(std.mem.indexOf(u8, after, "my_take[int](own gather_result_") != null);
    try testing.expect(std.mem.indexOf(u8, after, "my_take[str](own gather_result_") != null);
    try testing.expect(std.mem.indexOf(u8, after, "len(own gather_result_") == null);
    const result = try project.run("run", "main.selka", &.{"--verify-facts"});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 6), result.status);
}
// spec-case: CONTROL-COMPOSITION-1
test "wave1 control expressions deferred gather retains outer short circuit nofix" {
    const original =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\func main() -> int:
        \\    mut flag = False
        \\    if flag and len([value if True else 0 for value in [42]]) > 0:
        \\        return 42
        \\    return 0
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    for ([_][]const []const u8{ &.{"--check"}, &.{} }) |arguments| {
        const result = try project.run("fix", "main.selka", arguments);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.status);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_COMPREHENSION_REMOVED") != null);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_CONDITIONAL_EXPRESSION_REMOVED") == null);
        const after = try project.read("main.selka");
        defer testing.allocator.free(after);
        try testing.expectEqualStrings(original, after);
    }
}
// spec-case: CONTROL-COMPOSITION-1
test "wave1 control expressions deferred owners preserve conditional type diagnostics" {
    const inputs = [_][]const u8{
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        "func main() -> int:\n    const callback: func(int) -> int = lambda value: value if True else \"bad\"\n    return callback(42)\n",
        // migrate-embedded: skip original deferred-owner conditional type error witness
        "func main() -> int:\n    const values = [value if True else \"bad\" for value in [42]]\n    return values[0]\n",
    };
    for (inputs) |original| {
        var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
        defer project.deinit();
        const result = try project.run("fix", "main.selka", &.{});
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.status);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "error[E_TYPE]") != null);
        const after = try project.read("main.selka");
        defer testing.allocator.free(after);
        try testing.expectEqualStrings(original, after);
    }
}
// spec-case: CONTROL-COMPOSITION-1
test "wave1 control expressions imported nominal repairs use original module type names" {
    const shared =
        // migrate-embedded: skip intentional CONTROL-EXPRESSIONS-1 pre-removal source
        \\public record Box:
        \\    value: int
        \\public func answer() -> int:
        \\    const box = Box(value=42) if True else Box(value=0)
        \\    return box.value
    ;
    var project = try Project.init(&.{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "main.selka", .data = "import shared\nfunc main() -> int:\n    return shared.answer()\n" },
    });
    defer project.deinit();
    try migrate(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED");
    const after = try project.read("shared.selka");
    defer testing.allocator.free(after);
    try testing.expect(std.mem.indexOf(u8, after, "mut box: Box\n") != null);
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}

// spec-case: CONTROL-EXPRESSIONS-1
// spec-case: FIX-MIGRATION-1
test "wave1 control conditional exact source contract" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    return 42 if True else 0
        \\
    ;
    const expected =
        \\func main() -> int:
        \\    if True:
        \\        return 42
        \\    else:
        \\        return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    try migrateExpected(&project, "main.selka", "E_CONDITIONAL_EXPRESSION_REMOVED", expected);
}

// spec-case: CONTROL-EXPRESSIONS-1
// spec-case: FIX-MIGRATION-1
test "wave1 control match exact source contract" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\enum Choice:
        \\    yes
        \\    no
        \\func main() -> int:
        \\    return match Choice.yes:
        \\        case yes:
        \\            yield 42
        \\        case no:
        \\            yield 0
        \\
    ;
    const expected =
        \\enum Choice:
        \\    yes
        \\    no
        \\func main() -> int:
        \\    match Choice.yes:
        \\        case yes:
        \\            return 42
        \\        case no:
        \\            return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    try migrateExpected(&project, "main.selka", "E_MATCH_EXPRESSION_REMOVED", expected);
}

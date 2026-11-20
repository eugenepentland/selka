//! CLI migration contract for scalar-domain retirement.
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
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir } });
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

fn migrate(files: []const File, target: []const u8, expected: []const File) !void {
    var project = try Project.init(files);
    defer project.deinit();
    const preview = try project.run("fix", target, &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "E_DOMAIN_REMOVED") != null);
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
    const fixed = try project.run("fix", target, &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    for (expected) |file| {
        const actual = try project.read(file.path);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(file.data, actual);
    }
    const check = try project.run("check", target, &.{});
    defer check.deinit();
    try testing.expectEqual(@as(u8, 0), check.status);
    const again = try project.run("fix", target, &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
// spec-case: FIX-MIGRATION-CAPTURE-1
test "wave1 domain CLI migrates member collisions and representation access" {
    try migrate(&.{.{ .path = "main.selka", .data = original }}, "main.selka", &.{.{ .path = "main.selka", .data = replacement }});
}

const original =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\domain First: int:
    \\    func make(n: int) -> First:
    \\        return wrap[First](n)
    \\    func amount(item: First) -> int:
    \\        return unwrap(item)
    \\domain Second: int:
    \\    func make(n: int) -> Second:
    \\        return wrap[Second](n)
    \\    func amount(item: Second) -> int:
    \\        return unwrap(item)
    \\func main() -> int:
    \\    return First.amount(First.make(2)) + Second.amount(Second.make(3))
    \\
;
const replacement =
    // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
    \\record First:
    \\    value: int
    \\func First_make(n: int) -> First:
    \\    return First(value=n)
    \\func First_amount(item: First) -> int:
    \\    return (item).value
    \\record Second:
    \\    value: int
    \\func Second_make(n: int) -> Second:
    \\    return Second(value=n)
    \\func Second_amount(item: Second) -> int:
    \\    return (item).value
    \\func main() -> int:
    \\    return First_amount(First_make(2)) + Second_amount(Second_make(3))
    \\
;

fn migrateProject(files: []const File, expected_fragments: []const File) !void {
    return migrateTarget(files, expected_fragments, "main.selka");
}

/// `migrateProject` for a project whose repairs include a warning's, which a file run applies only with `--warnings`.
fn migrateProjectWarnings(files: []const File, expected_fragments: []const File) !void {
    return migrateTargetWith(files, expected_fragments, "main.selka", true);
}

fn migrateTarget(files: []const File, expected_fragments: []const File, target: []const u8) !void {
    return migrateTargetWith(files, expected_fragments, target, false);
}

fn migrateTargetWith(files: []const File, expected_fragments: []const File, target: []const u8, warnings: bool) !void {
    var project = try Project.init(files);
    defer project.deinit();
    const apply: []const []const u8 = if (warnings) &.{"--warnings"} else &.{};
    const list: []const []const u8 = if (warnings) &.{ "--check", "--warnings" } else &.{"--check"};
    const preview = try project.run("fix", target, list);
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const before = try project.read(files[0].path);
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(files[0].data, before);
    const fixed = try project.run("fix", target, apply);
    defer fixed.deinit();
    if (fixed.status != 0) std.debug.print("domain migration failed: {s}{s}\n", .{ fixed.stdout, fixed.stderr });
    try testing.expectEqual(@as(u8, 0), fixed.status);
    for (expected_fragments) |fragment| {
        const actual = try project.read(fragment.path);
        defer testing.allocator.free(actual);
        try testing.expect(std.mem.indexOf(u8, actual, fragment.data) != null);
    }
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", target, list);
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI migrates imported inferred named operations" {
    try migrateProjectWarnings(&.{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import operations
            \\import data
            \\func main() -> int:
            \\    return operations.evaluate(data.Counter.make(9))
        },
        .{
            .path = "operations.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import contracts
            \\public func evaluate[T: contracts.Scored](item: T) -> int effects():
            \\    return T.score(item)
        },
        .{
            .path = "contracts.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public constraint Scored[P] = copy + op(score(item: P) -> int effects())
        },
        .{
            .path = "data.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public domain Counter: int:
            \\    func make(n: int) -> Counter effects():
            \\        return wrap[Counter](n)
            \\    func score(item: Counter) -> int effects():
            \\        return unwrap(item)
        },
    }, &.{
        .{ .path = "main.selka", .data = "operations.evaluate(data.make(9), domain_op_T_score=data.score)" },
        .{ .path = "operations.selka", .data = "domain_op_T_score: func(T) -> int" },
        .{ .path = "operations.selka", .data = "return domain_op_T_score(item)" },
        .{ .path = "data.selka", .data = "public record Counter:" },
        .{ .path = "data.selka", .data = "public func score" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI preserves invariants and avoids function and local captures" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\@invariant(unwrap(self) >= 0)
        \\domain Count: int:
        \\    @requires(n >= 0)
        \\    func make(n: int) -> Count:
        \\        return wrap[Count](n)
        \\    func number(item: Count) -> int:
        \\        return unwrap(item)
        \\func make(n: int) -> int:
        \\    return n
        \\func main() -> int:
        \\    const number = 2
        \\    return Count.number(Count.make(number)) + make(1)
    }}, &.{
        .{ .path = "main.selka", .data = "@invariant((self).value >= 0)" },
        .{ .path = "main.selka", .data = "@requires(n >= 0)\nfunc Count_make" },
        .{ .path = "main.selka", .data = "func Count_number" },
        .{ .path = "main.selka", .data = "return Count_number(Count_make(number)) + make(1)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI passes explicit and inferred generic forwarding callbacks" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain Count: int:
        \\    func make(n: int) -> Count effects():
        \\        return wrap[Count](n)
        \\    func score(item: Count) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\func forward[U: copy + op(score(item: U) -> int effects())](item: U) -> int effects():
        \\    return evaluate[U](item) + evaluate(item)
        \\func main() -> int:
        \\    return forward[Count](Count.make(3))
    }}, &.{
        .{ .path = "main.selka", .data = "evaluate[U](item, domain_op_T_score=domain_op_U_score) + evaluate(item, domain_op_T_score=domain_op_U_score)" },
        .{ .path = "main.selka", .data = "forward[Count](make(3), domain_op_U_score=score)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI preserves CRLF comments and nondefault suite indentation" {
    try migrateProject(&.{.{ .path = "main.selka", .data = "domain Count: int: # count\r\n  pass # empty\r\nfunc main() -> int:\r\n  return 0\r\n" }}, &.{
        .{ .path = "main.selka", .data = "record Count: # count\r\n  value: int\r\n# empty\r\n" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-CAPTURE-1
test "wave1 domain CLI reserves own parameters loop bindings and generated stems" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain A_B: int:
        \\    func C(C: int) -> A_B:
        \\        return wrap[A_B](C)
        \\domain A: int:
        \\    func B_C(n: int) -> A:
        \\        return wrap[A](n)
        \\func B_C(n: int) -> int:
        \\    return n
        \\func main() -> int:
        \\    for C in range(1):
        \\        _ = A_B.C(C)
        \\    _ = A.B_C(2)
        \\    return B_C(3)
    }}, &.{
        .{ .path = "main.selka", .data = "func A_B_C(C: int)" },
        .{ .path = "main.selka", .data = "func A_B_C_2(n: int)" },
        .{ .path = "main.selka", .data = "_ = A_B_C(C)" },
        .{ .path = "main.selka", .data = "_ = A_B_C_2(2)" },
    });
}

// spec: FIX-DIRECTORY-ROUNDS-1
// spec-case: DOMAIN-REMOVED-1
test "wave1 domain CLI fixes all independent directory roots before shared metadata changes" {
    try migrateTarget(&.{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import api
            \\import data
            \\func main() -> int:
            \\    const Counter_score = 1
            \\    const domain_op_T_score = 2
            \\    return api.evaluate(data.Counter.make(9)) + Counter_score + domain_op_T_score
        },
        .{
            .path = "other.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import api
            \\import data
            \\func main() -> int:
            \\    return api.evaluate[data.Counter](data.Counter.make(8))
        },
        .{
            .path = "api.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
            \\    return T.score(item)
        },
        .{
            .path = "data.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public func score(value: int) -> int effects():
            \\    return value
            \\public domain Counter: int:
            \\    func make(n: int) -> Counter effects():
            \\        return wrap[Counter](n)
            \\    func score(item: Counter) -> int effects():
            \\        return unwrap(item)
        },
    }, &.{
        .{ .path = "main.selka", .data = "api.evaluate(data.make(9), domain_op_T_score=data.Counter_score)" },
        .{ .path = "other.selka", .data = "api.evaluate[data.Counter](data.make(8), domain_op_T_score=data.Counter_score)" },
        .{ .path = "api.selka", .data = "domain_op_T_score: func(T) -> int" },
        .{ .path = "data.selka", .data = "public func Counter_score" },
    }, ".");
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
// spec: FIX-DOMAIN-FORWARDING-1
test "wave1 domain CLI substitutes named subjects inside callback collection types" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint First[P] = copy + op(first(items: P[][]) -> P effects())
        \\domain Count: int:
        \\    func make(n: int) -> Count effects():
        \\        return wrap[Count](n)
        \\    func first(items: Count[][]) -> Count effects():
        \\        return items[0][0]
        \\domain Other: int:
        \\    func make(n: int) -> Other effects():
        \\        return wrap[Other](n)
        \\    func first(items: Other[][]) -> Other effects():
        \\        return items[0][0]
        \\type CountAlias = Count
        \\func evaluate[T: First](items: T[][]) -> T effects():
        \\    return T.first(items)
        \\func forward[Q: First](items: Q[][]) -> Q effects():
        \\    return evaluate(items=items)
        \\func same[T: First](items: T[][]) -> T effects():
        \\    return evaluate(items)
        \\func main() -> int:
        \\    const item: CountAlias = Count.make(4)
        \\    _ = forward([[item]])
        \\    _ = forward([[Other.make(5)]])
        \\    _ = same([[item]])
        \\    _ = same([[Other.make(6)]])
        \\    return 0
    }}, &.{
        .{ .path = "main.selka", .data = "domain_op_T_first: func(T[][]) -> T" },
        .{ .path = "main.selka", .data = "forward([[item]], domain_op_Q_first=Count_first)" },
        .{ .path = "main.selka", .data = "forward([[Other_make(5)]], domain_op_Q_first=Other_first)" },
        .{ .path = "main.selka", .data = "evaluate(items, domain_op_T_first=domain_op_T_first)" },
        .{ .path = "main.selka", .data = "evaluate(items=items, domain_op_T_first=domain_op_Q_first)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-CAPTURE-1
test "wave1 domain CLI does not capture existing builtin calls" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain Count: int:
        \\    func len(item: Count) -> int effects():
        \\        return unwrap(item)
        \\    func make(n: int) -> Count effects():
        \\        return wrap[Count](n)
        \\func main() -> int:
        \\    const items = [1, 2]
        \\    return len(items) + Count.len(Count.make(3))
    }}, &.{
        .{ .path = "main.selka", .data = "func Count_len(item: Count)" },
        .{ .path = "main.selka", .data = "return len(items) + Count_len(make(3))" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI preserves trailing commas comments defaults and named arguments" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain Count: int:
        \\    func make(n: int) -> Count effects():
        \\        return wrap[Count](n)
        \\    func score(item: Count) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: copy + op(score(item: T) -> int effects())](
        \\    item: T,
        \\    n: int = 0, # keep signature
        \\) -> int effects():
        \\    return T.score(item) + n
        \\func main() -> int:
        \\    return evaluate(
        \\        item=Count.make(3), # keep call
        \\    )
    }}, &.{
        .{ .path = "main.selka", .data = "named domain_op_T_score: func(T) -> int" },
        .{ .path = "main.selka", .data = "domain_op_T_score=score)" },
        .{ .path = "main.selka", .data = "# keep signature" },
        .{ .path = "main.selka", .data = "# keep call" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI preserves grouped wrap unwrap and generic calls" {
    try migrateTarget(&.{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\domain D: int:
            \\    func make(n: int) -> D effects():
            \\        return ((wrap[D]( # preserve wrap argument
            \\            n)))
            \\    func score(item: D) -> int effects():
            \\        return ((unwrap( # preserve unwrap argument
            \\            (item))))
            \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
            \\    return (T.score(item))
            \\func main() -> int:
            \\    return ((evaluate[D]((D.make(1)))))
        },
    }, &.{
        .{ .path = "main.selka", .data = "# preserve unwrap argument" },
        .{ .path = "main.selka", .data = "# preserve wrap argument" },
        .{ .path = "main.selka", .data = "((evaluate[D]((make(1)), domain_op_T_score=score)))" },
    }, "main.selka");
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI coalesces duplicate named requirements within limits" {
    try migrateTarget(&.{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
            \\func f[T: A + B](x: T) -> int effects():
            \\    return 0
            \\func main() -> int:
            \\    return 0
        },
    }, &.{
        .{ .path = "main.selka", .data = "func f[T: copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)]" },
    }, "main.selka");
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI defers inferred callbacks until mutation repairs" {
    try migrateTarget(&.{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\domain D: int:
            \\    func make(n: int) -> D effects():
            \\        return wrap[D](n)
            \\    func score(item: D) -> int effects():
            \\        return unwrap(item)
            \\
            \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
            \\    return T.score(item)
            \\
            \\func main() -> int:
            \\    const item = D.make(1)
            \\    mut text = [1]
            \\    text.append(2)
            \\    return evaluate(item) + len(text)
        },
    }, &.{
        .{ .path = "main.selka", .data = "evaluate(item, domain_op_T_score=score)" },
    }, "main.selka");
}

// spec-case: FIX-DIRECTORY-ROUNDS-1
// spec-case: DOMAIN-REMOVED-1
// spec: FIX-DIRECTORY-DOMAIN-PHASE-1
test "wave1 domain CLI defers shared declarations across independent roots" {
    const files = [_]File{
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import api
            \\import data
            \\func main() -> int:
            \\    return api.evaluate[data.D](data.D.make(1))
        },
        .{
            .path = "other.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import api
            \\import data
            \\func main() -> int:
            \\    item = data.D.make(1)
            \\    mut text = [1]
            \\    text.append(2)
            \\    return api.evaluate(item) + len(text)
        },
        .{
            .path = "data.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public domain D: int:
            \\    func make(n: int) -> D effects():
            \\        return wrap[D](n)
            \\    func score(item: D) -> int effects():
            \\        return unwrap(item)
        },
        .{
            .path = "api.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
            \\    return T.score(item)
        },
    };
    var initial = try Project.init(&files);
    defer initial.deinit();
    const parsed = try initial.run("check", "other.selka", &.{"--diagnostics=json"});
    defer parsed.deinit();
    try testing.expectEqual(@as(u8, 1), parsed.status);
    try testing.expect(std.mem.indexOf(u8, parsed.stderr, "E_EFFECTS_REMOVED") != null);
    try testing.expect(std.mem.indexOf(u8, parsed.stderr, "E_DOMAIN_REMOVED") == null);
    var modern_files: [files.len]File = undefined;
    for (files, 0..) |file, i| modern_files[i] = .{ .path = file.path, .data = try withoutEffects(file.data) };
    defer for (modern_files) |file| testing.allocator.free(file.data);
    var modern = try Project.init(&modern_files);
    defer modern.deinit();
    const modern_parsed = try modern.run("check", "other.selka", &.{"--diagnostics=json"});
    defer modern_parsed.deinit();
    try testing.expectEqual(@as(u8, 1), modern_parsed.status);
    try testing.expect(std.mem.indexOf(u8, modern_parsed.stderr, "E_BINDING_DECLARATION") != null);
    try testing.expect(std.mem.indexOf(u8, modern_parsed.stderr, "E_DOMAIN_REMOVED") == null);
    try migrateTarget(&files, &.{
        .{ .path = "other.selka", .data = "api.evaluate(item, domain_op_T_score=data.score)" },
    }, ".");
}

// spec-case: DOMAIN-REMOVED-1
test "wave1 domain CLI preserves operation metadata when inferred type is unknown" {
    const text =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: int:
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\func main() -> int:
        \\    return evaluate(unknown)
    ;
    try effectErasureBarrier(text, "E_UNKNOWN_NAME");
}

// spec-case: DOMAIN-REMOVED-1
test "wave1 domain CLI coalesces repeated identical named operations" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[P] = copy + op(score(item: P) -> int effects())
        \\constraint B[Q] = copy + op(score(other: Q) -> int effects())
        \\domain D: int:
        \\    func make(n: int) -> D effects():
        \\        return wrap[D](n)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: A + B](item: T) -> int effects():
        \\    return T.score(item)
        \\func main() -> int:
        \\    return evaluate[D](D.make(1))
    }}, &.{
        .{ .path = "main.selka", .data = "named domain_op_T_score: func(T) -> int)" },
        .{ .path = "main.selka", .data = "evaluate[D](make(1), domain_op_T_score=score)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-DIRECTORY-DOMAIN-PHASE-1
test "wave1 domain CLI preserves dependent sites for unsupported domain indentation" {
    const text = "domain D: int:\n\tfunc make(n: int) -> D effects():\n\t\treturn wrap[D](n)\nfunc main() -> int:\n    _ = D.make(1)\n    return 0\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const result = try project.run("fix", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_INDENTATION") != null);
    const actual = try project.read("main.selka");
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(text, actual);
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-DIRECTORY-DOMAIN-PHASE-1
test "wave1 domain CLI withholds dependent edits for an uncertain domain suite" {
    const text =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: int:
        \\    func make(n: int) -> D effects():
        \\        _ = """preserve literal contents"""
        \\        return wrap[D](n)
        \\func main() -> int:
        \\    _ = D.make(1)
        \\    return 0
    ;
    try effectErasureBarrier(text, "no certain automatic repair");
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI preserves already removed codec spellings with spaced brackets" {
    const text =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\record Wire:
        \\    n: int
        \\result Decoded:
        \\    ok: D,
        \\    err: int
        \\domain D: int:
        \\    codec Wire:
        \\        decode: from_wire,
        \\        encode: to_wire
        \\    func from_wire(item: Wire) -> Decoded effects():
        \\        return Ok(wrap[D](item.n))
        \\    func to_wire(item: D) -> Wire effects():
        \\        return Wire(n=unwrap(item))
        \\func main() -> int:
        \\    match codec_decode[D ](Wire(n=3)):
        \\        case ok(value):
        \\            return (codec_encode[D # preserve codec bracket comment
        \\            ](value)).n
        \\        case err(code):
        \\            return code
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const result = try project.run("fix", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_REMOVED_SPELLING") != null);
    const actual = try project.read("main.selka");
    defer testing.allocator.free(actual);
    // The codec spellings have no certain repair and survive verbatim, spaced
    // brackets and interior comment included; the file's unrelated certain
    // repairs (`effects()` retirement) still apply in the same run.
    try testing.expect(std.mem.indexOf(u8, actual, "codec_decode[D ](Wire(n=3))") != null);
    try testing.expect(std.mem.indexOf(u8, actual, "codec_encode[D # preserve codec bracket comment\n            ](value)).n") != null);
    try testing.expect(std.mem.indexOf(u8, actual, "effects()") == null);
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
// spec: FIX-DOMAIN-MEMBER-CALLBACK-1
test "wave1 domain CLI passes callbacks to imported domain owned generic members" {
    try migrateProject(&.{
        .{
            .path = "data.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\public domain D: int:
            \\    func make(n: int) -> D effects():
            \\        return wrap[D](n)
            \\    func score(item: D) -> int effects():
            \\        return unwrap(item)
            \\    func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
            \\        return T.score(item)
        },
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import data
            \\func main() -> int:
            \\    const item = data.D.make(1)
            \\    return data.D.evaluate[data.D](item) + data.D.evaluate(item)
        },
    }, &.{
        .{ .path = "main.selka", .data = "data.evaluate[data.D](item, domain_op_T_score=data.score)" },
        .{ .path = "main.selka", .data = "data.evaluate(item, domain_op_T_score=data.score)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-DOMAIN-MEMBER-CALLBACK-1
// spec: FIX-DOMAIN-OWNER-KIND-1
test "wave1 domain CLI leaves ordinary generic and reserved variant constructors alone" {
    try migrateProject(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\import strings
        \\enum Tree[T]:
        \\    leaf(value: T)
        \\enum Unusual:
        \\    some
        \\    none(value: int)
        \\domain D: int:
        \\    func make(n: int) -> D effects():
        \\        return wrap[D](n)
        \\    func leaf[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\        return T.score(item)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func main() -> int:
        \\    _ = strings.digits()
        \\    const tree: Tree[int] = Tree.leaf(value=3)
        \\    _ = tree
        \\    _ = Unusual.some
        \\    _ = Unusual.none(value=1)
        \\    return D.leaf[D](D.make(1))
    }}, &.{
        .{ .path = "main.selka", .data = "Tree.leaf(value=3)" },
        .{ .path = "main.selka", .data = "Unusual.some" },
        .{ .path = "main.selka", .data = "leaf[D](make(1), domain_op_T_score=score)" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 domain CLI does not substitute qualified nominal names matching bound subjects" {
    try migrateProject(&.{
        .{ .path = "types.selka", .data =
        \\public record P:
        \\    value: int
        },
        .{
            .path = "main.selka",
            .data =
            // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
            \\import types
            \\constraint Named[P] = copy + op(project(item: P) -> types.P effects())
            \\domain D: int:
            \\    func make(n: int) -> D effects():
            \\        return wrap[D](n)
            \\    func project(item: D) -> types.P effects():
            \\        return types.P(value=unwrap(item))
            \\func evaluate[T: Named](item: T) -> types.P effects():
            \\    return T.project(item)
            \\func main() -> int:
            \\    return evaluate(D.make(4)).value
        },
    }, &.{
        .{ .path = "main.selka", .data = "domain_op_T_project: func(T) -> types.P" },
        .{ .path = "main.selka", .data = "evaluate(make(4), domain_op_T_project=project).value" },
    });
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-DOMAIN-FORWARDING-1
// spec-case: FIX-DIRECTORY-DOMAIN-PHASE-1
test "wave1 domain CLI preserves conflicting operation ceiling diagnostics and metadata" {
    const text =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\constraint A[P] = copy + op(score(item: P) -> int effects(output))
        \\constraint B[Q] = copy + op(score(item: Q) -> int effects(filesystem))
        \\domain D: int:
        \\    func make(n: int) -> D effects():
        \\        return wrap[D](n)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: A + B](item: T) -> int effects(output, filesystem):
        \\    return T.score(item)
        \\func main() -> int:
        \\    return evaluate(D.make(1))
    ;
    try migrateProject(&.{.{ .path = "main.selka", .data = text }}, &.{
        .{ .path = "main.selka", .data = "named domain_op_T_score: func(T) -> int)" },
        .{ .path = "main.selka", .data = "evaluate(make(1), domain_op_T_score=score)" },
    });
    const clause_free = try withoutEffects(text);
    defer testing.allocator.free(clause_free);
    const signature_conflict = try std.mem.replaceOwned(u8, testing.allocator, clause_free, "op(score(item: Q) -> int)", "op(score(item: Q) -> str)");
    defer testing.allocator.free(signature_conflict);
    try stableDomainBarrier(signature_conflict, "E_GENERIC_REQUIREMENT");
}

// spec-case: DOMAIN-REMOVED-1
// spec-case: FIX-DIRECTORY-DOMAIN-PHASE-1
test "wave1 domain CLI preserves invalid named operation call diagnostics and metadata" {
    const prefix =
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\domain D: int:
        \\    func make(n: int) -> D effects():
        \\        return wrap[D](n)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\    func sum(a: D, b: D) -> int effects():
        \\        return unwrap(a) * 10 + unwrap(b)
    ;
    const tails = [_][]const u8{
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item=item)
        \\func main() -> int:
        \\    return evaluate(D.make(1))
        ,
        // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
        \\func evaluate[T: copy + op(sum(a: T, b: T) -> int effects())](a: T, b: T) -> int effects():
        \\    return T.sum(b=b, a=a)
        \\func main() -> int:
        \\    return evaluate(D.make(1), D.make(2))
        ,
    };
    for (tails) |tail| {
        const text = try std.mem.concat(testing.allocator, u8, &.{ prefix, "\n", tail });
        defer testing.allocator.free(text);
        try effectErasureBarrier(text, "E_CALL_ARGUMENT");
    }
}

// These helpers model effect erasure as a separate, certain phase. Domain
// barriers must remain atomic once the obsolete clauses have been removed.
fn withoutEffects(text: []const u8) ![]const u8 {
    var result = try testing.allocator.dupe(u8, text);
    errdefer testing.allocator.free(result);
    for ([_][]const u8{ " effects()", " effects(output)", " effects(filesystem)", " effects(output, filesystem)" }) |clause| {
        const next = try std.mem.replaceOwned(u8, testing.allocator, result, clause, "");
        testing.allocator.free(result);
        result = next;
    }
    return result;
}

fn stableDomainBarrier(text: []const u8, code: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    for ([_][]const []const u8{ &.{"--check"}, &.{}, &.{} }) |args| {
        const result = try project.run("fix", "main.selka", args);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.status);
        try testing.expect(std.mem.indexOf(u8, result.stderr, code) != null);
        const actual = try project.read("main.selka");
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(text, actual);
    }
}

fn effectErasureBarrier(text: []const u8, code: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = text }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "E_EFFECTS_REMOVED") != null);
    const before = try project.read("main.selka");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(text, before);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(std.mem.indexOf(u8, fixed.stderr, code) != null);
    const clause_free = try withoutEffects(text);
    defer testing.allocator.free(clause_free);
    const actual = try project.read("main.selka");
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(clause_free, actual);
    try stableDomainBarrier(clause_free, code);
}

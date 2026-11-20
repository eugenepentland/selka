//! `selka rename`, driven through the compiler binary as an agent runs it: every use the checker resolves is renamed,
//! text is left alone, the result is checked before anything is written, and each refusal writes nothing.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// One source file of a temporary project.
const File = struct { path: []const u8, data: []const u8 };

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

/// A temporary project directory.
const Project = struct {
    temp: testing.TmpDir,

    fn init(files: []const File) !Project {
        var temp = testing.tmpDir(.{});
        errdefer temp.cleanup();
        for (files) |file| {
            if (std.fs.path.dirname(file.path)) |directory| try temp.dir.createDirPath(testing.io, directory);
            try temp.dir.writeFile(testing.io, .{ .sub_path = file.path, .data = file.data });
        }
        return .{ .temp = temp };
    }

    fn deinit(self: *Project) void {
        self.temp.cleanup();
    }

    /// One file's current bytes, owned by the testing allocator.
    fn read(self: *const Project, relative: []const u8) ![]const u8 {
        return self.temp.dir.readFileAlloc(testing.io, relative, testing.allocator, .limited(1 << 20));
    }

    /// Whether one file still holds exactly `expected`.
    fn holds(self: *const Project, relative: []const u8, expected: []const u8) !bool {
        const now = try self.read(relative);
        defer testing.allocator.free(now);
        return std.mem.eql(u8, now, expected);
    }

    /// Run `selka ARGS...` from the project directory.
    fn run(self: *const Project, args: []const []const u8) !Outcome {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
        defer testing.allocator.free(compiler);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.append(testing.allocator, compiler);
        try argv.appendSlice(testing.allocator, args);
        var environment = try testing.environ.createMap(testing.allocator);
        defer environment.deinit();
        // A watch-built compiler finds its components through this variable (WATCH-LOOP.md).
        if (testing.environ.getPosix("SELKA_COMPONENT_DIR")) |directory| try environment.put("SELKA_COMPONENT_DIR", directory);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir }, .environ_map = &environment });
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .stdout = result.stdout, .stderr = result.stderr };
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

const shapes =
    \\# Shapes.
    \\public record Point:
    \\    x: int
    \\    y: int
    \\
    \\public enum Shape:
    \\    circle(center: Point, radius: int)
    \\    square(corner: Point, side: int)
    \\    empty
    \\
    \\public func area(shape: Shape) -> int:
    \\    match shape:
    \\        case circle(center, radius=r):
    \\            return 3 * r * r + center.x
    \\        case square(corner=p, side=s):
    \\            return s * s + p.y
    \\        case empty:
    \\            return 0
    \\
    \\public func make(x: int, y: int) -> Point:
    \\    return Point(x=x, y=y)
    \\
;

const shapes_main =
    \\import shapes as sh
    \\
    \\func shift(p: sh.Point, by: int) -> sh.Point:
    \\    mut q = sh.make(p.x + by, p.y)
    \\    q.x = q.x + 1
    \\    return q
    \\
    \\func main(out: Stream) -> int:
    \\    const p = sh.make(x=1, y=2)
    \\    const s = sh.Shape.circle(center=shift(p, by=3), radius=2)
    \\    # x marks the spot
    \\    print(out, sh.area(s), "x")
    \\    return 0
    \\
;

const shapes_test =
    \\import shapes
    \\
    \\public func test_area() -> bool:
    \\    return shapes.area(shapes.Shape.square(corner=shapes.make(0, 1), side=2)) == 5
    \\
;

fn shapesProject() !Project {
    return Project.init(&.{
        .{ .path = "shapes.selka", .data = shapes },
        .{ .path = "main.selka", .data = shapes_main },
        .{ .path = "shapes_test.selka", .data = shapes_test },
    });
}

// spec: RENAME-CLI-1
test "RENAME-CLI-1: a field is renamed at its declaration, reads, writes, constructor labels and the program's tests, and text is left" {
    var project = try shapesProject();
    defer project.deinit();
    const renamed = try project.run(&.{ "rename", ".", "shapes::Point.x", "left" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed the field `Point.x` to `left`: 6 edits in 2 files"));
    // The comment and the string literal that hold `x` are counted, not edited.
    try testing.expect(contains(renamed.stdout, "left unchanged: `x` appears as a whole word in 1 string literal and 1 comment"));
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expect(contains(main, "mut q = sh.make(p.left + by, p.y)\n    q.left = q.left + 1"));
    try testing.expect(contains(main, "# x marks the spot\n    print(out, sh.area(s), \"x\")"));
    const library = try project.read("shapes.selka");
    defer testing.allocator.free(library);
    // The constructor's label is the field; its value, the parameter `x`, is not.
    try testing.expect(contains(library, "return Point(left=x, y=y)"));
    try testing.expect(contains(library, "return 3 * r * r + center.left"));
}

// spec: RENAME-CLI-2
test "RENAME-CLI-2: a function, a case, a case's field and a type are renamed through an import alias and back, byte for byte" {
    var project = try shapesProject();
    defer project.deinit();
    try renameAndBack(&project, "shapes::make", "build", "shapes::build", "make");
    try renameAndBack(&project, "shapes::Shape.circle", "disc", "shapes::Shape.disc", "circle");
    try renameAndBack(&project, "shapes::Shape.circle.center", "middle", "shapes::Shape.circle.middle", "center");
    try renameAndBack(&project, "shapes::Shape", "Figure", "shapes::Figure", "Shape");
    try testing.expect(try project.holds("main.selka", shapes_main));
    try testing.expect(try project.holds("shapes.selka", shapes));
    try testing.expect(try project.holds("shapes_test.selka", shapes_test));
}

fn renameAndBack(project: *Project, target: []const u8, new: []const u8, back: []const u8, old: []const u8) !void {
    const forward = try project.run(&.{ "rename", ".", target, new });
    defer forward.deinit();
    try testing.expectEqual(@as(u8, 0), forward.status);
    const returned = try project.run(&.{ "rename", ".", back, old });
    defer returned.deinit();
    try testing.expectEqual(@as(u8, 0), returned.status);
}

// spec: RENAME-CLI-3
test "RENAME-CLI-3: a pattern's shorthand field keeps its local when the field is renamed, and becomes one name again when renamed back" {
    var project = try shapesProject();
    defer project.deinit();
    const forward = try project.run(&.{ "rename", ".", "shapes::Shape.circle.center", "middle" });
    defer forward.deinit();
    try testing.expectEqual(@as(u8, 0), forward.status);
    const library = try project.read("shapes.selka");
    defer testing.allocator.free(library);
    try testing.expect(contains(library, "case circle(middle=center, radius=r):"));
    const back = try project.run(&.{ "rename", ".", "shapes::Shape.circle.middle", "center" });
    defer back.deinit();
    try testing.expectEqual(@as(u8, 0), back.status);
    try testing.expect(try project.holds("shapes.selka", shapes));
}

// spec: RENAME-CLI-4
test "RENAME-CLI-4: a parameter named by position is renamed with the call sites' labels; a local by position too" {
    var project = try shapesProject();
    defer project.deinit();
    const parameter = try project.run(&.{ "rename", ".", "main.selka:3:25", "step" });
    defer parameter.deinit();
    try testing.expectEqual(@as(u8, 0), parameter.status);
    const local = try project.run(&.{ "rename", ".", "main.selka:4:9", "moved" });
    defer local.deinit();
    try testing.expectEqual(@as(u8, 0), local.status);
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expect(contains(main, "func shift(p: sh.Point, step: int) -> sh.Point:\n    mut moved = sh.make(p.x + step, p.y)\n    moved.x = moved.x + 1\n    return moved"));
    try testing.expect(contains(main, "center=shift(p, step=3)"));
}

const keyed =
    \\import json
    \\
    \\record Run:
    \\    main_head: str
    \\
    \\func main_head(text: str) -> str:
    \\    const document = json.loads(text) else Err(_):
    \\        return ""
    \\    match json.get(document, "main_head"):
    \\        case Some(found):
    \\            match json.as_str(found):
    \\                case Some(head):
    \\                    return copy(head)
    \\                case None:
    \\                    return ""
    \\        case None:
    \\            return ""
    \\
    \\func main(out: Stream) -> int:
    \\    const run = Run(main_head=main_head("{\"main_head\": \"abc\"}"))
    \\    print(out, run.main_head)
    \\    return 0
    \\
;

// spec: RENAME-CLI-5
test "RENAME-CLI-5 (F-12): a function and a field named like a JSON key are renamed and the key the program reads is not" {
    var project = try Project.init(&.{.{ .path = "seed.selka", .data = keyed }});
    defer project.deinit();
    const field = try project.run(&.{ "rename", "seed.selka", "seed::Run.main_head", "task_head" });
    defer field.deinit();
    const function = try project.run(&.{ "rename", "seed.selka", "seed::main_head", "read_head" });
    defer function.deinit();
    try testing.expectEqual(@as(u8, 0), field.status);
    try testing.expectEqual(@as(u8, 0), function.status);
    try testing.expect(contains(function.stdout, "appears as a whole word in 2 string literals"));
    const seed = try project.read("seed.selka");
    defer testing.allocator.free(seed);
    try testing.expect(contains(seed, "    task_head: str\n"));
    try testing.expect(contains(seed, "func read_head(text: str) -> str:"));
    try testing.expect(contains(seed, "json.get(document, \"main_head\")"));
    try testing.expect(contains(seed, "Run(task_head=read_head(\"{\\\"main_head\\\": \\\"abc\\\"}\"))"));
    try testing.expect(contains(seed, "print(out, run.task_head)"));
}

/// Run a rename that must be refused, and require exit 1, the reason, and every file unchanged.
fn refused(project: *Project, args: []const []const u8, reason: []const u8) !void {
    const outcome = try project.run(args);
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    const expected = try std.fmt.allocPrint(testing.allocator, "refused ({s})", .{reason});
    defer testing.allocator.free(expected);
    try testing.expect(contains(outcome.stderr, expected));
    try testing.expect(contains(outcome.stderr, "nothing was written"));
    try testing.expect(try project.holds("main.selka", shapes_main));
    try testing.expect(try project.holds("shapes.selka", shapes));
}

// spec: RENAME-CLI-6
test "RENAME-CLI-6: a name that is taken, a reserved word, and a local that would shadow or be shadowed are refused, writing nothing" {
    var project = try shapesProject();
    defer project.deinit();
    // A sibling field, a sibling case, and another module-level name hold it.
    try refused(&project, &.{ "rename", ".", "shapes::Point.x", "y" }, "taken");
    try refused(&project, &.{ "rename", ".", "shapes::Shape.empty", "square" }, "taken");
    try refused(&project, &.{ "rename", ".", "shapes::make", "area" }, "taken");
    try refused(&project, &.{ "rename", ".", "shapes::make", "while" }, "reserved");
    // `q` is visible where `p` is, and the module declares `shift`.
    try refused(&project, &.{ "rename", ".", "main.selka:4:9", "p" }, "shadowing");
    try refused(&project, &.{ "rename", ".", "main.selka:4:9", "shift" }, "shadowing");
}

// spec: RENAME-CLI-7
test "RENAME-CLI-7: a rename whose result checks differently is refused with the diagnostics that differ" {
    var project = try shapesProject();
    defer project.deinit();
    // `Unit` is a builtin type's name: the renamed declaration would be refused (`E_BUILTIN_TYPE_NAME`).
    try refused(&project, &.{ "rename", ".", "shapes::Point", "Unit" }, "verdict");
}

const unchecked_main =
    \\record Counter:
    \\    count: int
    \\
    \\func bump() -> int:
    \\    const c = Counter(count=1)
    \\    return c.count + 1
    \\
    \\func broken() -> int:
    \\    return "not a number"
    \\
    \\func main() -> int:
    \\    return bump()
    \\
;

// spec: RENAME-CLI-8
test "RENAME-CLI-8: a use the checker did not resolve (a body that does not check) refuses the rename, writing nothing" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = unchecked_main }});
    defer project.deinit();
    const outcome = try project.run(&.{ "rename", "main.selka", "main::Counter.count", "total" });
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    try testing.expect(contains(outcome.stderr, "refused (unresolved)"));
    try testing.expect(contains(outcome.stderr, "main.selka:6:14"));
    try testing.expect(contains(outcome.stderr, "a program that loads them does not check"));
    try testing.expect(try project.holds("main.selka", unchecked_main));
}

// spec: RENAME-CLI-9
test "RENAME-CLI-9: --dry-run prints the edits and writes nothing; --json prints one rename-v1 document with byte ranges" {
    var project = try shapesProject();
    defer project.deinit();
    const dry = try project.run(&.{ "rename", "--dry-run", ".", "shapes::area", "surface" });
    defer dry.deinit();
    try testing.expectEqual(@as(u8, 0), dry.status);
    try testing.expect(contains(dry.stdout, "would rename `shapes::area` to `surface`: 3 edits in 3 files"));
    try testing.expect(contains(dry.stdout, "main.selka:12:19: `area` -> `surface`"));
    try testing.expect(try project.holds("shapes.selka", shapes));
    const json = try project.run(&.{ "rename", "--dry-run", "--json", ".", "shapes::area", "surface" });
    defer json.deinit();
    try testing.expectEqual(@as(u8, 0), json.status);
    try testing.expect(contains(json.stdout, "{\"version\":\"rename-v1\",\"status\":\"dry-run\""));
    try testing.expect(contains(json.stdout, "{\"path\":\"shapes.selka\",\"edits\":[{\"bytes\":{\"start\":172,\"end\":176},\"text\":\"surface\"}]}"));
    try testing.expect(try project.holds("main.selka", shapes_main));
    // A refusal is one document too, and a usage error exits 2.
    const taken = try project.run(&.{ "rename", "--json", ".", "shapes::make", "area" });
    defer taken.deinit();
    try testing.expectEqual(@as(u8, 1), taken.status);
    try testing.expect(contains(taken.stdout, "\"status\":\"refused\",\"reason\":\"taken\""));
    const usage = try project.run(&.{ "rename", ".", "make" });
    defer usage.deinit();
    try testing.expectEqual(@as(u8, 2), usage.status);
}

const contracts =
    \\public record Box[T]:
    \\    value: T
    \\    count: int
    \\
    \\@invariant(self.count >= 0, "a counter never counts below zero")
    \\public record Counter:
    \\    count: int
    \\
    \\# Never instantiated: its body has no checked tree, and `box.count` resolves through the parameter's declared type.
    \\public func tally[T](box: Box[T]) -> int:
    \\    return box.count
    \\
    \\@requires(limit > 0)
    \\public func clamp(value: int, limit: int) -> int:
    \\    if value > limit:
    \\        return limit
    \\    return value
    \\
    \\public func first(text: str, other: str) -> str from text:
    \\    _ = other
    \\    return text
    \\
    \\func main() -> int:
    \\    const b = Box[int](value=1, count=2)
    \\    const k = Counter(count=1)
    \\    return clamp(value=b.count, limit=3) + len(first("a", "b")) + k.count
    \\
;

// spec: RENAME-CLI-10
test "RENAME-CLI-10: a parameter is renamed in its contract and `from` clauses; a field read in a generic body no instance reached, and in a record invariant, is renamed" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = contracts }});
    defer project.deinit();
    const limit = try project.run(&.{ "rename", "main.selka", "main.selka:14:31", "cap" });
    defer limit.deinit();
    try testing.expectEqual(@as(u8, 0), limit.status);
    const text = try project.run(&.{ "rename", "main.selka", "main.selka:19:19", "source" });
    defer text.deinit();
    try testing.expectEqual(@as(u8, 0), text.status);
    const count = try project.run(&.{ "rename", "main.selka", "main::Box.count", "tally_of" });
    defer count.deinit();
    try testing.expectEqual(@as(u8, 0), count.status);
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expect(contains(main, "@requires(cap > 0)\npublic func clamp(value: int, cap: int) -> int:\n    if value > cap:\n        return cap"));
    try testing.expect(contains(main, "public func first(source: str, other: str) -> str from source:\n    _ = other\n    return source"));
    try testing.expect(contains(main, "    return box.tally_of\n"));
    try testing.expect(contains(main, "return clamp(value=b.tally_of, cap=3)"));
    try testing.expect(contains(main, "@invariant(self.count >= 0, "));
    const counter = try project.run(&.{ "rename", "main.selka", "main::Counter.count", "total" });
    defer counter.deinit();
    try testing.expectEqual(@as(u8, 0), counter.status);
    const renamed = try project.read("main.selka");
    defer testing.allocator.free(renamed);
    try testing.expect(contains(renamed, "@invariant(self.total >= 0, "));
    try testing.expect(contains(renamed, "const k = Counter(total=1)"));
}

const extern_main =
    \\extern func c_add(host: Host, a: i64, b: i64) -> i64
    \\
    \\func main(host: Host) -> int:
    \\    return c_add(host, 1, 2)
    \\
;

// spec: RENAME-CLI-11
test "RENAME-CLI-11: an extern func is not renamed, since its name is the C function's, and a standard-library declaration is outside the project" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = extern_main }});
    defer project.deinit();
    const c_side = try project.run(&.{ "rename", "main.selka", "main::c_add", "c_plus" });
    defer c_side.deinit();
    try testing.expectEqual(@as(u8, 1), c_side.status);
    try testing.expect(contains(c_side.stderr, "refused (extern)"));
    try testing.expect(try project.holds("main.selka", extern_main));
    var shapes_project = try shapesProject();
    defer shapes_project.deinit();
    // `print` at this position is the prelude's, which no file of the project declares.
    const standard = try shapes_project.run(&.{ "rename", ".", "main.selka:12:5", "show" });
    defer standard.deinit();
    try testing.expect(standard.status != 0);
    try testing.expect(try shapes_project.holds("main.selka", shapes_main));
}

const linked_library =
    \\public enum Value:
    \\    null
    \\    integer(value: i64)
    \\    text(value: str)
    \\
    \\public func size(value: Value) -> int:
    \\    match value:
    \\        case null:
    \\            return 0
    \\        case integer(value=number):
    \\            return int(number)
    \\        case text(value=content):
    \\            return len(content)
    \\
;

const linked_main =
    \\import values
    \\
    \\func main() -> int:
    \\    return values.size(values.Value.integer(value=3)) + values.size(values.Value.text(value="ab"))
    \\
;

// spec: RENAME-CLI-12
test "RENAME-CLI-12: a module imported through a symbolic link is one file, and a case field shared by spelling with another case is renamed alone" {
    var project = try Project.init(&.{
        .{ .path = "lib/values.selka", .data = linked_library },
        .{ .path = "main.selka", .data = linked_main },
    });
    defer project.deinit();
    try project.temp.dir.symLink(testing.io, "lib/values.selka", "values.selka", .{});
    const renamed = try project.run(&.{ "rename", ".", "values::Value.integer.value", "amount" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    const library = try project.read("lib/values.selka");
    defer testing.allocator.free(library);
    try testing.expect(contains(library, "    integer(amount: i64)\n    text(value: str)\n"));
    try testing.expect(contains(library, "case integer(amount=number):"));
    try testing.expect(contains(library, "case text(value=content):"));
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expect(contains(main, "values.Value.integer(amount=3)) + values.size(values.Value.text(value=\"ab\"))"));
}

const facade_units =
    \\public record Distance:
    \\    metres: int
    \\
    \\public func make(metres: int) -> Distance:
    \\    return Distance(metres=metres)
    \\
;

const facade =
    \\import units
    \\export units.Distance
    \\export units.make
    \\
;

const facade_main =
    \\import facade
    \\
    \\func main() -> int:
    \\    const d: facade.Distance = facade.make(4)
    \\    return d.metres
    \\
;

// spec: RENAME-CLI-13
test "RENAME-CLI-13: a declaration named through the facade that re-exports it is renamed at its declaration, the export directive and every use through the facade" {
    var project = try Project.init(&.{
        .{ .path = "units.selka", .data = facade_units },
        .{ .path = "facade.selka", .data = facade },
        .{ .path = "main.selka", .data = facade_main },
    });
    defer project.deinit();
    const renamed = try project.run(&.{ "rename", ".", "facade::make", "build" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed `units::make` to `build`: 3 edits in 3 files"));
    try testing.expect(try project.holds("facade.selka", "import units\nexport units.Distance\nexport units.build\n"));
    const main = try project.read("main.selka");
    defer testing.allocator.free(main);
    try testing.expect(contains(main, "facade.build(4)"));
    const back = try project.run(&.{ "rename", ".", "units::build", "make" });
    defer back.deinit();
    try testing.expectEqual(@as(u8, 0), back.status);
    try testing.expect(try project.holds("main.selka", facade_main));
}

// ---- FR18: renaming a binding `E_SHADOWING` refuses -----------------------------------------------------------------

/// The site's F-53 program: a parameter named like the module the file imports.
const hides_module =
    \\import strings
    \\
    \\func shout(strings: str) -> str:
    \\    return strings + "!"
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, shout("hi"))
    \\    return 0
    \\
;

/// The site's other F-53 program: a local named like a function of its module.
const hides_function =
    \\func you_value(count: int) -> str:
    \\    return str(count)
    \\
    \\
    \\func tile(count: int) -> str:
    \\    mut you_value = "Nothing"
    \\    if count > 0:
    \\        you_value = str(count)
    \\    return you_value
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, tile(2))
    \\    return 0
    \\
;

// spec: RENAME-CLI-14
test "RENAME-CLI-14 (F-10, F-53): the refusal names the command that repairs it, and the command renames the binding so the program checks" {
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = hides_module }, .{ .path = "tile.selka", .data = hides_function } });
    defer project.deinit();
    const refused_module = try project.run(&.{ "check", "main.selka" });
    defer refused_module.deinit();
    try testing.expectEqual(@as(u8, 1), refused_module.status);
    // The first line is lane FR2's; the note adds the command, complete but for the new name.
    try testing.expect(contains(refused_module.stderr, "error[E_SHADOWING]: parameter `strings` would hide the imported module `strings`: a name is bound once where it is visible, so choose another name"));
    try testing.expect(contains(refused_module.stderr, "note: main.selka:3:12: rename the binding with `selka rename main.selka main.selka:3:12 <new-name>`"));
    const renamed = try project.run(&.{ "rename", "main.selka", "main.selka:3:12", "text" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed the parameter `strings` to `text`: 2 edits in 1 file; 1 entry checked as before apart from the refusals it repairs"));
    try testing.expect(contains(renamed.stdout, "removed 1 `E_SHADOWING` refusal of the renamed binding:\n  main.selka:3:12\n"));
    try testing.expect(contains(renamed.stdout, "no other error before or after"));
    try testing.expect(try project.holds("main.selka", "import strings\n\nfunc shout(text: str) -> str:\n    return text + \"!\"\n\n\nfunc main(out: Stream) -> int:\n    print(out, shout(\"hi\"))\n    return 0\n"));
    const module_checks = try project.run(&.{ "check", "main.selka" });
    defer module_checks.deinit();
    try testing.expectEqual(@as(u8, 0), module_checks.status);
    // A file checked alone (no imports) names its own path the same way.
    const refused_function = try project.run(&.{ "check", "tile.selka" });
    defer refused_function.deinit();
    try testing.expect(contains(refused_function.stderr, "rename the binding with `selka rename tile.selka tile.selka:6:9 <new-name>`"));
    const local = try project.run(&.{ "rename", "tile.selka", "tile.selka:6:9", "need" });
    defer local.deinit();
    try testing.expectEqual(@as(u8, 0), local.status);
    try testing.expect(contains(local.stdout, "3 edits in 1 file"));
    const function_checks = try project.run(&.{ "check", "tile.selka" });
    defer function_checks.deinit();
    try testing.expectEqual(@as(u8, 0), function_checks.status);
}

const awkward_util =
    \\import strings
    \\
    \\public func shout(strings: str) -> str:
    \\    return strings + "!"
    \\
    \\
    \\public func pick(items: str[], strings: int) -> str:
    \\    return copy(items[strings])
    \\
;

/// Every shape item 2 of the brief names: the module used before a local of its name, a nested block, a loop variable,
/// a payload binding beside a call of the function it hides, a `from` contract, a function without the clash, a field of
/// the same name, a `fails` function, a parameter labelled at a call in another module.
const awkward_main =
    \\import strings
    \\import util
    \\
    \\func reason(code: int) -> str:
    \\    return "status " + str(code)
    \\
    \\
    \\func before_and_after(x: str) -> str:
    \\    const upper = strings.upper(x)
    \\    mut strings = upper + "?"
    \\    strings = strings + "!"
    \\    return strings
    \\
    \\
    \\func nested(values: int[]) -> int:
    \\    mut total = 0
    \\    if len(values) > 0:
    \\        for reason in values:
    \\            total = total + reason
    \\        total = total + len(f"{total}")
    \\    return total
    \\
    \\
    \\func arms(result: Result[int, str]) -> str:
    \\    match result:
    \\        case Ok(value):
    \\            return reason(value)
    \\        case Err(reason):
    \\            return copy(reason)
    \\
    \\
    \\func first(strings: str[]) -> str from strings:
    \\    return strings[0]
    \\
    \\
    \\func clean(code: int) -> str:
    \\    return reason(code) + strings.upper("x")
    \\
    \\
    \\record Box:
    \\    reason: str
    \\    level: int
    \\
    \\
    \\func fields(own box: Box) -> int:
    \\    mut reason = own box
    \\    reason.level = reason.level + 1
    \\    return reason.level + len(reason.reason)
    \\
    \\
    \\func failing(code: int) -> int fails str:
    \\    if code < 0:
    \\        fail "negative"
    \\    const reason = code + 1
    \\    return reason
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, before_and_after("ab"), nested([1, 2]), arms(Ok(200)), first(["a"]), clean(3))
    \\    print(out, util.shout("x") + util.pick(["p", "q"], strings=1), fields(Box(reason="r", level=1)))
    \\    match failing(2):
    \\        case Ok(got):
    \\            print(out, got)
    \\        case Err(problem):
    \\            print(out, problem)
    \\    return 0
    \\
;

// spec: RENAME-CLI-15
test "RENAME-CLI-15: hiding:NAME renames every binding that hides NAME across the project by resolution, and nothing that names the module or the function" {
    var project = try Project.init(&.{ .{ .path = "main.selka", .data = awkward_main }, .{ .path = "util.selka", .data = awkward_util } });
    defer project.deinit();
    const before = try project.run(&.{ "check", "main.selka" });
    defer before.deinit();
    try testing.expect(contains(before.stderr, "4 bindings of this program hide `strings`; rename them all with `selka rename main.selka hiding:strings <new-name>`"));
    try testing.expect(contains(before.stderr, "4 bindings of this program hide `reason`; rename them all with `selka rename main.selka hiding:reason <new-name>`"));
    const strings_renamed = try project.run(&.{ "rename", "main.selka", "hiding:strings", "text" });
    defer strings_renamed.deinit();
    try testing.expectEqual(@as(u8, 0), strings_renamed.status);
    try testing.expect(contains(strings_renamed.stdout, "renamed the 4 bindings hiding `strings` to `text`: 12 edits in 2 files"));
    try testing.expect(contains(strings_renamed.stdout, "removed 4 `E_SHADOWING` refusals of the renamed bindings:\n  main.selka:10:9\n  main.selka:32:12\n  util.selka:3:19\n  util.selka:7:32\n"));
    const reason_renamed = try project.run(&.{ "rename", "main.selka", "hiding:reason", "why" });
    defer reason_renamed.deinit();
    try testing.expectEqual(@as(u8, 0), reason_renamed.status);
    try testing.expect(contains(reason_renamed.stdout, "renamed the 4 bindings hiding `reason` to `why`: 11 edits in 1 file"));
    const main_now = try project.read("main.selka");
    defer testing.allocator.free(main_now);
    // The module before the local, the function beside the payload, the field, and the clean function keep their names.
    try testing.expect(contains(main_now, "    const upper = strings.upper(x)\n    mut text = upper + \"?\"\n    text = text + \"!\"\n    return text\n"));
    try testing.expect(contains(main_now, "        for why in values:\n            total = total + why\n"));
    try testing.expect(contains(main_now, "            return reason(value)\n        case Err(why):\n            return copy(why)\n"));
    try testing.expect(contains(main_now, "func first(text: str[]) -> str from text:\n    return text[0]\n"));
    try testing.expect(contains(main_now, "    return reason(code) + strings.upper(\"x\")\n"));
    try testing.expect(contains(main_now, "    mut why = own box\n    why.level = why.level + 1\n    return why.level + len(why.reason)\n"));
    try testing.expect(contains(main_now, "    const why = code + 1\n    return why\n"));
    try testing.expect(contains(main_now, "util.pick([\"p\", \"q\"], text=1)"));
    try testing.expect(try project.holds("util.selka", "import strings\n\npublic func shout(text: str) -> str:\n    return text + \"!\"\n\n\npublic func pick(items: str[], text: int) -> str:\n    return copy(items[text])\n"));
    const ran = try project.run(&.{ "run", "main.selka" });
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("AB?! 4 status 200 a status 3X\nx!q 3\n3\n", ran.stdout);
}

/// The site's case: twenty functions that each move a poller into a local `live`, broken by a new module `live`.
fn twentyLocals() ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(testing.allocator);
    try text.appendSlice(testing.allocator, "import live\n\nrecord Poller:\n    items: int[]\n    count: int\n\n\nfunc bump(mut p: Poller, by: int):\n    p.count = p.count + by\n\n\n");
    for (0..20) |step| try text.print(testing.allocator,
        \\# step {d}: the live poller is moved into a local named live
        \\func step{d}(own poller: Poller) -> int:
        \\    mut live = own poller
        \\    bump(mut live, {d})
        \\    return live.count + len(live.items)
        \\
        \\
        \\
    , .{ step, step, step });
    try text.appendSlice(testing.allocator, "func main(out: Stream) -> int:\n    mut total = 0\n");
    for (0..20) |step| try text.print(testing.allocator, "    total = total + step{d}(Poller(items=[{d}], count={d}))\n", .{ step, step, step });
    try text.appendSlice(testing.allocator, "    print(out, f\"live total {total}\", live.script())\n    return 0\n");
    return text.toOwnedSlice(testing.allocator);
}

// spec: RENAME-CLI-16
test "RENAME-CLI-16 (F-10 again): twenty locals a new module hides are renamed by one command, and the word in strings and comments is left" {
    const server = try twentyLocals();
    defer testing.allocator.free(server);
    var project = try Project.init(&.{ .{ .path = "server.selka", .data = server }, .{ .path = "live.selka", .data = "# The pages' live script.\npublic func script() -> str:\n    return \"live\"\n" } });
    defer project.deinit();
    const before = try project.run(&.{ "check", "server.selka" });
    defer before.deinit();
    try testing.expect(contains(before.stderr, "note: server.selka:14:9: 20 bindings of this program hide `live`; rename them all with `selka rename server.selka hiding:live <new-name>`"));
    const renamed = try project.run(&.{ "rename", "server.selka", "hiding:live", "polled" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed the 20 bindings hiding `live` to `polled`: 80 edits in 1 file"));
    try testing.expect(contains(renamed.stdout, "removed 20 `E_SHADOWING` refusals of the renamed bindings:"));
    try testing.expect(contains(renamed.stdout, "left unchanged: `live` appears as a whole word in 1 string literal and 40 comments:"));
    const expected = try std.mem.replaceOwned(u8, testing.allocator, server, "live = own", "polled = own");
    defer testing.allocator.free(expected);
    const bumped = try std.mem.replaceOwned(u8, testing.allocator, expected, "(mut live,", "(mut polled,");
    defer testing.allocator.free(bumped);
    const read = try std.mem.replaceOwned(u8, testing.allocator, bumped, "return live.count + len(live.items)", "return polled.count + len(polled.items)");
    defer testing.allocator.free(read);
    try testing.expect(try project.holds("server.selka", read));
    const ran = try project.run(&.{ "run", "server.selka" });
    defer ran.deinit();
    try testing.expectEqualStrings("live total 400 live\n", ran.stdout);
}

// spec: RENAME-CLI-17
test "RENAME-CLI-17: a repair is refused, writing nothing, when the new name is taken in one function, when another diagnostic would go or come, and when a use cannot be attributed" {
    const taken =
        \\import live
        \\
        \\func one() -> int:
        \\    const live = 1
        \\    return live
        \\
        \\
        \\func two() -> int:
        \\    const live = 2
        \\    const polled = 3
        \\    return live + polled
        \\
        \\
        \\func main() -> int:
        \\    return one() + two() + len(live.script())
        \\
    ;
    // Renaming the parameter makes the call's label `names=` right: an error other than the refusal would go.
    const label =
        \\import strings
        \\
        \\func count(strings: str[]) -> int:
        \\    return len(strings)
        \\
        \\
        \\func main() -> int:
        \\    return count(names=["a"])
        \\
    ;
    // The copy still holds a type error, so the field `reason` read through the local has no type to resolve by.
    const unattributed =
        \\record Box:
        \\    reason: str
        \\
        \\
        \\func reason() -> int:
        \\    return 1
        \\
        \\
        \\func size(own box: Box) -> int:
        \\    mut reason = own box
        \\    return len(reason.reason)
        \\
        \\
        \\func broken() -> int:
        \\    return "not a number"
        \\
        \\
        \\func main() -> int:
        \\    return size(Box(reason="r")) + reason()
        \\
    ;
    var project = try Project.init(&.{
        .{ .path = "taken.selka", .data = taken },
        .{ .path = "live.selka", .data = "public func script() -> str:\n    return \"x\"\n" },
        .{ .path = "label.selka", .data = label },
        .{ .path = "unattributed.selka", .data = unattributed },
        .{ .path = "payload.selka", .data = "func reason() -> str:\n    return \"r\"\n\n\nfunc describe(result: Result[int, str]) -> str:\n    match result:\n        case Ok(_):\n            return reason()\n        case Err(reason):\n            return reason\n\n\nfunc main() -> int:\n    return len(describe(Ok(1)))\n" },
    });
    defer project.deinit();
    const in_use = try project.run(&.{ "rename", "taken.selka", "hiding:live", "polled" });
    defer in_use.deinit();
    try testing.expectEqual(@as(u8, 1), in_use.status);
    try testing.expect(contains(in_use.stderr, "refused (shadowing): `polled` is already bound where the 2 bindings hiding `live` is visible"));
    try testing.expect(contains(in_use.stderr, "taken.selka:10:11"));
    try testing.expect(try project.holds("taken.selka", taken));
    const gone = try project.run(&.{ "rename", "label.selka", "label.selka:3:12", "names" });
    defer gone.deinit();
    try testing.expectEqual(@as(u8, 1), gone.status);
    try testing.expect(contains(gone.stderr, "refused (verdict): the renamed project does not check as before"));
    try testing.expect(contains(gone.stderr, "[gone: error"));
    try testing.expect(try project.holds("label.selka", label));
    // The payload's refusal hid an ownership error of the body; the repair would print it, so it stays refused.
    const revealed = try project.run(&.{ "rename", "payload.selka", "payload.selka:9:18", "why" });
    defer revealed.deinit();
    try testing.expectEqual(@as(u8, 1), revealed.status);
    try testing.expect(contains(revealed.stderr, "refused (verdict): the project does not check as before apart from the refusals the rename repairs"));
    try testing.expect(contains(revealed.stderr, "[new:  error E_BORROW_MIXED]"));
    const unresolved = try project.run(&.{ "rename", "unattributed.selka", "unattributed.selka:10:9", "held" });
    defer unresolved.deinit();
    try testing.expectEqual(@as(u8, 1), unresolved.status);
    try testing.expect(contains(unresolved.stderr, "refused (unresolved)"));
    try testing.expect(contains(unresolved.stderr, "unattributed.selka:11:23"));
    try testing.expect(try project.holds("unattributed.selka", unattributed));
}

// spec: RENAME-CLI-17
test "RENAME-CLI-17: a repair that would show an error the clash hid says what happened, writes nothing, and works once the error is fixed (FR19)" {
    const hidden = "func reason() -> str:\n    return \"r\"\n\n\nfunc describe(result: Result[int, str]) -> str:\n    match result:\n        case Ok(_):\n            return reason()\n        case Err(reason):\n            return reason\n\n\nfunc main() -> int:\n    return len(describe(Ok(1)))\n";
    var project = try Project.init(&.{.{ .path = "payload.selka", .data = hidden }});
    defer project.deinit();
    const revealed = try project.run(&.{ "rename", "payload.selka", "payload.selka:9:18", "why" });
    defer revealed.deinit();
    try testing.expectEqual(@as(u8, 1), revealed.status);
    try testing.expect(contains(revealed.stderr, "refused (verdict): the project does not check as before apart from the refusals the rename repairs"));
    try testing.expect(contains(revealed.stderr, "[new:  error E_BORROW_MIXED]"));
    // The rename is right: the clash had stopped the check of the function, so its own error is named with its message and place.
    try testing.expect(contains(revealed.stderr, "The rename itself is right: the name clash had stopped the check of the function it is in, so the program had an error that no check could show: error[E_BORROW_MIXED]: "));
    try testing.expect(contains(revealed.stderr, "write copy(...) around each borrowed return. Its place is printed below. Fix it, then run the same command again; nothing was written"));
    try testing.expect(contains(revealed.stderr, "payload.selka:10:20"));
    try testing.expect(try project.holds("payload.selka", hidden));
    // Fixed as the message says, the same command writes the rename.
    const fixed = try std.mem.replaceOwned(u8, testing.allocator, hidden, "            return reason\n\n", "            return copy(reason)\n\n");
    defer testing.allocator.free(fixed);
    var again = try Project.init(&.{.{ .path = "payload.selka", .data = fixed }});
    defer again.deinit();
    const renamed = try again.run(&.{ "rename", "payload.selka", "payload.selka:9:18", "why" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed the local `reason` to `why`"));
}

// spec: RENAME-CLI-18
test "RENAME-CLI-18: a repair's --dry-run writes nothing and --json says which refusals it removed" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = hides_module }});
    defer project.deinit();
    const dry = try project.run(&.{ "rename", "--dry-run", "main.selka", "hiding:strings", "text" });
    defer dry.deinit();
    try testing.expectEqual(@as(u8, 0), dry.status);
    try testing.expect(contains(dry.stdout, "would rename the 1 binding hiding `strings` to `text`: 2 edits in 1 file"));
    try testing.expect(contains(dry.stdout, "  main.selka:3:12: `strings` -> `text`\n  main.selka:4:12: `strings` -> `text`\n"));
    try testing.expect(try project.holds("main.selka", hides_module));
    const json = try project.run(&.{ "rename", "--json", "--dry-run", "main.selka", "main.selka:4:12", "text" });
    defer json.deinit();
    try testing.expectEqual(@as(u8, 0), json.status);
    try testing.expect(contains(json.stdout, "\"status\":\"dry-run\""));
    try testing.expect(contains(json.stdout, "\"repaired\":{\"removed\":[\"main.selka:3:12\"],\"unchanged_errors\":0,\"warnings_now_printed\":1}"));
    try testing.expect(try project.holds("main.selka", hides_module));
    const absent = try project.run(&.{ "rename", "main.selka", "hiding:nothing", "text" });
    defer absent.deinit();
    try testing.expectEqual(@as(u8, 1), absent.status);
    try testing.expect(contains(absent.stderr, "refused (missing): no binding of the project hides `nothing`"));
}

// spec: RENAME-CLI-19
test "RENAME-CLI-19: a type the module names through the alias stays the module's; a use of the module where the binding is in force reads as the binding, so that repair is refused" {
    const store =
        \\public record Db:
        \\    rows: int
        \\
        \\public func open(rows: int) -> Db:
        \\    return Db(rows=rows)
        \\
    ;
    const typed =
        \\import store
        \\
        \\func count(store: store.Db) -> int:
        \\    return store.rows
        \\
        \\
        \\func main() -> int:
        \\    return count(store.open(2))
        \\
    ;
    const in_force =
        \\import store
        \\
        \\func count(store: int) -> int:
        \\    return store + store.open(1).rows
        \\
        \\
        \\func main() -> int:
        \\    return count(2)
        \\
    ;
    var project = try Project.init(&.{ .{ .path = "store.selka", .data = store }, .{ .path = "typed.selka", .data = typed }, .{ .path = "in_force.selka", .data = in_force } });
    defer project.deinit();
    const renamed = try project.run(&.{ "rename", "typed.selka", "typed.selka:3:12", "db" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(try project.holds("typed.selka", "import store\n\nfunc count(db: store.Db) -> int:\n    return db.rows\n\n\nfunc main() -> int:\n    return count(store.open(2))\n"));
    const ambiguous = try project.run(&.{ "rename", "in_force.selka", "in_force.selka:3:12", "n" });
    defer ambiguous.deinit();
    try testing.expectEqual(@as(u8, 1), ambiguous.status);
    try testing.expect(contains(ambiguous.stderr, "refused (verdict)"));
    try testing.expect(try project.holds("in_force.selka", in_force));
}

// ---- FR30: renaming the name a binding hides ------------------------------------------------------------------------

/// The site's F-79 program: a local named like a function, and a warning the refused check never reached.
const hidden_function =
    \\record Pair:
    \\    name: str
    \\    count: int
    \\
    \\
    \\func label(count: int) -> str:
    \\    return "used " + str(count)
    \\
    \\
    \\func pair(name: str, other: Pair) -> Pair:
    \\    return Pair(name=copy(name), count=other.count)
    \\
    \\
    \\func rows() -> Pair[]:
    \\    mut all: Pair[] = []
    \\    const one = Pair(name="a", count=1)
    \\    append(mut all, pair("b", copy(one)))
    \\    return all
    \\
    \\
    \\func main(out: Stream):
    \\    const label = label(3)
    \\    print(out, label)
    \\    for row in rows():
    \\        print(out, row.name)
    \\
;

// spec: RENAME-CLI-20
test "RENAME-CLI-20 (F-79): renaming the function a local hides is accepted as renaming the local is, and the warning the refusal hid is counted" {
    var project = try Project.init(&.{
        .{ .path = "shadowed.selka", .data = hidden_function },
        .{ .path = "other.selka", .data = hidden_function },
        .{ .path = "payload.selka", .data = "func reason() -> str:\n    return \"r\"\n\n\nfunc describe(result: Result[int, str]) -> str:\n    match result:\n        case Ok(_):\n            return reason()\n        case Err(reason):\n            return reason\n\n\nfunc main() -> int:\n    return len(describe(Ok(1)))\n" },
    });
    defer project.deinit();
    const unchecked = try project.run(&.{ "check", "shadowed.selka" });
    defer unchecked.deinit();
    try testing.expectEqual(@as(u8, 1), unchecked.status);
    try testing.expect(contains(unchecked.stderr, "error[E_SHADOWING]: binding `label` would hide the function `label`"));
    // The rename of the binding is the repair FR18 built: its report, for the comparison below.
    const binding = try project.run(&.{ "rename", "--dry-run", "other.selka", "other.selka:22:11", "text" });
    defer binding.deinit();
    try testing.expectEqual(@as(u8, 0), binding.status);
    try testing.expect(contains(binding.stdout, "removed 1 `E_SHADOWING` refusal of the renamed binding:\n  other.selka:22:11\nno other error before or after\n1 warning the refused check did not print is printed now\n"));
    const renamed = try project.run(&.{ "rename", "shadowed.selka", "shadowed::label", "label_of" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed `shadowed::label` to `label_of`: 2 edits in 1 file; 1 entry checked as before apart from the refusals it repairs\n"));
    try testing.expect(contains(renamed.stdout, "removed 1 `E_SHADOWING` refusal of a binding that hid the renamed name:\n  shadowed.selka:22:11\nno other error before or after\n1 warning the refused check did not print is printed now\n"));
    const text = try std.mem.replaceOwned(u8, testing.allocator, hidden_function, "func label(", "func label_of(");
    defer testing.allocator.free(text);
    const expected = try std.mem.replaceOwned(u8, testing.allocator, text, "const label = label(3)", "const label = label_of(3)");
    defer testing.allocator.free(expected);
    try testing.expect(try project.holds("shadowed.selka", expected));
    const checked = try project.run(&.{ "check", "shadowed.selka" });
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expect(contains(checked.stderr, "warning[W_NEEDLESS_COPY]"));
    // A neighbour: the refusal had hidden an ownership error of the function, which the rename would show, so it is refused.
    const revealed = try project.run(&.{ "rename", "payload.selka", "payload::reason", "cause" });
    defer revealed.deinit();
    try testing.expectEqual(@as(u8, 1), revealed.status);
    try testing.expect(contains(revealed.stderr, "refused (verdict): the project does not check as before apart from the refusals the rename repairs"));
    try testing.expect(contains(revealed.stderr, "[new:  error E_BORROW_MIXED]"));
    try testing.expect(contains(revealed.stderr, "nothing was written"));
    try testing.expect(try project.holds("payload.selka", "func reason() -> str:\n    return \"r\"\n\n\nfunc describe(result: Result[int, str]) -> str:\n    match result:\n        case Ok(_):\n            return reason()\n        case Err(reason):\n            return reason\n\n\nfunc main() -> int:\n    return len(describe(Ok(1)))\n"));
}

// ---- FR30: a parameter called like a modifier ------------------------------------------------------------------------

/// `named` is a modifier and also a name (FR29): the first `named` of each parameter is the modifier, the second the name.
const named_parameter =
    \\func labelled(named named: int, named total: int) -> int:
    \\    return named * 10 + total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, str(labelled(named=1, total=2)))
    \\    return 0
    \\
;

/// `mut` and `own` are markers too: a parameter called `mut` beside `mut total`, a `mut` binding and a `mut` argument, and a
/// parameter called `own` beside `own tail`.
const marker_parameters =
    \\func add(mut: int, mut total: int) -> int:
    \\    total += mut
    \\    return total
    \\
    \\
    \\func keep(own: int[], own tail: int[]) -> int:
    \\    return len(own) + len(tail)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut sum = 1
    \\    const rest = [3]
    \\    print(out, str(add(2, mut sum) + keep([1, 2], own rest)))
    \\    return 0
    \\
;

// spec: RENAME-CLI-21
test "RENAME-CLI-21 (FR29): a parameter called named, mut or own is renamed, and the marker beside it is no use of it" {
    var project = try Project.init(&.{ .{ .path = "labelled.selka", .data = named_parameter }, .{ .path = "markers.selka", .data = marker_parameters } });
    defer project.deinit();
    const renamed = try project.run(&.{ "rename", "labelled.selka", "labelled.selka:1:21", "count" });
    defer renamed.deinit();
    try testing.expectEqual(@as(u8, 0), renamed.status);
    try testing.expect(contains(renamed.stdout, "renamed the parameter `named` to `count`: 3 edits in 1 file; 1 entry checked as before\n"));
    try testing.expect(try project.holds("labelled.selka", "func labelled(named count: int, named total: int) -> int:\n    return count * 10 + total\n\n\nfunc main(out: Stream) -> int:\n    print(out, str(labelled(count=1, total=2)))\n    return 0\n"));
    const ran = try project.run(&.{ "run", "labelled.selka" });
    defer ran.deinit();
    try testing.expectEqualStrings("12\n", ran.stdout);
    const back = try project.run(&.{ "rename", "labelled.selka", "labelled.selka:1:21", "named" });
    defer back.deinit();
    try testing.expectEqual(@as(u8, 0), back.status);
    try testing.expect(try project.holds("labelled.selka", named_parameter));
    const mut = try project.run(&.{ "rename", "markers.selka", "markers.selka:1:10", "delta" });
    defer mut.deinit();
    try testing.expectEqual(@as(u8, 0), mut.status);
    try testing.expect(contains(mut.stdout, "renamed the parameter `mut` to `delta`: 2 edits in 1 file; 1 entry checked as before\n"));
    const own = try project.run(&.{ "rename", "markers.selka", "markers.selka:6:11", "head" });
    defer own.deinit();
    try testing.expectEqual(@as(u8, 0), own.status);
    try testing.expect(contains(own.stdout, "renamed the parameter `own` to `head`: 2 edits in 1 file; 1 entry checked as before\n"));
    const markers = try project.read("markers.selka");
    defer testing.allocator.free(markers);
    try testing.expect(contains(markers, "func add(delta: int, mut total: int) -> int:\n    total += delta\n"));
    try testing.expect(contains(markers, "func keep(head: int[], own tail: int[]) -> int:\n    return len(head) + len(tail)\n"));
    try testing.expect(contains(markers, "    mut sum = 1\n    const rest = [3]\n    print(out, str(add(2, mut sum) + keep([1, 2], own rest)))\n"));
    const ran_markers = try project.run(&.{ "run", "markers.selka" });
    defer ran_markers.deinit();
    try testing.expectEqualStrings("6\n", ran_markers.stdout);
    // A neighbour: the new name is a sibling parameter's, which is refused as before, and nothing is written.
    const taken = try project.run(&.{ "rename", "labelled.selka", "labelled.selka:1:21", "total" });
    defer taken.deinit();
    try testing.expectEqual(@as(u8, 1), taken.status);
    try testing.expect(contains(taken.stderr, "refused (shadowing): `total` is already bound where the parameter `named` is visible"));
    try testing.expect(try project.holds("labelled.selka", named_parameter));
}

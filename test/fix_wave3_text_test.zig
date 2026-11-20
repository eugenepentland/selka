//! Wave 3, phase 1: every scalar reading of a `str` is refused with its certain
//! repair, and `selka fix` moves a program across with no change in behaviour.
const std = @import("std");
const testing = std.testing;

// spec-case: TEXT-SCALARS-2
test "wave3 text iteration migrates to the chars loop source" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut count = 0
        \\    for character in "abc":
        \\        count += strings.char_count(character)
        \\    return count
        \\
    ,
        \\func main() -> int:
        \\    mut count = 0
        \\    for character in strings.chars("abc"):
        \\        count += strings.char_count(character)
        \\    return count
        \\
    );
}

// spec-case: TEXT-SCALARS-2
// spec-case: STEPPED-SLICE-1
test "wave3 stepped slices migrate to the stride helpers" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const text = "héllo"
        \\    const every_other = text[0:5:2]
        \\    const values = [10, 20, 30, 40, 50]
        \\    const middle = values[1:4:2]
        \\    return len(every_other) + len(middle)
        \\
    ,
        \\func main() -> int:
        \\    const text = "héllo"
        \\    const every_other = strings.char_stride(text, 0, 5, 2)
        \\    const values = [10, 20, 30, 40, 50]
        \\    const middle = lists.stride(values, 1, 4, 2)
        \\    return len(every_other) + len(middle)
        \\
    );
}

// spec-case: TEXT-SCALARS-2
// spec-case: STEPPED-SLICE-1
test "wave3 stepped slices carry the certain repair without an import" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    return len("abcde"[0:5:2])
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    try testing.expect(!contains(migrated, "import strings"));
    try testing.expect(contains(migrated, "strings.char_stride(\"abcde\", 0, 5, 2)"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec: STEPPED-SLICE-1
// spec-case: STEPPED-SLICE-1
test "wave3 stepped slice refusal points at the step it removed" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const values = [1, 2, 3, 4]
        \\    return len(values[0:4:2])
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "\"code\":\"E_STEPPED_SLICE_REMOVED\""));
    // The diagnostic is on the step (`2`), while its repair replaces the slice.
    try testing.expect(contains(checked.stderr, "\"start\":{\"line\":3,\"column\":27}"));
    try testing.expect(contains(checked.stderr, "lists.stride(values, 0, 4, 2)"));
}

/// The FIX-MIGRATION-1 protocol: the preview rewrites nothing, the fix applies
/// every edit, the result is exactly the expected program, it checks, and a
/// second preview finds nothing left to repair.
fn migration(original: []const u8, expected: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("fix stdout: {s}\nfix stderr: {s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    const borrow_repair = contains(fixed.stdout, "E_SLICE_ESCAPES") or
        contains(fixed.stdout, "E_BORROW_UNDECLARED") or
        contains(fixed.stdout, "E_BORROW_VIEWS_REMOVED");
    try testing.expect(
        contains(fixed.stdout, "E_TEXT_ITERATION") or
            contains(fixed.stdout, "E_STEPPED_SLICE_REMOVED") or
            borrow_repair,
    );
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    try testing.expectEqualStrings(expected, migrated);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 slice escapes migrate to the explicit copy the language requires" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\record Held:
        \\    piece: str
        \\func keep(text: str) -> int:
        \\    mut held = Held(piece=copy(text))
        \\    held.piece = text[0:2]
        \\    const pieces = [text[2:4]]
        \\    return len(held.piece) + len(pieces)
        \\
    ,
        \\record Held:
        \\    piece: str
        \\func keep(text: str) -> int:
        \\    mut held = Held(piece=copy(text))
        \\    held.piece = copy(text[0:2])
        \\    const pieces = [copy(text[2:4])]
        \\    return len(held.piece) + len(pieces)
        \\
    );
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 returned slices migrate to an explicit borrowing declaration" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func pick(first: str, second: str) -> str:
        \\    return second[0:1]
        \\func main() -> int:
        \\    return len(pick("ab", "cd"))
        \\
    ,
        \\func pick(first: str, second: str) -> str from second:
        \\    return second[0:1]
        \\func main() -> int:
        \\    return len(pick("ab", "cd"))
        \\
    );
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 invalidated slice views migrate to the copy the language requires" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func measure(text: str) -> int:
        \\    mut own = copy(text)
        \\    const piece = own[0:3]
        \\    own = own + "!"
        \\    return len(piece)
        \\func main() -> int:
        \\    return measure("aé中b")
        \\
    ,
        \\func measure(text: str) -> int:
        \\    mut own = copy(text)
        \\    const piece = copy(own[0:3])
        \\    own = own + "!"
        \\    return len(piece)
        \\func main() -> int:
        \\    return measure("aé中b")
        \\
    );
}

// spec: BORROW-VIEWS-REMOVED-1
// spec-case: BORROW-VIEWS-REMOVED-1
test "wave3 borrow calls and their view types migrate to slices" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func head(source: TextView, first: int) -> str:
        \\    return copy(source.borrow(first, first + 3))
        \\func main() -> int:
        \\    const text = "aé中b"
        \\    const piece = text.borrow(0, 3)
        \\    return len(piece) + len(head("abcdef", 1))
        \\
    ,
        \\func head(source: str, first: int) -> str:
        \\    return copy(source[first:first + 3])
        \\func main() -> int:
        \\    const text = "aé中b"
        \\    const piece = text[0:3]
        \\    return len(piece) + len(head("abcdef", 1))
        \\
    );
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 stored byte slices migrate to the explicit copy the language requires" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\record Held:
        \\    body: bytes
        \\func keep(data: bytes) -> int:
        \\    mut held = Held(body=copy(data))
        \\    held.body = data[1:3]
        \\    mut digests: bytes[] = []
        \\    digests.append(data[0:2])
        \\    _ = digests
        \\    return len(held.body)
        \\func main() -> int:
        \\    return keep(b"abcd")
        \\
    ,
        \\record Held:
        \\    body: bytes
        \\func keep(data: bytes) -> int:
        \\    mut held = Held(body=copy(data))
        \\    held.body = copy(data[1:3])
        \\    mut digests: bytes[] = []
        \\    append(mut digests, copy(data[0:2]))
        \\    _ = digests
        \\    return len(held.body)
        \\func main() -> int:
        \\    return keep(b"abcd")
        \\
    );
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

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
